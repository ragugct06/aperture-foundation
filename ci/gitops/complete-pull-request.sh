#!/usr/bin/env bash
# Finish a GitOps deployment after update-environment.sh has pushed its branch.
#
# Usage:
#   bash ci/gitops/complete-pull-request.sh WORKSPACE REPOSITORY SOURCE_BRANCH \
#     DESTINATION_BRANCH EXPECTED_COMMIT PR_TITLE
# EXPECTED_COMMIT is the full GitOps commit hash, not the application image commit.
# Example argument values: anovorx, aperture-gitops, deploy/dev/service/<commit>,
# main, <full GitOps commit hash>, and "deploy(service): dev dev".
#
# Credentials (supplied as CI variables):
#   GITOPS_ACCESS_TOKEN                   repository token for PR lookup/creation
#   GITOPS_APPROVER_EMAIL                 approver's Atlassian account email
#   GITOPS_APPROVER_TOKEN                 approver's API token for approval/merge
# Flow: find/create PR -> verify source -> approve -> wait for checks -> merge
#       -> poll any asynchronous task -> confirm the PR state is MERGED.
# Exit 0 means a matching PR was observed as merged; any failure exits nonzero.
# The caller can rerun after resolving a failure; an existing open PR is reused.
# No cluster health or rollout checks are performed here.

# Fail on command errors, unset variables, and failures inside shell pipelines.
set -euo pipefail

# 1. Read the caller's PR identity and required credentials.
WORKSPACE="${1:?workspace is required}"
REPOSITORY="${2:?repository is required}"
SOURCE_BRANCH="${3:?source branch is required}"
DESTINATION_BRANCH="${4:?destination branch is required}"
EXPECTED_COMMIT="${5:?deployment commit is required}"
PR_TITLE="${6:?PR title is required}"
: "${GITOPS_ACCESS_TOKEN:?GITOPS_ACCESS_TOKEN is required}"
: "${GITOPS_APPROVER_EMAIL:?GITOPS_APPROVER_EMAIL is required}"
: "${GITOPS_APPROVER_TOKEN:?GITOPS_APPROVER_TOKEN is required}"

# Optional polling settings, in seconds. The deadline starts after approval;
# an in-flight HTTP request or sleep can finish after that deadline.
TIMEOUT="${GITOPS_MERGE_TIMEOUT_SECONDS:-600}"
INTERVAL="${GITOPS_POLL_INTERVAL_SECONDS:-10}"
if [[ ! "${TIMEOUT}" =~ ^[1-9][0-9]*$ || ! "${INTERVAL}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: GitOps timeout and poll interval must be positive integer seconds."
  exit 1
fi

# Each invocation gets its own response file so parallel jobs cannot overwrite it.
# request() replaces this file on every call; fail() prints the latest response.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
RESPONSE="${WORK_DIR}/response.json"
API="https://api.bitbucket.org/2.0/repositories/${WORKSPACE}/${REPOSITORY}/pullrequests"

# Report the operation and Bitbucket's response, then stop the deployment.
fail() {
  echo "ERROR: $*" >&2
  if [[ -s "${RESPONSE}" ]]; then cat "${RESPONSE}" >&2; fi
  exit 1
}

# Only read requests are automatically retried. Mutations are reconciled by
# looking up the PR on the next run, avoiding blind duplicate POST requests.
# Usage: request creator|approver GET|POST URL [additional curl arguments...]
# Outputs: HTTP_CODE (status) and RESPONSE (body file); HTTP errors are checked by
# each caller because expected statuses differ for creation, approval, and merge.
request() {
  local identity="$1" method="$2" url="$3"
  # Remove the three named arguments; "$@" now contains optional curl arguments.
  shift 3
  local -a auth retry
  retry=(--retry 0)
  if [[ "${identity}" == "creator" ]]; then
    auth=(--header "Authorization: Bearer ${GITOPS_ACCESS_TOKEN}")
  else
    auth=(--user "${GITOPS_APPROVER_EMAIL}:${GITOPS_APPROVER_TOKEN}")
  fi
  if [[ "${method}" == "GET" ]]; then
    retry=(--retry 3 --retry-delay 2 --retry-max-time 60)
  fi
  HTTP_CODE="$(curl --silent --show-error --connect-timeout 10 --max-time 30 \
    "${retry[@]}" "${auth[@]}" --request "${method}" \
    --header 'Accept: application/json' --header 'Content-Type: application/json' \
    --output "${RESPONSE}" --write-out '%{http_code}' "$@" "${url}")" \
    || fail "Bitbucket request failed; rerun to reconcile the PR."
}

# Set PR_ID to the one matching open PR, or an empty string when none exists.
# Match the repository too: a fork can contain a branch with the same name.
find_pr() {
  local query
  # jq quotes filter values; curl URL-encodes the completed filter separately.
  query="$(jq -nr --arg source "${SOURCE_BRANCH}" --arg dest "${DESTINATION_BRANCH}" \
    --arg repo "${WORKSPACE}/${REPOSITORY}" \
    '"state = \"OPEN\" AND source.branch.name = " + ($source|tojson) +
     " AND destination.branch.name = " + ($dest|tojson) +
     " AND source.repository.full_name = " + ($repo|tojson)')"
  # Two results are enough to detect ambiguity; never choose an arbitrary PR.
  request creator GET "${API}" --get --data-urlencode "q=${query}" --data-urlencode 'pagelen=2'
  [[ "${HTTP_CODE}" == "200" ]] || fail "Cannot find existing PR (HTTP ${HTTP_CODE})."
  jq -e '.values | type == "array"' "${RESPONSE}" >/dev/null || fail "Invalid PR list."
  [[ "$(jq '.values | length' "${RESPONSE}")" -le 1 ]] || fail "Multiple matching open PRs."
  PR_ID="$(jq -r '.values[0].id // empty' "${RESPONSE}")"
}

# 2. Resume an existing PR, or create one if the lookup found nothing.
find_pr
if [[ -z "${PR_ID}" ]]; then
  # Build JSON with jq so quotes or other special characters in titles are safe.
  PAYLOAD="$(jq -n --arg title "${PR_TITLE}" --arg source "${SOURCE_BRANCH}" \
    --arg dest "${DESTINATION_BRANCH}" \
    '{title: $title, source: {branch: {name: $source}},
      destination: {branch: {name: $dest}}, close_source_branch: true}')"
  request creator POST "${API}" --data "${PAYLOAD}"
  case "${HTTP_CODE}" in
    # 201 = created. A 400/409 is recoverable only if a matching PR now exists.
    201) PR_ID="$(jq -r '.id // empty' "${RESPONSE}")" ;;
    400|409)
      # Another run may have created the same PR since the lookup.
      cat "${RESPONSE}" >&2
      find_pr
      [[ -n "${PR_ID}" ]] || fail "PR creation failed and no existing PR was found."
      ;;
    *) fail "Cannot create PR (HTTP ${HTTP_CODE})." ;;
  esac
else
  echo "Resuming existing GitOps PR ${PR_ID}."
fi
[[ "${PR_ID}" =~ ^[1-9][0-9]*$ ]] || fail "Invalid PR ID."
PR_API="${API}/${PR_ID}"
echo "GitOps PR: https://bitbucket.org/${WORKSPACE}/${REPOSITORY}/pull-requests/${PR_ID}"

# Read the current PR and set PR_STATE. Reject an unexpected commit/branch so
# this run does not knowingly approve a different change pushed by another job.
# These are point-in-time checks, not a lock on the remote branch.
read_pr() {
  request approver GET "${PR_API}"
  [[ "${HTTP_CODE}" == "200" ]] || fail "Cannot read PR (HTTP ${HTTP_CODE})."
  jq -e --arg commit "${EXPECTED_COMMIT}" --arg source "${SOURCE_BRANCH}" \
    --arg dest "${DESTINATION_BRANCH}" \
    '.source.commit.hash == $commit and .source.branch.name == $source and
     .destination.branch.name == $dest' "${RESPONSE}" >/dev/null \
    || fail "PR source or destination changed; refusing to approve/merge."
  PR_STATE="$(jq -r '.state' "${RESPONSE}")"
  case "${PR_STATE}" in
    OPEN|MERGED) ;;
    *) fail "PR is ${PR_STATE}; cannot merge." ;;
  esac
}

# 3. Approve the expected change with the separate approver account.
# A different actor may already have merged the PR after our initial lookup.
read_pr
if [[ "${PR_STATE}" == "MERGED" ]]; then
  echo "GitOps PR ${PR_ID} is already merged."
  exit 0
fi
request approver POST "${PR_API}/approve"
[[ "${HTTP_CODE}" == "200" ]] || fail "Cannot approve PR (HTTP ${HTTP_CODE})."
jq -e '.approved == true' "${RESPONSE}" >/dev/null || fail "Approval was not recorded."

# 4. Wait for eligibility and request a merge, then verify its completion.
# SECONDS is Bash's elapsed-time counter, used to bound this polling loop.
# TASK_ID: asynchronous merge task to poll, if Bitbucket returned HTTP 202.
# MERGE_ACCEPTED: once true, poll for completion instead of sending another POST.
DEADLINE=$((SECONDS + TIMEOUT))
TASK_ID=""
MERGE_ACCEPTED=false
while (( SECONDS < DEADLINE )); do
  # Re-read on every iteration. A successful POST/task alone is not our final
  # success signal: require the PR itself to report MERGED for this source.
  read_pr
  if [[ "${PR_STATE}" == "MERGED" ]]; then
    echo "GitOps PR ${PR_ID} approved and merged successfully."
    exit 0
  fi

  if [[ -n "${TASK_ID}" ]]; then
    # PENDING keeps polling. SUCCESS clears the task ID, but MERGE_ACCEPTED stays
    # true so the next iteration only waits for the PR's final state.
    request approver GET "${PR_API}/merge/task-status/${TASK_ID}"
    [[ "${HTTP_CODE}" == "200" ]] || fail "Merge task failed (HTTP ${HTTP_CODE})."
    case "$(jq -r '.task_status' "${RESPONSE}")" in
      PENDING) ;;
      SUCCESS) TASK_ID="" ;;
      *) fail "Merge task failed or returned an unknown status." ;;
    esac
  elif [[ "${MERGE_ACCEPTED}" == "false" ]]; then
    # Use the merge actor's permissions and the repository's configured gates.
    # This script does not define the required builds/approvals; Bitbucket does.
    request approver GET "${PR_API}/mergeability/checks"
    [[ "${HTTP_CODE}" == "200" ]] || fail "Cannot read merge checks (HTTP ${HTTP_CODE})."
    jq -e '.values | type == "array"' "${RESPONSE}" >/dev/null || fail "Invalid merge checks."
    if jq -e 'any(.values[]; .blocking == true)' "${RESPONSE}" >/dev/null; then
      echo "Waiting for blocking merge checks:"
      jq -c '.values[] | select(.blocking == true)' "${RESPONSE}"
    else
      # Eligibility can change between the check and POST; a 409 returns to the
      # checks loop. Authentication/other API failures stop immediately.
      request approver POST "${PR_API}/merge" --data '{"close_source_branch":true}'
      case "${HTTP_CODE}" in
        # 200 = synchronous response; still verify the PR state next iteration.
        200) MERGE_ACCEPTED=true ;;
        # 202 = accepted for asynchronous processing, not proof of completion.
        202)
          MERGE_ACCEPTED=true
          TASK_ID="$(jq -r '.task_id // empty' "${RESPONSE}")"
          # Some responses supply only a task-status link. Keep credentials on
          # the configured API host by extracting and validating just its ID.
          if [[ -z "${TASK_ID}" ]]; then
            TASK_LINK="$(jq -r '.links.self.href // empty' "${RESPONSE}")"
            if [[ "${TASK_LINK}" == "${PR_API}/merge/task-status/"* ]]; then
              TASK_ID="${TASK_LINK##*/}"
            fi
          fi
          [[ "${TASK_ID}" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Missing or invalid merge task ID."
          ;;
        409) echo "Merge eligibility changed; checking again."; cat "${RESPONSE}" ;;
        *) fail "Cannot merge PR (HTTP ${HTTP_CODE})." ;;
      esac
    fi
  fi
  sleep "${INTERVAL}"
done
# Leave an unresolved PR available for inspection and a later retry.
fail "Timed out waiting for PR ${PR_ID} to merge. Resolve blocking checks and rerun."

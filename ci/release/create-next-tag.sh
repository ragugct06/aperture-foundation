#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:?source state file is required}"
OUTPUT_FILE="${2:?output file is required}"

: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
: "${APP_REPO_ACCESS_TOKEN:?APP_REPO_ACCESS_TOKEN is required}"

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "ERROR: Source state file not found: ${STATE_FILE}"
  exit 1
fi

source "${STATE_FILE}"

: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${SOURCE_IMAGE_DIGEST:?SOURCE_IMAGE_DIGEST is required}"

VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

if [[ ! "${RELEASE_VERSION}" =~ ${VERSION_PATTERN} ]]; then
  echo "ERROR: RELEASE_VERSION must use semantic version format."
  echo "Example: 1.2.0"
  exit 1
fi

git fetch origin main --tags --force

if ! git merge-base --is-ancestor "${SOURCE_COMMIT}" origin/main; then
  echo "ERROR: DEV deployed commit is not contained in origin/main."
  exit 1
fi

TAG_PREFIX="v${RELEASE_VERSION}-beta."
NEXT_NUMBER=1

while IFS= read -r TAG; do
  [[ -z "${TAG}" ]] && continue

  TAG_COMMIT="$(git rev-list -n 1 "${TAG}")"

  if [[ "${TAG_COMMIT}" == "${SOURCE_COMMIT}" ]]; then
    mkdir -p "$(dirname "${OUTPUT_FILE}")"

    cat > "${OUTPUT_FILE}" <<METADATA
RELEASE_TAG=${TAG}
SOURCE_COMMIT=${SOURCE_COMMIT}
SOURCE_IMAGE_DIGEST=${SOURCE_IMAGE_DIGEST}
METADATA

    echo "Existing QA release tag found: ${TAG}"
    exit 0
  fi

  NUMBER="${TAG##*.}"

  if [[ "${NUMBER}" =~ ^[0-9]+$ ]] && (( NUMBER >= NEXT_NUMBER )); then
    NEXT_NUMBER=$((NUMBER + 1))
  fi
done < <(
  git tag -l "${TAG_PREFIX}*" | sort -V
)

RELEASE_TAG="${TAG_PREFIX}${NEXT_NUMBER}"

./ci/release/validate-version.sh \
  "${RELEASE_TAG}" \
  qa

git tag "${RELEASE_TAG}" "${SOURCE_COMMIT}"

git push \
  "https://x-token-auth:${APP_REPO_ACCESS_TOKEN}@bitbucket.org/anovorx/aperture-foundation.git" \
  "${RELEASE_TAG}"

mkdir -p "$(dirname "${OUTPUT_FILE}")"

cat > "${OUTPUT_FILE}" <<METADATA
RELEASE_TAG=${RELEASE_TAG}
SOURCE_COMMIT=${SOURCE_COMMIT}
SOURCE_IMAGE_DIGEST=${SOURCE_IMAGE_DIGEST}
METADATA

echo "QA release tag created: ${RELEASE_TAG}"

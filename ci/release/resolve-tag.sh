#!/usr/bin/env bash
# Resolve an existing remote release tag; never create or move release tags.
# Usage: bash ci/release/resolve-tag.sh qe|uat|prod [metadata-file]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ENV="${1:?target environment is required}"
OUTPUT_FILE="${2:-reports/release.env}"
: "${RELEASE_TAG:?Set the existing release tag to promote}"
bash "${SCRIPT_DIR}/validate-version.sh" "${RELEASE_TAG}" "${TARGET_ENV}"
# QE uses the existing QA deployment/GitOps directory.
[[ "${TARGET_ENV}" != qe ]] || TARGET_ENV=qa
FETCH_OPTIONS=(--no-tags)
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
  FETCH_OPTIONS+=(--unshallow)
fi
# No force on the tag ref: a moved local/remote release tag must fail closed.
git fetch "${FETCH_OPTIONS[@]}" origin \
  "refs/tags/${RELEASE_TAG}:refs/tags/${RELEASE_TAG}" \
  '+refs/heads/main:refs/remotes/origin/main'
SOURCE_COMMIT="$(git rev-parse --verify "refs/tags/${RELEASE_TAG}^{commit}")"
[[ "${SOURCE_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || exit 1
if ! git merge-base --is-ancestor "${SOURCE_COMMIT}" refs/remotes/origin/main; then
  echo "ERROR: Release tag must reference a commit contained in origin/main." >&2
  exit 1
fi
if ! git cat-file -e "${SOURCE_COMMIT}:database/changelog.yaml" 2>/dev/null; then
  echo "ERROR: Release tag has no Liquibase changelog." >&2
  exit 1
fi
mkdir -p "$(dirname "${OUTPUT_FILE}")"
printf 'RELEASE_TAG=%q\nSOURCE_COMMIT=%q\nTARGET_ENV=%q\n' \
  "${RELEASE_TAG}" "${SOURCE_COMMIT}" "${TARGET_ENV}" > "${OUTPUT_FILE}"
echo "Release ${RELEASE_TAG}: ${SOURCE_COMMIT} -> ${TARGET_ENV}"

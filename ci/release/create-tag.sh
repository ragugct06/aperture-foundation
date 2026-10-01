#!/usr/bin/env bash
# Create an immutable annotated release tag without migrating or deploying.
# qe: SOURCE_REF is a full main commit SHA; uat/prod: a prior-stage release tag.
set -euo pipefail
set +x
TARGET_ENV="${1:?target environment required}"
: "${RELEASE_TAG:?release tag required}"
: "${SOURCE_REF:?source commit or candidate tag required}"
: "${APP_REPO_ACCESS_TOKEN:?application repository tag-push token required}"
: "${BITBUCKET_GIT_HTTP_ORIGIN:?application repository HTTP origin required}"
bash ci/release/validate-version.sh "${RELEASE_TAG}" "${TARGET_ENV}"
REQUESTED_TAG="${RELEASE_TAG}"
case "${TARGET_ENV}" in
  qe|qa)
    [[ "${SOURCE_REF}" =~ ^[0-9a-f]{40}$ ]] || {
      echo "ERROR: Beta tags require a full 40-character SOURCE_REF commit SHA." >&2; exit 1;
    }
    ;;
  uat|prod)
    SOURCE_ENV=qe
    [[ "${TARGET_ENV}" != prod ]] || SOURCE_ENV=uat
    bash ci/release/validate-version.sh "${SOURCE_REF}" "${SOURCE_ENV}"
    SOURCE_VERSION="${SOURCE_REF#v}"
    TARGET_VERSION="${RELEASE_TAG#v}"
    [[ "${SOURCE_VERSION%%-*}" == "${TARGET_VERSION%%-*}" ]] || {
      echo "ERROR: Source and target tags must have the same major.minor.patch version." >&2; exit 1;
    }
    ;;
esac
FETCH_OPTIONS=(--no-tags)
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
  FETCH_OPTIONS+=(--unshallow)
fi
git fetch "${FETCH_OPTIONS[@]}" origin '+refs/heads/main:refs/remotes/origin/main'
if [[ "${TARGET_ENV}" == qe || "${TARGET_ENV}" == qa ]]; then
  SOURCE_COMMIT="$(git rev-parse --verify "${SOURCE_REF}^{commit}")"
else
  git fetch --no-tags origin "refs/tags/${SOURCE_REF}:refs/tags/${SOURCE_REF}"
  SOURCE_COMMIT="$(git rev-parse --verify "refs/tags/${SOURCE_REF}^{commit}")"
fi
if ! git merge-base --is-ancestor "${SOURCE_COMMIT}" refs/remotes/origin/main; then
  echo "ERROR: Source commit must be contained in origin/main." >&2; exit 1
fi
if ! git cat-file -e "${SOURCE_COMMIT}:database/changelog.yaml" 2>/dev/null; then
  echo "ERROR: Source commit has no Liquibase changelog." >&2; exit 1
fi
export IMAGE_COMMIT="${SOURCE_COMMIT}"
bash ci/ecr/read-existing-image.sh
source reports/image-metadata.env
RELEASE_TAG="${REQUESTED_TAG}"

# Inspect the remote, not just a possibly stale tag in the pipeline checkout.
REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/${RELEASE_TAG}" "refs/tags/${RELEASE_TAG}^{}")"
if [[ -n "${REMOTE_TAG}" ]]; then
  git fetch --no-tags origin "refs/tags/${RELEASE_TAG}:refs/tags/${RELEASE_TAG}"
  EXISTING_COMMIT="$(git rev-parse --verify "refs/tags/${RELEASE_TAG}^{commit}")"
  [[ "${EXISTING_COMMIT}" == "${SOURCE_COMMIT}" ]] || {
    echo "ERROR: Release tag already references a different commit; it will not be moved." >&2; exit 1;
  }
  echo "Release tag already exists on the requested commit: ${RELEASE_TAG}"
else
  # Do not replace even a local conflicting tag. Push only the requested ref.
  git -c user.name='Aperture CI' -c user.email='aperture-ci@users.noreply.bitbucket.org' \
    tag -a "${RELEASE_TAG}" "${SOURCE_COMMIT}" -m "Release ${RELEASE_TAG} from ${SOURCE_REF}"
  # The helper reads the token from the environment, never from a URL or file.
  # A concurrent push to this name fails rather than overwriting its tag.
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= \
    -c 'credential.helper=!f() { if [ "$1" = get ]; then printf "username=x-token-auth\npassword=%s\n" "$APP_REPO_ACCESS_TOKEN"; fi; }; f' \
    push "${BITBUCKET_GIT_HTTP_ORIGIN}" "refs/tags/${RELEASE_TAG}:refs/tags/${RELEASE_TAG}"
fi
printf 'RELEASE_TAG=%q\nSOURCE_REF=%q\nSOURCE_COMMIT=%q\nIMAGE_REPOSITORY=%q\nIMAGE_DIGEST=%q\nTARGET_ENV=%q\n' \
  "${RELEASE_TAG}" "${SOURCE_REF}" "${SOURCE_COMMIT}" "${IMAGE_REPOSITORY}" \
  "${IMAGE_DIGEST}" "${TARGET_ENV}" > reports/created-tag.env
echo "Release tag ready: ${RELEASE_TAG} (${SOURCE_COMMIT}). No deployment performed."

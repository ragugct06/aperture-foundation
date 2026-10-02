#!/usr/bin/env bash
# Run from the service checkout. PIPELINE_TEMPLATE_ACCESS_TOKEN needs Repository Read only.
set -euo pipefail
set +x
cd "${BITBUCKET_CLONE_DIR:-$(git rev-parse --show-toplevel)}"
VERSION="$(cat ci/template-version)"
[[ "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: Invalid template release" >&2; exit 1; }
if [[ -n "${1:-}" && "$1" != "${VERSION}" ]]; then
  echo "ERROR: Imported YAML and ci/template-version must select the same release." >&2; exit 1
fi
: "${PIPELINE_TEMPLATE_ACCESS_TOKEN:?Set the secured read-only template repository token}"
if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends git ca-certificates
fi
FETCH_DIR="$(mktemp -d "${PWD}/.pipeline-tools.XXXXXX")"
trap 'rm -rf "${FETCH_DIR}"' EXIT
GIT_TERMINAL_PROMPT=0 git -c credential.helper= \
  -c 'credential.helper=!f() { if [ "$1" = get ]; then printf "username=x-token-auth\npassword=%s\n" "$PIPELINE_TEMPLATE_ACCESS_TOKEN"; fi; }; f' \
  clone --quiet --depth 1 --branch "${VERSION}" \
  https://bitbucket.org/anovorx/aperture-pipeline-templates.git "${FETCH_DIR}"
# --branch also accepts branches, so verify this is actually the requested tag.
TAG_COMMIT="$(git -C "${FETCH_DIR}" rev-parse --verify "refs/tags/${VERSION}^{commit}")" || {
  echo "ERROR: Template release must be a Git tag, not a branch." >&2; exit 1
}
CHECKOUT_COMMIT="$(git -C "${FETCH_DIR}" rev-parse --verify HEAD)"
[[ "${CHECKOUT_COMMIT}" == "${TAG_COMMIT}" ]] || {
  echo "ERROR: Template checkout does not match the requested tag." >&2; exit 1
}
[[ "$(cat "${FETCH_DIR}/VERSION")" == "${VERSION}" ]] || { echo "ERROR: Template VERSION mismatch" >&2; exit 1; }
rm -rf .pipeline-tools
mv "${FETCH_DIR}" .pipeline-tools
echo "Pipeline template ${VERSION}: $(git -C .pipeline-tools rev-parse HEAD)"

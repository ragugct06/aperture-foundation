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
# Runners cannot reach the Ubuntu mirrors on port 80, so use HTTPS for apt.
# Images can ship HTTP repositories in either legacy or deb822 source files.
use_https_apt_sources() {
  local source_file
  for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if [[ -f "${source_file}" ]]; then
      sed -i 's|http://|https://|g' "${source_file}"
    fi
  done
}
if ! command -v git >/dev/null 2>&1; then
  use_https_apt_sources
  apt-get update
  apt-get install -y --no-install-recommends git ca-certificates
fi
# Self-hosted runners can leave /usr/bin/docker as an unusable bind mount.
# Installing docker.io would make dpkg replace that mount and fail with EBUSY.
# Extract only the CLI to /usr/local/bin; the Docker service supplies the daemon.
# Keep Docker preparation limited to Bitbucket builds.
if [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]] && ! docker --version >/dev/null 2>&1; then
  use_https_apt_sources
  apt-get update
  (
    DOCKER_CLI_DIR="$(mktemp -d)"
    trap 'rm -rf "${DOCKER_CLI_DIR}"' EXIT
    cd "${DOCKER_CLI_DIR}"
    apt-get download docker.io
    dpkg-deb --extract ./docker.io_*.deb ./extracted
    install -m 0755 ./extracted/usr/bin/docker /usr/local/bin/docker
  )
  # Prefer the extracted CLI even if the runner's PATH puts /usr/bin first.
  export PATH="/usr/local/bin:${PATH}"
  hash -r
  docker --version
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

#!/usr/bin/env bash
# Compatibility entry point. Supply RELEASE_TAG, not RELEASE_VERSION.
set -euo pipefail
bash ci/release/promote.sh qe

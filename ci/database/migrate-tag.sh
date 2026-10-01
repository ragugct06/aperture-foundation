#!/usr/bin/env bash
# Database-only promotion from an existing release tag; no image is required.
set -euo pipefail
TARGET_ENV="${1:?target environment is required}"
bash ci/release/resolve-tag.sh "${TARGET_ENV}" reports/database-release.env
source reports/database-release.env
bash ci/database/migrate.sh update "${SOURCE_COMMIT}"

#!/usr/bin/env bash
# Offline validation shared by application and CI-only pipelines.
set -euo pipefail

for script in ci/common/*.sh ci/ecr/*.sh ci/gitops/*.sh ci/release/*.sh ci/database/*.sh; do
  bash -n "${script}"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s ci/tests -v

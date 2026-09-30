#!/usr/bin/env bash
# The on-stage redeploy: check lambda/, re-zip it, push it. About 10 seconds.
# Skips the refresh of unchanged infrastructure; run a plain `terraform apply` otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

# A typo on stage should fail here, not in the Lambda.
PY="$(command -v python3 || command -v python)"
"$PY" -m py_compile lambda/*.py
if [[ -x .venv/bin/pytest ]]; then
  .venv/bin/pytest -q tests
else
  echo "(no .venv: skipping pytest; see README 'Checks' to set it up)"
fi

[[ -d build/layer ]] || scripts/build-layer.sh
terraform -chdir=terraform apply -auto-approve -refresh=false

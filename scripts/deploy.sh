#!/usr/bin/env bash
# The on-stage redeploy: re-zip lambda/ and push it. About 10 seconds.
# Skips the refresh of unchanged infrastructure; run a plain `terraform apply` otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d build/layer ]] || scripts/build-layer.sh
terraform -chdir=terraform apply -auto-approve -refresh=false

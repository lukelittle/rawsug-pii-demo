#!/usr/bin/env bash
# Build the Lambda layer (decision-circuits, pure Python) into build/layer.
# Run once before the first `terraform apply`, and again only when layer/requirements.txt changes.
# Function code (lambda/) is zipped by Terraform itself, so on-stage edits never rebuild this.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="$(command -v python3 || command -v python)"
rm -rf build/layer
"$PY" -m pip install --quiet --disable-pip-version-check \
  --requirement layer/requirements.txt \
  --target build/layer/python \
  --python-version 3.12 \
  --only-binary=:all: \
  --no-deps  # decision-circuits has none; --python-version: works even from macOS's python 3.9
find build/layer -name __pycache__ -type d -prune -exec rm -rf {} +
test -f build/layer/python/decision_circuits/__init__.py
echo "layer: $(ls -d build/layer/python/decision_circuits-*.dist-info | xargs basename) in build/layer"

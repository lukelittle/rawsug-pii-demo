#!/usr/bin/env bash
# Build the Lambda layer (decision-circuits + the Anthropic SDK) into build/layer.
# Run once before the first `terraform apply`, and again only when layer/requirements.txt changes.
# Function code (lambda/) is zipped by Terraform itself, so on-stage edits never rebuild this.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build/layer
pip install --quiet \
  --requirement layer/requirements.txt \
  --target build/layer/python \
  --platform manylinux2014_aarch64 \
  --implementation cp \
  --python-version 3.13 \
  --only-binary=:all: \
  --upgrade
# boto3/botocore ship with the Lambda runtime; drop copies pulled in transitively.
rm -rf build/layer/python/{boto3,botocore,s3transfer}* build/layer/python/bin
find build/layer -name __pycache__ -type d -prune -exec rm -rf {} +
echo "layer: $(du -sh build/layer | cut -f1) in build/layer"

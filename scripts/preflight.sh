#!/usr/bin/env bash
# Everything the demo needs, checked in order. Run tonight after deploying, and again
# 30 minutes before you go on (it also wakes the model).
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fails=$((fails + 1)); }
ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

echo "tools"
for t in aws curl jq; do command -v "$t" >/dev/null || bad "$t not installed"; done
# Accept either terraform >= 1.7 or tofu >= 1.7
if command -v tofu >/dev/null; then
  tfv="$(tofu version -json 2>/dev/null | jq -r .terraform_version)"
  ver_ge "${tfv:-0}" 1.7 && ok "tofu $tfv" || bad "tofu $tfv < 1.7"
elif command -v terraform >/dev/null; then
  tfv="$(terraform version -json 2>/dev/null | jq -r .terraform_version)"
  ver_ge "${tfv:-0}" 1.7 && ok "terraform $tfv" || bad "terraform $tfv < 1.7"
else
  bad "neither terraform nor tofu installed"
fi
awsv="$(aws --version 2>&1 | sed -E 's|aws-cli/([0-9.]+).*|\1|')"
ver_ge "${awsv:-0}" 2.9 && ok "aws-cli $awsv" || bad "aws-cli $awsv < 2.9 (need 'aws configure export-credentials')"
curlhelp="$(curl --help all 2>/dev/null)"  # not piped into grep -q: pipefail + SIGPIPE would misreport
[[ "$curlhelp" == *--aws-sigv4* ]] && ok "curl has --aws-sigv4" || bad "curl lacks --aws-sigv4 (need >= 7.75)"

echo "aws"
who="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" && ok "signed in as $who" || { bad "no AWS credentials (aws sso login?)"; exit 1; }

echo "stack"
source scripts/_outputs.sh 2>/dev/null
set +e  # _outputs.sh turns on errexit; this script reports failures instead of dying on them
if [[ -z "${API_URL:-}" || -z "${FUNCTION:-}" ]]; then bad "no terraform outputs: deploy first (README 'Deploy')"; exit 1; fi
ok "api $API_URL"
TF_CMD="$(command -v tofu 2>/dev/null || command -v terraform)"
SECRET="$("$TF_CMD" -chdir=terraform output -raw api_key_secret_id)"
if aws secretsmanager list-secret-version-ids --secret-id "$SECRET" \
    --query 'Versions[?contains(VersionStages, `AWSCURRENT`)] | length(@)' --output text 2>/dev/null | grep -q '^1$'; then
  ok "model API key is set"
else
  bad "model API key not set: see README 'Deploy' (put-secret-value)"
fi
aws lambda get-function-configuration --function-name "$FUNCTION" --query State --output text 2>/dev/null | grep -q Active \
  && ok "lambda $FUNCTION active" || bad "lambda $FUNCTION not active"

echo "self-test as the Lambda's role (wakes the model: up to ~1 min)"
out="$(mktemp)"
if aws lambda invoke --function-name "$FUNCTION" --cli-binary-format raw-in-base64-out \
     --cli-read-timeout 310 --payload '{"selftest": true}' "$out" >/dev/null; then
  if jq -e '.errorMessage' "$out" >/dev/null 2>&1; then
    bad "circuit model: $(jq -r '.errorMessage' "$out" | head -c 300)"
  else
    ok "circuit model $(jq -r .model "$out") answered in $(jq -r .seconds "$out")s"
    if jq -e '.bedrock.ok' "$out" >/dev/null; then
      ok "bedrock $(jq -r .bedrock.model "$out") in $(jq -r .bedrock.seconds "$out")s: $(jq -r .bedrock.summary "$out")"
    else
      bad "bedrock $(jq -r .bedrock.model "$out"): $(jq -r .bedrock.error "$out")"
    fi
  fi
else
  bad "could not invoke $FUNCTION"
fi
rm -f "$out"

echo "api (signed request, end to end)"
code="$(scripts/demo.sh "Where can I find my invoice?" 2>&1 | grep -oE '^HTTP [0-9]+' | head -1 || true)"
[[ "$code" == "HTTP 200" ]] && ok "POST /messages -> 200" || bad "POST /messages -> ${code:-no response} (run scripts/demo.sh \"test\" to see it)"

echo
if [[ $fails == 0 ]]; then echo "All good. Start: scripts/warmup.sh --keep-warm"; else echo "$fails problem(s) above."; exit 1; fi

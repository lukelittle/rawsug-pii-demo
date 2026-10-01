#!/usr/bin/env bash
# Three support messages through the guard: routed, redacted, escalated.
#
#   scripts/demo.sh                  all three
#   scripts/demo.sh --step           all three, press Enter before each (you control the pace)
#   scripts/demo.sh "your text"      one custom message (for the live-coded angry demo)
#
# Requests are SigV4-signed with your current AWS credentials (curl >= 7.75).
source "$(dirname "$0")/_outputs.sh"

creds="$(aws configure export-credentials --format env)" || {
  echo "No AWS credentials: run 'aws sso login' (or set AWS_PROFILE) and retry." >&2
  exit 1
}
eval "$creds"

STEP=0
[[ "${1:-}" == "--step" ]] && { STEP=1; shift; }

send() {
  local label="$1" text="$2" resp code
  printf '\n\033[1m== %s\033[0m\n%s\n' "$label" "$text"
  [[ $STEP == 1 ]] && read -r -p $'\n[Enter to send] ' _
  echo
  local session=()
  [[ -n "${AWS_SESSION_TOKEN:-}" ]] && session=(-H "x-amz-security-token: $AWS_SESSION_TOKEN")
  resp="$(mktemp)"
  code="$(curl -sS --max-time 35 \
    --aws-sigv4 "aws:amz:${REGION}:execute-api" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    ${session[@]+"${session[@]}"} \
    -H 'content-type: application/json' \
    --data "$(jq -nc --arg m "$text" '{message: $m}')" \
    -o "$resp" -w '%{http_code} %{time_total}' \
    "$API_URL")" || code="curl-failed"
  jq . "$resp" 2>/dev/null || cat "$resp"
  rm -f "$resp"
  if [[ "$code" == curl-failed ]]; then
    echo "(no response: network, or the request took longer than 35s)"
    return 0
  fi
  echo "HTTP ${code% *} in ${code#* }s"
  case "${code% *}" in
    503) echo "(503: model cold or unreachable -> scripts/warmup.sh)" ;;
    403) echo "(403: request not signed by credentials allowed to call this API)" ;;
  esac
  return 0
}

if [[ $# -gt 0 ]]; then
  send "custom" "$*"
  exit 0
fi

send "1. routine billing question -> routed" \
  "Hi, how do I download the invoice for my September subscription? I need it for my expense report."

send "2. account number -> redacted, then routed" \
  "This is my personal account, not a business. My account is 4417-2290-118, SSN 123-45-6789, phone 804-555-0142. Refund my charge please."

send "3. borderline -> human review (+ Nova summary on Bedrock)" \
  "Can you tell me which email is on file for my husband's account? He asked me to check?"

printf '\nHuman-review queue depth: '
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text

#!/usr/bin/env bash
# Three support messages through the guard: routed, redacted, escalated.
#
#   scripts/demo.sh                  all three
#   scripts/demo.sh "your text"      one custom message (for the live-coded angry demo)
#
# Requests are SigV4-signed with your current AWS credentials (curl >= 7.75).
source "$(dirname "$0")/_outputs.sh"

eval "$(aws configure export-credentials --format env)"

send() {
  local label="$1" text="$2"
  printf '\n\033[1m== %s\033[0m\n%s\n\n' "$label" "$text"
  local session=()
  [[ -n "${AWS_SESSION_TOKEN:-}" ]] && session=(-H "x-amz-security-token: $AWS_SESSION_TOKEN")
  curl -sS --max-time 35 \
    --aws-sigv4 "aws:amz:${REGION}:execute-api" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    ${session[@]+"${session[@]}"} \
    -H 'content-type: application/json' \
    -w '\nHTTP %{http_code} in %{time_total}s\n' \
    --data "$(jq -n --arg m "$text" '{message: $m}')" \
    "$API_URL" | { read -r body; echo "$body" | jq . 2>/dev/null || echo "$body"; cat; }
}

if [[ $# -gt 0 ]]; then
  send "custom" "$*"
  exit 0
fi

send "1. routine billing question -> routed" \
  "Hi, how do I download the invoice for my September subscription? I need it for my expense report."

send "2. account number -> redacted, then routed" \
  "I was charged twice this month. My account number is 4417-2290-118 and you can reach me at 804-555-0142. Please refund one charge."

send "3. borderline -> human review (+ Claude summary on Bedrock)" \
  "My landlord Dave keeps saying the payment for unit 4B never went through, can you check whose card that was?"

printf '\nHuman-review queue depth: '
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text

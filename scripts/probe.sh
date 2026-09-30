#!/usr/bin/env bash
# Show what the circuit would do with a message: every probability, every gate,
# and the decision. Nothing is queued, summarized or logged as a decision.
# Use it while rehearsing to pick messages that land where you want them.
#
#   scripts/probe.sh "My landlord says my card was declined"
source "$(dirname "$0")/_outputs.sh"
[[ $# -gt 0 ]] || { echo "usage: $0 \"message text\"" >&2; exit 2; }

out="$(mktemp)"
aws lambda invoke \
  --function-name "$FUNCTION" \
  --cli-binary-format raw-in-base64-out \
  --cli-read-timeout 310 \
  --payload "$(jq -n --arg m "$*" '{probe: $m}')" \
  "$out" >/dev/null
jq . "$out"
rm -f "$out"

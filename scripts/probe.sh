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
  --payload "$(jq -nc --arg m "$*" '{probe: $m}')" \
  "$out" >/dev/null
if jq -e '.errorMessage' "$out" >/dev/null 2>&1; then
  echo "probe FAILED:" >&2; jq . "$out" >&2; rm -f "$out"; exit 1
fi
jq '{would: .would.status, reasons: [.would.reasons[]?.gate], gates, answers}' "$out"
rm -f "$out"

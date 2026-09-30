#!/usr/bin/env bash
# Wake the hosted model (it scales to zero; the first call takes about a minute).
#
#   scripts/warmup.sh              wake it once, print how long it took
#   scripts/warmup.sh --keep-warm  then ping every 4 minutes until Ctrl-C (run during the talk)
#                                  KEEP_WARM_SECONDS=120 scripts/warmup.sh --keep-warm  to ping more often
#
# Invokes the Lambda directly, not through API Gateway: API Gateway gives up
# at 30s, a direct invoke can wait out the cold start. Same code, same key.
source "$(dirname "$0")/_outputs.sh"
INTERVAL="${KEEP_WARM_SECONDS:-240}"

ping_once() {
  local out t0=$SECONDS
  out="$(mktemp)"
  if ! aws lambda invoke \
    --function-name "$FUNCTION" \
    --cli-binary-format raw-in-base64-out \
    --cli-read-timeout 310 \
    --cli-connect-timeout 10 \
    --payload '{"warmup": true}' \
    "$out" >/dev/null; then
    echo "$(date +%T) warmup FAILED: could not invoke $FUNCTION" >&2
    rm -f "$out"
    return 1
  fi
  if jq -e '.ok == true' "$out" >/dev/null 2>&1; then
    echo "$(date +%T) warm after $((SECONDS - t0))s  $(jq -c '{model, seconds, gates: (.gates | map_values(.outcome))}' "$out")"
    rm -f "$out"
  else
    echo "$(date +%T) warmup FAILED after $((SECONDS - t0))s:" >&2
    jq . "$out" >&2 2>/dev/null || cat "$out" >&2
    rm -f "$out"
    return 1
  fi
}

echo "Waking the model (up to ~1 min on a cold start)..."
if [[ "${1:-}" == "--keep-warm" ]]; then
  ping_once || true
  echo "Keeping warm every ${INTERVAL}s. Ctrl-C to stop."
  while sleep "$INTERVAL"; do ping_once || true; done
else
  ping_once
fi

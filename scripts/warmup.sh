#!/usr/bin/env bash
# Wake the hosted model (it scales to zero; the first call takes about a minute).
#
#   scripts/warmup.sh              wake it once, print how long it took
#   scripts/warmup.sh --keep-warm  then ping every 4 minutes until Ctrl-C (run during the talk)
#
# Invokes the Lambda directly, not through API Gateway: API Gateway gives up
# at 30s, a direct invoke can wait out the cold start. Same code, same key.
source "$(dirname "$0")/_outputs.sh"

ping_once() {
  local out
  out="$(mktemp)"
  local t0=$SECONDS
  aws lambda invoke \
    --function-name "$FUNCTION" \
    --cli-binary-format raw-in-base64-out \
    --cli-read-timeout 310 \
    --payload '{"warmup": true}' \
    "$out" >/dev/null
  if grep -q '"ok": true' "$out"; then
    echo "$(date +%T) warm after $((SECONDS - t0))s: $(cat "$out")"
  else
    echo "$(date +%T) warmup FAILED after $((SECONDS - t0))s: $(cat "$out")" >&2
    rm -f "$out"
    return 1
  fi
  rm -f "$out"
}

echo "Waking the model (up to ~1 min on a cold start)..."
ping_once

if [[ "${1:-}" == "--keep-warm" ]]; then
  echo "Keeping warm every 240s. Ctrl-C to stop."
  while sleep 240; do ping_once || true; done
fi

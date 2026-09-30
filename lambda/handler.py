"""POST /messages -> run the circuit -> routed (200) or human review (202).

Direct invokes (not reachable through API Gateway):
  {"warmup": true}       wake the scaled-to-zero model; see scripts/warmup.sh
  {"probe": "some text"} run the circuit and return every probability, no side effects;
                         see scripts/probe.sh (for picking demo messages while rehearsing)
"""

from __future__ import annotations

import base64
import hashlib
import json
import time
from typing import Any

from backend import MODEL_ENDPOINT, make_backend
from circuit import VERSION, c
from decide import decide, gate_summary

MAX_CHARS = 4000
WARMUP_TEXT = "Hi, I was charged twice this month. Can you refund one of the charges?"


def log(**fields: Any) -> None:
    """One JSON line per event; CloudWatch Logs Insights can query every field."""
    print(json.dumps(fields, default=str))


def respond(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {"statusCode": status, "headers": {"content-type": "application/json"}, "body": json.dumps(body)}


def warmup() -> dict[str, Any]:
    t0 = time.monotonic()
    out = c.run(make_backend(timeout=120, retry_for=240), WARMUP_TEXT)
    seconds = round(time.monotonic() - t0, 1)
    log(event="warmup", seconds=seconds, model=out["model"], endpoint=MODEL_ENDPOINT)
    return {"ok": True, "seconds": seconds, "model": out["model"], "gates": gate_summary(out["gates"])}


def probe(text: str) -> dict[str, Any]:
    out = c.run(make_backend(timeout=120, retry_for=240), text)
    return {"model": out["model"], "answers": out["answers"], "gates": gate_summary(out["gates"]),
            "would": decide(text, out["gates"])}


def parse(event: dict[str, Any]) -> str:
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode()
    try:
        text = json.loads(raw).get("message")
    except (ValueError, AttributeError):
        text = None
    if not isinstance(text, str) or not text.strip():
        raise ValueError('send JSON: {"message": "..."}')
    if len(text) > MAX_CHARS:
        raise ValueError(f"message longer than {MAX_CHARS} characters")
    return text


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if event.get("warmup"):
        return warmup()
    if "probe" in event:
        return probe(str(event["probe"]))

    request_id = context.aws_request_id
    try:
        text = parse(event)
    except ValueError as e:
        return respond(400, {"error": str(e)})

    t0 = time.monotonic()
    try:
        # API Gateway gives up at 30s, so don't wait out a cold start here.
        out = c.run(make_backend(timeout=20, retry_for=8), text)
    except Exception as e:
        # No answers, no decision: nothing is routed, redacted or queued.
        log(event="model_unavailable", request_id=request_id, endpoint=MODEL_ENDPOINT, error=f"{type(e).__name__}: {e}"[:500])
        return respond(503, {"error": "model_unavailable", "hint": "run scripts/warmup.sh", "request_id": request_id})
    latency_ms = round((time.monotonic() - t0) * 1000)

    decision = decide(text, out["gates"])
    trace = {
        "circuit_version": VERSION,
        "model": out["model"],
        "endpoint": MODEL_ENDPOINT,
        "latency_ms": latency_ms,
        "answers": out["answers"],
        "gates": out["gates"],
    }
    summary = gate_summary(out["gates"])

    if decision["status"] == "human_review":
        from review import enqueue  # Bedrock + SQS clients load only when needed

        queued = enqueue(request_id, text, decision, trace)
        log(event="circuit_decision", request_id=request_id, status="human_review",
            message_sha256=hashlib.sha256(text.encode()).hexdigest(), reasons=decision["reasons"], review=queued, **trace)
        return respond(202, {"status": "human_review", "request_id": request_id, **queued,
                             "reasons": [r["gate"] for r in decision["reasons"]], "gates": summary})

    # Log the redacted text only; the raw message never reaches CloudWatch.
    log(event="circuit_decision", request_id=request_id, message_sha256=hashlib.sha256(text.encode()).hexdigest(),
        **decision, **trace)
    return respond(200, {**decision, "request_id": request_id, "gates": summary})

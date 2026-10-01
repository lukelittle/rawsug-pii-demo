"""POST /messages -> run the circuit -> routed (200) or human review (202).

Direct invokes (not reachable through API Gateway):
  {"warmup": true}       wake the scaled-to-zero model; see scripts/warmup.sh
  {"probe": "some text"} run the circuit and return every probability, no side effects;
                         see scripts/probe.sh (for picking demo messages while rehearsing)
  {"selftest": true}     warmup + one Bedrock summary, as the Lambda's own role; see scripts/preflight.sh
"""

from __future__ import annotations

import base64
import hashlib
import json
import time
from typing import Any

from backend import MODEL_ENDPOINT, forget_api_key, make_backend
from circuit import REVIEW_WHEN_TRUE, VERSION, c
from decide import answer_summary, decide, gate_summary

# Fail at cold start with a clear message, not mid-request with a KeyError.
_unknown = set(REVIEW_WHEN_TRUE) - {g.name for g in c.gates}
if _unknown:
    raise RuntimeError(f"circuit.py: REVIEW_WHEN_TRUE names no such gate: {sorted(_unknown)}")

MAX_CHARS = 4000
WARMUP_TEXT = "Hi, I was charged twice this month. Can you refund one of the charges?"


def log(**fields: Any) -> None:
    """One JSON line per event; CloudWatch Logs Insights can query every field."""
    print(json.dumps(fields, default=str))


def respond(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {"statusCode": status, "headers": {"content-type": "application/json"}, "body": json.dumps(body)}


# Direct invokes may wait out a cold model: at most ~170s of retries + one 60s attempt
# (x2 for connect + read), inside the Lambda's 300s timeout.
def warmup() -> dict[str, Any]:
    t0 = time.monotonic()
    forget_api_key()  # always read the current secret, so warmup also proves the key
    out = c.run(make_backend(timeout=60, retry_for=170), WARMUP_TEXT)
    seconds = round(time.monotonic() - t0, 1)
    log(event="warmup", seconds=seconds, model=out["model"], endpoint=MODEL_ENDPOINT)
    return {"ok": True, "seconds": seconds, "model": out["model"], "gates": gate_summary(out["gates"])}


def selftest() -> dict[str, Any]:
    from review import BEDROCK_MODEL_ID, summarize

    result = warmup()
    t0 = time.monotonic()
    try:
        result["bedrock"] = {"ok": True, "model": BEDROCK_MODEL_ID,
                             "summary": summarize(WARMUP_TEXT, [{"gate": "selftest", "outcome": "escalate"}])}
    except Exception as e:
        result["ok"] = False
        result["bedrock"] = {"ok": False, "model": BEDROCK_MODEL_ID, "error": f"{type(e).__name__}: {e}"[:500]}
    result["bedrock"]["seconds"] = round(time.monotonic() - t0, 1)
    return result


def probe(text: str) -> dict[str, Any]:
    out = c.run(make_backend(timeout=60, retry_for=170), text)
    return {"model": out["model"], "answers": out["answers"], "gates": gate_summary(out["gates"], c.compile()),
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
    if event.get("selftest"):
        return selftest()
    if "probe" in event:
        return probe(str(event["probe"]))

    request_id = context.aws_request_id
    try:
        text = parse(event)
    except ValueError as e:
        return respond(400, {"error": str(e)})

    t0 = time.monotonic()
    try:
        # API Gateway gives up at 30s. urllib's timeout is per socket operation (connect,
        # then read), so worst cases: model 2x6s + Bedrock 2+6s + SQS 2+3s = 25s.
        # One attempt, no waiting out a cold start: that's what warmup is for.
        out = c.run(make_backend(timeout=6, retry_for=0), text)
    except Exception as e:
        # No answers, no decision: nothing is routed, redacted or queued.
        forget_api_key()  # a key fixed in Secrets Manager is picked up on the next call
        error = f"{type(e).__name__}: {e}"[:500]
        log(event="model_unavailable", request_id=request_id, endpoint=MODEL_ENDPOINT, error=error)
        return respond(503, {"error": "model_unavailable", "detail": error[:200],
                             "hint": "cold model? run scripts/warmup.sh", "request_id": request_id})
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
    summary = gate_summary(out["gates"], c.compile())
    answered = answer_summary(out["answers"])  # the model's side of the split; gates are the code's

    if decision["status"] == "human_review":
        from review import enqueue  # Bedrock + SQS clients load only when needed

        try:
            queued = enqueue(request_id, text, decision, trace)
        except Exception as e:
            # The circuit said "a human decides" and no human can see it: tell the caller.
            log(event="review_queue_unavailable", request_id=request_id, error=f"{type(e).__name__}: {e}"[:500])
            return respond(503, {"error": "review_queue_unavailable", "request_id": request_id})
        log(event="circuit_decision", request_id=request_id, status="human_review",
            message_sha256=hashlib.sha256(text.encode()).hexdigest(), reasons=decision["reasons"], review=queued, **trace)
        return respond(202, {"status": "human_review", "request_id": request_id, **queued,
                             "reasons": [r["gate"] for r in decision["reasons"]],
                             "answers": answered, "gates": summary, "latency_ms": latency_ms})

    # The message text never reaches CloudWatch, redacted or not: a hash, and what was masked.
    log(event="circuit_decision", request_id=request_id, message_sha256=hashlib.sha256(text.encode()).hexdigest(),
        **{k: v for k, v in decision.items() if k != "message"}, **trace)
    return respond(200, {**decision, "request_id": request_id, "answers": answered, "gates": summary,
                         "latency_ms": latency_ms})

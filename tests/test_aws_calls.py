"""The AWS calls, checked against botocore's real service models (Stubber
rejects any parameter the API doesn't accept), and the handler end to end
against a local fake System One server. No AWS account, no model key.
"""

import json
import os
import sys
import threading
import types
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest
from botocore.stub import ANY, Stubber

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lambda"))

QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123456789012/decide-in-code-human-review"
MODEL_ID = "us.amazon.nova-2-lite-v1:0"


class FakeSystemOne(BaseHTTPRequestHandler):
    """Answers like circuit-8b would, keyed on words in the message."""

    status = 200
    seen: list = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeSystemOne.seen.append({"auth": self.headers.get("Authorization"), **body})
        if FakeSystemOne.status != 200:
            self.send_response(FakeSystemOne.status)
            self.end_headers()
            self.wfile.write(b'{"detail": "nope"}')
            return
        s = body["state"]
        pii = 0.97 if "4417" in s else 0.66 if "landlord" in s else 0.03
        known = {
            "pii": {"type": "noul", "noul": pii},
            "business": {"type": "noul", "noul": 0.05},
            "angry": {"type": "noul", "noul": 0.93 if "THIRD time" in s else 0.03},
            "dept": {
                "type": "choice",
                "choice": "billing",
                "confidence": 0.8,
                "probabilities": {"billing": 0.93, "technical": 0.05, "other": 0.02},
            },
        }
        # Answer whatever the circuit asks, so a question added on stage doesn't break tests.
        answers = {q: known.get(q, {"type": "noul", "noul": 0.02}) for q in body["questions"]}
        out = json.dumps({"model": body["model"], "answers": answers}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *a):
        pass


@pytest.fixture(scope="module")
def mods():
    srv = HTTPServer(("127.0.0.1", 0), FakeSystemOne)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    os.environ.update(
        AWS_REGION="us-east-1",
        AWS_DEFAULT_REGION="us-east-1",
        AWS_ACCESS_KEY_ID="testing",
        AWS_SECRET_ACCESS_KEY="testing",
        MODEL_ENDPOINT=f"http://127.0.0.1:{srv.server_port}/v1/systemone",
        MODEL_NAME="circuit-8b",
        API_KEY_SECRET_ARN="arn:aws:secretsmanager:us-east-1:123456789012:secret:decide-in-code/model-api-key-AbCdEf",
        BEDROCK_MODEL_ID=MODEL_ID,
        REVIEW_QUEUE_URL=QUEUE_URL,
    )
    import backend
    import handler
    import review

    yield types.SimpleNamespace(backend=backend, handler=handler, review=review)
    srv.shutdown()


@pytest.fixture
def aws(mods, monkeypatch):
    """Stubbed Bedrock, SQS and Secrets Manager clients."""
    import boto3

    sm = boto3.client("secretsmanager", region_name="us-east-1")
    monkeypatch.setattr(mods.backend.boto3, "client", lambda name, **kw: sm if name == "secretsmanager" else None)
    mods.backend.forget_api_key()
    FakeSystemOne.status, FakeSystemOne.seen = 200, []
    stubs = types.SimpleNamespace(
        bedrock=Stubber(mods.review._bedrock), sqs=Stubber(mods.review._sqs), sm=Stubber(sm)
    )
    for s in vars(stubs).values():
        s.activate()
    yield stubs
    for s in vars(stubs).values():
        s.deactivate()


def secret_ok(stubs):
    stubs.sm.add_response(
        "get_secret_value",
        {"SecretString": "sk-test\n", "ARN": os.environ["API_KEY_SECRET_ARN"], "Name": "decide-in-code/model-api-key"},
        {"SecretId": os.environ["API_KEY_SECRET_ARN"]},
    )


def converse_ok(stubs, text="The customer asks X. The guard was unsure about Y."):
    stubs.bedrock.add_response(
        "converse",
        {
            "output": {"message": {"role": "assistant", "content": [{"text": text}]}},
            "stopReason": "end_turn",
            "usage": {"inputTokens": 120, "outputTokens": 30, "totalTokens": 150},
            "metrics": {"latencyMs": 400},
        },
        {
            "modelId": MODEL_ID,
            "system": [{"text": ANY}],
            "messages": ANY,
            "inferenceConfig": {"maxTokens": 200, "temperature": 0.2},
        },
    )


def sqs_ok(stubs):
    stubs.sqs.add_response(
        "send_message",
        {"MessageId": "11111111-2222-3333-4444-555555555555", "MD5OfMessageBody": "d41d8cd98f00b204e9800998ecf8427e"},
        {"QueueUrl": QUEUE_URL, "MessageBody": ANY},
    )


def call(mods, message):
    event = {"body": json.dumps({"message": message}), "isBase64Encoded": False}
    r = mods.handler.handler(event, types.SimpleNamespace(aws_request_id="req-1"))
    return r["statusCode"], json.loads(r["body"])


def test_routed(mods, aws, capsys):
    secret_ok(aws)
    status, body = call(mods, "Where is my invoice?")
    assert status == 200 and body["status"] == "routed" and body["department"] == "billing"
    assert FakeSystemOne.seen[0]["auth"] == "Bearer sk-test"  # secret stripped, sent as Bearer
    assert FakeSystemOne.seen[0]["model"] == "circuit-8b"
    log = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert log["event"] == "circuit_decision" and "answers" in log and "gates" in log
    assert "message" not in log and "invoice" not in json.dumps(log)  # no message text in logs


def test_redacted_and_raw_text_never_logged(mods, aws, capsys):
    secret_ok(aws)
    status, body = call(mods, "Refund please, account number is 4417-2290-118, call 804-555-0142")
    assert status == 200 and body["redacted"] is True
    assert "4417" not in body["message"] and "0142" not in body["message"]
    assert "4417" not in capsys.readouterr().out


def test_escalated_goes_to_queue_with_summary(mods, aws, capsys):
    secret_ok(aws)
    converse_ok(aws)
    sqs_ok(aws)
    status, body = call(mods, "My landlord Dave says the payment failed, whose card was it?")
    assert status == 202 and body["status"] == "human_review" and body["reasons"] == ["redact"]
    assert body["summary"].startswith("The customer asks")
    assert body["review_id"]
    aws.bedrock.assert_no_pending_responses()
    aws.sqs.assert_no_pending_responses()
    assert "landlord" not in capsys.readouterr().out  # raw text: queue only, not logs


def test_bedrock_failure_still_queues(mods, aws):
    secret_ok(aws)
    aws.bedrock.add_client_error("converse", "AccessDeniedException", "not authorized", 403)
    sqs_ok(aws)
    status, body = call(mods, "My landlord Dave says the payment failed")
    assert status == 202 and body["summary"] is None and "AccessDenied" in body["summary_error"]


def test_queue_failure_is_503_not_silent(mods, aws):
    secret_ok(aws)
    converse_ok(aws)
    aws.sqs.add_client_error("send_message", "KMS.AccessDeniedException", "kms", 400)
    status, body = call(mods, "My landlord Dave says the payment failed")
    assert status == 503 and body["error"] == "review_queue_unavailable"


def test_model_down_is_503_and_key_reread(mods, aws):
    secret_ok(aws)
    FakeSystemOne.status = 401
    status, body = call(mods, "Where is my invoice?")
    assert status == 503 and body["error"] == "model_unavailable" and "401" in body["detail"]
    FakeSystemOne.status = 200
    secret_ok(aws)  # a fixed key is fetched again, not the cached bad one
    assert call(mods, "Where is my invoice?")[0] == 200
    aws.sm.assert_no_pending_responses()


def test_secret_without_value_is_503(mods, aws):
    aws.sm.add_client_error("get_secret_value", "ResourceNotFoundException", "no AWSCURRENT", 400)
    status, body = call(mods, "Where is my invoice?")
    assert status == 503 and "ResourceNotFound" in body["detail"]


@pytest.mark.parametrize("raw", ["", "not json", '{"msg": "x"}', '{"message": "   "}', json.dumps({"message": "x" * 4001})])
def test_bad_input_is_400(mods, aws, raw):
    r = mods.handler.handler({"body": raw}, types.SimpleNamespace(aws_request_id="r"))
    assert r["statusCode"] == 400


def test_base64_body(mods, aws):
    import base64

    secret_ok(aws)
    raw = base64.b64encode(json.dumps({"message": "Where is my invoice?"}).encode()).decode()
    r = mods.handler.handler({"body": raw, "isBase64Encoded": True}, types.SimpleNamespace(aws_request_id="r"))
    assert r["statusCode"] == 200


def test_warmup_probe_selftest(mods, aws):
    secret_ok(aws)
    assert mods.handler.handler({"warmup": True}, None)["ok"] is True
    secret_ok(aws)
    p = mods.handler.handler({"probe": "My landlord Dave"}, None)
    assert p["would"]["status"] == "human_review" and "pii" in p["answers"]
    secret_ok(aws)
    converse_ok(aws)
    st = mods.handler.handler({"selftest": True}, None)
    assert st["ok"] is True and st["bedrock"]["ok"] is True

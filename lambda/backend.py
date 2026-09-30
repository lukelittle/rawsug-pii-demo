"""Where the circuit's questions get answered. One setting picks the server.

MODEL_ENDPOINT (Terraform: var.model_endpoint.url) is either
  https://...          any System One HTTP server (hosted circuit, TypeSafe's Jev,
                       a self-hosted circuit); API key from Secrets Manager
  sagemaker://NAME     a SageMaker endpoint serving the System One contract; IAM auth
"""

from __future__ import annotations

import json
import os
from typing import Any

import boto3
from botocore.config import Config
from decision_circuits.backends import SystemOne
from decision_circuits.types import to_jsonable

MODEL_ENDPOINT = os.environ["MODEL_ENDPOINT"]
MODEL_NAME = os.environ.get("MODEL_NAME") or None
API_KEY_SECRET_ARN = os.environ.get("API_KEY_SECRET_ARN", "")

_api_key: str | None = None


def _get_api_key() -> str:
    global _api_key
    if _api_key is None:
        sm = boto3.client("secretsmanager", config=Config(connect_timeout=2, read_timeout=3))
        _api_key = sm.get_secret_value(SecretId=API_KEY_SECRET_ARN)["SecretString"].strip()
    return _api_key


def forget_api_key() -> None:
    global _api_key
    _api_key = None


class SageMakerSystemOne:
    """The SystemOne contract over SageMaker InvokeEndpoint (SigV4, no API key)."""

    def __init__(self, endpoint_name: str, model: str | None, timeout: float):
        self.endpoint_name = endpoint_name
        self.model = model
        self._rt = boto3.client("sagemaker-runtime", config=Config(connect_timeout=3, read_timeout=timeout))

    def answer(self, state: Any, questions: Any, *, model: str | None = None) -> Any:
        body = {"state": to_jsonable(state), "model": model or self.model, "questions": dict(questions)}
        r = self._rt.invoke_endpoint(
            EndpointName=self.endpoint_name, ContentType="application/json", Body=json.dumps(body)
        )
        payload = json.loads(r["Body"].read())
        if "answers" not in payload:
            raise RuntimeError(f"SageMaker endpoint returned no answers: {str(payload)[:300]}")
        return payload["answers"]


def make_backend(timeout: float, retry_for: float) -> Any:
    """`timeout` per request; `retry_for`: seconds to keep retrying while a
    scaled-to-zero model starts (the hosted circuit takes about a minute)."""
    if MODEL_ENDPOINT.startswith("sagemaker://"):
        return SageMakerSystemOne(MODEL_ENDPOINT.removeprefix("sagemaker://"), MODEL_NAME, timeout)
    kw: dict[str, Any] = {"timeout": timeout, "retry_for": retry_for}
    if MODEL_NAME:
        kw["model"] = MODEL_NAME
    return SystemOne(MODEL_ENDPOINT, api_key=_get_api_key(), **kw)

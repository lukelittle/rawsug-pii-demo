"""Turn gate results into an action. Pure code, no AWS: tested offline."""

from __future__ import annotations

from typing import Any

from circuit import REVIEW_WHEN_TRUE
from redact import mask


def decide(text: str, gates: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Review if any gate is uncertain, or a REVIEW_WHEN_TRUE gate fired.
    Otherwise redact (when the redact gate says so) and route."""
    reasons = [
        {"gate": name, "outcome": g["outcome"], "p": g["p"], "trace": g["trace"]}
        for name, g in gates.items()
        if g["outcome"] != "decided"
    ]
    reasons += [
        {"gate": name, "outcome": "flagged", "p": gates[name]["p"], "trace": gates[name]["trace"]}
        for name in REVIEW_WHEN_TRUE
        if gates[name]["outcome"] == "decided" and gates[name]["value"] is True
    ]
    if reasons:
        return {"status": "human_review", "reasons": reasons}

    redacted = gates["redact"]["value"] is True
    out, masks = mask(text) if redacted else (text, {})
    return {
        "status": "routed",
        "department": gates["route"]["value"],
        "redacted": redacted,
        "message": out,
        "masks": masks,
    }


def gate_summary(gates: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """The per-gate numbers worth showing a caller: value, probability, outcome."""
    return {
        name: {"value": g["value"], "p": None if g["p"] is None else round(g["p"], 3), "outcome": g["outcome"]}
        for name, g in gates.items()
    }

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


def _r(x: Any) -> Any:
    return None if x is None else round(float(x), 3)


def gate_summary(gates: dict[str, dict[str, Any]], spec: dict[str, dict[str, Any]] | None = None) -> dict[str, Any]:
    """The per-gate numbers worth showing a caller: value, probability, outcome, and
    (from the compiled circuit, `spec`) the rule it was held to: op, tau, band, min_confidence."""
    out = {}
    for name, g in gates.items():
        s = {"value": g["value"], "p": _r(g["p"]), "outcome": g["outcome"]}
        if g.get("confidence") is not None:
            s["confidence"] = _r(g["confidence"])
        rule = (spec or {}).get(name)
        if rule:
            s["rule"] = {k: rule[k] for k in ("op", "tau", "band", "min_confidence") if k in rule}
        out[name] = s
    return out


def answer_summary(answers: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """What the model answered, as plain numbers: P(yes) for a noul, a distribution otherwise."""
    out: dict[str, Any] = {}
    for qid, a in answers.items():
        if a.get("type") == "noul":
            out[qid] = {"type": "noul", "p": _r(a["noul"])}
        elif "probabilities" in a:
            out[qid] = {"type": a.get("type"), "probabilities": {k: _r(v) for k, v in a["probabilities"].items()}}
    return out

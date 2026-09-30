"""Offline tests: hand-written answers, the real gates. No model, no AWS.

Run: pip install -r requirements-dev.txt && pytest
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lambda"))

from circuit import REVIEW_WHEN_TRUE, c  # noqa: E402
from decide import decide  # noqa: E402
from redact import WITHHELD, mask  # noqa: E402
from decision_circuits.types import answer_from_probabilities  # noqa: E402


def answers(pii: float, business: float, dept: dict[str, float], **nouls: float) -> dict:
    a = {
        "pii": {"type": "noul", "noul": pii},
        "business": {"type": "noul", "noul": business},
        "dept": answer_from_probabilities(c.questions["dept"], dept),
    }
    a.update({k: {"type": "noul", "noul": v} for k, v in nouls.items()})
    return a


BILLING = {"billing": 0.94, "technical": 0.04, "other": 0.02}


def test_routine_billing_is_routed_untouched():
    text = "How do I download last month's invoice?"
    d = decide(text, c.evaluate(answers(0.03, 0.1, BILLING)))
    assert d == {"status": "routed", "department": "billing", "redacted": False, "message": text, "masks": {}}


def test_account_number_is_redacted_and_routed():
    text = "Please refund me, my account number is 4417-2290-118 and email jo@example.com"
    d = decide(text, c.evaluate(answers(0.97, 0.03, BILLING)))
    assert d["status"] == "routed" and d["redacted"] is True
    assert "4417" not in d["message"] and "jo@example.com" not in d["message"]
    assert d["message"].startswith("Please refund me, my account number is [ACCOUNT]")


def test_business_details_are_not_redacted():
    d = decide("Acme Corp, account 88812345, invoice is wrong", c.evaluate(answers(0.9, 0.95, BILLING)))
    assert d["status"] == "routed" and d["redacted"] is False


def test_borderline_pii_escalates():
    d = decide("Is it ok if I send you my details?", c.evaluate(answers(0.66, 0.05, BILLING)))
    assert d["status"] == "human_review"
    assert [r["gate"] for r in d["reasons"]] == ["redact"]


def test_unsure_department_goes_to_review():
    flat = {"billing": 0.36, "technical": 0.33, "other": 0.31}
    d = decide("hello?", c.evaluate(answers(0.02, 0.1, flat)))
    assert d["status"] == "human_review"
    assert "route" in [r["gate"] for r in d["reasons"]]


def test_model_says_pii_but_no_pattern_withholds_body():
    assert mask("My neighbour Jane Doe lives on Elm Street") == (WITHHELD, {"WITHHELD": 1})


@pytest.mark.parametrize(
    "text, rule",
    [
        ("card 4111 1111 1111 1111 please", "CARD"),
        ("call 804-555-0142", "PHONE"),
        ("ssn 123-45-6789", "SSN"),
        ("acct# 99381122", "ACCOUNT"),
        ("reference 7734912", "NUMBER"),
    ],
)
def test_mask_rules(text, rule):
    out, counts = mask(text)
    assert rule in counts and not any(ch.isdigit() for ch in out)


def test_review_gates_exist():
    names = {g.name for g in c.gates}
    assert set(REVIEW_WHEN_TRUE) <= names, "every REVIEW_WHEN_TRUE entry must name a gate"


def test_stage_change_angry_customer(monkeypatch):
    """The live-coded change, applied to a copy: three lines in circuit.py."""
    import copy

    import decide as decide_mod
    from decision_circuits import Q

    c2 = copy.deepcopy(c)
    c2.noul("angry", "Is the customer angry?")
    c2.gate("angry_to_human", Q("angry") >= 0.7, on_uncertain="escalate")
    monkeypatch.setattr(decide_mod, "REVIEW_WHEN_TRUE", ["angry_to_human"])

    text = "This is the THIRD time you've double charged me. Fix it now."
    furious = decide_mod.decide(text, c2.evaluate(answers(0.03, 0.1, BILLING, angry=0.93)))
    assert furious["status"] == "human_review"
    assert furious["reasons"][0]["gate"] == "angry_to_human" and furious["reasons"][0]["outcome"] == "flagged"

    calm = decide_mod.decide("How do I get an invoice?", c2.evaluate(answers(0.03, 0.1, BILLING, angry=0.04)))
    assert calm["status"] == "routed"

"""The decision circuit. This is the only file you edit on stage.

Questions are what we ask the model; it answers each with a calibrated
probability in one pass, and never sees the gates. Gates are plain code
over those probabilities: versionable, testable offline, auditable.

Any gate that isn't "decided" (it abstained or escalated) sends the
message to human review. So does any gate listed in REVIEW_WHEN_TRUE
when it decides True.
"""

from decision_circuits import Circuit, Q, argmax

VERSION = "v1"

c = Circuit()

# ---- questions ---------------------------------------------------------
c.noul(
    "pii",
    "Does this message contain personal information about a private individual?",
    true="A person's account or card number, email, phone, home address, SSN or date of birth",
    false="No personal details, or only details about a company",
)
c.noul(
    "business",
    "Are the identifying details in this message about a business, not a person?",
)
c.choice(
    "dept",
    "Which support team should handle this message?",
    {
        "billing": "Charges, refunds, invoices, payment methods, plans",
        "technical": "Bugs, errors, outages, login problems, integrations",
        "other": None,
    },
)

# ---- gates -------------------------------------------------------------
c.gate("redact", (Q("pii") & ~Q("business")) >= 0.6, band=0.1, on_uncertain="escalate")
c.gate("route", argmax("dept", min_confidence=0.35))

# Gates whose decided True value means "a human should see this".
REVIEW_WHEN_TRUE: list[str] = []

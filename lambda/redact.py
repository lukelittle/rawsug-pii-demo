"""Deterministic masking, applied only after the circuit's `redact` gate decides True.

The model decides WHETHER a message carries personal data; these patterns
decide WHICH characters to mask. Nothing here is generated. If the gate
fires but no pattern matches (a name and street address in prose, say),
the whole body is withheld rather than passed through.
"""

from __future__ import annotations

import re

WITHHELD = "[WITHHELD: personal information detected; no maskable pattern found]"


def _luhn_ok(digits: str) -> bool:
    total, parity = 0, len(digits) % 2
    for i, ch in enumerate(digits):
        d = int(ch)
        if i % 2 == parity:
            d = d * 2 - 9 if d > 4 else d * 2
        total += d
    return total % 10 == 0


def _card(m: re.Match[str]) -> str | None:
    digits = re.sub(r"\D", "", m.group(0))
    return "[CARD]" if 13 <= len(digits) <= 19 and _luhn_ok(digits) else None


# Order matters: the specific shapes go before the catch-all digit run.
RULES: list[tuple[str, re.Pattern[str], object]] = [
    ("EMAIL", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"), "[EMAIL]"),
    ("SSN", re.compile(r"\b\d{3}-\d{2}-\d{4}\b"), "[SSN]"),
    ("CARD", re.compile(r"\b(?:\d[ -]?){12,18}\d\b"), _card),
    ("PHONE", re.compile(r"(?:\+?1[ .-]?)?\(?\b\d{3}\)?[ .-]\d{3}[ .-]\d{4}\b"), "[PHONE]"),
    (
        "ACCOUNT",
        re.compile(r"(?i)(\b(?:acct|account)(?:\s*(?:number|no\.?|#))?(?:\s+is)?[\s:#]*)([a-z0-9-]*\d[a-z0-9-]{3,})"),
        lambda m: m.group(1) + "[ACCOUNT]",
    ),
    ("NUMBER", re.compile(r"\b\d{6,}\b"), "[NUMBER]"),
]


def mask(text: str) -> tuple[str, dict[str, int]]:
    """(masked text, {rule: count}). Withholds the body when nothing matched."""
    counts: dict[str, int] = {}
    for name, pattern, repl in RULES:

        def sub(m: re.Match[str], name: str = name, repl: object = repl) -> str:
            out = repl(m) if callable(repl) else repl
            if out is None:
                return m.group(0)
            counts[name] = counts.get(name, 0) + 1
            return out  # type: ignore[return-value]

        text = pattern.sub(sub, text)
    if not counts:
        return WITHHELD, {"WITHHELD": 1}
    return text, counts

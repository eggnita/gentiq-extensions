"""Shared `Remark` type and confidence-aggregation logic.

Any step in the file-handler subsystem can emit remarks: triage, parsers,
BKO builders, validators, an LLM classifier, future steps. A remark says
"something here is noteworthy — here's the human-readable text and here's
how noteworthy on a 1–100 scale".

Producers never compute confidence themselves. The orchestrator (the
production CLI entry point, or a test/validation script like
`validate_vouchers.py` playing that role) collects all remarks emitted
during a file's lifecycle and calls `compute_confidence(remarks)` once.

This split keeps each producer simple — it knows only its own context —
and concentrates the aggregation policy in a single, swappable function.

Confidence formula
------------------
For each remark `r`, compute a confidence factor `(100 − r.scalar) / 100`,
then take the product of all factors:

    confidence = ∏ (100 − r.scalar) / 100   for r in remarks

Properties of this multiplicative form (vs an additive sum):
  - Probabilistic interpretation: each remark is an independent "doubt";
    confidence is the joint probability that none of them matters.
  - Single severe remark dominates but never artificially zeros the
    signal — `scalar=90` gives 0.10, not 0.
  - Many small remarks degrade smoothly — five `scalar=10` remarks give
    `0.9⁵ ≈ 0.59`, not 0.5.
  - Order-independent.

Worked examples
---------------
  []                                 → 1.00
  [Remark(scalar=10)]                → 0.90
  [Remark(scalar=10), Remark(s=10)]  → 0.81
  [Remark(scalar=30), Remark(s=50)]  → 0.7 × 0.5 = 0.35
  [Remark(scalar=90)]                → 0.10
  [Remark(scalar=100)]               → 0.00
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Sequence


@dataclass(frozen=True)
class Remark:
    """One observation worth recording.

    Attributes
    ----------
    text   : human-readable description of what's noteworthy
    scalar : 1–100, larger = more remarkable (clamped at compute time)
    id     : optional stable identifier so dev tooling can aggregate
             "the same kind" of remark across many files. Producers that
             emit a remark repeatedly should give it an id; one-off
             observations (e.g. a freeform LLM note) can leave it None.
    """
    text: str
    scalar: int
    id: Optional[str] = None


def compute_confidence(remarks: Sequence[Remark]) -> float:
    """Multiplicative confidence aggregation. See module docstring."""
    conf = 1.0
    for r in remarks:
        s = max(0, min(100, r.scalar))  # defensive clamp
        conf *= (100 - s) / 100.0
    return max(0.0, conf)

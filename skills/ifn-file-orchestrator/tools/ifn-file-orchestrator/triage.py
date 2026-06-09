"""Triage — routes a bookkeeping-supporting document to its handling strategy.

See [`TriageOmniStrategy.md`](TriageOmniStrategy.md) for the full design
contract. This module is the implementation; that document is the spec.

Given a supporting file (a PDF, XLS, image, etc. that supports a bookkeeping
event), decide:
  1. Is the file recognised? (outcome: deterministic / llm_fallback / unsupported)
  2. If deterministic, WHICH strategy applies? Each strategy names a different
     post-parse workflow:
       - `parse_and_build_bko` — parse → build a BKO entity for `ifn staging propose`.
         Needs (parser_module, builder_module). Used by combo-invoice.
       - `parse_and_attach_to_voucher` — parse → look up an existing voucher via
         CLI by parsed fields → attach this file to it. No BKO produced.
         Needs (parser_module, attach_lookup_keys). Used by Payment Advice.

The aim is that EVERY recognised document type has a deterministic strategy
(see `project_runtime_and_format_roadmap` memory). LLM is a fallback for
formats we don't yet recognise.

--------------------------------------------------------------------------
API
--------------------------------------------------------------------------
    triage(
        filename: str,
        content: bytes | BinaryIO | None = None,
        prior_metadata: dict | None = None,
        prior_log: tuple[RoundEvent, ...] | None = None,
        prior_remarks: tuple[Remark, ...] | None = None,
    ) -> TriageResult

`filename` is required (today's primary key). `content` is reserved for
content-based disambiguation when filename alone is ambiguous.

`prior_metadata`, `prior_log`, and `prior_remarks` enable round-trippable
inputs per TriageOmniStrategy.md §4 — supplying them is how an external
orchestrator will eventually drive the iterative triage loop. They are
accepted today so callers can start building the loop on the outside;
the recursion semantics themselves (LLM-fallback execution, terminal vs
intermediate labels, batch grouping) are later migration steps —
see TriageOmniStrategy.md §Migration.

Triage does NOT compute confidence. It emits `Remark`s when something is
noteworthy; the orchestrator (or a test/validation script playing that
role) collects remarks from every step and calls
`remarks.compute_confidence(...)` once at the end. See `remarks.py`.

Files do NOT have to live on the filesystem — production usage passes
bytes/streams.

Triage is routing ONLY — fetching files, scheduling, and post-BKO file
metadata write-back are higher-orchestrator concerns (see
`project_orchestration_layering` memory).

--------------------------------------------------------------------------
Strategy constants
--------------------------------------------------------------------------
Importable so orchestrators can branch by string match without typos.
"""
from __future__ import annotations

import re
import time
from dataclasses import dataclass, field
from typing import BinaryIO, Callable, Optional

from remarks import Remark


TRIAGE_VERSION = "v0.5-distributed-remarks"

# Outcome values — the routing signal. (TriageOmniStrategy.md §Migration
# notes that these will be promoted to the richer terminal/intermediate
# label taxonomy in later migration steps.)
OUTCOME_DETERMINISTIC = "deterministic"
OUTCOME_LLM_FALLBACK = "llm_fallback"
OUTCOME_UNSUPPORTED = "unsupported"

# Strategy values — what to DO once a file is routed. Only meaningful when
# outcome == "deterministic". Add a new strategy here, then add the matching
# branch in the orchestrator (validate_vouchers.py).
STRATEGY_PARSE_AND_BUILD_BKO = "parse_and_build_bko"
STRATEGY_PARSE_AND_ATTACH = "parse_and_attach_to_voucher"

# Triage-local remark vocabulary.
#
# Each step in the file-handler subsystem maintains its own set of stable
# Remark IDs for things it might emit repeatedly. These are TRIAGE'S — when
# parsers / builders / LLM-classifier start emitting remarks of their own,
# they'll keep their own constants alongside their own code (no global
# catalog). The scalars below are policy and are mirrored in
# TriageOmniStrategy.md §6 — keep them in lockstep.
REMARK_NO_DETERMINISTIC_PARSER = "NO_DETERMINISTIC_PARSER"
REMARK_MULTIPLE_CANDIDATE_FORMATS = "MULTIPLE_CANDIDATE_FORMATS"
REMARK_LLM_CLASSIFIER_USED = "LLM_CLASSIFIER_USED"
REMARK_LLM_BKO_PROPOSED = "LLM_BKO_PROPOSED"
REMARK_LLM_CLASSIFIER_INCONCLUSIVE = "LLM_CLASSIFIER_INCONCLUSIVE"
REMARK_BATCH_GROUPING_UNRESOLVED = "BATCH_GROUPING_UNRESOLVED"

TRIAGE_REMARK_SCALARS: dict[str, int] = {
    REMARK_NO_DETERMINISTIC_PARSER: 10,
    REMARK_MULTIPLE_CANDIDATE_FORMATS: 15,
    REMARK_LLM_CLASSIFIER_USED: 30,
    REMARK_LLM_BKO_PROPOSED: 50,
    REMARK_LLM_CLASSIFIER_INCONCLUSIVE: 25,
    REMARK_BATCH_GROUPING_UNRESOLVED: 20,
}

PathOutcome = str  # one of OUTCOME_* above


@dataclass(frozen=True)
class RoundEvent:
    """One row in the event log — one per triage round for a given file."""
    round_n: int
    timestamp: float
    decision: str                              # outcome (today) or label (later)
    remarks_added: tuple[Remark, ...] = ()     # Remarks emitted this round


@dataclass(frozen=True)
class TriageResult:
    outcome: PathOutcome
    doc_type: Optional[str] = None
    strategy: Optional[str] = None              # one of STRATEGY_* (when outcome == deterministic)
    parser_module: Optional[str] = None         # required for any deterministic strategy
    builder_module: Optional[str] = None        # only for parse_and_build_bko
    attach_lookup_keys: tuple[str, ...] = ()    # only for parse_and_attach_to_voucher;
                                                  # dotted JSON-paths into parsed data
                                                  # that name fields to look up the voucher by
    reason: str = ""
    matched_rule: Optional[str] = None
    # Round-trippable + uncertainty trail (TriageOmniStrategy.md §4).
    # `metadata` is treated as immutable by convention — don't mutate it after
    # construction; we use plain dict for ergonomics rather than a frozen view.
    # `remarks` is the accumulated remark trail; confidence is NOT a field
    # here — orchestrators call `remarks.compute_confidence(r.remarks)`.
    metadata: dict = field(default_factory=dict)
    log: tuple[RoundEvent, ...] = ()
    remarks: tuple[Remark, ...] = ()


# Filename matchers — keep ordered, first match wins.
# v0.3: tolerate an optional " (N)" suffix that the ERP web UI appends
# when a file is downloaded more than once (e.g.
#   "Faktureringsdokument - 7002454489 (1).pdf").
# Without this, manually-downloaded duplicates fall through to llm_fallback.
_RE_FOODORA_COMBO = re.compile(
    r"^Faktureringsdokument - \d+(?:\s*\(\d+\))?\.pdf$",
    re.IGNORECASE,
)
_RE_FOODORA_PAYMENT_ADVICE = re.compile(r"^Payment Advice Note from .*\.PDF$", re.IGNORECASE)
_RE_XLS = re.compile(r"\.xlsx?$", re.IGNORECASE)


@dataclass(frozen=True)
class _Rule:
    name: str
    matches: Callable[[str], bool]
    outcome: PathOutcome
    doc_type: Optional[str] = None
    strategy: Optional[str] = None
    parser_module: Optional[str] = None
    builder_module: Optional[str] = None
    attach_lookup_keys: tuple[str, ...] = ()
    reason: str = ""


TRIAGE_RULES: list[_Rule] = [
    _Rule(
        name="foodora_combo_invoice",
        matches=lambda fn: bool(_RE_FOODORA_COMBO.match(fn)),
        outcome=OUTCOME_DETERMINISTIC,
        doc_type="foodora_combo_invoice",
        strategy=STRATEGY_PARSE_AND_BUILD_BKO,
        parser_module="parsers.foodora_combo_invoice",
        builder_module="bko_builders.foodora_combo_invoice",
        reason="filename matches Faktureringsdokument - <number>.pdf",
    ),
    _Rule(
        name="foodora_payment_advice",
        matches=lambda fn: bool(_RE_FOODORA_PAYMENT_ADVICE.match(fn)),
        outcome=OUTCOME_DETERMINISTIC,
        doc_type="foodora_payment_advice",
        strategy=STRATEGY_PARSE_AND_ATTACH,
        parser_module="parsers.foodora_payment_advice",
        # PA references the combi-invoice number; the orchestrator's CLI
        # lookup finds the matching voucher by that key (see
        # project_foodora_payment_advice memory).
        attach_lookup_keys=("comboInvoice.invoiceNo",),
        reason=("Foodora payment advice — parse to extract the referenced "
                "combi-invoice number, then look up the matching voucher "
                "and attach this file. Does not produce its own BKO."),
    ),
    _Rule(
        name="xls_file",
        matches=lambda fn: bool(_RE_XLS.search(fn)),
        outcome=OUTCOME_UNSUPPORTED,
        reason="XLS files (Foodora order detail or other partner exports) — no parser registered yet",
    ),
]


def _emit(remark_id: str, text: str) -> Remark:
    """Construct a Remark using one of triage's canonical scalar values."""
    return Remark(text=text, scalar=TRIAGE_REMARK_SCALARS[remark_id], id=remark_id)


def triage(
    filename: str,
    content: bytes | BinaryIO | None = None,
    prior_metadata: Optional[dict] = None,
    prior_log: Optional[tuple[RoundEvent, ...]] = None,
    prior_remarks: Optional[tuple[Remark, ...]] = None,
) -> TriageResult:
    """Decide how a supporting document should be handled.

    Returns a TriageResult with outcome in {deterministic, llm_fallback, unsupported}.
    `content` is accepted but unused today — reserved for content-based disambiguation
    when filename rules grow ambiguous.

    `prior_metadata`, `prior_log`, and `prior_remarks` accumulate across rounds
    when an external orchestrator drives the iterative loop. On round 1 they
    are typically omitted; on round N they carry forward whatever the previous
    rounds produced. See TriageOmniStrategy.md §7.
    """
    del content  # reserved for future content-sniffing rules
    metadata = dict(prior_metadata) if prior_metadata else {}
    prior_log_t: tuple[RoundEvent, ...] = tuple(prior_log) if prior_log else ()
    prior_remarks_t: tuple[Remark, ...] = tuple(prior_remarks) if prior_remarks else ()
    round_n = len(prior_log_t) + 1

    new_remarks: list[Remark] = []

    if not filename:
        return _build_result(
            outcome=OUTCOME_UNSUPPORTED,
            reason="empty filename",
            metadata=metadata,
            prior_log=prior_log_t,
            prior_remarks=prior_remarks_t,
            round_n=round_n,
            new_remarks=tuple(new_remarks),
        )

    for rule in TRIAGE_RULES:
        if rule.matches(filename):
            return _build_result(
                outcome=rule.outcome,
                doc_type=rule.doc_type,
                strategy=rule.strategy,
                parser_module=rule.parser_module,
                builder_module=rule.builder_module,
                attach_lookup_keys=rule.attach_lookup_keys,
                reason=rule.reason,
                matched_rule=rule.name,
                metadata=metadata,
                prior_log=prior_log_t,
                prior_remarks=prior_remarks_t,
                round_n=round_n,
                new_remarks=tuple(new_remarks),
            )

    # No filename rule matched — defer to LLM-based reasoning (the orchestrator
    # will invoke the LLM step and re-enter triage with the enriched metadata).
    new_remarks.append(_emit(
        REMARK_NO_DETERMINISTIC_PARSER,
        text=f"No deterministic parser matched filename {filename!r} in triage {TRIAGE_VERSION}",
    ))
    return _build_result(
        outcome=OUTCOME_LLM_FALLBACK,
        reason="no registered rule matched this filename — defer to LLM-based reasoning",
        metadata=metadata,
        prior_log=prior_log_t,
        prior_remarks=prior_remarks_t,
        round_n=round_n,
        new_remarks=tuple(new_remarks),
    )


def _build_result(
    *,
    outcome: str,
    metadata: dict,
    prior_log: tuple[RoundEvent, ...],
    prior_remarks: tuple[Remark, ...],
    round_n: int,
    new_remarks: tuple[Remark, ...],
    doc_type: Optional[str] = None,
    strategy: Optional[str] = None,
    parser_module: Optional[str] = None,
    builder_module: Optional[str] = None,
    attach_lookup_keys: tuple[str, ...] = (),
    reason: str = "",
    matched_rule: Optional[str] = None,
) -> TriageResult:
    decision = strategy or outcome
    event = RoundEvent(
        round_n=round_n,
        timestamp=time.time(),
        decision=decision,
        remarks_added=new_remarks,
    )
    return TriageResult(
        outcome=outcome,
        doc_type=doc_type,
        strategy=strategy,
        parser_module=parser_module,
        builder_module=builder_module,
        attach_lookup_keys=attach_lookup_keys,
        reason=reason,
        matched_rule=matched_rule,
        metadata=metadata,
        log=prior_log + (event,),
        remarks=prior_remarks + new_remarks,
    )


def main(argv: list[str] | None = None) -> int:
    """CLI for ad-hoc triage. Reads filenames from argv or stdin, prints decisions.

    For ad-hoc display the CLI plays orchestrator: it calls
    `remarks.compute_confidence` on the triage-only remark set so a single
    confidence column makes sense. Production orchestrators would aggregate
    across parser + builder + validator remarks too.
    """
    import argparse
    import json
    import sys
    from remarks import compute_confidence
    parser = argparse.ArgumentParser(description="Triage bookkeeping-support docs.")
    parser.add_argument("filenames", nargs="*",
                        help="One or more filenames to triage. If empty, reads stdin (one per line).")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of plain text.")
    args = parser.parse_args(argv)

    names = args.filenames or [line.strip() for line in sys.stdin if line.strip()]
    out = []
    for fn in names:
        r = triage(fn)
        out.append({
            "filename": fn,
            "outcome": r.outcome,
            "doc_type": r.doc_type,
            "strategy": r.strategy,
            "parser_module": r.parser_module,
            "builder_module": r.builder_module,
            "attach_lookup_keys": list(r.attach_lookup_keys),
            "matched_rule": r.matched_rule,
            "reason": r.reason,
            "triage_only_confidence": compute_confidence(r.remarks),
            "remarks": [{"id": rem.id, "scalar": rem.scalar, "text": rem.text} for rem in r.remarks],
            "round_count": len(r.log),
        })
    if args.json:
        json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        for o in out:
            strat = o['strategy'] or '-'
            conf = f"{o['triage_only_confidence']:.2f}"
            print(f"{o['filename']:60} → {o['outcome']:14} {strat:30} {o['doc_type'] or '-':28} triage_conf={conf}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

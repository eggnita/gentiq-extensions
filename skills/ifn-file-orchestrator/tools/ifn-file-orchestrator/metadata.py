"""Helpers for writing file metadata via `ifn files metadata`.

The IFN CLI exposes three writable fields per file:

  --category <string>      (free-form tag — e.g. "foodora_payment_advice")
  --group-id <uuid>        (grouping mechanism — files sharing a group_id
                            belong together)
  --details <text>          (free text; we use it as a JSON blob to track
                            triage / parse / attach state across runs)

This module:
  1. Provides `group_id_for(company_id, invoice_no)` to mint a STABLE
     UUIDv5 per (company × Foodora invoice no) pair, so the orchestrator
     can find related files (combo-invoice, PA, XLS detail) without a
     prior lookup.
  2. Defines the JSON shape we write into `--details`, plus serialisation
     helpers.

The orchestrator-side write calls (`ifn files metadata ...`) are not
implemented in this module yet — see TODO.md. The shape + group-id
machinery is here so the orchestrator can land later without re-designing.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


# Namespace for our deterministic group ids. The standard NAMESPACE_DNS /
# NAMESPACE_URL etc. wouldn't conflict, but using our own keeps generated
# ids clearly attributable to this project. The exact UUID below was picked
# once and must never change — if you change it, every existing file's
# computed group_id changes and the orchestrator's lookups break.
GROUP_ID_NAMESPACE = uuid.UUID("0d59bf1c-5e07-5b1f-8c8a-5b3f7e2a0a01")


def group_id_for(company_id: str, invoice_no: str) -> str:
    """Stable group id for all files belonging to one Foodora invoice on
    one company. Deterministic — same inputs always yield the same UUID,
    so the orchestrator can compute it on the fly without first listing
    existing files to see whether a group exists.

    Note: this is a NEW namespace. Files already grouped under a different
    (manually-assigned) UUID in IFN are unaffected; the orchestrator can
    reconcile by checking for an existing group_id on the combo-invoice
    file before writing one we minted.
    """
    name = f"{company_id}::{invoice_no}"
    return str(uuid.uuid5(GROUP_ID_NAMESPACE, name))


# ---- Category constants ----------------------------------------------------
# Free-form strings on IFN's side; we keep them explicit here so call sites
# don't drift on spelling.

CATEGORY_FOODORA_COMBO_INVOICE = "foodora_combo_invoice"
CATEGORY_FOODORA_PAYMENT_ADVICE = "foodora_payment_advice"
CATEGORY_MANUAL_REVIEW = "manual_review"


# ---- Details JSON schema ---------------------------------------------------
# Written into the `--details` text field. The orchestrator reads it back,
# updates it, and writes again on each scan. Avoid making this huge — keep
# it under a few KB.

# Schema version. Bump if we make a backwards-incompatible change to the
# JSON shape so older orchestrator runs can detect and migrate.
DETAILS_SCHEMA_VERSION = 1


@dataclass
class TriageRecord:
    outcome: str
    strategy: str | None
    rule: str | None
    version: str
    at: str  # ISO timestamp


@dataclass
class ParserRecord:
    module: str
    version: str
    at: str  # ISO timestamp
    extracted: dict[str, Any] = field(default_factory=dict)


@dataclass
class AttemptRecord:
    at: str
    step: str
    outcome: str          # "ok" | "not_found" | "error" | ...
    note: str | None = None


@dataclass
class FileDetails:
    """The full JSON we write into `--details`.

    next_step  is the orchestrator's todo for this file. When None or "done",
               the orchestrator should skip this file in future scans (it has
               nothing left to do).

    expected_match_after  is a date hint that lets the orchestrator avoid
                          fruitless lookups before this date — e.g. for a PA
                          waiting on a bank arrival, set to combo.dueDate.
    """
    schema_version: int = DETAILS_SCHEMA_VERSION
    triage: TriageRecord | None = None
    parser: ParserRecord | None = None
    next_step: str | None = None
    expected_match_after: str | None = None     # YYYY-MM-DD
    attempts: list[AttemptRecord] = field(default_factory=list)
    completed_at: str | None = None             # ISO timestamp; None == still in-flight


# next_step values — keep explicit so the orchestrator's branches don't typo.
NEXT_STEP_LOOKUP_VOUCHER_BY_INVOICE_NO = "lookup_voucher_by_invoice_no"
NEXT_STEP_LOOKUP_VOUCHER_BY_DATE_AMOUNT = "lookup_voucher_by_date_amount"
NEXT_STEP_ATTACH_TO_VOUCHER = "attach_to_voucher"
NEXT_STEP_AWAIT_BANK_ARRIVAL = "await_bank_arrival"
NEXT_STEP_DONE = "done"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def to_json(details: FileDetails) -> str:
    """Render a FileDetails as the JSON string we pass to `--details`."""
    def _ser(o: Any) -> Any:
        if hasattr(o, "__dict__"):
            return {k: v for k, v in o.__dict__.items() if v is not None or k == "extracted"}
        raise TypeError(f"not serialisable: {type(o)}")
    return json.dumps(details, default=_ser, separators=(",", ":"), ensure_ascii=False)


def from_json(raw: str) -> FileDetails:
    """Parse a JSON string from `--details` back into a FileDetails.

    Tolerant of partial / older shapes — missing fields become None / [].
    """
    data = json.loads(raw)
    fd = FileDetails(schema_version=data.get("schema_version", DETAILS_SCHEMA_VERSION))
    if "triage" in data and data["triage"]:
        fd.triage = TriageRecord(**data["triage"])
    if "parser" in data and data["parser"]:
        fd.parser = ParserRecord(**data["parser"])
    fd.next_step = data.get("next_step")
    fd.expected_match_after = data.get("expected_match_after")
    fd.attempts = [AttemptRecord(**a) for a in data.get("attempts") or []]
    fd.completed_at = data.get("completed_at")
    return fd

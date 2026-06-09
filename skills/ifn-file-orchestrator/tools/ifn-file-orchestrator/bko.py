"""Shared contract between format-agnostic orchestrators and the
format-specific parser + BKO builder modules.

Every supported format provides two modules:

  parsers/<format>.py
      PARSER_VERSION: str             # bumped on schema-breaking changes
      parse(source) -> ParseResult    # ParseResult = {data, errors, pagesScanned}
                                       # `source` accepts Path | str | bytes | BinaryIO

  bko_builders/<format>.py
      BUILDER_VERSION: str            # bumped when booking rules change behavior
      build_bko(data, BuildInput) -> BKO

The orchestrator (today: `validate_vouchers.py`; in production: the IFN CLI
trigger that fires when a new supporting doc arrives) dispatches via dotted
module names returned by `triage.triage()` and depends only on this contract.
Adding a new format means writing those two modules + a triage rule — no
changes to the orchestrator or to this file.

BuildInput lives here (not in each builder) so the orchestrator constructs a
single, known shape regardless of which builder it dispatches to.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, BinaryIO, Union

# Type aliases — kept loose so format-specific code can attach extra fields
# without changing the contract.

# A "supporting document" is any file that supports a bookkeeping event —
# PDF invoices, XLS exports, JSON payloads, images, etc. In production these
# arrive as bytes/streams (from `ifn files fetch`); Path/str are kept as a
# dev/test convenience.
SupportingDoc = Union[Path, str, bytes, BinaryIO]

# ParseResult contract:
#   REQUIRED keys:
#     "data"   : dict  — the extracted structured payload (format-specific shape)
#     "errors" : list[str] — missing-field / parse-failure messages; empty == success
#   OPTIONAL keys:
#     "diagnostics" : dict — format-specific telemetry (e.g. PDF parsers may set
#                            {"pagesScanned": N}; XLS parsers might set
#                            {"sheetsRead": N}; CSV parsers may omit entirely).
#                            Consumed by dev/audit tooling, NOT part of the
#                            production booking path.
ParseResult = dict[str, Any]
BKO = dict[str, Any]            # SKILL.md "Proposing Vouchers" entity


@dataclass
class BuildInput:
    """Inputs every BKO builder receives beyond the parsed data.

    Fields:
        file_refs           — IDs of files already uploaded to IFN (the
                              SKILL.md `file_refs` field).
        financial_year_id   — FY this voucher belongs to (e.g. "7").
        parser_version      — PARSER_VERSION of the parser that produced
                              `data` (recorded in the BKO trace footer).
        triage_version      — TRIAGE_VERSION of the dispatcher that routed
                              this file.
        triage_matched_rule — name of the triage rule that matched; goes
                              into the BKO trace + source provenance.
    """
    file_refs: list[str]
    financial_year_id: str
    parser_version: str = ""
    triage_version: str = ""
    triage_matched_rule: str = ""


# ---- module conformance helpers --------------------------------------------
# Protocols would need wrapper classes to validate modules, so we use simple
# runtime assertions instead — they give better error messages anyway. Use
# from tests or from a startup-time registry check.

def assert_parser_module(mod: Any) -> None:
    """Raise AssertionError if `mod` doesn't satisfy the parser contract."""
    assert hasattr(mod, "PARSER_VERSION"), \
        f"{mod.__name__} must expose PARSER_VERSION: str"
    assert hasattr(mod, "parse"), \
        f"{mod.__name__} must expose parse(source) -> ParseResult"


def assert_builder_module(mod: Any) -> None:
    """Raise AssertionError if `mod` doesn't satisfy the builder contract."""
    assert hasattr(mod, "BUILDER_VERSION"), \
        f"{mod.__name__} must expose BUILDER_VERSION: str"
    assert hasattr(mod, "build_bko"), \
        f"{mod.__name__} must expose build_bko(data, build_input) -> BKO"

# Version should always be amended below, and correspond to the current
# FoodoraComboInvoice_BookingRules.md (cross-referenced by
# tests/test_spec_consistency.py — version slugs must match AND the spec's
# sha256 must match RULES_DOC_SHA256 below).
#
# Procedure when editing the spec or the builder:
#   1. Update BUILDER_VERSION below + the spec's <!-- builder_version: ... --> marker (match).
#   2. Run: python3 tools/refresh_spec_hash.py
#   3. Paste the new sha256 into RULES_DOC_SHA256 below.
#
# Version: v0.20-credit-reversals
"""BKO (bookkeeping order) builder for the Foodora combo-invoice format.

Transforms parsed `data` (from parsers.foodora_combo_invoice) plus per-file
metadata into a Bookkeeping Order entity ready for `ifn staging propose`.

This module is the EXECUTABLE EMBODIMENT of the rules in
`FoodoraComboInvoice_BookingRules.md`. The spec and this code reference each
other deliberately — keep them in lockstep when rules change.

--------------------------------------------------------------------------
BKO output schema — contract with the IFN CLI
--------------------------------------------------------------------------
The dict returned by `build_bko()` is the JSON body that
`ifn staging propose <company_id> <json_file>` expects, defined in
`gentiq-extensions/skills/introspectfn/SKILL.md` ("Proposing Vouchers"
section, ~lines 496-509). Required CLI fields:
  - entity_type        : "voucher"
  - action             : "create"
  - payload.VoucherSeries, payload.TransactionDate, payload.Description
  - payload.VoucherRows: [{Account, Debit, Credit}, ...]
  - accounting_reasoning: text with CERTAINTY/COMPLEXITY/RISK header
  - notes              : prefix "HIGH/MODERATE/LOW CERTAINTY (X%) | <COMPLEXITY> — ..."
  - financial_year_id  : FY id (e.g. "7")
  - target_date        : YYYY-MM-DD (defaults to payload.TransactionDate)
  - file_refs          : [<file_id>, ...] for files already uploaded via
                          `ifn staging upload` (no field yet exists for
                          attaching NEW files in the same call; see
                          project_combi_invoice_followups item 5).

If the CLI schema changes, update this module — the field names below are
intentionally a one-to-one mirror.

Extra fields this builder emits (consumed locally, ignored by the CLI):
  - confidence         : scalar 0.0–1.0 — for downstream autobook rules
  - confidence_signals : structured inputs that drove the scalar (delta,
                          rounding, remark points, etc.)
  - generationMethod   : "deterministic" (vs. "llm" for fallback paths)
  - source             : {parser: {name,version}, builder: {name,version},
                          rules_doc, generated_at}
  - remarks            : graded remark items per the spec
  - balanceCheck       : debit/credit totals and delta for audit

--------------------------------------------------------------------------
Import:
    from bko_builders.foodora_combo_invoice import build_bko, BUILDER_VERSION
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from bko import BKO, BuildInput

BUILDER_VERSION = "v0.20-credit-reversals"
BUILDER_NAME = "foodora_combo_invoice"
RULES_DOC = "FoodoraComboInvoice_BookingRules.md"

# sha256 of the rules-spec markdown (full file contents). Bumped together
# with BUILDER_VERSION whenever the spec is edited — `tests/test_spec_consistency.py`
# enforces this. If the spec is legitimately updated, run
# `python3 tools/refresh_spec_hash.py` to get the new value, then paste it
# here AND bump BUILDER_VERSION + the spec's marker comment together.
RULES_DOC_SHA256 = "8ebabbbb2f445664ce8ebea37a3c2e5858e19d6879d89823a9d854ad9c131f11"

# Rate-keyed account selectors per the rules spec.
SALES_ACCOUNT_BY_RATE: dict[float, int] = {0.25: 3001, 0.12: 3002, 0.06: 3003}
OUTPUT_VAT_ACCOUNT_BY_RATE: dict[float, int] = {0.25: 2611, 0.12: 2621, 0.06: 2631}

BALANCE_TOLERANCE_SEK = 0.20

# Expected contractual rates per discount description. Each "discount" is
# economically a Foodora commission disguised as a discount for VAT reasons —
# all of them are negotiated rates, and a drift signals a contract change.
# v0.13: unknown descriptions now emit a remark too (was silence) — the
# silence default could hide a renamed or new commission type.
#
# - "Rabatt enligt avtal" — standard delivery commission at 21 %.
# - "Rabatt avhämtningsorders" — pickup/takeaway commission at 10 %, used by
#   partners running a Foodora-bar concept (e.g. Brödernas Kållered).
EXPECTED_DISCOUNT_RATES: dict[str, float] = {
    "Rabatt enligt avtal": 0.21,
    "Rabatt avhämtningsorders": 0.10,
    # Mid-period order cancellations: reverses a portion of the "Rabatt
    # enligt avtal" commission that was already deducted. Same 21% rate as
    # the parent commission; positive basis + positive amountExVat (the
    # builder's row emitter flips it to a Credit on the sales account).
    "Minskning av rabatt vid kreditering": 0.21,
}
DISCOUNT_RATE_DEVIATION_THRESHOLD = 0.005  # 0.5 pp; tentative

# Confidence scoring — deterministic builder starts at 1.0 and deducts per signal.
# Thresholds are tentative; revisit per `project_combi_invoice_followups` item 4.
#
# CONFIDENCE_FLOOR    = the minimum score graduated deductions can reach in
#                       the BALANCED case (still "needs review" but possibly
#                       salvageable after human inspection).
# UNBALANCED_CONFIDENCE = a HARD value used when the voucher fails the
#                         balance invariant. Far below any plausible autobook
#                         threshold; signals "do not even try to post".
CONFIDENCE_FLOOR = 0.40
UNBALANCED_CONFIDENCE = 0.10


def _discount_remarks(discs: list[dict]) -> list[dict]:
    """Two checks per contractual discount:
      1. Known description with rate deviation > threshold → "discount-rate-deviation".
      2. Unknown description (not in EXPECTED_DISCOUNT_RATES) → "unknown-discount-type".

    The second covers Foodora introducing a new commission type or renaming
    an existing one — silence on those would let unauthorised charges slip
    through unnoticed (v0.13 fix).
    """
    out: list[dict] = []
    for d in discs:
        rate = d.get("rate")
        desc = d.get("description")
        if rate is None or desc is None:
            continue
        expected = EXPECTED_DISCOUNT_RATES.get(desc)
        if expected is None:
            out.append({
                "code": "unknown-discount-type",
                "points": 20,
                "discount": desc,
                "rate": rate,
                "details": (f"'{desc}' (rate {rate*100:.2f}%) is not in "
                            f"EXPECTED_DISCOUNT_RATES — either a new Foodora "
                            f"commission type or a rename. Confirm with the "
                            f"contract and add to the map."),
            })
            continue
        deviation = abs(rate - expected)
        if deviation > DISCOUNT_RATE_DEVIATION_THRESHOLD:
            out.append({
                "code": "discount-rate-deviation",
                "points": 5,
                "discount": desc,
                "rate": rate,
                "expected": expected,
                "details": (f"'{desc}' rate {rate*100:.2f}% deviates from "
                            f"expected {expected*100:.0f}% by "
                            f"{deviation*100:.2f} pp"),
            })
    return out


def _invariant_remarks(data: dict) -> list[dict]:
    """Cross-check parsed values against arithmetic invariants the source
    document is expected to satisfy. Each failure becomes a remark — the BKO
    is still produced (we have enough data to book), but confidence drops and
    the reviewer sees the discrepancy.

    This is the start of a broader pattern (see TODO.md "Invariant-driven
    remarks"). Additional invariants to add: orders math, discount math,
    foodora-invoice totals, settlement payout reconciliation.
    """
    out: list[dict] = []

    # TODO: real invariants TBD. A first attempt (orders.grossAmount ==
    # totalInclVat) fired on every voucher because totalInclVat is the gross
    # AFTER the rabatt-as-discount net-out in some invoices and equal to
    # gross in others — the exact relationship needs a PDF-semantics study.
    # Capturing the structure so other invariants can be added (per TODO.md
    # "Invariant-driven remarks"); intentionally empty until a verified one
    # exists, so the audit output isn't poisoned by false-positive remarks.
    return out


def _rounding_remark(rounding: float) -> dict | None:
    a = abs(rounding)
    if a > 1000:
        return {"code": "rounding-deviation", "points": 100, "amount": rounding,
                "details": f"|rounding|={a:.2f} > 1000"}
    if a > 100:
        return {"code": "rounding-deviation", "points": 10, "amount": rounding,
                "details": f"|rounding|={a:.2f} > 100"}
    if a > 10:
        return {"code": "rounding-deviation", "points": 1, "amount": rounding,
                "details": f"|rounding|={a:.2f} > 10"}
    if a > 1:
        return {"code": "rounding-deviation", "points": 0, "amount": rounding,
                "details": f"|rounding|={a:.2f} > 1 (note)"}
    return None


def _confidence_score(balance_delta: float, rounding: float,
                      remarks: list[dict]) -> tuple[float, dict]:
    """Map structured signals to a 0.0–1.0 scalar plus the inputs.

    v0.13 hardening: an unbalanced voucher cannot be posted, full stop. So
    when |balance_delta| > tolerance the score is forced low (CONFIDENCE_FLOOR
    = 0.10) regardless of any other deductions. Below that, the score is
    1.0 minus 0.01 per non-rounding remark point, with the rounding
    magnitude treated separately (graduated by SEK magnitude).
    """
    not_balanced = abs(balance_delta) > BALANCE_TOLERANCE_SEK
    if not_balanced:
        score = UNBALANCED_CONFIDENCE  # hard 0.10 — voucher cannot be posted
    else:
        score = 1.0
        a = abs(rounding)
        if a > 100:
            score -= 0.15
        elif a > 10:
            score -= 0.05
        # Non-rounding remark points reduce confidence linearly.
        # rounding-deviation handled by magnitude above; voucher-not-balanced
        # only fires in the not-balanced branch — skip in both cases.
        SKIP = {"rounding-deviation", "voucher-not-balanced"}
        points = sum(r.get("points", 0) for r in remarks if r.get("code") not in SKIP)
        score -= 0.01 * points
        score = max(score, CONFIDENCE_FLOOR)
    signals = {
        "balanceDeltaSek": round(balance_delta, 2),
        "withinBalanceTolerance": not not_balanced,
        "roundingMagnitudeSek": round(rounding, 2),
        "remarkPointsExcludingRounding": sum(
            r.get("points", 0) for r in remarks
            if r.get("code") not in {"rounding-deviation", "voucher-not-balanced"}
        ),
    }
    return round(score, 2), signals


def _confidence_label(score: float) -> tuple[str, int]:
    """Map scalar to SKILL.md-style ('HIGH'/'MODERATE'/'LOW', pct-int)."""
    pct = int(round(score * 100))
    if score >= 0.90:
        return "HIGH", pct
    if score >= 0.70:
        return "MODERATE", pct
    return "LOW", pct


def _build_trace(build_input: BuildInput, generated_at: str) -> str:
    """One-line provenance footer: every component + version + timestamp.

    The builder reference includes a short prefix of the rules-spec sha256
    so a reviewer can verify the spec the BKO was produced against — not
    just the version slug, but the actual document content.

    Format: "TRACE: proposed by booker — triage <name> <ver> (rule: <X>) →
    parser <name> <ver> → builder <name> <ver> [spec sha:<8hex>] @ <ts>".
    """
    spec_sha_short = RULES_DOC_SHA256[:8] if RULES_DOC_SHA256 else "?"
    return (
        f"TRACE: proposed by booker — "
        f"triage triage.py {build_input.triage_version or '?'} "
        f"(rule: {build_input.triage_matched_rule or '?'}) → "
        f"parser parsers.foodora_combo_invoice {build_input.parser_version or '?'} → "
        f"builder bko_builders.{BUILDER_NAME} {BUILDER_VERSION} "
        f"[spec sha:{spec_sha_short}] "
        f"@ {generated_at}"
    )


def _fmt_sek(x: float) -> str:
    """`1234.5` → `"1 234.50"` (thin-space thousands separator, two decimals)."""
    return f"{x:,.2f}".replace(",", " ")


def _build_1584_calc_line(data: dict) -> str:
    """Long-form 1584 K math for `accounting_reasoning`:

        1584 K: <gross[ + gross2…]> (gross) - <payout> (expected payout) = <net> (Foodora's deductions for the period)
    """
    orders = data["selfBilling"]["orders"]
    payout = data["settlement"]["payoutAmount"]
    total_gross = sum(o["grossAmount"] for o in orders)
    if len(orders) == 1:
        gross_expr = _fmt_sek(orders[0]["grossAmount"])
    else:
        gross_expr = " + ".join(_fmt_sek(o["grossAmount"]) for o in orders)
    return (
        f"1584 K: {gross_expr} (gross) - {_fmt_sek(payout)} (expected payout) "
        f"= {_fmt_sek(total_gross - payout)} (Foodora's deductions for the period)"
    )


def _build_1584_calc_short_sv(data: dict) -> str:
    """Candidate B for the voucher COMMENT:

        1584 K = <total_gross> brutto - <payout> utbet = <net> Foodora-avdrag

    Rolled-up totals with inline Swedish labels — short enough to scan in
    a voucher list without losing the math. The per-category breakdown
    stays in `accounting_reasoning` (long form) for a reviewer who wants
    to cross-check against the source self-bill. ASCII hyphen-minus only,
    per the ERP comment-field character constraints.
    """
    orders = data["selfBilling"]["orders"]
    payout = data["settlement"]["payoutAmount"]
    total_gross = sum(o["grossAmount"] for o in orders)
    return (
        f"1584 K = {_fmt_sek(total_gross)} brutto - {_fmt_sek(payout)} utbet "
        f"= {_fmt_sek(total_gross - payout)} Foodora-avdrag"
    )


def _build_reasoning(data: dict, rows: list[dict], balance_delta: float,
                     score: float, remarks: list[dict],
                     build_input: BuildInput, generated_at: str) -> str:
    """Concise BKO reasoning. SKILL.md format header + 1-2 short paragraphs.

    Deliberately not verbose: the deterministic provenance + balance check are
    what a reviewer needs to trust the entry quickly. Long-form context lives
    in the spec doc, not here. Non-rounding remarks (e.g. discount-rate
    deviation) are always called out — they affect whether the BKO can
    auto-post.
    """
    label, pct = _confidence_label(score)
    complexity = "SIMPLE"
    risk = "VERY LOW" if score >= 0.90 else "LOW"

    si = data["selfBilling"]["invoiceNo"]
    fi = data["foodoraInvoice"]["invoiceNo"]
    period = f"{data['orderPeriod']['from']}:{data['orderPeriod']['to']}"
    n_discounts = len(data["selfBilling"]["contractualDiscounts"])
    tolerance_status = (f"within ±{BALANCE_TOLERANCE_SEK:.2f} SEK"
                        if abs(balance_delta) <= BALANCE_TOLERANCE_SEK
                        else f"OUT OF TOLERANCE by {abs(balance_delta)-BALANCE_TOLERANCE_SEK:.2f}")

    payout = data["settlement"]["payoutAmount"]
    due = data["comboInvoice"].get("dueDate") or "?"
    payout_str = _fmt_sek(payout)

    # Net 1584 calculation — surfaced so a reviewer can verify the single
    # 1584 K row matches their own math against the source self-bill, without
    # having to dig into the per-category figures on the PDF. Shared with
    # the notes field so the two stay in sync.
    # ASCII hyphen-minus, not Unicode U+2212 — the audit-PDF font renders
    # the latter as a centered dot.
    net_1584_line = "\n\n" + _build_1584_calc_line(data) + "."

    # Forecast of the future Payment Advance voucher the ERP's bank integration
    # will create when actual payout lands. Date is the combo's dueDate as a
    # hint — actual TransactionDate will be the bank-arrival date.
    payment_advance_forecast = (
        f"\n\nExpecting PaymentAdvance (1930 D {payout_str} SEK, "
        f"1584 K {payout_str} SEK) ca {due}"
    )

    # Balance is normally noiseless: every BKO must balance to be bookable,
    # so silence is the right signal. Only call it out when OUT OF TOLERANCE
    # — that's an alarm a reviewer must see (BKO must not be posted).
    balance_alarm = ""
    if abs(balance_delta) > BALANCE_TOLERANCE_SEK:
        balance_alarm = (
            f"\n\n⚠ NOT BALANCED — Δ {balance_delta:+.2f} SEK "
            f"(> ±{BALANCE_TOLERANCE_SEK:.2f} SEK tolerance). "
            f"DO NOT POST."
        )

    important = [r for r in remarks if r.get("code") != "rounding-deviation"]
    remarks_clause = ""
    if important:
        items = " ".join(f"⚠ {r['code']}: {r['details']}." for r in important)
        remarks_clause = f"\n\nFLAGGED FOR REVIEW: {items}"

    trace = _build_trace(build_input, generated_at)

    # Deliberately terse. The header gives confidence/complexity/risk in the
    # SKILL.md-required form; the body is case-specific facts; balance is
    # only mentioned when out of tolerance (alarms only, no "yes balanced");
    # FLAGGED FOR REVIEW only appears when something needs attention; TRACE
    # provides provenance. File refs are in BKO.file_refs; no need to
    # restate. Rule rationale lives in the spec doc that TRACE cites.
    return (
        f"CERTAINTY: {pct}% | COMPLEXITY: {complexity} | RISK: {risk}\n\n"
        f"Foodora orders {period}, self-billing invoice {si} + Foodora "
        f"invoice {fi}. {len(rows)} rows "
        f"({n_discounts} contractual discount{'s' if n_discounts != 1 else ''})."
        f"{net_1584_line}"
        f"{balance_alarm}"
        f"{payment_advance_forecast}"
        f"{remarks_clause}\n\n"
        f"{trace}"
    )


def _build_notes(data: dict, score: float) -> str:
    """`notes` becomes the voucher COMMENT. Deliberately concise —
    long comments aren't read. Three lines, one per concern:

      1. Bokfört via IFN.                — provenance
      2. 1584 K calc                     — the only non-trivial derived row
      3. Avvaktar bankvoucher …          — heads-up that a payout voucher
                                           is expected but not booked here

    No CERTAINTY header (it lives in accounting_reasoning + the confidence
    scalar). No builder slug (provenance is on accounting_reasoning's
    TRACE footer). No `→` / `−` / `…` — the ERP rejects U+2192 in comment
    fields, so we stay on ASCII + Latin-1.
    """
    payout = data["settlement"]["payoutAmount"]
    due = data["comboInvoice"].get("dueDate") or "?"
    return (
        "Bokfört via IFN.\n"
        f"{_build_1584_calc_short_sv(data)}.\n"
        f"Avvaktar bankvoucher ca {due} "
        f"(1930 D + 1584 K, {_fmt_sek(payout)} kr)."
    )


_REQUIRED_PATHS = (
    ("selfBilling", "invoiceNo"),
    ("selfBilling", "outputVat", "rate"),
    ("selfBilling", "outputVat", "amount"),
    ("foodoraInvoice", "invoiceNo"),
    ("foodoraInvoice", "foodoraFeesExVat"),
    ("foodoraInvoice", "inputVat", "rate"),
    ("foodoraInvoice", "inputVat", "amount"),
    ("orderPeriod", "from"),
    ("orderPeriod", "to"),
    ("settlement", "payoutAmount"),
    ("settlement", "rounding"),
    ("comboInvoice", "date"),
)


def _check_required(data: dict) -> list[str]:
    """Return a list of dotted paths whose value is missing or None.

    Per FoodoraComboInvoice_BookingRules.md "Pre-conditions": the executor
    must NOT post the voucher when any required field is null. The caller
    surfaces this list so an orchestrator can mark the file for manual review.
    """
    missing: list[str] = []
    for path in _REQUIRED_PATHS:
        cur: Any = data
        try:
            for key in path:
                cur = cur[key]
        except (KeyError, TypeError):
            missing.append(".".join(path))
            continue
        if cur is None:
            missing.append(".".join(path))

    # selfBilling.orders is a list (v0.9+ schema); must contain at least one
    # category and each must have grossAmount + netAmount.
    orders = (data.get("selfBilling") or {}).get("orders") or []
    if not orders:
        missing.append("selfBilling.orders[*]")
    for i, o in enumerate(orders):
        for k in ("grossAmount", "netAmount"):
            if o.get(k) is None:
                missing.append(f"selfBilling.orders[{i}].{k}")

    return missing


def build_bko(data: dict, build_input: BuildInput) -> BKO:
    """Transform parsed data + metadata into a BKO entity.

    Raises ValueError if:
      - any required field per the rules spec preamble is missing/None, OR
      - outputVat.rate isn't in the rate-keyed account table.

    The caller must NOT submit a BKO when this raises — surface the issue
    (the ValueError message names the offending field(s) or value) so an
    orchestrator can mark the file for manual review.
    """
    missing = _check_required(data)
    if missing:
        raise ValueError(
            "parsed data is missing required field(s) per "
            f"{RULES_DOC} pre-conditions: {', '.join(missing)}"
        )
    si = data["selfBilling"]["invoiceNo"]
    fi = data["foodoraInvoice"]["invoiceNo"]
    pf = data["orderPeriod"]["from"]
    pt = data["orderPeriod"]["to"]
    out_r = data["selfBilling"]["outputVat"]["rate"]
    out_a = data["selfBilling"]["outputVat"]["amount"]
    in_r = data["foodoraInvoice"]["inputVat"]["rate"]
    in_a = data["foodoraInvoice"]["inputVat"]["amount"]
    # Foodora groups orders by category (Utkörnings = delivery,
    # Avhämtnings = takeaway); the schema is now a list (v0.9 parser).
    # Sum gross/net across all categories — both are absolute amounts in
    # SEK and add cleanly.
    orders_list = data["selfBilling"]["orders"]
    gross = round(sum(o["grossAmount"] for o in orders_list), 2)
    net = round(sum(o["netAmount"] for o in orders_list), 2)
    fees = data["foodoraInvoice"]["foodoraFeesExVat"]
    payout = data["settlement"]["payoutAmount"]
    rnd = data["settlement"]["rounding"]
    discs = data["selfBilling"]["contractualDiscounts"]
    doc_date = data["comboInvoice"]["date"]

    if out_r not in SALES_ACCOUNT_BY_RATE:
        raise ValueError(
            f"unknown outputVat.rate {out_r}; rate-keyed account selectors only cover "
            f"{sorted(SALES_ACCOUNT_BY_RATE)}"
        )
    sales_acct = SALES_ACCOUNT_BY_RATE[out_r]
    output_vat_acct = OUTPUT_VAT_ACCOUNT_BY_RATE[out_r]
    rate_pct = f"{out_r * 100:.0f}"

    # SPLIT recognition voucher (v0.9+): the cash settlement is booked on a
    # separate voucher (created by the ERP's bank integration when actual
    # payment lands) with TransactionDate = bank-arrival date. This pipeline
    # produces only the recognition voucher; the combined effect across both
    # vouchers equals the old integrated form exactly.
    #
    # v0.15 row design: a single `1584 K` row at the NET amount
    # (sum(grossAmount) − payout) — what Foodora withholds as fees,
    # commission, and VAT-on-rabatt for the period. Earlier versions
    # exposed the gross and payout as separate rows (v0.13/14: one K per
    # category + an explicit D at payout); v0.15 collapses them because
    # the net is the only number that's economically meaningful on the
    # recognition voucher. The per-category breakdown is still visible
    # in the source self-bill PDF; surfacing it on the voucher just
    # crowded the row table without changing the books.
    rows: list[dict] = []
    net_1584 = round(gross - payout, 2)
    rows.append({
        "Account": 1584, "Debit": 0, "Credit": net_1584,
        "Description": f"{pf}->{pt}: Foodora fees and commission",
    })
    # v0.14: Faktura (2) "Er utgående moms" line — compensation income.
    # When Foodora gives us a credit (e.g. "Double cooking ersättning") in
    # their invoice section, foodoraFeesExVat is NET of that credit. We
    # recognise the credit as separate income at its own VAT rate:
    #   - 6044 D becomes TRUE Foodora fees = -fees + basis (corrects the
    #     net-of-credit value we'd otherwise book)
    #   - {salesAcct(comp_rate)} K basis — compensation income
    #   - {outputVatAcct(comp_rate)} K amount — output VAT on the income
    # When no compensation line exists, behaviour is identical to v0.13.
    comp = data["foodoraInvoice"].get("outputVat") or {}
    comp_rate = comp.get("rate")
    comp_basis = comp.get("basisAmount")
    comp_amount = comp.get("amount")
    if comp_rate is not None and comp_basis is not None and comp_amount is not None:
        if comp_rate not in SALES_ACCOUNT_BY_RATE:
            raise ValueError(
                f"unknown foodoraInvoice.outputVat.rate {comp_rate}; rate-keyed "
                f"account selectors only cover {sorted(SALES_ACCOUNT_BY_RATE)}"
            )
        comp_sales_acct = SALES_ACCOUNT_BY_RATE[comp_rate]
        comp_vat_acct = OUTPUT_VAT_ACCOUNT_BY_RATE[comp_rate]
        comp_rate_pct = f"{comp_rate * 100:.0f}"
        true_fees = round(-fees + comp_basis, 2)
        rows.extend([
            {"Account": 6044, "Debit": true_fees, "Credit": 0,
             "Description": f"Foodoras avgifter exkl. moms, faktura {fi}"},
            {"Account": 2641, "Debit": round(-in_a, 2), "Credit": 0,
             "Description": f"Er ingående moms {in_r * 100:.0f} %, faktura {fi}"},
            {"Account": comp_sales_acct, "Debit": 0, "Credit": round(comp_basis, 2),
             "Description": f"Foodora ersättning ({comp_rate_pct} %), faktura {fi}"},
            {"Account": comp_vat_acct, "Debit": 0, "Credit": round(comp_amount, 2),
             "Description": f"Utgående moms {comp_rate_pct} % på Foodora ersättning"},
        ])
    else:
        rows.extend([
            {"Account": 6044, "Debit": round(-fees, 2), "Credit": 0,
             "Description": f"Foodoras avgifter exkl. moms, faktura {fi}"},
            {"Account": 2641, "Debit": round(-in_a, 2), "Credit": 0,
             "Description": f"Er ingående moms {in_r * 100:.0f} %, faktura {fi}"},
        ])
    for d in discs:
        amt = d["amountExVat"]
        # Standard commission rows have amountExVat ≤ 0 (Foodora-side negative)
        # and post as Debit on the sales account, reducing recognised sales.
        # Credit-reversal rows (e.g. "Minskning av rabatt vid kreditering")
        # carry a POSITIVE amountExVat — they undo a portion of the commission
        # for mid-period cancellations — and must post as Credit so they ADD
        # back to recognised sales.
        if amt <= 0:
            rows.append({"Account": sales_acct, "Debit": round(-amt, 2), "Credit": 0,
                         "Description": f"{d['description']} på Foodora-försäljning"})
        else:
            rows.append({"Account": sales_acct, "Debit": 0, "Credit": round(amt, 2),
                         "Description": f"{d['description']} på Foodora-försäljning"})
    rows.append({"Account": output_vat_acct,
                 "Debit": round((gross - net) - out_a, 2), "Credit": 0,
                 "Description": f"Utgående moms-justering {rate_pct} % på avtalsrabatten"})
    if rnd >= 0:
        rows.append({"Account": 3740, "Debit": round(rnd, 2), "Credit": 0,
                     "Description": f"Öresavrundning enligt självfaktura {si}"})
    else:
        rows.append({"Account": 3740, "Debit": 0, "Credit": round(-rnd, 2),
                     "Description": f"Öresavrundning enligt självfaktura {si}"})

    debit_total = sum(r["Debit"] for r in rows)
    credit_total = sum(r["Credit"] for r in rows)
    balance_delta = round(debit_total - credit_total, 2)

    remarks: list[dict] = []
    rr = _rounding_remark(rnd)
    if rr:
        remarks.append(rr)
    remarks.extend(_discount_remarks(discs))
    remarks.extend(_invariant_remarks(data))

    # v0.13: an unbalanced voucher must surface loudly. The remark is
    # high-points so any aggregate severity score reflects how serious it is,
    # and the reasoning template will lead with "⚠ NOT BALANCED — DO NOT POST".
    if abs(balance_delta) > BALANCE_TOLERANCE_SEK:
        remarks.append({
            "code": "voucher-not-balanced",
            "points": 100,
            "delta_sek": round(balance_delta, 2),
            "tolerance_sek": BALANCE_TOLERANCE_SEK,
            "details": (f"sum(D) − sum(K) = {balance_delta:+.2f} SEK exceeds the "
                        f"±{BALANCE_TOLERANCE_SEK:.2f} SEK tolerance. The BKO must "
                        f"NOT be posted; surface to a human reviewer."),
        })

    score, signals = _confidence_score(balance_delta, rnd, remarks)
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    reasoning = _build_reasoning(data, rows, balance_delta, score, remarks,
                                 build_input, generated_at)
    notes = _build_notes(data, score)

    # Voucher Description (voucher-list header line). Period FIRST so the
    # voucher list sorts naturally by period when sorted on Description;
    # `7002661998` is the bare combo-invoice number (the self-billing
    # partition `-1` is internal Foodora notation, not useful for a
    # human reviewer).
    # The expected-payout figure lives in command.erp_payload.Comments only —
    # it was crowding this line. ISO dates throughout.
    # The ERP rejects U+2192 in voucher comment fields; we use ':' between
    # dates EVERYWHERE that lands in the ERP (Description, Comments,
    # trust.reasoning) so the whole record is portable.
    combo_no = data["comboInvoice"]["invoiceNo"]
    description = f"{pf}:{pt} Foodora combo faktura {combo_no}"

    # Convert financial_year_id ("7", "6") to integer for the
    # erp_payload.FinancialYear field. FY is REQUIRED — the orchestrator
    # must resolve it against the company's financial-year windows before
    # calling this builder. Letting it stay null lets the ERP's opaque
    # default-year fallback pick a value IFN doesn't know about (see
    # Kållered BKOs 5+6 on 2026-06-08, where the voucher landed in FY-6
    # while IFN still believed it was FY-7 and the file-attach then
    # failed against a non-existent A208/FY-7). Fail fast at build
    # instead of shipping a BKO that will surprise everyone at execute.
    fy_raw = build_input.financial_year_id
    if not fy_raw or fy_raw == "?":
        raise ValueError(
            "financial_year_id is required; the orchestrator must resolve "
            "it (e.g. via process_inbox._resolve_financial_year) before "
            "calling build_bko."
        )
    fy = int(fy_raw)

    # Wire shape v2 (post bko-wire-refactor, see TriageOmniStrategy + the
    # BKO wire-shape brief): four top-level blocks. Fields that previously
    # lived as flat top-level keys are namespaced by concern. Producer-side
    # context that doesn't fit a typed slot rides in provenance.agent_metadata
    # (IFN-opaque). Fields dropped entirely vs. v1: balanceCheck (producer
    # invariant, recomputable from rows), transactionDateSource (audit
    # string for a value that speaks for itself), generationMethod
    # (subsumed by producer_label), rateKeyedAccounts (internal state).
    return {
        "command": {
            "entity_type": "voucher",
            "action": "create",
            # All ERP-bound parameters. The IFN executor splits body vs.
            # query-string at request time (FinancialYear rides on
            # ?financialyear=N, the rest goes into the body).
            "erp_payload": {
                "VoucherSeries": "A",
                "FinancialYear": fy,
                "TransactionDate": doc_date,
                "Description": description,
                "Comments": notes,
                "VoucherRows": rows,
            },
            "attachments": {
                "file_refs": list(build_input.file_refs),
            },
        },
        "trust": {
            "confidence": score,
            "reasoning": reasoning,
            "remarks": remarks,
        },
        "provenance": {
            "producer_label": f"{BUILDER_NAME} {BUILDER_VERSION}",
            "agent_metadata": {
                "triage": {
                    "name": "triage",
                    "version": build_input.triage_version,
                    "matched_rule": build_input.triage_matched_rule,
                },
                "parser": {
                    "name": "foodora_combo_invoice",
                    "version": build_input.parser_version,
                },
                "builder": {
                    "name": BUILDER_NAME,
                    "version": BUILDER_VERSION,
                    "rules_doc_sha256": RULES_DOC_SHA256,
                },
                "rules_doc": RULES_DOC,
                "generated_at": generated_at,
                "confidence_signals": signals,
            },
        },
        "groups": [],
    }

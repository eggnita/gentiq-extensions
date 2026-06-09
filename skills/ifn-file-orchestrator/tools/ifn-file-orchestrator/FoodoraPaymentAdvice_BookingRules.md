<!-- parser_version: v0.2-attach-criteria -->
<!--
  ^ This spec is now parser-paired (no builder — PA does not produce a BKO
  under the SPLIT pattern). When `tests/test_spec_consistency.py` is taught
  to handle parser-paired specs, the version slug + sha256 will be enforced
  the same way the combo-invoice spec is today.
-->

# Foodora Payment Advice — Booking Rules

## Status

Parser is **live** at `v0.2-attach-criteria` (single-invoice PAs). The
attach workflow is still **planned** — the orchestrator side wiring (CLI
attach call, business-day calendar, fallback notifier) is not yet
implemented.

## Purpose

Defines what to do with a Foodora **Payment Advice** PDF
("`Payment Advice Note from <DD.MM.YYYY>.PDF`") once it is recognised by
triage. The corresponding parser will extract the lookup keys needed to find
the matching voucher; the higher orchestrator handles the lookup and the
file attachment.

## Strategy

`parse_and_attach_to_voucher` — see `triage.py::STRATEGY_PARSE_AND_ATTACH`.

Unlike the combo-invoice, a Payment Advice does **not** become its own BKO.
Per the bookkeeping team's SPLIT decision (2026-06-04, see TODO.md), the
cash settlement is booked on a separate voucher that the ERP's bank
integration creates from the actual bank transaction. The Payment Advice
is the supporting document for that voucher and should be attached to it.

## What the parser extracts

See `parsers/foodora_payment_advice.py` module docstring for the full output
schema. The fields the attach workflow consumes:

| Field | Source on the PA | Use |
|---|---|---|
| `comboInvoice.invoiceNo` | "Fakturanummer" column, first/only row | Cross-reference identifier (mirror of `payments[0].comboInvoiceNo`) |
| `paymentDate` | "Betalningdatum" — Foodora's stated payout date | Center of the date window for the attach lookup |
| `totals.paidAmount` | "Betalt belopp" line | Exact amount the target cash voucher must show |
| `attachCriteria` | computed from the three above | Pre-built decision object the orchestrator consumes verbatim |

`attachCriteria` is what makes the contract orchestrator-friendly: instead
of re-deriving "which voucher does this PA belong to?" from raw fields, the
orchestrator reads the criteria and queries the ERP directly.

## Attach criteria

The PA describes a payout. Under SPLIT, the ERP's bank integration creates
a cash-clearing voucher when the actual bank transaction lands; the PA is
the supporting document for that voucher. Match policy:

### Voucher rows — exact

The target voucher must contain BOTH of these rows, to the öre:

| Account | Side | Amount |
|---|---|---|
| **1930** | D | `totals.paidAmount.amount` |
| **1584** | K | `totals.paidAmount.amount` |

No tolerance. A 0.01 SEK mismatch is treated as "not the same voucher" —
silent rounding fudge would mask whole categories of bank-side
discrepancies. (Tolerance might be revisited if a real bank-integration
discrepancy pattern emerges in practice.)

### Transaction date — business-day window

The target voucher's `TransactionDate` must fall within:

| Lower bound | Upper bound |
|---|---|
| `paymentDate − 1 business day` | `paymentDate + 2 business days` |

- **−1**: covers a same-week early settle when banks process faster than
  Foodora's PA timing assumes.
- **+2**: covers weekends and the +1 business-day SEPA-style transfer lag
  Foodora's payouts typically experience.

Business days are computed against the orchestrator's calendar (Swedish
bank holidays). The parser emits the policy as integers
(`earlierBusinessDays: 1`, `laterBusinessDays: 2`); the orchestrator
resolves them to concrete ISO bounds at query time.

### Fallback — `ifNoMatch: "notify_accountant"`

If no voucher matches both the exact-rows and the date-window criteria,
the orchestrator must NOT attach the file. Long-run target: notify an
accountant directly, or surface the file on a messaging proxy bus that
the bookkeeping team subscribes to. Not yet implemented; for now the
orchestrator should mark the file with metadata
`next_step="notify_accountant_or_messaging_proxy"` and leave it on the
manual queue.

## Attach workflow (planned, not implemented)

**Hard ERP constraint:** a single uploaded file_id can be attached to at most
ONE voucher (see `project_erp_constraints_and_transactions` memory). So the
orchestrator picks one target per PA file. If we ever want PA visible from
multiple vouchers, upload one copy per voucher (all copies share the same
`group_id` via `metadata.group_id_for(company_id, invoice_no)`).

The orchestrator should:

1. Parse the PA → consume `data.attachCriteria` verbatim (no re-derivation).
2. Query the ERP for vouchers matching ALL of:
   - the exact `voucherRows` from `attachCriteria` (1930 D + 1584 K at
     the paid amount, to the öre);
   - a `TransactionDate` within the business-day window computed from
     `attachCriteria.transactionDateWindow`.
3. **Exactly one match** → attach the PA file to that voucher via the CLI.
4. **Zero matches** AND the date window upper bound is still in the future
   → leave the file with `next_step="await_bank_arrival"` and re-check on
   the next scan (per `metadata.FileDetails`). The cash voucher likely
   hasn't been created yet.
5. **Zero matches** AND the date window has elapsed → apply
   `attachCriteria.ifNoMatch` ("notify_accountant"). Mark
   `next_step="notify_accountant_or_messaging_proxy"`.
6. **More than one match** → ambiguous; also route to the notify path
   (we should never silently pick one when the criteria don't disambiguate).

The recognition voucher we produced from the combo-invoice is NOT the
target — the combo-invoice PDF is already attached there. Attaching the PA
to the recognition voucher would either duplicate the document trail
(if the PA was uploaded specifically for this) or waste an upload.

Open: which CLI subcommand performs the attach (the IFN CLI has been
updated — `ifn files metadata` writes category/group_id/details, but the
file→voucher attach call needs verifying). See `TODO.md`.

## Out of scope

- Producing a BKO from the PA. The cash voucher is the ERP's
  bank-integration's job.
- Triggering reattempt if no matching voucher is found (timing nuance:
  PA can arrive before or after the bank transaction). The orchestrator
  handles re-queueing.

## Related artifacts

- `triage.py` — PA rule + STRATEGY_PARSE_AND_ATTACH constant.
- `parsers/foodora_payment_advice.py` — stub parser.
- `~/.claude/projects/.../memory/project_foodora_payment_advice.md` — the
  domain-level facts (intent-to-pay semantics, invoice-number reference).
- `FoodoraComboInvoice_BookingRules.md` — the recognition voucher that the
  PA may attach to as a fallback.

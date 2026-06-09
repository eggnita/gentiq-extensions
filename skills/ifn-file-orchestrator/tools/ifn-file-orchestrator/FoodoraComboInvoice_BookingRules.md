<!-- builder_version: v0.20-credit-reversals -->
<!--
  ^ This invisible marker is parsed by tests/test_spec_consistency.py and
  must equal `BUILDER_VERSION` in bko_builders/foodora_combo_invoice.py.
  When you edit this spec, bump both — the test enforces it so a behavior
  change can't ship with a stale spec or vice versa.
-->

# Foodora Combo-Invoice — Booking Rules

## Purpose

Defines how a parsed Foodora combo-invoice (output of `parsers/foodora_combo_invoice.py`) maps onto a Swedish-style voucher (kontering). This document is the **rules specification**; the executable embodiment lives at `bko_builders/foodora_combo_invoice.py`. The two are intentionally cross-referenced — keep them in lockstep when rules change.

The rules describe **what** each voucher row should contain, using JSON-path expressions over the parsed data. They do **not** themselves perform bookings. The builder consumes parsed data plus per-file metadata (file refs, financial year, parser version) and emits a BKO entity ready for `ifn staging propose` — see the builder module header for the CLI schema contract.

## Applies to

- Parser version: **`v0.10-foodora-output-vat`** (in `parsers/foodora_combo_invoice.py`).
- Builder version: **`v0.20-credit-reversals`** (in `bko_builders/foodora_combo_invoice.py`).
- Document type: **Foodora combo-invoice** (Faktureringsdokument PDFs containing both Självfaktura "(1)" and Faktura "(2)" sections).
- Modeled on real vouchers **A262 / FY-7** (post-regulation 6 %) and **A1181 / FY-6, A25 / FY-7** (pre-regulation 12 %), all on Brödernas Uppsala AB. The historical actuals use the **integrated** pattern (cash + recognition on one voucher); the rules below now emit the **split** pattern per bookkeeping-team direction (2026-06-04), so a comparison against historicals will surface expected structural differences (see "Known systematic mismatches" below).

The parser and builder versions can diverge over time: schema-breaking parser changes bump the parser version, rules changes bump the builder version. They were aligned through v0.8; v0.9 is a builder-only change (rules pattern shift) and the parser stays at v0.8.

## VAT regulation change (2026-04-01)

Sweden lowered the food-delivery VAT rate from **12 %** to **6 %** effective **2026-04-01**. The parser already extracts the per-invoice rate into `selfBilling.outputVat.rate` — the rules below select sales and output-VAT accounts from that rate, so the rule set works seamlessly across the change. Pre-change invoices land on `3002 / 2621`; post-change land on `3003 / 2631`.

## Pre-conditions

The parsed `data` object must have non-null values for the fields referenced in the formulas below. If any required field is null, the executor must NOT post the voucher and should surface the parsed `errors` list instead. Enforced in code by `bko_builders/foodora_combo_invoice.py::_check_required` (raises `ValueError` listing the missing dotted paths).

## Wire shape (BKO envelope, v2)

The builder emits a v2-shaped BKO body matching the IFN `BkoCreate` schema (`ifn bko propose`). Four top-level blocks:

| Block | What lives there |
|---|---|
| `command` | `entity_type` (`"voucher"`), `action` (`"create"`), `erp_payload` (the ERP-bound voucher body — `VoucherSeries`, `FinancialYear`, `TransactionDate`, `Description`, `Comments`, `VoucherRows`), `attachments.file_refs` (existing IFN file_ids to link to the resulting voucher). |
| `trust` | `confidence` (0-1 scalar), `reasoning` (long-form audit text), `remarks` (array of producer-structured objects). |
| `provenance` | `producer_label` (`"foodora_combo_invoice v0.20-credit-reversals"`), `agent_metadata` (IFN-opaque object: triage/parser/builder versions + sha + confidence_signals). |
| `groups` | Producer-asserted tags for filtering on the BKO queue. Empty for this builder today. |

The IFN executor splits `erp_payload` at request time (`FinancialYear` becomes the `?financialyear=N` query, the rest goes into the request body). Fields dropped vs. v1 builder shape: `balanceCheck` (producer invariant, recomputable from rows), `transactionDateSource` (audit string for a value that speaks for itself), `generationMethod` (subsumed by `producer_label`), `rateKeyedAccounts` (internal state).

## Voucher metadata

| Field (path inside `command.erp_payload`) | Source / formula |
|---|---|
| `VoucherSeries` | `"A"` |
| `Description` | `"{orderPeriod.from}:{orderPeriod.to} Foodora combo faktura {comboInvoice.invoiceNo}"` — period first (so voucher lists sort naturally by period), then the partner format hint, then the bare combo-invoice number (no `-1` self-billing suffix). Dates are ISO (`YYYY-MM-DD`); separator is a colon — the ERP rejects `→` (U+2192) in some voucher fields, so we use ASCII-only separators throughout. The expected-payout figure and the `Expecting PaymentAdvance` forecast both live in `Comments` and `trust.reasoning` — kept off the header so it doesn't crowd the voucher list. |
| `TransactionDate` | `comboInvoice.date` — the document's own "Datum" line. The cash settlement is booked on a **separate** voucher (created by the ERP's bank integration when actual payment lands, using bank-arrival date); this pipeline does not produce that voucher. |
| `Comments` | Three-line voucher comment (Candidate B). See worked example below. |
| `FinancialYear` | Resolved from `TransactionDate` against the company's financial year calendar; arrives in the builder as `build_input.financial_year_id` and is coerced to int. |

## Voucher rows

JSON-path notation: dot-separated paths from `data`. `[*]` means "all elements". Sign convention: voucher amounts are positive; parsed `data` uses negative for Foodora-side amounts, so formulas negate where needed.

Descriptions are verbose Swedish phrasings, deliberately echoing terminology from the source PDF so a human auditor can trace each row back to the document. Templated values in `{…}` come from parsed fields; the surrounding Swedish text is fixed.

### Credit-reversal rows (v0.20)

When orders are cancelled mid-period, two paired rows appear in the source self-bill — one in the orders block, one in the discount block:

- `Avbruten Utkörningsorders` (or `Avbruten Avhämtningsorders`) — parsed into `selfBilling.orders[*]` with NEGATIVE `grossAmount` / `netAmount`. The builder treats it like any other order row; the `sum(grossAmount) - payoutAmount` collapse at 1584 K naturally nets the cancellation in.
- `Minskning av rabatt vid kreditering N%` — parsed into `selfBilling.contractualDiscounts[*]` with POSITIVE `discountBasisAmount` and `amountExVat`, reversing a portion of the standard `Rabatt enligt avtal` commission. The builder emits this as a `Credit` on the sales account (mirror of the standard discount's `Debit`), so the net effect on the sales account is `commission - reversal`.

### Rate-keyed account selectors

The sales account and the output-VAT account are selected from `selfBilling.outputVat.rate`:

| `outputVat.rate` | Sales account | Output-VAT account |
|---:|---|---|
| 0.25 | 3001 (Försäljning inom Sverige 25 % moms) | 2611 (Utgående moms 25 %) |
| 0.12 | 3002 (Försäljning inom Sverige 12 % moms) | 2621 (Utgående moms 12 %) |
| 0.06 | 3003 (Försäljning inom Sverige 6 % moms)  | 2631 (Utgående moms 6 %) |

If `outputVat.rate` isn't in this table, the executor must refuse to emit the voucher and surface the unknown-rate value for human review.

Below, `{salesAcct}` and `{outputVatAcct}` are the rate-keyed accounts. `{ratePct}` is `outputVat.rate * 100`.

### Core rows (always present, in this order)

| # | Account | Side | Description | Amount formula |
|---|---|---|---|---|
| 1 | **1584** | K | `"{orderPeriod.from}->{orderPeriod.to}: Foodora fees and commission"` | `sum(selfBilling.orders[*].grossAmount) - settlement.payoutAmount` — the net Foodora withholds for the period (fees + commission + VAT-on-rabatt). |
| 2 | **6044** | D | `"Foodoras avgifter exkl. moms, faktura {foodoraInvoice.invoiceNo}"` | `-foodoraInvoice.foodoraFeesExVat` |
| 3 | **2641** | D | `"Er ingående moms {foodoraInvoice.inputVat.rate*100:.0f} %, faktura {foodoraInvoice.invoiceNo}"` | `-foodoraInvoice.inputVat.amount` |

**Why a single `1584 K` at the net amount.** Earlier versions exposed the gross-vs-payout split on the voucher itself: v0.9–v0.11 netted them into one row whose amount was synthesized (`gross − payout`); v0.12 attempted a pro-rata split per category; v0.13/14 emitted one `1584 K` per category at its full gross plus an explicit `1584 D` at the payout amount. The v0.13/14 layout used only verifiable numbers, but it crowded the row table with figures that are already legible on the source self-bill. v0.15 collapses them: a single `1584 K` at the net (`sum(grossAmount) − payout`) represents what Foodora withholds — fees, commission, and the VAT-on-rabatt portion. Per-category gross numbers stay on the self-bill PDF where a reviewer can verify them; the voucher carries the one figure that's economically meaningful. The future cash voucher (created by the ERP's bank integration when actual payout lands) books `1930 D payoutAmount + 1584 K payoutAmount`; across both vouchers the cumulative effect on each account matches the historical integrated form.

### Compensation-income rows (v0.14, conditional)

Foodora's `Faktura (2)` may include an `Er utgående moms X% (BASIS) AMOUNT SEK` line — output VAT on a credit/compensation Foodora is paying us (e.g. *Double cooking ersättning*). When the parser captures `foodoraInvoice.outputVat` (rate + basisAmount + amount), the builder splits the recognition into three rows so the credit is treated as separate income at its own VAT rate rather than absorbed into the fees-net:

| # | Account | Side | Description | Amount formula |
|---|---|---|---|---|
| (replaces row 2) | **6044** | D | `"Foodoras avgifter exkl. moms, faktura {foodoraInvoice.invoiceNo}"` | `-foodoraInvoice.foodoraFeesExVat + foodoraInvoice.outputVat.basisAmount` — corrects to TRUE Foodora fees (foodoraFeesExVat is otherwise net of the credit) |
| new | **{salesAcct(comp_rate)}** | K | `"Foodora ersättning ({rate} %), faktura {foodoraInvoice.invoiceNo}"` | `foodoraInvoice.outputVat.basisAmount` — compensation income at the comp rate's sales account (e.g. 3002 for 12 %, 3003 for 6 %) |
| new | **{outputVatAcct(comp_rate)}** | K | `"Utgående moms {rate} % på Foodora ersättning"` | `foodoraInvoice.outputVat.amount` — output VAT on the income |

If `foodoraInvoice.outputVat.rate` isn't in the rate-keyed account table, the builder raises (same policy as for `selfBilling.outputVat.rate`).

**Why this matters.** Without these rows, A119 / FY-7 (Uppsala) was unbalanced by exactly `13.41 SEK` — the output VAT line we ignored. The v0.13 alarm correctly caught it ("⚠ NOT BALANCED — DO NOT POST" + confidence 0.10). v0.14 captures the underlying mechanic so the voucher can actually be posted.

When `foodoraInvoice.outputVat` is None (most invoices, including all current Kållered samples), behaviour is identical to v0.13: 6044 D = `-foodoraFeesExVat`, no extra rows.

### Dynamic rabatt rows (one per contractual discount)

For each `d` in `selfBilling.contractualDiscounts` (preserving array order):

| Account | Side | Description | Amount formula |
|---|---|---|---|
| **{salesAcct}** | D | `"{d.description} på Foodora-försäljning"` | `-d.amountExVat` |

For `d61d0de4` (which has two rabatts) this produces two `{salesAcct} D` rows:
`"Rabatt enligt avtal på Foodora-försäljning"` and `"Rabatt avhämtningsorders på Foodora-försäljning"`.

### VAT adjustment row (always present)

| Account | Side | Description | Amount formula |
|---|---|---|---|
| **{outputVatAcct}** | D | `"Utgående moms-justering {ratePct:.0f} % på avtalsrabatten"` | `(sum(selfBilling.orders[*].grossAmount) - sum(selfBilling.orders[*].netAmount)) - selfBilling.outputVat.amount` |

**Why row 6 (the VAT adjustment) exists.** Foodora's commission is economically a service fee but is invoiced as a "rabatt" (discount) for VAT reasons: this keeps the whole transaction at the food-sales rate (6 %) instead of triggering a 25 % VAT cycle on a separate commission invoice. The PDF therefore reports a *reduced* output VAT — 6 % of the post-rabatt sales basis (`outputVat.amount`) — instead of 6 % of the gross orders. For bookkeeping the partner's voucher should still recognise the full sales basis and the full output VAT, then reduce both via the rabatt rows and this adjustment row. Specifically:

- The rabatt rows (3003) post the rabatt as a sales reduction.
- This row (2631) posts the 6 % VAT *on that rabatt* as a matching output-VAT reduction.

The formula `(grossAmount − netAmount) − outputVat.amount` recovers the VAT-on-rabatt portion: `grossAmount − netAmount` is the full 6 % VAT included in the order gross, and `outputVat.amount` is the reduced 6 % VAT shown in the PDF; their difference is the missing piece. Equivalently: `outputVat.rate × |sum(contractualDiscounts[*].amountExVat)|`.

### Rounding row (always present)

| Account | Side | Description | Amount formula |
|---|---|---|---|
| **3740** | D if `settlement.rounding > 0`, K if `< 0` | `"Öresavrundning enligt självfaktura {selfBilling.invoiceNo}"` | `\|settlement.rounding\|` |

Even small öresavrundning is posted explicitly to 3740, mirroring the PDF's own line item.

## Remarks

Each voucher draft includes a `trust.remarks` array highlighting anomalies for human review. The executor surfaces a graduated severity signal so an auditor can triage cases by total remark points. Remarks also drive the BKO's `trust.confidence` scalar (deductions per category) and are surfaced explicitly in `trust.reasoning` under "FLAGGED FOR REVIEW" so a reviewer doesn't miss them.

### Rounding deviation

Scales by the magnitude of `|settlement.rounding|`:

| Condition | Action |
|---|---|
| `|settlement.rounding| > 1 SEK` | Add a note (informational, 0 points) |
| `|settlement.rounding| > 10 SEK` | 1 remark point |
| `|settlement.rounding| > 100 SEK` | 10 remark points |
| `|settlement.rounding| > 1000 SEK` | 100 remark points |

Thresholds are inclusive of the upper tier (e.g. a rounding of 250 SEK earns 10 points, not 1).

### Discount-rate deviation

One remark per contractual discount whose rate deviates from its documented expected value by more than 0.5 percentage points (tentative — see TODO.md). Documented expected rates (v0.13):

| `contractualDiscounts[*].description` | Expected `rate` | Meaning |
|---|---:|---|
| `Rabatt enligt avtal` | 0.21 (21 %) | Standard delivery commission. |
| `Rabatt avhämtningsorders` | 0.10 (10 %) | Pickup/takeaway commission (Foodora-bar partners). |

Each firing `discount-rate-deviation` remark scores **5 points** and names the offending description + rate in the BKO `trust.reasoning`.

### Unknown discount type

When a `contractualDiscounts[*].description` is not present in `EXPECTED_DISCOUNT_RATES` at all, the builder emits an `unknown-discount-type` remark worth **20 points** and surfaces it in `trust.reasoning`. This catches Foodora introducing a new commission type or renaming an existing one — silence on those would let unauthorised charges slip through unnoticed. The fix is to confirm with the contract, then add the description + expected rate to the map.

### Voucher not balanced

If `|sum(D) − sum(K)|` exceeds the balance tolerance (±0.20 SEK), the builder emits a `voucher-not-balanced` remark worth **100 points** AND forces the BKO `confidence` scalar to `CONFIDENCE_FLOOR` (0.10). The reasoning leads with `⚠ NOT BALANCED — DO NOT POST`. Under no circumstances should an unbalanced BKO be submitted to the ERP; surface to a human reviewer instead. The most likely cause is an unknown row type the parser doesn't capture (e.g. a new order category, an unfamiliar Foodora line item, a cancellation). See TODO.md "Invariant-driven remarks".

Future remark categories may be added (e.g. parser errors, schema mismatches, individual Faktura (2) line-item anomalies).

## Balance invariant

After computing all rows, the executor must verify:

```
sum(debits) - sum(credits) == 0
```

Allowing a **tolerance of ±0.20 SEK** to absorb sub-öre discrepancies between the parsed PDF values and the strict 6 %/21 % arithmetic used in the formulas. The explicit 3740 öresavrundning row removes the larger rounding component, so the residual tolerance is only for these öre-level computation deltas.

## Worked example — A262 / d84e0f51

Parsed values from `Faktureringsdokument - 7002649842.pdf` (= sample `d84e0f51`):

| Parsed field | Value |
|---|---|
| `settlement.payoutAmount` | 34 815.95 |
| `selfBilling.orders[*]` | `[{description: "Utkörningsorders", grossAmount: 51 673.80, netAmount: 48 748.87}]` — one category for A262. Foodora-bar partners (e.g. Kållered) have two: Utkörningsorders + Avhämtningsorders, summed by the builder. |
| `selfBilling.invoiceNo` | 7002649842-1 |
| `selfBilling.outputVat.rate` | 0.06 |
| `selfBilling.outputVat.amount` | 2 273.84 |
| `selfBilling.contractualDiscounts[0]` | `{description: "Rabatt enligt avtal", amountExVat: -10 851.50}` |
| `foodoraInvoice.invoiceNo` | 7002649842-2 |
| `foodoraInvoice.foodoraFeesExVat` | -4 284.11 |
| `foodoraInvoice.inputVat.rate` | 0.25 |
| `foodoraInvoice.inputVat.amount` | -1 071.03 |
| `settlement.rounding` | 0.12 |
| `orderPeriod.from` / `orderPeriod.to` | 2026-05-01 / 2026-05-07 |

Generated v0.15 voucher draft (recognition only):

| # | Account | Side | Description | Amount |
|---|---|---|---|---:|
| 1 | 1584 | K | 2026-05-01->2026-05-07: Foodora fees and commission | 16 857.85 |
| 2 | 6044 | D | Foodoras avgifter exkl. moms, faktura 7002649842-2 | 4 284.11 |
| 3 | 2641 | D | Er ingående moms 25 %, faktura 7002649842-2 | 1 071.03 |
| 4 | 3003 | D | Rabatt enligt avtal på Foodora-försäljning | 10 851.50 |
| 5 | 2631 | D | Utgående moms-justering 6 % på avtalsrabatten | 651.09 |
| 6 | 3740 | D | Öresavrundning enligt självfaktura 7002649842-1 | 0.12 |

Voucher description (voucher-list header): `"2026-05-01:2026-05-07 Foodora combo faktura 7002649842"`.

Voucher comment (`command.erp_payload.Comments`, becomes the voucher comment in the ERP) — three short lines, concise on purpose so a reader actually reads them:

```
Bokfört via IFN.
1584 K = 51 673.80 brutto - 34 815.95 utbet = 16 857.85 Foodora-avdrag.
Avvaktar bankvoucher ca 2026-05-15 (1930 D + 1584 K, 34 815.95 kr).
```

Line 1 = provenance. Line 2 = the only non-trivial derived row, shown with the values from the self-bill so a reviewer can spot-check against the PDF. Line 3 = heads-up that the cash voucher is expected but not booked here. ASCII only, per the ERP comment-field character constraints below. `_build_1584_calc_short_sv` in the builder produces the second line; the long English form in `trust.reasoning` comes from `_build_1584_calc_line`.

**ERP comment-field allowed characters (observed empirically):** the ERP's voucher-comment field rejects certain printable characters that a quick "it's just text" assumption would let through. Known-rejected: `→` (U+2192), `~`. Known-accepted: `@`, `#`, `:`, basic punctuation, Swedish letters. Use `ca` (Swedish for *cirka*) where you'd otherwise reach for `~`. This applies to anything written into `command.erp_payload.Comments` AND `trust.reasoning` (the BKO reasoning lands in an ERP-accessible field too).
TransactionDate: `2026-05-08` (= `comboInvoice.date`).

Balance: `4 284.11 + 1 071.03 + 10 851.50 + 651.09 + 0.12 = 16 857.85` D vs `16 857.85` K → **balanced exactly**. The reasoning surfaces the calculation `1584 K: 51 673.80 - 34 815.95 = 16 857.85 SEK` (ASCII hyphen-minus throughout, since the audit-PDF font renders Unicode U+2212 as a centered dot) so a reviewer can verify the figure without summing the row table by hand.

Remarks: none (`|rounding| = 0.12 SEK < 1 SEK`).

The cash settlement voucher (created separately by the ERP's bank integration when actual payout lands) will book `1930 D 34 815.95 + 1584 K 34 815.95`. Across the two vouchers, the cumulative effect on each account matches the v0.8 integrated voucher exactly — only the timing and pattern differ. The recognition voucher's `trust.reasoning` and `notes` both surface the forecast `Expecting PaymentAdvance (1930 D 34 815.95 SEK, 1584 K 34 815.95 SEK) ~2026-05-15`.

## Known systematic mismatches (not yet handled)

Comparison against historical vouchers surfaces two patterns the v0.8 rules do not yet reproduce. Both are acknowledged so the validation framework can report them separately from arithmetic deviations.

### 1. `Korrigering försäljning` rows — POS-vs-Foodora reconciliation (out of scope)

Some recognition vouchers include an extra correction row with a matching small output-VAT line and a corresponding bump on `1584 K`. The correction account is rate-keyed (same era as the regulation change):

| `outputVat.rate` | Correction account |
|---:|---|
| 0.12 (pre-2026-04-01) | **3081** Korrigering försäljning 12 % |
| 0.06 (post-2026-04-01) | **3083** Korrigering försäljning 6 % |

Example from A1181 / FY-6 (invoice 7002451568): `3081 D 565.60`, `2621 D 67.84` (= 12 % × 565.60), `1584 K 633.44` (= 565.60 × 1.12).

**What these rows represent.** They are manual adjustments for orders that were confirmed by the **POS** (Point-of-Sale) but later cancelled, where the POS could not retroactively void the entry due to regulatory restrictions on late cancellation. The POS therefore books slightly more Foodora-attributed revenue than Foodora ultimately confirms in its settlement; the difference shows up as a `Korrigering försäljning` line on the recognition voucher.

**Why this is out of scope for the combi-invoice booking rules.** The correction amount is **not derivable from the combi-invoice PDF** — confirmed by inspecting A1181 / 7002451568, where the Faktura (2) line items (`December Utvald`, `Uppkoppling och administrationsavgift`, `Fri Leverans`) sum cleanly into `foodoraFeesExVat` with no leftover that yields the correction base. The data lives in the POS, not in Foodora's documents.

**When the project moves to automatic booking, these corrections are intentionally omitted.** They will be produced by a separate downstream task that:

1. Compares orders acknowledged in Foodora's XLS files (or in the trailing detail pages of the combi-invoice PDFs) against orders recorded in the POS.
2. Identifies orders cancelled at end-of-day but mistakenly booked as POS revenue.
3. Generates daily adjustment vouchers for those discrepancies, attaching the cancellation evidence.

A further extension layered on top will gather material to support **challenging Foodora's decisions not to pay** for specific orders.

Until that separate workstream exists, comparisons against historical vouchers with a `Korrigering försäljning` row will show a small structural delta on the correction account, the matching output-VAT account, and `1584` — these are not parser/rules bugs.

### 2. Historicals use the integrated pattern; v0.9+ emits split

Two accounting patterns exist for the same invoice/payout pair:

- **Integrated** (e.g. A25, A262 / FY-7): one voucher containing recognition rows AND the cash receipt (`1930 D` + full `1584 K`). All historical vouchers in our test set use this pattern.
- **Split** — the v0.9+ form, per bookkeeping-team direction (2026-06-04):
  - **Recognition voucher** (this pipeline produces this) — no `1930`, single `1584 K` at `gross − payout` (v0.15 collapsed form).
  - **Cash-clearing voucher** (ERP's bank integration produces this when actual payout lands, with `TransactionDate = bank-arrival date`) — `1930 D + 1584 K`, both at `payout`.

When comparing the v0.15 draft against a historical integrated actual, the validation framework will report:
- `1930 D payout` — **actual-only** (expected; we no longer emit it here).
- `1584 K` — **draft is lower by `payout`** (the historical bundles both partitions on one row).

These are structural-by-design differences under SPLIT, not arithmetic errors. The audit PDF colors them red on the actual side, which is the correct visual signal.

## Out of scope (for this version)

- Per-rabatt VAT-rate splits in the VAT-adjustment row: today the row is one consolidated VAT-adjustment using `outputVat.rate`. If a future invoice has rabatts at multiple VAT rates (e.g. avhämtningsorders carry a different VAT than dine-in orders), this may need to split.
- Pre-VAT-period adjustment line items (Sökordsannonsering, Pink Choice/Utvald, Kampanj, Fri Leverans, Double cooking ersättning) that appear in Faktura (2). They net into `foodoraInvoice.foodoraFeesExVat` and `foodoraInvoice.inputVat.amount`, which is sufficient for the voucher rows above.
- The bank-arrival cash voucher itself (created by the ERP's bank integration, not exposed to the IFN API).
- Payment Advice handling (separate workstream — parse + look up the matching voucher by invoice number + attach the PA file; no BKO produced from PA).

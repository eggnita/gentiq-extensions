# Orchestration Context — IFN File Orchestrator

Read this document when the ifn-file-orchestrator skill is activated. It contains the step-by-step instructions for driving the bookkeeping file pipeline.

## Toolbox Location

The Python toolbox is at:
```
~/.openclaw/workspace/skills/ifn-file-orchestrator/tools/ifn-file-orchestrator/
```

All Python commands below should be run from this directory:
```bash
cd ~/.openclaw/workspace/skills/ifn-file-orchestrator/tools/ifn-file-orchestrator/
```

## Company Resolution

Before processing files, you need a `company_id`:

1. Check if the company is already known from the conversation context
2. If not, list companies: `ifn companies list`
3. Present the company names to the user and ask which one
4. The user may reply with a name — resolve it to the UUID from the list

## Financial Year Resolution

Before building a BKO, resolve the financial year ID:

1. Run: `ifn sync years <company_id>`
2. The invoice date from the parser output tells you which FY the voucher belongs to
3. Use the **ERP ID** (an integer), NOT the calendar year. Example: ID `6` = "2026"

---

## Flow A: Process a Single File

When the user points to a specific file (by name or file ID), process it with **per-step reporting**.

### Step 1 — Fetch the file

```bash
ifn files fetch <company_id> <file_id> --output /tmp/<filename>
```

If the user gave a filename instead of a file ID, first find it:
```bash
ifn browse <company_id> inbox
```
Then match by filename to get the file ID.

### Step 2 — Triage

```bash
python3 triage.py --json "<filename>"
```

Report the result:
- **If `outcome: "deterministic"`**: tell the user the file type and strategy, proceed to step 3
- **If `outcome: "llm_fallback"`**: tell the user "I don't recognise this file type. Tagging for manual review." Write metadata with `ifn files metadata <company_id> <file_id> --category manual_review` and stop
- **If `outcome: "unsupported"`**: tell the user the file type is not supported, skip

### Step 3 — Parse

The triage result tells you which parser to use via `parser_module` (e.g., `parsers.foodora_combo_invoice`).

```bash
python3 -c "
import json, sys
sys.path.insert(0, '.')
from parsers.foodora_combo_invoice import parse
result = parse('/tmp/<filename>')
print(json.dumps(result, default=str, ensure_ascii=False, indent=2))
"
```

Report: "Parsed successfully — extracted [key fields summary]" or "Parse failed: [error]"

If parsing fails, report the error and stop processing this file.

### Step 4 — Build BKO

Only for strategy `parse_and_build_bko`. Requires the parsed data from step 3 and the financial year ID.

```bash
python3 -c "
import json, sys
sys.path.insert(0, '.')
from bko_builders.foodora_combo_invoice import build_bko
from bko import BuildInput

data = <parsed_data_from_step_3>
input = BuildInput(
    file_refs=['<file_id>'],
    financial_year_id='<fy_id>',
    parser_version='<version_from_parser>',
    triage_version='<version_from_triage>',
    triage_matched_rule='<matched_rule_from_triage>',
)
bko = build_bko(data, input)
print(json.dumps(bko, default=str, ensure_ascii=False, indent=2))
"
```

After building, compute confidence from all remarks:

```bash
python3 -c "
import json
from remarks import compute_confidence, Remark
remarks = [Remark(text='...', scalar=N, id='...'), ...]  # all remarks from triage + parser + builder
print(json.dumps({'confidence': compute_confidence(remarks)}))
"
```

### Step 5 — Present for Approval

Present the BKO to the user with:
- **Voucher summary**: series, date, description, number of rows
- **Key rows**: account, debit/credit, description for each row
- **Confidence score** and any remarks
- **Total debits and credits** (should balance)

Ask: "Shall I submit this BKO?"

**Never auto-submit. Always ask.**

### Step 6 — Submit (on approval)

```bash
ifn staging propose <company_id> /tmp/bko_<file_id>.json
```

Write the BKO JSON to a temp file first, then pass it to the CLI.

Report: "BKO submitted successfully — BKO ID: [id]" or "Submission failed: [error]"

### Step 7 — Cleanup

Delete temp files:
```bash
rm -f /tmp/<filename> /tmp/bko_<file_id>.json
```

---

## Flow B: Process the Inbox (batch)

When the user says "process the inbox" or similar.

### Step 1 — List inbox files

```bash
ifn browse <company_id> inbox
```

Report: "Found [N] files in the inbox."

### Step 2 — Process each file sequentially

For each file, run **Flow A** but with **per-file summary reporting**:
- Report one line per file: "Processing `<filename>`: [type] -> [outcome]. [confidence if BKO built]"
- Show the BKO summary and ask for approval before submitting
- After each file (whether submitted, skipped, or failed), ask: **"[X] more files remaining. Continue?"**
- If the user says no, stop

### Step 3 — Final summary

After all files (or when stopped):
- "[N] files processed: [X] BKOs submitted, [Y] payment advices attached, [Z] sent to manual queue, [W] skipped/failed"

---

## Flow C: Payment Advice Attach

For files with strategy `parse_and_attach_to_voucher` (e.g., Foodora Payment Advice).

### Step 1-3 — Same as Flow A (fetch, triage, parse)

The parser output includes an `attachCriteria` block.

### Step 4 — Find the matching voucher

Read the `attachCriteria` from the parser output:
- `voucherRows`: exact rows the target voucher must have (1930 D + 1584 K at the paid amount, to the ore)
- `transactionDateWindow`: `earlierBusinessDays` and `laterBusinessDays` relative to `paymentDate`

Search for matching vouchers:
```bash
ifn records <company_id> vouchers --fy <fy_id>
```

Filter the results for vouchers that have BOTH:
1. A row with account 1930 Debit matching the exact amount
2. A row with account 1584 Credit matching the exact amount
3. A TransactionDate within the business-day window

### Step 5 — Attach or report

- **Exactly one match**: present the match to the user, ask to confirm attachment, then attach via `ifn staging propose` (or the appropriate attach command)
- **Zero matches + date window still in future**: report "No matching voucher yet. The payment is expected around [date]. I'll tag this file to check again later." Write metadata with `next_step: "await_bank_arrival"` and `expected_match_after: "<date>"`
- **Zero matches + date window passed**: report "No matching voucher found and the expected date has passed. Flagging for accountant review." Tag as manual review
- **Multiple matches**: present all candidates to the user and ask which one to attach to

---

## Triage Result Reference

| Field | Description |
|-------|-------------|
| `outcome` | `deterministic`, `llm_fallback`, or `unsupported` |
| `doc_type` | Document type identifier (e.g., `foodora_combo_invoice`) |
| `strategy` | `parse_and_build_bko` or `parse_and_attach_to_voucher` |
| `parser_module` | Python module to import for parsing (e.g., `parsers.foodora_combo_invoice`) |
| `builder_module` | Python module for BKO building (only for `parse_and_build_bko` strategy) |
| `attach_lookup_keys` | Fields to extract for voucher lookup (only for `parse_and_attach_to_voucher`) |
| `matched_rule` | Which triage rule fired |
| `reason` | Human-readable explanation |
| `remarks` | Array of `{id, scalar, text}` — noteworthy observations |
| `triage_only_confidence` | Confidence from triage remarks alone (not the full pipeline confidence) |

## Confidence Interpretation

| Range | Meaning |
|-------|---------|
| 1.00 | Perfect — fully deterministic, no remarks |
| 0.95-0.99 | Minor observations, safe to submit |
| 0.70-0.94 | Notable remarks — present clearly to accountant |
| 0.35-0.69 | Significant uncertainty — emphasize risks |
| < 0.35 | LLM-derived or major issues — strong caution |
| 0.00 | Hard veto (e.g., voucher doesn't balance) — do not submit |

Always present the confidence score and all remarks to the accountant when asking for approval.

## Supported File Types

| Type | Filename Pattern | Strategy |
|------|-----------------|----------|
| Foodora combo-invoice | `Faktureringsdokument - <number>.pdf` | `parse_and_build_bko` |
| Foodora payment advice | `Payment Advice Note from *.PDF` | `parse_and_attach_to_voucher` |
| XLS files | `*.xls`, `*.xlsx` | unsupported |
| Everything else | — | `llm_fallback` → manual queue |

## Booking Rules Reference

When reviewing BKO output or answering accountant questions about the booking logic, read the relevant rules document:
- Combo-invoice: `tools/ifn-file-orchestrator/FoodoraComboInvoice_BookingRules.md`
- Payment advice: `tools/ifn-file-orchestrator/FoodoraPaymentAdvice_BookingRules.md`

## Important Notes

- **The Python scripts are deterministic and pure** (except submitters). They have no network calls, no LLM calls, no side effects. You are the orchestrator — you call them and decide what to do with the output.
- **Triage never calls a model.** It only classifies by filename regex. If it returns `llm_fallback`, that means YOU should tag the file for manual review (we defer LLM classification for now).
- **Confidence is computed once**, after all steps, from all accumulated remarks. Use `remarks.compute_confidence()`.
- **`FinancialYear` is an ERP ID**, not the calendar year. Always resolve it via `ifn sync years`.
- **Recognition voucher vs. cash-clearing voucher**: This pipeline produces recognition/cost vouchers. Cash-clearing vouchers are created by the ERP's bank integration. Payment advices attach to cash-clearing vouchers, NOT to recognition vouchers.
- **Do NOT use the legacy `parse_foodora_pdf.py`** from the introspectfn-erp skill. This skill's parsers in `tools/ifn-file-orchestrator/parsers/` supersede them.

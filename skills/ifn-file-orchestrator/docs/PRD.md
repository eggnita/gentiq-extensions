# PRD: IFN File Orchestrator — Gentiq Skill Integration

## Problem Statement

Gentiq's virtual accountant Gents can query ERP data and propose vouchers via the `introspectfn-erp` skill, but they cannot automatically process incoming bookkeeping-supporting documents (PDFs from delivery partners like Foodora). Today, a developer (Ted) manually drives the `ifn-file-orchestrator` Python pipeline using Claude Desktop — classifying files, running parsers, building bookkeeping orders (BKOs), and submitting them. This is slow, manual, and doesn't scale to multiple companies or high-volume partners.

## Solution

Create a new Gentiq skill (`ifn-file-orchestrator`) that teaches the Gent how to orchestrate the existing deterministic Python pipeline. The Gent becomes the orchestrator — calling each Python script step by step, reporting results, and asking the accountant for approval before submitting. The pipeline's deterministic core stays untouched; only the orchestration layer moves from human+Claude Desktop to Gent+GentOS chat.

## User Stories

1. As an accountant, I want to tell my Gent "process the inbox" in GentOS chat, so that all new bookkeeping files are classified and processed without me opening each one manually
2. As an accountant, I want to point to a specific file and say "handle this file," so that a single file runs through the full pipeline
3. As an accountant, I want the Gent to ask me for approval before submitting any BKO, so that I stay in control of what gets booked
4. As an accountant, I want to see the BKO summary (accounts, amounts, confidence score, remarks) before approving, so that I can make an informed decision
5. As an accountant, I want the Gent to process inbox files one at a time and ask "X more, continue?" after each, so that I can stop the batch at any point
6. As an accountant, I want the Gent to automatically resolve the company from our chat context, so that I don't have to type company IDs
7. As an accountant, I want the Gent to resolve the financial year ID dynamically from the ERP, so that BKOs are always booked to the correct fiscal year
8. As an accountant, I want to ask the Gent to "just parse this invoice" without building a BKO, so that I can inspect extracted data
9. As an accountant, I want to ask "what type is this file?" and get a triage-only classification, so that I understand what the pipeline would do before running it
10. As an accountant, I want the Gent to handle Foodora payment advices by finding and attaching them to the matching cash-clearing voucher, so that supporting documents are linked correctly
11. As an accountant, I want to be notified when a payment advice has no matching voucher yet, so that I know it's waiting for the bank transaction to land
12. As an accountant, I want unrecognised files to be tagged for manual review and reported to me, so that nothing falls through the cracks silently
13. As an accountant, I want the Gent to continue processing the rest of the inbox when one file fails, so that a single bad PDF doesn't block everything
14. As an accountant, I want temp files cleaned up after processing, so that the Gent's VM doesn't accumulate orphaned PDFs
15. As an accountant, I want the Gent to use the new deterministic parsers instead of the legacy `parse_foodora_pdf.py`, so that I get the improved accuracy and booking rules
16. As an accountant, I want to see the confidence score explained (what remarks contributed, what each means), so that I understand why confidence is below 1.0
17. As an accountant, I want the Gent to ask me to clarify when it's unclear whether I want full processing or just information, so that it doesn't run the pipeline when I'm just asking a question

## Implementation Decisions

### Skill Architecture

- **Separate skill with hard dependency**: `ifn-file-orchestrator` is its own skill that declares `introspectfn-erp` as a required dependency. Not nested inside `introspectfn-erp`
- **Python toolbox bundled in `tools/`**: The entire `ifn-file-orchestrator` Python project (triage, parsers, builders, submitters, remarks, metadata) is copied into the skill's `tools/ifn-file-orchestrator/` directory. Self-contained when deployed to a Gent VM
- **`on_install` hook**: Installs `pdfplumber` via pip, verifies `ifn` CLI is available from the dependency skill, validates toolbox completeness

### SKILL.md Design (two-tier)

- **Capability declaration** (always in system prompt): Compact description of what the skill can do, when it activates, supported partial pipeline steps. Pattern-recognition triggers, not rigid keyword matching
- **Orchestration context** (loaded on activation): Full step-by-step instructions in `docs/ORCHESTRATION.md`. The Gent reads this when the skill activates. Contains Flow A (single file), Flow B (batch inbox), Flow C (payment advice attach)

### Orchestration Model

- **The Gent is the orchestrator**: It calls each Python script individually (triage → parse → build → submit), reads the output, decides what to do next, and reports to the user. The LLM drives the loop, not a Python orchestrator script
- **Per-step reporting for single files**: When processing one file, the Gent reports after each step (triage result, parse result, BKO summary)
- **Per-file summary for batch**: When processing the inbox, the Gent gives a one-line summary per file, with full detail only on anomalies
- **Sequential batch with continue prompt**: Files processed one at a time, "X more files remaining, continue?" after each

### Trigger and Activation

- **Human-initiated via GentOS chat**: An accountant tells the Gent to process files. No autonomous scanning or cron triggers
- **Two entry points**: "Process the inbox" (batch) or direct file pointer by name or ID (single file)
- **Partial pipeline**: The Gent can execute partial steps — triage only, parse only, triage+parse — when the user asks for less than the full pipeline
- **Ambiguity handling**: When intent is unclear, the Gent asks "I can process this through the full booking pipeline — want me to go ahead?"

### Submit Decision

- **Always ask**: The Gent never auto-submits. Every BKO is presented to the accountant with confidence score, remarks, and row summary. The accountant explicitly approves or rejects

### Company and Financial Year Resolution

- **Company from context**: Check chat context first. If not available, `ifn companies list` → present names → user picks → Gent resolves the UUID by name
- **Financial year resolved dynamically**: `ifn sync years <company_id>` → match invoice date to the correct FY → use the ERP ID (integer), never the calendar year

### File Handling

- **Fetch to disk**: `ifn files fetch` downloads to `/tmp/<filename>`. Passed as file path to parsers
- **Auto-cleanup**: Temp files deleted after the pipeline completes (submit, reject, or error)

### Error Handling

- **Fail per file, continue batch**: When a step fails for one file, the Gent reports the error (step name, message, filename) and moves to the next file. One bad PDF doesn't block the batch

### LLM Fallback

- **Deferred**: Files that don't match any triage rule are tagged `manual_review` and the accountant is notified. No LLM classification of unknown files until more formats are supported

### Payment Advice Attach

- **Gent drives the lookup**: The parser emits `attachCriteria` (exact voucher rows, date window). The Gent searches for matching vouchers via `ifn records`, evaluates the criteria, and attaches. No new Python code needed
- **Timing handling**: If no match and date window is still in the future, tag the file with `next_step: "await_bank_arrival"`. If date window passed, flag for manual review

### Legacy Parser

- **Clean break**: Remove `tools/parsers/parse_foodora_pdf.py` from `introspectfn-erp`. The new skill's parsers supersede it entirely (separate session)

## Testing Decisions

- **Skip skill-level tests for now**: The Python toolbox already has its own comprehensive test suite in `ifn-file-orchestrator/tests/` (unit tests, spec-consistency hash guards, historical voucher validation)
- **SKILL.md is prompt engineering**: Not unit-testable. Verified through live Gent interaction after deployment
- **`on_install.sh` testable manually**: Run on a clean VM to verify pdfplumber installs and ifn CLI detection works
- **Integration testing via live Gent**: The real test is deploying to a Gent and having an accountant try "process the inbox" against a real company with real files

## Out of Scope

- **LLM classification of unknown files**: Deferred until more formats are supported (Uber Eats, Wolt, generic supplier invoices)
- **Autonomous/cron-triggered processing**: The Gent only processes when asked by a human. Autonomous scanning is a future trust-building step
- **Auto-submit above confidence threshold**: All submissions require human approval. Configurable thresholds are a future feature
- **Batch approval**: Each BKO is approved individually. "Approve all" is a future UX improvement
- **New file formats**: Only Foodora combo-invoice and payment advice are supported. New formats follow the existing `ADDING_A_NEW_FORMAT.md` guide in the toolbox
- **Money type refactor**: The Python toolbox still uses `float` for SEK amounts. Tracked in the toolbox's own `TODO.md`, not in this skill
- **Triage vision features**: Recursive loop, batch mode, cross-file resolution, structured NextStep — all tracked in `TriageOmniStrategy.md` gap log

## Further Notes

- The `submitters/` Python scripts have hardcoded paths to the original developer's machine. The Gent will NOT use these scripts directly — it calls `ifn` CLI commands itself (`ifn staging propose`, `ifn files metadata`). The submitter scripts are bundled for reference only
- The spec-code lockstep enforcement (`tests/test_spec_consistency.py`) ensures booking rules markdown and builder code stay in sync. If rules change, the builder version and SHA256 hash must be updated together — this is enforced by the toolbox's own test suite, not by this skill
- Format roadmap: Foodora PA → Foodora POS reconciliation → Uber Eats → Wolt → unknown formats (LLM fallback). Each new format only needs a parser + builder + triage rule + spec markdown — no orchestrator changes

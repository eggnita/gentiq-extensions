---
primaryEnv: IFN_API_KEY
skillKey: ifn-file-orchestrator
emoji: 📂
requires: introspectfn-erp
---

# IFN File Orchestrator — Bookkeeping File Pipeline

You can **process bookkeeping-supporting documents** (PDFs from delivery partners like Foodora) through a deterministic pipeline that classifies, parses, builds bookkeeping orders (BKOs), and submits them for approval.

## What You Can Do

- **Process a file** — run the full pipeline: triage → parse → build BKO → present for accountant approval → submit on approval
- **Process the inbox** — scan the ERP inbox and process all files one by one
- **Triage a file** — classify a file to determine its type and handling strategy (without processing it further)
- **Parse a file** — extract structured data from a file (without building a BKO)
- **Attach a payment advice** — match a payment advice to an existing cash-clearing voucher and attach it

## When to Activate

Activate this skill when the user:
- Asks to **process**, **handle**, **book**, or **triage** files or the inbox
- Points to a specific file (by name or file ID) and asks to handle it
- Mentions **Foodora files**, **combo-invoices**, **payment advices**, **settlement files**
- Asks what a file is or what type it is
- Asks to parse, extract, or read an invoice

You can execute **partial steps** of the pipeline. If someone says "just parse this" — triage and parse, then stop. If someone says "what is this file?" — triage only, report the classification.

When intent is ambiguous, ask: "I can process this through the full booking pipeline — want me to go ahead?"

## Dependencies

This skill requires the **introspectfn-erp** skill to be installed. It uses the `ifn` CLI for:
- Fetching files from the ERP inbox (`ifn files fetch`, `ifn browse <company> inbox`)
- Looking up vouchers and financial years (`ifn records`, `ifn sync years`)
- Submitting BKOs (`ifn staging propose`)
- Writing file metadata (`ifn files metadata`)

## How It Works (overview)

The pipeline has four stages. Each stage uses a **deterministic Python script** — no LLM involved in the deterministic path. You are the **orchestrator**: you call each script, read the output, decide what to do next, and report to the user.

```
File → Triage → Parse → Build BKO → Present for Approval → Submit
         │
         ├─ deterministic → proceed through pipeline
         ├─ llm_fallback  → tag as manual_review, notify accountant
         └─ unsupported   → skip
```

The Python toolbox lives at: `~/.openclaw/workspace/skills/ifn-file-orchestrator/tools/ifn-file-orchestrator/`

**When activated, read the orchestration context** from `docs/ORCHESTRATION.md` in this skill directory for the full step-by-step instructions.

<!-- doc_version: v0.2-gap-log-and-merged-overview -->

# Triage Omni Strategy

Design contract for `triage` — the routing front-end of the
ifn-file-orchestrator → IFN pipeline.

This document is the source of truth for what triage IS and what it
PRODUCES. Implementation in `triage.py` is expected to align with this
document; today's implementation (`TRIAGE_VERSION = "v0.5-distributed-remarks"`)
is a strict subset of the contract below. Wherever the body of this doc
describes something not yet implemented, an inline footnote anchor
(`[^gap-...]`) links to a matching entry in the **gap log** at the end
of the document. As gaps close, check them off in the gap log AND
remove the matching anchor from the body — they retire together.

## 1. Purpose — the "always-useful output" principle

Triage is the *entry point* of the pipeline. Given one or more files, its
job is to decide what should happen to each file next AND to never leave
the caller empty-handed.

The minimum guarantee: every file that enters triage exits with a
structured `TriageResult` that contains:

- **what we know** about the file (identity, accumulated metadata),
- **a decision** (one label — see §5),
- **what to do next** (a concrete step for the orchestrator),
- **what has been done** (an event log of rounds and remarks),
- **remarks** that explain any noteworthiness — each carries text, a
  1-100 scalar, and an optional stable identifier (see §6). Confidence
  itself is computed by the *orchestrator* from accumulated remarks,
  not carried inside `TriageResult`.

Even when triage cannot route a file to a BKO, the output is *useful*:
the file gets metadata, the orchestrator can shelve it on the manual
queue with full traceability, and the dev-agent feedback loop can grep
remarks to find rules worth adding next.

## 2. Core mental model — triage is iterative

Triage is not a single-shot router. A file may pass through triage
multiple **rounds**, each round adding metadata until a terminal decision
is reached or convergence is detected.

```
        ┌─────────────────────────────────────────────┐
        │  round N input:                             │
        │    file ref + accumulated metadata + log    │
        └───────────────────┬─────────────────────────┘
                            │
                            ▼
                       [ triage ]
                            │
                            ▼
        ┌─────────────────────────────────────────────┐
        │  round N output (TriageResult):             │
        │    decision = <label>                       │
        │    next step = <orchestrator instruction>   │
        │    remarks = [...]                          │
        │    metadata = enriched                      │
        │    log = log_in + (round N event)           │
        └───────────────────┬─────────────────────────┘
                            │
              terminal? ────┴───── intermediate?
                  │                       │
                  ▼                       ▼
              done                orchestrator runs the
                                  next step (LLM call,
                                  batch grouping, …),
                                  attaches results as
                                  metadata, re-invokes
                                  triage with the same
                                  file ref + enriched
                                  metadata + log
```

The recursion is what makes the LLM-fallback path *useful*: a file with
no deterministic match gets sent for LLM classification, the orchestrator
attaches "company = Foodora, amount ≈ 17 000 SEK, invoice number =
7002…" as metadata, and the next round may now graduate to a deterministic
strategy (because we have a company-specific rule keyed on parsed
metadata) or to a generic BKO builder fed by extracted foreign keys.

## 3. Inputs

Triage operates on **batches** of files[^gap-e]. A single file is the
degenerate case where the batch has size 1.

A batch entry carries:

- a **file reference**: filename + content access (bytes, stream, or path)
- **prior metadata** (optional): everything previously parsed for this file
  — empty on round 1, populated on subsequent rounds
- **prior log** (optional): the event log accumulated from prior rounds

Files do not need to live on the filesystem. Production callers pass
bytes/streams; tests and CLI usage pass filenames.

Batch input enables two things a single-file API cannot:

1. **Cross-file disambiguation** — a Payment Advice dated 02.04.2026
   sitting next to a combo-invoice that pays out on 02.04.2026 is a
   strong pairing hint that neither file produces in isolation.
2. **Temporary queues** — see §8.

## 4. Universal output schema

Every `TriageResult` carries the following structure[^gap-a]. Fields are
stable across rounds and round-trip-safe (the result of round N is a
valid input to round N+1 via the orchestrator).

```
TriageResult:
  file_ref:        FileReference            # identity, content access
  metadata:        dict                     # accumulated, monotonically growing
  decision:        Label                    # one of §5 — terminal or intermediate
  next_step:       NextStep                 # concrete instruction for orchestrator
  log:             list[RoundEvent]         # round-by-round history
  remarks:         list[Remark]             # all remarks ever emitted for this file
```

`RoundEvent` is one line per round: `{round_n, timestamp, decision,
remarks_added}`. Append-only. `remarks_added` carries the actual `Remark`
objects emitted during the round, not just their IDs — so the log is
fully self-contained.

`Remark` lives in the shared module `remarks.py` and has shape
`{text: str, scalar: int, id: Optional[str]}`. `text` is human-readable
("what's noteworthy"); `scalar` is 1–100 ("how noteworthy"); `id` is an
optional stable identifier so dev tooling can aggregate the same kind of
remark across many files.

**Confidence is intentionally absent from `TriageResult`.** Triage emits
remarks; it does not compute confidence. Aggregation across all the
producers a file passes through (triage + parser + builder + …) is the
orchestrator's job — see §6.

> Future extension (deferred): allowing the orchestrator to *pass*
> `prior_confidence` *in* alongside `prior_remarks` for recursion-control
> use cases (e.g. early-terminating a loop that has burned through too
> much confidence)[^gap-h]. Not implemented today because the recursion
> driver isn't built yet; recorded here so the input shape can be
> extended without breaking callers.

`NextStep` is a structured directive for the orchestrator[^gap-b] — what
to do *outside* triage to advance this file. Examples:

- `{kind: "build_bko", parser_module: ..., builder_module: ...}`
- `{kind: "attach_to_voucher", parser_module: ..., lookup_keys: (...)}`
- `{kind: "llm_classify", skill: "Evaluating filetypes from ERP", expected_output_schema: {...}}`
- `{kind: "park_for_batch_grouping"}`
- `{kind: "send_to_manual_queue"}`

Triage describes; the orchestrator acts.

## 5. Strategy taxonomy

The decision label[^gap-c] distinguishes **terminal** outcomes (the loop
ends) from **intermediate** outcomes (re-enter triage with enriched
input).

### Terminal labels

| Label | Meaning | Typical remarks |
|---|---|---|
| `deterministic-build-bko` | Deterministic parser + builder ship a BKO. Combo-invoice today. | none (full confidence) |
| `deterministic-attach` | Deterministic parser extracts lookup keys; orchestrator finds existing voucher via CLI and attaches the file. Payment Advice today. | none |
| `deterministic-correction` | Deterministic correction-voucher recipe (e.g. POS reconciliation diffs). | none |
| `llm-classify-and-tag` | LLM classified the file and extracted foreign keys; no BKO produced. File is tagged with metadata and stored. | `LLM_CLASSIFIER_USED` |
| `llm-suggest-bko` | LLM proposed a BKO. Mandatory human review before posting. | `LLM_CLASSIFIER_USED`, `LLM_BKO_PROPOSED` |
| `tagged-no-action` | Recognised format but no action required (e.g. supporting XLS attached to a voucher elsewhere). | none |
| `manual-queue` | Triage gives up. File goes to a human queue with whatever metadata we could extract. | `NO_DETERMINISTIC_PARSER`, possibly `LLM_CLASSIFIER_INCONCLUSIVE` |

### Intermediate labels

| Label | Meaning | Orchestrator action |
|---|---|---|
| `extract-more-metadata` | Triage cannot decide yet, but has identified a way to learn more (typically: ask the LLM, using a named skill). | Run the LLM call described in `next_step`, attach output as metadata, re-invoke triage |
| `await-batch-grouping` | This file alone is ambiguous, but resolution may emerge once peers in the batch have completed round 1. | Park in temp queue; re-invoke triage after all peers have round-1 metadata |

The full *recipe* for any file is the temporal sequence of labels in
`log` — the recipe is recorded, not declared. This keeps the data model
declarative (one label per round) while allowing arbitrarily rich
compositions.

## 6. Remarks (distributed) and confidence (orchestrator-aggregated)

Remarks are emitted by **producers** — code that processes a file. Triage
is one producer; parsers, builders, the LLM classifier, and the validator
are others[^gap-g]. Each producer knows what is noteworthy in its own
context and emits remarks accordingly. There is **no global remark
catalog** — each producer keeps its own stable IDs alongside its own code.

Confidence is computed by the **orchestrator** (the production CLI
runner, or a test/validation script playing that role). The orchestrator
collects remarks across every producer that ran during a file's
lifecycle and calls `remarks.compute_confidence(all_remarks)` once,
producing a single scalar in `[0.0, 1.0]`. That scalar is shipped to
IFN in `trust.confidence`. What IFN does with it — autobook, route to
human review, hold for a rules-set evaluation — is **IFN-side policy
and outside the scope of this document**. Our job ends at producing the
number; IFN owns the consumer side.

```
   PRODUCERS  (each emits Remarks                    ORCHESTRATOR
   in its own context, no global catalog)            (aggregates ONCE)

   ┌─────────────┐
   │   triage    │ ─── remarks ───┐
   └─────────────┘                │
   ┌─────────────┐                │
   │   parser    │ ─── remarks ───┤
   └─────────────┘                │      ┌────────────────────────────┐
   ┌─────────────┐                │      │ compute_confidence(all)    │
   │  LLM step   │ ─── remarks ───┼─────►│   = ∏  (100 − r.scalar)    │
   └─────────────┘                │      │       ───────────────      │
   ┌─────────────┐                │      │             100            │
   │   builder   │ ─── remarks ───┤      └────────────┬───────────────┘
   └─────────────┘                │                   ▼
   ┌─────────────┐                │           single float ∈ [0.0, 1.0]
   │  validator  │ ─── remarks ───┘                   │
   └─────────────┘                                    ▼
                                          shipped to IFN as
                                          trust.confidence
   Each Remark =                                      │
     { text, scalar 1-100,                            ▼
       id? }                              ┌──────────────────────────┐
                                          │ IFN-side rules consume   │
                                          │ the scalar — autobook /  │
                                          │ human review / hold are  │
                                          │ IFN's call, not ours.    │
                                          └──────────────────────────┘
```

### Confidence formula

For each remark, compute a confidence factor `(100 − scalar) / 100`. The
total confidence is the product of all factors:

```
confidence = ∏ (100 − r.scalar) / 100   for r in remarks
```

The multiplicative form is the probabilistic interpretation: each remark
is an independent doubt, and confidence is the joint probability that
none of them matters. Properties:

- A single severe remark dominates but never artificially zeros the
  signal (`scalar=90` → confidence 0.10, not 0).
- Many small remarks degrade smoothly (five `scalar=10` → `0.9⁵ ≈ 0.59`).
- A single `scalar=100` remark zeroes confidence as a hard veto.
- Order-independent.

### Worked examples

| Remarks | Confidence |
|---|---|
| `[]` | 1.00 |
| `[Remark(scalar=10)]` | 0.90 |
| `[Remark(scalar=10), Remark(scalar=10)]` | 0.81 |
| `[Remark(scalar=30), Remark(scalar=50)]` | 0.35 |
| `[Remark(scalar=90)]` | 0.10 |
| `[Remark(scalar=100)]` | 0.00 |

### Triage's local remark vocabulary

The IDs and scalars below are what **triage** emits (the table mirrors
`TRIAGE_REMARK_SCALARS` in `triage.py` — keep in lockstep). Parsers,
builders and other producers maintain their own tables.

| Remark ID | Scalar | When it fires |
|---|---|---|
| `NO_DETERMINISTIC_PARSER` | 10 | No filename rule matched on round 1 |
| `MULTIPLE_CANDIDATE_FORMATS` | 15 | Two or more rules matched (ambiguous) |
| `LLM_CLASSIFIER_USED` | 30 | LLM was invoked for classification |
| `LLM_BKO_PROPOSED` | 50 | LLM-generated BKO (mandatory human review) |
| `LLM_CLASSIFIER_INCONCLUSIVE` | 25 | LLM returned a low-conviction answer |
| `BATCH_GROUPING_UNRESOLVED` | 20 | Round-2 grouping did not help |

The LLM-confidence cap falls out structurally: any path that touches the
LLM emits `LLM_CLASSIFIER_USED (30)` and frequently `LLM_BKO_PROPOSED (50)`.
Their combined factor (`0.7 × 0.5 = 0.35`) makes it mathematically
impossible for an LLM-derived BKO to reach a `≥ 0.95` autobook threshold.

Adjusting a scalar is a policy decision (it changes autobook
eligibility), which is why the table lives in this document — not in
code as an arbitrary constant. The code holds the same numbers but the
*authority* is here.

### Three execution lanes — structural confidence ceilings

The orchestrator routes a file through one of three execution lanes
depending on what triage decides. Each lane carries a structural set of
remarks that determines the maximum confidence it can ever reach — not
by a policy cap on top, but by the multiplicative formula itself.

```
   LANE                          STRUCTURAL REMARKS              MAX CONF
   ──────────────────────────────────────────────────────────────────────
   Deterministic                 (none)                          1.00
     parser + builder for                                        ▰▰▰▰▰▰▰▰▰▰
     a known format

   Skill-leveraged LLM           LLM_CLASSIFIER_USED  (s=30)     0.70
     file-type catalog                                           ▰▰▰▰▰▰▰░░░
     bounds the LLM's
     vocabulary

   Pure LLM                      LLM_CLASSIFIER_USED  (s=30)     0.35
     freeform fallback,           + LLM_BKO_PROPOSED  (s=50)     ▰▰▰░░░░░░░
     no catalog hint              (often + INCONCLUSIVE s=25 → 0.26)

   ──────────────────────────────────────────────────────────────────────
   Whatever threshold IFN's policy chooses to apply, the deterministic
   lane is the only one that *could* clear a high bar (e.g. ~0.95) by
   construction. The actual threshold and routing rules live on IFN's
   side, not ours.
```

This is the operational consequence of distributing remarks across
producers: the producer-side scalars and the formula determine what
confidence a file can structurally reach. Whether that confidence
clears any given threshold is for IFN's rules-set to decide.

### What we write into `trust.remarks` on the wire

When the orchestrator submits a BKO via `ifn bko propose`, the
producer-aggregated remark trail rides in `trust.remarks` (and the
aggregated scalar in `trust.confidence`). IFN's BKO wire treats
`trust.remarks[]` as **opaque JSON** — strict Pydantic at the top level
only; per-element shape is producer-defined. Our producer-side contract
for each remark element is:

```json
{
  "text":   "Discount rate 0.18 deviates from contractual 0.21 (-3pp)",
  "scalar": 25,
  "id":     "DISCOUNT_RATE_DEVIATION"
}
```

- `text`   — human-readable; required
- `scalar` — 1-100 noteworthiness weight; required; drives the formula
- `id`     — optional stable identifier for grep/aggregation across files

Declaring this shape *here* (in our doc, the producer side) lets IFN
engineers reading `docs/bko-implementation.md` choose how to surface
the array visually — colour severity from `scalar`, group by `id`,
filter on `text` substring. IFN doesn't validate it; we own the contract.

> Parser and builder remark vocabularies will be added next to their
> respective producers when those producers begin emitting (e.g.
> `parsers/foodora_combo_invoice.py` may emit a `DISCOUNT_RATE_DEVIATION`
> remark; `bko_builders/foodora_combo_invoice.py` may emit
> `VOUCHER_NOT_BALANCED` with a high scalar that approximates today's
> `UNBALANCED_CONFIDENCE = 0.10` floor as a single high-scalar remark
> — no special floor mechanism needed under the multiplicative form).

## 7. Recursion semantics

The orchestrator may re-invoke triage on the same file with enriched
metadata[^gap-d]. Triage itself never loops internally; the orchestrator
owns the control flow.

**Termination conditions** (whichever fires first):

1. **Terminal label reached** — the latest `decision` in the log is a
   terminal label (§5).
2. **Iteration cap** — round count reaches `MAX_TRIAGE_ROUNDS` (default 5).
   Triage emits a terminal `manual-queue` with `TRIAGE_ITERATION_CAP_REACHED`.
3. **No monotonic information gain** — the orchestrator detects that the
   most recent round added no new metadata. Triage emits a terminal
   `manual-queue` with `TRIAGE_CONVERGED_WITHOUT_RESOLUTION`.

The monotonic-information-gain rule is the safety net against infinite
loops where the LLM repeatedly returns the same partial classification.

**Idempotence requirement.** Triage with the same `(file_ref, metadata,
log)` triple must always produce the same `TriageResult`. The recursion
is reproducible from inputs alone — no hidden state.

### Worked example — three-round recursion

```
ROUND 1
  in:  foo_unknown.pdf, no prior metadata
  out: decision  = extract-more-metadata
       next_step = run LLM-classify (skill: file-type catalog)
       remarks   = [NO_DETERMINISTIC_PARSER  scalar=10]
  ── orchestrator runs the LLM, attaches output as metadata,
     re-invokes triage.

ROUND 2
  in:  foo_unknown.pdf, metadata = {vendor: Foodora,
                                    amount: ~17 000 SEK,
                                    invoice: 7002…}
  out: decision  = await-batch-grouping
       next_step = park in temp queue
       remarks  += LLM_CLASSIFIER_USED  scalar=30
  ── orchestrator parks the file; re-invokes once batch peers
     have completed their round 1.

ROUND 3
  in:  foo_unknown.pdf + batch metadata showing a paired
       Payment Advice with the same invoice number
  out: decision  = deterministic-attach     ← TERMINAL
       next_step = attach file to voucher via CLI
       remarks   = (none added)

Final:
  remarks = [NO_DETERMINISTIC_PARSER, LLM_CLASSIFIER_USED]
  compute_confidence = 0.9 × 0.7 = 0.63
  → orchestrator ships trust.confidence = 0.63 in the BKO;
    IFN-side rules decide what to do with that value.
```

The example shows all three pieces working together: intermediate
decisions enriching metadata across rounds, a structural remark
trail accumulating from each producer touched, and the orchestrator's
final `compute_confidence` call producing a single scalar that gets
handed to IFN. The routing decision (autobook vs. review vs. hold)
belongs to IFN's policy layer, not to anything in this document.

## 8. Batch mode and temporary queues

Multi-file batches enable cross-file resolution[^gap-e].

```
ROUND 1: each file individually
         │
         ├─ deterministic → terminal label (done)
         ├─ extract-more-metadata → orchestrator runs LLM, re-triages
         └─ await-batch-grouping → park in temp queue
                                              │
ROUND 2: temp queue (cross-file)              │
         │                                     │
         ├─ pairing-by-foreign-key resolves    │
         │  ambiguous files (e.g. PA ↔ combo  ◄┘
         │  invoice by invoice number)
         ├─ grouping yields enough metadata
         │  for a deterministic graduation
         └─ remaining stragglers exit via
            manual-queue or escalate to LLM
```

The orchestrator owns the temp queue. Triage just emits
`await-batch-grouping`; the orchestrator parks the file and re-invokes
triage with the full batch metadata visible when round 2 begins.

## 9. The LLM boundary

**Triage code never calls a model.** When the LLM is needed, triage emits
an intermediate decision (`extract-more-metadata` or, in rare cases, a
terminal `llm-classify-and-tag` / `llm-suggest-bko`). The orchestrator
— Claude or another agent in the higher orchestration layer — runs the
LLM, attaches the output as metadata, and re-invokes triage.

This boundary is load-bearing:

- The deterministic stack stays deterministic and testable in isolation.
- Triage has no network calls, no model-version-coupling, no API keys.
- The orchestrator decides which LLM to use, when to retry, how to budget
  spend. Triage just declares what knowledge it needs.

The LLM call is described in `next_step.skill` — a named skill the
orchestrator knows how to invoke (see §10).

## 10. Knowledge skill — the file-type catalog

The LLM-fallback path is grounded in a catalog of expected file types
that lives **next to** triage docs (not external)[^gap-f].

The catalog describes every format we currently know about — combo-invoice,
Payment Advice, POS export, supplier invoice, expense receipt, image of
receipt, bank statement, etc. — with the following per-format entries:

- **Name** and synonyms
- **Source** (which partner, which workflow)
- **Fingerprint hints** (filename pattern, content tells, distinguishing
  field names)
- **Expected foreign keys** to extract
- **Intended downstream strategy** if recognised

When the orchestrator runs an LLM classification step, it feeds the
catalog to the model as context. This means the LLM's guesses are
bounded by what we already know about, rather than free-form. The LLM is
choosing from a vocabulary, not inventing one.

A new format graduates from "LLM saw it once" → "added to the catalog as
a known type with hints" → "deterministic rule written in triage" as the
remarks index reveals the pattern.

The catalog lives at `TriageFileTypeCatalog.md` (to be created when the
LLM-fallback path is implemented).

## 11. Iterative-improvement loop

Triage's output is also a *signal* for our own development.

- **Dev / dev-agent loop**: scan all `TriageResult`s with a given
  remark (e.g. `NO_DETERMINISTIC_PARSER`); if a pattern emerges across
  multiple files, write a new deterministic rule and shrink the LLM
  workload over time. Likewise, `LLM_CLASSIFIER_USED` + repeated
  `doc_type` is a candidate for catalog expansion.
- **Accountant loop**: the manual-queue carries the full uncertainty
  trail. The accountant sees not just "low confidence" but *why*
  (missing date, ambiguous format, partial parse). Faster human triage,
  cleaner feedback.

The contract: every remark ever emitted by triage has a stable `id` and
appears in this document's table. New remarks land here first.

## 12. Non-goals

Triage does NOT handle:

- **Fetching files** — the orchestrator gathers files from inboxes,
  email, etc. and hands them to triage.
- **Scheduling** — when batches run, retry policy, rate limits.
- **Executing the next step** — triage *describes* the next step; the
  orchestrator runs it (parse, build, attach, LLM call).
- **Post-BKO state** — once a BKO is shipped to CLI, anything that
  happens to that voucher (file attachment back-fill, status updates) is
  the orchestrator's problem.

See `project_orchestration_layering` memory for the layering rationale.

## Gap log — vision vs. current implementation

`triage.py` is currently `TRIAGE_VERSION = "v0.5-distributed-remarks"`.
The body of this document is the destination; the entries below track
where today's code is short of it. Each entry has a stable anchor (e.g.
`[^gap-a]`) that the body references at the relevant point. **When a
gap closes:** check it off here AND remove the matching `[^gap-...]`
footnote anchor from the body — the two retire together so the doc
never falls out of sync.

### Gap A — schema shape

- **Vision §4:** `TriageResult{file_ref, metadata, decision, next_step, log, remarks}`.
- **Today:** `TriageResult{outcome, doc_type, strategy, parser_module, builder_module, attach_lookup_keys, matched_rule, metadata, log, remarks}` — flatter and routing-string-based.
- **Closes when:** `outcome`+`strategy` collapse into a single `decision` label per §5 and the result carries a structured `next_step` field.
- Status: [ ] open

### Gap B — structured `NextStep`

- **Vision §4:** `next_step` is a typed directive (`{kind, parser_module, builder_module, lookup_keys, skill, …}`) that orchestrators read directly.
- **Today:** orchestrators infer the next step from `outcome` + `strategy` strings.
- **Closes when:** `triage()` emits a typed `NextStep` object alongside the decision label.
- Status: [ ] open

### Gap C — full label taxonomy

- **Vision §5:** seven terminal labels (deterministic-build-bko, -attach, -correction; llm-classify-and-tag; llm-suggest-bko; tagged-no-action; manual-queue) + two intermediate labels (extract-more-metadata, await-batch-grouping).
- **Today:** three outcome strings (`deterministic` / `llm_fallback` / `unsupported`) + two strategy strings (`parse_and_build_bko`, `parse_and_attach_to_voucher`).
- **Closes when:** the orchestrator branches on the full label set; new STRATEGY_*/LABEL_* constants land alongside the matching builders/handlers (e.g. `deterministic-correction` lands with POS reconciliation).
- Status: [ ] open

### Gap D — recursion driver

- **Vision §7:** orchestrator re-invokes triage with `prior_*` inputs until terminal/cap/no-gain.
- **Today:** inputs are round-trip-safe (`prior_metadata`, `prior_log`, `prior_remarks` all accepted) but no orchestrator actually loops yet — every call today is round 1.
- **Closes when:** a recursion driver exists in the orchestrator and exercises `round_n > 1` against real input, with the termination conditions of §7 enforced.
- Status: [ ] open

### Gap E — batch mode and temporary queues

- **Vision §3, §8:** triage operates on batches natively; a `triage_batch(files)` entry-point returns a list of `TriageResult`s and supports cross-file pairing via the `await-batch-grouping` intermediate label.
- **Today:** `triage(filename)` is single-file only.
- **Closes when:** `triage_batch` exists and the orchestrator can park files between rounds.
- Status: [ ] open

### Gap F — file-type catalog

- **Vision §10:** `TriageFileTypeCatalog.md` describes every known format (name, source, fingerprint hints, expected foreign keys, intended strategy); LLM-fallback path uses it as bounding context.
- **Today:** no catalog file exists.
- **Closes when:** the catalog file is written and the LLM-classify next_step references it.
- Status: [ ] open

### Gap G — producer-side remark emission beyond triage

- **Vision §6:** parsers, builders, validators, the LLM classifier — all emit `remarks.Remark` objects in their own contexts; the orchestrator aggregates across all producers and calls `compute_confidence` once.
- **Today:** only triage emits remarks. The combo-invoice builder still computes its own confidence internally via the `UNBALANCED_CONFIDENCE = 0.10` floor — a special-case mechanism that should become a single high-scalar remark from the builder under the multiplicative form.
- **Closes when:** at least one non-triage producer emits `Remark` objects via `remarks.Remark`, and an orchestrator aggregates them with triage's remarks into a single `compute_confidence` call.
- Status: [ ] open

### Gap H — `prior_confidence` input (deferred)

- **Vision §4 (deferred future extension):** orchestrator can pass current cumulative confidence in alongside `prior_remarks` for recursion-control (e.g. early-terminating a loop that has burned through too much confidence).
- **Today:** triage accepts `prior_metadata` / `prior_log` / `prior_remarks` but not `prior_confidence`.
- **Closes when:** the recursion driver (Gap D) is built and demonstrates need.
- Status: [ ] deferred — not opening until Gap D closes.

Each gap is independently shippable; this document is the destination,
not a single-PR refactor.

[^gap-a]: See [Gap A — schema shape](#gap-a--schema-shape) in the gap log.
[^gap-b]: See [Gap B — structured `NextStep`](#gap-b--structured-nextstep) in the gap log.
[^gap-c]: See [Gap C — full label taxonomy](#gap-c--full-label-taxonomy) in the gap log.
[^gap-d]: See [Gap D — recursion driver](#gap-d--recursion-driver) in the gap log.
[^gap-e]: See [Gap E — batch mode and temporary queues](#gap-e--batch-mode-and-temporary-queues) in the gap log.
[^gap-f]: See [Gap F — file-type catalog](#gap-f--file-type-catalog) in the gap log.
[^gap-g]: See [Gap G — producer-side remark emission beyond triage](#gap-g--producer-side-remark-emission-beyond-triage) in the gap log.
[^gap-h]: See [Gap H — `prior_confidence` input (deferred)](#gap-h--prior_confidence-input-deferred) in the gap log.

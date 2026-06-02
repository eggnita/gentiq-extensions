# 10 — Update docs: openapi.json, SKILL.md, API.md

**Type:** AFK
**Blocked by:** #02, #03, #04, #05, #06, #07, #08, #09 (all implementation issues)

## What to build

Update all documentation to reflect the new API and CLI changes. These docs are what the Gent agent reads to know how to use the CLI — stale docs mean the agent calls commands wrong.

### 1. Replace `docs/openapi.json`

Replace the current `docs/openapi.json` (old spec) with the new spec from `https://ifn-stage.mayuda.com/openapi.json`. This is the source of truth for the API.

### 2. Rewrite `SKILL.md`

The 44KB `SKILL.md` is the primary reference the Gent reads. It must be updated to reflect:

- **`company_id` terminology everywhere** — no more `connection_id` in any example, explanation, or command reference
- **New `files` command group** — full reference with all subcommands, flags, and examples showing file download to temp path and referencing in conversation
- **New `xcompanies` command group** — full reference with all subcommands and flags
- **New `staging` subcommands** — archive, file-refs, uploads, upload, remove-upload
- **New `sync` subcommands** — batch, cancel-all
- **New `jobs` command group** — full reference, note about developer role requirement
- **New `companies doc-types`** and **`browse record-counts`** subcommands
- **New query param flags** — `--include-staged`, `--email`, `--phone`, `--referencenumber`, all new `files list` filters
- **FY-in-path routing** — explain that record IDs with `/` automatically use FY-in-path endpoints
- **File download workflow** — explicit example: `ifn files fetch <company_id> <file_id>` → prints temp path → agent reads/references the file
- **Updated CLI version number** if applicable

Be super explicit in SKILL.md. Every command, every flag, every example. The agent has no other reference.

### 3. Update `docs/API.md`

The 30KB `docs/API.md` REST API reference must be updated to reflect:

- **`company_id` path parameter** everywhere (was `connection_id`)
- **All new endpoints** with request/response examples
- **New query params** on existing endpoints
- **File download endpoints** with Content-Type and Content-Disposition behavior
- **Authentication requirements** per endpoint (especially developer-role endpoints in jobs group)

### Verification

After updating, grep the entire skill directory for any remaining `connection_id` references to ensure nothing was missed.

## Acceptance criteria

- [ ] `docs/openapi.json` is the new spec from staging
- [ ] `SKILL.md` documents every CLI command including all new ones
- [ ] `SKILL.md` uses `company_id` terminology exclusively — zero `connection_id` references
- [ ] `SKILL.md` includes explicit file download workflow example
- [ ] `SKILL.md` documents all new flags on existing commands
- [ ] `SKILL.md` explains FY-in-path transparent routing
- [ ] `SKILL.md` notes developer role requirement for `jobs` commands
- [ ] `docs/API.md` documents all new endpoints
- [ ] `docs/API.md` uses `company_id` exclusively
- [ ] `grep -r "connection_id" skills/introspectfn/` returns zero results after this issue is complete

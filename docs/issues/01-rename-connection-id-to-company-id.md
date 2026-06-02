# 01 — Rename `connection_id` to `company_id` globally

**Type:** AFK
**Blocked by:** None — can start immediately

## What to build

The IntrospectFN API has renamed the `connection_id` path parameter and field name to `company_id` across all endpoints. The ifn CLI and settlement CLI must be updated to match. This is a global rename touching URL construction, response parsing, JSON request payloads, bash variable names, and all user-facing help text.

### Scope

**URL paths in ifn-cli commands (29 endpoints):**
All commands that build URLs like `/api/companies/${conn_id}/...` must change the internal variable from `conn_id` to `company_id`. Affected files:
- `ifn-cli/commands/browse.sh` — 7 URL constructions
- `ifn-cli/commands/records.sh` — 2 URL constructions
- `ifn-cli/commands/analysis.sh` — 4 URL constructions
- `ifn-cli/commands/sync.sh` — 5 URL constructions
- `ifn-cli/commands/staging.sh` — 6 URL constructions
- `ifn-cli/commands/dashboard.sh` — 1 URL construction

**Response parsing:**
- `ifn-cli/commands/companies.sh:45` — change `connection_id: .connection_id` to `company_id: .company_id` in the jq format string

**JSON request payload:**
- `settlement-cli/lib/build_template.py:98` — change `"connection_id": args.company_id` to `"company_id": args.company_id`

**Help text and usage strings (38 occurrences):**
Every `ifn_require_arg` call and `echo "Usage: ..."` string that references `<connection_id>` must change to `<company_id>`. Affected files:
- `ifn` (main entry point, line 44)
- `ifn-cli/lib/format.sh` (line 72, comment)
- `ifn-cli/commands/browse.sh` (lines 6, 32, 33)
- `ifn-cli/commands/records.sh` (lines 6, 25, 26)
- `ifn-cli/commands/analysis.sh` (lines 14, 30, 52, 53, 64, 73)
- `ifn-cli/commands/sync.sh` (lines 41, 56, 65, 105, 106)
- `ifn-cli/commands/staging.sh` (lines 48, 72, 73, 136, 158, 159, 175)
- `ifn-cli/commands/dashboard.sh` (lines 6, 12)
- `ifn-cli/commands/link.sh` (lines 30, 64, 69, 82, 88, 94, 100, 106, 112, 118, 124, 129, 135, 141, 149, 154, 159, 165, 171)

**Internal bash variable names:**
- All commands using `conn_id` as a local variable should rename to `company_id` for consistency

**Settlement CLI:**
- `settlement-cli/learn.sh:206` — JSON payload field `'connection_id'` → `'company_id'`

**Also rename in DELETE /api/companies/{company_id}:**
- The old spec had `company_id` as type `integer` for this endpoint. The new spec has it as type `string`. Verify the CLI handles this correctly.

## Acceptance criteria

- [ ] All 29 URL paths in ifn-cli use `company_id` instead of `conn_id` or `connection_id`
- [ ] `companies.sh` response parser outputs `company_id` field
- [ ] `build_template.py` sends `"company_id"` in JSON payload
- [ ] `learn.sh` sends `'company_id'` in JSON payload
- [ ] All 38 help text / usage strings say `<company_id>` not `<connection_id>`
- [ ] All internal bash variables renamed from `conn_id` to `company_id`
- [ ] `ifn companies` output shows `company_id` column
- [ ] `ifn health` still works
- [ ] `ifn browse <company_id> vouchers` still works end-to-end
- [ ] Settlement CLI commands still work with the renamed variable

# 07 — Add `companies doc-types` and `browse record-counts`

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

Add two small subcommands to existing command groups.

### New commands

**`ifn companies doc-types <company_id>`**
- Endpoint: `GET /api/companies/{company_id}/allowed-doc-types`
- Returns the doc types allowed by the company's Fortnox scopes
- Useful for the agent to know what it can query before attempting — avoids 403s
- Output: list of allowed doc type strings

**`ifn browse record-counts <company_id>`**
- Endpoint: `GET /api/companies/{company_id}/external/record-counts`
- Returns live record counts from Fortnox (how many invoices, vouchers, suppliers, etc. exist)
- Useful for comparing against local sync counts to detect gaps
- Output: table of resource types and their counts

### Implementation notes

- Add `doc-types` subcommand to `ifn-cli/commands/companies.sh`
- Add `record-counts` subcommand to `ifn-cli/commands/browse.sh`
- Both are simple GET endpoints with no query params beyond the company_id path param

## Acceptance criteria

- [ ] `ifn companies doc-types <company_id>` lists allowed doc types
- [ ] `ifn browse record-counts <company_id>` shows live Fortnox counts
- [ ] Both support `--json` output flag
- [ ] Help text updated for both command groups

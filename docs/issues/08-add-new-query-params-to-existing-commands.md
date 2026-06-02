# 08 — Add new query params to existing commands

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

Several existing endpoints gained new query parameters in the API update. Expose these as CLI flags on the corresponding commands.

### Changes

**`ifn analysis accounts <company_id>` (account-analysis endpoint)**
- New flag: `--include-staged` (boolean)
- Maps to: `include_staged` query param on `GET /api/companies/{company_id}/internal/account-analysis`
- Purpose: include staged (not yet executed) bookkeeping actions in the analysis

**`ifn records list <company_id> <doc_type>` (internal/{doc_type} endpoint)**
- New flags: `--email`, `--phone`, `--referencenumber`
- Maps to: `email`, `phone`, `referencenumber` query params on `GET /api/companies/{company_id}/internal/{doc_type}`
- Purpose: search filters for customers/suppliers by email, phone, or reference number

**`ifn records files <company_id>` (internal/files endpoint, if it remains here after the `files` command group is created)**
- New flags: `--category`, `--group-id`, `--needs-categorization` (boolean), `--financial-year-id`, `--voucher-series`, `--inbox-folder`, `--sort`, `--sortdir`
- Maps to corresponding query params on `GET /api/companies/{company_id}/internal/files`
- Note: these params are also exposed via the new `ifn files list` command (issue #02). If `records files` is removed in favor of `ifn files list`, these flags only need to be on `files list`.

**`ifn jobs list <company_id>` (developer copy-jobs endpoint, if applicable)**
- Existing `copy-jobs` endpoint gained: `--sandbox` filter param
- Maps to: `sandbox` query param on `GET /api/developer/companies/{company_id}/copy-jobs`

### Implementation notes

- For boolean flags (`--include-staged`, `--needs-categorization`), when present append `=true` to query string
- Follow existing flag parsing patterns in each command file (typically `while` loop with `shift`)

## Acceptance criteria

- [ ] `ifn analysis accounts <company_id> --include-staged` sends `include_staged=true`
- [ ] `ifn records list <company_id> customers --email foo@bar.com` filters by email
- [ ] `ifn records list <company_id> suppliers --phone 555` filters by phone
- [ ] `ifn records list <company_id> vouchers --referencenumber REF1` filters by reference number
- [ ] `ifn files list <company_id> --category invoices --sort name --sortdir desc` applies all filters
- [ ] All new flags appear in `--help` output for their respective commands

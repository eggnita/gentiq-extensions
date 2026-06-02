# 03 — Add `xcompanies` command group

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

Add a new top-level `xcompanies` command group to the ifn CLI. These endpoints aggregate data across all connected Fortnox companies — no `company_id` parameter needed. All read-only.

### New commands

**`ifn xcompanies summary`**
- Endpoint: `GET /api/xcompanies/summary`
- Output: section counts across all companies

**`ifn xcompanies vouchers [options]`**
- Endpoint: `GET /api/xcompanies/vouchers`
- Flags: `--page`, `--limit`, `--search`, `--from-date`, `--to-date`, `--series`, `--number`, `--sort`, `--sortdir`

**`ifn xcompanies invoices [options]`**
- Endpoint: `GET /api/xcompanies/invoices`
- Flags: `--page`, `--limit`, `--search`, `--from-date`, `--to-date`, `--sort`, `--sortdir`

**`ifn xcompanies supplierinvoices [options]`**
- Endpoint: `GET /api/xcompanies/supplierinvoices`
- Flags: `--page`, `--limit`, `--search`, `--from-date`, `--to-date`, `--sort`, `--sortdir`

**`ifn xcompanies suppliers [options]`**
- Endpoint: `GET /api/xcompanies/suppliers`
- Flags: `--page`, `--limit`, `--search`, `--sort`, `--sortdir`

**`ifn xcompanies customers [options]`**
- Endpoint: `GET /api/xcompanies/customers`
- Flags: `--page`, `--limit`, `--search`, `--sort`, `--sortdir`

**`ifn xcompanies accounts [options]`**
- Endpoint: `GET /api/xcompanies/accounts`
- Flags: `--page`, `--limit`, `--search`, `--sort`, `--sortdir`, `--financial-year-id`, `--number-min`, `--number-max`

**`ifn xcompanies files [options]`**
- Endpoint: `GET /api/xcompanies/files`
- Flags: `--page`, `--limit`, `--doc-type`, `--search`, `--sort`, `--sortdir`, `--category`, `--group-id`, `--needs-categorization`

**`ifn xcompanies files-categories`**
- Endpoint: `GET /api/xcompanies/files/categories`
- Output: cross-company category directory

**`ifn xcompanies files-groups`**
- Endpoint: `GET /api/xcompanies/files/groups`
- Output: cross-company group directory

### Implementation notes

- Create `ifn-cli/commands/xcompanies.sh`
- Register in main `ifn` entry point
- These endpoints have no `company_id` path param — they go directly to `/api/xcompanies/...`
- Response items include a `company_name` or `company_id` field to identify which company each record belongs to — include this in table output

## Acceptance criteria

- [ ] `ifn xcompanies summary` returns cross-company counts
- [ ] `ifn xcompanies vouchers --from-date 2025-01-01 --series A` filters correctly
- [ ] `ifn xcompanies invoices`, `supplierinvoices`, `suppliers`, `customers`, `accounts` all work with pagination
- [ ] `ifn xcompanies files --category X` filters correctly
- [ ] `ifn xcompanies files-categories` and `files-groups` return directory listings
- [ ] All commands support `--json` output flag
- [ ] Table output includes company identification column
- [ ] `ifn xcompanies --help` shows usage for all subcommands

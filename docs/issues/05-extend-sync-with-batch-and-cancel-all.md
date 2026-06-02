# 05 — Extend `sync` with batch and cancel-all

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

Add two new subcommands to the existing `sync` command group.

### New commands

**`ifn sync batch`**
- Endpoint: `POST /api/sync/batch`
- Triggers a sync across all connected companies at once
- Output: confirmation with job details

**`ifn sync cancel-all <company_id> [options]`**
- Endpoint: `POST /api/companies/{company_id}/sync/cancel-all`
- Cancels all running sync jobs for a company
- Optional flag: `--parent-job-id` to scope cancellation to jobs under a specific parent
- Output: confirmation with number of jobs cancelled

### Implementation notes

- Extend `ifn-cli/commands/sync.sh` with the new subcommands
- `sync batch` has no company_id param — it operates globally
- `sync cancel-all` follows the same pattern as existing `sync cancel`

## Acceptance criteria

- [ ] `ifn sync batch` triggers sync across all companies
- [ ] `ifn sync cancel-all <company_id>` cancels all running jobs
- [ ] `ifn sync cancel-all <company_id> --parent-job-id 5` scopes cancellation
- [ ] Both commands support `--json` output flag
- [ ] Help text updated with new subcommands

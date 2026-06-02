# 06 — Add `jobs` read-only command group

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

Add a new top-level `jobs` command group for operational visibility into sync, copy, and purge jobs. These use developer-role endpoints but are strictly read-only — no cancel/resume/cleanup operations.

### New commands

**`ifn jobs sync <job_id>`**
- Endpoint: `GET /api/developer/sync-jobs/{job_id}`
- Output: sync job details (status, progress, timestamps)

**`ifn jobs sync-log <job_id>`**
- Endpoint: `GET /api/developer/sync-jobs/{job_id}/log`
- Output: sync job log entries

**`ifn jobs list <company_id> [options]`**
- Endpoint: `GET /api/developer/companies/{company_id}/job-logs`
- Lists copy/purge jobs for a company
- Flag: `--limit` (default from API)

**`ifn jobs stale`**
- Endpoint: `GET /api/developer/syshealth/cleanup/stale-jobs`
- Previews stale running/pending/cancelling jobs without modifying them

**`ifn jobs restart-history [options]`**
- Endpoint: `GET /api/developer/syshealth/restart-history`
- Flag: `--limit`
- Output: recent server restart events

### Implementation notes

- Create `ifn-cli/commands/jobs.sh`
- Register in main `ifn` entry point
- These endpoints require developer role — the CLI should surface any 403 errors clearly (e.g. "This command requires developer access")
- All read-only: no POST/DELETE operations in this command group

## Acceptance criteria

- [ ] `ifn jobs sync <job_id>` returns job details
- [ ] `ifn jobs sync-log <job_id>` returns job log
- [ ] `ifn jobs list <company_id>` lists jobs with optional `--limit`
- [ ] `ifn jobs stale` previews stale jobs
- [ ] `ifn jobs restart-history` shows restart events with optional `--limit`
- [ ] All commands support `--json` output flag
- [ ] 403 errors produce a clear "requires developer access" message
- [ ] `ifn jobs --help` shows usage for all subcommands

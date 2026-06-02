# 02 — Add `files` command group (list, fetch, refresh, metadata)

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

Add a new top-level `files` command group to the ifn CLI. This enables the Gent agent to browse, download, categorize, and inspect file attachments stored in the IntrospectFN system. Downloaded files are saved to a temp path that the agent references in conversation.

### New commands

**`ifn files list <company_id> [options]`**
- Endpoint: `GET /api/companies/{company_id}/internal/files`
- Query params as flags: `--page`, `--limit`, `--doc-type`, `--search`, `--sort`, `--sortdir`, `--category`, `--group-id`, `--needs-categorization` (boolean), `--financial-year-id`, `--voucher-series`, `--inbox-folder`
- Output: table or JSON list of files

**`ifn files fetch <company_id> <file_id>`**
- Endpoint: `GET /api/companies/{company_id}/internal/archive/{file_id}`
- Downloads file binary to a temp path (e.g. `/tmp/ifn-<file_id>-<original_name>`)
- Prints the temp file path to stdout so the agent can reference it
- No `?inline=` param (default attachment disposition)

**`ifn files fetch --live <company_id> <file_id>`**
- Endpoint: `GET /api/companies/{company_id}/external/archive/{file_id}`
- Same behavior as above but fetches directly from Fortnox instead of local storage

**`ifn files refresh <company_id> <file_id>`**
- Endpoint: `POST /api/companies/{company_id}/files/{file_id}/refresh`
- Re-downloads a file binary from Fortnox into local storage
- Output: confirmation message

**`ifn files categories <company_id>`**
- Endpoint: `GET /api/companies/{company_id}/files/categories`
- Output: table of categories with counts

**`ifn files groups <company_id> [group_id]`**
- Without group_id → `GET /api/companies/{company_id}/files/groups` (list all groups with counts + sample filename)
- With group_id → `GET /api/companies/{company_id}/files/groups/{group_id}` (list files in that group)

**`ifn files inbox-folders <company_id>`**
- Endpoint: `GET /api/companies/{company_id}/files/inbox-folders`
- Output: inbox folder breakdown for the files-list folder picker

**`ifn files refs <company_id> <file_id>`**
- Endpoint: `GET /api/companies/{company_id}/files/{file_id}/refs`
- Output: list of all ERP records that reference this file

**`ifn files metadata <company_id> <file_id> [options]`**
- Endpoint: `PATCH /api/companies/{company_id}/files/{file_id}/metadata`
- Flags: `--category`, `--group-id`, `--details`
- Sends JSON body with provided fields
- Output: updated file metadata

### Implementation notes

- Create `ifn-cli/commands/files.sh` following the same pattern as `browse.sh` and `records.sh`
- Register the `files` command in the main `ifn` entry point
- Use `ifn_http_get`, `ifn_http_post`, `ifn_http_patch` from `lib/http.sh`
- For `fetch`: use `curl` directly to write binary to temp file, extract filename from `Content-Disposition` header if available
- Support `--json` output flag on all list commands

## Acceptance criteria

- [ ] `ifn files list <company_id>` returns paginated file list
- [ ] `ifn files list <company_id> --category X --search Y` filters correctly
- [ ] `ifn files fetch <company_id> <file_id>` downloads to temp path and prints the path
- [ ] `ifn files fetch --live <company_id> <file_id>` downloads from Fortnox
- [ ] `ifn files refresh <company_id> <file_id>` triggers re-download
- [ ] `ifn files categories <company_id>` lists categories with counts
- [ ] `ifn files groups <company_id>` lists groups; `ifn files groups <company_id> <group_id>` lists files in group
- [ ] `ifn files inbox-folders <company_id>` shows folder breakdown
- [ ] `ifn files refs <company_id> <file_id>` shows referencing records
- [ ] `ifn files metadata <company_id> <file_id> --category X` updates metadata
- [ ] All commands support `--json` output flag
- [ ] `ifn files --help` shows usage for all subcommands

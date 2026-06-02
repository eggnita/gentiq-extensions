# 04 — Extend `staging` with archive, uploads, and file-refs

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

Add new subcommands to the existing `staging` command group for managing archives, staged file uploads, and file references on bookkeeping actions.

### New commands

**`ifn staging archive [options]`**
- Without `--action-id`: `POST /api/bk-staging/archive` — bulk archive rejected/failed actions (owner only)
- With `--action-id X`: `POST /api/bk-staging/{action_id}/archive` — archive a single action

**`ifn staging file-refs <action_id> [options]`**
- Endpoint: `PATCH /api/bk-staging/{action_id}/file-refs`
- Replaces the `file_refs` list on a staged action
- Accepts JSON body via stdin or `--data` flag with the new file_refs array

**`ifn staging uploads <action_id>`**
- Endpoint: `GET /api/bk-staging/{action_id}/uploads`
- Lists all staged uploads for a bookkeeping action
- Output: table or JSON list of uploads

**`ifn staging upload <action_id> <file_path>`**
- Endpoint: `POST /api/bk-staging/{action_id}/upload-file`
- Uploads a file and attaches it to an existing bookkeeping action (action-scoped, not company-scoped)
- This is different from the existing company-scoped `staging upload <company_id> <file_path>` — both should coexist
- Use multipart/form-data upload

**`ifn staging remove-upload <action_id> <file_id>`**
- Endpoint: `DELETE /api/bk-staging/{action_id}/uploads/{file_id}`
- Removes a pending staged upload from an action

### Implementation notes

- Extend `ifn-cli/commands/staging.sh` with the new subcommands
- The existing `staging upload` is company-scoped (`POST /api/companies/{company_id}/bk-staging/upload-file`). The new action-scoped upload is `POST /api/bk-staging/{action_id}/upload-file`. Disambiguate in help text.
- For `file-refs`, accept a JSON array of file ref objects via `--data '["file_id_1","file_id_2"]'` or piped stdin

## Acceptance criteria

- [ ] `ifn staging archive` bulk-archives rejected/failed actions
- [ ] `ifn staging archive --action-id 42` archives a single action
- [ ] `ifn staging file-refs <action_id> --data '[...]'` replaces file refs
- [ ] `ifn staging uploads <action_id>` lists staged uploads
- [ ] `ifn staging upload <action_id> <file_path>` uploads and attaches file to action
- [ ] `ifn staging remove-upload <action_id> <file_id>` removes an upload
- [ ] Existing company-scoped `staging upload <company_id> <file>` still works
- [ ] All commands support `--json` output flag
- [ ] Help text clearly distinguishes company-scoped vs action-scoped uploads

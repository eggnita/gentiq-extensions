# 09 — Transparent FY-in-path routing

**Type:** AFK
**Blocked by:** #01 (rename connection_id to company_id)

## What to build

The new API added endpoint variants that put the financial year segment directly in the URL path instead of as a query parameter. The CLI should transparently route to the correct variant based on the record ID format — no new user-facing commands needed.

### FY-in-path variants

| Standard endpoint | FY-in-path variant | When to use |
|---|---|---|
| `GET .../internal/{doc_type}/{record_id}?financial_year_id=X` | `GET .../internal/{doc_type}/{fy_segment}/{record_id}` | Record ID contains `/` (e.g. `FY-1/A123`) |
| `POST .../internal/{doc_type}/{record_id}/refresh?financial_year_id=X` | `POST .../internal/{doc_type}/{fy_segment}/{record_id}/refresh` | Record ID contains `/` |
| `GET .../external/{resource}/{path}` | `GET .../external/{resource}/{fy_segment}/{path}` | Path contains `/` with FY prefix |
| `GET .../accounts/{account_number}?financialyear=X` | `GET .../accounts/{fy_segment}/{account_number}` | Explicit FY segment provided |

### Detection logic

When the CLI receives a record ID argument:
1. If the ID contains a `/` character (e.g. `FY-1/A123`), split on the first `/` into `fy_segment` and `record_id`, then use the FY-in-path variant
2. If the ID does not contain `/`, use the standard endpoint with optional `--financial-year-id` query param

This already matches how the settlement CLI constructs paths like `/internal/vouchers/FY-${fy_id}/${series}${number}`.

### Affected commands

- `ifn records get <company_id> <doc_type> <record_id>` — route to FY-in-path when ID has `/`
- `ifn records refresh <company_id> <doc_type> <record_id>` — same detection
- `ifn browse <company_id> <resource> <record_id>` — same detection for external detail
- `ifn browse account <company_id> <account_number>` — support `FY-1/1930` format

### Implementation notes

- Add a helper function (e.g. `ifn_split_fy_path`) in `lib/format.sh` or `lib/http.sh` that takes a record ID and returns either `(fy_segment, record_id)` or `("", original_id)`
- Apply the helper in `records.sh` and `browse.sh` before constructing URLs
- The settlement CLI already handles this correctly — no changes needed there

## Acceptance criteria

- [ ] `ifn records get <company_id> vouchers FY-1/A123` routes to `/internal/vouchers/FY-1/A123`
- [ ] `ifn records get <company_id> suppliers 42` routes to `/internal/suppliers/42` (no change)
- [ ] `ifn records get <company_id> suppliers 42 --financial-year-id 1` routes to `/internal/suppliers/42?financial_year_id=1`
- [ ] `ifn records refresh <company_id> vouchers FY-1/A123` routes to FY-in-path refresh
- [ ] `ifn browse <company_id> vouchers FY-1/A123` routes to FY-in-path external detail
- [ ] Settlement CLI paths remain unaffected
- [ ] Helper function is reusable across commands

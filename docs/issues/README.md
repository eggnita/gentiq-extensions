# IFN Extension — API Update Issues

IntrospectFN-ERP API update: align the ifn CLI extension with the new API surface.

## Dependency Graph

```
#01 Rename connection_id → company_id
 ├── #02 Add files command group
 ├── #03 Add xcompanies command group
 ├── #04 Extend staging (archive, uploads, file-refs)
 ├── #05 Extend sync (batch, cancel-all)
 ├── #06 Add jobs read-only command group
 ├── #07 Add companies doc-types + browse record-counts
 ├── #08 Add new query params to existing commands
 └── #09 Transparent FY-in-path routing
      └── #10 Update docs (openapi.json, SKILL.md, API.md)
```

## Issues

| # | Title | Type | Blocked by |
|---|-------|------|------------|
| [01](01-rename-connection-id-to-company-id.md) | Rename `connection_id` → `company_id` globally | AFK | None |
| [02](02-add-files-command-group.md) | Add `files` command group | AFK | #01 |
| [03](03-add-xcompanies-command-group.md) | Add `xcompanies` command group | AFK | #01 |
| [04](04-extend-staging-with-archive-uploads-filerefs.md) | Extend staging (archive, uploads, file-refs) | AFK | #01 |
| [05](05-extend-sync-with-batch-and-cancel-all.md) | Extend sync (batch, cancel-all) | AFK | #01 |
| [06](06-add-jobs-read-only-command-group.md) | Add `jobs` read-only command group | AFK | #01 |
| [07](07-add-companies-doc-types-and-browse-record-counts.md) | Add `companies doc-types` + `browse record-counts` | AFK | #01 |
| [08](08-add-new-query-params-to-existing-commands.md) | Add new query params to existing commands | AFK | #01 |
| [09](09-transparent-fy-in-path-routing.md) | Transparent FY-in-path routing | AFK | #01 |
| [10](10-update-docs-openapi-skill-md-api-md.md) | Update docs (openapi.json, SKILL.md, API.md) | AFK | #02-#09 |

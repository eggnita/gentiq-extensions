# IntrospectFN — API Reference

> Machine-readable OpenAPI 3.1 spec: [`openapi.json`](./openapi.json)

---

## 1. System Overview

IntrospectFN is a multi-tenant bookkeeping introspection platform that connects to the **Fortnox ERP** system. It lets teams browse, sync, stage, and approve accounting actions against one or more Fortnox companies. The platform is designed as the **ERP domain module** in a broader group operating platform, with the API serving both a web GUI and a planned CLI/AI-agent layer.

| Property | Value |
|----------|-------|
| Base URL (local) | `http://localhost:8000` |
| Base URL (staging) | `https://ifn-stage.mayuda.com` |
| API prefix | `/api` |
| Auth prefix | `/auth` |
| OpenAPI version | 3.1.0 |
| Content-Type | `application/json` (unless noted) |
| Backend | Python / FastAPI |
| Database | SQLite (dev & current staging), PostgreSQL planned |

### What the platform does

1. **Connects** to one or more Fortnox companies via OAuth2 and stores encrypted access/refresh tokens.
2. **Syncs** ERP data (vouchers, invoices, suppliers, customers, accounts, etc.) into a local database for fast browsing, analysis, and integrity checks.
3. **Stages** bookkeeping mutations (voucher creation, file attachments, account updates, etc.) through a propose → review → approve → execute workflow.
4. **Manages** multi-user access with role-based permissions and an invite system.
5. **Provides** developer tools for sandbox management, data copy, and system health monitoring.

### Architecture at a glance

```
                   ┌────────────────────────────────────────┐
  Browser/CLI ───→ │  nginx :80/443                         │
                   │    ├─ /api/*  → FastAPI backend :8080   │
                   │    └─ /*      → Vite/React SPA          │
                   │                                         │
                   │  Backend ↔ SQLite (/mnt/data)           │
                   │  Backend ↔ Fortnox API (rate-limited)   │
                   └────────────────────────────────────────┘
```

Deployed on a GCP Compute Engine VM (e2-small, Stockholm `europe-north2`) with Docker Compose. HTTPS via Certbot. Secrets in GCP Secret Manager.

---

## 2. Authentication

There are two separate OAuth flows: one for **user sessions** (Google) and one for **ERP connections** (Fortnox). They are independent.

### 2.1 User session (Google OAuth)

All protected endpoints require a **session cookie** named `session`. It contains an HS256 JWT with a **7-day** expiry.

**JWT payload:**
```json
{
  "id": 1,
  "email": "user@example.com",
  "name": "Jane Doe",
  "role": "owner",
  "is_developer": true,
  "iat": 1710000000,
  "exp": 1710604800
}
```

Cookie attributes: `httpOnly`, `SameSite=Lax`, `Secure` (on HTTPS).

**Security notes:**
- The JWT signing key (`JWT_SIGNING_KEY`) is **rotated on every deploy**, invalidating all sessions.
- The encryption key (`SECRET_KEY`) for ERP tokens is stable and never auto-rotated.
- The backend **re-validates the user against the database on every request** — role changes, archiving, and deletion take immediate effect regardless of what the JWT says.

#### Login flow

1. Redirect user to `GET /auth/login/google` (optionally with `?invite=<token>`).
2. Backend redirects to Google's consent screen.
3. Google redirects to `GET /auth/login/google/callback` with an authorization code.
4. Backend exchanges code → fetches user info → creates/updates user → issues JWT cookie → redirects to frontend.

#### Sign-in gate

| Condition | Result |
|-----------|--------|
| 0 existing users | Auto-create as `owner` (bootstrap) |
| User already in DB | Normal login, role unchanged |
| New user + valid unused unexpired invite | Create with invite's role, mark invite used |
| New user + no invite (or invalid/expired) | Create with `pending` role — blocked until owner assigns a role |
| Archived user | 403 on all requests, shown "access denied" screen |

#### `/api/me` response

This endpoint is the primary session check. It returns 200 in all cases:

- **Authenticated:** `{ user: { id, email, name, role }, needs_auth: true }`
- **Not authenticated:** `{ user: null, needs_auth: true }`
- **Dev bypass (no Google configured):** `{ user: <dev-user>, needs_auth: false }`
- **Authenticated developer:** response also includes `unread_notifications` count

#### Dev login (local only)

When `GOOGLE_CLIENT_ID` is not set, the backend exposes:

```
GET /auth/dev-login?role=owner|accountant|assistant|viewer|developer
```

Creates/updates a dev user, sets session cookie, redirects to frontend. Disabled when Google auth is configured.

### 2.2 CLI / API key auth (planned, not yet implemented)

The `api_keys` table exists in the database (migration 005) but no routes are wired yet.

**Planned flow:**
1. An `owner` or `developer` user issues an API key via the UI.
2. Key stored as PBKDF2 hash in `api_keys` table.
3. CLI/bot sends `Authorization: Bearer <key>` on every request.
4. Backend verifies hash, checks expiry/scopes, injects the associated user.

**Planned schema:**
```sql
CREATE TABLE api_keys (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_hash     TEXT NOT NULL UNIQUE,
    label        TEXT NOT NULL DEFAULT '',
    scopes       TEXT NOT NULL DEFAULT '',
    last_used_at TEXT,
    expires_at   TEXT
);
```

**Until API keys are implemented**, a CLI can authenticate by:
- Performing the Google OAuth flow in a browser and extracting the `session` cookie, OR
- Using `GET /auth/dev-login?role=X` in local dev mode.

### 2.3 `X-Bot-Client` header

The backend already recognises and logs the `X-Bot-Client` header. CLI and bot clients should send this header to identify themselves. Future versions will use it for audit trail differentiation.

```
X-Bot-Client: introspect-cli/0.1.0
```

### 2.4 Logout

```
POST /auth/logout
```

Clears the session cookie.

---

## 3. ERP Connection (Fortnox OAuth)

Each connected company has its own Fortnox OAuth tokens, managed separately from user sessions.

### Connection flow

1. `GET /auth/connect` — initiates Fortnox OAuth with CSRF state (10-minute TTL).
2. User authorizes in Fortnox.
3. `GET /auth/callback` — exchanges code for access/refresh tokens, encrypts them (AES-256-GCM, PBKDF2 key derivation), and stores alongside company metadata (name, org number, database number).

Re-authorization: `GET /auth/connect?reauth={orgNumber}` updates tokens for an existing company instead of creating a new one. Uses `prompt=consent` to force a fresh refresh token.

### Token health

Each company has a `token_health` field. The backend tracks this automatically:

| State | Meaning | Recovery |
|-------|---------|----------|
| `healthy` | Last refresh succeeded | None needed |
| `refresh_token_invalid` | `invalid_grant` from Fortnox | User must re-authorize via `/auth/connect` |

Transient errors (`network`, `server`) are raised as exceptions but not persisted — they may self-resolve.

Token refresh happens transparently before each Fortnox API call when the access token is within 5 minutes of expiry. The CLI does not need to manage tokens directly.

---

## 4. Role-Based Access Control

### Roles

| Role | Description | Capabilities |
|------|-------------|--------------|
| `owner` | Data ownership responsibility | Everything: user/invite management, company deletion, all staging operations, developer flags |
| `accountant` | Accounting lead | Browse, sync, approve/reject staging, execute staged actions |
| `assistant` | Data entry / AI bot | Browse, propose (stage) actions, edit own actions, clone |
| `viewer` | Read-only | Browse companies, ERP records, dashboard, analysis |
| `pending` | Awaiting owner approval | **Blocked** — 403 on all protected endpoints |

### Developer flag

The boolean `is_developer` attribute is **orthogonal to roles**. A user with any role + `is_developer = true` gets access to `/api/developer/*` endpoints. Developers can toggle company safety flags, manage sandboxes, view system health, and receive system notifications.

### Bot/CLI roles

| Role | What a bot can do |
|------|-------------------|
| `assistant` | View all data, propose staging actions |
| `accountant` | + Approve and execute staging actions |

Bots will **never** hold `owner` — that role requires human accountability.

### Authorization matrix (internal)

| Check | Roles allowed |
|-------|---------------|
| `require_owner` | `owner` |
| `require_accountant_plus` | `owner`, `accountant` |
| `require_stage` | `owner`, `accountant`, `assistant` |
| `require_developer` | any role where `is_developer = true` |

---

## 5. Endpoint Reference

All endpoints return JSON unless otherwise noted. Path parameters in `{braces}`. Responses include standard FastAPI validation (422 on malformed input).

### 5.1 Health

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | No | Returns `{"ok": true}` |

### 5.2 Auth & Session

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/auth/connect` | No | Start Fortnox OAuth (optional `?reauth={orgNumber}`) |
| GET | `/auth/callback` | No | Fortnox OAuth callback |
| GET | `/auth/login/google` | No | Start Google OAuth (optional `?invite=<token>`) |
| GET | `/auth/login/google/callback` | No | Google OAuth callback |
| POST | `/auth/logout` | No | Clear session cookie |
| GET | `/auth/dev-login` | No | Dev-only quick login (`?role=owner\|accountant\|...`) |
| GET | `/api/me` | Optional | Current user info, or `{user: null}` if unauthenticated |

### 5.3 Companies

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `/api/companies` | Yes | any | List all connected companies (includes token health badge) |
| DELETE | `/api/companies/{company_id}` | Yes | owner | Delete a company and all associated data |
| POST | `/api/companies/{company_id}/refresh-token` | Yes | owner | Force-refresh the ERP OAuth token |

**Company identification:** Most per-company endpoints use `{connection_id}` (a UUID), not `{company_id}` (an integer). The `connection_id` is available in the company list response.

### 5.4 External ERP (Proxy)

These endpoints proxy requests to the Fortnox API through the backend's rate-limited client. The CLI can use these to browse live ERP data without managing Fortnox tokens directly.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `…/{connection_id}/external/{resource}` | Yes | List a resource (paginated) |
| GET | `…/{connection_id}/external/{resource}/{path}` | Yes | Get a single resource record |
| GET | `…/{connection_id}/accounts/{account_number}` | Yes | Get account description |
| GET | `…/{connection_id}/fileconnections` | Yes | File attachments for an entity (`?entity_type&entity_id`) |
| GET | `…/{connection_id}/archive/{file_id}` | Yes | Download archive file (binary) |
| GET | `…/{connection_id}/fileconnection-counts` | Yes | Batch file-attachment counts (`?entities=type:id,...`) |
| GET | `…/{connection_id}/inbox` | Yes | List ERP inbox |
| GET | `…/{connection_id}/inbox/file/{file_id}` | Yes | Download inbox file (binary) |
| GET | `…/{connection_id}/inbox/{folder_id}` | Yes | List inbox folder |

All paths above are prefixed with `/api/companies`.

**Query params for resource listing:** `page`, `limit`, `filter`, `sortby`, `sortorder`, `financialyear`, `lastmodified`

**Valid `resource` values:** `customers`, `invoices`, `articles`, `accounts`, `vouchers`, `suppliers`, `orders`, `offers`, `projects`, `costcenters`, `supplierinvoices`, `companyinformation`, `financialyears`, `voucherseries`

### 5.5 Sync (Local Data)

The sync system downloads ERP data into a local database for fast offline access. Sync is two-phase: first a **stub pass** (list endpoints), then a **detail enrichment pass** (per-record fetch).

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `…/{connection_id}/sync/financial-years` | Yes | any | List financial years for a company |
| GET | `…/{connection_id}/sync/status` | Yes | any | Current sync job status (includes `pending_detail` counts) |
| POST | `…/{connection_id}/sync` | Yes | accountant+ | Trigger a sync job |
| POST | `…/{connection_id}/sync/{job_id}/cancel` | Yes | any | Cancel a running sync job |
| DELETE | `…/{connection_id}/internal` | Yes | developer | Purge all locally synced data |
| GET | `…/{connection_id}/dashboard` | Yes | any | Dashboard metrics (unbooked vouchers, staged actions, sync freshness, pending enrichment) |
| GET | `…/{connection_id}/internal/account-analysis` | Yes | any | Vouchers grouped by account |
| GET | `…/{connection_id}/internal/accounts/{number}/year-balances` | Yes | any | Account balance across financial years |
| GET | `…/{connection_id}/internal/integrity` | Yes | any | Data integrity check |
| GET | `…/{connection_id}/internal/voucherseries-map` | Yes | any | Voucher series → description mapping |
| GET | `…/{connection_id}/internal/{doc_type}` | Yes | any | List local records (paginated, `?include_staged=true` for vouchers) |
| GET | `…/{connection_id}/internal/{doc_type}/{record_id}` | Yes | any | Get a single local record |
| POST | `…/{connection_id}/internal/{doc_type}/{record_id}/refresh` | Yes | any | Re-fetch a record from ERP |
| GET | `/api/sync/overview` | Yes | any | Global sync status across all companies |

All per-company paths above are prefixed with `/api/companies`.

**Sync request body:**
```json
{
  "doc_types": ["vouchers", "invoices", "supplierinvoices", "customers", "suppliers"],
  "financial_year_id": 6,
  "mode": "full",
  "fromdate": "2025-01-01",
  "todate": "2025-12-31"
}
```

`mode` can be `full` (re-sync everything) or `enrich_only` (only fetch detail for pending stubs).

**Synced doc types:** `vouchers`, `invoices`, `supplierinvoices`, `customers`, `suppliers`, `accounts`, `financialyears`, `voucherseries`

### 5.6 Staging (Bookkeeping Actions)

The staging system is the **core feature for CLI/bot integration**. It implements a propose → review → approve → execute workflow for accounting mutations. The backend carries all validation and ordering logic, so CLI clients get the same guarantees as the GUI.

#### Endpoints

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `…/{connection_id}/staging` | Yes | any | List staging actions for a company |
| POST | `…/{connection_id}/staging` | Yes | assistant+ | Propose a staging action |
| GET | `…/{connection_id}/staging/next-number` | Yes | any | Predicted next voucher number (`?series=A&financial_year_id=6`) |
| POST | `…/{connection_id}/staging/upload-file` | Yes | assistant+ | Upload file to ERP (multipart), returns `{file_id, filename}` |
| GET | `…/{connection_id}/write-windows` | Yes | any | List write windows |
| POST | `…/{connection_id}/write-windows` | Yes | owner | Create a write window |
| DELETE | `…/{connection_id}/write-windows/{window_id}` | Yes | any | Delete a write window |
| GET | `/api/staging` | Yes | any | List all staging actions across companies |
| GET | `/api/staging/{action_id}` | Yes | any | Get a staging action |
| POST | `/api/staging/{action_id}/approve` | Yes | accountant+ | Approve an action |
| POST | `/api/staging/{action_id}/reject` | Yes | accountant+ or own | Reject an action |
| PATCH | `/api/staging/{action_id}` | Yes | accountant+ or own | Edit an action (payload, notes, reasoning) |
| POST | `/api/staging/{action_id}/clone` | Yes | assistant+ | Clone an existing action |
| POST | `/api/staging/{action_id}/resume` | Yes | accountant+ | Clear `on_hold` flag, make eligible for execution |
| POST | `/api/staging/execute` | Yes | accountant+ | Execute a batch of approved actions |

Per-company paths prefixed with `/api/companies`.

#### Entity types

| Entity type | Action | What it does on execute |
|-------------|--------|------------------------|
| `voucher` | `create` | POST to Fortnox `/vouchers` |
| `file_connection` | `create` | POST to Fortnox `/fileattachments` (link file to entity) |
| `company_information` | `update` | PUT to Fortnox `/companyinformation` |
| `account` | `create` or `update` | POST or PUT to Fortnox `/accounts/{number}` |
| `voucher_series` | `update` | PUT to Fortnox `/voucherseries/{code}` |

#### Stage action request body

```json
{
  "entity_type": "voucher",
  "action": "create",
  "payload": {
    "VoucherSeries": "A",
    "TransactionDate": "2025-06-15",
    "Description": "Office supplies",
    "VoucherRows": [
      { "Account": 6110, "Debit": 1000, "Credit": 0 },
      { "Account": 1930, "Debit": 0, "Credit": 1000 }
    ]
  },
  "file_refs": ["file-uuid-from-upload"],
  "accounting_reasoning": "Monthly office supply purchase from Staples...",
  "notes": "June supplies",
  "sequence": 1,
  "predicted_number": "A7",
  "strict_number": false,
  "financial_year_id": "6",
  "target_date": "2025-06-15"
}
```

**Field details:**
- `accounting_reasoning` — unbounded text explaining the accounting rationale (written by AI bot or human; never truncated)
- `notes` — condensed human-readable note, may flow into ERP
- `sequence` — controls execution order (lower first); server auto-assigns if omitted
- `predicted_number` — e.g. `"A7"`; server auto-computes from local data + staged actions if omitted
- `strict_number` — if `true`, execution aborts and deletes the voucher from ERP if the actual number differs from predicted
- `financial_year_id` — required for vouchers; scopes the predicted number computation
- `target_date` — used for write-window validation (vouchers only)

#### Execution lifecycle

```
propose → status: proposed
   └── server computes predicted_number if omitted
   └── predicted_series derived from payload.VoucherSeries (internal)

approve → status: approved

execute (ordered by sequence ASC, id ASC):
  for each approved action (where on_hold = 0):
    1. allow_mutation check (company flag)
    2. write-window check (vouchers with target_date only)
    3. POST/PUT to Fortnox
    4a. success + strict_number + actual != predicted
        → DELETE from ERP → mark failed → halt company
    4b. success
        → upsert local ERP stub → mark executed
    4c. failure
        → mark failed → set on_hold on remaining same-company actions

resume → clears on_hold → eligible for next execute batch
```

#### Write windows

Write windows define open date ranges for a company. When windows exist, voucher actions whose `target_date` falls outside all windows are rejected at execution time. Non-voucher entity types bypass the check.

```json
POST /api/companies/{connection_id}/write-windows
{ "from_date": "2025-01-01", "to_date": "2025-12-31", "label": "FY 2025" }
```

#### Execute request body

```json
{ "action_ids": [1, 2, 3] }
```

If `action_ids` is omitted, all approved non-held actions are executed.

#### CLI bot workflow

A typical AI bot (`assistant` role) interaction:

1. **Read data** — browse synced records, run account analysis, check integrity
2. **Propose** — `POST /api/companies/{org}/staging` with full `accounting_reasoning`
3. **Human review** — accountant reviews reasoning in the web UI and approves
4. **Execute** — human (or trusted `accountant` bot) calls `POST /api/staging/execute`

### 5.7 Users & Invites

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `/api/users` | Yes | owner | List all users (id, email, name, role, created_at, last_login) |
| PATCH | `/api/users/{user_id}/role` | Yes | owner | Update role (cannot demote last owner) |
| PATCH | `/api/users/{user_id}/developer` | Yes | owner | Toggle `is_developer` flag |
| PATCH | `/api/users/{user_id}/archive` | Yes | owner | Archive / un-archive (cannot archive self) |
| GET | `/api/invites` | Yes | owner | List invites (pending + recently used) |
| POST | `/api/invites` | Yes | owner | Create invite link `→ {id, token, url, role, expires_at}` |
| DELETE | `/api/invites/{invite_id}` | Yes | owner | Revoke a pending invite |
| GET | `/api/invites/preview` | No | — | Preview invite details (`?token=<hex>`) `→ {role, invited_by_name, expires_at}` |

**Invite flow:**
1. Owner calls `POST /api/invites` with `{ role }`.
2. Backend generates a 32-byte hex token, 7-day expiry.
3. Owner shares the URL: `https://<host>/accept-invite?token=<hex>`.
4. Invitee opens URL, clicks "Sign in with Google", and is created with the assigned role.

### 5.8 Developer Tools

All endpoints require `is_developer = true`. These provide sandbox management, safety flags, and system notifications.

#### Company safety flags

Two per-company flags control what operations are allowed:

| Flag | Who can set | Purpose |
|------|-------------|---------|
| `allow_developer_tools` | Developers | Enables sandbox operations and developer features |
| `allow_mutation` | Owners | Enables staging execution (writing to Fortnox). Required for sandbox copy/purge |

#### Sandbox companies

A sandbox is a Fortnox test database linked to a production company. It's stored as a regular company record with `linked_production_id` pointing to the production company. All existing company routes work transparently for sandboxes.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/developer/companies` | List companies with dev flags |
| POST | `…/{company_id}/flags` | Set `allow_developer_tools` / `allow_mutation` |
| POST | `…/{company_id}/link-sandbox` | Start sandbox OAuth flow (links test Fortnox DB) |
| DELETE | `…/{company_id}/sandbox` | Unlink sandbox |
| POST | `…/{company_id}/copy-to-sandbox` | Copy production data to sandbox |
| GET | `…/{company_id}/copy-jobs` | List copy jobs for a company |
| GET | `/api/developer/copy-jobs/{job_id}` | Get copy job status + progress |
| POST | `/api/developer/copy-jobs/{job_id}/cancel` | Cancel a running copy job |
| POST | `…/{company_id}/purge-sandbox` | Purge file connections from sandbox Fortnox |

Per-company paths prefixed with `/api/developer/companies`.

**Data copy order** (respects Fortnox referential integrity):

| Step | Doc type | Method |
|------|----------|--------|
| 1 | Financial years | POST `/financialyears` |
| 2 | Accounts | PUT or POST `/accounts/{number}` |
| 3 | Voucher series | PUT or POST `/voucherseries/{code}` |
| 4 | Customers | POST `/customers` |
| 5 | Suppliers | POST `/suppliers` |
| 6 | Vouchers | POST `/vouchers?financialyear=X` |
| 7 | Invoices | POST `/invoices` |
| 8 | Supplier invoices | POST + bookkeep `/supplierinvoices` |

Copy jobs are idempotent (existing records detected and skipped), per-entity error tolerant (4xx on individual records logged and skipped), and cancellable.

**Copy request body:**
```json
{
  "doc_types": ["accounts", "vouchers", "customers"],
  "financial_year_ids": [5, 6]
}
```

**Purge request body:**
```json
{
  "targets": ["voucher_files", "supplier_invoice_files", "invoice_files"]
}
```

#### Notifications

Developers receive in-app notifications for system events.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/developer/notifications` | List notifications (`?unread_only=true`) |
| POST | `…/{notification_id}/read` | Mark as read |
| POST | `…/notifications/read-all` | Mark all as read |
| DELETE | `/api/developer/notifications` | Purge all |

**Current event triggers:**

| Event | Level |
|-------|-------|
| Pending user created (self-signup without invite) | warn |
| Invite accepted | info |

#### System Health

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/developer/syshealth` | Deployment info (env, git SHA, domain, Python version), uptime, CPU, memory, disk |

---

## 6. Key Models

Full schemas are in [`openapi.json`](./openapi.json) under `components.schemas`. Summary of the most important ones:

### Company

```
id                  int
name                string          "Acme AB"
org_number          string          "556988-6905"
connection_id       string (UUID)   ← used as path parameter in most endpoints
token_health        string          "healthy" | "refresh_token_invalid"
token_expires_at    string | null   ISO 8601
scopes              string          Fortnox OAuth scopes
created_at          string          ISO 8601
updated_at          string          ISO 8601
linked_production_id int | null     set on sandbox companies, points to production company ID
```

### CompanyWithBadge

Extends `Company` with a `badge` object for UI display:

```
badge.label         string    "Healthy", "Needs reauth", "Expiring soon"
badge.cls           string    CSS class hint
badge.needs_reauth  bool      true if user must re-authorize via /auth/connect
badge.can_refresh   bool      true if a manual refresh may resolve the issue
```

### Staging action (returned from staging endpoints)

```
id                    int
company_id            int
entity_type           string    "voucher" | "file_connection" | "company_information" | "account" | "voucher_series"
action                string    "create" | "update"
payload               object    the proposed ERP entity body (Fortnox API format)
file_refs             list | null
accounting_reasoning  string | null
notes                 string | null
status                string    "proposed" | "approved" | "rejected" | "executing" | "executed" | "failed"
sequence              int | null
predicted_number      string | null    e.g. "A7"
strict_number         bool
on_hold               bool
financial_year_id     string | null
target_date           string | null    YYYY-MM-DD
proposed_by           int | null       user ID
approved_by           int | null
rejected_by           int | null
proposed_at           string           ISO 8601
reviewed_at           string | null
executed_at           string | null
result_record_id      string | null    ERP ID of created/updated entity
error_message         string | null
```

### Other response models

| Model | Shape |
|-------|-------|
| `SyncTriggerResponse` | `{ "job_ids": [1, 2] }` |
| `SyncCancelResponse` | `{ "job_id": 1, "status": "cancelled" }` |
| `NextNumberResponse` | `{ "predicted_number": "A7", "sequence": 7 }` |
| `InviteResponse` | `{ "id": 1, "token": "hex...", "url": "https://...", "role": "accountant", "expires_at": "..." }` |
| `InvitePreviewResponse` | `{ "role": "accountant", "invited_by_name": "Jane", "expires_at": "..." }` |
| `FileUploadResponse` | `{ "file_id": "uuid", "filename": "receipt.pdf" }` |
| `CompanyFlagsResponse` | `{ "id": 1, "allow_developer_tools": true, "allow_mutation": false }` |
| `PurgeResponse` | `{ "deleted": 42 }` |
| `VoucherSeriesMapResponse` | `{ "series": { "A": "Huvudbok", "B": "Leverantörsfakturor" } }` |
| `HealthResponse` | `{ "ok": true }` |
| `OkResponse` | `{ "ok": "deleted" }` |
| `ErrorResponse` | `{ "error": "message" }` |
| `RefreshTokenResponse` | `{ "ok": true, "error": null, "code": null }` |

---

## 7. Error Handling

### Error response shape

Standard errors:
```json
{ "detail": "Human-readable message" }
```

ERP-related errors may include a structured detail:
```json
{ "detail": { "code": "invalid_grant", "error": "Token has been revoked" } }
```

Pydantic validation errors (422):
```json
{
  "detail": [
    { "loc": ["body", "entity_type"], "msg": "field required", "type": "value_error.missing" }
  ]
}
```

### HTTP status codes

| Code | Meaning |
|------|---------|
| 400 | Bad request — invalid input, unknown doc type, invalid role, etc. |
| 401 | Unauthorized — missing/invalid session cookie, user not in DB |
| 403 | Forbidden — insufficient role, archived account, pending account, developer access required |
| 404 | Not found — company, user, action, invite, or resource does not exist |
| 409 | Conflict — sync already running, invite already used, state mismatch |
| 422 | Validation error — Pydantic/FastAPI request body validation failed |
| 502 | Bad gateway — Fortnox API returned an error |
| 503 | Service unavailable — Fortnox API unreachable |

### ERP token refresh error codes

When the backend fails to refresh a Fortnox token during a proxied request:

| Code | Meaning | Recovery |
|------|---------|----------|
| `invalid_grant` | Refresh token expired or revoked | User must re-authorize via `/auth/connect` |
| `network` | Network error reaching Fortnox | Transient, retry later |
| `server` | Fortnox returned an unexpected error | Transient, retry later |

---

## 8. Rate Limiting

The backend enforces **per-company** rate limits when proxying to the Fortnox API:

- **Interactive requests** (browse, staging): up to **25 requests per 5-second window**
- **Background requests** (sync, copy): capped at **20 per window** (reserves 5 for interactive)

Rate limiting is handled server-side. CLI clients do not need to implement their own throttling — the backend queues and throttles automatically. However, a CLI performing many sequential requests for the same company may experience latency from queuing.

---

## 9. Data Model Concepts

### Companies and connection IDs

Each Fortnox company is identified by two keys:
- `id` (integer) — internal primary key, used in some admin endpoints
- `connection_id` (UUID string) — used as the path parameter in all per-company data endpoints

A sandbox company is a regular company with `linked_production_id` set to the production company's `id`.

### Synced data (`erp_records`)

Locally synced ERP data is stored in the `erp_records` table with:
- `company_id` — which company it belongs to
- `doc_type` — `vouchers`, `invoices`, `supplierinvoices`, `customers`, `suppliers`, `accounts`, `financialyears`, `voucherseries`
- `record_id` — ERP identifier (e.g. `A/7` for voucher series A number 7)
- `financial_year_id` — for period-scoped records
- `data` — full JSON payload from Fortnox
- `is_stub` — `true` if only list-level data was synced, `false` if detail was fetched

Querying local records via `/internal/{doc_type}` supports pagination, filtering, and sorting. The `?include_staged=true` flag on vouchers merges proposed/approved staging actions into the result set with a `_meta.staged` marker.

### Staging actions (`bk_staged_actions`)

Each staged action represents a proposed mutation to the ERP. Actions flow through the lifecycle: `proposed` → `approved` → `executing` → `executed` (or `failed`). Failed actions can put downstream same-company actions `on_hold`.

### Financial years

Fortnox uses integer financial year IDs that differ between companies (and between production and sandbox). The sync endpoint provides `GET .../sync/financial-years` to discover available years.

---

## 10. Deployment & Environment

### Environment variables (backend)

| Variable | Required | Description |
|----------|----------|-------------|
| `SECRET_KEY` | Yes | AES-256-GCM encryption key for stored ERP tokens |
| `JWT_SIGNING_KEY` | No | HS256 session signing key (falls back to `SECRET_KEY`) |
| `FORTNOX_CLIENT_ID` | Yes | Fortnox OAuth client ID |
| `FORTNOX_CLIENT_SECRET` | Yes | Fortnox OAuth client secret |
| `GOOGLE_CLIENT_ID` | No | Google OAuth client ID (omit for dev-bypass mode) |
| `GOOGLE_CLIENT_SECRET` | No | Google OAuth client secret |
| `BASE_URL` | No | Backend URL, default `http://localhost:8000` |
| `FRONTEND_URL` | No | Frontend URL for CORS + redirects, default `http://localhost:5173` |
| `DB_DRIVER` | No | `sqlite` (default) or `postgresql` |
| `DB_PATH` | No | SQLite file path (default: `introspectfn.db`) |
| `DATABASE_URL` | No | PostgreSQL DSN (when `DB_DRIVER=postgresql`) |

### Multi-environment model

One GCP project per customer deployment. Each environment has its own VM, secrets, and Terraform state. A shared Artifact Registry in the staging project holds container images.

| Environment | URL | Notes |
|-------------|-----|-------|
| Local dev | `http://localhost:8000` | SQLite, dev-bypass auth |
| Staging | `https://ifn-stage.mayuda.com` | SQLite on persistent disk |
| Production | `https://<customer-domain>` | Per-customer GCP project |

---

## 11. Platform Context & Roadmap

IntrospectFN is the **ERP domain** in a broader group operating platform. The architecture follows the pattern:

```
Domain → API → CLI module → AI agent
```

Each domain will have its own API, CLI module, and data model. AI agents operate on top of CLI modules and can work within a single domain or across domains.

### Current status (ERP domain)

- **Step 1A** (Direct API browsing) — done
- **Step 1B** (Synchronized local database) — done
- **Step 1C** (ERP CLI module) — **this is what you're building**

### Planned future domains

| Phase | Domain | CLI module |
|-------|--------|------------|
| 2 | Contract registry & legal | `contracts-cli` |
| 3 | POS & operational data | — |
| 4 | Organizational & asset management | `org-cli`, `assets-cli` |
| 5+ | Procurement, workforce, delivery, loyalty | — |

### Planned API changes relevant to CLI

- **API key authentication** — Bearer token auth for CLI/bots (schema exists, routes not wired)
- **PostgreSQL migration** — no API changes, but enables horizontal scaling
- **File storage abstraction** — S3-compatible storage for attachments (MinIO locally, GCS in cloud)
- **Voucher staging extensions** — staging delete, correction rows, account updates, inbox file integration

---

## 12. Regenerating the OpenAPI Spec

```bash
cd backend && .venv/bin/python scripts/export_openapi.py
```

Writes `docs/openapi.json` from the live FastAPI app. Re-run after any endpoint or model changes. The script provides dummy environment variables so it works without a `.env` file.

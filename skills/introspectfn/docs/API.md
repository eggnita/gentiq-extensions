# IntrospectFN — API Reference

> Machine-readable OpenAPI 3.1 spec: [`openapi.json`](./openapi.json)

---

## 1. System Overview

IntrospectFN is a multi-tenant bookkeeping introspection platform that connects to the **Fortnox ERP** system. It lets teams browse, sync, stage, and approve accounting actions against one or more Fortnox companies. The API serves both a web GUI and CLI/AI-agent clients.

| Property | Value |
|----------|-------|
| Base URL (local) | `http://localhost:8000` |
| Base URL (staging) | `https://ifn-stage.mayuda.com` |
| API prefix | `/api` |
| Auth prefix | `/auth` |
| OpenAPI version | 3.1.0 |
| Content-Type | `application/json` (unless noted) |
| Backend | Python / FastAPI |
| Database | SQLite (dev & staging), PostgreSQL planned |

### What the platform does

1. **Connects** to one or more Fortnox companies via OAuth2 and stores encrypted access/refresh tokens.
2. **Syncs** ERP data (vouchers, invoices, suppliers, customers, accounts, etc.) into a local database for fast browsing and analysis.
3. **Stages** bookkeeping mutations through a propose → review → approve → execute workflow.
4. **Manages** multi-user access with role-based permissions, invites, and bot API keys.
5. **Provides** developer tools for sandbox management, data copy, and system health monitoring.

### Architecture

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

---

## 2. Authentication

Two independent auth systems: **user sessions** (Google OAuth, browser) and **API keys** (Bearer tokens, CLI/bots). A third flow — **API provisioning** — bridges the two by letting an owner issue a key for a bot through a browser-based confirmation.

### 2.1 User Sessions (Google OAuth)

Protected endpoints require a `session` cookie containing an HS256 JWT (7-day expiry).

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

**Login flow:**
1. Redirect to `GET /auth/login/google` (optionally `?invite_token=<hex>`)
2. Google consent screen → `GET /auth/login/google/callback`
3. Backend issues JWT cookie → redirects to frontend

**Sign-in gate:**

| Condition | Result |
|-----------|--------|
| 0 existing users | Auto-create as `owner` |
| User already in DB | Normal login |
| New user + valid invite | Create with invite's role |
| New user + no invite | Create with `pending` role (blocked) |

**Dev login (local only):** When `GOOGLE_CLIENT_ID` is not set:
```
GET /auth/dev-login?role=owner|accountant|assistant|viewer|developer
```

### 2.2 API Keys (Bearer Tokens)

CLI and bot clients authenticate with API keys sent as Bearer tokens:

```
Authorization: Bearer ifn_...
X-Bot-Client: my-client/1.0.0
```

Keys are SHA-256 hashed at rest. The raw key is only returned once — at creation time.

**Two ways to create a key:**

1. **Direct creation** (owner calls `POST /api/api-keys`) — simple, no OAuth dance
2. **OAuth provisioning flow** (owner confirms in browser) — automated, key returned via server-to-server callback

### 2.3 API Key Provisioning Flow

An OAuth-style flow for external apps to obtain API keys. The raw key never appears in browser URLs.

```
External App                     Browser (owner)              IntrospectFN
────────────                     ───────────────              ─────────────
     │                                 │                            │
     ├─ 302 /auth/api-provision ──────►│                            │
     │  ?email=bot@app.dev             ├─ GET ─────────────────────►│
     │  &client_id=my-app              │                            │
     │  &redirect_uri=.../callback     │  (login if needed)         │
     │  &state=<csrf>                  │                            │
     │                                 │◄── Confirmation page ──────┤
     │                                 │    "Issue key for          │
     │                                 │     bot@app.dev?"          │
     │                                 ├─ POST confirm ────────────►│
     │                                 │                    Create bot user
     │                                 │                    Generate key + code
     │                                 │◄── 302 redirect_uri ──────┤
     │◄── GET /callback?code=...&state=│    ?code=<auth-code>      │
     │                                 │                            │
     ├─ POST /auth/api-provision/token ────────────────────────────►│
     │  { code, client_id,                              Validate code
     │    client_secret }                               (one-time, 10min)
     │◄── { raw_key, email, name } ─────────────────────────────────┤
     │                                                              │
     │  Store raw_key as Bearer token                               │
```

**Security properties:**
- Auth code is single-use with 10-minute TTL
- Raw key only passes server-to-server (never in browser redirect URLs)
- CSRF protection via `state` parameter
- Provisioner must be logged in as owner

### 2.4 Key Rotation

Keys support two rotation modes:

| Mode | Endpoint | Who | Behavior |
|------|----------|-----|----------|
| Self-rotation | `POST /api/api-keys/self/rotate` | Bot | Grace period: both old and new keys valid until new key is first used for a normal API call |
| Owner rotation | `POST /api/api-keys/{key_id}/rotate` | Owner | Immediate: old key invalidated instantly |

**Rotation signals:** The server may include these response headers on any API call:
- `X-Key-Rotation-Required: true` — the bot should rotate soon
- `X-Key-Hard-Expires: <ISO 8601>` — deadline after which the key stops working

### 2.5 `X-Bot-Client` Header

CLI and bot clients should send this header for audit trail:

```
X-Bot-Client: introspect-cli/0.1.0
```

### 2.6 Logout

```
POST /auth/logout
```

Clears the session cookie. Not relevant for API key auth.

---

## 3. ERP Connection (Fortnox OAuth)

Each connected company has its own Fortnox OAuth tokens, managed independently from user sessions.

### Connection flow

1. `GET /auth/connect` — initiates Fortnox OAuth with CSRF state (10-minute TTL)
2. User authorizes in Fortnox
3. `GET /auth/callback` — exchanges code for access/refresh tokens, encrypts them (AES-256-GCM), stores with company metadata

Re-authorization: `GET /auth/connect?reauth={orgNumber}` updates tokens for an existing company.

### Token health

| State | Meaning | Recovery |
|-------|---------|----------|
| `healthy` | Last refresh succeeded | None needed |
| `refresh_token_invalid` | `invalid_grant` from Fortnox | Re-authorize via `/auth/connect` |

Token refresh happens transparently before each Fortnox API call when the access token is within 5 minutes of expiry.

---

## 4. Role-Based Access Control

### Roles

| Role | Description | Capabilities |
|------|-------------|--------------|
| `owner` | Data ownership | Everything: user/invite/key management, company deletion, all staging operations |
| `accountant` | Accounting lead | Browse, sync, approve/reject staging, execute staged actions |
| `assistant` | Data entry / bot | Browse, propose (stage) actions, edit/reject own actions, clone |
| `viewer` | Read-only | Browse companies, ERP records, dashboard, analysis |
| `pending` | Awaiting approval | Blocked — 403 on all protected endpoints |

### Developer flag

`is_developer` is orthogonal to roles. Any role + developer flag grants access to `/api/developer/*` endpoints.

### Bot roles

| Role | What a bot can do |
|------|-------------------|
| `assistant` | View all data, propose staging actions |
| `accountant` | + Approve and execute staging actions |

Bots never hold `owner` — that role requires human accountability.

### Authorization matrix

| Check | Roles allowed |
|-------|---------------|
| `require_owner` | `owner` |
| `require_accountant_plus` | `owner`, `accountant` |
| `require_stage` | `owner`, `accountant`, `assistant` |
| `require_developer` | any role where `is_developer = true` |

---

## 5. Endpoint Reference

All endpoints return JSON unless otherwise noted. Path parameters in `{braces}`.

### 5.1 Health

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | No | Returns `{"ok": true}` |

### 5.2 Auth & Session

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/auth/connect` | No | Start Fortnox OAuth (`?reauth={orgNumber}`) |
| GET | `/auth/callback` | No | Fortnox OAuth callback |
| GET | `/auth/login/google` | No | Start Google OAuth (`?invite_token=<hex>`) |
| GET | `/auth/login/google/callback` | No | Google OAuth callback |
| POST | `/auth/logout` | No | Clear session cookie |
| GET | `/auth/dev-login` | No | Dev-only quick login (`?role=owner\|...`) |
| GET | `/api/me` | Optional | Current user info or `{user: null}` |

### 5.3 API Key Provisioning

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/auth/api-provision` | Session (owner) | Show confirmation page for issuing a key |
| POST | `/auth/api-provision/confirm` | Session (owner) | Confirm: create user + key, generate auth code, redirect |
| POST | `/auth/api-provision/token` | None (uses code) | Exchange one-time auth code for raw API key |

**Provisioning query params** (`GET /auth/api-provision`):

| Param | Required | Description |
|-------|----------|-------------|
| `email` | Yes | Bot identity email |
| `client_id` | Yes | Requesting application identifier |
| `redirect_uri` | Yes | Where to send the auth code |
| `state` | No | CSRF protection token |
| `name` | No | Display name for the bot user |

**Token exchange request** (`POST /auth/api-provision/token`):

```json
{
  "code": "<one-time-auth-code>",
  "client_id": "my-app",
  "client_secret": "my-secret"
}
```

**Token exchange response:**

```json
{
  "raw_key": "ifn_...",
  "email": "bot@app.dev",
  "name": "My Bot",
  "user_id": 5
}
```

### 5.4 API Key Management

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `/api/api-keys` | Yes | owner | List all API keys |
| POST | `/api/api-keys` | Yes | owner | Create bot user + API key |
| DELETE | `/api/api-keys/{key_id}` | Yes | owner | Delete an API key |
| POST | `/api/api-keys/{key_id}/rotate` | Yes | owner | Owner-initiated rotation (immediate) |
| POST | `/api/api-keys/self/rotate` | Yes (Bearer) | any | Self-service key rotation (grace period) |

**Create key request** (`POST /api/api-keys`):

```json
{
  "email": "bot@company.com",
  "name": "Accounting Bot",
  "label": "Production key",
  "expires_in_days": 90
}
```

**Create key response:** Returns the raw key (only shown once).

**Self-rotate response** (`POST /api/api-keys/self/rotate`):

```json
{
  "raw_key": "ifn_...",
  "rotated_at": "2025-06-15T10:00:00Z"
}
```

Both old and new keys remain valid until the new key is first used for a normal API call — then the old key is burned.

### 5.5 Companies

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `/api/companies` | Yes | any | List all connected companies |
| DELETE | `/api/companies/{company_id}` | Yes | owner | Delete a company and all data |
| POST | `/api/companies/{company_id}/refresh-token` | Yes | owner | Force-refresh ERP OAuth token |

**Company identification:** Most per-company endpoints use `{connection_id}` (UUID), not `{company_id}` (integer).

**Company response fields:**

```
id                    int
name                  string          "Acme AB"
org_number            string          "556988-6905"
connection_id         string (UUID)   ← used as path parameter
token_health          string          "healthy" | "refresh_token_invalid"
token_expires_at      string | null   ISO 8601
scopes                string          Fortnox OAuth scopes
created_at            string          ISO 8601
updated_at            string          ISO 8601
linked_production_id  int | null      set on sandbox companies
badge.label           string          "Healthy", "Needs reauth", "Expiring soon"
badge.cls             string          CSS class hint
badge.needs_reauth    bool
badge.can_refresh     bool
```

### 5.6 External ERP (Proxy)

These proxy requests to the Fortnox API through the backend's rate-limited client. All paths prefixed with `/api/companies`.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `…/{connection_id}/external/{resource}` | Yes | List a resource (paginated) |
| GET | `…/{connection_id}/external/{resource}/{path}` | Yes | Get a single resource record |
| GET | `…/{connection_id}/accounts/{account_number}` | Yes | Get account description |
| GET | `…/{connection_id}/fileconnections` | Yes | File attachments (`?entity&number&series&financialyear`) |
| GET | `…/{connection_id}/archive/{file_id}` | Yes | Download archive file (binary) |
| GET | `…/{connection_id}/fileconnection-counts` | Yes | Batch file-attachment counts |
| GET | `…/{connection_id}/inbox` | Yes | List ERP inbox |
| GET | `…/{connection_id}/inbox/file/{file_id}` | Yes | Download inbox file (binary) |
| GET | `…/{connection_id}/inbox/{folder_id}` | Yes | List inbox folder |

**Query params for resource listing:** `page`, `limit`, `filter`, `sortby`, `sortorder`, `financialyear`, `lastmodified`

**Valid resources:** `customers`, `invoices`, `articles`, `accounts`, `vouchers`, `suppliers`, `orders`, `offers`, `projects`, `costcenters`, `supplierinvoices`, `companyinformation`, `financialyears`, `voucherseries`

### 5.7 Sync (Local Data)

The sync system downloads ERP data into a local database for fast offline access. All per-company paths prefixed with `/api/companies`.

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `…/{connection_id}/sync/financial-years` | Yes | any | List financial years |
| GET | `…/{connection_id}/sync/status` | Yes | any | Current sync job status |
| POST | `…/{connection_id}/sync` | Yes | accountant+ | Trigger a sync job |
| POST | `…/{connection_id}/sync/{job_id}/cancel` | Yes | any | Cancel a running sync |
| DELETE | `…/{connection_id}/internal` | Yes | developer | Purge all locally synced data |
| GET | `…/{connection_id}/dashboard` | Yes | any | Dashboard metrics |
| GET | `…/{connection_id}/internal/account-analysis` | Yes | any | Vouchers grouped by account |
| GET | `…/{connection_id}/internal/accounts/{number}/year-balances` | Yes | any | Account balance across years |
| GET | `…/{connection_id}/internal/integrity` | Yes | any | Data integrity check |
| GET | `…/{connection_id}/internal/voucherseries-map` | Yes | any | Voucher series mapping |
| GET | `…/{connection_id}/internal/files` | Yes | any | List synced file attachments |
| GET | `…/{connection_id}/internal/{doc_type}` | Yes | any | List local records |
| GET | `…/{connection_id}/internal/{doc_type}/{record_id}` | Yes | any | Get a single local record |
| POST | `…/{connection_id}/internal/{doc_type}/{record_id}/refresh` | Yes | accountant+ | Re-fetch a record from ERP |
| GET | `/api/sync/overview` | Yes | any | Global sync status across companies |

**Sync request body** (`POST …/{connection_id}/sync`):

```json
{
  "doc_types": ["vouchers", "invoices", "supplierinvoices", "customers", "suppliers"],
  "financial_year_id": "6",
  "mode": "full",
  "fromdate": "2025-01-01",
  "todate": "2025-12-31"
}
```

`mode`: `full` (re-sync everything), `incremental` (default), or `enrich_only` (fetch detail for stubs only).

**Synced doc types:** `vouchers`, `invoices`, `supplierinvoices`, `customers`, `suppliers`, `accounts`, `financialyears`, `voucherseries`

**Synced file attachments** (`GET …/{connection_id}/internal/files`):

Lists file references from `erp_file_refs` with pagination.

| Param | Default | Description |
|-------|---------|-------------|
| `page` | 1 | Page number |
| `limit` | 100 | Records per page |
| `doc_type` | "" | Filter by document type |
| `search` | "" | Search query |

### 5.8 Staging (Bookkeeping Actions)

The staging system is the core feature for CLI/bot integration. It implements a propose → review → approve → execute workflow. Per-company paths prefixed with `/api/companies`.

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `…/{connection_id}/staging` | Yes | any | List staged actions for a company |
| POST | `…/{connection_id}/staging` | Yes | assistant+ | Propose a staging action |
| GET | `…/{connection_id}/staging/next-number` | Yes | any | Predicted next voucher number |
| POST | `…/{connection_id}/staging/upload-file` | Yes | assistant+ | Upload file (multipart) |
| GET | `…/{connection_id}/write-windows` | Yes | any | List write windows |
| POST | `…/{connection_id}/write-windows` | Yes | owner | Create a write window |
| DELETE | `…/{connection_id}/write-windows/{window_id}` | Yes | any | Delete a write window |
| GET | `/api/staging` | Yes | any | List all staged actions across companies |
| GET | `/api/staging/{action_id}` | Yes | any | Get a staged action |
| PATCH | `/api/staging/{action_id}` | Yes | accountant+ or own | Edit action (payload, notes, reasoning) |
| POST | `/api/staging/{action_id}/approve` | Yes | accountant+ | Approve an action |
| POST | `/api/staging/{action_id}/reject` | Yes | accountant+ or own | Reject an action |
| POST | `/api/staging/{action_id}/clone` | Yes | assistant+ | Clone an existing action |
| POST | `/api/staging/{action_id}/resume` | Yes | accountant+ | Clear `on_hold` flag |
| POST | `/api/staging/execute` | Yes | accountant+ | Execute a batch of approved actions |

**Stage action request:**

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
  "accounting_reasoning": "Monthly office supply purchase...",
  "notes": "June supplies",
  "sequence": 1,
  "predicted_number": "A7",
  "strict_number": false,
  "financial_year_id": "6",
  "target_date": "2025-06-15"
}
```

**Entity types:**

| Entity type | Action | What it does on execute |
|-------------|--------|------------------------|
| `voucher` | `create` | POST to Fortnox `/vouchers` |
| `file_connection` | `create` | POST to Fortnox `/fileattachments` |
| `company_information` | `update` | PUT to Fortnox `/companyinformation` |
| `account` | `create` or `update` | POST or PUT to Fortnox `/accounts/{number}` |
| `voucher_series` | `update` | PUT to Fortnox `/voucherseries/{code}` |

**Staging action fields (response):**

```
id                    int
company_id            int
entity_type           string    "voucher" | "file_connection" | "company_information" | "account" | "voucher_series"
action                string    "create" | "update"
payload               object
file_refs             list | null
accounting_reasoning  string | null
notes                 string | null
status                string    "proposed" | "approved" | "rejected" | "executing" | "executed" | "failed"
sequence              int | null
predicted_number      string | null
strict_number         bool
on_hold               bool
financial_year_id     string | null
target_date           string | null
proposed_by           int | null
approved_by           int | null
rejected_by           int | null
proposed_at           string (ISO 8601)
reviewed_at           string | null
executed_at           string | null
result_record_id      string | null
error_message         string | null
```

**Execution lifecycle:**

```
propose → status: proposed
approve → status: approved
execute (ordered by sequence ASC, id ASC):
  1. allow_mutation check
  2. write-window check (vouchers with target_date)
  3. POST/PUT to Fortnox
  4a. success + strict_number + actual != predicted → DELETE from ERP → mark failed
  4b. success → upsert local record → mark executed
  4c. failure → mark failed → set on_hold on remaining same-company actions
resume → clears on_hold
```

**Execute request body:**

```json
{ "action_ids": [1, 2, 3] }
```

If `action_ids` is omitted, all approved non-held actions are executed.

**Write windows:** Define open date ranges. Voucher actions with `target_date` outside all windows are rejected at execution.

```json
POST /api/companies/{connection_id}/write-windows
{ "from_date": "2025-01-01", "to_date": "2025-12-31", "label": "FY 2025" }
```

### 5.9 Users & Invites

| Method | Path | Auth | Min role | Description |
|--------|------|------|----------|-------------|
| GET | `/api/users` | Yes | owner | List all users |
| PATCH | `/api/users/{user_id}/role` | Yes | owner | Update role |
| PATCH | `/api/users/{user_id}/name` | Yes | owner | Update display name |
| PATCH | `/api/users/{user_id}/developer` | Yes | owner | Toggle `is_developer` flag |
| PATCH | `/api/users/{user_id}/archive` | Yes | owner | Archive / un-archive user |
| GET | `/api/invites` | Yes | owner | List invites |
| POST | `/api/invites` | Yes | owner | Create invite link |
| DELETE | `/api/invites/{invite_id}` | Yes | owner | Revoke an invite |
| GET | `/api/invites/preview` | No | — | Preview invite (`?token=<hex>`) |

### 5.10 Developer Tools

All endpoints require `is_developer = true`. Per-company paths prefixed with `/api/developer/companies`.

**Company flags:**

| Flag | Who can set | Purpose |
|------|-------------|---------|
| `allow_developer_tools` | Developers | Enables sandbox operations |
| `allow_mutation` | Owners | Enables staging execution |

**Sandbox management:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/developer/companies` | List companies with dev flags |
| POST | `…/{company_id}/flags` | Set flags |
| POST | `…/{company_id}/link-sandbox` | Link sandbox Fortnox DB |
| DELETE | `…/{company_id}/sandbox` | Unlink sandbox |
| POST | `…/{company_id}/copy-to-sandbox` | Copy production data to sandbox |
| GET | `…/{company_id}/copy-jobs` | List copy jobs |
| GET | `/api/developer/copy-jobs/{job_id}` | Get copy job status |
| POST | `/api/developer/copy-jobs/{job_id}/cancel` | Cancel a copy job |
| POST | `/api/developer/copy-jobs/{job_id}/resume` | Resume a failed/cancelled copy job |
| POST | `…/{company_id}/purge-sandbox` | Purge file connections from sandbox |
| POST | `…/{company_id}/purge-voucher-series` | Delete vouchers from a sandbox series (highest first) |

**Notifications:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/developer/notifications` | List notifications (`?unread_only=true`) |
| POST | `…/{notification_id}/read` | Mark as read |
| POST | `…/notifications/read-all` | Mark all as read |
| DELETE | `/api/developer/notifications` | Purge all |

**System health:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/developer/syshealth` | Deployment info, uptime, CPU, memory, disk |

---

## 6. Error Handling

### Error response shapes

Standard:
```json
{ "detail": "Human-readable message" }
```

ERP-related:
```json
{ "detail": { "code": "invalid_grant", "error": "Token has been revoked" } }
```

Validation (422):
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
| 400 | Bad request — invalid input, unknown doc type, etc. |
| 401 | Unauthorized — missing/invalid session or API key |
| 403 | Forbidden — insufficient role, archived, pending |
| 404 | Not found |
| 409 | Conflict — sync already running, invite already used |
| 422 | Validation error |
| 502 | Bad gateway — Fortnox API error |
| 503 | Service unavailable — Fortnox unreachable |

---

## 7. Rate Limiting

Per-company rate limits when proxying to Fortnox:

- **Interactive** (browse, staging): 25 requests / 5-second window
- **Background** (sync, copy): 20 / window (reserves 5 for interactive)

Rate limiting is server-side. Clients do not need their own throttling.

---

## 8. Schemas Reference

### Request Schemas

| Schema | Fields |
|--------|--------|
| `StageRequest` | `entity_type` (str), `action` (str, default "create"), `payload` (obj), `file_refs` (list\|null), `accounting_reasoning` (str\|null), `notes` (str\|null), `sequence` (int\|null), `predicted_number` (str\|null), `strict_number` (bool, default false), `financial_year_id` (str\|null), `target_date` (str\|null) |
| `PatchActionRequest` | `payload` (obj\|null), `notes` (str\|null), `accounting_reasoning` (str\|null) |
| `ReviewRequest` | `notes` (str\|null) |
| `ExecuteRequest` | `action_ids` (int[]) |
| `SyncRequest` | `doc_types` (str[]), `financial_year_id` (str), `mode` (str, default "incremental"), `fromdate` (str), `todate` (str) |
| `WriteWindowRequest` | `from_date` (str), `to_date` (str), `label` (str) |
| `CreateKeyRequest` | `email` (str), `name` (str\|null), `label` (str), `expires_in_days` (int\|null) |
| `TokenExchangeRequest` | `code` (str), `client_id` (str), `client_secret` (str) |
| `InviteCreate` | `role` (str) |
| `RoleUpdate` | `role` (str) |
| `CopyRequest` | `doc_types` (str[]), `financial_year_ids` (str[]) |
| `PurgeSandboxRequest` | `targets` (str[]) |
| `PurgeVoucherSeriesRequest` | `series` (str), `financial_year` (str), `down_to` (int, default 1) |
| `LinkSandboxRequest` | `sandbox_company_id` (int) |

### Response Schemas

| Schema | Fields |
|--------|--------|
| `HealthResponse` | `ok` (bool) |
| `OkResponse` | `ok` (str) |
| `RefreshTokenResponse` | `ok` (bool), `error` (str\|null), `code` (enum\|null) |
| `CompanyWithBadge` | `id`, `name`, `org_number`, `connection_id`, `token_health`, `token_expires_at`, `scopes`, `created_at`, `updated_at`, `linked_production_id`, `badge` (TokenBadge) |
| `TokenBadge` | `label` (str), `cls` (str), `needs_reauth` (bool), `can_refresh` (bool) |
| `NextNumberResponse` | `predicted_number` (str), `sequence` (int) |
| `FileUploadResponse` | `file_id` (str), `filename` (str) |
| `FileConnection` | `file_id` (str), `name` (str), `source` (str\|null) |
| `FileConnectionsResponse` | `files` (FileConnection[]) |
| `AccountDescriptionResponse` | `description` (str) |
| `SyncTriggerResponse` | `job_ids` (int[]) |
| `SyncCancelResponse` | `job_id` (int), `status` (str) |
| `VoucherSeriesMapResponse` | `series` (object) |
| `CompanyFlagsResponse` | `id` (int), `allow_developer_tools` (bool), `allow_mutation` (bool) |
| `PurgeResponse` | `deleted` (int) |
| `InviteResponse` | `id`, `token`, `url`, `role`, `expires_at` |
| `InvitePreviewResponse` | `role`, `invited_by_name`, `expires_at` |

---

## 9. Deployment & Environment

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SECRET_KEY` | Yes | AES-256-GCM encryption key for ERP tokens |
| `JWT_SIGNING_KEY` | No | Session signing key (falls back to `SECRET_KEY`) |
| `FORTNOX_CLIENT_ID` | Yes | Fortnox OAuth client ID |
| `FORTNOX_CLIENT_SECRET` | Yes | Fortnox OAuth client secret |
| `GOOGLE_CLIENT_ID` | No | Google OAuth client ID (omit for dev-bypass) |
| `GOOGLE_CLIENT_SECRET` | No | Google OAuth client secret |
| `BASE_URL` | No | Backend URL (default `http://localhost:8000`) |
| `FRONTEND_URL` | No | Frontend URL for CORS + redirects |
| `DB_DRIVER` | No | `sqlite` (default) or `postgresql` |
| `DB_PATH` | No | SQLite file path |
| `DATABASE_URL` | No | PostgreSQL DSN |

### Environments

| Environment | URL | Notes |
|-------------|-----|-------|
| Local dev | `http://localhost:8000` | SQLite, dev-bypass auth |
| Staging | `https://ifn-stage.mayuda.com` | SQLite on persistent disk |
| Production | `https://<customer-domain>` | Per-customer GCP project |

---

## 10. CLI Bot Workflow

A typical AI bot (`assistant` role) interaction pattern:

1. **Authenticate** — use API key (`Authorization: Bearer ifn_...`)
2. **Read data** — browse synced records, run account analysis, check integrity
3. **Propose** — `POST /api/companies/{conn_id}/staging` with full `accounting_reasoning`
4. **Human review** — accountant reviews in web UI and approves/rejects
5. **Execute** — human or trusted `accountant` bot calls `POST /api/staging/execute`
6. **Monitor rotation** — check `X-Key-Rotation-Required` headers, self-rotate when signaled

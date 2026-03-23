# IFN Bot Test

Minimal external app that authenticates against IntrospectFN using the OAuth-style API key provisioning flow.

## Start

```bash
cd ~/Desktop/projects/ifn-bot-test
python3 app.py
```

Open http://localhost:8090

No dependencies — stdlib only.

## Authentication Flow

```
 Test App (localhost:8090)     Browser (provisioner)        IntrospectFN (staging)
 ──────────────────────────    ─────────────────────        ──────────────────────
        │                            │                            │
        │  Click "Connect"           │                            │
        ├─ 302 Redirect ────────────►│                            │
        │  /auth/api-provision       │                            │
        │  ?email=test-bot@ifn.dev   │                            │
        │  &client_id=ifn-bot-test   │                            │
        │  &redirect_uri=            │                            │
        │   localhost:8090/callback  │                            │
        │  &state=<csrf>             │                            │
        │                            ├─ GET ─────────────────────►│
        │                            │                            │
        │                            │  Not logged in?            │
        │                            │  → "Login required" page   │
        │                            │  → Log in via Google       │
        │                            │                            │
        │                            │◄── Confirmation page ──────┤
        │                            │  "Issue key for            │
        │                            │   test-bot@ifn.dev?"       │
        │                            │  [Confirm] [Deny]          │
        │                            │                            │
        │                            ├─ POST confirm ────────────►│
        │                            │                     Create user
        │                            │                     Generate key
        │                            │                     Store SHA-256
        │                            │                     Generate code
        │                            │◄── 302 ───────────────────┤
        │                            │  → localhost:8090/callback │
        │◄── GET /callback ──────────┤    ?code=<auth-code>      │
        │    ?code=...&state=...     │    &state=<csrf>           │
        │                            │                            │
        │  Verify CSRF state         │                            │
        │                            │                            │
        ├─ POST /auth/api-provision/token ───────────────────────►│
        │  { code, client_id,                                     │
        │    client_secret }                              Validate code
        │                                                 (one-time,
        │◄── 200 { raw_key, email, name } ───────────────────────┤
        │                                                  10-min TTL)
        │  Store key in memory       │                            │
        │  Verify via GET /api/me    │                            │
        │                            │                            │
        │  ✓ Connected               │                            │
        │                            │                            │
```

Key points:
- The raw API key never appears in browser URLs — only the auth code is passed via redirect
- The auth code is single-use with a 10-minute TTL
- The key exchange happens server-to-server (test app → IFN backend)
- CSRF protection via the `state` parameter

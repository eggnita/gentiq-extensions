#!/usr/bin/env python3
"""
Minimal external app with web GUI that authenticates against IntrospectFN
using the OAuth-style API key provisioning flow.

Run:  python3 app.py
Open: http://localhost:8090
"""
import http.server
import json
import os
import secrets
import ssl
import urllib.request
import urllib.error
from urllib.parse import parse_qs, urlparse, urlencode

# Allow self-signed certs on staging
_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

IFN_URL = os.environ.get("IFN_BASE_URL", "https://ifn-stage.mayuda.com")
CLIENT_ID = "ifn-bot-test"
CLIENT_SECRET = "test-secret"
CALLBACK_PATH = "/callback"
PORT = 8090
BOT_EMAIL = "test-bot@ifn.dev"
BOT_NAME = "IFN Test Bot"

# In-memory state
_state = {
    "api_key": None,
    "user": None,
    "csrf_token": None,
    "bot_email": BOT_EMAIL,
    "bot_name": BOT_NAME,
}


def _ifn_request(method: str, path: str, body: dict | None = None) -> tuple[int, dict, dict]:
    url = f"{IFN_URL}{path}"
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"}
    if _state["api_key"]:
        headers["Authorization"] = f"Bearer {_state['api_key']}"
        headers["X-Bot-Client"] = CLIENT_ID
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, context=_ssl_ctx)
        return resp.status, dict(resp.headers), json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        try:
            body_resp = json.loads(e.read().decode())
        except Exception:
            body_resp = {"error": str(e)}
        return e.code, dict(e.headers), body_resp


def _html(title: str, body: str) -> bytes:
    return f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{title}</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
           background: #f8f9fa; color: #333; padding: 40px; max-width: 720px; margin: 0 auto; }}
    h1 {{ font-size: 1.5rem; margin-bottom: 8px; }}
    h2 {{ font-size: 1.1rem; color: #666; margin: 24px 0 12px; }}
    .subtitle {{ color: #888; font-size: 0.9rem; margin-bottom: 24px; }}
    .card {{ background: white; border-radius: 12px; padding: 24px; margin-bottom: 16px;
             box-shadow: 0 1px 3px rgba(0,0,0,0.08); }}
    .btn {{ display: inline-block; padding: 10px 20px; border-radius: 8px; border: none;
            font-size: 0.9rem; font-weight: 600; cursor: pointer; text-decoration: none;
            transition: all 0.15s; }}
    .btn-primary {{ background: #2563eb; color: white; }}
    .btn-primary:hover {{ background: #1d4ed8; }}
    .btn-danger {{ background: #ef4444; color: white; }}
    .btn-danger:hover {{ background: #dc2626; }}
    .btn-secondary {{ background: #e5e7eb; color: #374151; }}
    .btn-secondary:hover {{ background: #d1d5db; }}
    .btn-orange {{ background: #f59e0b; color: white; }}
    .btn-orange:hover {{ background: #d97706; }}
    .badge {{ display: inline-block; padding: 3px 10px; border-radius: 999px;
              font-size: 0.75rem; font-weight: 600; }}
    .badge-blue {{ background: #dbeafe; color: #1e40af; }}
    .badge-green {{ background: #dcfce7; color: #166534; }}
    .badge-orange {{ background: #fef3c7; color: #92400e; }}
    .kv {{ display: flex; gap: 8px; padding: 6px 0; border-bottom: 1px solid #f3f4f6; }}
    .kv .k {{ color: #888; min-width: 120px; font-size: 0.85rem; }}
    .kv .v {{ font-size: 0.85rem; }}
    .warn {{ background: #fef3c7; border: 1px solid #fcd34d; border-radius: 8px;
             padding: 12px 16px; margin: 12px 0; font-size: 0.85rem; color: #92400e; }}
    .error {{ background: #fee2e2; border: 1px solid #fca5a5; border-radius: 8px;
              padding: 12px 16px; margin: 12px 0; font-size: 0.85rem; color: #991b1b; }}
    .success {{ background: #dcfce7; border: 1px solid #86efac; border-radius: 8px;
                padding: 12px 16px; margin: 12px 0; font-size: 0.85rem; color: #166534; }}
    .actions {{ display: flex; gap: 8px; margin-top: 16px; flex-wrap: wrap; }}
    pre {{ background: #f3f4f6; padding: 12px; border-radius: 8px; font-size: 0.8rem;
           overflow-x: auto; margin: 8px 0; }}
    .connected {{ border-left: 4px solid #22c55e; }}
    .disconnected {{ border-left: 4px solid #e5e7eb; }}
    code {{ background: #f3f4f6; padding: 2px 6px; border-radius: 4px; font-size: 0.85rem; }}
  </style>
</head>
<body>
  <h1>IFN Bot Test</h1>
  <p class="subtitle">External app &middot; authenticates via IntrospectFN</p>
  {body}
</body>
</html>""".encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _respond(self, code: int, html: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        if path == "/":
            self._page_home()
        elif path == "/connect":
            self._start_provision(params)
        elif path == CALLBACK_PATH:
            self._handle_callback(params)
        elif path == "/disconnect":
            _state["api_key"] = None
            _state["user"] = None
            self.send_response(302)
            self.send_header("Location", "/")
            self.end_headers()
        elif path == "/test/whoami":
            self._page_whoami()
        elif path == "/test/companies":
            self._page_companies()
        elif path == "/test/rotate":
            self._page_rotate()
        else:
            self._respond(404, _html("Not Found", "<p>Page not found.</p>"))

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/test/rotate":
            self._do_rotate()
        elif parsed.path == "/settings":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode()
            params = parse_qs(body)
            _state["bot_email"] = params.get("email", [_state["bot_email"]])[0].strip()
            _state["bot_name"] = params.get("name", [_state["bot_name"]])[0].strip()
            self.send_response(302)
            self.send_header("Location", "/")
            self.end_headers()
        else:
            self._respond(404, _html("Not Found", "<p>Not found.</p>"))

    # ── Provisioning flow ────────────────────────────────────────────────────

    def _start_provision(self, query_params: dict):
        """Step 1: Redirect the user to IFN's provisioning page."""
        # Allow overriding email/name via query params from the connect form
        email = query_params.get("email", [_state["bot_email"]])[0]
        name = query_params.get("name", [_state["bot_name"]])[0]

        csrf = secrets.token_urlsafe(16)
        _state["csrf_token"] = csrf

        params = urlencode({
            "email": email,
            "name": name,
            "client_id": CLIENT_ID,
            "redirect_uri": f"http://localhost:{PORT}{CALLBACK_PATH}",
            "state": csrf,
        })
        location = f"{IFN_URL}/auth/api-provision?{params}"
        self.send_response(302)
        self.send_header("Location", location)
        self.end_headers()

    def _handle_callback(self, params: dict):
        """Step 2: Receive the auth code and exchange it for an API key."""
        code = params.get("code", [""])[0]
        state = params.get("state", [""])[0]

        # Verify CSRF
        if state != _state.get("csrf_token"):
            self._respond(400, _html("Error", '<div class="error">CSRF state mismatch. Try connecting again.</div><a href="/" class="btn btn-secondary">Home</a>'))
            return

        if not code:
            self._respond(400, _html("Error", '<div class="error">No authorization code received.</div><a href="/" class="btn btn-secondary">Home</a>'))
            return

        # Exchange code for API key (server-to-server)
        status, _, resp = _ifn_request("POST", "/auth/api-provision/token", {
            "code": code,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
        })

        if status == 200 and resp.get("raw_key"):
            _state["api_key"] = resp["raw_key"]
            _state["user"] = {
                "email": resp.get("email", ""),
                "name": resp.get("name", ""),
                "user_id": resp.get("user_id"),
            }
            # Verify by calling /api/me
            me_status, _, me_resp = _ifn_request("GET", "/api/me")
            if me_status == 200 and me_resp.get("user"):
                _state["user"] = me_resp["user"]

            self._respond(200, _html("Connected!", f"""
                <div class="card connected">
                  <div class="success">Successfully authenticated with IntrospectFN!</div>
                  <div style="margin-top:12px">
                    <div class="kv"><span class="k">Email</span><span class="v">{resp.get('email','')}</span></div>
                    <div class="kv"><span class="k">Name</span><span class="v">{resp.get('name','')}</span></div>
                    <div class="kv"><span class="k">API Key</span><span class="v"><code>{resp['raw_key'][:12]}...{resp['raw_key'][-6:]}</code></span></div>
                  </div>
                  <div class="actions">
                    <a href="/" class="btn btn-primary">Continue to Dashboard</a>
                  </div>
                </div>
            """))
        else:
            detail = resp.get("detail", "Unknown error")
            self._respond(400, _html("Auth Failed", f"""
                <div class="error">Token exchange failed: {detail}</div>
                <a href="/" class="btn btn-secondary">Home</a>
            """))

    # ── Pages ────────────────────────────────────────────────────────────────

    def _page_home(self):
        if _state["api_key"] and _state["user"]:
            u = _state["user"]
            key = _state["api_key"]
            self._respond(200, _html("Connected", f"""
                <div class="card connected">
                  <div style="display:flex;justify-content:space-between;align-items:center">
                    <div>
                      <span class="badge badge-green">Connected</span>
                      <span style="margin-left:8px;font-size:0.85rem;color:#888">{IFN_URL}</span>
                    </div>
                    <a href="/disconnect" class="btn btn-danger" style="font-size:0.8rem;padding:6px 14px">Disconnect</a>
                  </div>
                  <div style="margin-top:16px">
                    <div class="kv"><span class="k">Identity</span><span class="v"><strong>{u.get('name','')}</strong> ({u.get('email','')})</span></div>
                    <div class="kv"><span class="k">Role</span><span class="v"><span class="badge badge-blue">{u.get('role','assistant')}</span></span></div>
                    <div class="kv"><span class="k">API Key</span><span class="v"><code>{key[:12]}...{key[-6:]}</code></span></div>
                  </div>
                </div>

                <h2>Test Endpoints</h2>
                <div class="actions">
                  <a href="/test/whoami" class="btn btn-primary">Who am I?</a>
                  <a href="/test/companies" class="btn btn-secondary">List Companies</a>
                  <a href="/test/rotate" class="btn btn-orange">Rotate Key</a>
                </div>
            """))
        else:
            em = _state["bot_email"]
            nm = _state["bot_name"]
            self._respond(200, _html("Not Connected", f"""
                <div class="card disconnected">
                  <p style="color:#888;margin-bottom:16px">Not connected to IntrospectFN</p>

                  <form action="/connect" method="GET" style="margin-bottom:16px">
                    <div style="display:flex;gap:8px;margin-bottom:12px">
                      <div style="flex:1">
                        <label style="font-size:0.8rem;color:#666;display:block;margin-bottom:4px">Email</label>
                        <input type="text" name="email" value="{em}"
                               style="width:100%;padding:8px 10px;border:1px solid #d1d5db;border-radius:8px;font-size:0.85rem">
                      </div>
                      <div style="flex:1">
                        <label style="font-size:0.8rem;color:#666;display:block;margin-bottom:4px">Name</label>
                        <input type="text" name="name" value="{nm}"
                               style="width:100%;padding:8px 10px;border:1px solid #d1d5db;border-radius:8px;font-size:0.85rem">
                      </div>
                    </div>
                    <button type="submit" class="btn btn-primary" style="width:100%">Connect to IntrospectFN</button>
                  </form>
                </div>
                <p style="margin-top:16px;font-size:0.85rem;color:#888">
                  Target: {IFN_URL}<br>
                  You will be redirected to IntrospectFN to authorize this app.
                </p>
            """))

    def _page_whoami(self):
        status, headers, resp = _ifn_request("GET", "/api/me")
        rotation_warn = ""
        if headers.get("X-Key-Rotation-Required") == "true":
            hard = headers.get("X-Key-Hard-Expires", "unknown")
            rotation_warn = f'<div class="warn">Key rotation required. Hard expires: {hard}</div>'

        if status == 200 and resp.get("user"):
            u = resp["user"]
            _state["user"] = u
            self._respond(200, _html("Who Am I", f"""
                <div class="card">
                  <h2 style="margin-top:0">GET /api/me</h2>
                  <span class="badge badge-green">{status}</span>
                  {rotation_warn}
                  <div style="margin-top:12px">
                    <div class="kv"><span class="k">Name</span><span class="v">{u.get('name','')}</span></div>
                    <div class="kv"><span class="k">Email</span><span class="v">{u.get('email','')}</span></div>
                    <div class="kv"><span class="k">Role</span><span class="v">{u.get('role','')}</span></div>
                    <div class="kv"><span class="k">Developer</span><span class="v">{u.get('is_developer', False)}</span></div>
                  </div>
                </div>
                <a href="/" class="btn btn-secondary" style="margin-top:12px">Home</a>
            """))
        else:
            self._respond(200, _html("Who Am I", f"""
                <div class="card">
                  <h2 style="margin-top:0">GET /api/me</h2>
                  <span class="badge badge-orange">{status}</span>
                  <pre>{json.dumps(resp, indent=2)}</pre>
                </div>
                <a href="/" class="btn btn-secondary" style="margin-top:12px">Home</a>
            """))

    def _page_companies(self):
        status, headers, resp = _ifn_request("GET", "/api/companies")
        rotation_warn = ""
        if headers.get("X-Key-Rotation-Required") == "true":
            hard = headers.get("X-Key-Hard-Expires", "unknown")
            rotation_warn = f'<div class="warn">Key rotation required. Hard expires: {hard}</div>'

        if status == 200:
            companies = resp if isinstance(resp, list) else resp.get("companies", [resp])
            rows = ""
            for c in companies if isinstance(companies, list) else []:
                name = c.get("name", "?")
                org = c.get("org_number", "")
                conn = c.get("connection_id", "")[:12]
                rows += f'<div class="kv"><span class="k">{name}</span><span class="v">{org} &middot; {conn}...</span></div>'
            if not rows:
                rows = "<p style='color:#888;font-size:0.85rem'>No companies or unexpected format</p>"
                rows += f"<pre>{json.dumps(resp, indent=2)[:500]}</pre>"
            self._respond(200, _html("Companies", f"""
                <div class="card">
                  <h2 style="margin-top:0">GET /api/companies</h2>
                  <span class="badge badge-green">{status}</span>
                  {rotation_warn}
                  <div style="margin-top:12px">{rows}</div>
                </div>
                <a href="/" class="btn btn-secondary" style="margin-top:12px">Home</a>
            """))
        else:
            self._respond(200, _html("Companies", f"""
                <div class="card">
                  <h2 style="margin-top:0">GET /api/companies</h2>
                  <span class="badge badge-orange">{status}</span>
                  <pre>{json.dumps(resp, indent=2)}</pre>
                </div>
                <a href="/" class="btn btn-secondary" style="margin-top:12px">Home</a>
            """))

    def _page_rotate(self):
        self._respond(200, _html("Rotate Key", """
            <div class="card">
              <h2 style="margin-top:0">Self-Service Key Rotation</h2>
              <p style="font-size:0.85rem;color:#666;margin-bottom:16px">
                This will generate a new API key. Both keys remain valid until
                the new key is first used, at which point the old key is burned.
              </p>
              <form method="POST" action="/test/rotate">
                <div class="actions">
                  <button type="submit" class="btn btn-orange">Rotate Now</button>
                  <a href="/" class="btn btn-secondary">Cancel</a>
                </div>
              </form>
            </div>
        """))

    def _do_rotate(self):
        status, headers, resp = _ifn_request("POST", "/api/api-keys/self/rotate")
        if status == 200:
            new_key = resp.get("raw_key", "")
            _state["api_key"] = new_key
            self._respond(200, _html("Key Rotated", f"""
                <div class="card connected">
                  <div class="success">Key rotated successfully!</div>
                  <div class="kv"><span class="k">New key</span><span class="v"><code>{new_key[:12]}...{new_key[-6:]}</code></span></div>
                  <div class="kv"><span class="k">Rotated at</span><span class="v">{resp.get('rotated_at', '')}</span></div>
                  <div class="actions">
                    <a href="/" class="btn btn-secondary">Home</a>
                    <a href="/test/whoami" class="btn btn-primary">Verify identity</a>
                  </div>
                </div>
            """))
        else:
            self._respond(200, _html("Rotation Failed", f"""
                <div class="error">Rotation failed: {json.dumps(resp, indent=2)}</div>
                <a href="/" class="btn btn-secondary">Home</a>
            """))


if __name__ == "__main__":
    print(f"IFN Bot Test App")
    print(f"Target:   {IFN_URL}")
    print(f"Client:   {CLIENT_ID}")
    print(f"Open:     http://localhost:{PORT}")
    server = http.server.HTTPServer(("", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")

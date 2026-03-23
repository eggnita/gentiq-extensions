#!/usr/bin/env python3
"""
Simple bot client to test IntrospectFN API key authentication.

Usage:
  1. Create an API key on staging:
     - Log in to https://ifn-stage.mayuda.com as owner
     - Go to admin → create a bot key (or use curl below)

  2. Save the raw key:
     export IFN_API_KEY="ifn_..."

  3. Run this bot:
     python3 bot.py

  Or use the interactive menu to test different endpoints.
"""
import os
import sys
import json
import urllib.request
import urllib.error

BASE_URL = os.environ.get("IFN_BASE_URL", "https://ifn-stage.mayuda.com")
API_KEY = os.environ.get("IFN_API_KEY", "")


def _req(method: str, path: str, body: dict | None = None) -> tuple[int, dict, dict]:
    """Make an API request. Returns (status, headers_dict, body_dict)."""
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"}
    if API_KEY:
        headers["Authorization"] = f"Bearer {API_KEY}"
        headers["X-Bot-Client"] = "ifn-bot-test"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        resp_headers = dict(resp.headers)
        resp_body = json.loads(resp.read().decode())
        return resp.status, resp_headers, resp_body
    except urllib.error.HTTPError as e:
        resp_body = {}
        try:
            resp_body = json.loads(e.read().decode())
        except Exception:
            pass
        return e.code, dict(e.headers), resp_body


def check_rotation_headers(headers: dict):
    """Check and report key rotation signals."""
    if headers.get("X-Key-Rotation-Required") == "true":
        hard = headers.get("X-Key-Hard-Expires", "unknown")
        print(f"\n  ⚠ Key rotation required! Hard expires: {hard}")


def cmd_whoami():
    """Test /api/me — verify authentication."""
    print(f"\n→ GET {BASE_URL}/api/me")
    status, headers, body = _req("GET", "/api/me")
    print(f"  Status: {status}")
    if status == 200 and body.get("user"):
        u = body["user"]
        print(f"  User: {u.get('name')} ({u.get('email')})")
        print(f"  Role: {u.get('role')}")
        print(f"  Bot: {u.get('is_bot', False)}")
        print(f"  Developer: {u.get('is_developer', False)}")
    else:
        print(f"  Response: {json.dumps(body, indent=2)}")
    check_rotation_headers(headers)


def cmd_companies():
    """List companies."""
    print(f"\n→ GET {BASE_URL}/api/companies")
    status, headers, body = _req("GET", "/api/companies")
    print(f"  Status: {status}")
    if status == 200:
        companies = body if isinstance(body, list) else body.get("companies", body)
        if isinstance(companies, list):
            for c in companies:
                print(f"  - {c.get('name', '?')} ({c.get('connection_id', '?')})")
        else:
            print(f"  Response: {json.dumps(body, indent=2)[:500]}")
    else:
        print(f"  Error: {json.dumps(body, indent=2)}")
    check_rotation_headers(headers)


def cmd_rotate():
    """Self-rotate the API key."""
    print(f"\n→ POST {BASE_URL}/api/api-keys/self/rotate")
    status, headers, body = _req("POST", "/api/api-keys/self/rotate")
    print(f"  Status: {status}")
    if status == 200:
        new_key = body.get("raw_key", "")
        print(f"  New key: {new_key[:20]}...")
        print(f"  Rotated at: {body.get('rotated_at')}")
        print(f"\n  To use the new key:")
        print(f"  export IFN_API_KEY=\"{new_key}\"")
    else:
        print(f"  Error: {json.dumps(body, indent=2)}")


def cmd_health():
    """Check /health (no auth needed)."""
    print(f"\n→ GET {BASE_URL}/health")
    status, _, body = _req("GET", "/health")
    print(f"  Status: {status}")
    print(f"  Response: {body}")


def main():
    print("IntrospectFN Bot Test Client")
    print(f"Base URL: {BASE_URL}")
    print(f"API Key:  {'set (' + API_KEY[:12] + '...)' if API_KEY else 'NOT SET'}")

    if not API_KEY:
        print("\n⚠ No API key set. Set IFN_API_KEY environment variable.")
        print("  You can still test /health (no auth required).\n")

    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        cmds = {"whoami": cmd_whoami, "companies": cmd_companies,
                "rotate": cmd_rotate, "health": cmd_health}
        if cmd in cmds:
            cmds[cmd]()
            return
        print(f"Unknown command: {cmd}")

    print("\nCommands:")
    print("  1) whoami     — GET /api/me")
    print("  2) companies  — GET /api/companies")
    print("  3) rotate     — POST /api/api-keys/self/rotate")
    print("  4) health     — GET /health")
    print("  q) quit")

    while True:
        try:
            choice = input("\n> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if choice in ("1", "whoami"):
            cmd_whoami()
        elif choice in ("2", "companies"):
            cmd_companies()
        elif choice in ("3", "rotate"):
            cmd_rotate()
        elif choice in ("4", "health"):
            cmd_health()
        elif choice in ("q", "quit", "exit"):
            break
        else:
            print("  Unknown command. Try 1-4 or q.")


if __name__ == "__main__":
    main()

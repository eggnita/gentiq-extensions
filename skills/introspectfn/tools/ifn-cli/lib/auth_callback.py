#!/usr/bin/env python3
"""Minimal OAuth callback server for ifn auth login.

Usage: auth_callback.py <csrf_token> <port_file> <code_file>

Starts a one-shot HTTP server on 127.0.0.1 with an OS-assigned port.
Writes the port to port_file, waits for the OAuth callback, validates
the CSRF state, writes the auth code to code_file, and exits.
"""

import http.server
import sys
import os
import threading
import urllib.parse

CSRF_TOKEN = sys.argv[1]
PORT_FILE = sys.argv[2]
CODE_FILE = sys.argv[3]
TIMEOUT = 120

SUCCESS_HTML = """<!DOCTYPE html>
<html>
<head><title>IntrospectFN CLI</title>
<style>
body { font-family: -apple-system, system-ui, sans-serif; display: flex;
       justify-content: center; align-items: center; height: 100vh; margin: 0;
       background: #f8f9fa; }
.card { background: white; border-radius: 12px; padding: 40px; text-align: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1); max-width: 400px; }
.icon { font-size: 48px; margin-bottom: 16px; color: #22c55e; }
h1 { font-size: 1.2rem; color: #166534; margin: 0 0 8px; }
p { color: #666; font-size: 0.9rem; margin: 0; }
</style></head>
<body><div class="card">
<div class="icon">&#10003;</div>
<h1>Authorization successful</h1>
<p>You can close this tab and return to the terminal.</p>
</div></body></html>"""

ERROR_HTML = """<!DOCTYPE html>
<html>
<head><title>IntrospectFN CLI</title>
<style>
body { font-family: -apple-system, system-ui, sans-serif; display: flex;
       justify-content: center; align-items: center; height: 100vh; margin: 0;
       background: #f8f9fa; }
.card { background: white; border-radius: 12px; padding: 40px; text-align: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1); max-width: 400px; }
h1 { font-size: 1.2rem; color: #991b1b; margin: 0 0 8px; }
p { color: #666; font-size: 0.9rem; margin: 0; }
</style></head>
<body><div class="card">
<h1>Authorization failed</h1>
<p>%s</p>
</div></body></html>"""


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/callback":
            self.send_error(404)
            return

        params = urllib.parse.parse_qs(parsed.query)
        code = params.get("code", [None])[0]
        state = params.get("state", [None])[0]

        if not code:
            self._respond(400, ERROR_HTML % "No authorization code received.")
            return

        if state != CSRF_TOKEN:
            self._respond(400, ERROR_HTML % "Security token mismatch. Please retry.")
            return

        with open(CODE_FILE, "w") as f:
            f.write(code)

        self._respond(200, SUCCESS_HTML)
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def _respond(self, status, html):
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode())

    def log_message(self, fmt, *args):
        pass


def main():
    server = http.server.HTTPServer(("127.0.0.1", 0), CallbackHandler)
    port = server.server_address[1]

    with open(PORT_FILE, "w") as f:
        f.write(str(port))

    # Auto-shutdown after timeout
    timer = threading.Timer(TIMEOUT, lambda: server.shutdown())
    timer.daemon = True
    timer.start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        timer.cancel()
        server.server_close()


if __name__ == "__main__":
    main()

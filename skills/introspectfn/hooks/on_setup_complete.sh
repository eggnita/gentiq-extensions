#!/usr/bin/env bash
# on_setup_complete.sh — Verify credential after setup completes
# Lifecycle: on_setup_complete
# Output: {"ok": bool, "user": {email, role}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/ifn-cli/config.sh"
source "${SKILL_ROOT}/tools/ifn-cli/lib/http.sh"

ifn_load_config

if [ -z "$IFN_API_KEY" ]; then
    jq -n '{ok: false, error: "No API key provided"}'
    exit 0
fi

# Verify by calling /api/me
me_resp=$(ifn_get "/api/me" 2>/dev/null) || {
    jq -n '{ok: false, error: "Failed to verify API key"}'
    exit 0
}

if echo "$me_resp" | jq -e '.user' >/dev/null 2>&1; then
    echo "$me_resp" | jq '{ok: true, user: {email: .user.email, role: .user.role}}'
else
    jq -n '{ok: false, error: "API key verification returned unexpected response"}'
fi

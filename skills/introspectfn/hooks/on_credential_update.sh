#!/usr/bin/env bash
# on_credential_update.sh — Re-verify credential after update
# Lifecycle: on_credential_update
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

# Verify the updated key via /api/me
me_resp=$(ifn_get "/api/me" 2>/dev/null) || {
    jq -n '{ok: false, error: "Failed to verify updated API key"}'
    exit 0
}

if echo "$me_resp" | jq -e '.user' >/dev/null 2>&1; then
    echo "$me_resp" | jq '{ok: true, user: {email: .user.email, role: .user.role}}'
else
    jq -n '{ok: false, error: "Updated API key verification failed"}'
fi

#!/usr/bin/env bash
# health_check.sh — Check API connectivity and key validity
# Cron: every 6 hours
# Output: {"ok": bool, "api": bool, "auth": bool, "message": str}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/ifn-cli/config.sh"
source "${SKILL_ROOT}/tools/ifn-cli/lib/http.sh"

ifn_load_config

api_ok=false
auth_ok=false
message=""

# Check API health endpoint (no auth required)
if health_resp=$(ifn_get "/health" 2>/dev/null); then
    api_ok=true
else
    message="API unreachable at ${IFN_BASE_URL}"
fi

# Check auth by calling /api/me
if [ "$api_ok" = true ] && [ -n "$IFN_API_KEY" ]; then
    if me_resp=$(ifn_get "/api/me" 2>/dev/null); then
        if echo "$me_resp" | jq -e '.user' >/dev/null 2>&1; then
            auth_ok=true
        else
            message="API key not recognized"
        fi
    else
        message="Authentication failed (HTTP ${IFN_HTTP_STATUS:-unknown})"
    fi
elif [ -z "$IFN_API_KEY" ]; then
    message="No API key configured"
fi

if [ "$api_ok" = true ] && [ "$auth_ok" = true ]; then
    ok=true
    [ -z "$message" ] && message="Healthy"
else
    ok=false
fi

jq -n \
    --argjson ok "$ok" \
    --argjson api "$api_ok" \
    --argjson auth "$auth_ok" \
    --arg message "$message" \
    '{ok: $ok, api: $api, auth: $auth, message: $message}'

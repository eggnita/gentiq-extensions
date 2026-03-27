#!/usr/bin/env bash
# status.sh — Dashboard status widget
# Trigger: status hook (refresh_interval: 3600)
# Output: {"connected": bool, "companies": int, "key_ok": bool, ...}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/ifn-cli/config.sh"
source "${SKILL_ROOT}/tools/ifn-cli/lib/http.sh"

ifn_load_config

connected=false
companies=0
key_ok=false
rotation_needed=false
message=""

if [ -z "$IFN_API_KEY" ]; then
    jq -n '{connected: false, companies: 0, key_ok: false, rotation_needed: false, message: "No API key configured"}'
    exit 0
fi

# Check connectivity and auth via /api/me with header inspection
header_file=$(mktemp)
curl_args=(-s -S -w '\n%{http_code}' -D "$header_file")
if [ "$IFN_INSECURE" = "true" ]; then
    curl_args+=(-k)
fi
me_response=$(curl "${curl_args[@]}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${IFN_API_KEY}" \
    -H "X-Bot-Client: ${IFN_USER_AGENT}" \
    "${IFN_BASE_URL}/api/me" 2>&1) || true

status_code=$(echo "$me_response" | tail -n1)
me_body=$(echo "$me_response" | sed '$d')

if [[ "$status_code" =~ ^2[0-9][0-9]$ ]]; then
    connected=true
    key_ok=true
    if echo "$me_body" | jq -e '.user' >/dev/null 2>&1; then
        message="Authenticated"
    fi
fi

# Check rotation header
rot_header=$(grep -i '^X-Key-Rotation-Required:' "$header_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r' || true)
if [ "$rot_header" = "true" ]; then
    rotation_needed=true
fi
rm -f "$header_file"

# Count companies
if [ "$connected" = true ]; then
    companies_resp=$(ifn_get "/api/companies" 2>/dev/null) || true
    if [ -n "$companies_resp" ]; then
        count=$(echo "$companies_resp" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
        companies=$count
    fi
fi

jq -n \
    --argjson connected "$connected" \
    --argjson companies "$companies" \
    --argjson key_ok "$key_ok" \
    --argjson rotation_needed "$rotation_needed" \
    --arg message "$message" \
    --arg base_url "$IFN_BASE_URL" \
    '{connected: $connected, companies: $companies, key_ok: $key_ok, rotation_needed: $rotation_needed, message: $message, base_url: $base_url}'

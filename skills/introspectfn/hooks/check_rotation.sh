#!/usr/bin/env bash
# check_rotation.sh — Check if API key rotation is needed
# Cron: daily at 08:00
# Output: {"rotation_needed": bool, "hard_expires": str|null}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/ifn-cli/config.sh"
source "${SKILL_ROOT}/tools/ifn-cli/lib/http.sh"

ifn_load_config

rotation_needed=false
hard_expires="null"

if [ -z "$IFN_API_KEY" ]; then
    jq -n '{rotation_needed: false, hard_expires: null, error: "No API key configured"}'
    exit 0
fi

# Call /api/me and capture response headers via the header inspection in http.sh
# We need to inspect headers directly for rotation signals
header_file=$(mktemp)
response=$(curl -s -S \
    -w '\n%{http_code}' \
    -D "$header_file" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${IFN_API_KEY}" \
    -H "X-Bot-Client: ${IFN_USER_AGENT}" \
    "${IFN_BASE_URL}/api/me" 2>&1) || true

# Check rotation header
rot_header=$(grep -i '^X-Key-Rotation-Required:' "$header_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r' || true)
if [ "$rot_header" = "true" ]; then
    rotation_needed=true
    exp=$(grep -i '^X-Key-Hard-Expires:' "$header_file" 2>/dev/null | head -1 | sed 's/^[^:]*: *//' | tr -d '\r' || true)
    if [ -n "$exp" ]; then
        hard_expires="\"${exp}\""
    fi
fi

rm -f "$header_file"

jq -n \
    --argjson rotation_needed "$rotation_needed" \
    --argjson hard_expires "$hard_expires" \
    '{rotation_needed: $rotation_needed, hard_expires: $hard_expires}'

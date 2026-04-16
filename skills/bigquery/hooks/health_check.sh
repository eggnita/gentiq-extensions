#!/usr/bin/env bash
# health_check.sh — Check BigQuery connectivity and credential validity
# Cron: every 6 hours
# Output: {"ok": bool, "bq": bool, "auth": bool, "message": str}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/bq-cli/config.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/format.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/auth.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/http.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/cache.sh"

bq_load_config 2>/dev/null || true

bq_ok=false
auth_ok=false
message=""

# Check credentials file exists
if [ ! -f "$BQ_CREDENTIALS_FILE" ]; then
    message="No service account credentials found"
    jq -n \
        --argjson ok false \
        --argjson bq false \
        --argjson auth false \
        --arg message "$message" \
        '{ok: $ok, bq: $bq, auth: $auth, message: $message}'
    exit 0
fi

# Check SA JSON is valid
sa_email=$(jq -r '.client_email // empty' "$BQ_CREDENTIALS_FILE" 2>/dev/null)
if [ -z "$sa_email" ]; then
    message="Invalid credentials file — no client_email"
    jq -n \
        --argjson ok false \
        --argjson bq false \
        --argjson auth false \
        --arg message "$message" \
        '{ok: $ok, bq: $bq, auth: $auth, message: $message}'
    exit 0
fi

auth_ok=true

# Check BQ connectivity via REST API
if bq_verify_connection; then
    bq_ok=true
    message="Healthy"
    # Refresh metadata cache if stale
    bq_cache_load
    if bq_cache_is_stale; then
        bq_cache_refresh >/dev/null 2>&1 || true
    fi
else
    message="BigQuery unreachable or authentication failed"
fi

if [ "$bq_ok" = true ] && [ "$auth_ok" = true ]; then
    ok=true
else
    ok=false
fi

jq -n \
    --argjson ok "$ok" \
    --argjson bq "$bq_ok" \
    --argjson auth "$auth_ok" \
    --arg message "$message" \
    --arg sa_email "$sa_email" \
    '{ok: $ok, bq: $bq, auth: $auth, message: $message, sa_email: $sa_email}'

#!/usr/bin/env bash
# check_freshness.sh — Check ERP sync freshness, alert if stale
# Cron: weekdays at 09:00
# Output: {"ok": bool, "companies": [{name, last_sync, stale}]}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/ifn-cli/config.sh"
source "${SKILL_ROOT}/tools/ifn-cli/lib/http.sh"

ifn_load_config

if [ -z "$IFN_API_KEY" ]; then
    jq -n '{ok: false, companies: [], error: "No API key configured"}'
    exit 0
fi

# Fetch companies
companies_resp=$(ifn_get "/api/companies" 2>/dev/null) || {
    jq -n '{ok: false, companies: [], error: "Failed to fetch companies"}'
    exit 0
}

# Check if we got a valid response
if ! echo "$companies_resp" | jq -e '.' >/dev/null 2>&1; then
    jq -n '{ok: false, companies: [], error: "Invalid response from API"}'
    exit 0
fi

# Stale threshold: 24 hours ago (in seconds since epoch)
stale_threshold=$(($(date +%s) - 86400))
all_ok=true

# Process each company — check dashboard freshness
result=$(echo "$companies_resp" | jq --argjson threshold "$stale_threshold" '
    (if type == "array" then . else [.] end) |
    map({
        name: (.name // .company_name // "unknown"),
        connection_id: (.connection_id // ""),
        last_sync: (.last_sync // .updated_at // null),
        stale: (
            if (.last_sync // .updated_at // null) then
                ((.last_sync // .updated_at) | sub("\\.[0-9]+"; "") | sub("Z$"; "+00:00") |
                 fromdateiso8601) < $threshold
            else true
            end
        )
    })
' 2>/dev/null) || result="[]"

# Check if any company is stale
has_stale=$(echo "$result" | jq 'any(.stale == true)' 2>/dev/null || echo "false")
if [ "$has_stale" = "true" ]; then
    all_ok=false
fi

jq -n \
    --argjson ok "$all_ok" \
    --argjson companies "$result" \
    '{ok: $ok, companies: $companies}'

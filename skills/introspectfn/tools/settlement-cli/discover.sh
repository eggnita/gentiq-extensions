#!/usr/bin/env bash
# settlement discover-accounts — Discover account mapping from Fortnox chart of accounts
#
# Usage: settlement discover-accounts <company_id> --partner <partner>
#
# Scans the company's accounts for partner-related accounts and proposes a mapping.
# If a mapping file already exists, merges — doesn't overwrite confirmed companies.

settlement_discover() {
    local company_id="" partner=""

    if [ $# -lt 1 ]; then
        echo '{"error": "Usage: settlement discover-accounts <company_id> --partner <partner>"}' >&2
        return 1
    fi
    company_id="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --partner) partner="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done

    if [ -z "$partner" ]; then
        echo '{"error": "--partner is required (foodora, wolt, or ubereats)"}' >&2
        return 1
    fi

    # Fetch accounts from IFN
    local accounts_response
    accounts_response=$(ifn_get "/api/companies/${company_id}/internal/accounts?page=1&limit=500&active=true") || {
        echo '{"error": "Failed to fetch accounts"}' >&2
        return 1
    }

    # Get company name from dashboard
    local company_name=""
    local dashboard
    dashboard=$(ifn_get "/api/companies/${company_id}/dashboard" 2>/dev/null) || true
    company_name=$(echo "$dashboard" | jq -r '.company_name // empty' 2>/dev/null)

    # Write accounts to temp file and run Python discovery
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    echo "$accounts_response" > "${tmp_dir}/accounts.json"

    python3 "${SETTLEMENT_CLI}/lib/discover_accounts.py" \
        "${tmp_dir}/accounts.json" \
        --partner "$partner" \
        --company-id "$company_id" \
        --company-name "${company_name:-Unknown}"
}

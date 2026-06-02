#!/usr/bin/env bash
# dashboard.sh — Dashboard metrics for a company

cmd_dashboard() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: ifn dashboard <company_id>"
        echo ""
        echo "Show dashboard metrics: unbooked vouchers, staged actions, sync freshness."
        return
    fi

    ifn_require_arg "${1:-}" "company_id" "ifn dashboard <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/dashboard") || return 1
    ifn_output "$result"
}

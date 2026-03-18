#!/usr/bin/env bash
# dashboard.sh — Dashboard metrics for a company

cmd_dashboard() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: ifn dashboard <connection_id>"
        echo ""
        echo "Show dashboard metrics: unbooked vouchers, staged actions, sync freshness."
        return
    fi

    ifn_require_arg "${1:-}" "connection_id" "ifn dashboard <connection_id>"
    local conn_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/dashboard") || return 1
    ifn_output "$result"
}

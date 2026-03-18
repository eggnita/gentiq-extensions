#!/usr/bin/env bash
# analysis.sh — Financial analysis commands

cmd_analysis() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        accounts)   _analysis_accounts "$@" ;;
        balances)   _analysis_balances "$@" ;;
        integrity)  _analysis_integrity "$@" ;;
        series)     _analysis_series "$@" ;;
        --help|-h|"")
            echo "Usage: ifn analysis <subcommand> <connection_id> [options]"
            echo ""
            echo "Subcommands:"
            echo "  accounts  <conn_id>              Vouchers grouped by account"
            echo "  balances  <conn_id> <account_no>  Account balance across financial years"
            echo "  integrity <conn_id>              Data integrity check"
            echo "  series    <conn_id>              Voucher series → description mapping"
            ;;
        *)
            ifn_error "unknown analysis subcommand: $subcmd"
            return 1
            ;;
    esac
}

_analysis_accounts() {
    ifn_require_arg "${1:-}" "connection_id" "ifn analysis accounts <connection_id>"
    local conn_id="$1"
    shift

    # Parse optional financial year
    local fy=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --fy) fy="$2"; shift 2 ;;
            *)    shift ;;
        esac
    done

    local path="/api/companies/${conn_id}/internal/account-analysis"
    [ -n "$fy" ] && path="${path}?financial_year_id=${fy}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_analysis_balances() {
    ifn_require_arg "${1:-}" "connection_id" "ifn analysis balances <connection_id> <account_number>"
    ifn_require_arg "${2:-}" "account_number" "ifn analysis balances <connection_id> <account_number>"

    local conn_id="$1"
    local account_no="$2"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/internal/accounts/${account_no}/year-balances") || return 1
    ifn_output "$result"
}

_analysis_integrity() {
    ifn_require_arg "${1:-}" "connection_id" "ifn analysis integrity <connection_id>"
    local conn_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/internal/integrity") || return 1
    ifn_output "$result"
}

_analysis_series() {
    ifn_require_arg "${1:-}" "connection_id" "ifn analysis series <connection_id>"
    local conn_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/internal/voucherseries-map") || return 1
    ifn_output "$result"
}

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
            echo "Usage: ifn analysis <subcommand> <company_id> [options]"
            echo ""
            echo "Subcommands:"
            echo "  accounts  <company_id>              Vouchers grouped by account"
            echo "  balances  <company_id> <account_no>  Account balance across financial years"
            echo "  integrity <company_id>              Data integrity check"
            echo "  series    <company_id>              Voucher series → description mapping"
            ;;
        *)
            ifn_error "unknown analysis subcommand: $subcmd"
            return 1
            ;;
    esac
}

_analysis_accounts() {
    ifn_require_arg "${1:-}" "company_id" "ifn analysis accounts <company_id> --account <n>"
    local company_id="$1"
    shift

    local fy="" include_staged="false" account=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --fy)              fy="$2"; shift 2 ;;
            --include-staged)  include_staged="true"; shift ;;
            --account)         account="$2"; shift 2 ;;
            *)                 shift ;;
        esac
    done

    if [ -z "$account" ]; then
        ifn_error "missing required option: --account <number> (e.g. --account 1584)"
        return 1
    fi

    local qs="account=${account}"
    [ -n "$fy" ] && qs="${qs}&financial_year_id=${fy}"
    [ "$include_staged" = "true" ] && qs="${qs}&include_staged=true"

    local path="/api/companies/${company_id}/internal/account-analysis?${qs}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_analysis_balances() {
    ifn_require_arg "${1:-}" "company_id" "ifn analysis balances <company_id> <account_number>"
    ifn_require_arg "${2:-}" "account_number" "ifn analysis balances <company_id> <account_number>"

    local company_id="$1"
    local account_no="$2"

    local result
    result=$(ifn_get "/api/companies/${company_id}/internal/accounts/${account_no}/year-balances") || return 1
    ifn_output "$result"
}

_analysis_integrity() {
    ifn_require_arg "${1:-}" "company_id" "ifn analysis integrity <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/internal/integrity") || return 1
    ifn_output "$result"
}

_analysis_series() {
    ifn_require_arg "${1:-}" "company_id" "ifn analysis series <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/internal/voucherseries-map") || return 1
    ifn_output "$result"
}

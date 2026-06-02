#!/usr/bin/env bash
# sync.sh — Sync management commands
# Read-only operations available to all roles.
# Trigger and cancel require accountant+ role.

cmd_sync() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        status)     _sync_status "$@" ;;
        overview)   _sync_overview "$@" ;;
        years)      _sync_years "$@" ;;
        trigger)    _sync_trigger "$@" ;;
        cancel)     _sync_cancel "$@" ;;
        batch)      _sync_batch "$@" ;;
        cancel-all) _sync_cancel_all "$@" ;;
        --help|-h|"")
            echo "Usage: ifn sync <subcommand> [options]"
            echo ""
            echo "Subcommands:"
            echo "  status     <company_id>                Current sync job status"
            echo "  overview                               Global sync status across all companies"
            echo "  years      <company_id>                List financial years for a company"
            echo "  trigger    <company_id> [options]       Trigger ERP sync (accountant+)"
            echo "  cancel     <company_id> <job_id>        Cancel a running sync job"
            echo "  batch                                  Trigger sync across all companies"
            echo "  cancel-all <company_id> [options]       Cancel all running sync jobs"
            echo ""
            echo "Trigger options:"
            echo "  --doc-types <types>  Comma-separated: vouchers,invoices,supplierinvoices,..."
            echo "  --fy <id>            Financial year ID"
            echo "  --mode <mode>        incremental (default), full, or enrich_only"
            echo "  --from <date>        Start date (YYYY-MM-DD)"
            echo "  --to <date>          End date (YYYY-MM-DD)"
            ;;
        *)
            ifn_error "unknown sync subcommand: $subcmd"
            return 1
            ;;
    esac
}

_sync_status() {
    ifn_require_arg "${1:-}" "company_id" "ifn sync status <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/sync/status") || return 1
    ifn_output "$result"
}

_sync_overview() {
    local result
    result=$(ifn_get "/api/sync/overview") || return 1
    ifn_output "$result"
}

_sync_years() {
    ifn_require_arg "${1:-}" "company_id" "ifn sync years <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/sync/financial-years") || return 1
    ifn_output "$result"
}

_sync_trigger() {
    ifn_require_arg "${1:-}" "company_id" "ifn sync trigger <company_id> [options]"
    local company_id="$1"
    shift

    local doc_types="" fy="" mode="" fromdate="" todate=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --doc-types) doc_types="$2"; shift 2 ;;
            --fy)        fy="$2"; shift 2 ;;
            --mode)      mode="$2"; shift 2 ;;
            --from)      fromdate="$2"; shift 2 ;;
            --to)        todate="$2"; shift 2 ;;
            *)           shift ;;
        esac
    done

    # Build JSON body
    local body='{'

    # doc_types: comma-separated → JSON array
    if [ -n "$doc_types" ]; then
        local types_json
        types_json=$(echo "$doc_types" | tr ',' '\n' | jq -R . | jq -s .)
        body="${body}\"doc_types\":${types_json}"
    else
        body="${body}\"doc_types\":[\"vouchers\",\"invoices\",\"supplierinvoices\",\"customers\",\"suppliers\"]"
    fi

    [ -n "$fy" ] && body="${body},\"financial_year_id\":\"${fy}\""
    [ -n "$mode" ] && body="${body},\"mode\":\"${mode}\""
    [ -n "$fromdate" ] && body="${body},\"fromdate\":\"${fromdate}\""
    [ -n "$todate" ] && body="${body},\"todate\":\"${todate}\""
    body="${body}}"

    local result
    result=$(ifn_post "/api/companies/${company_id}/sync" "$body") || return 1
    ifn_output "$result"
}

_sync_cancel() {
    ifn_require_arg "${1:-}" "company_id" "ifn sync cancel <company_id> <job_id>"
    ifn_require_arg "${2:-}" "job_id" "ifn sync cancel <company_id> <job_id>"
    local company_id="$1"
    local job_id="$2"

    local result
    result=$(ifn_post "/api/companies/${company_id}/sync/${job_id}/cancel") || return 1
    ifn_output "$result"
}

_sync_batch() {
    local result
    result=$(ifn_post "/api/sync/batch") || return 1
    ifn_output "$result"
}

_sync_cancel_all() {
    ifn_require_arg "${1:-}" "company_id" "ifn sync cancel-all <company_id> [--parent-job-id n]"
    local company_id="$1"
    shift

    local parent_job_id=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --parent-job-id) parent_job_id="$2"; shift 2 ;;
            *)               shift ;;
        esac
    done

    local path="/api/companies/${company_id}/sync/cancel-all"
    [ -n "$parent_job_id" ] && path="${path}?parent_job_id=${parent_job_id}"

    local result
    result=$(ifn_post "$path") || return 1
    ifn_output "$result"
}

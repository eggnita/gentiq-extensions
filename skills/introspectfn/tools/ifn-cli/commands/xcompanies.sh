#!/usr/bin/env bash
# xcompanies.sh — Cross-company aggregation commands (read-only)

cmd_xcompanies() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        summary)          _xc_summary "$@" ;;
        vouchers)         _xc_list "vouchers" "$@" ;;
        invoices)         _xc_list "invoices" "$@" ;;
        supplierinvoices) _xc_list "supplierinvoices" "$@" ;;
        suppliers)        _xc_list "suppliers" "$@" ;;
        customers)        _xc_list "customers" "$@" ;;
        accounts)         _xc_accounts "$@" ;;
        files)            _xc_files "$@" ;;
        files-categories) _xc_files_categories "$@" ;;
        files-groups)     _xc_files_groups "$@" ;;
        --help|-h|"")
            echo "Usage: ifn xcompanies <subcommand> [options]"
            echo ""
            echo "Cross-company aggregation (read-only, no company_id needed)."
            echo ""
            echo "Subcommands:"
            echo "  summary                              Section counts across all companies"
            echo "  vouchers     [options]                Cross-company voucher list"
            echo "  invoices     [options]                Cross-company invoice list"
            echo "  supplierinvoices [options]            Cross-company supplier-invoice list"
            echo "  suppliers    [options]                Cross-company supplier list"
            echo "  customers    [options]                Cross-company customer list"
            echo "  accounts     [options]                Cross-company account list"
            echo "  files        [options]                Cross-company file list"
            echo "  files-categories                      Cross-company category directory"
            echo "  files-groups                          Cross-company group directory"
            echo ""
            echo "Common options:"
            echo "  --page <n>        Page number"
            echo "  --limit <n>       Records per page"
            echo "  --search <q>      Search text"
            echo "  --sort <field>    Sort field"
            echo "  --sortdir <dir>   asc or desc"
            echo ""
            echo "Date filters (vouchers, invoices, supplierinvoices):"
            echo "  --from-date <d>   Start date (YYYY-MM-DD)"
            echo "  --to-date <d>     End date (YYYY-MM-DD)"
            echo ""
            echo "Voucher-specific:"
            echo "  --series <code>   Voucher series"
            echo "  --number <n>      Voucher number"
            echo ""
            echo "Account-specific:"
            echo "  --financial-year-id <id>  Financial year"
            echo "  --number-min <n>          Min account number"
            echo "  --number-max <n>          Max account number"
            echo ""
            echo "File-specific:"
            echo "  --doc-type <type>          Document type"
            echo "  --category <cat>           Category filter"
            echo "  --group-id <id>            Group filter"
            echo "  --needs-categorization     Only uncategorized"
            ;;
        *)
            ifn_error "unknown xcompanies subcommand: $subcmd"
            return 1
            ;;
    esac
}

_xc_summary() {
    local result
    result=$(ifn_get "/api/xcompanies/summary") || return 1
    ifn_output "$result"
}

# Generic list for vouchers, invoices, supplierinvoices, suppliers, customers
_xc_list() {
    local resource="$1"
    shift

    local page="" limit="" search="" sort="" sortdir=""
    local from_date="" to_date="" series="" number=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --page)      page="$2"; shift 2 ;;
            --limit)     limit="$2"; shift 2 ;;
            --search)    search="$2"; shift 2 ;;
            --sort)      sort="$2"; shift 2 ;;
            --sortdir)   sortdir="$2"; shift 2 ;;
            --from-date) from_date="$2"; shift 2 ;;
            --to-date)   to_date="$2"; shift 2 ;;
            --series)    series="$2"; shift 2 ;;
            --number)    number="$2"; shift 2 ;;
            *)           shift ;;
        esac
    done

    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ -n "$search" ] && qs="${qs}&search=${search}"
    [ -n "$sort" ] && qs="${qs}&sort=${sort}"
    [ -n "$sortdir" ] && qs="${qs}&sortdir=${sortdir}"
    [ -n "$from_date" ] && qs="${qs}&from_date=${from_date}"
    [ -n "$to_date" ] && qs="${qs}&to_date=${to_date}"
    [ -n "$series" ] && qs="${qs}&series=${series}"
    [ -n "$number" ] && qs="${qs}&number=${number}"

    local path="/api/xcompanies/${resource}"
    [ -n "$qs" ] && path="${path}?${qs:1}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_xc_accounts() {
    local page="" limit="" search="" sort="" sortdir=""
    local financial_year_id="" number_min="" number_max=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --page)              page="$2"; shift 2 ;;
            --limit)             limit="$2"; shift 2 ;;
            --search)            search="$2"; shift 2 ;;
            --sort)              sort="$2"; shift 2 ;;
            --sortdir)           sortdir="$2"; shift 2 ;;
            --financial-year-id) financial_year_id="$2"; shift 2 ;;
            --number-min)        number_min="$2"; shift 2 ;;
            --number-max)        number_max="$2"; shift 2 ;;
            *)                   shift ;;
        esac
    done

    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ -n "$search" ] && qs="${qs}&search=${search}"
    [ -n "$sort" ] && qs="${qs}&sort=${sort}"
    [ -n "$sortdir" ] && qs="${qs}&sortdir=${sortdir}"
    [ -n "$financial_year_id" ] && qs="${qs}&financial_year_id=${financial_year_id}"
    [ -n "$number_min" ] && qs="${qs}&number_min=${number_min}"
    [ -n "$number_max" ] && qs="${qs}&number_max=${number_max}"

    local path="/api/xcompanies/accounts"
    [ -n "$qs" ] && path="${path}?${qs:1}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_xc_files() {
    local page="" limit="" search="" sort="" sortdir=""
    local doc_type="" category="" group_id="" needs_categorization="false"

    while [ $# -gt 0 ]; do
        case "$1" in
            --page)                  page="$2"; shift 2 ;;
            --limit)                 limit="$2"; shift 2 ;;
            --search)                search="$2"; shift 2 ;;
            --sort)                  sort="$2"; shift 2 ;;
            --sortdir)               sortdir="$2"; shift 2 ;;
            --doc-type)              doc_type="$2"; shift 2 ;;
            --category)              category="$2"; shift 2 ;;
            --group-id)              group_id="$2"; shift 2 ;;
            --needs-categorization)  needs_categorization="true"; shift ;;
            *)                       shift ;;
        esac
    done

    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ -n "$search" ] && qs="${qs}&search=${search}"
    [ -n "$sort" ] && qs="${qs}&sort=${sort}"
    [ -n "$sortdir" ] && qs="${qs}&sortdir=${sortdir}"
    [ -n "$doc_type" ] && qs="${qs}&doc_type=${doc_type}"
    [ -n "$category" ] && qs="${qs}&category=${category}"
    [ -n "$group_id" ] && qs="${qs}&group_id=${group_id}"
    [ "$needs_categorization" = "true" ] && qs="${qs}&needs_categorization=true"

    local path="/api/xcompanies/files"
    [ -n "$qs" ] && path="${path}?${qs:1}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_xc_files_categories() {
    local result
    result=$(ifn_get "/api/xcompanies/files/categories") || return 1
    ifn_output "$result"
}

_xc_files_groups() {
    local result
    result=$(ifn_get "/api/xcompanies/files/groups") || return 1
    ifn_output "$result"
}

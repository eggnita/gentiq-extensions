#!/usr/bin/env bash
# records.sh — Browse locally synced ERP records

cmd_records() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: ifn records <company_id> <doc_type> [record_id] [options]"
        echo ""
        echo "Browse locally synced ERP records."
        echo ""
        echo "Doc types: vouchers, invoices, supplierinvoices, customers,"
        echo "  suppliers, accounts, financialyears, voucherseries"
        echo ""
        echo "Special subcommands:"
        echo "  files   [--doc-type <type>] [--search <q>]  List synced file attachments"
        echo ""
        echo "Options:"
        echo "  --page <n>           Page number"
        echo "  --limit <n>          Records per page"
        echo "  --fy <id>            Financial year ID"
        echo "  --include-staged     Include staged actions (vouchers only)"
        echo "  --refresh            Re-fetch a specific record from ERP (requires --fy)"
        echo "  --ensure-fresh       Auto-refresh before fetching (requires --fy)"
        return
    fi

    ifn_require_arg "${1:-}" "company_id" "ifn records <company_id> <doc_type> [id]"
    ifn_require_arg "${2:-}" "doc_type" "ifn records <company_id> <doc_type> [id]"

    local company_id="$1"
    local doc_type="$2"
    shift 2

    # Dispatch special subcommands
    case "$doc_type" in
        files)
            _records_files "$company_id" "$@"
            return
            ;;
    esac

    # Check for record ID
    local record_id=""
    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
        record_id="$1"
        shift
    fi

    # Parse options
    local page="" limit="" fy="" include_staged="false" refresh="false" ensure_fresh="false"
    local email="" phone="" referencenumber=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --page)              page="$2"; shift 2 ;;
            --limit)             limit="$2"; shift 2 ;;
            --fy)                fy="$2"; shift 2 ;;
            --include-staged)    include_staged="true"; shift ;;
            --refresh)           refresh="true"; shift ;;
            --ensure-fresh)      ensure_fresh="true"; shift ;;
            --email)             email="$2"; shift 2 ;;
            --phone)             phone="$2"; shift 2 ;;
            --referencenumber)   referencenumber="$2"; shift 2 ;;
            *)                   shift ;;
        esac
    done

    local path="/api/companies/${company_id}/internal/${doc_type}"

    # Handle explicit --refresh flag
    if [ "$refresh" = "true" ] && [ -n "$record_id" ]; then
        local refresh_path="${path}"
        [ -n "$fy" ] && refresh_path="${refresh_path}/FY-${fy}"
        refresh_path="${refresh_path}/${record_id}/refresh"

        local result
        result=$(ifn_post "$refresh_path") || return 1
        ifn_output "$result"
        return
    fi

    # Handle --ensure-fresh: auto-refresh before fetching (vouchers only)
    if [ "$ensure_fresh" = "true" ] && [ -n "$record_id" ]; then
        local refresh_path="${path}"
        [ -n "$fy" ] && refresh_path="${refresh_path}/FY-${fy}"
        refresh_path="${refresh_path}/${record_id}/refresh"

        if [ "$IFN_VERBOSE" = "true" ]; then
            echo "[records] auto-refreshing ${doc_type}/${record_id} from Fortnox..." >&2
        fi
        ifn_post "$refresh_path" >/dev/null 2>&1 || {
            echo "[warning] refresh failed, returning cached data" >&2
        }
    fi

    # Build fetch path
    if [ -n "$record_id" ] && [ -n "$fy" ]; then
        path="${path}/FY-${fy}/${record_id}"
    elif [ -n "$record_id" ]; then
        path="${path}/${record_id}"
    fi

    # Build query string
    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ "$include_staged" = "true" ] && qs="${qs}&include_staged=true"
    [ -n "$email" ] && qs="${qs}&email=${email}"
    [ -n "$phone" ] && qs="${qs}&phone=${phone}"
    [ -n "$referencenumber" ] && qs="${qs}&referencenumber=${referencenumber}"
    # FY on LIST queries — when there's no record_id the FY-in-path branch
    # above doesn't fire, so pass it as a query param instead. Matches the
    # convention `files.sh` uses on the same /internal/... family.
    [ -z "$record_id" ] && [ -n "$fy" ] && qs="${qs}&financial_year_id=${fy}"

    if [ -n "$qs" ]; then
        path="${path}?${qs:1}"
    fi

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

# List synced file attachments
_records_files() {
    local company_id="$1"
    shift

    local page="" limit="" doc_type="" search=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --page)      page="$2"; shift 2 ;;
            --limit)     limit="$2"; shift 2 ;;
            --doc-type)  doc_type="$2"; shift 2 ;;
            --search)    search="$2"; shift 2 ;;
            *)           shift ;;
        esac
    done

    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ -n "$doc_type" ] && qs="${qs}&doc_type=${doc_type}"
    [ -n "$search" ] && qs="${qs}&search=${search}"

    local path="/api/companies/${company_id}/internal/files"
    if [ -n "$qs" ]; then
        path="${path}?${qs:1}"
    fi

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

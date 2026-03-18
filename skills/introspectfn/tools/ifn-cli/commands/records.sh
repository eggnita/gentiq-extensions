#!/usr/bin/env bash
# records.sh — Browse locally synced ERP records

cmd_records() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: ifn records <connection_id> <doc_type> [record_id] [options]"
        echo ""
        echo "Browse locally synced ERP records."
        echo ""
        echo "Doc types: vouchers, invoices, supplierinvoices, customers,"
        echo "  suppliers, accounts, financialyears, voucherseries"
        echo ""
        echo "Options:"
        echo "  --page <n>           Page number"
        echo "  --limit <n>          Records per page"
        echo "  --include-staged     Include staged actions (vouchers only)"
        echo "  --refresh            Re-fetch a specific record from ERP"
        return
    fi

    ifn_require_arg "${1:-}" "connection_id" "ifn records <connection_id> <doc_type> [id]"
    ifn_require_arg "${2:-}" "doc_type" "ifn records <connection_id> <doc_type> [id]"

    local conn_id="$1"
    local doc_type="$2"
    shift 2

    # Check for record ID
    local record_id=""
    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
        record_id="$1"
        shift
    fi

    # Parse options
    local page="" limit="" include_staged="false" refresh="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --page)            page="$2"; shift 2 ;;
            --limit)           limit="$2"; shift 2 ;;
            --include-staged)  include_staged="true"; shift ;;
            --refresh)         refresh="true"; shift ;;
            *)                 shift ;;
        esac
    done

    local path="/api/companies/${conn_id}/internal/${doc_type}"

    if [ -n "$record_id" ]; then
        if [ "$refresh" = "true" ]; then
            local result
            result=$(ifn_post "${path}/${record_id}/refresh") || return 1
            ifn_output "$result"
            return
        fi
        path="${path}/${record_id}"
    fi

    # Build query string
    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ "$include_staged" = "true" ] && qs="${qs}&include_staged=true"

    if [ -n "$qs" ]; then
        path="${path}?${qs:1}"
    fi

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

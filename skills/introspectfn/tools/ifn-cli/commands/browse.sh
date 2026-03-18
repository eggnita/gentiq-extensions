#!/usr/bin/env bash
# browse.sh — Browse live ERP records (external proxy)

cmd_browse() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: ifn browse <connection_id> <resource> [record_id] [options]"
        echo ""
        echo "Browse live ERP data via the Fortnox proxy."
        echo ""
        echo "Resources: customers, invoices, articles, accounts, vouchers,"
        echo "  suppliers, orders, offers, projects, costcenters,"
        echo "  supplierinvoices, companyinformation, financialyears, voucherseries"
        echo ""
        echo "Options:"
        echo "  --page <n>        Page number (default: 1)"
        echo "  --limit <n>       Records per page (default: 100)"
        echo "  --filter <expr>   Fortnox filter expression"
        echo "  --sortby <field>  Sort field"
        echo "  --sortorder <dir> asc or desc"
        echo "  --fy <id>         Financial year ID"
        return
    fi

    ifn_require_arg "${1:-}" "connection_id" "ifn browse <connection_id> <resource> [id]"
    ifn_require_arg "${2:-}" "resource" "ifn browse <connection_id> <resource> [id]"

    local conn_id="$1"
    local resource="$2"
    shift 2

    # Check for record ID (next arg if not a flag)
    local record_id=""
    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
        record_id="$1"
        shift
    fi

    # Parse optional params
    local page="" limit="" filter="" sortby="" sortorder="" fy=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --page)     page="$2"; shift 2 ;;
            --limit)    limit="$2"; shift 2 ;;
            --filter)   filter="$2"; shift 2 ;;
            --sortby)   sortby="$2"; shift 2 ;;
            --sortorder) sortorder="$2"; shift 2 ;;
            --fy)       fy="$2"; shift 2 ;;
            *)          shift ;;
        esac
    done

    local path="/api/companies/${conn_id}/external/${resource}"

    if [ -n "$record_id" ]; then
        path="${path}/${record_id}"
    fi

    # Build query string
    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ -n "$filter" ] && qs="${qs}&filter=${filter}"
    [ -n "$sortby" ] && qs="${qs}&sortby=${sortby}"
    [ -n "$sortorder" ] && qs="${qs}&sortorder=${sortorder}"
    [ -n "$fy" ] && qs="${qs}&financialyear=${fy}"

    if [ -n "$qs" ]; then
        path="${path}?${qs:1}"  # Strip leading &
    fi

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

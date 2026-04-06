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
        echo "Special subcommands:"
        echo "  account-info <number>        Get account description by number"
        echo "  fileconnections --entity <e>  List file attachments for an entity"
        echo "  file-counts --entity <e>      Batch file-connection counts"
        echo "  archive <file_id>             Download an archive file"
        echo "  inbox [folder_id]             List ERP inbox (or folder contents)"
        echo "  inbox-file <file_id>          Download an inbox file"
        echo ""
        echo "Options (for resource listings):"
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

    # Dispatch special subcommands
    case "$resource" in
        account-info)       _browse_account_info "$conn_id" "$@"; return ;;
        fileconnections)    _browse_fileconnections "$conn_id" "$@"; return ;;
        file-counts)        _browse_file_counts "$conn_id" "$@"; return ;;
        archive)            _browse_archive "$conn_id" "$@"; return ;;
        inbox)              _browse_inbox "$conn_id" "$@"; return ;;
        inbox-file)         _browse_inbox_file "$conn_id" "$@"; return ;;
    esac

    # Default: external resource proxy
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

    if [ -n "$record_id" ] && [ -n "$fy" ]; then
        # FY-in-path: /external/{resource}/FY-{fy}/{record_id}
        path="${path}/FY-${fy}/${record_id}"
        fy=""  # consumed — don't add as query param
    elif [ -n "$record_id" ]; then
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

# Get account description by number
_browse_account_info() {
    local conn_id="$1"
    shift
    ifn_require_arg "${1:-}" "account_number" "ifn browse <conn_id> account-info <account_number>"
    local account_number="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/accounts/${account_number}") || return 1
    ifn_output "$result"
}

# List file connections (attachments) for an entity
_browse_fileconnections() {
    local conn_id="$1"
    shift

    local entity="" number="" series="" fy=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --entity) entity="$2"; shift 2 ;;
            --number) number="$2"; shift 2 ;;
            --series) series="$2"; shift 2 ;;
            --fy)     fy="$2"; shift 2 ;;
            *)        shift ;;
        esac
    done

    if [ -z "$entity" ]; then
        ifn_error "missing required option: --entity <entity_type>"
        echo "Usage: ifn browse <conn_id> fileconnections --entity <type> [--number <n>] [--series <s>] [--fy <id>]" >&2
        return 1
    fi

    local qs="entity=${entity}"
    [ -n "$number" ] && qs="${qs}&number=${number}"
    [ -n "$series" ] && qs="${qs}&series=${series}"
    [ -n "$fy" ] && qs="${qs}&financialyear=${fy}"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/external/fileconnections?${qs}") || return 1
    ifn_output "$result"
}

# Batch file-connection counts for an entity type
_browse_file_counts() {
    local conn_id="$1"
    shift

    local entity="" fy=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --entity) entity="$2"; shift 2 ;;
            --fy)     fy="$2"; shift 2 ;;
            *)        shift ;;
        esac
    done

    if [ -z "$entity" ]; then
        ifn_error "missing required option: --entity <entity_type>"
        echo "Usage: ifn browse <conn_id> file-counts --entity <type> [--fy <id>]" >&2
        return 1
    fi

    local qs="entity=${entity}"
    [ -n "$fy" ] && qs="${qs}&financialyear=${fy}"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/fileconnection-counts?${qs}") || return 1
    ifn_output "$result"
}

# Download an archive file
_browse_archive() {
    local conn_id="$1"
    shift
    ifn_require_arg "${1:-}" "file_id" "ifn browse <conn_id> archive <file_id>"
    local file_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/external/archive/${file_id}") || return 1
    ifn_output "$result"
}

# Download an inbox file
_browse_inbox_file() {
    local conn_id="$1"
    shift
    ifn_require_arg "${1:-}" "file_id" "ifn browse <conn_id> inbox-file <file_id>"
    local file_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/inbox/file/${file_id}") || return 1
    ifn_output "$result"
}

# List ERP inbox or folder contents
_browse_inbox() {
    local conn_id="$1"
    shift

    local folder_id=""
    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
        folder_id="$1"
        shift
    fi

    local path="/api/companies/${conn_id}/inbox"
    if [ -n "$folder_id" ]; then
        path="${path}/${folder_id}"
    fi

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

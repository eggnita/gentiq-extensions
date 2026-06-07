#!/usr/bin/env bash
# files.sh — File management commands (browse, download, categorize)

cmd_files() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list)           _files_list "$@" ;;
        fetch)          _files_fetch "$@" ;;
        refresh)        _files_refresh "$@" ;;
        categories)     _files_categories "$@" ;;
        groups)         _files_groups "$@" ;;
        inbox-folders)  _files_inbox_folders "$@" ;;
        refs)           _files_refs "$@" ;;
        metadata)       _files_metadata "$@" ;;
        --help|-h|"")
            echo "Usage: ifn files <subcommand> <company_id> [options]"
            echo ""
            echo "Subcommands:"
            echo "  list           <company_id> [options]              List synced file attachments"
            echo "  fetch          <company_id> <file_id> [--live]     Download file to temp path"
            echo "  refresh        <company_id> <file_id>              Re-download from Fortnox into local storage"
            echo "  categories     <company_id>                        List file categories with counts"
            echo "  groups         <company_id> [group_id]             List groups (or files in a group)"
            echo "  inbox-folders  <company_id>                        Inbox folder breakdown"
            echo "  refs           <company_id> <file_id>              List ERP records referencing a file"
            echo "  metadata       <company_id> <file_id> [options]    Set file category/group/details"
            echo ""
            echo "List options:"
            echo "  --page <n>                 Page number"
            echo "  --limit <n>                Records per page"
            echo "  --doc-type <type>          Filter by document type"
            echo "  --search <query>           Search text"
            echo "  --sort <field>             Sort field"
            echo "  --sortdir <dir>            asc or desc"
            echo "  --category <cat>           Filter by category"
            echo "  --group-id <id>            Filter by metadata group"
            echo "  --needs-categorization     Only uncategorized files"
            echo "  --financial-year-id <id>   Filter by financial year"
            echo "  --voucher-series <code>    Filter by voucher series"
            echo "  --inbox-folder <id>        Filter by inbox folder"
            echo ""
            echo "Metadata options:"
            echo "  --category <cat>           Set file category"
            echo "  --group-id <id>            Set metadata group"
            echo "  --details <text>           Set details/description"
            ;;
        *)
            ifn_error "unknown files subcommand: $subcmd"
            return 1
            ;;
    esac
}

_files_list() {
    ifn_require_arg "${1:-}" "company_id" "ifn files list <company_id> [options]"
    local company_id="$1"
    shift

    local page="" limit="" doc_type="" search="" sort="" sortdir=""
    local category="" group_id="" needs_categorization="false"
    local financial_year_id="" voucher_series="" inbox_folder=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --page)                  page="$2"; shift 2 ;;
            --limit)                 limit="$2"; shift 2 ;;
            --doc-type)              doc_type="$2"; shift 2 ;;
            --search)                search="$2"; shift 2 ;;
            --sort)                  sort="$2"; shift 2 ;;
            --sortdir)               sortdir="$2"; shift 2 ;;
            --category)              category="$2"; shift 2 ;;
            --group-id)              group_id="$2"; shift 2 ;;
            --needs-categorization)  needs_categorization="true"; shift ;;
            --financial-year-id)     financial_year_id="$2"; shift 2 ;;
            --voucher-series)        voucher_series="$2"; shift 2 ;;
            --inbox-folder)          inbox_folder="$2"; shift 2 ;;
            *)                       shift ;;
        esac
    done

    local qs=""
    [ -n "$page" ] && qs="${qs}&page=${page}"
    [ -n "$limit" ] && qs="${qs}&limit=${limit}"
    [ -n "$doc_type" ] && qs="${qs}&doc_type=${doc_type}"
    [ -n "$search" ] && qs="${qs}&search=${search}"
    [ -n "$sort" ] && qs="${qs}&sort=${sort}"
    [ -n "$sortdir" ] && qs="${qs}&sortdir=${sortdir}"
    [ -n "$category" ] && qs="${qs}&category=${category}"
    [ -n "$group_id" ] && qs="${qs}&group_id=${group_id}"
    [ "$needs_categorization" = "true" ] && qs="${qs}&needs_categorization=true"
    [ -n "$financial_year_id" ] && qs="${qs}&financial_year_id=${financial_year_id}"
    [ -n "$voucher_series" ] && qs="${qs}&voucher_series=${voucher_series}"
    [ -n "$inbox_folder" ] && qs="${qs}&inbox_folder=${inbox_folder}"

    local path="/api/companies/${company_id}/internal/files"
    if [ -n "$qs" ]; then
        path="${path}?${qs:1}"
    fi

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_files_fetch() {
    ifn_require_arg "${1:-}" "company_id" "ifn files fetch <company_id> <file_id> [--live]"
    ifn_require_arg "${2:-}" "file_id" "ifn files fetch <company_id> <file_id> [--live]"

    local company_id="$1"
    local file_id="$2"
    shift 2

    local live="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --live) live="true"; shift ;;
            *)      shift ;;
        esac
    done

    local path
    if [ "$live" = "true" ]; then
        path="/api/companies/${company_id}/external/archive/${file_id}"
    else
        path="/api/companies/${company_id}/internal/archive/${file_id}"
    fi

    local tmpfile
    tmpfile="/tmp/ifn-${file_id}"

    ifn_get_binary "$path" > "$tmpfile"

    echo "$tmpfile"
}

_files_refresh() {
    ifn_require_arg "${1:-}" "company_id" "ifn files refresh <company_id> <file_id>"
    ifn_require_arg "${2:-}" "file_id" "ifn files refresh <company_id> <file_id>"

    local company_id="$1"
    local file_id="$2"

    local result
    result=$(ifn_post "/api/companies/${company_id}/files/${file_id}/refresh") || return 1
    ifn_output "$result"
}

_files_categories() {
    ifn_require_arg "${1:-}" "company_id" "ifn files categories <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/files/categories") || return 1
    ifn_output "$result"
}

_files_groups() {
    ifn_require_arg "${1:-}" "company_id" "ifn files groups <company_id> [group_id]"
    local company_id="$1"
    shift

    local group_id=""
    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
        group_id="$1"
        shift
    fi

    local path
    if [ -n "$group_id" ]; then
        path="/api/companies/${company_id}/files/groups/${group_id}"
    else
        path="/api/companies/${company_id}/files/groups"
    fi

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_files_inbox_folders() {
    ifn_require_arg "${1:-}" "company_id" "ifn files inbox-folders <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/files/inbox-folders") || return 1
    ifn_output "$result"
}

_files_refs() {
    ifn_require_arg "${1:-}" "company_id" "ifn files refs <company_id> <file_id>"
    ifn_require_arg "${2:-}" "file_id" "ifn files refs <company_id> <file_id>"

    local company_id="$1"
    local file_id="$2"

    local result
    result=$(ifn_get "/api/companies/${company_id}/files/${file_id}/refs") || return 1
    ifn_output "$result"
}

_files_metadata() {
    ifn_require_arg "${1:-}" "company_id" "ifn files metadata <company_id> <file_id> [options]"
    ifn_require_arg "${2:-}" "file_id" "ifn files metadata <company_id> <file_id> [options]"

    local company_id="$1"
    local file_id="$2"
    shift 2

    local category="" group_id="" details=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --category) category="$2"; shift 2 ;;
            --group-id) group_id="$2"; shift 2 ;;
            --details)  details="$2"; shift 2 ;;
            *)          shift ;;
        esac
    done

    # Build JSON body. category and group_id are plain strings (wrap in
    # quotes). `details` is passed in as raw JSON — wrapping it in quotes
    # would make the body invalid as soon as the JSON contains its own
    # quotes (which it always does for an object), and would store the
    # value as a string-of-JSON in IFN rather than as a structured JSON
    # object. Inline it raw.
    local body='{'
    local first="true"
    if [ -n "$category" ]; then
        body="${body}\"category\":\"${category}\""
        first="false"
    fi
    if [ -n "$group_id" ]; then
        [ "$first" = "false" ] && body="${body},"
        body="${body}\"group_id\":\"${group_id}\""
        first="false"
    fi
    if [ -n "$details" ]; then
        [ "$first" = "false" ] && body="${body},"
        body="${body}\"details\":${details}"
    fi
    body="${body}}"

    local result
    result=$(ifn_patch "/api/companies/${company_id}/files/${file_id}/metadata" "$body") || return 1
    ifn_output "$result"
}

#!/usr/bin/env bash
# staging.sh — Staging workflow commands (propose, review)
# Only implements assistant-level operations (API key scoped).
# Approve, execute, and resume require accountant+ and are not included.

cmd_staging() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list)        _staging_list "$@" ;;
        list-all)    _staging_list_all "$@" ;;
        get)         _staging_get "$@" ;;
        propose)     _staging_propose "$@" ;;
        edit)        _staging_edit "$@" ;;
        clone)       _staging_clone "$@" ;;
        reject)      _staging_reject "$@" ;;
        next-number) _staging_next_number "$@" ;;
        upload)      _staging_upload "$@" ;;
        --help|-h|"")
            echo "Usage: ifn staging <subcommand> [options]"
            echo ""
            echo "Subcommands:"
            echo "  list         <conn_id>                List staged actions for a company"
            echo "  list-all                              List all staged actions across companies"
            echo "  get          <action_id>              Get details of a staged action"
            echo "  propose      <conn_id> <json_file>    Propose a new staging action"
            echo "  edit         <action_id> <json_file>  Edit own staged action (payload, notes, reasoning)"
            echo "  clone        <action_id>              Clone a staged action"
            echo "  reject       <action_id>              Reject own staged action"
            echo "  next-number  <conn_id> [options]      Get predicted next voucher number"
            echo "  upload       <conn_id> <file_path>    Upload a file for attachment"
            echo ""
            echo "Next-number options:"
            echo "  --series <code>   Voucher series (default: A)"
            echo "  --fy <id>         Financial year ID"
            ;;
        *)
            ifn_error "unknown staging subcommand: $subcmd"
            return 1
            ;;
    esac
}

_staging_list() {
    ifn_require_arg "${1:-}" "connection_id" "ifn staging list <connection_id>"
    local conn_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/staging") || return 1
    ifn_output "$result"
}

_staging_list_all() {
    local result
    result=$(ifn_get "/api/staging") || return 1
    ifn_output "$result"
}

_staging_get() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging get <action_id>"
    local action_id="$1"

    local result
    result=$(ifn_get "/api/staging/${action_id}") || return 1
    ifn_output "$result"
}

_staging_propose() {
    ifn_require_arg "${1:-}" "connection_id" "ifn staging propose <connection_id> <json_file>"
    ifn_require_arg "${2:-}" "json_file" "ifn staging propose <connection_id> <json_file>"

    local conn_id="$1"
    local json_file="$2"

    if [ ! -f "$json_file" ]; then
        ifn_error "file not found: $json_file"
        return 1
    fi

    local body
    body=$(cat "$json_file")

    # Validate JSON
    if ! echo "$body" | jq empty 2>/dev/null; then
        ifn_error "invalid JSON in $json_file"
        return 1
    fi

    local result
    result=$(ifn_post "/api/companies/${conn_id}/staging" "$body") || return 1
    ifn_output "$result"
}

_staging_edit() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging edit <action_id> <json_file>"
    ifn_require_arg "${2:-}" "json_file" "ifn staging edit <action_id> <json_file>"

    local action_id="$1"
    local json_file="$2"

    if [ ! -f "$json_file" ]; then
        ifn_error "file not found: $json_file"
        return 1
    fi

    local body
    body=$(cat "$json_file")

    local result
    result=$(ifn_patch "/api/staging/${action_id}" "$body") || return 1
    ifn_output "$result"
}

_staging_clone() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging clone <action_id>"
    local action_id="$1"

    local result
    result=$(ifn_post "/api/staging/${action_id}/clone") || return 1
    ifn_output "$result"
}

_staging_reject() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging reject <action_id>"
    local action_id="$1"

    local result
    result=$(ifn_post "/api/staging/${action_id}/reject") || return 1
    ifn_output "$result"
}

_staging_next_number() {
    ifn_require_arg "${1:-}" "connection_id" "ifn staging next-number <connection_id>"
    local conn_id="$1"
    shift

    local series="A" fy=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --series) series="$2"; shift 2 ;;
            --fy)     fy="$2"; shift 2 ;;
            *)        shift ;;
        esac
    done

    local path="/api/companies/${conn_id}/staging/next-number?series=${series}"
    [ -n "$fy" ] && path="${path}&financial_year_id=${fy}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_staging_upload() {
    ifn_require_arg "${1:-}" "connection_id" "ifn staging upload <connection_id> <file_path>"
    ifn_require_arg "${2:-}" "file_path" "ifn staging upload <connection_id> <file_path>"

    local conn_id="$1"
    local file_path="$2"

    if [ ! -f "$file_path" ]; then
        ifn_error "file not found: $file_path"
        return 1
    fi

    local result
    result=$(ifn_upload "/api/companies/${conn_id}/staging/upload-file" "$file_path") || return 1
    ifn_output "$result"
}

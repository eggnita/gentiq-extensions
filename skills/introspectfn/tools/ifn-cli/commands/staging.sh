#!/usr/bin/env bash
# staging.sh — Staging workflow commands (propose, review)
# Only implements assistant-level operations (API key scoped).
# Approve, execute, and resume require accountant+ and are not included.

cmd_staging() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list)           _staging_list "$@" ;;
        list-all)       _staging_list_all "$@" ;;
        get)            _staging_get "$@" ;;
        propose)        _staging_propose "$@" ;;
        edit)           _staging_edit "$@" ;;
        clone)          _staging_clone "$@" ;;
        reject)         _staging_reject "$@" ;;
        next-number)    _staging_next_number "$@" ;;
        upload)         _staging_upload "$@" ;;
        write-windows)  _staging_write_windows "$@" ;;
        archive)        _staging_archive "$@" ;;
        file-refs)      _staging_file_refs "$@" ;;
        uploads)        _staging_uploads "$@" ;;
        upload-action)  _staging_upload_action "$@" ;;
        remove-upload)  _staging_remove_upload "$@" ;;
        --help|-h|"")
            echo "Usage: ifn staging <subcommand> [options]"
            echo ""
            echo "Subcommands:"
            echo "  list          <company_id>                List staged actions for a company"
            echo "  list-all                               List all staged actions across companies"
            echo "  get           <action_id>              Get details of a staged action"
            echo "  propose       <company_id> <json_file>    Propose a new staging action"
            echo "  edit          <action_id> <json_file>  Edit own staged action (payload, notes, reasoning)"
            echo "  clone         <action_id>              Clone a staged action"
            echo "  reject        <action_id>              Reject own staged action"
            echo "  next-number   <company_id> [options]      Get predicted next voucher number"
            echo "  upload        <company_id> <file_path>    Upload a file for attachment (company-scoped)"
            echo "  write-windows <company_id>                List write windows for a company"
            echo "  archive       [--action-id <id>]       Archive rejected/failed actions"
            echo "  file-refs     <action_id> --data <json>  Replace file refs on a staged action"
            echo "  uploads       <action_id>              List staged uploads for an action"
            echo "  upload-action <action_id> <file_path>  Upload file to a specific action"
            echo "  remove-upload <action_id> <file_id>    Remove a staged upload"
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
    ifn_require_arg "${1:-}" "company_id" "ifn staging list <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/bk-staging") || return 1
    ifn_output "$result"
}

_staging_list_all() {
    local result
    result=$(ifn_get "/api/bk-staging") || return 1
    ifn_output "$result"
}

_staging_get() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging get <action_id>"
    local action_id="$1"

    local result
    result=$(ifn_get "/api/bk-staging/${action_id}") || return 1
    ifn_output "$result"
}

_staging_propose() {
    ifn_require_arg "${1:-}" "company_id" "ifn staging propose <company_id> <json_file>"
    ifn_require_arg "${2:-}" "json_file" "ifn staging propose <company_id> <json_file>"

    local company_id="$1"
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
    result=$(ifn_post "/api/companies/${company_id}/bk-staging" "$body") || return 1
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
    result=$(ifn_patch "/api/bk-staging/${action_id}" "$body") || return 1
    ifn_output "$result"
}

_staging_clone() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging clone <action_id>"
    local action_id="$1"

    local result
    result=$(ifn_post "/api/bk-staging/${action_id}/clone") || return 1
    ifn_output "$result"
}

_staging_reject() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging reject <action_id>"
    local action_id="$1"

    local result
    result=$(ifn_post "/api/bk-staging/${action_id}/reject") || return 1
    ifn_output "$result"
}

_staging_next_number() {
    ifn_require_arg "${1:-}" "company_id" "ifn staging next-number <company_id>"
    local company_id="$1"
    shift

    local series="A" fy=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --series) series="$2"; shift 2 ;;
            --fy)     fy="$2"; shift 2 ;;
            *)        shift ;;
        esac
    done

    local path="/api/companies/${company_id}/bk-staging/next-number?series=${series}"
    [ -n "$fy" ] && path="${path}&financial_year_id=${fy}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_staging_upload() {
    ifn_require_arg "${1:-}" "company_id" "ifn staging upload <company_id> <file_path>"
    ifn_require_arg "${2:-}" "file_path" "ifn staging upload <company_id> <file_path>"

    local company_id="$1"
    local file_path="$2"

    if [ ! -f "$file_path" ]; then
        ifn_error "file not found: $file_path"
        return 1
    fi

    local result
    result=$(ifn_upload "/api/companies/${company_id}/bk-staging/upload-file" "$file_path") || return 1
    ifn_output "$result"
}

_staging_write_windows() {
    ifn_require_arg "${1:-}" "company_id" "ifn staging write-windows <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/write-windows") || return 1
    ifn_output "$result"
}

_staging_archive() {
    local action_id=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --action-id) action_id="$2"; shift 2 ;;
            *)           shift ;;
        esac
    done

    local result
    if [ -n "$action_id" ]; then
        result=$(ifn_post "/api/bk-staging/${action_id}/archive") || return 1
    else
        result=$(ifn_post "/api/bk-staging/archive") || return 1
    fi
    ifn_output "$result"
}

_staging_file_refs() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging file-refs <action_id> --data <json>"
    local action_id="$1"
    shift

    local data=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --data) data="$2"; shift 2 ;;
            *)      shift ;;
        esac
    done

    if [ -z "$data" ]; then
        ifn_error "missing required option: --data <json>"
        return 1
    fi

    local result
    result=$(ifn_patch "/api/bk-staging/${action_id}/file-refs" "$data") || return 1
    ifn_output "$result"
}

_staging_uploads() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging uploads <action_id>"
    local action_id="$1"

    local result
    result=$(ifn_get "/api/bk-staging/${action_id}/uploads") || return 1
    ifn_output "$result"
}

_staging_upload_action() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging upload-action <action_id> <file_path>"
    ifn_require_arg "${2:-}" "file_path" "ifn staging upload-action <action_id> <file_path>"

    local action_id="$1"
    local file_path="$2"

    if [ ! -f "$file_path" ]; then
        ifn_error "file not found: $file_path"
        return 1
    fi

    local result
    result=$(ifn_upload "/api/bk-staging/${action_id}/upload-file" "$file_path") || return 1
    ifn_output "$result"
}

_staging_remove_upload() {
    ifn_require_arg "${1:-}" "action_id" "ifn staging remove-upload <action_id> <file_id>"
    ifn_require_arg "${2:-}" "file_id" "ifn staging remove-upload <action_id> <file_id>"

    local action_id="$1"
    local file_id="$2"

    local result
    result=$(ifn_delete "/api/bk-staging/${action_id}/uploads/${file_id}") || return 1
    ifn_output "$result"
}

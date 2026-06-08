#!/usr/bin/env bash
# bko.sh — Bookkeeping Object (BKO) workflow commands
# Phase-2 bookkeeping: propose/edit/approve/execute/resume with per-record deviation tracking.
# Mirrors staging.sh, plus approve/execute/resume verbs unique to BKO.

cmd_bko() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list)              _bko_list "$@" ;;
        list-all)          _bko_list_all "$@" ;;
        get)               _bko_get "$@" ;;
        propose)           _bko_propose "$@" ;;
        edit)              _bko_edit "$@" ;;
        clone)             _bko_clone "$@" ;;
        approve)           _bko_approve "$@" ;;
        reject)            _bko_reject "$@" ;;
        resume)            _bko_resume "$@" ;;
        execute)           _bko_execute "$@" ;;
        archive)           _bko_archive "$@" ;;
        archive-bulk)      _bko_archive_bulk "$@" ;;
        upload)            _bko_upload "$@" ;;
        uploads)           _bko_uploads "$@" ;;
        remove-upload)     _bko_remove_upload "$@" ;;
        transfer-uploads)  _bko_transfer_uploads "$@" ;;
        --help|-h|"")
            cat <<'USAGE'
Usage: ifn bko <subcommand> [options]

Subcommands:
  list             <company_id>                List BKOs for a company
  list-all                                     List all BKOs across companies
  get              <bko_id>                    Get details of a BKO
  propose          <company_id> <json_file>    Propose a new BKO
  edit             <bko_id> <json_file>        Edit a BKO (payload, notes, reasoning)
  clone            <bko_id>                    Clone a BKO
  approve          <bko_id>                    Approve a BKO (accountant+)
  reject           <bko_id>                    Reject a BKO
  resume           <bko_id>                    Resume a paused/failed BKO execution
  execute          --data <json>               Trigger batch execution
  archive          <bko_id>                    Archive a single BKO
  archive-bulk     --data <json>               Bulk archive (ArchiveManyRequest)
  upload           <bko_id> <file_path>        Attach a file to a BKO
  uploads          <bko_id>                    List staged uploads on a BKO
  remove-upload    <bko_id> <file_id>          Remove a staged upload
  transfer-uploads --data <json>               Move uploads between BKOs

Execute / archive-bulk / transfer-uploads expect a JSON body via --data.
USAGE
            ;;
        *)
            ifn_error "unknown bko subcommand: $subcmd"
            return 1
            ;;
    esac
}

_bko_list() {
    ifn_require_arg "${1:-}" "company_id" "ifn bko list <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/bko") || return 1
    ifn_output "$result"
}

_bko_list_all() {
    local result
    result=$(ifn_get "/api/bko") || return 1
    ifn_output "$result"
}

_bko_get() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko get <bko_id>"
    local bko_id="$1"

    local result
    result=$(ifn_get "/api/bko/${bko_id}") || return 1
    ifn_output "$result"
}

_bko_propose() {
    ifn_require_arg "${1:-}" "company_id" "ifn bko propose <company_id> <json_file>"
    ifn_require_arg "${2:-}" "json_file" "ifn bko propose <company_id> <json_file>"

    local company_id="$1"
    local json_file="$2"

    if [ ! -f "$json_file" ]; then
        ifn_error "file not found: $json_file"
        return 1
    fi

    local body
    body=$(cat "$json_file")

    if ! echo "$body" | jq empty 2>/dev/null; then
        ifn_error "invalid JSON in $json_file"
        return 1
    fi

    local result
    result=$(ifn_post "/api/companies/${company_id}/bko" "$body") || return 1
    ifn_output "$result"
}

_bko_edit() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko edit <bko_id> <json_file>"
    ifn_require_arg "${2:-}" "json_file" "ifn bko edit <bko_id> <json_file>"

    local bko_id="$1"
    local json_file="$2"

    if [ ! -f "$json_file" ]; then
        ifn_error "file not found: $json_file"
        return 1
    fi

    local body
    body=$(cat "$json_file")

    local result
    result=$(ifn_patch "/api/bko/${bko_id}" "$body") || return 1
    ifn_output "$result"
}

_bko_clone() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko clone <bko_id>"
    local bko_id="$1"

    local result
    result=$(ifn_post "/api/bko/${bko_id}/clone") || return 1
    ifn_output "$result"
}

_bko_approve() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko approve <bko_id>"
    local bko_id="$1"

    local result
    result=$(ifn_post "/api/bko/${bko_id}/approve") || return 1
    ifn_output "$result"
}

_bko_reject() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko reject <bko_id>"
    local bko_id="$1"

    local result
    result=$(ifn_post "/api/bko/${bko_id}/reject") || return 1
    ifn_output "$result"
}

_bko_resume() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko resume <bko_id>"
    local bko_id="$1"

    local result
    result=$(ifn_post "/api/bko/${bko_id}/resume") || return 1
    ifn_output "$result"
}

_bko_execute() {
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
    result=$(ifn_post "/api/bko/execute" "$data") || return 1
    ifn_output "$result"
}

_bko_archive() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko archive <bko_id>"
    local bko_id="$1"

    local result
    result=$(ifn_post "/api/bko/${bko_id}/archive") || return 1
    ifn_output "$result"
}

_bko_archive_bulk() {
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
    result=$(ifn_post "/api/bko/archive" "$data") || return 1
    ifn_output "$result"
}

_bko_upload() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko upload <bko_id> <file_path>"
    ifn_require_arg "${2:-}" "file_path" "ifn bko upload <bko_id> <file_path>"

    local bko_id="$1"
    local file_path="$2"

    if [ ! -f "$file_path" ]; then
        ifn_error "file not found: $file_path"
        return 1
    fi

    local result
    result=$(ifn_upload "/api/bko/${bko_id}/upload-file" "$file_path") || return 1
    ifn_output "$result"
}

_bko_uploads() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko uploads <bko_id>"
    local bko_id="$1"

    local result
    result=$(ifn_get "/api/bko/${bko_id}/uploads") || return 1
    ifn_output "$result"
}

_bko_remove_upload() {
    ifn_require_arg "${1:-}" "bko_id" "ifn bko remove-upload <bko_id> <file_id>"
    ifn_require_arg "${2:-}" "file_id" "ifn bko remove-upload <bko_id> <file_id>"

    local bko_id="$1"
    local file_id="$2"

    local result
    result=$(ifn_delete "/api/bko/${bko_id}/uploads/${file_id}") || return 1
    ifn_output "$result"
}

_bko_transfer_uploads() {
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
    result=$(ifn_post "/api/bko/uploads/transfer" "$data") || return 1
    ifn_output "$result"
}

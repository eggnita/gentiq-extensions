#!/usr/bin/env bash
# jobs.sh — Read-only job inspection (developer endpoints)

cmd_jobs() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        sync)             _jobs_sync "$@" ;;
        sync-log)         _jobs_sync_log "$@" ;;
        list)             _jobs_list "$@" ;;
        stale)            _jobs_stale "$@" ;;
        restart-history)  _jobs_restart_history "$@" ;;
        --help|-h|"")
            echo "Usage: ifn jobs <subcommand> [options]"
            echo ""
            echo "Read-only job inspection (requires developer role)."
            echo ""
            echo "Subcommands:"
            echo "  sync            <job_id>              Sync job details"
            echo "  sync-log        <job_id>              Sync job log"
            echo "  list            <company_id> [options] List copy/purge jobs"
            echo "  stale                                  Preview stale jobs"
            echo "  restart-history [options]              Recent server restart events"
            echo ""
            echo "Options:"
            echo "  --limit <n>     Limit results"
            ;;
        *)
            ifn_error "unknown jobs subcommand: $subcmd"
            return 1
            ;;
    esac
}

_jobs_sync() {
    ifn_require_arg "${1:-}" "job_id" "ifn jobs sync <job_id>"
    local job_id="$1"

    local result
    result=$(ifn_get "/api/developer/sync-jobs/${job_id}") || return 1
    ifn_output "$result"
}

_jobs_sync_log() {
    ifn_require_arg "${1:-}" "job_id" "ifn jobs sync-log <job_id>"
    local job_id="$1"

    local result
    result=$(ifn_get "/api/developer/sync-jobs/${job_id}/log") || return 1
    ifn_output "$result"
}

_jobs_list() {
    ifn_require_arg "${1:-}" "company_id" "ifn jobs list <company_id> [--limit n]"
    local company_id="$1"
    shift

    local limit=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --limit) limit="$2"; shift 2 ;;
            *)       shift ;;
        esac
    done

    local path="/api/developer/companies/${company_id}/job-logs"
    [ -n "$limit" ] && path="${path}?limit=${limit}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

_jobs_stale() {
    local result
    result=$(ifn_get "/api/developer/syshealth/cleanup/stale-jobs") || return 1
    ifn_output "$result"
}

_jobs_restart_history() {
    local limit=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --limit) limit="$2"; shift 2 ;;
            *)       shift ;;
        esac
    done

    local path="/api/developer/syshealth/restart-history"
    [ -n "$limit" ] && path="${path}?limit=${limit}"

    local result
    result=$(ifn_get "$path") || return 1
    ifn_output "$result"
}

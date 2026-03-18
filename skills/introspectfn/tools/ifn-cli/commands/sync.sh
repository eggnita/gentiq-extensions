#!/usr/bin/env bash
# sync.sh — Sync management commands (read-only)
# Only implements assistant-level operations (API key scoped).
# Triggering a sync requires accountant+ and is not included.

cmd_sync() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        status)   _sync_status "$@" ;;
        overview) _sync_overview "$@" ;;
        years)    _sync_years "$@" ;;
        --help|-h|"")
            echo "Usage: ifn sync <subcommand> [options]"
            echo ""
            echo "Subcommands:"
            echo "  status   <conn_id>   Current sync job status"
            echo "  overview             Global sync status across all companies"
            echo "  years    <conn_id>   List financial years for a company"
            ;;
        *)
            ifn_error "unknown sync subcommand: $subcmd"
            return 1
            ;;
    esac
}

_sync_status() {
    ifn_require_arg "${1:-}" "connection_id" "ifn sync status <connection_id>"
    local conn_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/sync/status") || return 1
    ifn_output "$result"
}

_sync_overview() {
    local result
    result=$(ifn_get "/api/sync/overview") || return 1
    ifn_output "$result"
}

_sync_years() {
    ifn_require_arg "${1:-}" "connection_id" "ifn sync years <connection_id>"
    local conn_id="$1"

    local result
    result=$(ifn_get "/api/companies/${conn_id}/sync/financial-years") || return 1
    ifn_output "$result"
}

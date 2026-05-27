#!/usr/bin/env bash
# bk — Bookkeeping operations (settlements, adjustments, account mapping)
#
# Usage: ifn bk <command> <company_id> [options]
#
# Commands:
#   find               Search inbox for settlement files
#   parse              Parse a settlement file into structured JSON
#   propose            Build a bookkeeping proposal
#   discover-accounts  Discover account mapping from chart of accounts
#   mapping            Manage account mappings (show/set/confirm/reset)
#   status             Show mapping cache status
#   bq                 BigQuery queries for POS data
#   adjust             Find unsettled orders (revenue adjustments)
#   stage              Create IFN staging entries (Phase 2)

# Resolve BK_CLI directory (settlement-cli lives alongside ifn-cli)
BK_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/settlement-cli"
# Export as SETTLEMENT_CLI for backward compat with inner scripts
SETTLEMENT_CLI="$BK_CLI"
export SETTLEMENT_CLI BK_CLI

cmd_bk() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        find)
            source "${BK_CLI}/find.sh"
            settlement_find "$@"
            ;;
        parse)
            source "${BK_CLI}/parse.sh"
            settlement_parse "$@"
            ;;
        propose)
            source "${BK_CLI}/propose.sh"
            settlement_propose "$@"
            ;;
        discover-accounts)
            source "${BK_CLI}/discover.sh"
            settlement_discover "$@"
            ;;
        mapping)
            source "${BK_CLI}/mapping.sh"
            settlement_mapping "$@"
            ;;
        status)
            source "${BK_CLI}/status.sh"
            settlement_status "$@"
            ;;
        bq)
            source "${BK_CLI}/bq.sh"
            settlement_bq "$@"
            ;;
        adjust)
            source "${BK_CLI}/adjust.sh"
            settlement_adjust "$@"
            ;;
        stage)
            source "${BK_CLI}/stage.sh"
            settlement_stage "$@"
            ;;
        -h|--help|help|"")
            cat <<'USAGE'
ifn bk — Bookkeeping operations

Usage: ifn bk <command> <company_id> [options]

Commands:
  find <company_id> --partner <foodora|wolt|ubereats>
      Search inbox for settlement files

  parse <company_id> --file-id <id> --partner <partner>
      Parse a settlement file into structured JSON

  propose <company_id> --partner <partner> --file-id <ids>
      Build a bookkeeping proposal

  discover-accounts <company_id> --partner <partner>
      Discover account mapping from chart of accounts

  mapping show|set|confirm|reset <company_id> --partner <partner>
      Manage account mappings

  status
      Show mapping cache status

  bq <subcommand> [options]
      BigQuery queries for POS data

  adjust <company_id> --partner <partner> --from <date> --to <date>
      Find unsettled orders for revenue adjustments

  stage <company_id> --partner <partner> --file-id <ids>
      Create IFN staging entries (Phase 2)
USAGE
            ;;
        *)
            echo "Error: unknown bk command '$subcmd'" >&2
            echo "Run 'ifn bk --help' for usage." >&2
            return 1
            ;;
    esac
}

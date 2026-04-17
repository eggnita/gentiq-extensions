#!/usr/bin/env bash
# bq-adapter — v2 tool-invocation shim for the bq-tool CLI.
#
# The v2 runtime invokes tools with arguments in TOOL_ARGS (JSON). This shim
# reads TOOL_ARGS, maps fields to CLI flags, and exec's bq-tool.
#
# Usage from tools.json:
#   "exec": "tools/bq-adapter.sh <subcommand>"
#
# Supported subcommands (match tools.json entries):
#   health       — args: {}
#   datasets     — args: {project_id?, dataset?}     (dataset → list tables)
#   schema       — args: {table, project_id?}
#   query        — args: {sql, project_id?}
#   dry-run      — args: {sql, project_id?}

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BQ="$DIR/bq-tool"
SUBCMD="${1:?bq-adapter: missing subcommand}"
ARGS_JSON="${TOOL_ARGS:-{\}}"

# Fetch a field from TOOL_ARGS; empty string if missing/null.
_get() { printf '%s' "$ARGS_JSON" | jq -r --arg k "$1" '.[$k] // empty'; }

# Optional project_id override (exported so bq-tool picks it up).
PROJECT_ID=$(_get project_id)
[ -n "$PROJECT_ID" ] && export BQ_PROJECT_ID="$PROJECT_ID"

case "$SUBCMD" in
    health)
        exec "$BQ" --json health
        ;;
    datasets)
        DATASET=$(_get dataset)
        if [ -n "$DATASET" ]; then
            exec "$BQ" --json tables "$DATASET"
        else
            exec "$BQ" --json datasets
        fi
        ;;
    schema)
        TABLE=$(_get table)
        if [ -z "$TABLE" ]; then
            echo '{"error":"Missing required field: table"}' >&2
            exit 1
        fi
        exec "$BQ" --json schema "$TABLE"
        ;;
    query)
        SQL=$(_get sql)
        if [ -z "$SQL" ]; then
            echo '{"error":"Missing required field: sql"}' >&2
            exit 1
        fi
        exec "$BQ" --json query "$SQL"
        ;;
    dry-run)
        SQL=$(_get sql)
        if [ -z "$SQL" ]; then
            echo '{"error":"Missing required field: sql"}' >&2
            exit 1
        fi
        exec "$BQ" --json query --dry-run "$SQL"
        ;;
    *)
        echo "{\"error\":\"bq-adapter: unknown subcommand '$SUBCMD'\"}" >&2
        exit 1
        ;;
esac

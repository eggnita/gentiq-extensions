#!/usr/bin/env bash
# ifn-adapter — v2 tool-invocation shim for the ifn CLI.
#
# The v2 runtime invokes tools with arguments in TOOL_ARGS (JSON). This shim
# reads TOOL_ARGS, maps fields to CLI args, and exec's the ifn CLI.
#
# Usage from tools.json:
#   "exec": "tools/ifn-adapter.sh <subcommand>"

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
IFN="$DIR/ifn"
SUBCMD="${1:?ifn-adapter: missing subcommand}"
ARGS_JSON="${TOOL_ARGS:-{\}}"

_get() { printf '%s' "$ARGS_JSON" | jq -r --arg k "$1" '.[$k] // empty'; }
_require() {
    local v
    v=$(_get "$1")
    if [ -z "$v" ]; then
        printf '{"error":"Missing required field: %s"}\n' "$1" >&2
        exit 1
    fi
    printf '%s' "$v"
}

case "$SUBCMD" in
    health)
        exec "$IFN" --json health
        ;;
    companies)
        exec "$IFN" --json companies list
        ;;
    dashboard)
        CONN=$(_require connection_id)
        exec "$IFN" --json dashboard "$CONN"
        ;;
    browse)
        CONN=$(_require connection_id)
        RESOURCE=$(_require resource)
        ID=$(_get id)
        OPTS=$(_get options)
        # shellcheck disable=SC2086
        if [ -n "$ID" ]; then
            exec "$IFN" --json browse "$CONN" "$RESOURCE" "$ID" $OPTS
        else
            exec "$IFN" --json browse "$CONN" "$RESOURCE" $OPTS
        fi
        ;;
    records)
        CONN=$(_require connection_id)
        DOC_TYPE=$(_require doc_type)
        ID=$(_get id)
        if [ -n "$ID" ]; then
            exec "$IFN" --json records "$CONN" "$DOC_TYPE" "$ID"
        else
            exec "$IFN" --json records "$CONN" "$DOC_TYPE"
        fi
        ;;
    analysis)
        TYPE=$(_require type)
        CONN=$(_require connection_id)
        ACCOUNT=$(_get account)
        if [ -n "$ACCOUNT" ]; then
            exec "$IFN" --json analysis "$TYPE" "$CONN" "$ACCOUNT"
        else
            exec "$IFN" --json analysis "$TYPE" "$CONN"
        fi
        ;;
    staging)
        ACTION=$(_require action)
        CONN=$(_get connection_id)
        ACTION_ID=$(_get action_id)
        JSON_FILE=$(_get json_file)
        cmd=("$IFN" --json staging "$ACTION")
        [ -n "$CONN" ] && cmd+=("$CONN")
        [ -n "$ACTION_ID" ] && cmd+=("$ACTION_ID")
        [ -n "$JSON_FILE" ] && cmd+=("$JSON_FILE")
        exec "${cmd[@]}"
        ;;
    sync)
        ACTION=$(_require action)
        CONN=$(_get connection_id)
        JOB_ID=$(_get job_id)
        cmd=("$IFN" --json sync "$ACTION")
        [ -n "$CONN" ] && cmd+=("$CONN")
        [ -n "$JOB_ID" ] && cmd+=("$JOB_ID")
        exec "${cmd[@]}"
        ;;
    link)
        TYPE=$(_require type)
        CONN=$(_require connection_id)
        EXTRA=$(_get args)
        # shellcheck disable=SC2086
        exec "$IFN" --json link "$TYPE" "$CONN" $EXTRA
        ;;
    *)
        echo "{\"error\":\"ifn-adapter: unknown subcommand '$SUBCMD'\"}" >&2
        exit 1
        ;;
esac

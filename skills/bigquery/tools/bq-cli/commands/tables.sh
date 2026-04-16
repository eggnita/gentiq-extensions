#!/usr/bin/env bash
# tables.sh — List tables in a BigQuery dataset
# Usage: bq-tool tables <dataset>

cmd_tables() {
    bq_require_auth || exit 1
    bq_require_arg "${1:-}" "dataset" "bq-tool tables <dataset>"

    local dataset="$1"

    bq_debug "Listing tables in dataset: ${BQ_PROJECT_ID}:${dataset}"

    # Try cache first
    bq_cache_load
    if ! bq_cache_is_stale; then
        bq_debug "Using cached tables for ${dataset}"
        local cached
        cached=$(bq_cache_get_tables "$dataset")
        if [ -n "$cached" ] && [ "$cached" != "[]" ]; then
            if [ "$BQ_RAW_JSON" = "true" ]; then
                echo "$cached"
            else
                echo "$cached" | jq '.' 2>/dev/null || echo "$cached"
            fi
            return 0
        fi
    fi

    # Cache miss or stale — fetch from API
    local result
    result=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets/${dataset}/tables") || {
        bq_error "Failed to list tables in ${dataset}"
        exit 1
    }

    # Refresh cache in the background (for subsequent calls)
    bq_cache_refresh >/dev/null 2>&1 || true

    # Format output: extract table list
    if [ "$BQ_RAW_JSON" = "true" ]; then
        echo "$result"
    else
        echo "$result" | jq '[.tables[]? | {
            tableId: .tableReference.tableId,
            type: .type,
            numRows: (.numRows // "-"),
            numBytes: (.numBytes // "-"),
            creationTime: .creationTime
        }]' 2>/dev/null || echo "$result" | jq '.'
    fi
}

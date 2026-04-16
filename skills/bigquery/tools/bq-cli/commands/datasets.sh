#!/usr/bin/env bash
# datasets.sh — List BigQuery datasets
# Usage: bq-tool datasets

cmd_datasets() {
    bq_require_auth || exit 1

    bq_debug "Listing datasets in project: ${BQ_PROJECT_ID}"

    # Try cache first
    bq_cache_load
    if ! bq_cache_is_stale; then
        bq_debug "Using cached datasets"
        local cached
        cached=$(bq_cache_get_datasets)
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
    result=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets") || {
        bq_error "Failed to list datasets"
        exit 1
    }

    # Refresh cache in the background (for subsequent calls)
    bq_cache_refresh >/dev/null 2>&1 || true

    # Format output: extract dataset list
    if [ "$BQ_RAW_JSON" = "true" ]; then
        echo "$result"
    else
        echo "$result" | jq '[.datasets[]? | {
            datasetId: .datasetReference.datasetId,
            location: .location,
            friendlyName: (.friendlyName // "-"),
            labels: (.labels // {})
        }]' 2>/dev/null || echo "$result" | jq '.'
    fi
}

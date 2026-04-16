#!/usr/bin/env bash
# refresh.sh — Refresh the metadata cache (datasets, tables, locations)
# Usage: bq-tool refresh

cmd_refresh() {
    bq_require_auth || exit 1

    bq_debug "Refreshing metadata cache"

    if ! bq_cache_refresh; then
        jq -n '{ok: false, error: "Failed to refresh cache — check BigQuery connectivity"}'
        exit 1
    fi

    # Build summary from refreshed cache
    local ds_count tbl_count locations_summary
    ds_count=$(echo "$_BQ_CACHE" | jq '[.datasets[]?] | length' 2>/dev/null || echo "0")
    tbl_count=$(echo "$_BQ_CACHE" | jq '[.tables | to_entries[]?.value[]?] | length' 2>/dev/null || echo "0")
    locations_summary=$(echo "$_BQ_CACHE" | jq -r '[.dataset_locations | to_entries[]? | "\(.key): \(.value)"] | join(", ")' 2>/dev/null || echo "")

    jq -n \
        --argjson ok true \
        --arg message "Cache refreshed" \
        --argjson datasets "$ds_count" \
        --argjson tables "$tbl_count" \
        --arg dataset_locations "$locations_summary" \
        '{ok: $ok, message: $message, datasets: $datasets, tables: $tables, dataset_locations: $dataset_locations}'
}

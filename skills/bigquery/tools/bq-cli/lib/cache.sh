#!/usr/bin/env bash
# cache.sh — Metadata cache for BigQuery datasets, tables, and locations
#
# Cache file: ~/.config/gent-bq/cache.json
# Format:
# {
#   "cached_at": <epoch>,
#   "ttl": <seconds>,
#   "project_id": "...",
#   "datasets": [ {"datasetId": "...", "location": "...", "friendlyName": "..."} ],
#   "tables": { "dataset": [ {"tableId": "...", "type": "...", "numRows": "..."} ] },
#   "dataset_locations": { "dataset": "EU", ... }
# }

_BQ_CACHE=""

# Load cache from disk into _BQ_CACHE variable
bq_cache_load() {
    _BQ_CACHE=""
    if [ -f "$BQ_CACHE_FILE" ]; then
        _BQ_CACHE=$(cat "$BQ_CACHE_FILE" 2>/dev/null || true)
        # Validate it's proper JSON
        if ! echo "$_BQ_CACHE" | jq -e '.cached_at' >/dev/null 2>&1; then
            bq_debug "Cache file is invalid, ignoring"
            _BQ_CACHE=""
        fi
    fi
}

# Save _BQ_CACHE to disk atomically
bq_cache_save() {
    if [ -z "$_BQ_CACHE" ]; then
        return 0
    fi
    local cache_dir
    cache_dir=$(dirname "$BQ_CACHE_FILE")
    mkdir -p "$cache_dir" 2>/dev/null || true
    local tmp_file
    tmp_file=$(mktemp "${cache_dir}/cache.XXXXXX")
    echo "$_BQ_CACHE" > "$tmp_file"
    chmod 600 "$tmp_file"
    mv "$tmp_file" "$BQ_CACHE_FILE"
    bq_debug "Cache saved to ${BQ_CACHE_FILE}"
}

# Check if cache is stale (returns 0 if stale or missing, 1 if fresh)
bq_cache_is_stale() {
    if [ -z "$_BQ_CACHE" ]; then
        return 0
    fi
    local cached_at ttl now
    cached_at=$(echo "$_BQ_CACHE" | jq -r '.cached_at // 0' 2>/dev/null)
    ttl=$(echo "$_BQ_CACHE" | jq -r '.ttl // 0' 2>/dev/null)
    now=$(date +%s)

    if [ $((now - cached_at)) -ge "$ttl" ]; then
        return 0  # stale
    fi
    return 1  # fresh
}

# Fetch all datasets + tables from API and build cache
bq_cache_refresh() {
    bq_debug "Refreshing metadata cache from BigQuery API"

    local now
    now=$(date +%s)

    # Fetch all datasets
    local ds_json
    ds_json=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets" 2>/dev/null) || {
        bq_debug "Failed to fetch datasets for cache refresh"
        return 1
    }

    # Build datasets array with locations
    local datasets dataset_locations
    datasets=$(echo "$ds_json" | jq '[.datasets[]? | {
        datasetId: .datasetReference.datasetId,
        location: .location,
        friendlyName: (.friendlyName // "-")
    }]' 2>/dev/null || echo '[]')

    dataset_locations=$(echo "$ds_json" | jq '[.datasets[]?] | reduce .[] as $d ({}; . + {($d.datasetReference.datasetId): $d.location})' 2>/dev/null || echo '{}')

    # Fetch tables for each dataset
    local tables="{}"
    local dataset_ids
    dataset_ids=$(echo "$datasets" | jq -r '.[].datasetId' 2>/dev/null)

    while IFS= read -r ds_id; do
        [ -z "$ds_id" ] && continue
        bq_debug "Fetching tables for dataset: ${ds_id}"
        local tbl_json
        tbl_json=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets/${ds_id}/tables" 2>/dev/null) || continue
        local tbl_list
        tbl_list=$(echo "$tbl_json" | jq '[.tables[]? | {
            tableId: .tableReference.tableId,
            type: .type,
            numRows: (.numRows // "-")
        }]' 2>/dev/null || echo '[]')
        tables=$(echo "$tables" | jq --arg ds "$ds_id" --argjson tbls "$tbl_list" '. + {($ds): $tbls}')
    done <<< "$dataset_ids"

    # Build cache object
    _BQ_CACHE=$(jq -n \
        --argjson cached_at "$now" \
        --argjson ttl "${BQ_CACHE_TTL:-3600}" \
        --arg project_id "$BQ_PROJECT_ID" \
        --argjson datasets "$datasets" \
        --argjson tables "$tables" \
        --argjson dataset_locations "$dataset_locations" \
        '{
            cached_at: $cached_at,
            ttl: $ttl,
            project_id: $project_id,
            datasets: $datasets,
            tables: $tables,
            dataset_locations: $dataset_locations
        }')

    bq_cache_save
    return 0
}

# Load cache, auto-refresh if stale or missing
bq_cache_ensure() {
    bq_cache_load
    if bq_cache_is_stale; then
        bq_debug "Cache is stale or missing, refreshing"
        bq_cache_refresh || return 1
    fi
}

# Return cached datasets as JSON array
bq_cache_get_datasets() {
    if [ -z "$_BQ_CACHE" ]; then
        return 1
    fi
    echo "$_BQ_CACHE" | jq '.datasets // []' 2>/dev/null
}

# Return cached tables for a dataset as JSON array
bq_cache_get_tables() {
    local dataset="$1"
    if [ -z "$_BQ_CACHE" ]; then
        return 1
    fi
    echo "$_BQ_CACHE" | jq --arg ds "$dataset" '.tables[$ds] // []' 2>/dev/null
}

# Return location for a dataset, fallback to BQ_LOCATION
bq_cache_get_location() {
    local dataset="$1"
    if [ -n "$_BQ_CACHE" ]; then
        local loc
        loc=$(echo "$_BQ_CACHE" | jq -r --arg ds "$dataset" '.dataset_locations[$ds] // empty' 2>/dev/null)
        if [ -n "$loc" ]; then
            echo "$loc"
            return 0
        fi
    fi
    echo "${BQ_LOCATION:-EU}"
}

# Parse SQL for FROM/JOIN dataset.table references, look up locations,
# error if cross-region. Returns the resolved location on stdout.
bq_resolve_query_location() {
    local sql="$1"

    # Extract dataset references from FROM and JOIN clauses
    # Matches: dataset.table or `dataset.table` or `project.dataset.table`
    # We only care about the dataset part for location lookup
    local datasets_found
    datasets_found=$(echo "$sql" | \
        grep -oiE '(FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.)?([a-zA-Z0-9_-]+)\.([a-zA-Z0-9_-]+)`?' | \
        sed -E 's/(FROM|JOIN)\s+`?//i; s/`?$//' | \
        while IFS= read -r ref; do
            # Count dots to determine format
            local dot_count
            dot_count=$(echo "$ref" | tr -cd '.' | wc -c | tr -d ' ')
            if [ "$dot_count" -eq 2 ]; then
                # project.dataset.table → extract dataset (middle part)
                echo "$ref" | cut -d'.' -f2
            elif [ "$dot_count" -eq 1 ]; then
                # dataset.table → extract dataset (first part)
                echo "$ref" | cut -d'.' -f1
            fi
        done | sort -u)

    if [ -z "$datasets_found" ]; then
        # No dataset refs found — use default dataset location or BQ_LOCATION
        if [ -n "$BQ_DEFAULT_DATASET" ]; then
            bq_cache_get_location "$BQ_DEFAULT_DATASET"
        else
            echo "${BQ_LOCATION:-EU}"
        fi
        return 0
    fi

    # Look up location for each dataset
    local locations_found="" first_location="" first_dataset=""
    while IFS= read -r ds; do
        [ -z "$ds" ] && continue
        local loc
        loc=$(bq_cache_get_location "$ds")
        if [ -z "$first_location" ]; then
            first_location="$loc"
            first_dataset="$ds"
        elif [ "$loc" != "$first_location" ]; then
            echo "Error: Cross-region query detected. Dataset '${first_dataset}' is in ${first_location} but '${ds}' is in ${loc}. BigQuery cannot join data across regions." >&2
            return 1
        fi
    done <<< "$datasets_found"

    if [ -n "$first_location" ]; then
        echo "$first_location"
    else
        echo "${BQ_LOCATION:-EU}"
    fi
}

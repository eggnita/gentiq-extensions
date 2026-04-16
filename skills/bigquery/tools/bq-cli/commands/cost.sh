#!/usr/bin/env bash
# cost.sh — Show bytes processed and cost estimate for a job
# Usage: bq-tool cost <job_id>

cmd_cost() {
    bq_require_auth || exit 1
    bq_require_arg "${1:-}" "job_id" "bq-tool cost <job_id>"

    local job_id="$1"

    bq_debug "Getting cost info for job: ${job_id}"

    local result
    result=$(bq_api_get "/projects/${BQ_PROJECT_ID}/jobs/${job_id}") || {
        bq_error "Failed to get job info"
        exit 1
    }

    # Extract relevant cost fields
    local bytes_processed
    bytes_processed=$(echo "$result" | jq -r '.statistics.totalBytesProcessed // "0"' 2>/dev/null)
    local bytes_billed
    bytes_billed=$(echo "$result" | jq -r '.statistics.query.totalBytesBilled // "0"' 2>/dev/null)
    local cache_hit
    cache_hit=$(echo "$result" | jq -r '.statistics.query.cacheHit // false' 2>/dev/null)
    local slot_ms
    slot_ms=$(echo "$result" | jq -r '.statistics.totalSlotMs // "0"' 2>/dev/null)
    local state
    state=$(echo "$result" | jq -r '.status.state // "unknown"' 2>/dev/null)

    local human_processed
    human_processed=$(bq_format_bytes "$bytes_processed")
    local human_billed
    human_billed=$(bq_format_bytes "$bytes_billed")
    local cost
    cost=$(bq_estimate_cost "$bytes_billed")

    jq -n \
        --arg job_id "$job_id" \
        --arg state "$state" \
        --arg bytes_processed "$bytes_processed" \
        --arg bytes_billed "$bytes_billed" \
        --arg size_processed "$human_processed" \
        --arg size_billed "$human_billed" \
        --arg estimated_cost "\$${cost}" \
        --argjson cache_hit "$cache_hit" \
        --arg slot_ms "$slot_ms" \
        '{job_id: $job_id, state: $state, bytes_processed: $bytes_processed, bytes_billed: $bytes_billed, size_processed: $size_processed, size_billed: $size_billed, estimated_cost: $estimated_cost, cache_hit: $cache_hit, slot_ms: $slot_ms}'
}

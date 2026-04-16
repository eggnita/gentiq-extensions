#!/usr/bin/env bash
# query.sh — Run read-only SQL queries against BigQuery
# Usage: bq-tool query "<SQL>"
#        bq-tool query --dry-run "<SQL>"
#        bq-tool query --file <path>

cmd_query() {
    bq_require_auth || exit 1

    local dry_run=false
    local sql=""
    local sql_file=""

    # Parse flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|--dry_run)
                dry_run=true
                shift
                ;;
            --file|-f)
                sql_file="${2:-}"
                if [ -z "$sql_file" ]; then
                    bq_error "Missing file path after --file"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                echo "Usage: bq-tool query [--dry-run] [--file <path>] \"<SQL>\""
                exit 0
                ;;
            *)
                sql="$1"
                shift
                ;;
        esac
    done

    # Read SQL from file if specified
    if [ -n "$sql_file" ]; then
        if [ ! -f "$sql_file" ]; then
            bq_error "SQL file not found: ${sql_file}"
            exit 1
        fi
        sql=$(cat "$sql_file")
    fi

    if [ -z "$sql" ]; then
        bq_error "No SQL query provided"
        echo "Usage: bq-tool query \"SELECT ...\"" >&2
        exit 1
    fi

    # Validate query safety (SELECT only)
    bq_validate_query "$sql" || exit 1

    # Resolve query location from SQL dataset references (multi-region support)
    bq_cache_load
    local query_location
    query_location=$(bq_resolve_query_location "$sql") || {
        bq_error "$query_location"
        exit 1
    }
    bq_debug "Resolved query location: ${query_location}"

    # Build request body
    local request_body
    request_body=$(jq -n \
        --arg query "$sql" \
        --arg maxBytesBilled "$BQ_MAX_BYTES_BILLED" \
        --argjson dryRun "$dry_run" \
        --arg location "$query_location" \
        '{
            query: $query,
            useLegacySql: false,
            maximumBytesBilled: $maxBytesBilled,
            dryRun: $dryRun,
            location: $location
        }')

    # Add default dataset if set
    if [ -n "$BQ_DEFAULT_DATASET" ]; then
        request_body=$(echo "$request_body" | jq \
            --arg project "$BQ_PROJECT_ID" \
            --arg dataset "$BQ_DEFAULT_DATASET" \
            '. + {defaultDataset: {projectId: $project, datasetId: $dataset}}')
    fi

    if [ "$dry_run" = true ]; then
        bq_debug "Dry-run query: ${sql}"
    else
        bq_debug "Executing query: ${sql}"
    fi

    local result
    result=$(bq_api_post "/projects/${BQ_PROJECT_ID}/queries" "$request_body") || {
        bq_error "Query failed"
        exit 1
    }

    if [ "$dry_run" = true ]; then
        # Parse dry-run response for bytes estimate
        local bytes
        bytes=$(echo "$result" | jq -r '.totalBytesProcessed // "0"' 2>/dev/null)
        local human_bytes
        human_bytes=$(bq_format_bytes "$bytes")
        local cost
        cost=$(bq_estimate_cost "$bytes")
        jq -n \
            --arg bytes "$bytes" \
            --arg human_bytes "$human_bytes" \
            --arg estimated_cost "\$${cost}" \
            '{dry_run: true, bytes_processed: $bytes, size: $human_bytes, estimated_cost: $estimated_cost}'
    else
        if [ "$BQ_RAW_JSON" = "true" ]; then
            echo "$result"
        else
            # Extract rows and schema for readable output
            local has_rows
            has_rows=$(echo "$result" | jq -r '.rows // empty' 2>/dev/null)
            if [ -n "$has_rows" ]; then
                echo "$result" | jq '{
                    jobComplete: .jobComplete,
                    totalRows: .totalRows,
                    totalBytesProcessed: .totalBytesProcessed,
                    columns: [.schema.fields[]?.name],
                    rows: [.rows[]? | [.f[]?.v]]
                }' 2>/dev/null || echo "$result" | jq '.'
            else
                # No rows — might be a job reference or empty result
                echo "$result" | jq '{
                    jobComplete: .jobComplete,
                    totalRows: (.totalRows // "0"),
                    totalBytesProcessed: .totalBytesProcessed,
                    jobId: .jobReference.jobId
                }' 2>/dev/null || echo "$result" | jq '.'
            fi
        fi
    fi
}

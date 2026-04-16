#!/usr/bin/env bash
# preview.sh — Preview table rows
# Usage: bq-tool preview <dataset.table> [-n N]

cmd_preview() {
    bq_require_auth || exit 1
    bq_require_arg "${1:-}" "dataset.table" "bq-tool preview <dataset.table> [-n N]"

    local table_ref="$1"
    shift

    local limit=10
    local dataset table

    # Parse flags
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--limit)
                limit="${2:-10}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Parse dataset.table format
    if [[ "$table_ref" == *.* ]]; then
        dataset="${table_ref%%.*}"
        table="${table_ref#*.}"
    else
        bq_error "Table reference must be in format: dataset.table"
        exit 1
    fi

    bq_debug "Previewing ${limit} rows from: ${BQ_PROJECT_ID}:${dataset}.${table}"

    local result
    result=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets/${dataset}/tables/${table}/data?maxResults=${limit}") || {
        bq_error "Failed to preview ${table_ref}"
        exit 1
    }

    # Get schema for column names
    local schema_json
    schema_json=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets/${dataset}/tables/${table}" 2>/dev/null) || true

    if [ "$BQ_RAW_JSON" = "true" ]; then
        echo "$result"
    else
        # Combine schema field names with row data for readable output
        local fields
        fields=$(echo "$schema_json" | jq -r '[.schema.fields[]?.name]' 2>/dev/null || echo '[]')

        echo "$result" | jq --argjson fields "$fields" '{
            total_rows: .totalRows,
            rows: [.rows[]? | {
                values: [.f[]?.v]
            }],
            columns: $fields
        }' 2>/dev/null || echo "$result" | jq '.'
    fi
}

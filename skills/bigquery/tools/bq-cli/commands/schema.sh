#!/usr/bin/env bash
# schema.sh — Show/dump BigQuery table schemas
# Usage: bq-tool schema <dataset.table>
#        bq-tool schema-dump [dataset]

cmd_schema() {
    bq_require_auth || exit 1
    bq_require_arg "${1:-}" "dataset.table" "bq-tool schema <dataset.table>"

    local table_ref="$1"
    local dataset table

    # Parse dataset.table format
    if [[ "$table_ref" == *.* ]]; then
        dataset="${table_ref%%.*}"
        table="${table_ref#*.}"
    else
        bq_error "Table reference must be in format: dataset.table"
        exit 1
    fi

    bq_debug "Showing schema for: ${BQ_PROJECT_ID}:${dataset}.${table}"

    local result
    result=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets/${dataset}/tables/${table}") || {
        bq_error "Failed to get schema for ${table_ref}"
        exit 1
    }

    if [ "$BQ_RAW_JSON" = "true" ]; then
        echo "$result"
    else
        echo "$result" | jq '{
            table_id: .tableReference.tableId,
            dataset: .tableReference.datasetId,
            type: .type,
            num_rows: .numRows,
            num_bytes: .numBytes,
            creation_time: .creationTime,
            last_modified: .lastModifiedTime,
            description: (.description // null),
            time_partitioning: (.timePartitioning // null),
            clustering: (.clustering // null),
            schema: [.schema.fields[]? | {name, type, mode, description}]
        }' 2>/dev/null || echo "$result" | jq '.'
    fi
}

cmd_schema_dump() {
    bq_require_auth || exit 1

    local target_dataset="${1:-}"
    local datasets=()

    if [ -n "$target_dataset" ]; then
        datasets=("$target_dataset")
    else
        # Get all datasets
        local ds_json
        ds_json=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets") || {
            bq_error "Failed to list datasets"
            exit 1
        }
        while IFS= read -r ds; do
            [ -n "$ds" ] && datasets+=("$ds")
        done < <(echo "$ds_json" | jq -r '.datasets[]?.datasetReference.datasetId // empty' 2>/dev/null)
    fi

    if [ ${#datasets[@]} -eq 0 ]; then
        bq_error "No datasets found"
        exit 1
    fi

    local all_schemas="[]"

    for ds in "${datasets[@]}"; do
        bq_debug "Dumping schemas for dataset: ${ds}"

        local tables_json
        tables_json=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets/${ds}/tables") || continue

        while IFS= read -r table_id; do
            [ -z "$table_id" ] && continue
            local table_json
            table_json=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets/${ds}/tables/${table_id}") || continue

            local entry
            entry=$(echo "$table_json" | jq '{
                dataset: .tableReference.datasetId,
                table: .tableReference.tableId,
                type: .type,
                num_rows: .numRows,
                description: (.description // null),
                schema: [.schema.fields[]? | {name, type, mode, description}]
            }' 2>/dev/null) || continue

            all_schemas=$(echo "$all_schemas" | jq --argjson entry "$entry" '. + [$entry]')
        done < <(echo "$tables_json" | jq -r '.tables[]?.tableReference.tableId // empty' 2>/dev/null)
    done

    bq_output "$all_schemas"
}

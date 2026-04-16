#!/usr/bin/env bash
# format.sh — Output formatting helpers for BigQuery skill

# Print JSON with optional formatting
# Usage: bq_output <json>
bq_output() {
    local json="$1"
    if [ "$BQ_RAW_JSON" = "true" ]; then
        echo "$json"
    else
        echo "$json" | jq '.' 2>/dev/null || echo "$json"
    fi
}

# Print a key-value table from JSON object
# Usage: echo '{"a":"b"}' | bq_kv_table
bq_kv_table() {
    jq -r 'to_entries[] | "\(.key)\t\(.value)"' | column -t -s$'\t' 2>/dev/null || cat
}

# Print an array of objects as a table
# Usage: echo '[{...}]' | bq_table <field1> <field2> ...
bq_table() {
    local fields=("$@")
    local jq_header

    # Build header
    jq_header=$(printf '%s\t' "${fields[@]}")
    echo "$jq_header" | sed 's/\t$//' | tr '[:lower:]' '[:upper:]'

    # Build jq expression for rows
    local jq_expr
    jq_expr=$(printf '.%s // "-"\t' "${fields[@]}")
    jq_expr="[${jq_expr%\\t}] | @tsv"

    jq -r ".[] | ${jq_expr}" 2>/dev/null | head -100
}

# Format byte count to human-readable
# Usage: bq_format_bytes 1073741824
bq_format_bytes() {
    local bytes="$1"
    if [ "$bytes" -ge 1099511627776 ] 2>/dev/null; then
        echo "$(echo "scale=2; $bytes / 1099511627776" | bc) TB"
    elif [ "$bytes" -ge 1073741824 ] 2>/dev/null; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [ "$bytes" -ge 1048576 ] 2>/dev/null; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [ "$bytes" -ge 1024 ] 2>/dev/null; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} bytes"
    fi
}

# Estimate cost from bytes processed (on-demand pricing: $6.25 per TB)
# Usage: bq_estimate_cost 1073741824
bq_estimate_cost() {
    local bytes="$1"
    echo "scale=4; $bytes / 1099511627776 * 6.25" | bc 2>/dev/null || echo "N/A"
}

# Print a section header
bq_header() {
    local title="$1"
    echo ""
    echo "=== ${title} ==="
    echo ""
}

# Print an error message
bq_error() {
    echo "Error: $1" >&2
}

# Print a warning
bq_warn() {
    echo "Warning: $1" >&2
}

# Print info (only in verbose mode)
bq_debug() {
    if [ "$BQ_VERBOSE" = "true" ]; then
        echo "[debug] $1" >&2
    fi
}

# Require a positional argument or print usage and exit
# Usage: bq_require_arg "$1" "dataset.table" "bq-tool schema <dataset.table>"
bq_require_arg() {
    local value="${1:-}"
    local name="$2"
    local usage="$3"
    if [ -z "$value" ]; then
        bq_error "missing required argument: <${name}>"
        echo "Usage: ${usage}" >&2
        exit 1
    fi
}

#!/usr/bin/env bash
# format.sh — Output formatting helpers

# Print JSON with optional formatting
# Usage: ifn_output <json>
ifn_output() {
    local json="$1"
    if [ "$IFN_RAW_JSON" = "true" ]; then
        echo "$json"
    else
        echo "$json" | jq '.' 2>/dev/null || echo "$json"
    fi
}

# Print a key-value table from JSON object
# Usage: echo '{"a":"b"}' | ifn_kv_table
ifn_kv_table() {
    jq -r 'to_entries[] | "\(.key)\t\(.value)"' | column -t -s$'\t' 2>/dev/null || cat
}

# Print an array of objects as a table
# Usage: echo '[{...}]' | ifn_table <field1> <field2> ...
ifn_table() {
    local fields=("$@")
    local jq_header jq_rows

    # Build header
    jq_header=$(printf '%s\t' "${fields[@]}")
    echo "$jq_header" | sed 's/\t$//' | tr '[:lower:]' '[:upper:]'

    # Build jq expression for rows
    local jq_expr
    jq_expr=$(printf '.%s // "-"\t' "${fields[@]}")
    jq_expr="[${jq_expr%\\t}] | @tsv"

    jq -r ".[] | ${jq_expr}" 2>/dev/null | head -100
}

# Format amount with thousand separators
# Usage: ifn_amount 1234567.89
ifn_amount() {
    local amount="$1"
    printf "%'.2f" "$amount" 2>/dev/null || echo "$amount"
}

# Print a section header
ifn_header() {
    local title="$1"
    echo ""
    echo "=== ${title} ==="
    echo ""
}

# Print an error message
ifn_error() {
    echo "Error: $1" >&2
}

# Print a warning
ifn_warn() {
    echo "Warning: $1" >&2
}

# Print info (only in verbose mode)
ifn_debug() {
    if [ "$IFN_VERBOSE" = "true" ]; then
        echo "[debug] $1" >&2
    fi
}

# Split a record ID that may contain an FY segment (e.g. "FY-1/A123")
# Sets IFN_FY_SEGMENT and IFN_RECORD_ID.
# If no "/" is present, IFN_FY_SEGMENT is empty and IFN_RECORD_ID is the original.
# Usage: ifn_split_fy_path "FY-1/A123"
#        echo "$IFN_FY_SEGMENT"  # → "FY-1"
#        echo "$IFN_RECORD_ID"   # → "A123"
ifn_split_fy_path() {
    local input="$1"
    if [[ "$input" == */* ]]; then
        IFN_FY_SEGMENT="${input%%/*}"
        IFN_RECORD_ID="${input#*/}"
    else
        IFN_FY_SEGMENT=""
        IFN_RECORD_ID="$input"
    fi
    export IFN_FY_SEGMENT IFN_RECORD_ID
}

# Require a positional argument or print usage and exit
# Usage: ifn_require_arg "$1" "company_id" "ifn dashboard <company_id>"
ifn_require_arg() {
    local value="${1:-}"
    local name="$2"
    local usage="$3"
    if [ -z "$value" ]; then
        ifn_error "missing required argument: <${name}>"
        echo "Usage: ${usage}" >&2
        exit 1
    fi
}

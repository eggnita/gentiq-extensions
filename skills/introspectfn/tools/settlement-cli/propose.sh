#!/usr/bin/env bash
# settlement propose — Build bookkeeping proposal from settlement data
#
# Usage: settlement propose <company_id> --partner <partner> --file-id <id>
#
# Combines parsed settlement data + account mapping → balanced voucher proposal.
# Auto-discovers accounts if no mapping exists. Passes company_id for v2 resolution.

settlement_propose() {
    local company_id="" partner="" file_id=""

    if [ $# -lt 1 ]; then
        echo '{"error": "Usage: settlement propose <company_id> --partner <partner> --file-id <id>"}' >&2
        return 1
    fi
    company_id="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --partner)  partner="$2"; shift 2 ;;
            --file-id)  file_id="$2"; shift 2 ;;
            *)          shift ;;
        esac
    done

    if [ -z "$partner" ]; then
        echo '{"error": "--partner is required"}' >&2
        return 1
    fi
    if [ -z "$file_id" ]; then
        echo '{"error": "--file-id is required (use settlement find to discover file IDs)"}' >&2
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    # Step 1: Load or discover account mapping
    local mapping_file="${HOME}/.ifn/booking-templates/${partner}.json"

    if [ ! -f "$mapping_file" ]; then
        echo "[propose] No mapping found. Discovering accounts for ${partner}..." >&2
        source "${SETTLEMENT_CLI}/discover.sh"
        settlement_discover "$company_id" --partner "$partner" > /dev/null || {
            echo '{"error": "Failed to discover accounts"}' >&2
            return 1
        }
    fi

    if [ ! -f "$mapping_file" ]; then
        echo '{"error": "No mapping file after discovery"}' >&2
        return 1
    fi

    # Step 2: Parse settlement data
    source "${SETTLEMENT_CLI}/parse.sh"
    settlement_parse "$company_id" --file-id "$file_id" --partner "$partner" > "${tmp_dir}/parsed.json" || {
        echo '{"error": "Failed to parse settlement file"}' >&2
        return 1
    }

    # Step 3: Build proposal with company_id for v2 resolution
    cp "$mapping_file" "${tmp_dir}/mapping.json"

    python3 "${SETTLEMENT_CLI}/lib/build_proposal.py" \
        "${tmp_dir}/parsed.json" "${tmp_dir}/mapping.json" \
        --company-id "$company_id"
}

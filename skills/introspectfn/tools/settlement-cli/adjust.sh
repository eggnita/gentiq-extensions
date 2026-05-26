#!/usr/bin/env bash
# settlement adjust — Revenue adjustment finder
#
# Identifies orders booked as POS revenue but not settled by delivery partner.
#
# Usage:
#   settlement adjust <company_id> --partner <partner> --from <date> --to <date> [--venue <name>]

settlement_adjust() {
    local company_id="" partner="" from_date="" to_date="" venue=""

    if [ $# -lt 1 ]; then
        echo '{"error": "Usage: settlement adjust <company_id> --partner <partner> --from <date> --to <date>"}' >&2
        return 1
    fi
    company_id="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --partner) partner="$2"; shift 2 ;;
            --from)    from_date="$2"; shift 2 ;;
            --to)      to_date="$2"; shift 2 ;;
            --venue)   venue="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done

    if [ -z "$partner" ] || [ -z "$from_date" ] || [ -z "$to_date" ]; then
        echo '{"error": "--partner, --from, --to are required"}' >&2
        return 1
    fi

    # If venue not provided, try to derive from IFN company name
    if [ -z "$venue" ]; then
        local company_info
        company_info=$(ifn_get "/api/companies/${company_id}/dashboard" 2>/dev/null)
        venue=$(echo "$company_info" | jq -r '.company_name // empty' 2>/dev/null | sed 's/Brödernas //' | sed 's/ AB$//')
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    source "${SETTLEMENT_CLI}/bq.sh"

    case "$partner" in
        foodora)
            # Get POS orders and cancelled orders, write to temp files
            _bq_pos_orders --venue "$venue" --partner foodora --from "$from_date" --to "$to_date" > "${tmp_dir}/pos.json" || {
                echo '{"error": "Failed to query POS orders"}' >&2; return 1
            }
            _bq_cancelled --partner foodora --venue "$venue" --from "$from_date" --to "$to_date" > "${tmp_dir}/cancelled.json" || {
                echo '{"error": "Failed to query cancelled orders"}' >&2; return 1
            }
            # Ensure valid JSON (empty result → empty array)
            [ -s "${tmp_dir}/pos.json" ] || echo '[]' > "${tmp_dir}/pos.json"
            [ -s "${tmp_dir}/cancelled.json" ] || echo '[]' > "${tmp_dir}/cancelled.json"

            python3 "${SETTLEMENT_CLI}/lib/build_adjustment.py" \
                "${tmp_dir}/pos.json" "${tmp_dir}/cancelled.json" \
                --partner foodora --venue "$venue" --from-date "$from_date" --to-date "$to_date"
            ;;
        wolt|ubereats)
            # Use daily totals + Deliverect cancellation data
            _bq_daily_totals --venue "$venue" --partner "$partner" --from "$from_date" --to "$to_date" > "${tmp_dir}/pos_daily.json" || {
                echo '{"error": "Failed to query POS daily totals"}' >&2; return 1
            }
            _bq_cancelled --partner "$partner" --venue "$venue" --from "$from_date" --to "$to_date" > "${tmp_dir}/cancelled.json" || {
                echo '{"error": "Failed to query cancelled orders"}' >&2; return 1
            }
            [ -s "${tmp_dir}/pos_daily.json" ] || echo '[]' > "${tmp_dir}/pos_daily.json"
            [ -s "${tmp_dir}/cancelled.json" ] || echo '[]' > "${tmp_dir}/cancelled.json"

            python3 "${SETTLEMENT_CLI}/lib/build_adjustment.py" \
                "${tmp_dir}/pos_daily.json" "${tmp_dir}/cancelled.json" \
                --partner "$partner" --venue "$venue" --from-date "$from_date" --to-date "$to_date" --fuzzy
            ;;
        *)
            echo "{\"error\": \"Unknown partner: $partner\"}" >&2
            return 1
            ;;
    esac
}

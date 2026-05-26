#!/usr/bin/env bash
# settlement bq — BigQuery queries for POS and delivery partner data
#
# Usage:
#   settlement bq pos-orders --venue <name> --partner <foodora|wolt|ubereats> --from <date> --to <date>
#   settlement bq cancelled --partner <foodora> --store <id> --from <date> --to <date>
#   settlement bq daily-totals --venue <name> --partner <partner> --from <date> --to <date>
#
# Requires: gcloud/bq CLI with access to bigbrotherprod project

BQ_PROJECT="bigbrotherprod"

settlement_bq() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    if ! command -v bq >/dev/null 2>&1; then
        echo '{"error": "bq CLI not found. Install Google Cloud SDK."}' >&2
        return 1
    fi

    case "$subcmd" in
        pos-orders)    _bq_pos_orders "$@" ;;
        cancelled)     _bq_cancelled "$@" ;;
        daily-totals)  _bq_daily_totals "$@" ;;
        *)
            echo '{"error": "Usage: settlement bq <pos-orders|cancelled|daily-totals> [options]"}' >&2
            return 1
            ;;
    esac
}

_parse_bq_args() {
    # Parse common args into global vars
    BQ_VENUE="" BQ_PARTNER="" BQ_FROM="" BQ_TO="" BQ_STORE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --venue)   BQ_VENUE="$2"; shift 2 ;;
            --partner) BQ_PARTNER="$2"; shift 2 ;;
            --from)    BQ_FROM="$2"; shift 2 ;;
            --to)      BQ_TO="$2"; shift 2 ;;
            --store)   BQ_STORE="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done
}

_sanitize_bq() {
    # Remove characters that could be used for SQL injection
    # Allow: alphanumeric, spaces, hyphens, dots, underscores, åäö
    echo "$1" | sed 's/[^a-zA-Z0-9 _.åäöÅÄÖ-]//g'
}

_bq_payment_method() {
    # Map partner name to Baemingo paymentMethod
    case "$1" in
        foodora)  echo "FOODORA" ;;
        wolt)     echo "WOLT" ;;
        ubereats) echo "UBER_EATS" ;;
        *)        echo "$1" ;;
    esac
}

_bq_pos_orders() {
    _parse_bq_args "$@"
    local payment_method
    payment_method=$(_bq_payment_method "$BQ_PARTNER")

    if [ -z "$BQ_VENUE" ] || [ -z "$BQ_PARTNER" ] || [ -z "$BQ_FROM" ] || [ -z "$BQ_TO" ]; then
        echo '{"error": "--venue, --partner, --from, --to are all required"}' >&2
        return 1
    fi

    local safe_venue safe_from safe_to safe_method
    safe_venue=$(_sanitize_bq "$BQ_VENUE")
    safe_from=$(_sanitize_bq "$BQ_FROM")
    safe_to=$(_sanitize_bq "$BQ_TO")
    safe_method=$(_sanitize_bq "$payment_method")

    bq query --use_legacy_sql=false --format=json --max_rows=1000 "
        SELECT
            id,
            date,
            intAmount / 100.0 AS amount_sek,
            intAmountAfterDiscounts / 100.0 AS amount_after_discounts_sek,
            paymentMethod,
            venueName,
            easyId,
            basketToken
        FROM \`${BQ_PROJECT}.baemingo.orders\`
        WHERE origin = 'THIRD_PARTY'
          AND paymentMethod = '${safe_method}'
          AND venueName LIKE '%${safe_venue}%'
          AND date BETWEEN '${safe_from}' AND '${safe_to}T23:59:59'
        ORDER BY date
    " 2>/dev/null
}

_bq_cancelled() {
    _parse_bq_args "$@"

    if [ -z "$BQ_PARTNER" ] || [ -z "$BQ_FROM" ] || [ -z "$BQ_TO" ]; then
        echo '{"error": "--partner, --from, --to are required"}' >&2
        return 1
    fi

    case "$BQ_PARTNER" in
        foodora)
            local store_filter="" venue_filter=""
            if [ -n "$BQ_STORE" ]; then
                local safe_store=$(_sanitize_bq "$BQ_STORE")
                store_filter="AND store_id = '${safe_store}'"
            fi
            if [ -n "$BQ_VENUE" ]; then
                local safe_venue=$(_sanitize_bq "$BQ_VENUE")
                venue_filter="AND restaurant_name LIKE '%${safe_venue}%'"
            fi

            local safe_from=$(_sanitize_bq "$BQ_FROM")
            local safe_to=$(_sanitize_bq "$BQ_TO")

            bq query --use_legacy_sql=false --format=json --max_rows=1000 "
                SELECT
                    order_id,
                    store_id,
                    restaurant_name,
                    order_status,
                    cancellation_owner,
                    cancellation_reason,
                    order_received_at,
                    cancelled_at,
                    subtotal,
                    commission
                FROM \`${BQ_PROJECT}.delivery_data.foodora_orders\`
                WHERE order_status = 'Cancelled'
                  AND order_received_at BETWEEN '${safe_from}' AND '${safe_to}T23:59:59'
                  ${store_filter}
                  ${venue_filter}
                ORDER BY order_received_at
            " 2>/dev/null
            ;;
        wolt|ubereats)
            local channel
            case "$BQ_PARTNER" in
                wolt)     channel="Wolt" ;;
                ubereats) channel="Uber Eats" ;;
            esac
            local location_filter=""
            if [ -n "$BQ_VENUE" ]; then
                local safe_venue=$(_sanitize_bq "$BQ_VENUE")
                location_filter="AND location LIKE '%${safe_venue}%'"
            fi

            local safe_channel=$(_sanitize_bq "$channel")
            local safe_from=$(_sanitize_bq "$BQ_FROM")
            local safe_to=$(_sanitize_bq "$BQ_TO")

            bq query --use_legacy_sql=false --format=json --max_rows=1000 "
                SELECT
                    channel_order_id,
                    order_id,
                    channel,
                    status,
                    location,
                    created_time_utc,
                    payment_amount,
                    subtotal
                FROM \`${BQ_PROJECT}.delivery_data.deliverect_orders\`
                WHERE channel = '${safe_channel}'
                  AND status = 'CANCELLED'
                  AND created_time_utc BETWEEN '${safe_from}' AND '${safe_to}T23:59:59'
                  ${location_filter}
                ORDER BY created_time_utc
            " 2>/dev/null
            ;;
    esac
}

_bq_daily_totals() {
    _parse_bq_args "$@"
    local payment_method
    payment_method=$(_bq_payment_method "$BQ_PARTNER")

    if [ -z "$BQ_VENUE" ] || [ -z "$BQ_PARTNER" ] || [ -z "$BQ_FROM" ] || [ -z "$BQ_TO" ]; then
        echo '{"error": "--venue, --partner, --from, --to are all required"}' >&2
        return 1
    fi

    local safe_venue safe_from safe_to safe_method
    safe_venue=$(_sanitize_bq "$BQ_VENUE")
    safe_from=$(_sanitize_bq "$BQ_FROM")
    safe_to=$(_sanitize_bq "$BQ_TO")
    safe_method=$(_sanitize_bq "$payment_method")

    bq query --use_legacy_sql=false --format=json "
        SELECT
            DATE(date) AS order_date,
            COUNT(*) AS order_count,
            SUM(intAmountAfterDiscounts) / 100.0 AS total_amount_sek
        FROM \`${BQ_PROJECT}.baemingo.orders\`
        WHERE origin = 'THIRD_PARTY'
          AND paymentMethod = '${safe_method}'
          AND venueName LIKE '%${safe_venue}%'
          AND date BETWEEN '${safe_from}' AND '${safe_to}T23:59:59'
        GROUP BY order_date
        ORDER BY order_date
    " 2>/dev/null
}

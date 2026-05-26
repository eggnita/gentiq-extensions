#!/usr/bin/env bash
# settlement stage — Create IFN staging entries from proposals (Phase 2)
#
# Usage:
#   settlement stage <company_id> --partner <partner> --file-id <id>
#   settlement stage <company_id> --adjustment --partner <partner> --from <date> --to <date>

settlement_stage() {
    local company_id="" partner="" file_id="" is_adjustment=false
    local from_date="" to_date="" venue=""

    if [ $# -lt 1 ]; then
        echo '{"error": "Usage: settlement stage <company_id> --partner <partner> --file-id <id>"}' >&2
        return 1
    fi
    company_id="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --partner)    partner="$2"; shift 2 ;;
            --file-id)    file_id="$2"; shift 2 ;;
            --adjustment) is_adjustment=true; shift ;;
            --from)       from_date="$2"; shift 2 ;;
            --to)         to_date="$2"; shift 2 ;;
            --venue)      venue="$2"; shift 2 ;;
            *)            shift ;;
        esac
    done

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    if [ "$is_adjustment" = true ]; then
        _stage_adjustment "$company_id" "$partner" "$from_date" "$to_date" "$venue" "$tmp_dir"
    elif [ -n "$file_id" ] && [ -n "$partner" ]; then
        _stage_settlement "$company_id" "$partner" "$file_id" "$tmp_dir"
    else
        echo '{"error": "Provide --partner + --file-id, or --adjustment + --partner + --from + --to"}' >&2
        return 1
    fi
}

_stage_settlement() {
    local company_id="$1" partner="$2" file_id="$3" tmp_dir="$4"

    # Step 1: Generate proposal
    source "${SETTLEMENT_CLI}/propose.sh"
    settlement_propose "$company_id" --partner "$partner" --file-id "$file_id" > "${tmp_dir}/proposal.json" || {
        echo '{"error": "Failed to generate proposal"}' >&2
        return 1
    }

    # Step 2: Get financial year
    local fy_id=""
    local fy_response
    fy_response=$(ifn_get "/api/companies/${company_id}/sync/financial-years" 2>/dev/null) || true
    fy_id=$(echo "$fy_response" | jq -r '.financial_years[0].external_id // .FinancialYears[-1].Id // empty' 2>/dev/null)

    # Step 3: Upload PDF attachment
    local file_ref=""
    local pdf_id
    # Extract PDF file ID (second in comma-separated list for Foodora, first for others)
    IFS=',' read -ra ids <<< "$file_id"
    case "$partner" in
        foodora) pdf_id="${ids[1]:-}" ;;  # Second ID is the PDF
        *)       pdf_id="${ids[0]:-}" ;;
    esac

    if [ -n "$pdf_id" ]; then
        ifn_get_binary "/api/companies/${company_id}/inbox/file/${pdf_id}" > "${tmp_dir}/attachment.pdf" 2>/dev/null
        if [ -s "${tmp_dir}/attachment.pdf" ]; then
            local upload_response
            upload_response=$(ifn_upload "/api/companies/${company_id}/bk-staging/upload-file" "${tmp_dir}/attachment.pdf" 2>/dev/null) || true
            file_ref=$(echo "$upload_response" | jq -r '.id // empty' 2>/dev/null)
        fi
    fi

    # Step 4: Build staging payload
    local stage_args=(--fy-id "${fy_id}")
    [ -n "$file_ref" ] && stage_args+=(--file-ref "$file_ref")

    python3 "${SETTLEMENT_CLI}/lib/build_staging_payload.py" \
        "${tmp_dir}/proposal.json" "${stage_args[@]}" > "${tmp_dir}/payload.json" || {
        echo '{"error": "Failed to build staging payload"}' >&2
        return 1
    }

    # Step 5: Submit to IFN staging
    local payload
    payload=$(cat "${tmp_dir}/payload.json")
    local staging_response
    staging_response=$(ifn_post "/api/companies/${company_id}/bk-staging" "$payload") || {
        echo '{"error": "Failed to create staging entry"}' >&2
        return 1
    }

    # Step 6: Output result
    local action_id
    action_id=$(echo "$staging_response" | jq -r '.id // empty')
    jq -n --arg id "$action_id" --arg partner "$partner" --arg link "${IFN_WEB_URL:-${IFN_BASE_URL}}/staging/${company_id}/${action_id}" \
        '{"status": "staged", "action_id": $id, "partner": $partner, "deep_link": $link, "message": "Settlement staged for review."}'
}

_stage_adjustment() {
    local company_id="$1" partner="$2" from_date="$3" to_date="$4" venue="$5" tmp_dir="$6"

    if [ -z "$partner" ] || [ -z "$from_date" ] || [ -z "$to_date" ]; then
        echo '{"error": "--partner, --from, --to required for adjustments"}' >&2
        return 1
    fi

    # Step 1: Get adjustment data
    source "${SETTLEMENT_CLI}/adjust.sh"
    settlement_adjust "$company_id" --partner "$partner" --from "$from_date" --to "$to_date" \
        ${venue:+--venue "$venue"} > "${tmp_dir}/adjustment.json" || {
        echo '{"error": "Failed to compute adjustments"}' >&2
        return 1
    }

    local total_adjustment
    total_adjustment=$(jq -r '.total_adjustment_amount // 0' "${tmp_dir}/adjustment.json")
    if [ "$total_adjustment" = "0" ] || [ "$total_adjustment" = "0.0" ]; then
        echo '{"status": "no_adjustment_needed", "message": "No cancelled/unsettled orders found"}'
        return 0
    fi

    # Step 2: Generate support document
    python3 "${SETTLEMENT_CLI}/lib/build_support_doc.py" "${tmp_dir}/adjustment.json" \
        > "${tmp_dir}/support_document.md"

    # Step 3: Upload support document
    local file_ref=""
    local upload_response
    upload_response=$(ifn_upload "/api/companies/${company_id}/bk-staging/upload-file" "${tmp_dir}/support_document.md" 2>/dev/null) || true
    file_ref=$(echo "$upload_response" | jq -r '.id // empty' 2>/dev/null)

    # Step 4: Get financial year and template
    local fy_id=""
    local fy_response
    fy_response=$(ifn_get "/api/companies/${company_id}/sync/financial-years" 2>/dev/null) || true
    fy_id=$(echo "$fy_response" | jq -r '.financial_years[0].external_id // .FinancialYears[-1].Id // empty' 2>/dev/null)

    local template_file="${HOME}/.ifn/booking-templates/${partner}.json"
    local correction_acct=3083 receivable_acct=1584
    if [ -f "$template_file" ]; then
        correction_acct=$(jq -r '.mapping.correction_6.account // 3083' "$template_file")
        receivable_acct=$(jq -r '.mapping.receivable_clear.account // .receivable_account // 1584' "$template_file")
    fi

    # Step 5: Build correction voucher payload
    local correction_args=(
        "${tmp_dir}/adjustment.json"
        --correction-acct "$correction_acct"
        --receivable-acct "$receivable_acct"
    )
    [ -n "$fy_id" ] && correction_args+=(--fy-id "$fy_id")
    [ -n "$file_ref" ] && correction_args+=(--file-ref "$file_ref")

    python3 "${SETTLEMENT_CLI}/lib/build_correction_payload.py" \
        "${correction_args[@]}" > "${tmp_dir}/adj_payload.json"

    # Step 6: Submit to staging
    local staging_response
    staging_response=$(ifn_post "/api/companies/${company_id}/bk-staging" "$(cat "${tmp_dir}/adj_payload.json")") || {
        echo '{"error": "Failed to stage adjustment"}' >&2
        return 1
    }

    local action_id
    action_id=$(echo "$staging_response" | jq -r '.id // empty')
    jq -n --arg id "$action_id" --arg partner "$partner" \
        --argjson total "$total_adjustment" \
        --argjson cancelled "$(jq '.total_cancelled_orders' "${tmp_dir}/adjustment.json")" \
        --arg link "${IFN_WEB_URL:-${IFN_BASE_URL}}/staging/${company_id}/${action_id}" \
        '{"status": "staged", "action_id": $id, "partner": $partner, "total_adjustment": $total, "cancelled_orders": $cancelled, "deep_link": $link, "message": "Revenue adjustment staged with support document."}'
}

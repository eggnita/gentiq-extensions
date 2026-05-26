#!/usr/bin/env bash
# settlement parse — Parse settlement files into structured JSON
#
# Usage:
#   settlement parse <company_id> --file-id <id> --partner <partner>
#
# For Foodora: file_id is comma-separated: xls_id,pdf_id
# For Wolt: file_id is comma-separated: payout_id,sales_id,commission_id
# For Uber Eats: file_id is a single PDF id

settlement_parse() {
    local company_id="" partner="" file_id=""

    if [ $# -lt 1 ]; then
        echo '{"error": "Usage: settlement parse <company_id> --file-id <id> --partner <partner>"}' >&2
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

    if [ -z "$partner" ] || [ -z "$file_id" ]; then
        echo '{"error": "--partner and --file-id are required"}' >&2
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    case "$partner" in
        foodora)
            # file_id = xls_id,pdf_id
            IFS=',' read -ra ids <<< "$file_id"
            if [ ${#ids[@]} -lt 2 ]; then
                echo '{"error": "Foodora requires 2 file IDs: --file-id xls_id,pdf_id"}' >&2
                return 1
            fi
            ifn_get_binary "/api/companies/${company_id}/inbox/file/${ids[0]}" > "${tmp_dir}/settlement.xls"
            ifn_get_binary "/api/companies/${company_id}/inbox/file/${ids[1]}" > "${tmp_dir}/settlement.pdf"

            # Parse both files
            python3 "${HOME}/.ifn/parsers/parse_foodora_xls.py" "${tmp_dir}/settlement.xls" > "${tmp_dir}/xls.json" || {
                echo '{"error": "XLS parsing failed"}' >&2; return 1
            }
            python3 "${HOME}/.ifn/parsers/parse_foodora_pdf.py" "${tmp_dir}/settlement.pdf" > "${tmp_dir}/pdf.json" || {
                echo '{"error": "PDF parsing failed"}' >&2; return 1
            }

            # Merge: XLS has order-level data, PDF has settlement summary
            python3 "${SETTLEMENT_CLI}/lib/merge_foodora.py" "${tmp_dir}/xls.json" "${tmp_dir}/pdf.json"
            ;;
        wolt)
            IFS=',' read -ra ids <<< "$file_id"
            if [ ${#ids[@]} -ne 3 ]; then
                echo '{"error": "Wolt requires 3 file IDs: --file-id payout_id,sales_id,commission_id"}' >&2
                return 1
            fi
            ifn_get_binary "/api/companies/${company_id}/inbox/file/${ids[0]}" > "${tmp_dir}/payout.pdf"
            ifn_get_binary "/api/companies/${company_id}/inbox/file/${ids[1]}" > "${tmp_dir}/sales.pdf"
            ifn_get_binary "/api/companies/${company_id}/inbox/file/${ids[2]}" > "${tmp_dir}/commission.pdf"
            python3 "${HOME}/.ifn/parsers/parse_wolt.py" "${tmp_dir}/payout.pdf" "${tmp_dir}/sales.pdf" "${tmp_dir}/commission.pdf"
            ;;
        ubereats)
            ifn_get_binary "/api/companies/${company_id}/inbox/file/${file_id}" > "${tmp_dir}/settlement.pdf"
            python3 "${HOME}/.ifn/parsers/parse_ubereats.py" "${tmp_dir}/settlement.pdf"
            ;;
        *)
            echo "{\"error\": \"Unknown partner: $partner\"}" >&2
            return 1
            ;;
    esac
}

#!/usr/bin/env bash
# settlement learn — Learn booking template from historical vouchers
#
# Usage: settlement learn <company_id> --partner <partner>
#
# Discovers account mapping by analyzing historical vouchers on
# partner receivable accounts. Saves template to ~/.ifn/booking-templates/

settlement_learn() {
    local company_id="" partner=""

    if [ $# -lt 1 ]; then
        echo '{"error": "Usage: settlement learn <company_id> --partner <partner>"}' >&2
        return 1
    fi
    company_id="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --partner) partner="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done

    if [ -z "$partner" ]; then
        echo '{"error": "--partner is required (foodora, wolt, or ubereats)"}' >&2
        return 1
    fi

    # Step 1: Find the partner's receivable account
    local accounts_response
    accounts_response=$(ifn_get "/api/companies/${company_id}/internal/accounts?page=1&limit=500&active=true") || {
        echo '{"error": "Failed to fetch accounts"}' >&2
        return 1
    }

    local partner_account
    partner_account=$(_find_partner_account "$partner" "$accounts_response") || {
        echo "{\"error\": \"Could not find receivable account for $partner\"}" >&2
        return 1
    }

    echo "[learn] Found receivable account: $partner_account" >&2

    # Step 2: Get financial year ID
    local fy_response
    fy_response=$(ifn_get "/api/companies/${company_id}/sync/financial-years") || {
        echo '{"error": "Failed to fetch financial years"}' >&2
        return 1
    }

    local fy_id
    fy_id=$(echo "$fy_response" | jq -r '.financial_years[0].external_id // .FinancialYears[-1].Id // empty')
    if [ -z "$fy_id" ]; then
        echo '{"error": "No financial years found"}' >&2
        return 1
    fi

    # Step 3: Get vouchers on the partner receivable account
    local analysis_response
    analysis_response=$(ifn_get "/api/companies/${company_id}/internal/account-analysis?account=${partner_account}&financial_year_id=${fy_id}&limit=50") || {
        echo '{"error": "Failed to fetch account analysis"}' >&2
        return 1
    }

    # Step 4: Extract recent settlement vouchers and their row structure
    # Get the 3 most recent vouchers that touch this account
    local voucher_refs
    voucher_refs=$(echo "$analysis_response" | jq -r '
        [.vouchers // [] | sort_by(.TransactionDate) | reverse | .[0:3] |
         .[] | "\(.VoucherSeries)\(.VoucherNumber)_FY\(.Year // "")"]
        | join(",")
    ')

    if [ -z "$voucher_refs" ] || [ "$voucher_refs" = "" ]; then
        echo "[learn] No vouchers found on account $partner_account — falling back to account description matching" >&2
        _learn_from_accounts "$partner" "$company_id" "$accounts_response"
        return $?
    fi

    # Step 5: Fetch full voucher details for pattern analysis
    local vouchers_json="[]"
    IFS=',' read -ra refs <<< "$voucher_refs"
    for ref in "${refs[@]}"; do
        local series="${ref%%[0-9]*}"
        local rest="${ref#$series}"
        local number="${rest%%_*}"
        local fy_part="${rest#*_FY}"

        local voucher_detail
        voucher_detail=$(ifn_get "/api/companies/${company_id}/internal/vouchers/FY-${fy_id}/${series}${number}" 2>/dev/null) || continue

        vouchers_json=$(echo "$vouchers_json" | jq --argjson v "$voucher_detail" '. + [$v]')
    done

    # Step 6: Analyze voucher patterns and create template
    _build_template "$partner" "$company_id" "$partner_account" "$vouchers_json" "$accounts_response"
}

_find_partner_account() {
    local partner="$1"
    local accounts_json="$2"

    # Search for account with partner name in description
    local search_term
    case "$partner" in
        foodora)  search_term="Foodora" ;;
        wolt)     search_term="Wolt" ;;
        ubereats) search_term="Uber" ;;
    esac

    # Look for dedicated receivable accounts (15xx range)
    local account
    account=$(echo "$accounts_json" | jq -r --arg term "$search_term" '
        .Accounts // [] |
        map(select(.Number >= 1500 and .Number < 1600 and (.Description | test($term; "i")))) |
        .[0].Number // empty
    ')

    if [ -n "$account" ]; then
        echo "$account"
        return 0
    fi

    echo "" >&2
    return 1
}

_learn_from_accounts() {
    local partner="$1"
    local company_id="$2"
    local accounts_json="$3"

    # Fallback: build a template purely from account descriptions
    # Find accounts that mention the partner name
    local template
    template=$(echo "$accounts_json" | python3 -c "
import json, sys, re
from datetime import datetime

partner = '${partner}'
data = json.load(sys.stdin)
accounts = data.get('Accounts', [])

search_terms = {
    'foodora': ['Foodora', 'foodora'],
    'wolt': ['Wolt', 'wolt'],
    'ubereats': ['Uber', 'uber'],
}
terms = search_terms.get(partner, [partner])

# Find partner-related accounts
partner_accounts = {}
for a in accounts:
    desc = a.get('Description', '')
    num = a.get('Number', 0)
    for term in terms:
        if term.lower() in desc.lower():
            if 1500 <= num < 1600:
                partner_accounts['receivable'] = {'account': num, 'side': 'credit', 'description': desc}
            elif 3000 <= num < 3100:
                vat_code = a.get('VATCode', '')
                if '6' in desc or 'MP3' == vat_code:
                    partner_accounts['revenue_6'] = {'account': num, 'side': 'credit', 'description': desc}
                elif '12' in desc or 'MP2' == vat_code:
                    partner_accounts['revenue_12'] = {'account': num, 'side': 'credit', 'description': desc}
            elif 6000 <= num < 7000:
                partner_accounts['fees'] = {'account': num, 'side': 'debit', 'description': desc}

# Add common accounts
for a in accounts:
    num = a.get('Number', 0)
    desc = a.get('Description', '')
    if num == 1930:
        partner_accounts['bank'] = {'account': num, 'side': 'debit', 'description': desc}
    elif num == 2640:
        partner_accounts['input_vat'] = {'account': num, 'side': 'debit', 'description': desc}
    elif num == 2630:
        partner_accounts['output_vat_6'] = {'account': num, 'side': 'credit', 'description': desc}
    elif num == 3740:
        partner_accounts['rounding'] = {'account': num, 'side': 'debit', 'description': desc}

# Find correction accounts (308x)
for a in accounts:
    num = a.get('Number', 0)
    desc = a.get('Description', '')
    if 3080 <= num <= 3089 and 'orrigering' in desc.lower():
        vat_code = a.get('VATCode', '')
        if 'MP3' == vat_code or '6%' in desc:
            partner_accounts['correction_6'] = {'account': num, 'side': 'debit', 'description': desc}
        elif 'MP2' == vat_code or '12%' in desc:
            partner_accounts['correction_12'] = {'account': num, 'side': 'debit', 'description': desc}
        elif 'MP1' == vat_code or '25%' in desc:
            partner_accounts['correction_25'] = {'account': num, 'side': 'debit', 'description': desc}

mapping = {}
for key, val in partner_accounts.items():
    mapping[key] = {
        'account': val['account'],
        'side': val['side'],
        'description_template': val['description'] + ' {period}',
    }

template = {
    'partner': partner,
    'connection_id': '${company_id}',
    'learned_from_vouchers': [],
    'learned_at': datetime.utcnow().isoformat() + 'Z',
    'ttl_days': 90,
    'source': 'account_descriptions',
    'mapping': mapping,
}
print(json.dumps(template, indent=2))
")

    local template_dir="${HOME}/.ifn/booking-templates"
    mkdir -p "$template_dir"
    echo "$template" > "${template_dir}/${partner}.json"
    echo "$template"
}

_build_template() {
    local partner="$1"
    local company_id="$2"
    local partner_account="$3"
    local vouchers_json="$4"
    local accounts_json="$5"

    # Write data to temp files for safe Python processing
    local tmp_dir
    tmp_dir=$(mktemp -d)

    echo "$vouchers_json" > "${tmp_dir}/vouchers.json"
    echo "$accounts_json" > "${tmp_dir}/accounts.json"

    local template
    template=$(python3 "${SETTLEMENT_CLI}/lib/build_template.py" \
        "${tmp_dir}/vouchers.json" "${tmp_dir}/accounts.json" \
        --partner "$partner" --conn-id "$company_id" --account "$partner_account")

    rm -rf "$tmp_dir"

    if [ -z "$template" ]; then
        echo '{"error": "Failed to build template from voucher analysis"}' >&2
        return 1
    fi

    local template_dir="${HOME}/.ifn/booking-templates"
    mkdir -p "$template_dir"
    echo "$template" > "${template_dir}/${partner}.json"
    echo "$template"
}

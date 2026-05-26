#!/usr/bin/env bash
# settlement find — Search inbox for delivery partner settlement files
#
# Usage: settlement find <company_id> --partner <foodora|wolt|ubereats> [--limit <n>]
#
# Output: JSON array of settlement file groups

settlement_find() {
    local company_id="" partner="" limit=100

    # Parse args
    if [ $# -lt 1 ]; then
        echo '{"error": "Usage: settlement find <company_id> --partner <foodora|wolt|ubereats>"}' >&2
        return 1
    fi
    company_id="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --partner) partner="$2"; shift 2 ;;
            --limit)   limit="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done

    if [ -z "$partner" ]; then
        echo '{"error": "--partner is required (foodora, wolt, or ubereats)"}' >&2
        return 1
    fi

    # Map partner to search term
    local search_term
    case "$partner" in
        foodora)  search_term="foodora" ;;
        wolt)     search_term="wolt" ;;
        ubereats) search_term="uber" ;;
        *)
            echo "{\"error\": \"Unknown partner: $partner\"}" >&2
            return 1
            ;;
    esac

    # Query IFN inbox API
    local api_path="/api/companies/${company_id}/internal/inbox?page=1&limit=${limit}&search=${search_term}"
    local response
    response=$(ifn_get "$api_path") || {
        echo "{\"error\": \"Failed to query inbox: $response\"}" >&2
        return 1
    }

    # Dispatch to partner-specific grouping logic
    case "$partner" in
        foodora)  _find_foodora "$response" ;;
        wolt)     _find_wolt "$response" ;;
        ubereats) _find_ubereats "$response" ;;
    esac
}

_find_foodora() {
    local response="$1"
    # Group XLS + PDF pairs by invoice number
    # XLS: invoice-<number>.XLS
    # PDF: Faktureringsdokument - <number>.pdf
    echo "$response" | python3 -c "
import json, sys, re

data = json.load(sys.stdin)
files = data.get('files', [])

# Index by invoice number
groups = {}
for f in files:
    name = f.get('Name', '')
    # XLS: invoice-7002651526.XLS
    m = re.match(r'invoice-(\d+)\.xls', name, re.IGNORECASE)
    if m:
        num = m.group(1)
        groups.setdefault(num, {'invoice_number': num, 'xls': None, 'pdf': None, 'period': None})
        groups[num]['xls'] = {'id': f['Id'], 'name': name, 'size': f.get('Size', 0)}
        continue
    # PDF: Faktureringsdokument - 7002651526.pdf
    m = re.match(r'Faktureringsdokument\s*-\s*(\d+)\.pdf', name, re.IGNORECASE)
    if m:
        num = m.group(1)
        groups.setdefault(num, {'invoice_number': num, 'xls': None, 'pdf': None, 'period': None})
        groups[num]['pdf'] = {'id': f['Id'], 'name': name, 'size': f.get('Size', 0)}

# Extract period from comments if available
for f in files:
    comments = f.get('Comments', '')
    for num, g in groups.items():
        if num in comments and g['period'] is None:
            g['period'] = comments

result = {'partner': 'foodora', 'settlements': list(groups.values())}
print(json.dumps(result, indent=2))
"
}

_find_wolt() {
    local response="$1"
    # Group 3 PDFs by date range in Comments field
    echo "$response" | python3 -c "
import json, sys, re

data = json.load(sys.stdin)
files = data.get('files', [])

# Classify files and group by date range
groups = {}
for f in files:
    name = f.get('Name', '')
    comments = f.get('Comments', '')
    if not name.lower().endswith('.pdf'):
        continue

    # Extract date range from comments: 'Brödernas X - Wolt payout report DD/MM/YYYY - DD/MM/YYYY'
    m = re.search(r'(\d{2}/\d{2}/\d{4})\s*-\s*(\d{2}/\d{2}/\d{4})', comments)
    if not m:
        continue
    period_key = f'{m.group(1)}-{m.group(2)}'

    # Classify file type by filename pattern
    file_type = 'unknown'
    if '__payout_report__' in name:
        file_type = 'payout'
    elif '__sales_report__' in name:
        file_type = 'sales'
    elif re.search(r'_\d{4}-\d{2}-\d{2}_00_00_00\.000_', name):
        file_type = 'commission'

    groups.setdefault(period_key, {
        'period_from': m.group(1), 'period_to': m.group(2),
        'payout': None, 'sales': None, 'commission': None
    })
    if file_type != 'unknown':
        groups[period_key][file_type] = {'id': f['Id'], 'name': name, 'size': f.get('Size', 0)}

result = {'partner': 'wolt', 'settlements': list(groups.values())}
print(json.dumps(result, indent=2))
"
}

_find_ubereats() {
    local response="$1"
    # Each PDF is standalone
    echo "$response" | python3 -c "
import json, sys

data = json.load(sys.stdin)
files = data.get('files', [])

settlements = []
for f in files:
    name = f.get('Name', '')
    if name.lower().endswith('.pdf'):
        settlements.append({
            'file': {'id': f['Id'], 'name': name, 'size': f.get('Size', 0)},
            'comments': f.get('Comments', '')
        })

result = {'partner': 'ubereats', 'settlements': settlements}
print(json.dumps(result, indent=2))
"
}

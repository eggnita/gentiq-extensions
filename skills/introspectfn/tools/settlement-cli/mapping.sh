#!/usr/bin/env bash
# settlement mapping — Manage account mappings
#
# Usage:
#   settlement mapping show <company_id> --partner <partner>
#   settlement mapping set <company_id> --partner <partner> --key <key> --account <number>
#   settlement mapping confirm <company_id> --partner <partner>
#   settlement mapping reset <company_id> --partner <partner>

settlement_mapping() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        show)    _mapping_show "$@" ;;
        set)     _mapping_set "$@" ;;
        confirm) _mapping_confirm "$@" ;;
        reset)   _mapping_reset "$@" ;;
        *)
            echo '{"error": "Usage: settlement mapping <show|set|confirm|reset> <company_id> --partner <partner>"}' >&2
            return 1
            ;;
    esac
}

_parse_mapping_args() {
    MAPPING_COMPANY="" MAPPING_PARTNER="" MAPPING_KEY="" MAPPING_ACCOUNT=""
    if [ $# -ge 1 ]; then
        MAPPING_COMPANY="$1"; shift
    fi
    while [ $# -gt 0 ]; do
        case "$1" in
            --partner)  MAPPING_PARTNER="$2"; shift 2 ;;
            --key)      MAPPING_KEY="$2"; shift 2 ;;
            --account)  MAPPING_ACCOUNT="$2"; shift 2 ;;
            *)          shift ;;
        esac
    done
}

_mapping_show() {
    _parse_mapping_args "$@"
    if [ -z "$MAPPING_PARTNER" ] || [ -z "$MAPPING_COMPANY" ]; then
        echo '{"error": "--partner and company_id required"}' >&2
        return 1
    fi

    python3 -c "
import sys; sys.path.insert(0, '${SETTLEMENT_CLI}/lib')
from mapping import load, get_effective, is_confirmed
import json

m = load('${MAPPING_PARTNER}')
if not m:
    print(json.dumps({'error': 'No mapping found for ${MAPPING_PARTNER}. Run: settlement discover-accounts'}))
    sys.exit(0)

eff = get_effective(m, '${MAPPING_COMPANY}')
confirmed = is_confirmed(m, '${MAPPING_COMPANY}')
company = m.get('companies', {}).get('${MAPPING_COMPANY}', {})

result = {
    'partner': '${MAPPING_PARTNER}',
    'company_id': '${MAPPING_COMPANY}',
    'company_name': company.get('name', 'Unknown'),
    'confirmed': confirmed,
    'confirmed_at': company.get('confirmed_at', ''),
    'accounts': {k: v['account'] for k, v in eff.items()},
    'overrides': list(company.get('overrides', {}).keys()),
}
print(json.dumps(result, indent=2, ensure_ascii=False))
"
}

_mapping_set() {
    _parse_mapping_args "$@"
    if [ -z "$MAPPING_PARTNER" ] || [ -z "$MAPPING_COMPANY" ] || [ -z "$MAPPING_KEY" ] || [ -z "$MAPPING_ACCOUNT" ]; then
        echo '{"error": "--partner, company_id, --key, --account all required"}' >&2
        return 1
    fi

    # Validate account exists in Fortnox
    local accounts_response
    accounts_response=$(ifn_get "/api/companies/${MAPPING_COMPANY}/internal/accounts?page=1&limit=500&active=true" 2>/dev/null) || true

    python3 -c "
import sys; sys.path.insert(0, '${SETTLEMENT_CLI}/lib')
from mapping import load, save, set_override, new_mapping
import json

m = load('${MAPPING_PARTNER}') or new_mapping('${MAPPING_PARTNER}')

# Validate account exists
accounts = json.loads('''${accounts_response}''') if '''${accounts_response}'''.strip() else {}
account_list = accounts.get('Accounts', [])
account_num = int('${MAPPING_ACCOUNT}')
found = any(a.get('Number') == account_num for a in account_list)

if account_list and not found:
    print(json.dumps({'error': f'Account {account_num} not found in chart of accounts', 'warning': True}))
else:
    set_override(m, '${MAPPING_COMPANY}', '', '${MAPPING_KEY}', account_num)
    save('${MAPPING_PARTNER}', m)
    print(json.dumps({'ok': True, 'key': '${MAPPING_KEY}', 'account': account_num, 'partner': '${MAPPING_PARTNER}'}))
"
}

_mapping_confirm() {
    _parse_mapping_args "$@"
    if [ -z "$MAPPING_PARTNER" ] || [ -z "$MAPPING_COMPANY" ]; then
        echo '{"error": "--partner and company_id required"}' >&2
        return 1
    fi

    # Get company name
    local company_name=""
    local dashboard
    dashboard=$(ifn_get "/api/companies/${MAPPING_COMPANY}/dashboard" 2>/dev/null) || true
    company_name=$(echo "$dashboard" | jq -r '.company_name // empty' 2>/dev/null)

    python3 -c "
import sys; sys.path.insert(0, '${SETTLEMENT_CLI}/lib')
from mapping import load, save, confirm, new_mapping
import json

m = load('${MAPPING_PARTNER}') or new_mapping('${MAPPING_PARTNER}')
confirm(m, '${MAPPING_COMPANY}', '${company_name}')
save('${MAPPING_PARTNER}', m)
print(json.dumps({'ok': True, 'confirmed': True, 'partner': '${MAPPING_PARTNER}', 'company': '${company_name}'}))
"
}

_mapping_reset() {
    _parse_mapping_args "$@"
    if [ -z "$MAPPING_PARTNER" ] || [ -z "$MAPPING_COMPANY" ]; then
        echo '{"error": "--partner and company_id required"}' >&2
        return 1
    fi

    python3 -c "
import sys; sys.path.insert(0, '${SETTLEMENT_CLI}/lib')
from mapping import load, save, reset_overrides
import json

m = load('${MAPPING_PARTNER}')
if not m:
    print(json.dumps({'error': 'No mapping found for ${MAPPING_PARTNER}'}))
else:
    reset_overrides(m, '${MAPPING_COMPANY}')
    save('${MAPPING_PARTNER}', m)
    print(json.dumps({'ok': True, 'reset': True, 'partner': '${MAPPING_PARTNER}'}))
"
}

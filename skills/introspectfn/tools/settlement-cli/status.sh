#!/usr/bin/env bash
# settlement status — Show booking template cache status
#
# Usage: settlement status [company_id]

settlement_status() {
    local template_dir="${HOME}/.ifn/booking-templates"

    if [ ! -d "$template_dir" ]; then
        echo '{"templates": [], "message": "No template cache directory found"}'
        return 0
    fi

    python3 -c "
import json, os, sys
from datetime import datetime, timedelta

template_dir = os.path.expanduser('~/.ifn/booking-templates')
templates = []

for f in sorted(os.listdir(template_dir)):
    if not f.endswith('.json'):
        continue
    path = os.path.join(template_dir, f)
    try:
        with open(path) as fh:
            t = json.load(fh)
        learned_at = t.get('learned_at', '')
        ttl_days = t.get('ttl_days', 90)
        expired = False
        if learned_at:
            learned = datetime.fromisoformat(learned_at.replace('Z', '+00:00'))
            expired = datetime.now(learned.tzinfo) > learned + timedelta(days=ttl_days)
        templates.append({
            'partner': t.get('partner', f.replace('.json', '')),
            'learned_at': learned_at,
            'ttl_days': ttl_days,
            'expired': expired,
            'source_vouchers': t.get('learned_from_vouchers', []),
            'accounts': list(t.get('mapping', {}).keys()),
        })
    except Exception as e:
        templates.append({'partner': f, 'error': str(e)})

print(json.dumps({'templates': templates}, indent=2))
"
}

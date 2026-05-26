#!/usr/bin/env python3
"""Generate a markdown support document from adjustment data.

Usage: build_support_doc.py <adjustment.json>
Output: Markdown to stdout
"""

import json
import sys


def main():
    if len(sys.argv) != 2:
        print("Usage: build_support_doc.py <adjustment.json>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        data = json.load(f)

    partner = data.get("partner", "")
    venue = data.get("venue", "")
    period = data.get("period", {})

    print(f"# Revenue Adjustment — {partner.title()}")
    print(f"**Restaurant:** {venue}")
    print(f"**Period:** {period.get('from', '')} to {period.get('to', '')}")
    print(f"**Match method:** {data.get('match_method', '')}")
    print(f"**Total adjustment:** {data.get('total_adjustment_amount', 0):.2f} SEK")
    print(f"**Cancelled orders:** {data.get('total_cancelled_orders', 0)}")
    print()

    for adj in data.get("adjustments", []):
        print(f"## {adj['date']}")
        print(f"- Cancelled orders: {adj['cancelled_orders']}")
        print(f"- Adjustment amount: {adj['adjustment_amount']:.2f} SEK")
        pos_count = adj.get("pos_orders", adj.get("pos_orders_that_day", "N/A"))
        print(f"- POS orders that day: {pos_count}")
        print()
        for o in adj.get("orders", adj.get("cancelled_order_details", [])):
            oid = o.get("order_id", "N/A")
            amt = o.get("amount", 0)
            reason = o.get("reason", o.get("status", ""))
            owner = o.get("owner", "")
            suffix = f" — {reason}" if reason else ""
            suffix += f" ({owner})" if owner else ""
            print(f"  - {oid}: {amt:.2f} SEK{suffix}")
        print()


if __name__ == "__main__":
    main()

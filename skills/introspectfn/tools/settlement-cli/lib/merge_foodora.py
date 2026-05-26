#!/usr/bin/env python3
"""Merge Foodora XLS (order-level) and PDF (summary) parser outputs.

Usage: merge_foodora.py <xls.json> <pdf.json>
Output: Combined JSON to stdout
"""

import json
import sys


def main():
    if len(sys.argv) != 3:
        print(json.dumps({"error": "Usage: merge_foodora.py <xls.json> <pdf.json>"}), file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        xls = json.load(f)
    with open(sys.argv[2]) as f:
        pdf = json.load(f)

    result = {
        "partner": "foodora",
        "store_id": xls.get("store_id", pdf.get("store_id", "")),
        "restaurant": xls.get("restaurant", pdf.get("restaurant", "")),
        "invoice_number": pdf.get("invoice_number", ""),
        "period": {
            "from": pdf.get("period_from", ""),
            "to": pdf.get("period_to", ""),
        },
        "orders": xls.get("orders", []),
        "summary": {
            "total_orders": xls["summary"]["total_orders"],
            "delivery": pdf.get("part1_sales", {}).get("delivery", {}),
            "pickup": pdf.get("part1_sales", {}).get("pickup", {}),
            "commissions": pdf.get("part1_sales", {}).get("commissions", []),
            "sales_excl_vat": pdf.get("part1_sales", {}).get("sales_excl_vat", 0),
            "vat_rate": pdf.get("part1_sales", {}).get("vat_rate", 0),
            "vat_amount": pdf.get("part1_sales", {}).get("vat_amount", 0),
            "total_part1": pdf.get("part1_sales", {}).get("total", 0),
            "charges": pdf.get("part2_charges", {}).get("charges", []),
            "charges_excl_vat": pdf.get("part2_charges", {}).get("charges_excl_vat", 0),
            "input_vat_25": pdf.get("part2_charges", {}).get("input_vat_25", 0),
            "total_part2": pdf.get("part2_charges", {}).get("total", 0),
            "rounding": pdf.get("rounding", 0),
            "net_payout": pdf.get("net_payout", 0),
            # XLS totals for cross-check
            "xls_total_gross": xls["summary"]["total_gross"],
            "xls_total_commission_base": xls["summary"]["total_commission_base"],
            "xls_total_vat_6": xls["summary"]["total_vat_6"],
        },
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

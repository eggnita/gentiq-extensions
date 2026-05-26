#!/usr/bin/env python3
"""Build IFN staging payload for a revenue adjustment correction voucher.

Usage: build_correction_payload.py <adjustment.json> --correction-acct <n> --receivable-acct <n> --fy-id <id> [--file-ref <ref>]
Output: JSON staging payload to stdout
"""

import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("adjustment_file")
    parser.add_argument("--correction-acct", type=int, default=3083)
    parser.add_argument("--receivable-acct", type=int, default=1584)
    parser.add_argument("--fy-id", default="")
    parser.add_argument("--file-ref", default="")
    args = parser.parse_args()

    with open(args.adjustment_file) as f:
        data = json.load(f)

    partner = data.get("partner", "")
    venue = data.get("venue", "")
    total = data.get("total_adjustment_amount", 0)
    period = data.get("period", {})
    period_str = f"{period.get('from', '')} - {period.get('to', '')}"
    target_date = period.get("to", "")

    # For restaurant food (6% VAT), reverse the revenue
    vat_rate = 0.06
    net_amount = round(total / (1 + vat_rate), 2)
    vat_amount = round(total - net_amount, 2)

    voucher_rows = [
        {
            "Account": args.correction_acct,
            "Debit": net_amount,
            "Credit": 0,
            "Description": f"Korrigering {partner.title()} {period_str}"[:100],
        },
        {
            "Account": 2630,
            "Debit": vat_amount,
            "Credit": 0,
            "Description": f"Moms korrigering {partner.title()} {period_str}"[:100],
        },
        {
            "Account": args.receivable_acct,
            "Debit": 0,
            "Credit": total,
            "Description": f"{partner.title()} avräkning korrigering {period_str}"[:100],
        },
    ]

    payload = {
        "entity_type": "voucher",
        "action": "create",
        "payload": {
            "VoucherSeries": "A",
            "TransactionDate": target_date,
            "Description": f"Intäktskorrigering {partner.title()} {period_str} — {venue}",
            "VoucherRows": voucher_rows,
        },
        "accounting_reasoning": json.dumps({
            "confidence": "MEDIUM",
            "confidence_reason": f"Based on {data.get('total_cancelled_orders', 0)} cancelled orders via {data.get('match_method', '')}",
            "complexity": "COMPLEX",
            "risk": "MEDIUM",
        }),
        "notes": f"Revenue adjustment for {data.get('total_cancelled_orders', 0)} cancelled {partner.title()} orders totaling {total:.2f} SEK",
        "financial_year_id": int(args.fy_id) if args.fy_id else None,
        "target_date": target_date,
    }

    if args.file_ref:
        payload["file_refs"] = [args.file_ref]

    print(json.dumps(payload, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

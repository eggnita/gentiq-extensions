#!/usr/bin/env python3
"""Build IFN staging payload from a settlement proposal.

Usage: build_staging_payload.py <proposal.json> --fy-id <id> [--file-ref <ref>] [--voucher-series <s>]
Output: JSON staging payload to stdout
"""

import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("proposal_file")
    parser.add_argument("--fy-id", default="")
    parser.add_argument("--file-ref", default="")
    parser.add_argument("--voucher-series", default="A")
    args = parser.parse_args()

    with open(args.proposal_file) as f:
        proposal = json.load(f)

    rows = proposal.get("voucher_rows", [])
    period = proposal.get("period", {})
    partner = proposal.get("partner", "")
    restaurant = proposal.get("restaurant", "")
    period_str = f"{period.get('from', '')} - {period.get('to', '')}"

    # Build VoucherRows for Fortnox
    fortnox_rows = []
    for r in rows:
        fortnox_rows.append({
            "Account": r["account"],
            "Debit": r["debit"] if r["debit"] > 0 else 0,
            "Credit": r["credit"] if r["credit"] > 0 else 0,
            "Description": r["description"][:100],
        })

    # Target date = end of settlement period, normalized to YYYY-MM-DD
    target_date = period.get("to", "")
    if "." in target_date:
        parts = target_date.split(".")
        if len(parts) == 3:
            target_date = f"{parts[2]}-{parts[1]}-{parts[0]}"

    payload = {
        "entity_type": "voucher",
        "action": "create",
        "payload": {
            "VoucherSeries": args.voucher_series,
            "TransactionDate": target_date,
            "Description": f"{partner.title()} avräkning {period_str} — {restaurant}",
            "VoucherRows": fortnox_rows,
        },
        "accounting_reasoning": json.dumps({
            "confidence": proposal.get("confidence", "MEDIUM"),
            "confidence_reason": proposal.get("confidence_reason", ""),
            "complexity": "MODERATE",
            "risk": "LOW",
            "template_source": proposal.get("template_source", ""),
            "template_vouchers": proposal.get("template_vouchers", []),
            "order_count": proposal.get("order_count", 0),
            "partner": partner,
            "period": period_str,
        }),
        "notes": f"{partner.title()} settlement — {proposal.get('order_count', 0)} orders, {period_str}. Confidence: {proposal.get('confidence', 'MEDIUM')}",
        "financial_year_id": int(args.fy_id) if args.fy_id else None,
        "target_date": target_date,
    }

    if args.file_ref:
        payload["file_refs"] = [args.file_ref]

    print(json.dumps(payload, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

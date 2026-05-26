#!/usr/bin/env python3
"""Analyze historical vouchers and build a booking template.

Usage: build_template.py <vouchers.json> <accounts.json> --partner <p> --company-id <id> --account <n>
Output: JSON template to stdout
"""

import argparse
import json
import sys
from datetime import datetime


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("vouchers_file")
    parser.add_argument("accounts_file")
    parser.add_argument("--partner", required=True)
    parser.add_argument("--company-id", required=True)
    parser.add_argument("--account", type=int, required=True)
    args = parser.parse_args()

    with open(args.vouchers_file) as f:
        vouchers = json.load(f)
    with open(args.accounts_file) as f:
        accounts_data = json.load(f)

    accounts = {a["Number"]: a for a in accounts_data.get("Accounts", [])}
    partner_account = args.account

    # Analyze voucher rows to find the pattern
    account_usage = {}
    voucher_refs = []

    for v in vouchers:
        rows = v.get("VoucherRows", [])
        if not rows:
            continue
        series = v.get("VoucherSeries", "")
        number = v.get("VoucherNumber", "")
        voucher_refs.append(f"{series}{number}")

        for row in rows:
            acct = row.get("Account", 0)
            debit = float(row.get("Debit", 0) or 0)
            credit = float(row.get("Credit", 0) or 0)
            desc = row.get("Description", "")

            if acct not in account_usage:
                account_usage[acct] = {
                    "debit_count": 0, "credit_count": 0,
                    "total_debit": 0, "total_credit": 0,
                    "descriptions": set(),
                }
            if debit > 0:
                account_usage[acct]["debit_count"] += 1
                account_usage[acct]["total_debit"] += debit
            if credit > 0:
                account_usage[acct]["credit_count"] += 1
                account_usage[acct]["total_credit"] += credit
            if desc:
                account_usage[acct]["descriptions"].add(desc)

    # Build mapping from observed patterns
    mapping = {}

    for acct, usage in account_usage.items():
        acct_info = accounts.get(acct, {})
        desc = acct_info.get("Description", f"Account {acct}")
        primary_side = "debit" if usage["debit_count"] >= usage["credit_count"] else "credit"

        if acct == partner_account:
            mapping["receivable_clear"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
        elif 1930 <= acct <= 1939:
            mapping["bank_payout"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
        elif 2610 <= acct <= 2639:
            vat_code = acct_info.get("VATCode", "")
            if vat_code == "U3" or acct in (2630, 2631):
                mapping["output_vat_6"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
            elif vat_code == "U2" or acct in (2620, 2621):
                mapping["output_vat_12"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
            elif vat_code == "U1" or acct in (2610, 2611):
                mapping["output_vat_25"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
        elif 2640 <= acct <= 2649:
            mapping["input_vat"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
        elif 3000 <= acct < 3100:
            mapping.setdefault("revenue", {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"})
        elif 3700 <= acct < 3800:
            mapping["rounding"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
        elif 6000 <= acct < 7000:
            if "commission" not in mapping:
                mapping["commission"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}
            else:
                mapping["partner_charges"] = {"account": acct, "side": primary_side, "description_template": f"{desc} {{period}}"}

    template = {
        "partner": args.partner,
        "connection_id": args.company_id,
        "learned_from_vouchers": voucher_refs[:3],
        "learned_at": datetime.utcnow().isoformat() + "Z",
        "ttl_days": 90,
        "source": "voucher_analysis",
        "receivable_account": partner_account,
        "mapping": mapping,
    }
    print(json.dumps(template, indent=2))


if __name__ == "__main__":
    main()

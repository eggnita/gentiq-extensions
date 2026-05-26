#!/usr/bin/env python3
"""Discover account mapping from Fortnox chart of accounts.

Usage: discover_accounts.py <accounts.json> --partner <p> --company-id <id> --company-name <name>
Output: JSON mapping (v2 format) to stdout. Also saves to ~/.ifn/booking-templates/.
"""

import argparse
import json
import sys
from pathlib import Path

# Import mapping module
sys.path.insert(0, str(Path(__file__).parent))
from mapping import load, save, new_mapping, STANDARD_KEYS


PARTNER_SEARCH = {
    "foodora": ["Foodora", "foodora"],
    "wolt": ["Wolt", "wolt"],
    "ubereats": ["Uber", "uber"],
}

# Default receivable accounts per partner (if not found by name search)
DEFAULT_RECEIVABLES = {
    "foodora": 1584,
    "wolt": 1582,
    "ubereats": 1583,
}


def discover(accounts, partner, company_id, company_name):
    """Scan accounts and build/merge a v2 mapping."""

    # Load existing mapping or create new
    mapping = load(partner) or new_mapping(partner)

    terms = PARTNER_SEARCH.get(partner, [partner])
    found = {}

    for a in accounts:
        num = a.get("Number", 0)
        desc = a.get("Description", "")
        vat_code = a.get("VATCode", "")

        # Partner-specific receivable (1500-1599 with partner name)
        for term in terms:
            if term.lower() in desc.lower() and 1500 <= num < 1600:
                found["receivable"] = {"account": num, "side": "credit"}

        # Common accounts by number
        if num == 1930:
            found.setdefault("bank", {"account": num, "side": "debit"})
        elif num == 2640:
            found.setdefault("input_vat", {"account": num, "side": "debit"})
        elif num == 2630:
            found.setdefault("output_vat_6", {"account": num, "side": "credit"})
        elif num == 3740:
            found.setdefault("rounding", {"account": num, "side": "debit"})

        # Partner-specific fees (6000-6999 with delivery/avgift in name)
        for term in terms:
            if term.lower() in desc.lower() and 6000 <= num < 7000:
                found.setdefault("fees", {"account": num, "side": "debit"})
        if 6044 == num:
            found.setdefault("fees", {"account": num, "side": "debit"})

        # Correction accounts (3081-3089)
        if 3080 <= num <= 3089 and "orrigering" in desc.lower():
            if vat_code == "MP3" or "6%" in desc:
                found.setdefault("correction_6", {"account": num, "side": "debit"})
            elif vat_code == "MP2" or "12%" in desc:
                found.setdefault("correction_12", {"account": num, "side": "debit"})
            elif vat_code == "MP1" or "25%" in desc:
                found.setdefault("correction_25", {"account": num, "side": "debit"})

    # Apply default receivable if not found
    if "receivable" not in found:
        found["receivable"] = {"account": DEFAULT_RECEIVABLES.get(partner, 1584), "side": "credit"}

    # Merge found accounts into defaults (don't overwrite existing defaults)
    for key, value in found.items():
        if key not in mapping["defaults"]:
            mapping["defaults"][key] = value

    # Add this company (don't overwrite if already exists and confirmed)
    if company_id not in mapping.get("companies", {}):
        mapping.setdefault("companies", {})[company_id] = {
            "name": company_name,
            "confirmed": False,
            "overrides": {},
        }
    elif not mapping["companies"][company_id].get("confirmed", False):
        mapping["companies"][company_id]["name"] = company_name

    # Save
    save(partner, mapping)

    # Output
    print(json.dumps(mapping, indent=2, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("accounts_file")
    parser.add_argument("--partner", required=True)
    parser.add_argument("--company-id", required=True)
    parser.add_argument("--company-name", default="Unknown")
    args = parser.parse_args()

    with open(args.accounts_file) as f:
        data = json.load(f)

    accounts = data.get("Accounts", data) if isinstance(data, dict) else data
    discover(accounts, args.partner, args.company_id, args.company_name)


if __name__ == "__main__":
    main()

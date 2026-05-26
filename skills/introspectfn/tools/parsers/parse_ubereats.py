#!/usr/bin/env python3
"""Parse Uber Eats settlement PDF into normalized JSON.

Usage: parse_ubereats.py <path_to_pdf>
Output: JSON to stdout
"""

import json
import re
import subprocess
import sys


def extract_text(pdf_path):
    result = subprocess.run(
        ["pdftotext", "-layout", pdf_path, "-"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"pdftotext failed on {pdf_path}: {result.stderr}")
    return result.stdout


def clean_sek(s):
    """Convert Swedish SEK format to float. E.g. '2.605,27 kr' → 2605.27, '-675,94 kr' → 675.94"""
    s = re.sub(r'[\u200e\u200f\u200b\u00ad\ufeff]', '', s)
    s = s.replace('kr', '').strip()
    negative = '-' in s
    s = s.replace('-', '').strip()
    # Remove thousand separator dots, convert decimal comma
    s = s.replace('.', '').replace(',', '.')
    s = re.sub(r'\s+', '', s)
    val = float(s)
    return val if not negative else val


def parse(pdf_path):
    text = extract_text(pdf_path)

    # Restaurant name — first line
    restaurant = ""
    m = re.search(r'^(.+)$', text.strip(), re.MULTILINE)
    if m:
        restaurant = m.group(1).strip()

    # Period
    period_from = period_to = ""
    m = re.search(r'Betalningsöversikt över\s+(\S+)\s*-\s*(\S+)', text)
    if m:
        period_from, period_to = m.group(1), m.group(2)

    # Daily breakdown rows: date, orders, amount kr
    orders = []
    # Match lines like: 12/29/25    2    825,00 kr
    for m in re.finditer(r'(\d{1,2}/\d{1,2}/\d{2})\s+(\d+)\s+([\d.,]+)\s*kr', text):
        orders.append({
            "date": m.group(1),
            "order_count": int(m.group(2)),
            "sales": clean_sek(m.group(3)),
        })

    # Summary values — find the last "number kr" on a line containing the label
    def find_value(label):
        m = re.search(label + r'.*?([-\d.,]+)\s*kr\s*$', text, re.MULTILINE)
        if m:
            return clean_sek(m.group(1))
        return 0.0

    total_gross = find_value(r'Totalbelopp')
    uber_fee = find_value(r'Uber Eats-avgift')
    uber_fee_vat = find_value(r'Moms på Uber Eats-avgift')
    net_sales = find_value(r'Nettoförsäljning')
    promotions = find_value(r'Kampanjer på objekt')
    # "Total Betalning" appears twice — once in header (with total), once in summary
    # Find the last occurrence which is the summary one
    payout_matches = re.findall(r'Total Betalning\s+([-\d.,\s]+)\s*kr', text)
    net_payout = clean_sek(payout_matches[-1]) if payout_matches else 0.0

    return {
        "partner": "ubereats",
        "restaurant": restaurant,
        "period": {
            "from": period_from,
            "to": period_to,
        },
        "orders": orders,
        "summary": {
            "total_orders": sum(o["order_count"] for o in orders),
            "total_gross": total_gross,
            "uber_fee": uber_fee,
            "uber_fee_vat": uber_fee_vat,
            "net_sales": net_sales,
            "promotions": promotions,
            "net_payout": net_payout,
        },
    }


def main():
    if len(sys.argv) != 2:
        print(json.dumps({"error": "Usage: parse_ubereats.py <path>"}), file=sys.stderr)
        sys.exit(1)

    try:
        result = parse(sys.argv[1])
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

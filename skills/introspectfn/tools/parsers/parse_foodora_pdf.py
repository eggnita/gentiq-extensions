#!/usr/bin/env python3
"""Parse Foodora settlement PDF summary (page 1) into structured JSON.

Extracts commission rates, charges (Pink Choice, Fri Leverans),
VAT, and net payout — data not available in the XLS.

Usage: parse_foodora_pdf.py <path_to_pdf>
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
        raise RuntimeError(f"pdftotext failed: {result.stderr}")
    return result.stdout


def clean_sek(s):
    """Parse Swedish SEK number format. E.g. '9,075.43 SEK' → 9075.43"""
    s = re.sub(r'[\u200e\u200f\u200b\u00ad\ufeff]', '', s)
    s = s.replace('SEK', '').strip()
    negative = s.startswith('-')
    s = s.lstrip('-').strip()
    # Foodora PDF uses period as thousands separator, comma as decimal
    # But also sometimes uses comma for thousands: "981,14" means 981.14
    # Detect: if there's exactly one comma and digits after it are 2, it's decimal
    # If there's a period followed by digits and then comma, period is thousands
    # Pattern: "9,075.43" → period is thousands sep? No — Foodora uses "9,075.43" as English format
    # Actually looking at the PDF: "9,075.43 SEK" — comma is thousands, period is decimal
    # And "-1,905.83 SEK"
    # But also "472.04 SEK" — no thousands separator
    # So: remove commas (thousands), period stays as decimal
    s = s.replace(',', '')
    s = s.strip()
    if not s:
        return 0.0
    val = float(s)
    return -val if negative else val


def parse(pdf_path):
    text = extract_text(pdf_path)

    result = {
        "invoice_number": "",
        "period_from": "",
        "period_to": "",
        "restaurant": "",
    }

    # Invoice number
    m = re.search(r'Fakturanummer:\s+(\d+)', text)
    if m:
        result["invoice_number"] = m.group(1)

    # Period — from "Självfaktura ... för perioden DD.MM.YYYY - DD.MM.YYYY"
    m = re.search(r'för perioden\s+([\d.]+)\s*-\s*([\d.]+)', text)
    if m:
        result["period_from"] = m.group(1)
        result["period_to"] = m.group(2)

    # Restaurant name — after "Bill To:" or from the address block
    m = re.search(r'Brödernas\s+(\S+)\s+AB', text)
    if m:
        result["restaurant"] = f"Brödernas {m.group(1)}"
    elif re.search(r'Brödernas\s+(\S+)', text):
        m2 = re.search(r'Brödernas\s+(\S+)', text)
        result["restaurant"] = f"Brödernas {m2.group(1)}"

    # Store ID / customer number
    m = re.search(r'Kundnummer:\s+(\S+)', text)
    if m:
        result["store_id"] = m.group(1)

    # --- Part 1: Restaurant's sales (Självfaktura) ---

    # Delivery orders
    m = re.search(r'Utkörningsorders\s+(\d+)\s+([\d,.]+)\s*SEK\s+([\d,.]+)\s*SEK', text)
    delivery = {}
    if m:
        delivery = {
            "count": int(m.group(1)),
            "gross": clean_sek(m.group(2)),
            "net": clean_sek(m.group(3)),
        }

    # Pickup orders
    m = re.search(r'Avhämtningsorders\s+(\d+)\s+([\d,.]+)\s*SEK\s+([\d,.]+)\s*SEK', text)
    pickup = {}
    if m:
        pickup = {
            "count": int(m.group(1)),
            "gross": clean_sek(m.group(2)),
            "net": clean_sek(m.group(3)),
        }

    # Commission rates
    commissions = []
    for m in re.finditer(r'Rabatt\s+(.+?)\s+(\d+)\s+(-?[\d,.]+)\s*SEK\s+([\d.]+)\s+(-?[\d,.]+)\s*SEK', text):
        commissions.append({
            "description": m.group(1).strip(),
            "order_count": int(m.group(2)),
            "base": clean_sek(m.group(3)),
            "rate_percent": float(m.group(4)),
            "amount": clean_sek(m.group(5)),
        })

    # Sales excl VAT
    m = re.search(r'Era försäljningar exkl\. moms\s+([\d,.]+)\s*SEK', text)
    sales_excl_vat = clean_sek(m.group(1)) if m else 0

    # VAT on sales
    m = re.search(r'Moms\s+(\d+)\s*%\s+([\d,.]+)\s*SEK', text)
    vat_rate = int(m.group(1)) if m else 0
    vat_amount = clean_sek(m.group(2)) if m else 0

    # Total part 1
    m = re.search(r'Totalt\s*\(1\)\s+([\d,.]+)\s*SEK', text)
    total_part1 = clean_sek(m.group(1)) if m else 0

    # --- Part 2: Foodora's charges ---

    charges = []
    # Extract the Part 2 section (between "Faktura ...2" header and "Foodoras försäljningar")
    part2_section = re.search(
        r'Faktura\s+\d+-2\s+för perioden.*?\n(.*?)Foodoras försäljningar',
        text, re.DOTALL)
    if part2_section:
        # Match any charge line: "Description    count    -amount SEK"
        for m in re.finditer(r'^(.+?)\s+(\d+)\s+(-?[\d,.]+)\s*SEK\s*$',
                             part2_section.group(1), re.MULTILINE):
            desc = m.group(1).strip()
            # Skip header rows
            if desc in ("Beskrivning", "Antal") or "Totalt" in desc:
                continue
            charges.append({
                "description": desc,
                "count": int(m.group(2)),
                "amount": clean_sek(m.group(3)),
            })

    # Foodora sales excl VAT
    m = re.search(r'Foodoras försäljningar exkl\. moms\s+(-?[\d,.]+)\s*SEK', text)
    foodora_charges_excl_vat = clean_sek(m.group(1)) if m else 0

    # Input VAT on Foodora charges
    m = re.search(r'Er ingående moms\s+\d+%\s*\([^)]+\)\s+(-?[\d,.]+)\s*SEK', text)
    input_vat = clean_sek(m.group(1)) if m else 0

    # Total part 2
    m = re.search(r'Totalt\s*\(2\)\s+(-?[\d,.]+)\s*SEK', text)
    total_part2 = clean_sek(m.group(1)) if m else 0

    # Rounding
    m = re.search(r'Öresavrundning\s+(-?[\d,.]+)\s*SEK', text)
    rounding = clean_sek(m.group(1)) if m else 0

    # Net payout
    m = re.search(r'Vi betalar ut till er.*?\s+([\d,.]+)\s*SEK', text)
    net_payout = clean_sek(m.group(1)) if m else 0

    result["part1_sales"] = {
        "delivery": delivery,
        "pickup": pickup,
        "commissions": commissions,
        "sales_excl_vat": sales_excl_vat,
        "vat_rate": vat_rate,
        "vat_amount": vat_amount,
        "total": total_part1,
    }

    result["part2_charges"] = {
        "charges": charges,
        "charges_excl_vat": foodora_charges_excl_vat,
        "input_vat_25": input_vat,
        "total": total_part2,
    }

    result["rounding"] = rounding
    result["net_payout"] = net_payout

    return result


def main():
    if len(sys.argv) != 2:
        print(json.dumps({"error": "Usage: parse_foodora_pdf.py <path>"}), file=sys.stderr)
        sys.exit(1)

    try:
        result = parse(sys.argv[1])
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

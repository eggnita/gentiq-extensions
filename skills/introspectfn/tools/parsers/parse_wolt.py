#!/usr/bin/env python3
"""Parse Wolt settlement PDFs into normalized JSON.

Usage: parse_wolt.py <payout.pdf> <sales.pdf> <commission.pdf>
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


def clean_number(s):
    """Convert Swedish number format to float. Handles invisible chars and spaces."""
    # Remove Unicode control chars (LRM, etc.)
    s = re.sub(r'[\u200e\u200f\u200b\u00ad\ufeff]', '', s)
    # Remove spaces within numbers (e.g., "7 71,00" → "771,00")
    s = re.sub(r'(\d)\s+(\d)', r'\1\2', s)
    # Swedish format: comma = decimal, period = thousands
    s = s.replace('.', '').replace(',', '.')
    s = s.strip()
    return float(s)


def parse_payout(text):
    """Parse the payout report (Wolt License Services Oy)."""
    data = {}

    # Period
    m = re.search(r'Tidsram\s+([\d.]+)\s*-\s*([\d.]+)', text)
    if m:
        data["period_from"] = m.group(1)
        data["period_to"] = m.group(2)

    # Restaurant
    m = re.search(r'Brödernas\s+(\S+)', text)
    if m:
        data["restaurant"] = f"Brödernas {m.group(1)}"

    # The payout summary section has lines like:
    #   Totalt antal sålda artiklar    771,00
    #   Belopp utbetalning             519,13
    # Use end-of-line anchoring to grab just the last number on each line.
    num = r'([\u200e\s]*-?[\d\s,.]+)'

    m = re.search(r'Totalt antal sålda artiklar' + num + r'\s*$', text, re.MULTILINE)
    if m:
        data["sold_goods_incl_vat"] = clean_number(m.group(1))

    m = re.search(r'Totala leveranser och sålda tjänster' + num + r'\s*$', text, re.MULTILINE)
    if m:
        data["deliveries_incl_vat"] = clean_number(m.group(1))

    m = re.search(r'Utbetalningskorrigeringar' + num + r'\s*$', text, re.MULTILINE)
    if m:
        data["payout_adjustments"] = clean_number(m.group(1))

    m = re.search(r'Summa faktura från Wolt till försäljare' + num + r'\s*$', text, re.MULTILINE)
    if m:
        data["wolt_invoice"] = clean_number(m.group(1))

    m = re.search(r'Belopp utbetalning' + num + r'\s*$', text, re.MULTILINE)
    if m:
        data["net_payout"] = clean_number(m.group(1))

    return data


def parse_sales(text):
    """Parse the sales report (order-level detail)."""
    orders = []

    # Period
    period_from = period_to = ""
    m = re.search(r'Tidsram\s+([\d.]+)\s*-\s*([\d.]+)', text)
    if m:
        period_from, period_to = m.group(1), m.group(2)

    # Order rows: date, time, #, Wolt+, ID, Värde, Moms 0%, ...
    pattern = re.compile(
        r'(\d{2}\.\d{2}\.\d{4})\s+'     # date
        r'(\d{2}:\d{2}:\d{2})\s+'        # time
        r'(\d+)\s+'                       # order number
        r'(Ja|Nej)\s+'                    # Wolt+
        r'(SWE/[\d/\-]+)\s+'             # ID
        r'([\s\d,.\u200e]+?)\s+'         # Värde
        r'([\s\d,.\u200e]+?)\s+'         # Moms 0%
        r'Leverans\s+'                    # delivery type
        r'([\s\d,.\u200e]+?)\s+'         # product total
        r'([\s\d,.\u200e]+?)$'           # delivery total
        , re.MULTILINE
    )

    for m in pattern.finditer(text):
        orders.append({
            "date": m.group(1),
            "timestamp": f"{m.group(1)} {m.group(2)}",
            "order_number": int(m.group(3)),
            "wolt_plus": m.group(4) == "Ja",
            "order_id": m.group(5).strip(),
            "value": clean_number(m.group(6)),
            "vat_0_base": clean_number(m.group(7)),
            "type": "delivery",
            "product_total": clean_number(m.group(8)),
            "delivery_total": clean_number(m.group(9)),
        })

    # Total row
    total_value = None
    m = re.search(r'Totalt\s+([\s\d,.\u200e]+?)\s+([\s\d,.\u200e]+?)\s+([\s\d,.\u200e]+?)\s+([\s\d,.\u200e]+?)$', text, re.MULTILINE)
    if m:
        total_value = clean_number(m.group(1))

    # VAT summary
    vat_amount = None
    m = re.search(r'6,00\s+([\s\d,.\u200e]+?)\s+([\s\d,.\u200e]+?)$', text, re.MULTILINE)
    if m:
        vat_amount = clean_number(m.group(2))

    return {
        "orders": orders,
        "total_value": total_value,
        "vat_amount": vat_amount,
        "period_from": period_from,
        "period_to": period_to,
    }


def parse_commission(text):
    """Parse the commission invoice (Wolt Sverige AB)."""
    data = {"commission_rows": [], "delivery_fees": {}, "service_fees": {}, "transaction_fees": {}}

    # Invoice number
    m = re.search(r'Fakturanummer\s+(SWE/[\d/\-]+)', text)
    if m:
        data["invoice_number"] = m.group(1)

    # Commission rows
    for m in re.finditer(r'Kommission[,\s]+(\S.*?)\s+([\s\d,.\u200e]+?)\s+([\s\d,.\u200e]+?)\s+25\.00%\s+([\s\d,.\u200e]+?)\s+([\s\d,.\u200e]+?)$', text, re.MULTILINE):
        data["commission_rows"].append({
            "description": f"Kommission {m.group(1).strip()}",
            "sales": clean_number(m.group(2)),
            "fee_excl_vat": clean_number(m.group(3)),
            "vat": clean_number(m.group(4)),
            "fee_incl_vat": clean_number(m.group(5)),
        })

    # For multi-column rows, extract by splitting the line on large whitespace gaps
    def parse_table_line(pattern, text_block):
        """Find a line matching pattern, return all numbers from that line."""
        m = re.search(pattern + r'(.+)$', text_block, re.MULTILINE)
        if not m:
            return []
        line = m.group(1) if m.lastindex else m.group(0)
        # Clean invisible chars, then find all numbers
        line = re.sub(r'[\u200e\u200f\u200b\u00ad\ufeff]', '', line)
        nums = re.findall(r'-?[\d\s]*\d+,\d+', line)
        return [clean_number(n) for n in nums]

    # Commission rows — already handled above via regex

    # Commission total: last number on the Totalt line under Kommission section
    # Find the section between "Kommission Wolt" and "Leverans-"
    comm_section = re.search(r'Kommission Wolt(.+?)Leverans', text, re.DOTALL)
    if comm_section:
        nums = parse_table_line(r'Totalt', comm_section.group(1))
        if nums:
            data["commission_total_incl_vat"] = nums[-1]

    # Delivery fees
    nums = parse_table_line(r'Leveransavgifter', text)
    if len(nums) >= 4:
        data["delivery_fees"] = {"fee_excl_vat": nums[1], "vat": nums[2], "fee_incl_vat": nums[3]}

    # Service fees
    nums = parse_table_line(r'Serviceavgift\b', text)
    if len(nums) >= 4:
        data["service_fees"] = {"fee_excl_vat": nums[1], "vat": nums[2], "fee_incl_vat": nums[3]}

    # Transaction fees total
    trans_section = re.search(r'Finans.+?transaktionsavgifter(.+?)Produktförsäljning', text, re.DOTALL)
    if trans_section:
        nums = parse_table_line(r'Totalt', trans_section.group(1))
        if nums:
            data["transaction_fees"] = {"fee_excl_vat": nums[1] if len(nums) > 1 else 0, "vat": nums[2] if len(nums) > 2 else 0, "fee_incl_vat": nums[-1]}

    # Invoice total
    nums = parse_table_line(r'Fakturabelopp', text)
    if nums:
        data["invoice_total"] = nums[-1]

    return data


def parse(payout_path, sales_path, commission_path):
    payout_text = extract_text(payout_path)
    sales_text = extract_text(sales_path)
    commission_text = extract_text(commission_path)

    payout = parse_payout(payout_text)
    sales = parse_sales(sales_text)
    commission = parse_commission(commission_text)

    # Build normalized output
    orders = []
    for o in sales["orders"]:
        orders.append({
            "order_id": o["order_id"],
            "date": o["date"],
            "timestamp": o["timestamp"],
            "gross_amount": o["value"],
            "product_total": o["product_total"],
            "delivery_total": o["delivery_total"],
            "wolt_plus": o["wolt_plus"],
            "type": o["type"],
        })

    return {
        "partner": "wolt",
        "restaurant": payout.get("restaurant", ""),
        "invoice_number": commission.get("invoice_number", ""),
        "period": {
            "from": payout.get("period_from", ""),
            "to": payout.get("period_to", ""),
        },
        "orders": orders,
        "summary": {
            "total_orders": len(orders),
            "sold_goods_incl_vat": payout.get("sold_goods_incl_vat", 0),
            "deliveries_incl_vat": payout.get("deliveries_incl_vat", 0),
            "payout_adjustments": payout.get("payout_adjustments", 0),
            "wolt_invoice": payout.get("wolt_invoice", 0),
            "net_payout": payout.get("net_payout", 0),
            "vat_on_sales": sales.get("vat_amount", 0),
            "fees": {
                "commission": commission.get("commission_rows", []),
                "commission_total_incl_vat": commission.get("commission_total_incl_vat", 0),
                "delivery_fees": commission.get("delivery_fees", {}),
                "service_fees": commission.get("service_fees", {}),
                "transaction_fees": commission.get("transaction_fees", {}),
                "invoice_total": commission.get("invoice_total", 0),
            },
        },
    }


def main():
    if len(sys.argv) != 4:
        print(json.dumps({"error": "Usage: parse_wolt.py <payout.pdf> <sales.pdf> <commission.pdf>"}), file=sys.stderr)
        sys.exit(1)

    try:
        result = parse(sys.argv[1], sys.argv[2], sys.argv[3])
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

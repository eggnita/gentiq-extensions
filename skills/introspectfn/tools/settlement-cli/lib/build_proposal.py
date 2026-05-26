#!/usr/bin/env python3
"""Build a balanced voucher proposal from parsed settlement data + mapping.

Usage: build_proposal.py <parsed.json> <mapping.json> [--company-id <id>]
Output: JSON proposal to stdout

Supports both v1 (flat mapping) and v2 (defaults + company overrides).
"""

import json
import sys

# Import mapping module if available (for v2 resolution)
try:
    from mapping import resolve as v2_resolve, is_confirmed
except ImportError:
    v2_resolve = None
    is_confirmed = None


def get_account(mapping, key, fallback=0, company_id=None):
    """Resolve account number. Supports v1 flat mapping and v2 with company overrides."""
    if company_id and mapping.get("version") == 2 and v2_resolve:
        result = v2_resolve(mapping, company_id, key, fallback)
        return result if result is not None else fallback
    # V1 fallback: check "mapping" sub-dict or flat keys
    m = mapping.get("mapping", mapping.get("defaults", mapping))
    return m.get(key, {}).get("account", fallback)


def get_desc(mapping, key, period_str, fallback=""):
    m = mapping.get("mapping", mapping.get("defaults", mapping))
    tmpl = m.get(key, {}).get("description_template", fallback)
    return tmpl.replace("{period}", period_str)


def build_foodora(parsed, mapping, period_str, company_id=None):
    """Build Foodora settlement voucher.

    The Foodora settlement has two sub-invoices:
    Part 1 (Självfaktura): Restaurant's sales, commission deducted, + output VAT
    Part 2 (Faktura): Foodora's charges to restaurant (Pink Choice, etc.) + input VAT

    The receivable to clear = net payout + all deductions (commission + charges + VAT).
    We compute the receivable from the settlement rather than guessing what POS booked,
    then let the auto-rounding handle any small difference.
    """
    rows = []
    s = parsed.get("summary", {})

    # Extract all amounts from PDF summary
    sales_excl_vat = s.get("sales_excl_vat", 0)
    vat_amount = s.get("vat_amount", 0)  # output VAT 6%
    total_part1 = s.get("total_part1", 0)  # sales + VAT

    charges_excl_vat = abs(s.get("charges_excl_vat", 0))
    input_vat_25 = abs(s.get("input_vat_25", 0))
    total_part2 = abs(s.get("total_part2", 0))

    total_commission = sum(abs(c.get("amount", 0)) for c in s.get("commissions", []))

    rounding = s.get("rounding", 0)
    net_payout = s.get("net_payout", 0)

    # The receivable = what the POS booked when orders were placed.
    # From Foodora's perspective: receivable = Part 1 total = 8,339.36
    # This is the amount Foodora owes us BEFORE their own charges.
    # Foodora then deducts Part 2 and pays the net.
    #
    # Settlement voucher structure:
    #   Credit 1584 (receivable): Part 1 total (clear what POS booked)
    #   Debit  6044 (commission): Commission amounts
    #   Debit  6044 (charges): Foodora's charges excl VAT (Part 2 items)
    #   Debit  2640 (input VAT): VAT 25% on Foodora charges
    #   Credit 2630 (output VAT): VAT 6% on sales (already in Part 1 total)
    #   Debit  1930 (bank): Net payout received
    #   Debit  3740 (rounding): Öresavrundning
    #
    # Balance check: Part1 + VAT6 = commission + charges + input_vat + bank + rounding
    # 8339.36 + 472.04 = 2049.47 + 1332.35 + 333.10 + 6673.86 + 0.05
    # 8811.40 ≠ 10388.83 — this doesn't balance because commission is ALREADY
    # deducted from Part 1 (sales_excl_vat = sales AFTER commission).
    #
    # Actually: the commission is deducted BEFORE calculating Part 1.
    # sales_excl_vat (7867.32) = gross_orders - commission
    # So the receivable = sales_excl_vat + VAT = 8339.36
    # The commission is NOT a separate debit — it's already reflected in
    # the reduced receivable amount.
    #
    # Correct structure:
    #   Credit 1584: 8,339.36 (Part 1 = what we receive from restaurant sales)
    #   Credit 2630: (no — VAT is inside Part 1)
    #   Debit  6044: 1,332.35 (Part 2 charges excl VAT)
    #   Debit  2640: 333.10 (input VAT on Part 2)
    #   Debit  1930: 6,673.86 (net payout)
    #   Debit  3740: 0.05 (rounding)
    #   Total credit: 8,339.36
    #   Total debit: 1,332.35 + 333.10 + 6,673.86 + 0.05 = 8,339.36 ✓

    cid = company_id
    receivable = get_account(mapping, "receivable", 1584, cid) or get_account(mapping, "receivable_clear", 1584, cid)
    fees_acct = get_account(mapping, "fees", 6044, cid) or get_account(mapping, "commission", 6044, cid)
    bank = get_account(mapping, "bank", 1930, cid) or get_account(mapping, "bank_payout", 1930, cid)
    vat_in = get_account(mapping, "input_vat", 2640, cid)
    rounding_acct = get_account(mapping, "rounding", 3740, cid)

    # Credit: Clear Foodora receivable = Part 1 total
    rows.append({
        "description": get_desc(mapping, "receivable", period_str, f"Foodora avräkning {period_str}"),
        "account": receivable,
        "debit": 0, "credit": round(total_part1, 2),
    })

    # Debit: Foodora's charges (Part 2 excl VAT: Pink Choice, Fri Leverans)
    if charges_excl_vat > 0:
        rows.append({
            "description": f"Foodora avgifter (Pink Choice, Fri Leverans) {period_str}",
            "account": fees_acct,
            "debit": round(charges_excl_vat, 2), "credit": 0,
        })

    # Debit: Input VAT 25% on Foodora charges
    if input_vat_25 > 0:
        rows.append({
            "description": get_desc(mapping, "input_vat", period_str, f"Ingående moms 25% Foodora {period_str}"),
            "account": vat_in,
            "debit": round(input_vat_25, 2), "credit": 0,
        })

    # Debit: Bank payout
    rows.append({
        "description": get_desc(mapping, "bank_payout", period_str, f"Foodora utbetalning {period_str}"),
        "account": bank,
        "debit": round(net_payout, 2), "credit": 0,
    })

    # Rounding
    if abs(rounding) > 0.001:
        rows.append({
            "description": "Öresavrundning",
            "account": rounding_acct,
            "debit": round(rounding, 2) if rounding > 0 else 0,
            "credit": round(abs(rounding), 2) if rounding < 0 else 0,
        })

    return rows


def build_wolt(parsed, mapping, period_str, company_id=None):
    rows = []
    s = parsed.get("summary", {})

    sold_goods = s.get("sold_goods_incl_vat", 0)
    deliveries = s.get("deliveries_incl_vat", 0)
    wolt_invoice = abs(s.get("wolt_invoice", 0))
    vat_on_sales = s.get("vat_on_sales", 0)
    net_payout = s.get("net_payout", 0)
    fees = s.get("fees", {})

    cid = company_id
    receivable = get_account(mapping, "receivable", 1582, cid) or get_account(mapping, "receivable_clear", 1582, cid)
    fees_acct = get_account(mapping, "fees", 6044, cid) or get_account(mapping, "commission", 6044, cid)
    bank = get_account(mapping, "bank", 1930, cid) or get_account(mapping, "bank_payout", 1930, cid)
    vat_in = get_account(mapping, "input_vat", 2640, cid)
    vat_out_6 = get_account(mapping, "output_vat_6", 2630, cid)

    # Credit: Clear Wolt receivable
    rows.append({
        "description": get_desc(mapping, "receivable_clear", period_str, f"Wolt avräkning {period_str}"),
        "account": receivable,
        "debit": 0, "credit": round(sold_goods + deliveries, 2),
    })

    # Debit: Commission
    commission_total = fees.get("commission_total_incl_vat", 0)
    if commission_total > 0:
        rows.append({
            "description": get_desc(mapping, "commission", period_str, f"Wolt provision {period_str}"),
            "account": fees_acct,
            "debit": round(commission_total, 2), "credit": 0,
        })

    # Debit: Delivery + service + transaction fees
    delivery_fee = fees.get("delivery_fees", {}).get("fee_incl_vat", 0)
    service_fee = fees.get("service_fees", {}).get("fee_incl_vat", 0)
    transaction_fee = fees.get("transaction_fees", {}).get("fee_incl_vat", 0)
    other_fees = delivery_fee + service_fee + transaction_fee
    if other_fees > 0:
        charges_acct = get_account(mapping, "partner_charges", fees_acct)
        rows.append({
            "description": f"Wolt leverans-/serviceavgifter {period_str}",
            "account": charges_acct,
            "debit": round(other_fees, 2), "credit": 0,
        })

    # Debit: Input VAT on all Wolt charges
    fees_vat = (
        fees.get("delivery_fees", {}).get("vat", 0)
        + fees.get("service_fees", {}).get("vat", 0)
        + fees.get("transaction_fees", {}).get("vat", 0)
        + sum(r.get("vat", 0) for r in fees.get("commission", []))
    )
    if fees_vat > 0:
        rows.append({
            "description": get_desc(mapping, "input_vat", period_str, f"Ingående moms Wolt {period_str}"),
            "account": vat_in,
            "debit": round(fees_vat, 2), "credit": 0,
        })

    # Credit: Output VAT on sales
    if vat_on_sales > 0:
        rows.append({
            "description": get_desc(mapping, "output_vat_6", period_str, f"Utgående moms 6% {period_str}"),
            "account": vat_out_6,
            "debit": 0, "credit": round(vat_on_sales, 2),
        })

    # Debit: Bank payout
    rows.append({
        "description": get_desc(mapping, "bank_payout", period_str, f"Wolt utbetalning {period_str}"),
        "account": bank,
        "debit": round(net_payout, 2), "credit": 0,
    })

    return rows


def build_ubereats(parsed, mapping, period_str, company_id=None):
    rows = []
    s = parsed.get("summary", {})

    total_gross = s.get("total_gross", 0)
    uber_fee = s.get("uber_fee", 0)
    uber_fee_vat = s.get("uber_fee_vat", 0)
    promotions = s.get("promotions", 0)
    net_payout = s.get("net_payout", 0)

    cid = company_id
    receivable = get_account(mapping, "receivable", 1583, cid) or get_account(mapping, "receivable_clear", 1583, cid)
    fees_acct = get_account(mapping, "fees", 6044, cid) or get_account(mapping, "commission", 6044, cid)
    bank = get_account(mapping, "bank", 1930, cid) or get_account(mapping, "bank_payout", 1930, cid)
    vat_in = get_account(mapping, "input_vat", 2640, cid)

    # Credit: Clear Uber receivable
    rows.append({
        "description": get_desc(mapping, "receivable_clear", period_str, f"Uber avräkning {period_str}"),
        "account": receivable,
        "debit": 0, "credit": round(total_gross, 2),
    })

    # Debit: Uber fee
    if uber_fee > 0:
        rows.append({
            "description": f"Uber Eats-avgift {period_str}",
            "account": fees_acct,
            "debit": round(uber_fee, 2), "credit": 0,
        })

    # Debit: VAT on Uber fee
    if uber_fee_vat > 0:
        rows.append({
            "description": get_desc(mapping, "input_vat", period_str, f"Moms Uber Eats-avgift {period_str}"),
            "account": vat_in,
            "debit": round(uber_fee_vat, 2), "credit": 0,
        })

    # Debit: Promotions
    if promotions > 0:
        charges_acct = get_account(mapping, "partner_charges", fees_acct)
        rows.append({
            "description": f"Kampanjer {period_str}",
            "account": charges_acct,
            "debit": round(promotions, 2), "credit": 0,
        })

    # Debit: Bank payout
    rows.append({
        "description": get_desc(mapping, "bank_payout", period_str, f"Uber Eats utbetalning {period_str}"),
        "account": bank,
        "debit": round(net_payout, 2), "credit": 0,
    })

    return rows


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("parsed_file")
    parser.add_argument("mapping_file")
    parser.add_argument("--company-id", default=None)
    args = parser.parse_args()

    with open(args.parsed_file) as f:
        parsed = json.load(f)
    with open(args.mapping_file) as f:
        mapping_data = json.load(f)

    company_id = args.company_id
    partner = parsed.get("partner", "")
    restaurant = parsed.get("restaurant", "")
    period = parsed.get("period", {})
    period_from = period.get("from", "")
    period_to = period.get("to", "")
    period_str = f"{period_from} - {period_to}"

    # Build rows per partner
    if partner == "foodora":
        rows = build_foodora(parsed, mapping_data, period_str, company_id)
    elif partner == "wolt":
        rows = build_wolt(parsed, mapping_data, period_str, company_id)
    elif partner == "ubereats":
        rows = build_ubereats(parsed, mapping_data, period_str, company_id)
    else:
        print(json.dumps({"error": f"Unknown partner: {partner}"}), file=sys.stderr)
        sys.exit(1)

    # Validate balance
    total_debit = sum(r["debit"] for r in rows)
    total_credit = sum(r["credit"] for r in rows)
    balanced = abs(total_debit - total_credit) < 0.02

    # Auto-rounding if close
    if not balanced and abs(total_debit - total_credit) < 1.0:
        diff = round(total_debit - total_credit, 2)
        rounding_acct = get_account(mapping_data, "rounding", 3740, company_id)
        if diff > 0:
            rows.append({"description": "Öresavrundning", "account": rounding_acct, "debit": 0, "credit": abs(diff)})
        else:
            rows.append({"description": "Öresavrundning", "account": rounding_acct, "debit": abs(diff), "credit": 0})
        total_debit = sum(r["debit"] for r in rows)
        total_credit = sum(r["credit"] for r in rows)
        balanced = abs(total_debit - total_credit) < 0.02

    # Confirmation status
    confirmed = False
    if mapping_data.get("version") == 2 and is_confirmed and company_id:
        confirmed = is_confirmed(mapping_data, company_id)

    # Confidence
    confidence = "HIGH"
    confidence_reason = "All values extracted deterministically from settlement files"
    if not balanced:
        confidence = "LOW"
        confidence_reason = f"Voucher does not balance: debit={total_debit:.2f}, credit={total_credit:.2f}"
    elif not confirmed:
        confidence = "MEDIUM"
        confidence_reason = "Account mapping not yet confirmed for this company"

    proposal = {
        "partner": partner,
        "restaurant": restaurant,
        "period": period,
        "invoice_number": parsed.get("invoice_number", ""),
        "voucher_rows": rows,
        "total_debit": round(total_debit, 2),
        "total_credit": round(total_credit, 2),
        "balanced": balanced,
        "confirmed": confirmed,
        "confidence": confidence,
        "confidence_reason": confidence_reason,
        "order_count": parsed.get("summary", {}).get("total_orders", len(parsed.get("orders", []))),
    }

    if not confirmed:
        proposal["disclaimer"] = "Account mapping not yet confirmed for this company. Verify accounts before acting."

    print(json.dumps(proposal, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

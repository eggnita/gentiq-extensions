"""Tests for Foodora PDF summary parser.

Extracts commission rates, charges, VAT, and net payout from page 1.
Uses real Foodora PDF from Brödernas Borlänge, invoice 7002651526.
"""

import json
import subprocess
import sys
from pathlib import Path

PARSER = Path(__file__).parent.parent / "tools" / "parsers" / "parse_foodora_pdf.py"
FIXTURE = Path(__file__).parent / "fixtures" / "foodora_sample.pdf"


def run_parser(file_path=None):
    args = [sys.executable, str(PARSER)]
    if file_path is not None:
        args.append(str(file_path))
    result = subprocess.run(args, capture_output=True, text=True)
    parsed = None
    if result.returncode == 0:
        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError:
            pass
    return result.returncode, parsed, result.stderr


def test_parses_and_outputs_valid_json():
    code, data, stderr = run_parser(FIXTURE)
    assert code == 0, f"Parser failed: {stderr}"
    assert data is not None, "Not valid JSON"
    assert data["invoice_number"] == "7002651526"


def test_period():
    _, data, _ = run_parser(FIXTURE)
    assert data["period_from"] == "01.05.2026"
    assert data["period_to"] == "07.05.2026"


def test_delivery_orders():
    _, data, _ = run_parser(FIXTURE)
    d = data["part1_sales"]["delivery"]
    assert d["count"] == 28
    assert abs(d["gross"] - 9075.43) < 0.01
    assert abs(d["net"] - 8561.70) < 0.01


def test_pickup_orders():
    _, data, _ = run_parser(FIXTURE)
    p = data["part1_sales"]["pickup"]
    assert p["count"] == 2
    assert abs(p["gross"] - 1436.37) < 0.01


def test_commission_rates():
    """21% on delivery, 10% on pickup."""
    _, data, _ = run_parser(FIXTURE)
    comms = data["part1_sales"]["commissions"]
    assert len(comms) == 2
    delivery_comm = next(c for c in comms if c["rate_percent"] == 21.0)
    assert abs(delivery_comm["amount"] - (-1905.83)) < 0.01
    pickup_comm = next(c for c in comms if c["rate_percent"] == 10.0)
    assert abs(pickup_comm["amount"] - (-143.64)) < 0.01


def test_sales_and_vat():
    _, data, _ = run_parser(FIXTURE)
    p1 = data["part1_sales"]
    assert abs(p1["sales_excl_vat"] - 7867.32) < 0.01
    assert p1["vat_rate"] == 6
    assert abs(p1["vat_amount"] - 472.04) < 0.01
    assert abs(p1["total"] - 8339.36) < 0.01


def test_foodora_charges():
    """Pink Choice 909.70, Fri Leverans 422.65."""
    _, data, _ = run_parser(FIXTURE)
    charges = data["part2_charges"]["charges"]
    pink = next(c for c in charges if "Pink" in c["description"])
    assert abs(pink["amount"] - (-909.70)) < 0.01
    fri = next(c for c in charges if "Fri" in c["description"])
    assert abs(fri["amount"] - (-422.65)) < 0.01


def test_input_vat():
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["part2_charges"]["input_vat_25"] - (-333.10)) < 0.01


def test_part2_total():
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["part2_charges"]["total"] - (-1665.45)) < 0.01


def test_rounding():
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["rounding"] - 0.05) < 0.01


def test_net_payout():
    """Vi betalar ut till er (1) + (2) = 6,673.86 SEK"""
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["net_payout"] - 6673.86) < 0.01


def test_net_payout_balances():
    """Verify: part1 total + part2 total + rounding ≈ net payout.
    Foodora has sub-öre rounding differences, so we allow 0.20 SEK tolerance."""
    _, data, _ = run_parser(FIXTURE)
    calculated = data["part1_sales"]["total"] + data["part2_charges"]["total"] + data["rounding"]
    assert abs(calculated - data["net_payout"]) < 0.20, f"Calculated {calculated} != payout {data['net_payout']}"


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS: {t.__name__}")

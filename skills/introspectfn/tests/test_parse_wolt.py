"""Tests for Wolt PDF settlement parser.

Tests the public interface: 3 PDF file paths in → JSON to stdout.
Uses real sample PDFs from Brödernas Borlänge, period 16.05.2026-20.05.2026.
"""

import json
import subprocess
import sys
from pathlib import Path

PARSER = Path(__file__).parent.parent / "tools" / "parsers" / "parse_wolt.py"
FIXTURES = Path(__file__).parent / "fixtures"
PAYOUT = FIXTURES / "wolt_payout.pdf"
SALES = FIXTURES / "wolt_sales.pdf"
COMMISSION = FIXTURES / "wolt_commission.pdf"


def run_parser(*file_paths):
    args = [sys.executable, str(PARSER)] + [str(p) for p in file_paths]
    result = subprocess.run(args, capture_output=True, text=True)
    parsed = None
    if result.returncode == 0:
        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError:
            pass
    return result.returncode, parsed, result.stderr


def test_parses_three_pdfs_and_outputs_valid_json():
    code, data, stderr = run_parser(PAYOUT, SALES, COMMISSION)
    assert code == 0, f"Parser failed: {stderr}"
    assert data is not None, "Output is not valid JSON"
    assert data["partner"] == "wolt"
    assert "orders" in data
    assert "summary" in data


def test_net_payout():
    """Net payout should be 519.13 SEK."""
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    assert abs(data["summary"]["net_payout"] - 519.13) < 0.01


def test_wolt_invoice_total():
    """Wolt invoice (fees) should be 430.02 SEK."""
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    assert abs(data["summary"]["wolt_invoice"] - (-430.02)) < 0.01


def test_order_count():
    """Sales report has 3 orders."""
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    assert len(data["orders"]) == 3


def test_order_detail():
    """First order: Wolt+ order on 17.05.2026, value 372.55."""
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    o = data["orders"][0]
    assert o["date"] == "17.05.2026"
    assert o["wolt_plus"] is True
    assert abs(o["gross_amount"] - 372.55) < 0.01
    assert "SWE/26/559310-0679/5/177" in o["order_id"]


def test_commission_breakdown():
    """Commission invoice total should be 430.02."""
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    fees = data["summary"]["fees"]
    assert abs(fees["invoice_total"] - 430.02) < 0.01
    assert abs(fees["commission_total_incl_vat"] - 218.96) < 0.01


def test_delivery_and_service_fees():
    """Delivery fees 128.54, service fees 81.54 (incl VAT)."""
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    fees = data["summary"]["fees"]
    assert abs(fees["delivery_fees"]["fee_incl_vat"] - 128.54) < 0.01
    assert abs(fees["service_fees"]["fee_incl_vat"] - 81.54) < 0.01


def test_period():
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    assert data["period"]["from"] == "16.05.2026"
    assert data["period"]["to"] == "20.05.2026"


def test_sold_goods_and_deliveries():
    """Payout report: sold goods 771.00, deliveries 178.15."""
    _, data, _ = run_parser(PAYOUT, SALES, COMMISSION)
    s = data["summary"]
    assert abs(s["sold_goods_incl_vat"] - 771.00) < 0.01
    assert abs(s["deliveries_incl_vat"] - 178.15) < 0.01


def test_fails_with_wrong_arg_count():
    code, _, _ = run_parser(PAYOUT)
    assert code == 1


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS: {t.__name__}")

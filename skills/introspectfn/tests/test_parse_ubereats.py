"""Tests for Uber Eats PDF settlement parser.

Uses real sample PDF from Brödernas Uppsala, period 12/29/25 - 1/4/26.
"""

import json
import subprocess
import sys
from pathlib import Path

PARSER = Path(__file__).parent.parent / "tools" / "parsers" / "parse_ubereats.py"
FIXTURE = Path(__file__).parent / "fixtures" / "ubereats_sample.pdf"


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


def test_parses_pdf_and_outputs_valid_json():
    code, data, stderr = run_parser(FIXTURE)
    assert code == 0, f"Parser failed: {stderr}"
    assert data is not None, "Output is not valid JSON"
    assert data["partner"] == "ubereats"
    assert "orders" in data
    assert "summary" in data


def test_net_payout():
    """Total Betalning = 2,605.27 SEK."""
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["summary"]["net_payout"] - 2605.27) < 0.01


def test_gross_total():
    """Totalbelopp = 3,677.00 SEK."""
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["summary"]["total_gross"] - 3677.00) < 0.01


def test_uber_fee_and_vat():
    """Uber Eats-avgift = 675.94, Moms = 168.99."""
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["summary"]["uber_fee"] - 675.94) < 0.01
    assert abs(data["summary"]["uber_fee_vat"] - 168.99) < 0.01


def test_promotions():
    """Kampanjer på objekt = 226.80."""
    _, data, _ = run_parser(FIXTURE)
    assert abs(data["summary"]["promotions"] - 226.80) < 0.01


def test_daily_breakdown():
    """5 days of orders, 8 total."""
    _, data, _ = run_parser(FIXTURE)
    assert len(data["orders"]) == 5
    total_orders = sum(o["order_count"] for o in data["orders"])
    assert total_orders == 8


def test_daily_amounts():
    """Verify specific daily amounts."""
    _, data, _ = run_parser(FIXTURE)
    day1 = data["orders"][0]
    assert day1["order_count"] == 2
    assert abs(day1["sales"] - 825.00) < 0.01


def test_restaurant_and_period():
    _, data, _ = run_parser(FIXTURE)
    assert "Uppsala" in data["restaurant"]
    assert data["period"]["from"] == "12/29/25"
    assert data["period"]["to"] == "1/4/26"


def test_fails_on_no_args():
    code, _, _ = run_parser()
    assert code == 1


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS: {t.__name__}")

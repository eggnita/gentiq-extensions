"""Tests for Foodora XLS settlement parser.

Tests the public interface: file path in → JSON to stdout.
Uses the real sample XLS from Brödernas Borlänge, invoice 7002651526.
"""

import json
import subprocess
import sys
from pathlib import Path

PARSER = Path(__file__).parent.parent / "tools" / "parsers" / "parse_foodora_xls.py"
FIXTURE = Path(__file__).parent / "fixtures" / "foodora_sample.xls"


def run_parser(file_path=None):
    """Run the parser and return (exit_code, parsed_json_or_none, stderr)."""
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


def test_parses_sample_xls_and_outputs_valid_json():
    code, data, stderr = run_parser(FIXTURE)
    assert code == 0, f"Parser failed with: {stderr}"
    assert data is not None, "Output is not valid JSON"
    assert data["partner"] == "foodora"
    assert "orders" in data
    assert "summary" in data


def test_extracts_correct_order_count():
    """28 delivery + 2 pickup = 30 orders. Daily aggregate rows (OPCC_INT) excluded."""
    _, data, _ = run_parser(FIXTURE)
    assert len(data["orders"]) == 30
    assert data["summary"]["total_orders"] == 30


def test_extracts_correct_order_level_data():
    """Verify a known order: gctc-2618-b0hm from page 2 of the PDF."""
    _, data, _ = run_parser(FIXTURE)
    order = next(o for o in data["orders"] if o["order_id"] == "gctc-2618-b0hm")
    assert order["date"] == "01.05.2026"
    assert order["vat_6"] == 17.75
    assert order["gross_amount"] == 478.0
    assert order["commission_base"] == 313.4
    assert order["store_id"] == "GCTC"
    assert order["restaurant"] == "Brödernas Borlänge"


def test_extracts_pickup_order():
    """Verify pickup order gctc-2618-5jv8 is included."""
    _, data, _ = run_parser(FIXTURE)
    order = next(o for o in data["orders"] if o["order_id"] == "gctc-2618-5jv8")
    assert order["gross_amount"] == 1040.0
    assert order["commission_base"] == 1040.0


def test_summary_totals_match_pdf():
    """Cross-check XLS commission_base sum against PDF settlement totals.
    PDF says: delivery gross = 9,075.43, pickup gross = 1,436.37 → total 10,511.80
    XLS Provisionsgrundande belopp sum = 10,511.80 (matches)
    Total VAT 6% = 595.15 (513.85 delivery + 81.30 pickup)
    """
    _, data, _ = run_parser(FIXTURE)
    s = data["summary"]
    assert s["total_orders"] == 30
    assert abs(s["total_commission_base"] - 10511.80) < 0.02, f"commission_base: {s['total_commission_base']}"
    assert abs(s["total_vat_6"] - 595.15) < 0.02, f"total_vat_6: {s['total_vat_6']}"
    assert s["total_vat_12"] == 0.0
    assert s["total_vat_25"] == 0.0


def test_fails_on_missing_file():
    code, _, stderr = run_parser("/nonexistent/file.xls")
    assert code == 1
    assert "error" in stderr.lower()


def test_fails_on_no_args():
    code, _, stderr = run_parser()
    assert code == 1


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS: {t.__name__}")

"""Foodora combo-invoice parser.

Extracts structured fields from a Foodora "Faktureringsdokument" PDF
(combined Självfaktura (1) + Faktura (2)). Output schema is consumed by
bko_builders/foodora_combo_invoice.py to produce a BKO entity.

CLI:
    python -m parsers.foodora_combo_invoice [PATH] [--out OUT]

Import:
    from parsers.foodora_combo_invoice import parse, PARSER_VERSION

API contract (`bko.Parser` protocol):
    `parse(source)` accepts a Path, raw bytes, or a binary file-like object.
    Returns {"data": dict, "errors": list[str], "diagnostics": dict}
    where diagnostics carries PDF-specific telemetry ({"pagesScanned": N}).

    Calling patterns:
        # Dev / test — easiest for ad-hoc batch runs:
        result = parse(Path("dev-data/FoodoraComboInvoice_FileSamples/x.pdf"))

        # Production — file arrives from `ifn files fetch` as bytes:
        result = parse(file_bytes)              # or BytesIO(file_bytes)

    `parse_invoice` is kept as a thin alias for in-flight callers but is
    deprecated; new code should use `parse`.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from io import BytesIO
from pathlib import Path
from typing import Any, Callable

import pdfplumber

from bko import SupportingDoc

PARSER_VERSION = "v0.11-credit-reversals"

MAX_RETRY_PAGES = 3

# `Rabatt ...` is the standard commission line (negative basis + amount).
# `Minskning av rabatt vid kreditering N%` is the paired REVERSAL row that
# appears when orders are cancelled mid-period — same rate, positive basis
# and positive amount. Both shapes are captured by the same regex; the sign
# of the amount tells the builder which is which (see _build_discount_rows).
CONTRACTUAL_DISCOUNT_ROW_RE = re.compile(
    r"^((?:Rabatt|Minskning av rabatt vid kreditering)[^\n0-9]*?)\s+(\d+\.\d{2})\s*%\s+(\d+)\s+"
    r"(-?[0-9,]+\.\d{2})\s*SEK\s+\d+\.\d{2}\s+(-?[0-9,]+\.\d{2})\s*SEK\s*$",
    re.MULTILINE,
)

# Order categories Foodora groups by. Each row is:
#   <Category>  <quantity>  <gross>SEK  <net>SEK
# Known categories so far:
#   Utkörningsorders            — delivery
#   Avhämtningsorders           — takeaway
#   Avbruten Utkörningsorders   — cancelled deliveries (negative gross/net)
#   Avbruten Avhämtningsorders  — cancelled takeaway   (negative gross/net)
# The builder treats Avbruten rows like any other order row — their negative
# gross/net values net out of the per-period totals automatically (the 1584 K
# math is `sum(grossAmount) - payoutAmount`, so cancellations reduce both
# sides symmetrically). New categories: extend the alternation here and add
# a sample test in tests/test_parser_foodora_combo_invoice.py.
ORDER_ROW_RE = re.compile(
    r"^(Utkörningsorders|Avhämtningsorders|Avbruten Utkörningsorders|Avbruten Avhämtningsorders)\s+(\d+)\s+"
    r"(-?[0-9,]+\.\d{2})\s*SEK\s*(-?[0-9,]+\.\d{2})\s*SEK\s*$",
    re.MULTILINE,
)


def _to_str(s: str) -> str:
    return s.strip()


def _to_int(s: str) -> int:
    return int(s)


def _to_amount(s: str) -> float:
    return float(Decimal(s.replace(",", "").replace(" ", "")))


def _to_rate(s: str) -> float:
    return float(Decimal(s) / Decimal(100))


def _to_iso_date_dmy(s: str) -> str:
    return datetime.strptime(s, "%d-%m-%Y").date().isoformat()


def _to_iso_date_dot_dmy(s: str) -> str:
    return datetime.strptime(s, "%d.%m.%Y").date().isoformat()


@dataclass(frozen=True)
class Field:
    path: tuple[str, ...]
    pattern: str
    transform: Callable[[str], Any] = _to_str
    required: bool = True


FIELDS: tuple[Field, ...] = (
    Field(("issuer", "orgNo"), r"Email: ?Partner@foodora\.se\s+(\d{6}-\d{4})"),
    Field(("issuer", "vatNo"), r"Momsreg\. nr\.\s*\n?(SE\d+)"),

    Field(("recipient", "name"), r"Fakturanummer:\s*\d+\s+([^\n]+?)\s*$"),
    Field(("recipient", "customerNo"), r"Kundnummer:\s*(\S+)"),
    Field(("recipient", "orgNo"), r"Org\. Nr\.:\s*(\d+)"),
    Field(("recipient", "vatNo"), r"Moms Nr:\s*(SE\d+)"),

    Field(("comboInvoice", "invoiceNo"), r"Fakturanummer:\s*(\d+)"),
    Field(("comboInvoice", "date"), r"Datum:\s*(\d{2}-\d{2}-\d{4})", _to_iso_date_dmy),
    Field(("comboInvoice", "dueDate"), r"Förfallodatum:\s*(\d{2}-\d{2}-\d{4})", _to_iso_date_dmy),

    Field(("orderPeriod", "from"), r"för perioden\s+(\d{2}\.\d{2}\.\d{4})", _to_iso_date_dot_dmy),
    Field(("orderPeriod", "to"), r"för perioden\s+\d{2}\.\d{2}\.\d{4}\s+-\s+(\d{2}\.\d{2}\.\d{4})", _to_iso_date_dot_dmy),

    Field(("selfBilling", "invoiceNo"), r"Självfaktura\s+(\S+)"),
    # `selfBilling.orders` is now a list (was single-row dict in v0.8) —
    # extracted by `_extract_orders()` so the parser captures every order
    # category that appears (Utkörningsorders + Avhämtningsorders for
    # Foodora-bar partners like Kållered).
    Field(("selfBilling", "salesExVat"),
          r"Era försäljningar exkl\. moms\s+([0-9,]+\.\d{2})\s*SEK", _to_amount),
    Field(("selfBilling", "outputVat", "rate"),
          r"Moms\s+(\d+)\s*%\s+[0-9,]+\.\d{2}\s*SEK", _to_rate),
    Field(("selfBilling", "outputVat", "amount"),
          r"Moms\s+\d+\s*%\s+([0-9,]+\.\d{2})\s*SEK", _to_amount),
    Field(("selfBilling", "totalInclVat"),
          r"Totalt \(1\)\s+([0-9,]+\.\d{2})\s*SEK", _to_amount),

    Field(("foodoraInvoice", "invoiceNo"), r"Faktura\s+(\d+-2)"),
    Field(("foodoraInvoice", "foodoraFeesExVat"),
          r"Foodoras försäljningar exkl\. moms\s+(-?[0-9,]+\.\d{2})\s*SEK", _to_amount),
    Field(("foodoraInvoice", "inputVat", "rate"),
          r"Er ingående moms\s+(\d+)\s*%", _to_rate),
    Field(("foodoraInvoice", "inputVat", "amount"),
          r"Er ingående moms\s+\d+\s*%[^\n]*?(-?[0-9,]+\.\d{2})\s*SEK", _to_amount),
    # v0.10: Faktura (2) can also carry an "Er utgående moms" line — output
    # VAT on a credit/compensation item that Foodora is paying us (e.g.
    # "Double cooking ersättning"). When present, this represents
    # compensation income we owe output VAT on. Format:
    #   "Er utgående moms 12% (111.79) 13.41 SEK"
    # where 12 = rate, 111.79 = basis (ex-VAT compensation), 13.41 = VAT.
    # Optional: not every combo-invoice has it.
    Field(("foodoraInvoice", "outputVat", "rate"),
          r"Er utgående moms\s+(\d+)\s*%", _to_rate, required=False),
    Field(("foodoraInvoice", "outputVat", "basisAmount"),
          r"Er utgående moms\s+\d+\s*%\s*\((-?[0-9,]+\.\d{2})\)", _to_amount, required=False),
    Field(("foodoraInvoice", "outputVat", "amount"),
          r"Er utgående moms\s+\d+\s*%\s*\(-?[0-9,]+\.\d{2}\)\s+(-?[0-9,]+\.\d{2})\s*SEK",
          _to_amount, required=False),
    Field(("foodoraInvoice", "totalInclVat"),
          r"Totalt \(2\)\s+(-?[0-9,]+\.\d{2})\s*SEK", _to_amount),

    Field(("settlement", "rounding"),
          r"Öresavrundning\s+(-?[0-9,]+\.\d{2})\s*SEK", _to_amount),
    Field(("settlement", "payoutAmount"),
          r"Vi betalar ut till er[^\n]*?\s+([0-9,]+\.\d{2})\s*SEK", _to_amount),
)


def _empty_data() -> dict:
    return {
        "issuer": {"name": "Foodora AB Stockholm", "orgNo": None, "vatNo": None},
        "recipient": {"name": None, "customerNo": None, "orgNo": None, "vatNo": None},
        "comboInvoice": {"invoiceNo": None, "date": None, "dueDate": None},
        "orderPeriod": {"from": None, "to": None},
        "selfBilling": {
            "invoiceNo": None,
            "orders": [],
            "contractualDiscounts": [],
            "salesExVat": None,
            "outputVat": {"rate": None, "amount": None},
            "totalInclVat": None,
        },
        "foodoraInvoice": {
            "invoiceNo": None,
            "foodoraFeesExVat": None,
            "inputVat": {"rate": None, "amount": None},
            # Optional — only set when Faktura (2) carries an "Er utgående
            # moms" line (compensation credit at our sales VAT rate).
            "outputVat": {"rate": None, "basisAmount": None, "amount": None},
            "totalInclVat": None,
        },
        "settlement": {"rounding": None, "payoutAmount": None, "currency": "SEK"},
    }


def _nested_set(d: dict, path: tuple[str, ...], value: Any) -> None:
    for key in path[:-1]:
        d = d[key]
    d[path[-1]] = value


def _extract_contractual_discounts(text: str) -> list[dict]:
    rows = []
    for m in CONTRACTUAL_DISCOUNT_ROW_RE.finditer(text):
        description, rate, quantity, base_amount, amount = m.groups()
        rows.append({
            "description": description.strip(),
            "rate": _to_rate(rate),
            "quantity": _to_int(quantity),
            "discountBasisAmount": _to_amount(base_amount),
            "amountExVat": _to_amount(amount),
        })
    return rows


def _extract_orders(text: str) -> list[dict]:
    """Each Foodora self-bill can list orders under multiple categories
    (delivery vs takeaway). Each row becomes one entry; the builder sums
    grossAmount and netAmount across all categories.
    """
    rows = []
    for m in ORDER_ROW_RE.finditer(text):
        description, quantity, gross, net = m.groups()
        rows.append({
            "description": description.strip(),
            "quantity": _to_int(quantity),
            "grossAmount": _to_amount(gross),
            "netAmount": _to_amount(net),
        })
    return rows


def _parse_text(text: str) -> tuple[dict, list[str]]:
    data = _empty_data()
    errors: list[str] = []
    for field in FIELDS:
        m = re.search(field.pattern, text, re.MULTILINE)
        if m is None:
            if field.required:
                errors.append(f"missing: {'.'.join(field.path)}")
            continue
        try:
            value = field.transform(m.group(1).strip())
        except (ValueError, ArithmeticError) as e:
            errors.append(f"parse_error: {'.'.join(field.path)} ({e})")
            continue
        _nested_set(data, field.path, value)

    data["selfBilling"]["orders"] = _extract_orders(text)
    if not data["selfBilling"]["orders"]:
        errors.append("missing: selfBilling.orders")

    data["selfBilling"]["contractualDiscounts"] = _extract_contractual_discounts(text)
    if not data["selfBilling"]["contractualDiscounts"]:
        errors.append("missing: selfBilling.contractualDiscounts")

    return data, errors


def parse(source: SupportingDoc) -> dict:
    """Parse one Foodora combo-invoice PDF. Returns {data, errors, diagnostics}.

    `source` may be a filesystem Path/str (dev/test convenience), raw bytes, or
    a binary file-like object (production path — files arrive from `ifn files
    fetch` as bytes/streams, not as filesystem paths).

    Page-1 fast path; if any required fields are missing, retry with up to
    MAX_RETRY_PAGES pages concatenated.
    """
    if isinstance(source, bytes):
        source = BytesIO(source)
    with pdfplumber.open(source) as pdf:
        total_pages = len(pdf.pages)
        text = pdf.pages[0].extract_text() or ""
        data, errors = _parse_text(text)
        pages_scanned = 1

        if errors and total_pages > 1:
            n = min(MAX_RETRY_PAGES, total_pages)
            text = "\n".join((pdf.pages[i].extract_text() or "") for i in range(n))
            data, errors = _parse_text(text)
            pages_scanned = n

    return {
        "data": data,
        "errors": errors,
        # Format-specific telemetry — PDF-only, optional per the bko.ParseResult
        # contract. The audit-PDF generator reads pagesScanned to decide how
        # many summary pages of the source PDF to embed in each review spread.
        "diagnostics": {"pagesScanned": pages_scanned},
    }


# Deprecated alias — kept temporarily for any external caller pinned to the
# old name. New code should use `parse()` (the bko.Parser contract).
parse_invoice = parse


def _count_leaves(d: Any) -> tuple[int, int]:
    if isinstance(d, dict):
        totals = [_count_leaves(v) for v in d.values()]
        return sum(t for t, _ in totals), sum(m for _, m in totals)
    if isinstance(d, list):
        totals = [_count_leaves(v) for v in d]
        return sum(t for t, _ in totals), sum(m for _, m in totals)
    return 1, (1 if d is None else 0)


def run_batch(input_path: Path, out_path: Path) -> dict:
    if input_path.is_file():
        pdfs = [input_path]
    else:
        pdfs = sorted(p for p in input_path.iterdir() if p.suffix.lower() == ".pdf")

    started = datetime.now(timezone.utc).replace(microsecond=0)
    t0 = time.perf_counter()

    files: dict = {}
    total_fields = 0
    total_missing = 0
    total_errors = 0
    files_fully_parsed = 0
    files_retried = 0

    for pdf in pdfs:
        file_t0 = time.perf_counter()
        result = parse(pdf)
        duration_ms = round((time.perf_counter() - file_t0) * 1000, 2)

        n_fields, n_missing = _count_leaves(result["data"])
        n_errors = len(result["errors"])

        total_fields += n_fields
        total_missing += n_missing
        total_errors += n_errors
        if n_errors == 0:
            files_fully_parsed += 1
        pages_scanned = (result.get("diagnostics") or {}).get("pagesScanned", 1)
        if pages_scanned > 1:
            files_retried += 1

        files[pdf.name] = {
            "parseDurationMs": duration_ms,
            "pagesScanned": pages_scanned,
            "fieldScore": f"{n_fields - n_missing}/{n_fields}",
            "errors": result["errors"],
            "data": result["data"],
        }

    total_ms = round((time.perf_counter() - t0) * 1000, 2)

    root = {
        "parserVersion": PARSER_VERSION,
        "meta": {
            "runStartedAt": started.isoformat().replace("+00:00", "Z"),
            "totalDurationMs": total_ms,
            "inputPath": str(input_path),
        },
        "score": {
            "filesProcessed": len(pdfs),
            "filesFullyParsed": files_fully_parsed,
            "filesRetried": files_retried,
            "fieldsExtracted": total_fields - total_missing,
            "fieldsMissing": total_missing,
            "errorCount": total_errors,
        },
        "files": files,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(root, ensure_ascii=False, indent=2) + "\n")
    return root


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Parse Foodora combo-invoice PDFs.")
    parser.add_argument("path", nargs="?", default="dev-data/FoodoraComboInvoice_FileSamples",
                        help="PDF file or directory (default: dev-data/FoodoraComboInvoice_FileSamples)")
    parser.add_argument("--out", default=None,
                        help=f"Output JSON path (default: dev-data/test-runs/foodora_combo_invoice-{PARSER_VERSION}.json)")
    args = parser.parse_args(argv)

    input_path = Path(args.path)
    if not input_path.exists():
        print(f"error: path not found: {input_path}", file=sys.stderr)
        return 2

    out_path = Path(args.out) if args.out else Path("dev-data/test-runs") / f"foodora_combo_invoice-{PARSER_VERSION}.json"
    root = run_batch(input_path, out_path)

    s = root["score"]
    print(
        f"{s['filesFullyParsed']}/{s['filesProcessed']} filer, "
        f"{s['fieldsExtracted']}/{s['fieldsExtracted'] + s['fieldsMissing']} fält, "
        f"{s['errorCount']} fel  ->  {out_path}",
        file=sys.stderr,
    )
    return 0 if s["errorCount"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

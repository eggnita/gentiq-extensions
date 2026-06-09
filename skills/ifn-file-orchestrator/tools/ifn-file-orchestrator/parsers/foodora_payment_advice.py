"""Foodora Payment Advice parser.

A Payment Advice ("Payment Advice Note from <DD.MM.YYYY>.PDF") is Foodora's
statement of intent to pay. It references the combo-invoice number, the
payout date and amount, and identifies the recipient + sender. Under the
SPLIT booking pattern (v0.9+, see `FoodoraPaymentAdvice_BookingRules.md`),
Payment Advices do NOT produce their own BKO — they get attached, via CLI
lookup, to the cash-arrival voucher the ERP's bank integration creates.

The triage rule routes PA files here with strategy
`parse_and_attach_to_voucher` and `attach_lookup_keys=("comboInvoice.invoiceNo",)`.
The orchestrator expects this parser to return enough parsed data to
populate those lookup keys; everything else is informational.

--------------------------------------------------------------------------
Output schema
--------------------------------------------------------------------------
`parse()` returns `{data, errors, diagnostics}` where `data` carries:

    issuer:
      name           "Foodora AB" (always)
      address[]      ["Fleminggatan 20", "SE-112 26 Stockholm"]
      vatNo          "SE559007564301"
      bankgiro       "5462-0000"
      email          "partner@foodora.se"
    recipient:
      name           legal entity, e.g. "Brödernas Hudiksvall AB"
      tradeName      optional informal name on the PA (when present)
      address[]      street, postal+city lines
      orgNo          Swedish org no with SE prefix
      customerNo     Foodora's internal customer account no for this partner
    documentType     "Betalningsbekräftelse" — pure payment-intent declaration
    documentNumber   12-digit Foodora-internal document number
    partnerId        4-char alphanumeric (Foodora's partner identifier)
    paymentDate      ISO date — when Foodora intends to release the funds
    payments[]:                              # one or more, single in the corpus today
      comboInvoiceNo  10-digit "70..." reference
      invoiceDate     ISO date of the referenced invoice
      currency        ISO 4217
      amount          float (SEK)
    totals:
      totalAmount   {currency, amount}    # "Totalt belopp"
      paidAmount    {currency, amount}    # "Betalt belopp"
    comboInvoice:
      invoiceNo     mirror of payments[0].comboInvoiceNo — the lookup key
                    named in triage's attach_lookup_keys=("comboInvoice.invoiceNo",)
    attachCriteria:                          # SEE FoodoraPaymentAdvice_BookingRules.md §Attach criteria
      voucherRows:    [{Account, Side, Amount}, ...]   exact rows the target voucher must contain
      exactAmountMatch: true                 attach only on an exact öre-level match (no tolerance)
      transactionDateWindow:
        expected         ISO date — paymentDate
        earlierBusinessDays  integer — how many BUSINESS days before `expected` are acceptable
        laterBusinessDays    integer — how many BUSINESS days after `expected` are acceptable
      ifNoMatch       "notify_accountant"    fallback policy (orchestrator-implemented, not yet wired)

Import:
    from parsers.foodora_payment_advice import parse, PARSER_VERSION
"""
from __future__ import annotations

import re
from io import BytesIO
from typing import Any

import pdfplumber

from bko import SupportingDoc

PARSER_VERSION = "v0.2-attach-criteria"

EXPECTED_DOC_TYPE = "Betalningsbekräftelse"

# Foodora's own issuer data is fixed across the corpus; we extract it from
# the document so a future divergence (new issuer entity, new bankgiro)
# surfaces as a parsed value rather than a silent assumption.
_RE_VAT_ID = re.compile(r"VAT ID:\s*(\S+)")
_RE_BANKGIRO = re.compile(r"Bankgiro:\s*([\d-]+)")
_RE_EMAIL = re.compile(r"E-mail:\s*(\S+@\S+)")

# Document-level metadata. Some labels share a printed line (Partner ID and
# Betalningdatum); the regexes are anchored on each label individually so
# layout shifts are tolerated.
_RE_PARTNER_ID = re.compile(r"Partner ID:\s*([A-Z0-9]+)\b")
_RE_PAYMENT_DATE = re.compile(r"Betalningdatum:\s*(\d{2}\.\d{2}\.\d{4})")
_RE_DOC_NUMBER = re.compile(r"Dokumentnummer:\s*(\d+)")

# Recipient block markers.
_RE_RECIPIENT_VAT = re.compile(r"VAT-nummer:\s*(\S+)")
_RE_RECIPIENT_KONTO = re.compile(r"Kontonummer:\s*(\d+)")

# Payment table: one or more rows under the column header
# `Fakturanummer  Datum  Valuta  Belopp`. Anchored on the 10-digit
# 70xxxxxxxx invoice number which is unique to this row type.
_RE_PAYMENT_LINE = re.compile(
    r"^\s*(7\d{9})\s+(\d{2}\.\d{2}\.\d{4})\s+([A-Z]{3})\s+([\d\s ,]+)\s*$",
    re.M,
)
_RE_TOTAL_AMOUNT = re.compile(
    r"^\s*Totalt belopp\s+([A-Z]{3})\s+([\d\s ,]+)\s*$", re.M
)
_RE_PAID_AMOUNT = re.compile(
    r"^\s*Betalt belopp\s+([A-Z]{3})\s+([\d\s ,]+)\s*$", re.M
)


def _iso_date(dmy: str) -> str:
    """`02.09.2025` -> `2025-09-02`. Callers pass already-validated input."""
    dd, mm, yyyy = dmy.split(".")
    return f"{yyyy}-{mm}-{dd}"


def _sek_amount(s: str) -> float:
    """`19 455,20` (with normal or non-breaking spaces) -> 19455.20."""
    return float(s.replace(" ", "").replace(" ", "").replace(",", "."))


def _extract_recipient(text: str) -> dict:
    """The recipient block sits between `PARTNER` and `Betalningsbekräftelse`.
    Layout: legal name, (optional) trade name, address line(s), VAT-nummer,
    Kontonummer."""
    m = re.search(r"PARTNER\s*\n(.+?)Betalningsbekräftelse", text, flags=re.S)
    if not m:
        return {}
    block = m.group(1)
    lines = [ln.strip() for ln in block.splitlines() if ln.strip()]
    if not lines:
        return {}

    out: dict[str, Any] = {"name": lines[0]}

    # Address lines = everything between line 1 and the first VAT-nummer line.
    addr_lines: list[str] = []
    for ln in lines[1:]:
        if ln.startswith("VAT-nummer") or ln.startswith("Kontonummer"):
            break
        addr_lines.append(ln)

    # Heuristic: a leading line with no digits is a trade name (informal name
    # printed without the `AB` suffix), not part of the postal address.
    if addr_lines and not any(c.isdigit() for c in addr_lines[0]):
        out["tradeName"] = addr_lines[0]
        addr_lines = addr_lines[1:]
    if addr_lines:
        out["address"] = addr_lines

    if vm := _RE_RECIPIENT_VAT.search(block):
        out["orgNo"] = vm.group(1)
    if km := _RE_RECIPIENT_KONTO.search(block):
        out["customerNo"] = km.group(1)

    return out


def _parse_text(text: str) -> tuple[dict, list[str]]:
    errors: list[str] = []
    data: dict[str, Any] = {}

    # --- issuer (always Foodora; we extract verbatim to detect future drift)
    issuer: dict[str, Any] = {"name": "Foodora AB"}
    # Issuer address: the first two non-Foodora-name lines under the issuer block.
    head = text.split("PARTNER", 1)[0]
    head_lines = [ln.strip() for ln in head.splitlines() if ln.strip()]
    addr: list[str] = []
    for ln in head_lines[1:]:  # skip "Foodora AB"
        if ln.startswith(("VAT ID:", "Bankgiro:", "E-mail:")):
            break
        addr.append(ln)
    if addr:
        issuer["address"] = addr
    if vm := _RE_VAT_ID.search(text):
        issuer["vatNo"] = vm.group(1)
    if bm := _RE_BANKGIRO.search(text):
        issuer["bankgiro"] = bm.group(1)
    if em := _RE_EMAIL.search(text):
        issuer["email"] = em.group(1)
    data["issuer"] = issuer

    # --- recipient
    recipient = _extract_recipient(text)
    if not recipient:
        errors.append("recipient block (PARTNER ... Betalningsbekräftelse) not found")
    data["recipient"] = recipient

    # --- document type — a Payment Advice is by name a pure payment-intent
    # declaration ("Betalningsbekräftelse"). If that marker is missing we
    # have something else and the attach workflow must not proceed.
    if EXPECTED_DOC_TYPE in text:
        data["documentType"] = EXPECTED_DOC_TYPE
    else:
        errors.append(f"document type marker '{EXPECTED_DOC_TYPE}' not found")

    # --- document metadata
    if pm := _RE_PARTNER_ID.search(text):
        data["partnerId"] = pm.group(1)
    else:
        errors.append("partnerId not found")
    if dm := _RE_DOC_NUMBER.search(text):
        data["documentNumber"] = dm.group(1)
    else:
        errors.append("documentNumber not found")
    if bdm := _RE_PAYMENT_DATE.search(text):
        data["paymentDate"] = _iso_date(bdm.group(1))
    else:
        errors.append("paymentDate (Betalningdatum) not found")

    # --- payment lines (one or more)
    payments: list[dict[str, Any]] = []
    for m in _RE_PAYMENT_LINE.finditer(text):
        payments.append({
            "comboInvoiceNo": m.group(1),
            "invoiceDate": _iso_date(m.group(2)),
            "currency": m.group(3),
            "amount": _sek_amount(m.group(4)),
        })
    data["payments"] = payments
    if not payments:
        errors.append("no payment lines found under Fakturanummer/Datum/Valuta/Belopp")

    # --- totals (sanity-check fields for the attach step)
    totals: dict[str, Any] = {}
    if tm := _RE_TOTAL_AMOUNT.search(text):
        totals["totalAmount"] = {"currency": tm.group(1), "amount": _sek_amount(tm.group(2))}
    if pm := _RE_PAID_AMOUNT.search(text):
        totals["paidAmount"] = {"currency": pm.group(1), "amount": _sek_amount(pm.group(2))}
    if totals:
        data["totals"] = totals

    # --- convenience field for triage's attach_lookup_keys.
    # When multi-invoice PAs appear (not yet seen in the corpus), the
    # attach strategy will need to enumerate `payments[*].comboInvoiceNo`
    # instead of the single key here. For today's single-invoice PAs the
    # mirror keeps the attach contract simple.
    if payments:
        data["comboInvoice"] = {"invoiceNo": payments[0]["comboInvoiceNo"]}

    # --- attach criteria — see FoodoraPaymentAdvice_BookingRules.md.
    # The PA describes a payout. Under SPLIT, the ERP's bank integration will
    # create a cash-clearing voucher when the actual bank transaction lands.
    # The PA should be attached to that voucher. We pre-compute the criteria
    # the orchestrator can match against, so attach decisions don't require
    # the orchestrator to re-derive policy from raw PA fields.
    #
    # Date window is in BUSINESS DAYS, not calendar days — the orchestrator
    # resolves to a concrete ISO bound against its holiday calendar.
    # Rationale: -1 covers a same-week early settle; +2 covers weekend +
    # one business-day delay common with SEPA-style transfers.
    paid = (totals.get("paidAmount") or {}).get("amount") if totals else None
    paid_currency = (totals.get("paidAmount") or {}).get("currency") if totals else None
    if paid is not None and data.get("paymentDate"):
        data["attachCriteria"] = {
            "voucherRows": [
                {"Account": 1930, "Side": "D",
                 "Amount": paid, "Currency": paid_currency},
                {"Account": 1584, "Side": "K",
                 "Amount": paid, "Currency": paid_currency},
            ],
            "exactAmountMatch": True,
            "transactionDateWindow": {
                "expected": data["paymentDate"],
                "earlierBusinessDays": 1,
                "laterBusinessDays": 2,
            },
            "ifNoMatch": "notify_accountant",
        }

    return data, errors


def parse(source: SupportingDoc) -> dict[str, Any]:
    """Parse one Foodora Payment Advice PDF. Returns {data, errors, diagnostics}.

    `source` may be a filesystem Path/str (dev/test convenience), raw bytes,
    or a binary file-like object (production path — files arrive from
    `ifn files fetch` as bytes/streams, not as filesystem paths)."""
    if isinstance(source, bytes):
        source = BytesIO(source)
    with pdfplumber.open(source) as pdf:
        pages_scanned = len(pdf.pages)
        text = "\n".join((p.extract_text() or "") for p in pdf.pages)

    data, errors = _parse_text(text)
    return {
        "data": data,
        "errors": errors,
        "diagnostics": {"pagesScanned": pages_scanned},
    }

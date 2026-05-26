#!/usr/bin/env python3
"""Account mapping v2 — load, save, resolve, migrate.

Storage: ~/.ifn/booking-templates/<partner>.json
Format: {"version": 2, "defaults": {...}, "companies": {...}}
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path

TEMPLATES_DIR = Path.home() / ".ifn" / "booking-templates"

# Canonical key set
STANDARD_KEYS = [
    "receivable", "fees", "input_vat", "output_vat_6",
    "bank", "rounding",
    "correction_6", "correction_12", "correction_25",
]

# V1 → V2 key renames
V1_KEY_MAP = {
    "receivable_clear": "receivable",
    "bank_payout": "bank",
    "commission": "fees",
    "partner_charges": "fees",
}


def resolve(mapping, company_id, key, fallback=None):
    """Get effective account number for a company + key."""
    company = mapping.get("companies", {}).get(company_id, {})
    override = company.get("overrides", {}).get(key)
    if override:
        return override["account"]
    default = mapping.get("defaults", {}).get(key)
    if default:
        return default["account"]
    return fallback


def resolve_side(mapping, company_id, key, fallback="debit"):
    """Get effective side (debit/credit) for a company + key."""
    company = mapping.get("companies", {}).get(company_id, {})
    override = company.get("overrides", {}).get(key)
    if override and "side" in override:
        return override["side"]
    default = mapping.get("defaults", {}).get(key)
    if default and "side" in default:
        return default["side"]
    return fallback


def get_effective(mapping, company_id):
    """Return flat dict of all effective accounts for a company."""
    result = {}
    for key, default in mapping.get("defaults", {}).items():
        result[key] = {"account": default["account"], "side": default.get("side", "debit")}
    company = mapping.get("companies", {}).get(company_id, {})
    for key, override in company.get("overrides", {}).items():
        result[key] = {"account": override["account"], "side": override.get("side", result.get(key, {}).get("side", "debit"))}
    return result


def is_confirmed(mapping, company_id):
    """Check if mapping is confirmed for a company."""
    company = mapping.get("companies", {}).get(company_id, {})
    return company.get("confirmed", False)


def load(partner):
    """Load mapping file. Auto-migrates v1 → v2."""
    path = TEMPLATES_DIR / f"{partner}.json"
    if not path.exists():
        return None
    with open(path) as f:
        data = json.load(f)
    if data.get("version") != 2:
        data = migrate_v1(data)
        save(partner, data)
    return data


def save(partner, mapping):
    """Write mapping file."""
    TEMPLATES_DIR.mkdir(parents=True, exist_ok=True)
    mapping["updated_at"] = datetime.now(timezone.utc).isoformat()
    path = TEMPLATES_DIR / f"{partner}.json"
    with open(path, "w") as f:
        json.dump(mapping, f, indent=2, ensure_ascii=False)


def migrate_v1(v1):
    """Convert v1 template to v2 format."""
    old_mapping = v1.get("mapping", {})
    defaults = {}
    for old_key, value in old_mapping.items():
        new_key = V1_KEY_MAP.get(old_key, old_key)
        if new_key not in defaults:
            defaults[new_key] = {
                "account": value["account"],
                "side": value.get("side", "debit"),
            }
    return {
        "partner": v1.get("partner", ""),
        "version": 2,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "defaults": defaults,
        "companies": {},
    }


def set_override(mapping, company_id, company_name, key, account, note=""):
    """Set an account override for a company."""
    if "companies" not in mapping:
        mapping["companies"] = {}
    if company_id not in mapping["companies"]:
        mapping["companies"][company_id] = {
            "name": company_name,
            "confirmed": False,
            "overrides": {},
        }
    override = {"account": account}
    if note:
        override["note"] = note
    mapping["companies"][company_id]["overrides"][key] = override
    return mapping


def confirm(mapping, company_id, company_name=""):
    """Mark a company's mapping as confirmed."""
    if "companies" not in mapping:
        mapping["companies"] = {}
    if company_id not in mapping["companies"]:
        mapping["companies"][company_id] = {
            "name": company_name,
            "confirmed": False,
            "overrides": {},
        }
    mapping["companies"][company_id]["confirmed"] = True
    mapping["companies"][company_id]["confirmed_at"] = datetime.now(timezone.utc).isoformat()
    if company_name:
        mapping["companies"][company_id]["name"] = company_name
    return mapping


def reset_overrides(mapping, company_id):
    """Remove all overrides for a company."""
    company = mapping.get("companies", {}).get(company_id)
    if company:
        company["overrides"] = {}
        company["confirmed"] = False
    return mapping


def new_mapping(partner):
    """Create an empty v2 mapping."""
    return {
        "partner": partner,
        "version": 2,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "defaults": {},
        "companies": {},
    }

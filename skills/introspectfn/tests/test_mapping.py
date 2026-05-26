"""Tests for account mapping v2 library."""

import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "tools" / "settlement-cli" / "lib"))

from mapping import (
    resolve, resolve_side, get_effective, is_confirmed,
    load, save, migrate_v1, set_override, confirm,
    reset_overrides, new_mapping, TEMPLATES_DIR,
)


# --- resolve ---

def test_resolve_returns_default():
    m = {"version": 2, "defaults": {"receivable": {"account": 1584, "side": "credit"}}, "companies": {}}
    assert resolve(m, "company-abc", "receivable") == 1584


def test_resolve_returns_override():
    m = {
        "version": 2,
        "defaults": {"receivable": {"account": 1584, "side": "credit"}},
        "companies": {
            "company-abc": {"overrides": {"receivable": {"account": 1585}}}
        },
    }
    assert resolve(m, "company-abc", "receivable") == 1585


def test_resolve_override_doesnt_affect_other_company():
    m = {
        "version": 2,
        "defaults": {"receivable": {"account": 1584, "side": "credit"}},
        "companies": {
            "company-abc": {"overrides": {"receivable": {"account": 1585}}}
        },
    }
    assert resolve(m, "company-xyz", "receivable") == 1584


def test_resolve_returns_fallback_for_unknown_key():
    m = {"version": 2, "defaults": {}, "companies": {}}
    assert resolve(m, "company-abc", "receivable", fallback=9999) == 9999


def test_resolve_returns_none_without_fallback():
    m = {"version": 2, "defaults": {}, "companies": {}}
    assert resolve(m, "company-abc", "receivable") is None


# --- get_effective ---

def test_get_effective_merges_defaults_and_overrides():
    m = {
        "version": 2,
        "defaults": {
            "receivable": {"account": 1584, "side": "credit"},
            "fees": {"account": 6044, "side": "debit"},
            "bank": {"account": 1930, "side": "debit"},
        },
        "companies": {
            "co-1": {"overrides": {"receivable": {"account": 1585}}}
        },
    }
    eff = get_effective(m, "co-1")
    assert eff["receivable"]["account"] == 1585  # override
    assert eff["fees"]["account"] == 6044  # default
    assert eff["bank"]["account"] == 1930  # default


# --- is_confirmed ---

def test_is_confirmed_true():
    m = {"companies": {"co-1": {"confirmed": True}}}
    assert is_confirmed(m, "co-1") is True


def test_is_confirmed_false_when_missing():
    m = {"companies": {}}
    assert is_confirmed(m, "co-1") is False


def test_is_confirmed_false_when_not_set():
    m = {"companies": {"co-1": {"confirmed": False, "overrides": {}}}}
    assert is_confirmed(m, "co-1") is False


# --- migrate_v1 ---

def test_migrate_v1_converts_keys():
    v1 = {
        "partner": "foodora",
        "mapping": {
            "receivable_clear": {"account": 1584, "side": "credit"},
            "bank_payout": {"account": 1930, "side": "debit"},
            "commission": {"account": 6044, "side": "debit"},
            "input_vat": {"account": 2640, "side": "debit"},
            "rounding": {"account": 3740, "side": "debit"},
        },
    }
    v2 = migrate_v1(v1)
    assert v2["version"] == 2
    assert v2["partner"] == "foodora"
    assert v2["defaults"]["receivable"]["account"] == 1584
    assert v2["defaults"]["bank"]["account"] == 1930
    assert v2["defaults"]["fees"]["account"] == 6044
    assert "receivable_clear" not in v2["defaults"]
    assert "bank_payout" not in v2["defaults"]
    assert v2["companies"] == {}


def test_migrate_v1_preserves_unmapped_keys():
    v1 = {
        "partner": "wolt",
        "mapping": {
            "output_vat_6": {"account": 2630, "side": "credit"},
        },
    }
    v2 = migrate_v1(v1)
    assert v2["defaults"]["output_vat_6"]["account"] == 2630


# --- set_override ---

def test_set_override_creates_company():
    m = new_mapping("foodora")
    set_override(m, "co-1", "Test AB", "receivable", 1585, note="Custom")
    assert m["companies"]["co-1"]["overrides"]["receivable"]["account"] == 1585
    assert m["companies"]["co-1"]["overrides"]["receivable"]["note"] == "Custom"
    assert m["companies"]["co-1"]["name"] == "Test AB"
    assert m["companies"]["co-1"]["confirmed"] is False


def test_set_override_preserves_existing_overrides():
    m = new_mapping("foodora")
    set_override(m, "co-1", "Test AB", "receivable", 1585)
    set_override(m, "co-1", "Test AB", "fees", 6590)
    assert m["companies"]["co-1"]["overrides"]["receivable"]["account"] == 1585
    assert m["companies"]["co-1"]["overrides"]["fees"]["account"] == 6590


# --- confirm ---

def test_confirm_sets_true():
    m = new_mapping("foodora")
    confirm(m, "co-1", "Test AB")
    assert m["companies"]["co-1"]["confirmed"] is True
    assert "confirmed_at" in m["companies"]["co-1"]


def test_confirm_preserves_overrides():
    m = new_mapping("foodora")
    set_override(m, "co-1", "Test AB", "receivable", 1585)
    confirm(m, "co-1", "Test AB")
    assert m["companies"]["co-1"]["overrides"]["receivable"]["account"] == 1585
    assert m["companies"]["co-1"]["confirmed"] is True


# --- reset_overrides ---

def test_reset_clears_overrides_and_confirmation():
    m = new_mapping("foodora")
    set_override(m, "co-1", "Test AB", "receivable", 1585)
    confirm(m, "co-1")
    reset_overrides(m, "co-1")
    assert m["companies"]["co-1"]["overrides"] == {}
    assert m["companies"]["co-1"]["confirmed"] is False


# --- load / save round-trip ---

def test_save_and_load_round_trip():
    import mapping as mod
    old_dir = mod.TEMPLATES_DIR
    try:
        with tempfile.TemporaryDirectory() as tmp:
            mod.TEMPLATES_DIR = Path(tmp)
            m = new_mapping("foodora")
            m["defaults"]["receivable"] = {"account": 1584, "side": "credit"}
            confirm(m, "co-1", "Test AB")
            save("foodora", m)
            loaded = load("foodora")
            assert loaded["version"] == 2
            assert loaded["defaults"]["receivable"]["account"] == 1584
            assert is_confirmed(loaded, "co-1") is True
    finally:
        mod.TEMPLATES_DIR = old_dir


def test_load_auto_migrates_v1():
    import mapping as mod
    old_dir = mod.TEMPLATES_DIR
    try:
        with tempfile.TemporaryDirectory() as tmp:
            mod.TEMPLATES_DIR = Path(tmp)
            v1 = {"partner": "foodora", "mapping": {"receivable_clear": {"account": 1584, "side": "credit"}}}
            with open(Path(tmp) / "foodora.json", "w") as f:
                json.dump(v1, f)
            loaded = load("foodora")
            assert loaded["version"] == 2
            assert loaded["defaults"]["receivable"]["account"] == 1584
    finally:
        mod.TEMPLATES_DIR = old_dir


def test_load_returns_none_if_missing():
    import mapping as mod
    old_dir = mod.TEMPLATES_DIR
    try:
        with tempfile.TemporaryDirectory() as tmp:
            mod.TEMPLATES_DIR = Path(tmp)
            assert load("nonexistent") is None
    finally:
        mod.TEMPLATES_DIR = old_dir


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS: {t.__name__}")

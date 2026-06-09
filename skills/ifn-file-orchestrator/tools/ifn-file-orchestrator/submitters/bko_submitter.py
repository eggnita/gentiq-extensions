"""IFN-side BKO submission — wraps `ifn bko propose`.

Single responsibility: take a fully-built BKO dict and stage it via the
IFN CLI. Everything else (deciding whether to submit, computing the
BKO, building `command.attachments.file_refs`) lives upstream in the
orchestrator.

API:
    submit(bko: dict, company_id: str) -> dict

Returns a status dict the orchestrator can append as a trail segment:
    { status: "ok" | "failed",
      bko_id: int | None,        (when ok)
      error: str | None,         (when failed)
      cli: str,                  (the exact command invoked, for audit)
      response_summary: dict     (raw CLI JSON output, when parseable) }
"""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

IFN = "/Users/tedakerlund/Documents/Projects/gentiq-extensions/skills/introspectfn/tools/ifn"


def submit(bko: dict, company_id: str, *, timeout: int = 60) -> dict:
    """Stage a BKO via `ifn bko propose <cid> <json_file>`.

    The CLI takes the BKO body as a file path, so we write it to a
    temp file and clean up afterwards. Errors are returned in-band —
    we never raise from here, so the orchestrator can record the
    failure as a trail segment and move on to the next file."""
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, encoding="utf-8",
    ) as tf:
        json.dump(bko, tf, ensure_ascii=False)
        tmp_path = tf.name
    cmd = [IFN, "bko", "propose", company_id, tmp_path]
    cli_str = " ".join(cmd)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if r.returncode != 0:
            return {
                "status": "failed",
                "error": r.stderr.strip() or f"non-zero exit ({r.returncode})",
                "cli": cli_str,
                "response_summary": None,
            }
        try:
            payload = json.loads(r.stdout)
        except json.JSONDecodeError:
            payload = {"_raw": r.stdout.strip()[:400]}
        # Wire shape v2 response: {"bko": {identity, command, trust,
        # provenance, lifecycle, groups}}. The integer id lives on
        # bko.identity.id; trust.confidence is echoed back so we can
        # catch server-side casts (we've seen float32 roundoff:
        # 0.99 round-trips as 0.9900000095367432).
        bko_id = None
        confidence_acknowledged = None
        if isinstance(payload, dict):
            outer = payload.get("bko") if isinstance(payload.get("bko"), dict) else payload
            identity = outer.get("identity") if isinstance(outer.get("identity"), dict) else {}
            trust = outer.get("trust") if isinstance(outer.get("trust"), dict) else {}
            bko_id = identity.get("id") or outer.get("id") or payload.get("bko_id")
            confidence_acknowledged = trust.get("confidence")
        return {
            "status": "ok",
            "bko_id": bko_id,
            "confidence_acknowledged": confidence_acknowledged,
            "error": None,
            "cli": cli_str,
            "response_summary": payload,
        }
    except Exception as e:
        return {
            "status": "failed",
            "error": f"{type(e).__name__}: {e}",
            "cli": cli_str,
            "response_summary": None,
        }
    finally:
        Path(tmp_path).unlink(missing_ok=True)

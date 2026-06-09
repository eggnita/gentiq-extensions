"""IFN-side file metadata write — wraps `ifn files metadata`.

Single responsibility: write the (category, group_id, details) triple
onto a file in IFN. Everything else (deciding what to write, computing
the details JSON) lives upstream in the orchestrator.

API:
    write(company_id: str, file_id: str,
          category: str | None = None,
          group_id: str | None = None,
          details: dict | None = None) -> dict
"""
from __future__ import annotations

import json
import subprocess
from typing import Any

IFN = "/Users/tedakerlund/Documents/Projects/gentiq-extensions/skills/introspectfn/tools/ifn"


def write(company_id: str, file_id: str, *,
          category: str | None = None,
          group_id: str | None = None,
          details: dict | None = None,
          timeout: int = 30) -> dict:
    """Write metadata via `ifn files metadata <cid> <file_id> [opts] --json`.

    All three fields are optional — pass only what you mean to set.
    `details` is serialised to compact JSON on the wire. Returns a
    status dict the orchestrator appends as a trail segment."""
    cmd = [IFN, "files", "metadata", company_id, file_id]
    if category:
        cmd += ["--category", category]
    if group_id:
        cmd += ["--group-id", group_id]
    if details is not None:
        # Send as raw JSON. The IFN-CLI's `_files_metadata` inlines the
        # `--details` value directly into the request body (no
        # quote-wrapping) so the value is stored as a structured JSON
        # object on the IFN side rather than a stringified blob.
        cmd += ["--details", json.dumps(details, ensure_ascii=False)]
    cmd += ["--json"]
    cli_str = " ".join(cmd[:5]) + " [+ category/group/details]"  # don't log the JSON blob

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
            payload = json.loads(r.stdout) if r.stdout.strip() else None
        except json.JSONDecodeError:
            payload = {"_raw": r.stdout.strip()[:400]}
        return {
            "status": "ok",
            "error": None,
            "cli": cli_str,
            "response_summary": payload,
            "wrote_fields": [k for k in ("category", "group_id", "details")
                             if locals().get(k) is not None],
        }
    except Exception as e:
        return {
            "status": "failed",
            "error": f"{type(e).__name__}: {e}",
            "cli": cli_str,
            "response_summary": None,
        }

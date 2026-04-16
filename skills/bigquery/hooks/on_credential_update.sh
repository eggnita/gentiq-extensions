#!/usr/bin/env bash
# on_credential_update.sh — Re-write credentials and re-verify on credential update
# Lifecycle: on_credential_update
#
# Same logic as on_setup_complete — re-persist SA JSON and verify.
#
# Output: {"ok": bool, "project": "...", "sa_email": "..."}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Delegate to on_setup_complete (identical logic)
exec "${SCRIPT_DIR}/on_setup_complete.sh"

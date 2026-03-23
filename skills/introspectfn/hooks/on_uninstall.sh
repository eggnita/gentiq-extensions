#!/usr/bin/env bash
# on_uninstall.sh — Cleanup on skill removal
# Lifecycle: on_uninstall
# Output: {"ok": true}
set -euo pipefail

# No server-side cleanup needed — credentials are managed by GentiqOS
jq -n '{ok: true}'

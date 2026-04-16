#!/usr/bin/env bash
# on_uninstall.sh — Cleanup on skill removal
# Lifecycle: on_uninstall
# Output: {"ok": true}
set -euo pipefail

# Remove credentials, config, and token cache
rm -rf "${HOME}/.config/gent-bq"

# Remove bq-tool symlink
rm -f "${HOME}/bin/bq-tool"

jq -n '{ok: true}'

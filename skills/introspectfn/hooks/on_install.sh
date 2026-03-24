#!/usr/bin/env bash
# on_install.sh — Validate environment after skill installation
# Lifecycle: on_install
# Output: {"ok": bool}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

errors=()

# Check that the ifn tool exists and is executable
if [ ! -x "${SKILL_ROOT}/tools/ifn" ]; then
    errors+=("ifn tool not found or not executable")
fi

# Check that required libraries exist
for lib in config.sh lib/http.sh lib/format.sh; do
    if [ ! -f "${SKILL_ROOT}/tools/ifn-cli/${lib}" ]; then
        errors+=("missing library: tools/ifn-cli/${lib}")
    fi
done

# Check that curl and jq are available
command -v curl >/dev/null 2>&1 || errors+=("curl not installed")
command -v jq >/dev/null 2>&1 || errors+=("jq not installed")

if [ ${#errors[@]} -eq 0 ]; then
    # Make ifn available in PATH via ~/bin symlink
    mkdir -p "${HOME}/bin"
    ln -sf "${SKILL_ROOT}/tools/ifn" "${HOME}/bin/ifn"
    # Ensure ~/bin is in PATH for future shells
    if ! grep -q 'HOME/bin' "${HOME}/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "${HOME}/.bashrc"
    fi
    jq -n '{ok: true}'
else
    msg=$(printf '%s; ' "${errors[@]}")
    jq -n --arg errors "${msg%;* }" '{ok: false, errors: $errors}'
fi

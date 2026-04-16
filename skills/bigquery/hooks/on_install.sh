#!/usr/bin/env bash
# on_install.sh — Validate environment after skill installation
# Lifecycle: on_install
# Output: {"ok": bool, "errors": [...]}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

errors=()

# Check that the bq-tool exists and is executable
if [ ! -x "${SKILL_ROOT}/tools/bq-tool" ]; then
    errors+=("bq-tool not found or not executable")
fi

# Check that required libraries exist
for lib in config.sh lib/format.sh lib/auth.sh lib/http.sh lib/query.sh; do
    if [ ! -f "${SKILL_ROOT}/tools/bq-cli/${lib}" ]; then
        errors+=("missing library: tools/bq-cli/${lib}")
    fi
done

# Check that curl, jq, and openssl are available (no gcloud/bq needed)
command -v curl >/dev/null 2>&1 || errors+=("curl not installed")
command -v jq >/dev/null 2>&1 || errors+=("jq not installed")
command -v openssl >/dev/null 2>&1 || errors+=("openssl not installed (needed for SA key signing)")

if [ ${#errors[@]} -eq 0 ]; then
    # Make bq-tool available in PATH via ~/bin symlink
    mkdir -p "${HOME}/bin"
    ln -sf "${SKILL_ROOT}/tools/bq-tool" "${HOME}/bin/bq-tool"
    # Ensure ~/bin is in PATH for future shells
    if ! grep -q 'HOME/bin' "${HOME}/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "${HOME}/.bashrc"
    fi
    jq -n '{ok: true}'
else
    msg=$(printf '%s; ' "${errors[@]}")
    jq -n --arg errors "${msg%;* }" '{ok: false, errors: $errors}'
fi

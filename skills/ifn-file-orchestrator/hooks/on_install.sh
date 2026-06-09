#!/usr/bin/env bash
# on_install.sh — Validate environment after ifn-file-orchestrator skill installation
# Requires: introspectfn-erp skill (provides the ifn CLI)
# Lifecycle: on_install
# Output: {"ok": bool}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLBOX="${SKILL_ROOT}/tools/ifn-file-orchestrator"

errors=()

# --- Check dependency: introspectfn-erp must be installed (ifn CLI available) ---
if ! command -v ifn >/dev/null 2>&1; then
    # Try known paths
    if [ -x "${HOME}/bin/ifn" ]; then
        : # available via ~/bin
    elif [ -x "/usr/local/bin/ifn" ]; then
        : # available via /usr/local/bin
    else
        errors+=("ifn CLI not found — install the introspectfn-erp skill first")
    fi
fi

# --- Check python3 is available ---
if ! command -v python3 >/dev/null 2>&1; then
    OS="$(uname -s)"
    case "${OS}" in
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update -qq >/dev/null 2>&1
                sudo apt-get install -y python3 python3-pip >/dev/null 2>&1 || errors+=("failed to install python3")
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y python3 python3-pip >/dev/null 2>&1 || errors+=("failed to install python3")
            fi
            ;;
        *)
            errors+=("python3 not found — required for ifn-file-orchestrator")
            ;;
    esac
fi

# --- Install pdfplumber (required by parsers) ---
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c "import pdfplumber" 2>/dev/null; then
        pip3 install --user pdfplumber >/dev/null 2>&1 \
            || pip3 install pdfplumber >/dev/null 2>&1 \
            || python3 -m pip install --user pdfplumber >/dev/null 2>&1 \
            || errors+=("failed to install pdfplumber — try: pip3 install pdfplumber")
    fi
fi

# --- Verify toolbox is present ---
if [ ! -d "${TOOLBOX}" ]; then
    errors+=("toolbox directory not found at tools/ifn-file-orchestrator/")
fi

if [ ! -f "${TOOLBOX}/triage.py" ]; then
    errors+=("triage.py not found in toolbox")
fi

if [ ! -f "${TOOLBOX}/remarks.py" ]; then
    errors+=("remarks.py not found in toolbox")
fi

if [ ! -f "${TOOLBOX}/bko.py" ]; then
    errors+=("bko.py not found in toolbox")
fi

# --- Final verification ---
if [ ${#errors[@]} -eq 0 ]; then
    # Verify pdfplumber is importable
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import pdfplumber" 2>/dev/null || errors+=("pdfplumber still not importable after install")
    fi
fi

if [ ${#errors[@]} -eq 0 ]; then
    jq -n '{ok: true}'
else
    msg=$(printf '%s; ' "${errors[@]}")
    jq -n --arg errors "${msg%;* }" '{ok: false, errors: $errors}'
fi

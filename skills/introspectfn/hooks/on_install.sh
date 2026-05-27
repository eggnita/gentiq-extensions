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
    # Make ifn available in PATH (bk is a subcommand, no separate symlink needed)
    # Use /usr/local/bin (always in PATH) with fallback to ~/bin
    if [ -w /usr/local/bin ] || sudo -n true 2>/dev/null; then
        sudo ln -sf "${SKILL_ROOT}/tools/ifn" /usr/local/bin/ifn 2>/dev/null \
            || ln -sf "${SKILL_ROOT}/tools/ifn" /usr/local/bin/ifn 2>/dev/null
    fi
    # Also create ~/bin as fallback
    mkdir -p "${HOME}/bin"
    ln -sf "${SKILL_ROOT}/tools/ifn" "${HOME}/bin/ifn"
    # Clean up old standalone settlement symlink if present
    rm -f "${HOME}/bin/settlement" 2>/dev/null
    sudo rm -f /usr/local/bin/settlement 2>/dev/null || true
    if ! grep -q 'HOME/bin' "${HOME}/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "${HOME}/.bashrc"
    fi

    # --- Settlement parser dependencies ---

    # Detect platform
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    # Install poppler-utils (pdftotext) if missing
    if ! command -v pdftotext >/dev/null 2>&1; then
        case "${OS}" in
            Linux)
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get update -qq >/dev/null 2>&1
                    sudo apt-get install -y poppler-utils >/dev/null 2>&1 || errors+=("failed to install poppler-utils via apt")
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y poppler-utils >/dev/null 2>&1 || errors+=("failed to install poppler-utils via yum")
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y poppler-utils >/dev/null 2>&1 || errors+=("failed to install poppler-utils via dnf")
                elif command -v apk >/dev/null 2>&1; then
                    sudo apk add poppler-utils >/dev/null 2>&1 || errors+=("failed to install poppler-utils via apk")
                else
                    errors+=("pdftotext not found — install poppler-utils manually (no supported package manager detected)")
                fi
                ;;
            Darwin)
                if command -v brew >/dev/null 2>&1; then
                    brew install poppler >/dev/null 2>&1 || errors+=("failed to install poppler via brew")
                else
                    errors+=("pdftotext not found — install poppler via Homebrew: brew install poppler")
                fi
                ;;
            *)
                errors+=("pdftotext not found — unsupported OS: ${OS}. Install poppler-utils manually")
                ;;
        esac
    fi

    # Install Python3 + pip if missing
    if ! command -v python3 >/dev/null 2>&1; then
        case "${OS}" in
            Linux)
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get install -y python3 python3-pip >/dev/null 2>&1 || errors+=("failed to install python3")
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y python3 python3-pip >/dev/null 2>&1 || errors+=("failed to install python3")
                fi
                ;;
            *)
                errors+=("python3 not found — required for settlement parsers")
                ;;
        esac
    fi

    # Install openpyxl if missing
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import openpyxl" 2>/dev/null; then
            # Try pip3 --user first, fall back to pip3 without --user (for venvs/containers)
            pip3 install --user openpyxl >/dev/null 2>&1 \
                || pip3 install openpyxl >/dev/null 2>&1 \
                || python3 -m pip install --user openpyxl >/dev/null 2>&1 \
                || errors+=("failed to install openpyxl — try: pip3 install openpyxl")
        fi
    fi

    # Deploy parser scripts
    mkdir -p "${HOME}/.ifn/parsers"
    if [ -d "${SKILL_ROOT}/tools/parsers" ]; then
        cp "${SKILL_ROOT}/tools/parsers/"*.py "${HOME}/.ifn/parsers/" 2>/dev/null || true
        chmod +x "${HOME}/.ifn/parsers/"*.py 2>/dev/null || true
    fi

    # Create booking template cache directory
    mkdir -p "${HOME}/.ifn/booking-templates"

    # Verify all dependencies are working
    if [ ${#errors[@]} -eq 0 ]; then
        command -v pdftotext >/dev/null 2>&1 || errors+=("pdftotext still not available after install")
        python3 -c "import openpyxl" 2>/dev/null || errors+=("openpyxl still not importable after install")
    fi

    # Re-check for errors from dependency install
    if [ ${#errors[@]} -eq 0 ]; then
        jq -n '{ok: true}'
    else
        msg=$(printf '%s; ' "${errors[@]}")
        jq -n --arg errors "${msg%;* }" '{ok: false, errors: $errors}'
    fi
else
    msg=$(printf '%s; ' "${errors[@]}")
    jq -n --arg errors "${msg%;* }" '{ok: false, errors: $errors}'
fi

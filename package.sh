#!/usr/bin/env bash
# package.sh — Package a skill for upload to GentiqOS
# Usage: ./package.sh
#
# Interactively selects a skill from skills/, validates it,
# and produces a .tar.gz archive in dist/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
DIST_DIR="${REPO_ROOT}/dist"

# --- Helpers ---

die() { echo "Error: $1" >&2; exit 1; }

# --- Discover skills ---

skills=()
while IFS= read -r dir; do
    name="$(basename "$dir")"
    if [ -f "${dir}/skill.toml" ]; then
        skills+=("$name")
    fi
done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [ ${#skills[@]} -eq 0 ]; then
    die "No skills found in ${SKILLS_DIR}/. Each skill needs a skill.toml."
fi

# --- Select skill ---

echo "Available skills:"
echo ""
for i in "${!skills[@]}"; do
    skill="${skills[$i]}"
    # Extract description from skill.toml
    desc=$(grep '^description' "${SKILLS_DIR}/${skill}/skill.toml" 2>/dev/null | head -1 | sed 's/^description *= *"//;s/"$//')
    printf "  %d) %-25s %s\n" $((i + 1)) "$skill" "$desc"
done
echo ""

read -rp "Select skill to package [1-${#skills[@]}]: " choice

# Validate selection
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#skills[@]} ]; then
    die "Invalid selection: $choice"
fi

SKILL_NAME="${skills[$((choice - 1))]}"
SKILL_DIR="${SKILLS_DIR}/${SKILL_NAME}"

echo ""
echo "Packaging: ${SKILL_NAME}"

# --- Validate skill ---

errors=()

if [ ! -f "${SKILL_DIR}/skill.toml" ]; then
    errors+=("missing skill.toml")
fi

if [ ! -f "${SKILL_DIR}/SKILL.md" ]; then
    errors+=("missing SKILL.md")
fi

# Extract version from skill.toml
VERSION=$(grep '^version' "${SKILL_DIR}/skill.toml" 2>/dev/null | head -1 | sed 's/^version *= *"//;s/"$//')
if [ -z "$VERSION" ]; then
    errors+=("no version found in skill.toml")
fi

# Check tool scripts are executable
if [ -d "${SKILL_DIR}/tools" ]; then
    while IFS= read -r tool; do
        if [ ! -x "$tool" ]; then
            errors+=("tool not executable: $(basename "$tool")")
        fi
    done < <(find "${SKILL_DIR}/tools" -maxdepth 1 -type f 2>/dev/null)
fi

if [ ${#errors[@]} -gt 0 ]; then
    echo ""
    echo "Validation errors:"
    for err in "${errors[@]}"; do
        echo "  - $err"
    done
    die "Fix the errors above before packaging."
fi

# --- Build archive ---

mkdir -p "$DIST_DIR"

ARCHIVE_NAME="${SKILL_NAME}-${VERSION}.tar.gz"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"

# Exclude docs/ directory (API specs are reference material, not part of the deployed skill)
# Exclude config/ examples (credentials are managed via GentiqOS admin)
tar -czf "$ARCHIVE_PATH" \
    -C "$SKILLS_DIR" \
    --exclude="${SKILL_NAME}/docs" \
    --exclude="${SKILL_NAME}/config" \
    --exclude='.DS_Store' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.git' \
    "$SKILL_NAME"

# --- Summary ---

SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1 | xargs)

echo ""
echo "Package created:"
echo "  File:    ${ARCHIVE_PATH}"
echo "  Size:    ${SIZE}"
echo "  Skill:   ${SKILL_NAME}"
echo "  Version: ${VERSION}"
echo ""
echo "Contents:"
tar -tzf "$ARCHIVE_PATH" | head -30
TOTAL=$(tar -tzf "$ARCHIVE_PATH" | wc -l | xargs)
if [ "$TOTAL" -gt 30 ]; then
    echo "  ... and $((TOTAL - 30)) more files"
fi
echo ""
echo "Upload via: POST /api/v1/skills/upload or the GentiqOS web admin."

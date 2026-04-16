#!/bin/bash
# migrate-legacy-skill.sh — Migrate a legacy skill to v2 format (§10a, E4).
#
# Takes a legacy skill directory and:
# 1. Rewrites SKILL.md frontmatter to v2 format
# 2. Scaffolds tools.json from tools/ directory
# 3. Extracts cron definitions from skill.toml into standalone JSON files
# 4. Prints a diff of what changed and what needs manual review
#
# Usage: ./scripts/migrate-legacy-skill.sh <skill-dir>

set -euo pipefail

SKILL_DIR="${1:?Usage: $0 <skill-directory>}"

if [ ! -d "$SKILL_DIR" ]; then
    echo "Error: '$SKILL_DIR' is not a directory" >&2
    exit 1
fi

SKILL_MD="$SKILL_DIR/SKILL.md"
if [ ! -f "$SKILL_MD" ]; then
    echo "Error: '$SKILL_MD' not found" >&2
    exit 1
fi

echo "=== Migrating skill: $SKILL_DIR ==="
echo ""

# ---- 1. Parse existing frontmatter ----
SKILL_KEY=""
PRIMARY_ENV=""
EMOJI=""

if head -1 "$SKILL_MD" | grep -q "^---"; then
    # Extract frontmatter
    FM=$(sed -n '/^---$/,/^---$/p' "$SKILL_MD" | sed '1d;$d')
    SKILL_KEY=$(echo "$FM" | grep "^skillKey:" | sed 's/skillKey: *//' | tr -d '"' | tr -d "'")
    PRIMARY_ENV=$(echo "$FM" | grep "^primaryEnv:" | sed 's/primaryEnv: *//' | tr -d '"' | tr -d "'")
    EMOJI=$(echo "$FM" | grep "^emoji:" | sed 's/emoji: *//' | tr -d '"' | tr -d "'")
fi

SKILL_ID="${SKILL_KEY:-$(basename "$SKILL_DIR")}"
SKILL_NAME=$(echo "$SKILL_ID" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

echo "Detected:"
echo "  id: $SKILL_ID"
echo "  name: $SKILL_NAME"
echo "  primary_env: $PRIMARY_ENV"
echo ""

# ---- 2. Discover tools ----
TOOLS_DIR="$SKILL_DIR/tools"
TOOL_NAMES=""
if [ -d "$TOOLS_DIR" ]; then
    for tool in "$TOOLS_DIR"/*; do
        if [ -f "$tool" ] && [ -x "$tool" ]; then
            name=$(basename "$tool" | sed 's/\.[^.]*$//')
            TOOL_NAMES="$TOOL_NAMES $name"
        fi
    done
fi
TOOL_NAMES=$(echo "$TOOL_NAMES" | xargs)  # trim whitespace

echo "Discovered tools: ${TOOL_NAMES:-none}"
echo ""

# ---- 3. Generate tools.json if it doesn't exist ----
TOOLS_JSON="$SKILL_DIR/tools.json"
if [ ! -f "$TOOLS_JSON" ] && [ -n "$TOOL_NAMES" ]; then
    echo "Creating tools.json..."
    echo "{" > "$TOOLS_JSON"
    FIRST=true
    for name in $TOOL_NAMES; do
        if [ "$FIRST" = false ]; then
            echo "  ," >> "$TOOLS_JSON"
        fi
        FIRST=false
        exec_path="tools/$name"
        cat >> "$TOOLS_JSON" << TOOLJSON
  "$name": {
    "exec": "$exec_path",
    "description": "TODO: describe what $name does",
    "args_schema": {"type": "object", "properties": {}},
    "side_effects": false,
    "timeout_ms": 180000
  }
TOOLJSON
    done
    echo "}" >> "$TOOLS_JSON"
    echo "  Created: $TOOLS_JSON (needs manual review of args_schema and side_effects)"
else
    echo "  tools.json already exists or no tools found, skipping"
fi

# ---- 4. Rewrite SKILL.md frontmatter ----
echo ""
echo "Rewriting SKILL.md frontmatter..."

# Build tools array string
TOOLS_ARRAY=""
if [ -n "$TOOL_NAMES" ]; then
    TOOLS_ARRAY=$(echo "$TOOL_NAMES" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd ',' - | sed 's/,/, /g')
    TOOLS_ARRAY="[$TOOLS_ARRAY]"
else
    TOOLS_ARRAY="[]"
fi

# Build requires_auth array
AUTH_ARRAY="[]"
if [ -n "$PRIMARY_ENV" ]; then
    AUTH_ARRAY="[$PRIMARY_ENV]"
fi

# Get body (everything after second ---)
BODY=$(sed -n '/^---$/,/^---$/!p' "$SKILL_MD" | tail -n +1)

# Write new frontmatter
BACKUP="$SKILL_MD.bak"
cp "$SKILL_MD" "$BACKUP"

cat > "$SKILL_MD" << FRONTMATTER
---
id: $SKILL_ID
name: $SKILL_NAME
description: TODO — describe what this skill does
activation: always
task_type: conversation
tools: $TOOLS_ARRAY
requires_auth: $AUTH_ARRAY
schema_version: "1.0.0"
---
FRONTMATTER

echo "$BODY" >> "$SKILL_MD"

echo "  Original backed up to: $BACKUP"
echo ""

# ---- 5. Check for cron definitions in skill.toml ----
SKILL_TOML="$SKILL_DIR/skill.toml"
if [ -f "$SKILL_TOML" ] && grep -q "\[\[cron\]\]" "$SKILL_TOML"; then
    echo "Found cron definitions in skill.toml — these need manual extraction"
    echo "  to standalone workspace/crons/*.json files matching §11 schema."
    echo ""
    echo "  Example cron JSON:"
    echo '  {'
    echo '    "id": "daily-check",'
    echo '    "schedule": "0 8 * * 1-5",'
    echo '    "timezone": "Europe/Stockholm",'
    echo '    "invoke": { "type": "skill", "skill": "'$SKILL_ID'" }'
    echo '  }'
fi

# ---- 6. Summary ----
echo ""
echo "=== Migration Summary ==="
echo "  SKILL.md frontmatter: REWRITTEN (review description, task_type)"
echo "  tools.json: $([ -f "$TOOLS_JSON" ] && echo "EXISTS" || echo "NOT CREATED")"
echo ""
echo "Manual review needed:"
echo "  [ ] SKILL.md: update 'description' field"
echo "  [ ] SKILL.md: set correct 'task_type' (data_analysis, code_write, etc.)"
echo "  [ ] tools.json: verify args_schema for each tool"
echo "  [ ] tools.json: set side_effects=true for tools that modify external state"
echo "  [ ] tools.json: adjust timeout_ms per tool"
if [ -f "$SKILL_TOML" ]; then
    echo "  [ ] Extract cron jobs from skill.toml to standalone JSON files"
fi
echo ""
echo "Done."

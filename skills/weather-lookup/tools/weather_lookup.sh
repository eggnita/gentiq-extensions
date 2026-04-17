#!/usr/bin/env bash
# weather_lookup — Fetch current weather for a given city
#
# v2 contract: arguments arrive as JSON in the TOOL_ARGS env var.
#   Expected fields: { "city": string }
# Stdout: JSON from wttr.in on success, or {"error": "..."} on failure.

set -euo pipefail

ARGS_JSON="${TOOL_ARGS:-}"

if [ -z "$ARGS_JSON" ]; then
    echo '{"error":"TOOL_ARGS env var not set"}' >&2
    exit 1
fi

CITY=$(printf '%s' "$ARGS_JSON" | jq -r '.city // empty')

if [ -z "$CITY" ]; then
    echo '{"error":"Missing required field: city"}' >&2
    exit 1
fi

# URL-encode the city name (spaces → +)
ENCODED_CITY=$(printf '%s' "$CITY" | sed 's/ /+/g')

# Fetch weather as JSON from wttr.in
curl -sf "https://wttr.in/${ENCODED_CITY}?format=j1" 2>/dev/null || {
    printf '{"error":"Could not fetch weather for %s. City may not exist or service unavailable."}\n' "$(printf '%s' "$CITY" | sed 's/"/\\"/g')"
    exit 1
}

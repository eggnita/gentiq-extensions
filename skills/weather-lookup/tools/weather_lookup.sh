#!/usr/bin/env bash
# weather_lookup — Fetch current weather for a given city
# Usage: weather_lookup.sh <city_name>
# Returns: JSON weather data from wttr.in
#
# This tool is invoked by the Gent runtime when the agent calls weather_lookup.

set -euo pipefail

CITY="${1:?Usage: weather_lookup.sh <city_name>}"

# URL-encode the city name
ENCODED_CITY=$(printf '%s' "$CITY" | sed 's/ /+/g')

# Fetch weather as JSON from wttr.in
curl -sf "https://wttr.in/${ENCODED_CITY}?format=j1" 2>/dev/null || {
    echo "{\"error\": \"Could not fetch weather for '${CITY}'. City may not exist or service unavailable.\"}"
    exit 1
}

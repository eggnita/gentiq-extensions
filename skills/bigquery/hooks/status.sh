#!/usr/bin/env bash
# status.sh — Dashboard status widget
# Trigger: status hook (refresh_interval: 3600)
# Output: {"connected": bool, "project": str, "sa_email": str, "datasets": int}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/bq-cli/config.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/format.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/auth.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/http.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/cache.sh"

bq_load_config 2>/dev/null || true

connected=false
datasets=0
sa_email=""
project="${BQ_PROJECT_ID:-}"
regions=""

if [ ! -f "$BQ_CREDENTIALS_FILE" ]; then
    jq -n '{connected: false, project: "", sa_email: "", datasets: 0, regions: "", message: "No credentials configured"}'
    exit 0
fi

sa_email=$(bq_sa_email)

# Try to read from cache first
bq_cache_load
if [ -n "$_BQ_CACHE" ] && ! bq_cache_is_stale; then
    connected=true
    datasets=$(echo "$_BQ_CACHE" | jq '[.datasets[]?] | length' 2>/dev/null || echo "0")
    regions=$(echo "$_BQ_CACHE" | jq -r '[.dataset_locations | to_entries[]?.value] | unique | join(", ")' 2>/dev/null || echo "")
else
    # Cache miss — fall back to API
    ds_json=$(bq_api_get "/projects/${BQ_PROJECT_ID}/datasets" 2>/dev/null) || true
    if [ -n "$ds_json" ]; then
        connected=true
        datasets=$(echo "$ds_json" | jq '[.datasets[]?] | length' 2>/dev/null || echo "0")
        regions=$(echo "$ds_json" | jq -r '[.datasets[]?.location] | unique | join(", ")' 2>/dev/null || echo "")
    fi
fi

jq -n \
    --argjson connected "$connected" \
    --arg project "$project" \
    --arg sa_email "$sa_email" \
    --argjson datasets "$datasets" \
    --arg regions "$regions" \
    '{connected: $connected, project: $project, sa_email: $sa_email, datasets: $datasets, regions: $regions}'

#!/usr/bin/env bash
# on_setup_complete.sh — Persist credentials and verify after setup completes
# Lifecycle: on_setup_complete
#
# gentd passes credentials as environment variables when running this hook.
# We persist the SA JSON to ~/.config/gent-bq/credentials.json and verify
# BigQuery connectivity via the REST API (no gcloud dependency).
#
# Output: {"ok": bool, "project": "...", "sa_email": "..."}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/bq-cli/config.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/format.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/auth.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/http.sh"
source "${SKILL_ROOT}/tools/bq-cli/lib/cache.sh"

# Persist credentials to config directory
config_dir="${HOME}/.config/gent-bq"
mkdir -p "$config_dir"
chmod 700 "$config_dir"

# Write SA JSON to credentials file
if [ -n "${BQ_SERVICE_ACCOUNT_JSON:-}" ]; then
    # Validate it's proper JSON with service_account type
    if ! echo "$BQ_SERVICE_ACCOUNT_JSON" | jq -e '.type == "service_account"' >/dev/null 2>&1; then
        jq -n '{ok: false, error: "Invalid service account JSON — must contain type: service_account"}'
        exit 0
    fi

    tmp_file=$(mktemp "${config_dir}/creds.XXXXXX")
    echo "$BQ_SERVICE_ACCOUNT_JSON" > "$tmp_file"
    chmod 600 "$tmp_file"
    mv "$tmp_file" "${config_dir}/credentials.json"
fi

# Write config file
if [ -n "${BQ_PROJECT_ID:-}" ] || [ -n "${BQ_DEFAULT_DATASET:-}" ]; then
    tmp_conf=$(mktemp "${config_dir}/config.XXXXXX")
    cat > "$tmp_conf" <<CONF
# BigQuery skill config — written by on_setup_complete hook
# $(date -u +"%Y-%m-%dT%H:%M:%SZ")
BQ_PROJECT_ID=${BQ_PROJECT_ID:-}
BQ_DEFAULT_DATASET=${BQ_DEFAULT_DATASET:-}
BQ_MAX_BYTES_BILLED=${BQ_MAX_BYTES_BILLED:-1073741824}
CONF
    chmod 600 "$tmp_conf"
    mv "$tmp_conf" "${config_dir}/config"
fi

# Reload config (now picks up persisted files)
bq_load_config

# Extract SA email for display
sa_email=$(bq_sa_email)

# Verify connectivity via REST API
if bq_verify_connection; then
    # Populate metadata cache after successful verification
    bq_cache_refresh >/dev/null 2>&1 || true
    jq -n \
        --arg project "$BQ_PROJECT_ID" \
        --arg sa_email "$sa_email" \
        '{ok: true, project: $project, sa_email: $sa_email}'
else
    jq -n \
        --arg project "$BQ_PROJECT_ID" \
        --arg sa_email "$sa_email" \
        '{ok: false, error: "BigQuery connection verification failed", project: $project, sa_email: $sa_email}'
fi

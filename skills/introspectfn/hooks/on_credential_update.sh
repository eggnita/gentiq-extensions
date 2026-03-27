#!/usr/bin/env bash
# on_credential_update.sh — Persist updated credentials and re-verify
# Lifecycle: on_credential_update
#
# gentd passes credentials as environment variables when running this hook.
# We persist them to ~/.ifn/config so the CLI can read them.
#
# Output: {"ok": bool, "user": {email, role}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/ifn-cli/config.sh"
source "${SKILL_ROOT}/tools/ifn-cli/lib/http.sh"

# Persist updated credentials to ~/.ifn/config
if [ -n "$IFN_API_KEY" ]; then
    config_dir="${HOME}/.ifn"
    config_file="${config_dir}/config"
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"

    tmp_file=$(mktemp "${config_dir}/config.XXXXXX")
    cat > "$tmp_file" <<CONF
# IntrospectFN CLI credentials — written by on_credential_update hook
# $(date -u +"%Y-%m-%dT%H:%M:%SZ")
IFN_API_KEY=${IFN_API_KEY}
IFN_BASE_URL=${IFN_BASE_URL:-https://ifn-stage.mayuda.com}
IFN_INSECURE=${IFN_INSECURE:-true}
CONF
    chmod 600 "$tmp_file"
    mv "$tmp_file" "$config_file"
fi

# Reload config
ifn_load_config

if [ -z "$IFN_API_KEY" ]; then
    jq -n '{ok: false, error: "No API key provided"}'
    exit 0
fi

# Verify the updated key via /api/me
me_resp=$(ifn_get "/api/me" 2>/dev/null) || {
    jq -n '{ok: false, error: "Failed to verify updated API key"}'
    exit 0
}

if echo "$me_resp" | jq -e '.user' >/dev/null 2>&1; then
    echo "$me_resp" | jq '{ok: true, user: {email: .user.email, role: .user.role}}'
else
    jq -n '{ok: false, error: "Updated API key verification failed"}'
fi

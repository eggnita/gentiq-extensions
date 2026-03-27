#!/usr/bin/env bash
# on_setup_complete.sh — Persist credentials and verify after setup completes
# Lifecycle: on_setup_complete
#
# gentd passes credentials as environment variables when running this hook.
# We persist them to ~/.ifn/config so the CLI can read them even if
# openclaw.json credential injection hasn't completed yet.
#
# Output: {"ok": bool, "user": {email, role}}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SKILL_ROOT}/tools/ifn-cli/config.sh"
source "${SKILL_ROOT}/tools/ifn-cli/lib/http.sh"

# Persist credentials to ~/.ifn/config (CLI fallback config file).
# gentd injects IFN_API_KEY and IFN_BASE_URL as env vars for this hook.
if [ -n "$IFN_API_KEY" ]; then
    config_dir="${HOME}/.ifn"
    config_file="${config_dir}/config"
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"

    # Write config atomically
    tmp_file=$(mktemp "${config_dir}/config.XXXXXX")
    cat > "$tmp_file" <<CONF
# IntrospectFN CLI credentials — written by on_setup_complete hook
# $(date -u +"%Y-%m-%dT%H:%M:%SZ")
IFN_API_KEY=${IFN_API_KEY}
IFN_BASE_URL=${IFN_BASE_URL:-https://ifn-stage.mayuda.com}
IFN_INSECURE=${IFN_INSECURE:-true}
CONF
    chmod 600 "$tmp_file"
    mv "$tmp_file" "$config_file"
fi

# Reload config (now picks up ~/.ifn/config if env vars weren't set)
ifn_load_config

if [ -z "$IFN_API_KEY" ]; then
    jq -n '{ok: false, error: "No API key provided"}'
    exit 0
fi

# Verify by calling /api/me
me_resp=$(ifn_get "/api/me" 2>/dev/null) || {
    jq -n '{ok: false, error: "Failed to verify API key"}'
    exit 0
}

if echo "$me_resp" | jq -e '.user' >/dev/null 2>&1; then
    echo "$me_resp" | jq '{ok: true, user: {email: .user.email, role: .user.role}}'
else
    jq -n '{ok: false, error: "API key verification returned unexpected response"}'
fi

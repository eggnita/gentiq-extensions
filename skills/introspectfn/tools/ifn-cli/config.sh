#!/usr/bin/env bash
# config.sh — Configuration loading and defaults

IFN_VERSION="0.6.0"
IFN_USER_AGENT="introspect-cli/${IFN_VERSION}"

# Defaults — must match [credentials.defaults] in skill.toml
IFN_BASE_URL="${IFN_BASE_URL:-}"
IFN_WEB_URL="${IFN_WEB_URL:-}"
IFN_API_KEY="${IFN_API_KEY:-}"
IFN_INSECURE="${IFN_INSECURE:-true}"
IFN_VERBOSE="${IFN_VERBOSE:-false}"
IFN_CONFIG="${IFN_CONFIG:-${HOME}/.ifn/config}"

ifn_load_config() {
    # Load config file if it exists
    if [ -f "$IFN_CONFIG" ]; then
        while IFS='=' read -r key value; do
            key="$(echo "$key" | xargs)"
            value="$(echo "$value" | xargs)"
            [ -z "$key" ] && continue
            [[ "$key" == \#* ]] && continue
            case "$key" in
                IFN_BASE_URL)  IFN_BASE_URL="${IFN_BASE_URL:-$value}" ;;
                IFN_WEB_URL)   IFN_WEB_URL="${IFN_WEB_URL:-$value}" ;;
                IFN_API_KEY)   IFN_API_KEY="${IFN_API_KEY:-$value}" ;;
                IFN_INSECURE)  IFN_INSECURE="${IFN_INSECURE:-$value}" ;;
            esac
        done < "$IFN_CONFIG"
    fi

    # Strip trailing slashes
    IFN_BASE_URL="${IFN_BASE_URL%/}"
    IFN_WEB_URL="${IFN_WEB_URL%/}"

    # Require IFN_BASE_URL — no hardcoded default
    if [ -z "$IFN_BASE_URL" ]; then
        echo "Error: IFN_BASE_URL is not set." >&2
        echo "Set it via skill credentials, ~/.ifn/config, or environment variable." >&2
        return 1
    fi

    # Default web URL to base URL if not set (same origin deployment)
    if [ -z "$IFN_WEB_URL" ]; then
        IFN_WEB_URL="$IFN_BASE_URL"
    fi

    export IFN_BASE_URL IFN_WEB_URL IFN_API_KEY IFN_INSECURE IFN_VERBOSE IFN_USER_AGENT IFN_VERSION
}

# Write credentials to config file (atomic)
# Usage: ifn_write_config <base_url> <api_key>
ifn_write_config() {
    local base_url="$1"
    local api_key="$2"
    local config_dir
    config_dir="$(dirname "$IFN_CONFIG")"

    mkdir -p "$config_dir"
    chmod 700 "$config_dir"

    local tmp
    tmp=$(mktemp "${config_dir}/config.XXXXXX")

    {
        echo "# IntrospectFN CLI config (written by ifn auth login)"
        echo "IFN_BASE_URL=${base_url}"
        echo "IFN_API_KEY=${api_key}"
        echo "IFN_INSECURE=${IFN_INSECURE:-true}"
        if [ -n "${IFN_WEB_URL:-}" ] && [ "${IFN_WEB_URL:-}" != "$base_url" ]; then
            echo "IFN_WEB_URL=${IFN_WEB_URL}"
        fi
    } > "$tmp"

    chmod 600 "$tmp"
    mv "$tmp" "$IFN_CONFIG"
}

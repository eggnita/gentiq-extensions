#!/usr/bin/env bash
# config.sh — Configuration loading and defaults

IFN_VERSION="0.2.3"
IFN_USER_AGENT="introspect-cli/${IFN_VERSION}"

# Defaults — must match [credentials.defaults] in skill.toml
IFN_BASE_URL="${IFN_BASE_URL:-https://ifn-stage.mayuda.com}"
IFN_WEB_URL="${IFN_WEB_URL:-}"
IFN_API_KEY="${IFN_API_KEY:-}"
IFN_INSECURE="${IFN_INSECURE:-true}"
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

    # Default web URL to base URL if not set (same origin deployment)
    if [ -z "$IFN_WEB_URL" ]; then
        IFN_WEB_URL="$IFN_BASE_URL"
    fi

    export IFN_BASE_URL IFN_WEB_URL IFN_API_KEY IFN_INSECURE IFN_USER_AGENT IFN_VERSION
}

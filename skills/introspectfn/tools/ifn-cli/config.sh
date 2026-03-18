#!/usr/bin/env bash
# config.sh — Configuration loading and defaults

IFN_VERSION="0.1.0"
IFN_USER_AGENT="introspect-cli/${IFN_VERSION}"

# Defaults
IFN_BASE_URL="${IFN_BASE_URL:-http://localhost:8000}"
IFN_API_KEY="${IFN_API_KEY:-}"
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
                IFN_BASE_URL) IFN_BASE_URL="${IFN_BASE_URL:-$value}" ;;
                IFN_API_KEY)  IFN_API_KEY="${IFN_API_KEY:-$value}" ;;
            esac
        done < "$IFN_CONFIG"
    fi

    # Strip trailing slash from base URL
    IFN_BASE_URL="${IFN_BASE_URL%/}"

    export IFN_BASE_URL IFN_API_KEY IFN_USER_AGENT IFN_VERSION
}

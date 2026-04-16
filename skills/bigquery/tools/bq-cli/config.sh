#!/usr/bin/env bash
# config.sh — Configuration loading and defaults for BigQuery skill

BQ_VERSION="0.1.0"
BQ_USER_AGENT="bq-tool/${BQ_VERSION}"

# Defaults — must match [credentials.defaults] in skill.toml
BQ_SERVICE_ACCOUNT_JSON="${BQ_SERVICE_ACCOUNT_JSON:-}"
BQ_PROJECT_ID="${BQ_PROJECT_ID:-}"
BQ_DEFAULT_DATASET="${BQ_DEFAULT_DATASET:-}"
BQ_LOCATION="${BQ_LOCATION:-EU}"
BQ_MAX_BYTES_BILLED="${BQ_MAX_BYTES_BILLED:-1073741824}"
BQ_CACHE_TTL="${BQ_CACHE_TTL:-3600}"
BQ_CACHE_FILE="${BQ_CACHE_FILE:-${HOME}/.config/gent-bq/cache.json}"
BQ_CONFIG="${BQ_CONFIG:-${HOME}/.config/gent-bq/config}"
BQ_CREDENTIALS_FILE="${HOME}/.config/gent-bq/credentials.json"

bq_load_config() {
    # Load config file if it exists (key=value format)
    if [ -f "$BQ_CONFIG" ]; then
        while IFS='=' read -r key value; do
            key="$(echo "$key" | xargs)"
            value="$(echo "$value" | xargs)"
            [ -z "$key" ] && continue
            [[ "$key" == \#* ]] && continue
            case "$key" in
                BQ_SERVICE_ACCOUNT_JSON) BQ_SERVICE_ACCOUNT_JSON="${BQ_SERVICE_ACCOUNT_JSON:-$value}" ;;
                BQ_PROJECT_ID)           BQ_PROJECT_ID="${BQ_PROJECT_ID:-$value}" ;;
                BQ_DEFAULT_DATASET)      BQ_DEFAULT_DATASET="${BQ_DEFAULT_DATASET:-$value}" ;;
                BQ_LOCATION)             BQ_LOCATION="${BQ_LOCATION:-$value}" ;;
                BQ_MAX_BYTES_BILLED)     BQ_MAX_BYTES_BILLED="${BQ_MAX_BYTES_BILLED:-$value}" ;;
            esac
        done < "$BQ_CONFIG"
    fi

    # If SA JSON is provided as env var, write it to credentials file
    if [ -n "$BQ_SERVICE_ACCOUNT_JSON" ] && [ "$BQ_SERVICE_ACCOUNT_JSON" != "file://${BQ_CREDENTIALS_FILE}" ]; then
        # Only write if it looks like JSON (not a file reference)
        if echo "$BQ_SERVICE_ACCOUNT_JSON" | jq -e '.type' >/dev/null 2>&1; then
            mkdir -p "$(dirname "$BQ_CREDENTIALS_FILE")"
            local tmp_file
            tmp_file=$(mktemp "$(dirname "$BQ_CREDENTIALS_FILE")/creds.XXXXXX")
            echo "$BQ_SERVICE_ACCOUNT_JSON" > "$tmp_file"
            chmod 600 "$tmp_file"
            mv "$tmp_file" "$BQ_CREDENTIALS_FILE"
        fi
    fi

    # Set GOOGLE_APPLICATION_CREDENTIALS for ADC
    if [ -f "$BQ_CREDENTIALS_FILE" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$BQ_CREDENTIALS_FILE"
    fi

    # Try to extract project ID from SA JSON if not explicitly set
    if [ -z "$BQ_PROJECT_ID" ] && [ -f "$BQ_CREDENTIALS_FILE" ]; then
        BQ_PROJECT_ID=$(jq -r '.project_id // empty' "$BQ_CREDENTIALS_FILE" 2>/dev/null || true)
    fi

    # Require project ID
    if [ -z "$BQ_PROJECT_ID" ]; then
        echo "Error: BQ_PROJECT_ID is not set." >&2
        echo "Set it via skill credentials, ~/.config/gent-bq/config, or environment variable." >&2
        return 1
    fi

    export BQ_SERVICE_ACCOUNT_JSON BQ_PROJECT_ID BQ_DEFAULT_DATASET BQ_LOCATION
    export BQ_MAX_BYTES_BILLED BQ_USER_AGENT BQ_VERSION BQ_CREDENTIALS_FILE
    export BQ_CACHE_TTL BQ_CACHE_FILE
}

# Extract SA email from credentials file
bq_sa_email() {
    if [ -f "$BQ_CREDENTIALS_FILE" ]; then
        jq -r '.client_email // "unknown"' "$BQ_CREDENTIALS_FILE" 2>/dev/null || echo "unknown"
    else
        echo "no-credentials"
    fi
}

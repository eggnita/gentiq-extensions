#!/usr/bin/env bash
# auth.sh — Service account authentication for BigQuery
# Authenticates via JWT → access token exchange using the SA JSON key.
# No dependency on gcloud — uses openssl for signing and curl for token exchange.

# Validate that credentials are configured and accessible
bq_require_auth() {
    if [ ! -f "$BQ_CREDENTIALS_FILE" ]; then
        bq_error "No service account credentials found at ${BQ_CREDENTIALS_FILE}"
        echo "Set BQ_SERVICE_ACCOUNT_JSON or run skill setup." >&2
        return 1
    fi

    # Validate the JSON structure
    if ! jq -e '.type == "service_account"' "$BQ_CREDENTIALS_FILE" >/dev/null 2>&1; then
        bq_error "Invalid credentials file — must contain type: service_account"
        return 1
    fi

    if ! jq -e '.private_key' "$BQ_CREDENTIALS_FILE" >/dev/null 2>&1; then
        bq_error "Invalid credentials file — missing private_key"
        return 1
    fi
}

# Verify BQ connectivity by listing datasets (1 result)
bq_verify_connection() {
    bq_debug "Verifying BigQuery connection for project: ${BQ_PROJECT_ID}"
    if bq_api_get "/projects/${BQ_PROJECT_ID}/datasets?maxResults=1" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

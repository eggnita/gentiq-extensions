#!/usr/bin/env bash
# http.sh — OAuth2 token generation and BigQuery REST API helpers
#
# Authenticates using a Service Account JSON key via JWT → access token exchange.
# No dependency on gcloud or bq CLI — uses only curl, jq, and openssl.

BQ_API_BASE="https://bigquery.googleapis.com/bigquery/v2"
BQ_TOKEN_URL="https://oauth2.googleapis.com/token"
BQ_SCOPE="https://www.googleapis.com/auth/bigquery"

# Token cache (in-memory for the process, file-backed for short-lived re-use)
_BQ_ACCESS_TOKEN=""
_BQ_TOKEN_EXPIRY=0
_BQ_TOKEN_CACHE_FILE="${HOME}/.config/gent-bq/.token_cache"

# --- Base64url encoding (RFC 4648 §5) ---
_bq_base64url() {
    openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# --- Generate a signed JWT from the service account key ---
# Returns the JWT string on stdout
_bq_make_jwt() {
    local sa_email
    sa_email=$(jq -r '.client_email' "$BQ_CREDENTIALS_FILE" 2>/dev/null)
    if [ -z "$sa_email" ] || [ "$sa_email" = "null" ]; then
        bq_error "Cannot read client_email from credentials file"
        return 1
    fi

    local now
    now=$(date +%s)
    local exp=$((now + 3600))

    # JWT header
    local header='{"alg":"RS256","typ":"JWT"}'

    # JWT claims
    local claims
    claims=$(jq -n \
        --arg iss "$sa_email" \
        --arg scope "$BQ_SCOPE" \
        --arg aud "$BQ_TOKEN_URL" \
        --argjson iat "$now" \
        --argjson exp "$exp" \
        '{iss:$iss,scope:$scope,aud:$aud,iat:$iat,exp:$exp}')

    # Encode header and claims
    local b64_header b64_claims
    b64_header=$(printf '%s' "$header" | _bq_base64url)
    b64_claims=$(printf '%s' "$claims" | _bq_base64url)

    # Extract private key from credentials
    local private_key
    private_key=$(jq -r '.private_key' "$BQ_CREDENTIALS_FILE" 2>/dev/null)
    if [ -z "$private_key" ] || [ "$private_key" = "null" ]; then
        bq_error "Cannot read private_key from credentials file"
        return 1
    fi

    # Sign with RS256
    local signature
    signature=$(printf '%s.%s' "$b64_header" "$b64_claims" | \
        openssl dgst -sha256 -sign <(printf '%s' "$private_key") | \
        _bq_base64url)

    printf '%s.%s.%s' "$b64_header" "$b64_claims" "$signature"
}

# --- Get an access token (cached, auto-refreshes) ---
# Sets _BQ_ACCESS_TOKEN and prints it to stdout
bq_get_access_token() {
    local now
    now=$(date +%s)

    # Check in-memory cache first
    if [ -n "$_BQ_ACCESS_TOKEN" ] && [ "$_BQ_TOKEN_EXPIRY" -gt "$now" ] 2>/dev/null; then
        echo "$_BQ_ACCESS_TOKEN"
        return 0
    fi

    # Check file cache
    if [ -f "$_BQ_TOKEN_CACHE_FILE" ]; then
        local cached_expiry cached_token
        cached_expiry=$(jq -r '.expiry // "0"' "$_BQ_TOKEN_CACHE_FILE" 2>/dev/null || echo "0")
        if [ "$cached_expiry" -gt "$now" ] 2>/dev/null; then
            cached_token=$(jq -r '.access_token // empty' "$_BQ_TOKEN_CACHE_FILE" 2>/dev/null)
            if [ -n "$cached_token" ]; then
                _BQ_ACCESS_TOKEN="$cached_token"
                _BQ_TOKEN_EXPIRY="$cached_expiry"
                echo "$_BQ_ACCESS_TOKEN"
                return 0
            fi
        fi
    fi

    # Generate new token
    bq_debug "Generating new access token via JWT"

    local jwt
    jwt=$(_bq_make_jwt) || return 1

    local token_response
    token_response=$(curl -s -S -X POST "$BQ_TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}" \
        2>&1) || {
        bq_error "Token exchange request failed"
        return 1
    }

    local access_token
    access_token=$(echo "$token_response" | jq -r '.access_token // empty' 2>/dev/null)
    if [ -z "$access_token" ]; then
        local err_msg
        err_msg=$(echo "$token_response" | jq -r '.error_description // .error // "Unknown error"' 2>/dev/null)
        bq_error "Failed to obtain access token: ${err_msg}"
        return 1
    fi

    local expires_in
    expires_in=$(echo "$token_response" | jq -r '.expires_in // "3600"' 2>/dev/null)
    _BQ_ACCESS_TOKEN="$access_token"
    _BQ_TOKEN_EXPIRY=$((now + expires_in - 60))  # 60s safety margin

    # Cache to file
    mkdir -p "$(dirname "$_BQ_TOKEN_CACHE_FILE")" 2>/dev/null || true
    jq -n \
        --arg access_token "$_BQ_ACCESS_TOKEN" \
        --argjson expiry "$_BQ_TOKEN_EXPIRY" \
        '{access_token:$access_token,expiry:$expiry}' > "$_BQ_TOKEN_CACHE_FILE" 2>/dev/null || true
    chmod 600 "$_BQ_TOKEN_CACHE_FILE" 2>/dev/null || true

    echo "$_BQ_ACCESS_TOKEN"
}

# --- HTTP GET with auth ---
# Usage: bq_api_get "/projects/{project}/datasets" [extra_curl_args...]
bq_api_get() {
    local path="$1"
    shift

    local token
    token=$(bq_get_access_token) || return 1

    local url="${BQ_API_BASE}${path}"
    bq_debug "GET ${url}"

    local response http_code
    response=$(curl -s -S -w '\n%{http_code}' \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        "$@" \
        "$url" 2>&1)

    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        echo "$body"
        return 0
    else
        local err_msg
        err_msg=$(echo "$body" | jq -r '.error.message // empty' 2>/dev/null)
        if [ -n "$err_msg" ]; then
            bq_error "API error (HTTP ${http_code}): ${err_msg}"
        else
            bq_error "API request failed (HTTP ${http_code})"
        fi
        bq_debug "Response body: ${body}"
        return 1
    fi
}

# --- HTTP POST with auth ---
# Usage: bq_api_post "/projects/{project}/queries" '{"query":"SELECT 1"}'
bq_api_post() {
    local path="$1"
    local data="$2"
    shift 2

    local token
    token=$(bq_get_access_token) || return 1

    local url="${BQ_API_BASE}${path}"
    bq_debug "POST ${url}"

    local response http_code
    response=$(curl -s -S -w '\n%{http_code}' \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$@" \
        "$url" 2>&1)

    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        echo "$body"
        return 0
    else
        local err_msg
        err_msg=$(echo "$body" | jq -r '.error.message // empty' 2>/dev/null)
        if [ -n "$err_msg" ]; then
            bq_error "API error (HTTP ${http_code}): ${err_msg}"
        else
            bq_error "API request failed (HTTP ${http_code})"
        fi
        bq_debug "Response body: ${body}"
        return 1
    fi
}

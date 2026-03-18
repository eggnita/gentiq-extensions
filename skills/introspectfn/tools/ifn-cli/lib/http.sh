#!/usr/bin/env bash
# http.sh — HTTP request helpers (curl wrappers with API key auth)

# Check dependencies
_ifn_check_deps() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: missing required dependencies: ${missing[*]}" >&2
        echo "Install them and retry." >&2
        exit 1
    fi
}
_ifn_check_deps

# Core HTTP request function
# Usage: ifn_http <method> <path> [body_json]
# Returns: JSON response on stdout, sets IFN_HTTP_STATUS
ifn_http() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    local url="${IFN_BASE_URL}${path}"

    local -a curl_args=(
        -s -S
        -w '\n%{http_code}'
        -X "$method"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        -H "X-Bot-Client: ${IFN_USER_AGENT}"
    )

    # API key auth (Bearer token)
    if [ -n "$IFN_API_KEY" ]; then
        curl_args+=(-H "Authorization: Bearer ${IFN_API_KEY}")
    fi

    if [ -n "$body" ]; then
        curl_args+=(-d "$body")
    fi

    if [ "$IFN_VERBOSE" = "true" ]; then
        echo "[http] ${method} ${url}" >&2
        if [ -n "$body" ]; then
            echo "[http] body: ${body}" >&2
        fi
    fi

    local response
    response=$(curl "${curl_args[@]}" "$url" 2>&1) || {
        echo '{"error": "Failed to connect to IntrospectFN API at '"${IFN_BASE_URL}"'. Is the server running?"}'
        return 1
    }

    # Split response body and status code
    local status_code
    status_code=$(echo "$response" | tail -n1)
    local response_body
    response_body=$(echo "$response" | sed '$d')

    IFN_HTTP_STATUS="$status_code"
    export IFN_HTTP_STATUS

    if [ "$IFN_VERBOSE" = "true" ]; then
        echo "[http] status: ${status_code}" >&2
    fi

    # Check for HTTP errors
    case "$status_code" in
        2[0-9][0-9])
            echo "$response_body"
            ;;
        401)
            echo '{"error": "Authentication failed. Check that IFN_API_KEY is valid and not expired."}' >&2
            echo "$response_body"
            return 1
            ;;
        403)
            echo '{"error": "Permission denied. The API key role may not allow this action."}' >&2
            echo "$response_body"
            return 1
            ;;
        404)
            echo "$response_body"
            return 1
            ;;
        *)
            echo "$response_body" >&2
            echo "$response_body"
            return 1
            ;;
    esac
}

# Convenience wrappers
ifn_get() { ifn_http GET "$@"; }
ifn_post() { ifn_http POST "$@"; }
ifn_patch() { ifn_http PATCH "$@"; }
ifn_delete() { ifn_http DELETE "$@"; }

# Upload a file (multipart)
# Usage: ifn_upload <path> <file_path>
ifn_upload() {
    local path="$1"
    local file_path="$2"
    local url="${IFN_BASE_URL}${path}"

    local -a curl_args=(
        -s -S
        -w '\n%{http_code}'
        -X POST
        -H "X-Bot-Client: ${IFN_USER_AGENT}"
        -F "file=@${file_path}"
    )

    if [ -n "$IFN_API_KEY" ]; then
        curl_args+=(-H "Authorization: Bearer ${IFN_API_KEY}")
    fi

    local response
    response=$(curl "${curl_args[@]}" "$url" 2>&1) || {
        echo '{"error": "Upload failed"}'
        return 1
    }

    local status_code
    status_code=$(echo "$response" | tail -n1)
    local response_body
    response_body=$(echo "$response" | sed '$d')

    IFN_HTTP_STATUS="$status_code"
    echo "$response_body"
}

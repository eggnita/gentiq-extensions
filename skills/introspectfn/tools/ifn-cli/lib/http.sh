#!/usr/bin/env bash
# http.sh — HTTP request helpers (curl wrappers with API key auth)
# Supports key rotation detection via X-Key-Rotation-Required header.

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

    # Use a temp file for response headers so we can inspect rotation signals
    local header_file
    header_file=$(mktemp)

    local -a curl_args=(
        -s -S
        -w '\n%{http_code}'
        -D "$header_file"
        -X "$method"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        -H "X-Bot-Client: ${IFN_USER_AGENT}"
    )

    # Skip SSL certificate validation when configured
    if [ "$IFN_INSECURE" = "true" ]; then
        curl_args+=(-k)
    fi

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
        rm -f "$header_file"
        echo '{"error": "Failed to connect to IntrospectFN API at '"${IFN_BASE_URL}"'. Is the server running?"}'
        return 1
    }

    # Check for key rotation signal in response headers
    _ifn_check_rotation_headers "$header_file"
    rm -f "$header_file"

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

# Check rotation headers and warn if rotation is needed
_ifn_check_rotation_headers() {
    local header_file="$1"
    [ -f "$header_file" ] || return 0

    local rotation_required
    rotation_required=$(grep -i '^X-Key-Rotation-Required:' "$header_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r')

    if [ "$rotation_required" = "true" ]; then
        local hard_expires
        hard_expires=$(grep -i '^X-Key-Hard-Expires:' "$header_file" 2>/dev/null | head -1 | sed 's/^[^:]*: *//' | tr -d '\r')
        echo "[warning] Key rotation required. Run: ifn auth rotate" >&2
        if [ -n "$hard_expires" ]; then
            echo "[warning] Hard expiry: ${hard_expires}" >&2
        fi
    fi
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

    # Skip SSL certificate validation when configured
    if [ "$IFN_INSECURE" = "true" ]; then
        curl_args+=(-k)
    fi

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

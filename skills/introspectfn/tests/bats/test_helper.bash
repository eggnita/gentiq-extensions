#!/usr/bin/env bash
# test_helper.bash — shared setup for ifn CLI bats tests
#
# Mocks the HTTP layer so tests verify URL construction, flag parsing,
# and output formatting without hitting a real API.

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../tools && pwd)"
IFN_CLI_DIR="${TOOLS_DIR}/ifn-cli"

# Required env vars
export IFN_BASE_URL="http://test-api.local"
export IFN_API_KEY="test-key-000"
export IFN_INSECURE="true"
export IFN_RAW_JSON="true"
export IFN_VERBOSE="false"

# Source real libraries (non-HTTP)
source "${IFN_CLI_DIR}/config.sh"
source "${IFN_CLI_DIR}/lib/format.sh"
source "${IFN_CLI_DIR}/lib/auth.sh"
source "${IFN_CLI_DIR}/lib/deeplink.sh"

# Load config (sets exports)
ifn_load_config

# --- Mock state ---

_MOCK_CALLS_FILE=""
_MOCK_RESPONSE='[]'
_MOCK_STATUS="200"

mock_setup() {
    _MOCK_CALLS_FILE="$(mktemp)"
}

mock_teardown() {
    [ -n "$_MOCK_CALLS_FILE" ] && rm -f "$_MOCK_CALLS_FILE"
}

mock_set_response() {
    _MOCK_RESPONSE="${1:-[]}"
    _MOCK_STATUS="${2:-200}"
}

# --- Mock HTTP functions (replace real ones from http.sh) ---

ifn_http() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    echo "${method} ${path} ${body}" >> "$_MOCK_CALLS_FILE"
    echo "$_MOCK_RESPONSE"
    IFN_HTTP_STATUS="$_MOCK_STATUS"
    export IFN_HTTP_STATUS
}

ifn_get() { ifn_http GET "$@"; }
ifn_post() { ifn_http POST "$@"; }
ifn_patch() { ifn_http PATCH "$@"; }
ifn_delete() { ifn_http DELETE "$@"; }

ifn_get_binary() {
    local path="$1"
    echo "GET_BINARY ${path}" >> "$_MOCK_CALLS_FILE"
    echo "binary-content"
}

ifn_upload() {
    local path="$1"
    local file_path="$2"
    echo "UPLOAD ${path} ${file_path}" >> "$_MOCK_CALLS_FILE"
    echo "$_MOCK_RESPONSE"
}

# --- Assertion helpers ---

# Assert a specific HTTP call was made (method + path prefix match)
assert_http_call() {
    local expected_method="$1"
    local expected_path="$2"
    local calls
    calls=$(cat "$_MOCK_CALLS_FILE")
    if ! echo "$calls" | grep -qF "${expected_method} ${expected_path}"; then
        echo "FAIL: Expected HTTP call: ${expected_method} ${expected_path}" >&2
        echo "Actual calls:" >&2
        echo "$calls" >&2
        return 1
    fi
}

# Assert no HTTP call contains a string
assert_no_http_call_containing() {
    local bad_string="$1"
    local calls
    calls=$(cat "$_MOCK_CALLS_FILE")
    if echo "$calls" | grep -qF "$bad_string"; then
        echo "FAIL: Expected no HTTP call containing: ${bad_string}" >&2
        echo "But found in calls:" >&2
        echo "$calls" >&2
        return 1
    fi
}

# Get all captured HTTP calls
get_http_calls() {
    cat "$_MOCK_CALLS_FILE"
}

# Source a command file (use after mock_setup so mocks are in scope)
load_command() {
    local cmd_name="$1"
    source "${IFN_CLI_DIR}/commands/${cmd_name}.sh"
}

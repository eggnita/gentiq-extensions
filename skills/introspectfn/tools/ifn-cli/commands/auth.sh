#!/usr/bin/env bash
# auth.sh — Authentication and key management commands

cmd_auth() {
    local subcmd="${1:-status}"
    shift 2>/dev/null || true

    case "$subcmd" in
        login)  _auth_login "$@" ;;
        status) _auth_status "$@" ;;
        rotate) _auth_rotate "$@" ;;
        --help|-h)
            cat <<'EOF'
Usage: ifn auth <subcommand>

Subcommands:
  login     Authenticate via browser (OAuth) or paste an API key
  status    Check current API key and session info
  rotate    Self-rotate the API key (grace period)

Login examples:
  ifn auth login                       # Interactive OAuth flow
  ifn auth login --token               # Paste an existing API key
  ifn auth login --email me@co.com     # Pre-fill email for OAuth

Authentication is via API key (IFN_API_KEY environment variable or ~/.ifn/config).
Keys are issued in the IntrospectFN web UI or via the OAuth provision flow.

Key rotation: both old and new keys remain valid until the new
key is first used for a normal API call, then the old key is burned.
EOF
            ;;
        *)
            ifn_error "unknown auth subcommand: $subcmd"
            return 1
            ;;
    esac
}

# --- login ---

_auth_login() {
    local email="" name="" token_mode=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --email)  email="$2"; shift 2 ;;
            --name)   name="$2"; shift 2 ;;
            --token)  token_mode=true; shift ;;
            --help|-h)
                cat <<'EOF'
Usage: ifn auth login [options]

Authenticate the CLI and store credentials in ~/.ifn/config.

Options:
  --email <email>   Your email (prompted if omitted)
  --name <name>     Display name (default: "CLI User")
  --token           Skip OAuth — paste an existing API key instead
  --help            Show this help

The default flow opens your browser for OAuth authorization against
the IntrospectFN server. Use --token to skip the browser and paste
a key you already have.
EOF
                return 0
                ;;
            *) shift ;;
        esac
    done

    echo "IntrospectFN CLI Login" >&2
    echo "" >&2

    # --- Resolve base URL ---
    local base_url="${IFN_BASE_URL:-}"
    if [ -z "$base_url" ]; then
        printf "IntrospectFN server URL: " >&2
        read -r base_url
        base_url="${base_url%/}"
        if [ -z "$base_url" ]; then
            echo "Error: server URL is required." >&2
            return 1
        fi
    else
        echo "Server: ${base_url}" >&2
    fi

    # --- Token mode: just paste a key ---
    if [ "$token_mode" = "true" ]; then
        _auth_login_token "$base_url"
        return $?
    fi

    # --- OAuth flow ---
    if [ -z "$email" ]; then
        printf "Email: " >&2
        read -r email
        if [ -z "$email" ]; then
            echo "Error: email is required." >&2
            return 1
        fi
    fi
    name="${name:-CLI User}"

    # CSRF token
    local csrf_token
    csrf_token=$(openssl rand -hex 24 2>/dev/null || LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 48)

    # Try local callback server (requires python3)
    local code=""
    if command -v python3 >/dev/null 2>&1; then
        code=$(_auth_login_browser "$base_url" "$email" "$name" "$csrf_token")
    fi

    # Fallback: manual paste
    if [ -z "$code" ]; then
        code=$(_auth_login_manual "$base_url" "$email" "$name" "$csrf_token")
    fi

    if [ -z "$code" ]; then
        echo "Error: no authorization code received." >&2
        return 1
    fi

    # Exchange code for API key
    _auth_exchange_and_save "$base_url" "$code"
}

# Token paste mode
_auth_login_token() {
    local base_url="$1"

    printf "API key: " >&2
    read -r api_key
    if [ -z "$api_key" ]; then
        echo "Error: API key is required." >&2
        return 1
    fi

    echo "" >&2
    echo "Verifying API key..." >&2

    local ssl_flag=""
    [ "${IFN_INSECURE:-true}" = "true" ] && ssl_flag="-k"

    local me_result
    # shellcheck disable=SC2086
    me_result=$(curl -s -S $ssl_flag \
        -H "Authorization: Bearer ${api_key}" \
        -H "Accept: application/json" \
        "${base_url}/api/me" 2>&1) || true

    local user_email user_role
    user_email=$(echo "$me_result" | jq -r '.user.email // empty' 2>/dev/null)
    user_role=$(echo "$me_result" | jq -r '.user.role // empty' 2>/dev/null)

    if [ -z "$user_email" ]; then
        echo "Warning: could not verify API key (server may be unreachable)." >&2
        echo "Saving anyway — you can re-verify with: ifn auth status" >&2
    fi

    ifn_write_config "$base_url" "$api_key"

    echo "" >&2
    echo "Login successful!" >&2
    [ -n "$user_email" ] && echo "  Email: ${user_email}" >&2
    [ -n "$user_role" ]  && echo "  Role:  ${user_role}" >&2
    echo "  Config: ${IFN_CONFIG}" >&2
    echo "" >&2
    echo "Try: ifn health" >&2

    jq -n --arg email "${user_email:-unknown}" --arg role "${user_role:-unknown}" \
        --arg base_url "$base_url" \
        '{ok: true, email: $email, role: $role, base_url: $base_url}'
}

# Browser-based OAuth flow with local callback server
_auth_login_browser() {
    local base_url="$1" email="$2" name="$3" csrf_token="$4"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local port_file="${tmp_dir}/port"
    local code_file="${tmp_dir}/code"

    # Start callback server in background
    python3 "${IFN_CLI_DIR}/lib/auth_callback.py" "$csrf_token" "$port_file" "$code_file" &
    local server_pid=$!

    # Wait for server to write port (up to 3s)
    local n=0
    while [ ! -f "$port_file" ] && [ $n -lt 30 ]; do
        sleep 0.1
        n=$((n + 1))
    done

    if [ ! -f "$port_file" ]; then
        kill "$server_pid" 2>/dev/null || true
        rm -rf "$tmp_dir"
        return 1
    fi

    local port
    port=$(cat "$port_file")
    local redirect_uri="http://127.0.0.1:${port}/callback"

    # URL-encode parameters
    local provision_url
    provision_url=$(python3 -c "
import urllib.parse
params = urllib.parse.urlencode({
    'email': '''${email}''',
    'name': '''${name}''',
    'client_id': 'ifn-bot-test',
    'redirect_uri': '${redirect_uri}',
    'state': '${csrf_token}'
})
print('${base_url}/auth/api-provision?' + params)
")

    echo "" >&2
    echo "Opening browser for authorization..." >&2
    _open_url "$provision_url"
    echo "Waiting for authorization (Ctrl+C to cancel)..." >&2

    # Wait for callback server to finish
    wait "$server_pid" 2>/dev/null || true

    local code=""
    if [ -f "$code_file" ]; then
        code=$(cat "$code_file")
    fi

    rm -rf "$tmp_dir"
    echo "$code"
}

# Manual code paste fallback
_auth_login_manual() {
    local base_url="$1" email="$2" name="$3" csrf_token="$4"

    echo "" >&2
    echo "Open this URL in your browser to authorize:" >&2
    echo "" >&2
    echo "  ${base_url}/auth/api-provision?email=${email}&name=${name}&client_id=ifn-bot-test&state=${csrf_token}" >&2
    echo "" >&2
    echo "After authorizing, copy the code from the browser and paste it below." >&2
    printf "Authorization code: " >&2
    read -r code
    echo "$code"
}

# Exchange auth code for API key and save config
_auth_exchange_and_save() {
    local base_url="$1" code="$2"

    echo "" >&2
    echo "Exchanging authorization code..." >&2

    local exchange_body
    exchange_body=$(jq -n \
        --arg code "$code" \
        --arg client_id "ifn-bot-test" \
        --arg client_secret "test-secret" \
        '{code: $code, client_id: $client_id, client_secret: $client_secret}')

    local ssl_flag=""
    [ "${IFN_INSECURE:-true}" = "true" ] && ssl_flag="-k"

    local exchange_result
    # shellcheck disable=SC2086
    exchange_result=$(curl -s -S $ssl_flag \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$exchange_body" \
        "${base_url}/auth/api-provision/token" 2>&1) || {
        echo "Error: token exchange failed. Is the server reachable?" >&2
        return 1
    }

    local raw_key
    raw_key=$(echo "$exchange_result" | jq -r '.raw_key // empty')

    if [ -z "$raw_key" ]; then
        local err_msg
        err_msg=$(echo "$exchange_result" | jq -r '.error // .detail // .message // "Unknown error"' 2>/dev/null)
        echo "Error: token exchange failed: ${err_msg}" >&2
        return 1
    fi

    # Verify the key
    echo "Verifying API key..." >&2

    local me_result
    # shellcheck disable=SC2086
    me_result=$(curl -s -S $ssl_flag \
        -H "Authorization: Bearer ${raw_key}" \
        -H "Accept: application/json" \
        "${base_url}/api/me" 2>&1) || true

    local user_email user_role
    user_email=$(echo "$me_result" | jq -r '.user.email // empty' 2>/dev/null)
    user_role=$(echo "$me_result" | jq -r '.user.role // empty' 2>/dev/null)

    # Save config
    ifn_write_config "$base_url" "$raw_key"

    echo "" >&2
    echo "Login successful!" >&2
    [ -n "$user_email" ] && echo "  Email: ${user_email}" >&2
    [ -n "$user_role" ]  && echo "  Role:  ${user_role}" >&2
    echo "  Config: ${IFN_CONFIG}" >&2
    echo "" >&2
    echo "Try: ifn health" >&2

    jq -n --arg email "${user_email:-unknown}" --arg role "${user_role:-unknown}" \
        --arg base_url "$base_url" \
        '{ok: true, email: $email, role: $role, base_url: $base_url}'
}

# Open URL in the default browser
_open_url() {
    local url="$1"
    if command -v open >/dev/null 2>&1; then
        open "$url"             # macOS
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url"        # Linux
    elif command -v wslview >/dev/null 2>&1; then
        wslview "$url"         # WSL
    else
        echo "Could not open browser. Open this URL manually:" >&2
        echo "  ${url}" >&2
    fi
}

# --- status ---

_auth_status() {
    if [ -z "$IFN_API_KEY" ]; then
        echo '{"authenticated": false, "message": "No API key configured. Run: ifn auth login"}'
        return
    fi

    local result
    result=$(ifn_get "/api/me") || {
        echo '{"authenticated": false, "message": "API key rejected or server unreachable."}'
        return 1
    }

    if [ "$IFN_RAW_JSON" = "true" ]; then
        echo "$result"
        return
    fi

    local user_null
    user_null=$(echo "$result" | jq -r '.user == null')

    if [ "$user_null" = "true" ]; then
        echo '{"authenticated": false, "message": "API key not recognized by server."}'
    else
        echo "$result" | jq '{
            authenticated: true,
            email: .user.email,
            name: .user.name,
            role: .user.role,
            is_bot: .user.is_bot
        }'
    fi
}

# --- rotate ---

_auth_rotate() {
    if [ -z "$IFN_API_KEY" ]; then
        ifn_error "No API key configured. Run: ifn auth login"
        return 1
    fi

    local result
    result=$(ifn_post "/api/api-keys/self/rotate") || return 1

    if [ "$IFN_RAW_JSON" = "true" ]; then
        echo "$result"
        return
    fi

    local new_key
    new_key=$(echo "$result" | jq -r '.raw_key // empty')

    if [ -n "$new_key" ]; then
        local rotated_at
        rotated_at=$(echo "$result" | jq -r '.rotated_at // "now"')
        echo "{\"ok\": true, \"rotated_at\": \"${rotated_at}\", \"message\": \"Key rotated. Both keys valid until new key is first used.\", \"new_key_prefix\": \"${new_key:0:12}...\"}"
        echo "" >&2
        echo "New API key (update IFN_API_KEY):" >&2
        echo "  ${new_key}" >&2

        # Update config file if it exists
        if [ -f "$IFN_CONFIG" ] && [ -n "$IFN_BASE_URL" ]; then
            ifn_write_config "$IFN_BASE_URL" "$new_key"
            echo "  Config updated: ${IFN_CONFIG}" >&2
        fi
    else
        echo "$result"
    fi
}

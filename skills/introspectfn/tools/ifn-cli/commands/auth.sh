#!/usr/bin/env bash
# auth.sh — Authentication and key management commands

cmd_auth() {
    local subcmd="${1:-status}"
    shift 2>/dev/null || true

    case "$subcmd" in
        status) _auth_status "$@" ;;
        rotate) _auth_rotate "$@" ;;
        --help|-h)
            echo "Usage: ifn auth <subcommand>"
            echo ""
            echo "Subcommands:"
            echo "  status    Check current API key and session info"
            echo "  rotate    Self-rotate the API key (grace period)"
            echo ""
            echo "Authentication is via API key (IFN_API_KEY environment variable)."
            echo "Keys are issued in the IntrospectFN web UI by an owner or developer."
            echo ""
            echo "Key rotation: both old and new keys remain valid until the new"
            echo "key is first used for a normal API call, then the old key is burned."
            ;;
        *)
            ifn_error "unknown auth subcommand: $subcmd"
            return 1
            ;;
    esac
}

_auth_status() {
    if [ -z "$IFN_API_KEY" ]; then
        echo '{"authenticated": false, "message": "No API key configured. Set IFN_API_KEY."}'
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

_auth_rotate() {
    if [ -z "$IFN_API_KEY" ]; then
        ifn_error "No API key configured. Set IFN_API_KEY first."
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
    else
        echo "$result"
    fi
}

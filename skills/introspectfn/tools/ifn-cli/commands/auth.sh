#!/usr/bin/env bash
# auth.sh — Authentication status commands

cmd_auth() {
    local subcmd="${1:-status}"
    shift 2>/dev/null || true

    case "$subcmd" in
        status) _auth_status "$@" ;;
        --help|-h)
            echo "Usage: ifn auth <subcommand>"
            echo ""
            echo "Subcommands:"
            echo "  status    Check current API key and session info"
            echo ""
            echo "Authentication is via API key (IFN_API_KEY environment variable)."
            echo "Keys are issued in the IntrospectFN web UI by an owner or developer."
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
            role: .user.role
        }'
    fi
}

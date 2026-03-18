#!/usr/bin/env bash
# health.sh — Health check command

cmd_health() {
    local result
    result=$(ifn_get "/health") || {
        echo '{"status": "unreachable", "error": "Cannot connect to IntrospectFN at '"${IFN_BASE_URL}"'"}'
        return 1
    }

    if [ "$IFN_RAW_JSON" = "true" ]; then
        echo "$result"
    else
        local ok
        ok=$(echo "$result" | jq -r '.ok // false')
        if [ "$ok" = "true" ]; then
            echo '{"status": "healthy", "base_url": "'"${IFN_BASE_URL}"'", "ok": true}'
        else
            echo '{"status": "unhealthy", "base_url": "'"${IFN_BASE_URL}"'", "response": '"${result}"'}'
        fi
    fi
}

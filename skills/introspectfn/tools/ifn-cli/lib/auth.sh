#!/usr/bin/env bash
# auth.sh — API key authentication
# The CLI authenticates via Bearer token (IFN_API_KEY).
# Keys are issued by an owner/developer in the IntrospectFN web UI
# and configured as credentials in the GentiqOS admin dashboard.

# Validate that an API key is configured
ifn_require_auth() {
    if [ -z "$IFN_API_KEY" ]; then
        echo '{"error": "No API key configured. Set IFN_API_KEY or add it to ~/.ifn/config"}' >&2
        return 1
    fi
}

#!/usr/bin/env bash
# companies.sh — Company management commands

cmd_companies() {
    local subcmd="${1:-list}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list)      _companies_list "$@" ;;
        doc-types) _companies_doc_types "$@" ;;
        --help|-h)
            echo "Usage: ifn companies <subcommand>"
            echo ""
            echo "Subcommands:"
            echo "  list       List all connected ERP companies"
            echo "  doc-types  <company_id>  List allowed doc types for a company"
            ;;
        *)
            ifn_error "unknown subcommand: $subcmd"
            echo "Usage: ifn companies list" >&2
            return 1
            ;;
    esac
}

_companies_list() {
    local result
    result=$(ifn_get "/api/companies") || return 1

    if [ "$IFN_RAW_JSON" = "true" ]; then
        echo "$result"
        return
    fi

    local count
    count=$(echo "$result" | jq 'length')

    if [ "$count" = "0" ]; then
        echo '{"message": "No companies connected. Connect a Fortnox company via the IntrospectFN web UI."}'
        return
    fi

    # Output structured summary
    echo "$result" | jq '[.[] | {
        name: .name,
        org_number: .org_number,
        company_id: .company_id,
        token_health: .token_health,
        badge: (.badge.label // "unknown"),
        created_at: .created_at
    }]'
}

_companies_doc_types() {
    ifn_require_arg "${1:-}" "company_id" "ifn companies doc-types <company_id>"
    local company_id="$1"

    local result
    result=$(ifn_get "/api/companies/${company_id}/allowed-doc-types") || return 1
    ifn_output "$result"
}

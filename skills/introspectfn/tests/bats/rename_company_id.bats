#!/usr/bin/env bats
# Tests for issue #01: connection_id → company_id rename
#
# These tests verify that every CLI command uses "company_id" in:
# 1. URL paths sent to the API
# 2. Help text shown to users
# 3. Response field parsing
#
# RED phase: all tests should FAIL before the rename is applied.

load test_helper

setup() {
    mock_setup
}

teardown() {
    mock_teardown
}

# ============================================================
# URL path construction — every command must use company_id
# ============================================================

@test "browse: URL uses company_id path param" {
    load_command browse
    cmd_browse abc-123 vouchers
    assert_http_call "GET" "/api/companies/abc-123/external/vouchers"
    # The URL itself doesn't contain the literal string "connection_id",
    # but we verify the variable flows through correctly
}

@test "browse account-info: URL uses company_id" {
    load_command browse
    cmd_browse abc-123 account-info 1930
    assert_http_call "GET" "/api/companies/abc-123/accounts/1930"
}

@test "browse fileconnections: URL uses company_id" {
    load_command browse
    cmd_browse abc-123 fileconnections --entity supplierinvoices
    assert_http_call "GET" "/api/companies/abc-123/external/fileconnections?entity=supplierinvoices"
}

@test "browse file-counts: URL uses company_id" {
    load_command browse
    cmd_browse abc-123 file-counts --entity invoices
    assert_http_call "GET" "/api/companies/abc-123/fileconnection-counts?entity=invoices"
}

@test "browse archive: URL uses company_id" {
    load_command browse
    cmd_browse abc-123 archive file-999
    assert_http_call "GET" "/api/companies/abc-123/external/archive/file-999"
}

@test "browse inbox: URL uses company_id" {
    load_command browse
    cmd_browse abc-123 inbox
    assert_http_call "GET" "/api/companies/abc-123/inbox"
}

@test "browse inbox folder: URL uses company_id" {
    load_command browse
    cmd_browse abc-123 inbox folder-1
    assert_http_call "GET" "/api/companies/abc-123/inbox/folder-1"
}

@test "browse inbox-file: URL uses company_id" {
    load_command browse
    cmd_browse abc-123 inbox-file file-42
    assert_http_call "GET" "/api/companies/abc-123/inbox/file/file-42"
}

@test "dashboard: URL uses company_id" {
    load_command dashboard
    cmd_dashboard abc-123
    assert_http_call "GET" "/api/companies/abc-123/dashboard"
}

@test "records list: URL uses company_id" {
    load_command records
    cmd_records abc-123 vouchers
    assert_http_call "GET" "/api/companies/abc-123/internal/vouchers"
}

@test "records get single: URL uses company_id" {
    load_command records
    cmd_records abc-123 vouchers 42
    assert_http_call "GET" "/api/companies/abc-123/internal/vouchers/42"
}

@test "records files: URL uses company_id" {
    load_command records
    cmd_records abc-123 files
    assert_http_call "GET" "/api/companies/abc-123/internal/files"
}

@test "records refresh: URL uses company_id" {
    load_command records
    cmd_records abc-123 vouchers 42 --refresh
    assert_http_call "POST" "/api/companies/abc-123/internal/vouchers/42/refresh"
}

@test "records FY-in-path: URL uses company_id" {
    load_command records
    cmd_records abc-123 vouchers 42 --fy 1
    assert_http_call "GET" "/api/companies/abc-123/internal/vouchers/FY-1/42"
}

@test "analysis accounts: URL uses company_id" {
    load_command analysis
    cmd_analysis accounts abc-123
    assert_http_call "GET" "/api/companies/abc-123/internal/account-analysis"
}

@test "analysis balances: URL uses company_id" {
    load_command analysis
    cmd_analysis balances abc-123 1930
    assert_http_call "GET" "/api/companies/abc-123/internal/accounts/1930/year-balances"
}

@test "analysis integrity: URL uses company_id" {
    load_command analysis
    cmd_analysis integrity abc-123
    assert_http_call "GET" "/api/companies/abc-123/internal/integrity"
}

@test "analysis series: URL uses company_id" {
    load_command analysis
    cmd_analysis series abc-123
    assert_http_call "GET" "/api/companies/abc-123/internal/voucherseries-map"
}

@test "sync status: URL uses company_id" {
    load_command sync
    cmd_sync status abc-123
    assert_http_call "GET" "/api/companies/abc-123/sync/status"
}

@test "sync years: URL uses company_id" {
    load_command sync
    cmd_sync years abc-123
    assert_http_call "GET" "/api/companies/abc-123/sync/financial-years"
}

@test "sync trigger: URL uses company_id" {
    load_command sync
    cmd_sync trigger abc-123
    assert_http_call "POST" "/api/companies/abc-123/sync"
}

@test "sync cancel: URL uses company_id" {
    load_command sync
    cmd_sync cancel abc-123 77
    assert_http_call "POST" "/api/companies/abc-123/sync/77/cancel"
}

@test "staging list: URL uses company_id" {
    load_command staging
    cmd_staging list abc-123
    assert_http_call "GET" "/api/companies/abc-123/bk-staging"
}

@test "staging propose: URL uses company_id" {
    load_command staging
    local tmpfile
    tmpfile=$(mktemp)
    echo '{"entity_type":"voucher"}' > "$tmpfile"
    cmd_staging propose abc-123 "$tmpfile"
    assert_http_call "POST" "/api/companies/abc-123/bk-staging"
    rm -f "$tmpfile"
}

@test "staging next-number: URL uses company_id" {
    load_command staging
    cmd_staging next-number abc-123
    assert_http_call "GET" "/api/companies/abc-123/bk-staging/next-number?series=A"
}

@test "staging upload: URL uses company_id" {
    load_command staging
    local tmpfile
    tmpfile=$(mktemp)
    echo "test" > "$tmpfile"
    cmd_staging upload abc-123 "$tmpfile"
    assert_http_call "UPLOAD" "/api/companies/abc-123/bk-staging/upload-file"
    rm -f "$tmpfile"
}

@test "staging write-windows: URL uses company_id" {
    load_command staging
    cmd_staging write-windows abc-123
    assert_http_call "GET" "/api/companies/abc-123/write-windows"
}

# ============================================================
# Help text — must say company_id, not connection_id
# ============================================================

@test "browse help says company_id" {
    load_command browse
    run cmd_browse --help
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
}

@test "dashboard help says company_id" {
    load_command dashboard
    run cmd_dashboard --help
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
}

@test "records help says company_id" {
    load_command records
    run cmd_records --help
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
}

@test "analysis help says company_id" {
    load_command analysis
    run cmd_analysis --help
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
}

@test "sync help says company_id" {
    load_command sync
    run cmd_sync --help
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
}

@test "staging help says company_id" {
    load_command staging
    run cmd_staging --help
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
}

# ============================================================
# Response parsing — companies list must output company_id field
# ============================================================

@test "companies list jq formats company_id field (not connection_id)" {
    load_command companies
    # Simulate API response with company_id field (new API format)
    mock_set_response '[{"name":"Test AB","org_number":"556677","company_id":"abc-123","token_health":"ok","badge":{"label":"synced"},"created_at":"2025-01-01"}]'
    export IFN_RAW_JSON="false"
    run cmd_companies list
    # The jq formatter in companies.sh must select .company_id, not .connection_id
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
    export IFN_RAW_JSON="true"
}

# ============================================================
# Main entry point help — must say company_id
# ============================================================

@test "main ifn help says company_id" {
    run bash -c "source '${TOOLS_DIR}/ifn-cli/config.sh' && ifn_load_config && source '${TOOLS_DIR}/ifn-cli/lib/format.sh' && source '${TOOLS_DIR}/ifn' --help 2>&1 || true"
    # The help text should not contain connection_id
    [[ "$output" != *"connection_id"* ]]
}

# ============================================================
# Settlement CLI — build_template.py must use company_id in payload
# ============================================================

@test "build_template.py uses company_id field in JSON payload" {
    local template_file="${TOOLS_DIR}/settlement-cli/lib/build_template.py"
    # The Python file must not contain "connection_id" in JSON keys
    run grep -c '"connection_id"' "$template_file"
    [[ "$output" == "0" ]]
}

# ============================================================
# No remaining connection_id references in CLI code
# ============================================================

@test "no connection_id in ifn-cli command files" {
    run grep -rl 'connection_id' "${TOOLS_DIR}/ifn-cli/"
    [[ "$status" -ne 0 ]] || [[ -z "$output" ]]
}

@test "no connection_id in main ifn entry point" {
    run grep -c 'connection_id' "${TOOLS_DIR}/ifn"
    [[ "$output" == "0" ]]
}

@test "no conn_id variable in ifn-cli command files" {
    # Internal variable should be company_id, not conn_id
    run grep -rl 'conn_id' "${TOOLS_DIR}/ifn-cli/commands/"
    [[ "$status" -ne 0 ]] || [[ -z "$output" ]]
}

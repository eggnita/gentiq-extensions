#!/usr/bin/env bats
# Tests for issue #09: transparent FY-in-path routing
#
# When a record_id contains "/" (e.g. FY-1/A123), the CLI should
# automatically split it and use the FY-in-path endpoint variant
# without requiring --fy flag.

load test_helper

setup() { mock_setup; }
teardown() { mock_teardown; }

# ============================================================
# Helper function
# ============================================================

@test "ifn_split_fy_path splits FY-1/A123 into fy_segment and record_id" {
    source "${IFN_CLI_DIR}/lib/format.sh"
    ifn_split_fy_path "FY-1/A123"
    [[ "$IFN_FY_SEGMENT" == "FY-1" ]]
    [[ "$IFN_RECORD_ID" == "A123" ]]
}

@test "ifn_split_fy_path leaves plain ID unchanged" {
    source "${IFN_CLI_DIR}/lib/format.sh"
    ifn_split_fy_path "42"
    [[ "$IFN_FY_SEGMENT" == "" ]]
    [[ "$IFN_RECORD_ID" == "42" ]]
}

@test "ifn_split_fy_path handles FY-2/B456" {
    source "${IFN_CLI_DIR}/lib/format.sh"
    ifn_split_fy_path "FY-2/B456"
    [[ "$IFN_FY_SEGMENT" == "FY-2" ]]
    [[ "$IFN_RECORD_ID" == "B456" ]]
}

# ============================================================
# records: auto-detect FY in record_id
# ============================================================

@test "records get with FY-1/A123 auto-routes to FY-in-path" {
    load_command records
    cmd_records abc-123 vouchers FY-1/A123
    assert_http_call "GET" "/api/companies/abc-123/internal/vouchers/FY-1/A123"
}

@test "records get with plain ID still works" {
    load_command records
    cmd_records abc-123 suppliers 42
    assert_http_call "GET" "/api/companies/abc-123/internal/suppliers/42"
}

@test "records get with plain ID and --fy still works" {
    load_command records
    cmd_records abc-123 vouchers 42 --fy 1
    assert_http_call "GET" "/api/companies/abc-123/internal/vouchers/FY-1/42"
}

@test "records refresh with FY-1/A123 auto-routes to FY-in-path refresh" {
    load_command records
    cmd_records abc-123 vouchers FY-1/A123 --refresh
    assert_http_call "POST" "/api/companies/abc-123/internal/vouchers/FY-1/A123/refresh"
}

@test "records refresh with plain ID still works" {
    load_command records
    cmd_records abc-123 vouchers 42 --refresh
    assert_http_call "POST" "/api/companies/abc-123/internal/vouchers/42/refresh"
}

# ============================================================
# browse: auto-detect FY in record_id
# ============================================================

@test "browse with FY-1/A123 auto-routes to FY-in-path" {
    load_command browse
    cmd_browse abc-123 vouchers FY-1/A123
    assert_http_call "GET" "/api/companies/abc-123/external/vouchers/FY-1/A123"
}

@test "browse with plain ID still works" {
    load_command browse
    cmd_browse abc-123 vouchers 42
    assert_http_call "GET" "/api/companies/abc-123/external/vouchers/42"
}

@test "browse with plain ID and --fy still works" {
    load_command browse
    cmd_browse abc-123 vouchers 42 --fy 1
    assert_http_call "GET" "/api/companies/abc-123/external/vouchers/FY-1/42"
}

# ============================================================
# browse account-info: FY-in-path variant
# ============================================================

@test "browse account-info with FY-1/1930 auto-routes to FY-in-path" {
    load_command browse
    cmd_browse abc-123 account-info FY-1/1930
    assert_http_call "GET" "/api/companies/abc-123/accounts/FY-1/1930"
}

@test "browse account-info with plain number still works" {
    load_command browse
    cmd_browse abc-123 account-info 1930
    assert_http_call "GET" "/api/companies/abc-123/accounts/1930"
}

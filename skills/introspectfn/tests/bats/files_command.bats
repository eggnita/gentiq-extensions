#!/usr/bin/env bats
# Tests for issue #02: files command group
#
# Verifies URL construction, flag parsing, and dispatch for:
# files list, fetch, fetch --live, refresh, categories, groups,
# inbox-folders, refs, metadata

load test_helper

setup() {
    mock_setup
}

teardown() {
    mock_teardown
}

# ============================================================
# files list
# ============================================================

@test "files list hits internal/files endpoint" {
    load_command files
    cmd_files list abc-123
    assert_http_call "GET" "/api/companies/abc-123/internal/files"
}

@test "files list with pagination flags" {
    load_command files
    cmd_files list abc-123 --page 2 --limit 50
    assert_http_call "GET" "/api/companies/abc-123/internal/files?page=2&limit=50"
}

@test "files list with all filter flags" {
    load_command files
    cmd_files list abc-123 --doc-type invoices --search "faktura" --category "incoming" --group-id grp-1 --sort name --sortdir desc
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"/api/companies/abc-123/internal/files?"* ]]
    [[ "$calls" == *"doc_type=invoices"* ]]
    [[ "$calls" == *"search=faktura"* ]]
    [[ "$calls" == *"category=incoming"* ]]
    [[ "$calls" == *"group_id=grp-1"* ]]
    [[ "$calls" == *"sort=name"* ]]
    [[ "$calls" == *"sortdir=desc"* ]]
}

@test "files list with boolean needs-categorization flag" {
    load_command files
    cmd_files list abc-123 --needs-categorization
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"needs_categorization=true"* ]]
}

@test "files list with financial-year-id flag" {
    load_command files
    cmd_files list abc-123 --financial-year-id FY-1
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"financial_year_id=FY-1"* ]]
}

@test "files list with voucher-series flag" {
    load_command files
    cmd_files list abc-123 --voucher-series A
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"voucher_series=A"* ]]
}

@test "files list with inbox-folder flag" {
    load_command files
    cmd_files list abc-123 --inbox-folder folder-1
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"inbox_folder=folder-1"* ]]
}

# ============================================================
# files fetch (local archive download)
# ============================================================

@test "files fetch hits internal archive endpoint" {
    load_command files
    cmd_files fetch abc-123 file-42
    assert_http_call "GET_BINARY" "/api/companies/abc-123/internal/archive/file-42"
}

@test "files fetch prints temp file path to stdout" {
    load_command files
    run cmd_files fetch abc-123 file-42
    # Output should contain a file path (starts with /)
    [[ "$output" == /* ]]
}

# ============================================================
# files fetch --live (external archive download)
# ============================================================

@test "files fetch --live hits external archive endpoint" {
    load_command files
    cmd_files fetch abc-123 file-42 --live
    assert_http_call "GET_BINARY" "/api/companies/abc-123/external/archive/file-42"
}

# ============================================================
# files refresh
# ============================================================

@test "files refresh hits files refresh endpoint" {
    load_command files
    cmd_files refresh abc-123 file-42
    assert_http_call "POST" "/api/companies/abc-123/files/file-42/refresh"
}

# ============================================================
# files categories
# ============================================================

@test "files categories hits categories endpoint" {
    load_command files
    cmd_files categories abc-123
    assert_http_call "GET" "/api/companies/abc-123/files/categories"
}

# ============================================================
# files groups (list all or specific group)
# ============================================================

@test "files groups lists all groups" {
    load_command files
    cmd_files groups abc-123
    assert_http_call "GET" "/api/companies/abc-123/files/groups"
}

@test "files groups with group_id lists files in group" {
    load_command files
    cmd_files groups abc-123 grp-99
    assert_http_call "GET" "/api/companies/abc-123/files/groups/grp-99"
}

# ============================================================
# files inbox-folders
# ============================================================

@test "files inbox-folders hits inbox-folders endpoint" {
    load_command files
    cmd_files inbox-folders abc-123
    assert_http_call "GET" "/api/companies/abc-123/files/inbox-folders"
}

# ============================================================
# files refs
# ============================================================

@test "files refs hits refs endpoint" {
    load_command files
    cmd_files refs abc-123 file-42
    assert_http_call "GET" "/api/companies/abc-123/files/file-42/refs"
}

# ============================================================
# files metadata (PATCH)
# ============================================================

@test "files metadata sends PATCH with category" {
    load_command files
    cmd_files metadata abc-123 file-42 --category incoming
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"PATCH /api/companies/abc-123/files/file-42/metadata"* ]]
    [[ "$calls" == *'"category":"incoming"'* ]]
}

@test "files metadata sends PATCH with group-id" {
    load_command files
    cmd_files metadata abc-123 file-42 --group-id grp-5
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"PATCH /api/companies/abc-123/files/file-42/metadata"* ]]
    [[ "$calls" == *'"group_id":"grp-5"'* ]]
}

@test "files metadata sends PATCH with details" {
    load_command files
    cmd_files metadata abc-123 file-42 --details "settlement march"
    local calls
    calls=$(get_http_calls)
    [[ "$calls" == *"PATCH /api/companies/abc-123/files/file-42/metadata"* ]]
    [[ "$calls" == *'"details":"settlement march"'* ]]
}

# ============================================================
# help text
# ============================================================

@test "files help shows all subcommands" {
    load_command files
    run cmd_files --help
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"fetch"* ]]
    [[ "$output" == *"refresh"* ]]
    [[ "$output" == *"categories"* ]]
    [[ "$output" == *"groups"* ]]
    [[ "$output" == *"inbox-folders"* ]]
    [[ "$output" == *"refs"* ]]
    [[ "$output" == *"metadata"* ]]
}

@test "files help uses company_id terminology" {
    load_command files
    run cmd_files --help
    [[ "$output" == *"company_id"* ]]
    [[ "$output" != *"connection_id"* ]]
}

# ============================================================
# dispatch — files command registered in main ifn
# ============================================================

@test "ifn dispatches files command" {
    run grep -c "files)" "${TOOLS_DIR}/ifn"
    [[ "$output" != "0" ]]
}

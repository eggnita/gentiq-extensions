#!/usr/bin/env bats
# Tests for issues #05-#08:
# - sync batch + cancel-all
# - jobs command group
# - companies doc-types + browse record-counts
# - new query params on existing commands

load test_helper

setup() { mock_setup; }
teardown() { mock_teardown; }

# ============================================================
# Issue #05: sync batch + cancel-all
# ============================================================

@test "sync batch hits batch endpoint" {
    load_command sync
    cmd_sync batch
    assert_http_call "POST" "/api/sync/batch"
}

@test "sync cancel-all hits cancel-all endpoint" {
    load_command sync
    cmd_sync cancel-all abc-123
    assert_http_call "POST" "/api/companies/abc-123/sync/cancel-all"
}

@test "sync cancel-all with parent-job-id" {
    load_command sync
    cmd_sync cancel-all abc-123 --parent-job-id 5
    local calls=$(get_http_calls)
    [[ "$calls" == *"/api/companies/abc-123/sync/cancel-all?parent_job_id=5"* ]]
}

@test "sync help shows batch and cancel-all" {
    load_command sync
    run cmd_sync --help
    [[ "$output" == *"batch"* ]]
    [[ "$output" == *"cancel-all"* ]]
}

# ============================================================
# Issue #06: jobs command group
# ============================================================

@test "jobs sync hits sync job endpoint" {
    load_command jobs
    cmd_jobs sync 42
    assert_http_call "GET" "/api/developer/sync-jobs/42"
}

@test "jobs sync-log hits sync job log endpoint" {
    load_command jobs
    cmd_jobs sync-log 42
    assert_http_call "GET" "/api/developer/sync-jobs/42/log"
}

@test "jobs list hits job-logs endpoint" {
    load_command jobs
    cmd_jobs list abc-123
    assert_http_call "GET" "/api/developer/companies/abc-123/job-logs"
}

@test "jobs list with limit" {
    load_command jobs
    cmd_jobs list abc-123 --limit 10
    local calls=$(get_http_calls)
    [[ "$calls" == *"limit=10"* ]]
}

@test "jobs stale hits stale-jobs endpoint" {
    load_command jobs
    cmd_jobs stale
    assert_http_call "GET" "/api/developer/syshealth/cleanup/stale-jobs"
}

@test "jobs restart-history hits restart-history endpoint" {
    load_command jobs
    cmd_jobs restart-history
    assert_http_call "GET" "/api/developer/syshealth/restart-history"
}

@test "jobs restart-history with limit" {
    load_command jobs
    cmd_jobs restart-history --limit 5
    local calls=$(get_http_calls)
    [[ "$calls" == *"limit=5"* ]]
}

@test "jobs help shows all subcommands" {
    load_command jobs
    run cmd_jobs --help
    [[ "$output" == *"sync"* ]]
    [[ "$output" == *"sync-log"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"stale"* ]]
    [[ "$output" == *"restart-history"* ]]
}

@test "ifn dispatches jobs command" {
    run grep -c "jobs)" "${TOOLS_DIR}/ifn"
    [[ "$output" != "0" ]]
}

# ============================================================
# Issue #07: companies doc-types + browse record-counts
# ============================================================

@test "companies doc-types hits allowed-doc-types endpoint" {
    load_command companies
    cmd_companies doc-types abc-123
    assert_http_call "GET" "/api/companies/abc-123/allowed-doc-types"
}

@test "browse record-counts hits record-counts endpoint" {
    load_command browse
    cmd_browse abc-123 record-counts
    assert_http_call "GET" "/api/companies/abc-123/external/record-counts"
}

# ============================================================
# Issue #08: new query params on existing commands
# ============================================================

@test "analysis accounts with --include-staged" {
    load_command analysis
    cmd_analysis accounts abc-123 --include-staged
    local calls=$(get_http_calls)
    [[ "$calls" == *"include_staged=true"* ]]
}

@test "records list with --email filter" {
    load_command records
    cmd_records abc-123 customers --email "test@example.com"
    local calls=$(get_http_calls)
    [[ "$calls" == *"email=test@example.com"* ]]
}

@test "records list with --phone filter" {
    load_command records
    cmd_records abc-123 suppliers --phone "555-1234"
    local calls=$(get_http_calls)
    [[ "$calls" == *"phone=555-1234"* ]]
}

@test "records list with --referencenumber filter" {
    load_command records
    cmd_records abc-123 vouchers --referencenumber "REF-001"
    local calls=$(get_http_calls)
    [[ "$calls" == *"referencenumber=REF-001"* ]]
}

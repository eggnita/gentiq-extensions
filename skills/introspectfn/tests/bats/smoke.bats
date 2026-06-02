#!/usr/bin/env bats
# Smoke test — verify bats infrastructure and HTTP mocking work

load test_helper

setup() {
    mock_setup
}

teardown() {
    mock_teardown
}

@test "mock captures HTTP GET call" {
    load_command browse
    cmd_browse abc-123 vouchers
    assert_http_call "GET" "/api/companies/abc-123/external/vouchers"
}

@test "mock captures HTTP POST call" {
    ifn_post "/api/test/path"
    assert_http_call "POST" "/api/test/path"
}

@test "mock returns canned response" {
    mock_set_response '{"status":"ok"}'
    local result
    result=$(ifn_get "/any/path")
    [[ "$result" == '{"status":"ok"}' ]]
}

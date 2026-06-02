#!/usr/bin/env bats
# Tests for issue #04: staging extensions (archive, uploads, file-refs)

load test_helper

setup() { mock_setup; }
teardown() { mock_teardown; }

@test "staging archive bulk hits archive endpoint" {
    load_command staging
    cmd_staging archive
    assert_http_call "POST" "/api/bk-staging/archive"
}

@test "staging archive single action" {
    load_command staging
    cmd_staging archive --action-id 42
    assert_http_call "POST" "/api/bk-staging/42/archive"
}

@test "staging file-refs sends PATCH" {
    load_command staging
    cmd_staging file-refs 42 --data '["file-1","file-2"]'
    local calls=$(get_http_calls)
    [[ "$calls" == *"PATCH /api/bk-staging/42/file-refs"* ]]
    [[ "$calls" == *'["file-1","file-2"]'* ]]
}

@test "staging uploads lists staged uploads" {
    load_command staging
    cmd_staging uploads 42
    assert_http_call "GET" "/api/bk-staging/42/uploads"
}

@test "staging upload-action uploads file to action" {
    load_command staging
    local tmpfile=$(mktemp)
    echo "test" > "$tmpfile"
    cmd_staging upload-action 42 "$tmpfile"
    assert_http_call "UPLOAD" "/api/bk-staging/42/upload-file"
    rm -f "$tmpfile"
}

@test "staging remove-upload deletes upload" {
    load_command staging
    cmd_staging remove-upload 42 file-99
    assert_http_call "DELETE" "/api/bk-staging/42/uploads/file-99"
}

@test "staging help shows new subcommands" {
    load_command staging
    run cmd_staging --help
    [[ "$output" == *"archive"* ]]
    [[ "$output" == *"file-refs"* ]]
    [[ "$output" == *"uploads"* ]]
    [[ "$output" == *"upload-action"* ]]
    [[ "$output" == *"remove-upload"* ]]
}

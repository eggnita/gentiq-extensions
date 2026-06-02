#!/usr/bin/env bats
# Tests for issue #03: xcompanies command group

load test_helper

setup() { mock_setup; }
teardown() { mock_teardown; }

@test "xcompanies summary hits summary endpoint" {
    load_command xcompanies
    cmd_xcompanies summary
    assert_http_call "GET" "/api/xcompanies/summary"
}

@test "xcompanies vouchers hits vouchers endpoint" {
    load_command xcompanies
    cmd_xcompanies vouchers
    assert_http_call "GET" "/api/xcompanies/vouchers"
}

@test "xcompanies vouchers with filters" {
    load_command xcompanies
    cmd_xcompanies vouchers --from-date 2025-01-01 --to-date 2025-12-31 --series A --number 100 --page 2 --limit 25
    local calls=$(get_http_calls)
    [[ "$calls" == *"/api/xcompanies/vouchers?"* ]]
    [[ "$calls" == *"from_date=2025-01-01"* ]]
    [[ "$calls" == *"to_date=2025-12-31"* ]]
    [[ "$calls" == *"series=A"* ]]
    [[ "$calls" == *"number=100"* ]]
    [[ "$calls" == *"page=2"* ]]
    [[ "$calls" == *"limit=25"* ]]
}

@test "xcompanies invoices hits invoices endpoint" {
    load_command xcompanies
    cmd_xcompanies invoices
    assert_http_call "GET" "/api/xcompanies/invoices"
}

@test "xcompanies invoices with date filters" {
    load_command xcompanies
    cmd_xcompanies invoices --from-date 2025-01-01 --to-date 2025-06-30
    local calls=$(get_http_calls)
    [[ "$calls" == *"from_date=2025-01-01"* ]]
    [[ "$calls" == *"to_date=2025-06-30"* ]]
}

@test "xcompanies supplierinvoices hits endpoint" {
    load_command xcompanies
    cmd_xcompanies supplierinvoices
    assert_http_call "GET" "/api/xcompanies/supplierinvoices"
}

@test "xcompanies suppliers with search" {
    load_command xcompanies
    cmd_xcompanies suppliers --search "Acme"
    local calls=$(get_http_calls)
    [[ "$calls" == *"/api/xcompanies/suppliers?"* ]]
    [[ "$calls" == *"search=Acme"* ]]
}

@test "xcompanies customers hits endpoint" {
    load_command xcompanies
    cmd_xcompanies customers
    assert_http_call "GET" "/api/xcompanies/customers"
}

@test "xcompanies accounts with number range" {
    load_command xcompanies
    cmd_xcompanies accounts --number-min 1000 --number-max 1999
    local calls=$(get_http_calls)
    [[ "$calls" == *"number_min=1000"* ]]
    [[ "$calls" == *"number_max=1999"* ]]
}

@test "xcompanies accounts with financial-year-id" {
    load_command xcompanies
    cmd_xcompanies accounts --financial-year-id FY-1
    local calls=$(get_http_calls)
    [[ "$calls" == *"financial_year_id=FY-1"* ]]
}

@test "xcompanies files with filters" {
    load_command xcompanies
    cmd_xcompanies files --doc-type invoices --category incoming --needs-categorization
    local calls=$(get_http_calls)
    [[ "$calls" == *"doc_type=invoices"* ]]
    [[ "$calls" == *"category=incoming"* ]]
    [[ "$calls" == *"needs_categorization=true"* ]]
}

@test "xcompanies files-categories hits endpoint" {
    load_command xcompanies
    cmd_xcompanies files-categories
    assert_http_call "GET" "/api/xcompanies/files/categories"
}

@test "xcompanies files-groups hits endpoint" {
    load_command xcompanies
    cmd_xcompanies files-groups
    assert_http_call "GET" "/api/xcompanies/files/groups"
}

@test "xcompanies help shows all subcommands" {
    load_command xcompanies
    run cmd_xcompanies --help
    [[ "$output" == *"summary"* ]]
    [[ "$output" == *"vouchers"* ]]
    [[ "$output" == *"invoices"* ]]
    [[ "$output" == *"supplierinvoices"* ]]
    [[ "$output" == *"suppliers"* ]]
    [[ "$output" == *"customers"* ]]
    [[ "$output" == *"accounts"* ]]
    [[ "$output" == *"files"* ]]
    [[ "$output" == *"files-categories"* ]]
    [[ "$output" == *"files-groups"* ]]
}

@test "ifn dispatches xcompanies command" {
    run grep -c "xcompanies)" "${TOOLS_DIR}/ifn"
    [[ "$output" != "0" ]]
}

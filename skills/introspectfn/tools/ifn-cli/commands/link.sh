#!/usr/bin/env bash
# link.sh — Generate deep links into the IntrospectFN web app.
# These URLs can be included in messages to help users navigate directly
# to the relevant page in the web UI.

cmd_link() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        company)             _link_company "$@" ;;
        voucher)             _link_voucher "$@" ;;
        vouchers)            _link_vouchers "$@" ;;
        invoice)             _link_invoice "$@" ;;
        invoices)            _link_invoices "$@" ;;
        supplier-invoice)    _link_supplier_invoice "$@" ;;
        supplier-invoices)   _link_supplier_invoices "$@" ;;
        account-analysis)    _link_account_analysis "$@" ;;
        staging)             _link_staging "$@" ;;
        staging-list)        _link_staging_list "$@" ;;
        file)                _link_file "$@" ;;
        files)               _link_files "$@" ;;
        inbox)               _link_inbox "$@" ;;
        integrity)           _link_integrity "$@" ;;
        sync)                _link_sync "$@" ;;
        customer)            _link_customer "$@" ;;
        supplier)            _link_supplier "$@" ;;
        resource)            _link_resource "$@" ;;
        --help|-h|"")
            echo "Usage: ifn link <type> <company_id> [args] [options]"
            echo ""
            echo "Generate deep links into the IntrospectFN web app."
            echo "Web URL: ${IFN_WEB_URL}"
            echo ""
            echo "Types:"
            echo "  company            <company_id>                              Company dashboard"
            echo "  voucher            <company_id> <series> <number> [--fy id]  Voucher detail"
            echo "  vouchers           <company_id> [--fy id] [--from d] [--to d] Voucher list"
            echo "  invoice            <company_id> <number>                     Invoice detail"
            echo "  invoices           <company_id> [--from d] [--to d]          Invoice list"
            echo "  supplier-invoice   <company_id> <number>                     Supplier invoice"
            echo "  supplier-invoices  <company_id> [--from d] [--to d]          Supplier invoice list"
            echo "  account-analysis   <company_id> [--account n] [--from d]     Account analysis"
            echo "  staging            <company_id> <action_id>                  Staging action detail"
            echo "  staging-list       <company_id>                              Staging list"
            echo "  file               <company_id> <file_id>                    File detail"
            echo "  files              <company_id> [--doc-type t] [--search q]  Files list"
            echo "  inbox              <company_id> [folder_id] [file_id]        Inbox"
            echo "  integrity          <company_id>                              Integrity check"
            echo "  sync               <company_id>                              Sync status"
            echo "  customer           <company_id> <number>                     Customer detail"
            echo "  supplier           <company_id> <number>                     Supplier detail"
            echo "  resource           <company_id> <resource> [record_id]       Generic resource"
            ;;
        *)
            ifn_error "unknown link type: $subcmd"
            echo "Run 'ifn link --help' for usage." >&2
            return 1
            ;;
    esac
}

_link_company() {
    ifn_require_arg "${1:-}" "company_id" "ifn link company <company_id>"
    ifn_link_company "$1"
}

_link_voucher() {
    ifn_require_arg "${1:-}" "company_id" "ifn link voucher <company_id> <series> <number> [--fy id]"
    ifn_require_arg "${2:-}" "series" "ifn link voucher <company_id> <series> <number> [--fy id]"
    ifn_require_arg "${3:-}" "number" "ifn link voucher <company_id> <series> <number> [--fy id]"
    local company_id="$1" series="$2" number="$3"
    shift 3
    local fy=""
    while [ $# -gt 0 ]; do
        case "$1" in --fy) fy="$2"; shift 2 ;; *) shift ;; esac
    done
    ifn_link_voucher "$company_id" "$series" "$number" "$fy"
}

_link_vouchers() {
    ifn_require_arg "${1:-}" "company_id" "ifn link vouchers <company_id> [options]"
    local company_id="$1"; shift
    ifn_link_vouchers "$company_id" "$@"
}

_link_invoice() {
    ifn_require_arg "${1:-}" "company_id" "ifn link invoice <company_id> <number>"
    ifn_require_arg "${2:-}" "number" "ifn link invoice <company_id> <number>"
    ifn_link_invoice "$1" "$2"
}

_link_invoices() {
    ifn_require_arg "${1:-}" "company_id" "ifn link invoices <company_id> [options]"
    local company_id="$1"; shift
    ifn_link_invoices "$company_id" "$@"
}

_link_supplier_invoice() {
    ifn_require_arg "${1:-}" "company_id" "ifn link supplier-invoice <company_id> <number>"
    ifn_require_arg "${2:-}" "number" "ifn link supplier-invoice <company_id> <number>"
    ifn_link_supplier_invoice "$1" "$2"
}

_link_supplier_invoices() {
    ifn_require_arg "${1:-}" "company_id" "ifn link supplier-invoices <company_id> [options]"
    local company_id="$1"; shift
    ifn_link_supplier_invoices "$company_id" "$@"
}

_link_account_analysis() {
    ifn_require_arg "${1:-}" "company_id" "ifn link account-analysis <company_id> [options]"
    local company_id="$1"; shift
    ifn_link_account_analysis "$company_id" "$@"
}

_link_staging() {
    ifn_require_arg "${1:-}" "company_id" "ifn link staging <company_id> <action_id>"
    ifn_require_arg "${2:-}" "action_id" "ifn link staging <company_id> <action_id>"
    ifn_link_staging "$1" "$2"
}

_link_staging_list() {
    ifn_require_arg "${1:-}" "company_id" "ifn link staging-list <company_id>"
    ifn_link_staging_list "$1"
}

_link_file() {
    ifn_require_arg "${1:-}" "company_id" "ifn link file <company_id> <file_id>"
    ifn_require_arg "${2:-}" "file_id" "ifn link file <company_id> <file_id>"
    ifn_link_file "$1" "$2"
}

_link_files() {
    ifn_require_arg "${1:-}" "company_id" "ifn link files <company_id> [options]"
    local company_id="$1"; shift
    ifn_link_files "$company_id" "$@"
}

_link_inbox() {
    ifn_require_arg "${1:-}" "company_id" "ifn link inbox <company_id> [folder_id] [file_id]"
    local company_id="$1"
    local folder_id="${2:-}"
    local file_id="${3:-}"
    ifn_link_inbox "$company_id" "$folder_id" "$file_id"
}

_link_integrity() {
    ifn_require_arg "${1:-}" "company_id" "ifn link integrity <company_id>"
    ifn_link_integrity "$1"
}

_link_sync() {
    ifn_require_arg "${1:-}" "company_id" "ifn link sync <company_id>"
    ifn_link_sync "$1"
}

_link_customer() {
    ifn_require_arg "${1:-}" "company_id" "ifn link customer <company_id> <number>"
    ifn_require_arg "${2:-}" "number" "ifn link customer <company_id> <number>"
    ifn_link_customer "$1" "$2"
}

_link_supplier() {
    ifn_require_arg "${1:-}" "company_id" "ifn link supplier <company_id> <number>"
    ifn_require_arg "${2:-}" "number" "ifn link supplier <company_id> <number>"
    ifn_link_supplier "$1" "$2"
}

_link_resource() {
    ifn_require_arg "${1:-}" "company_id" "ifn link resource <company_id> <resource> [record_id]"
    ifn_require_arg "${2:-}" "resource" "ifn link resource <company_id> <resource> [record_id]"
    ifn_link_resource "$1" "$2" "${3:-}"
}

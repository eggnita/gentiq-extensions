#!/usr/bin/env bash
# deeplink.sh — Build deep links into the IntrospectFN web app.
# All functions output a full URL using IFN_WEB_URL as the base.

# Build a web app URL from path segments.
# Usage: ifn_web_url "/company/${conn_id}/vouchers"
ifn_web_url() {
    local path="${1:-}"
    echo "${IFN_WEB_URL}${path}"
}

# --- Entity deep links ---

# Company dashboard
ifn_link_company() {
    local conn_id="$1"
    ifn_web_url "/company/${conn_id}"
}

# Voucher detail: series + number + financial year
ifn_link_voucher() {
    local conn_id="$1"
    local series="$2"
    local number="$3"
    local fy="${4:-}"
    local url="/company/${conn_id}/vouchers/${series}/${number}"
    [ -n "$fy" ] && url="${url}?financialyear=${fy}"
    ifn_web_url "$url"
}

# Voucher list (optionally filtered)
ifn_link_vouchers() {
    local conn_id="$1"
    shift
    local qs=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --fy)       qs="${qs}&financialyear=$2"; shift 2 ;;
            --from)     qs="${qs}&fromdate=$2"; shift 2 ;;
            --to)       qs="${qs}&todate=$2"; shift 2 ;;
            --series)   qs="${qs}&series=$2"; shift 2 ;;
            *)          shift ;;
        esac
    done
    local url="/company/${conn_id}/vouchers"
    [ -n "$qs" ] && url="${url}?${qs:1}"
    ifn_web_url "$url"
}

# Invoice detail
ifn_link_invoice() {
    local conn_id="$1"
    local number="$2"
    ifn_web_url "/company/${conn_id}/invoices/${number}"
}

# Invoice list
ifn_link_invoices() {
    local conn_id="$1"
    shift
    local qs=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --from)     qs="${qs}&fromdate=$2"; shift 2 ;;
            --to)       qs="${qs}&todate=$2"; shift 2 ;;
            --customer) qs="${qs}&customername=$2"; shift 2 ;;
            *)          shift ;;
        esac
    done
    local url="/company/${conn_id}/invoices"
    [ -n "$qs" ] && url="${url}?${qs:1}"
    ifn_web_url "$url"
}

# Supplier invoice detail
ifn_link_supplier_invoice() {
    local conn_id="$1"
    local number="$2"
    ifn_web_url "/company/${conn_id}/supplierinvoices/${number}"
}

# Supplier invoice list
ifn_link_supplier_invoices() {
    local conn_id="$1"
    shift
    local qs=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --from)     qs="${qs}&fromdate=$2"; shift 2 ;;
            --to)       qs="${qs}&todate=$2"; shift 2 ;;
            --supplier) qs="${qs}&suppliername=$2"; shift 2 ;;
            *)          shift ;;
        esac
    done
    local url="/company/${conn_id}/supplierinvoices"
    [ -n "$qs" ] && url="${url}?${qs:1}"
    ifn_web_url "$url"
}

# Account analysis (specific account with optional date range)
ifn_link_account_analysis() {
    local conn_id="$1"
    shift
    local qs=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --account) qs="${qs}&account=$2"; shift 2 ;;
            --from)    qs="${qs}&fromdate=$2"; shift 2 ;;
            --to)      qs="${qs}&todate=$2"; shift 2 ;;
            *)         shift ;;
        esac
    done
    local url="/company/${conn_id}/account-analysis"
    [ -n "$qs" ] && url="${url}?${qs:1}"
    ifn_web_url "$url"
}

# Staging action detail
ifn_link_staging() {
    local conn_id="$1"
    local action_id="$2"
    ifn_web_url "/company/${conn_id}/staging/${action_id}"
}

# Staging list for a company
ifn_link_staging_list() {
    local conn_id="$1"
    ifn_web_url "/company/${conn_id}/staging"
}

# File detail
ifn_link_file() {
    local conn_id="$1"
    local file_id="$2"
    ifn_web_url "/company/${conn_id}/files/${file_id}"
}

# Files list
ifn_link_files() {
    local conn_id="$1"
    shift
    local qs=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --doc-type) qs="${qs}&doc_type=$2"; shift 2 ;;
            --search)   qs="${qs}&search=$2"; shift 2 ;;
            *)          shift ;;
        esac
    done
    local url="/company/${conn_id}/files"
    [ -n "$qs" ] && url="${url}?${qs:1}"
    ifn_web_url "$url"
}

# Inbox folder
ifn_link_inbox() {
    local conn_id="$1"
    local folder_id="${2:-}"
    local file_id="${3:-}"
    local url="/company/${conn_id}/inbox"
    [ -n "$folder_id" ] && url="${url}/${folder_id}"
    [ -n "$file_id" ] && url="${url}/${file_id}"
    ifn_web_url "$url"
}

# Integrity check
ifn_link_integrity() {
    local conn_id="$1"
    ifn_web_url "/company/${conn_id}/integrity"
}

# Sync status
ifn_link_sync() {
    local conn_id="$1"
    ifn_web_url "/company/${conn_id}/sync"
}

# Customer detail
ifn_link_customer() {
    local conn_id="$1"
    local number="$2"
    ifn_web_url "/company/${conn_id}/customers/${number}"
}

# Supplier detail
ifn_link_supplier() {
    local conn_id="$1"
    local number="$2"
    ifn_web_url "/company/${conn_id}/suppliers/${number}"
}

# Generic resource (fallback)
ifn_link_resource() {
    local conn_id="$1"
    local resource="$2"
    local record_id="${3:-}"
    local url="/company/${conn_id}/${resource}"
    [ -n "$record_id" ] && url="${url}/${record_id}"
    ifn_web_url "$url"
}

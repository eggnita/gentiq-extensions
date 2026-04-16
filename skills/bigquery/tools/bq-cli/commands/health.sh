#!/usr/bin/env bash
# health.sh — Check BigQuery connectivity
# Usage: bq-tool health

cmd_health() {
    bq_require_auth || exit 1

    local sa_email
    sa_email=$(bq_sa_email)

    bq_debug "Checking BigQuery connectivity for project: ${BQ_PROJECT_ID}"

    if bq_verify_connection; then
        jq -n \
            --arg project "$BQ_PROJECT_ID" \
            --arg sa_email "$sa_email" \
            --arg location "$BQ_LOCATION" \
            '{ok: true, project: $project, sa_email: $sa_email, location: $location, message: "Connected to BigQuery"}'
    else
        jq -n \
            --arg project "$BQ_PROJECT_ID" \
            --arg sa_email "$sa_email" \
            '{ok: false, project: $project, sa_email: $sa_email, message: "Failed to connect to BigQuery"}'
        exit 1
    fi
}

#!/usr/bin/env bash
# jobs.sh — List and inspect BigQuery jobs
# Usage: bq-tool jobs [--limit N]
#        bq-tool job <job_id>

cmd_jobs() {
    bq_require_auth || exit 1

    local limit=10

    # Parse flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --limit|-n)
                limit="${2:-10}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    bq_debug "Listing last ${limit} jobs in project: ${BQ_PROJECT_ID}"

    local result
    result=$(bq_api_get "/projects/${BQ_PROJECT_ID}/jobs?maxResults=${limit}&projection=minimal") || {
        bq_error "Failed to list jobs"
        exit 1
    }

    if [ "$BQ_RAW_JSON" = "true" ]; then
        echo "$result"
    else
        echo "$result" | jq '[.jobs[]? | {
            jobId: .jobReference.jobId,
            state: .status.state,
            type: .configuration.jobType,
            creationTime: .statistics.creationTime,
            user: .user_email
        }]' 2>/dev/null || echo "$result" | jq '.'
    fi
}

cmd_job_detail() {
    bq_require_auth || exit 1
    bq_require_arg "${1:-}" "job_id" "bq-tool job <job_id>"

    local job_id="$1"

    bq_debug "Getting details for job: ${job_id}"

    local result
    result=$(bq_api_get "/projects/${BQ_PROJECT_ID}/jobs/${job_id}") || {
        bq_error "Failed to get job details"
        exit 1
    }

    bq_output "$result"
}

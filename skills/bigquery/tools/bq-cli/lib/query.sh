#!/usr/bin/env bash
# query.sh — SQL safety validation for BigQuery
# Defense-in-depth: application-level validation + cost control + IAM
#
# Only SELECT statements are allowed. All DDL/DML is rejected.

# Forbidden SQL keywords (case-insensitive check after normalization)
BQ_FORBIDDEN_KEYWORDS=(
    "INSERT"
    "UPDATE"
    "DELETE"
    "DROP"
    "CREATE"
    "ALTER"
    "MERGE"
    "TRUNCATE"
    "CALL"
    "GRANT"
    "REVOKE"
    "EXECUTE"
    "LOAD"
    "EXPORT"
)

# Validate a SQL query is read-only (SELECT only)
# Returns 0 if safe, 1 if rejected
# Usage: bq_validate_query "SELECT * FROM dataset.table"
bq_validate_query() {
    local sql="$1"

    if [ -z "$sql" ]; then
        bq_error "Empty query"
        return 1
    fi

    # Normalize: strip single-line comments (--), collapse to one line, strip leading/trailing whitespace
    local normalized
    normalized=$(echo "$sql" | \
        sed 's/--.*$//' | \
        tr '\n' ' ' | \
        sed 's|/\*[^*]*\*/||g' | \
        tr -s ' ')
    # Trim leading/trailing whitespace
    normalized="${normalized#"${normalized%%[![:space:]]*}"}"
    normalized="${normalized%"${normalized##*[![:space:]]}"}"

    # Convert to uppercase for keyword matching
    local upper
    upper=$(echo "$normalized" | tr '[:lower:]' '[:upper:]')

    # Check that query starts with SELECT or WITH (CTEs)
    case "$upper" in
        SELECT*|WITH*) ;;
        *)
            bq_error "Only SELECT queries are allowed. Query must start with SELECT or WITH."
            return 1
            ;;
    esac

    # Check for forbidden keywords as standalone tokens
    for keyword in "${BQ_FORBIDDEN_KEYWORDS[@]}"; do
        # Use word-boundary matching via awk for portability
        if echo "$upper" | awk -v kw="$keyword" 'BEGIN{r=1} {if(match($0, "(^|[^A-Z_])" kw "([^A-Z_]|$)")) r=0} END{exit r}'; then
            bq_error "Forbidden SQL keyword detected: ${keyword}. Only read-only SELECT queries are allowed."
            return 1
        fi
    done

    return 0
}

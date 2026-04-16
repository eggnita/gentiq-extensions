# BigQuery Data Lake Skill — Setup Guide

This guide walks you through creating a Google Cloud service account with BigQuery read access, downloading the JSON key, and configuring it in GentiqOS.

## Prerequisites

- A Google Cloud account with **Owner** or **IAM Admin** permissions on the target project
- The target GCP project must have billing enabled (BigQuery requires it for queries)
- The Gent machine needs `curl`, `jq`, and `openssl` (pre-installed on virtually all Linux systems)
- **No Google Cloud SDK required** — the skill talks directly to the BigQuery REST API

## Step 1: Enable the BigQuery API

Before creating the service account, make sure the BigQuery API is turned on in your project.

1. Open [Google Cloud Console](https://console.cloud.google.com/)
2. In the top navigation bar, click the **project dropdown** (next to "Google Cloud") and select the project that contains your BigQuery data. If you don't see it, click **All** and search by name or ID
3. Open the left sidebar menu (**hamburger icon**, top-left) and navigate to **APIs & Services > Library**
4. In the search bar, type **BigQuery API**
5. Click on **BigQuery API** in the results
6. If the button says **Enable**, click it and wait a few seconds. If it says **Manage**, the API is already enabled — you can skip to Step 2

## Step 2: Create a Service Account

A service account is a special Google account that represents the Gent (not a human). It gets its own email address and credentials.

1. In the left sidebar, navigate to **IAM & Admin > Service Accounts**
   - Direct link: [console.cloud.google.com/iam-admin/serviceaccounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
   - Make sure the correct project is selected in the top bar
2. Click **+ Create Service Account** at the top of the page
3. Fill in the **Service account details**:
   - **Service account name**: `gent-bigquery-reader` (or any descriptive name like `gent-data-analyst`)
   - **Service account ID**: auto-fills based on the name (e.g., `gent-bigquery-reader`). This becomes the email: `gent-bigquery-reader@your-project.iam.gserviceaccount.com`
   - **Description**: `Read-only BigQuery access for Gent virtual employee`
4. Click **Create and Continue**

## Step 3: Assign Roles (Permissions)

Still on the service account creation page, you'll see "Grant this service account access to project". You need to add exactly two roles.

1. Click the **Select a role** dropdown
2. In the filter/search box, type `BigQuery Data Viewer`
3. Select **BigQuery Data Viewer** (`roles/bigquery.dataViewer`) — this grants read access to all datasets and tables in the project
4. Click **+ Add Another Role**
5. In the new dropdown, type `BigQuery Job User`
6. Select **BigQuery Job User** (`roles/bigquery.jobUser`) — this allows the service account to run query jobs (required to execute SQL)
7. Click **Continue**
8. Skip the "Grant users access to this service account" section — just click **Done**

### Roles Summary

| Role | What it allows |
|------|---------------|
| **BigQuery Data Viewer** | Read table data, list datasets/tables, view schemas |
| **BigQuery Job User** | Submit and manage query jobs |

### Roles to AVOID

Do **not** grant any of these — they allow write operations that bypass the skill's safety controls:

| Role | Why to avoid |
|------|-------------|
| BigQuery Data Editor | Allows INSERT, UPDATE, DELETE on tables |
| BigQuery Admin | Full admin access including DDL (CREATE, DROP) |
| BigQuery User | Broader than needed — includes creating datasets |
| Owner / Editor | Project-wide access — far too broad |

### Restricting to Specific Datasets (Optional)

If you only want the Gent to access certain datasets (not all data in the project):

1. Go to **BigQuery** in the left sidebar (or [console.cloud.google.com/bigquery](https://console.cloud.google.com/bigquery))
2. In the Explorer panel, find the dataset you want to share
3. Click the **three-dot menu** next to the dataset name > **Share**
4. Click **Add Principal**
5. Paste the service account email (e.g., `gent-bigquery-reader@your-project.iam.gserviceaccount.com`)
6. Assign the role **BigQuery Data Viewer**
7. Click **Save**
8. Repeat for each dataset the Gent should access

When using dataset-level permissions, you can skip adding `BigQuery Data Viewer` at the project level in Step 3 — only add `BigQuery Job User` at the project level (still required for running queries).

## Step 4: Create and Download the JSON Key

Now you need to generate a key file that the Gent will use to authenticate.

1. You should now see your new service account in the list at **IAM & Admin > Service Accounts**. Click on its **email address** to open it
2. Click the **Keys** tab at the top
3. Click **Add Key > Create new key**
4. In the dialog, select **JSON** (not P12) and click **Create**
5. A `.json` file will automatically download to your computer. This is the service account key — **keep it safe**

The downloaded file looks like this:

```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "abc123def456...",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQ...\n-----END PRIVATE KEY-----\n",
  "client_email": "gent-bigquery-reader@your-project.iam.gserviceaccount.com",
  "client_id": "123456789012345678901",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/gent-bigquery-reader%40your-project.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
```

**Important:**
- This file contains a private key — treat it like a password
- Do not commit it to version control
- Do not share it via email or chat — use the GentiqOS setup UI (next step)
- You can delete the local file after pasting it into the setup UI
- If you lose it, you can create a new key (Step 4 again) and delete the old one

### Finding Your Project ID

If you're unsure of your project ID:

1. Look at the top navigation bar in the Cloud Console — the project name and ID are shown in the project selector dropdown
2. Or go to **IAM & Admin > Settings** — the Project ID is displayed at the top
3. Or check the `project_id` field in the downloaded JSON key file

## Step 5: Configure in GentiqOS Dashboard

1. Open the **GentiqOS admin dashboard**
2. Navigate to the Gent you want to configure
3. Go to **Skills** and find the **BigQuery Data Lake** skill
4. Click **Setup / Configure**
5. Fill in the fields:
   - **GCP Project ID**: your project ID (e.g., `my-company-analytics-prod`). This is the `project_id` from the JSON key file
   - **Default Dataset** (optional): if most queries target one dataset, enter it here (e.g., `analytics`). The Gent can still query other datasets by fully qualifying table names
   - **Service Account JSON**: open the downloaded `.json` key file in a text editor, select **all** the content (`Ctrl+A` / `Cmd+A`), copy it (`Ctrl+C` / `Cmd+C`), and paste it into this field
   - **Note**: You do not need to select a location — dataset locations are auto-discovered from the BigQuery API
6. Click **Connect to BigQuery**

The setup UI validates that:
- The JSON is valid and parseable
- It contains `"type": "service_account"`
- It has a `client_email` field

After submission, the skill's `on_setup_complete` hook will:
- Write the JSON key to a secure location on the Gent's machine
- Authenticate via the BigQuery REST API (JWT signing with openssl)
- Test the connection by listing BigQuery datasets
- Report success or failure back to the dashboard

## Step 6: Write DATALAKE.md (Recommended)

Create a `DATALAKE.md` file in the Gent's workspace describing your data lake structure. See `DATALAKE.md.example` for a template.

This file helps the Gent:
- Understand table relationships and what each table represents
- Use correct partition filters to avoid expensive full-table scans
- Avoid forbidden query patterns specific to your data
- Follow your team's query conventions and naming standards

Without this file the Gent can still explore schemas and query data, but may write suboptimal queries or miss important business context about what columns mean.

## Step 7: Verify

After setup completes, the skill will automatically:
1. Write the SA JSON to `~/.config/gent-bq/credentials.json` (chmod 600)
2. Authenticate via the BigQuery REST API (JWT signing with openssl)
3. Verify BigQuery connectivity by listing datasets

Check the skill status in the dashboard to confirm "Connected".

You can also verify manually by asking the Gent:
- "Check BigQuery health" — runs `bq-tool health`
- "List my datasets" — runs `bq-tool datasets`
- "Show me the schema of dataset.table_name" — runs `bq-tool schema`

## Rotating or Revoking the Key

### Rotating the Key (e.g., on a schedule or after a team member leaves)

1. Go to **IAM & Admin > Service Accounts** in the Cloud Console
2. Click on the service account email
3. Go to the **Keys** tab
4. Click **Add Key > Create new key > JSON** — download the new key
5. In the GentiqOS dashboard, go to the Gent's BigQuery skill settings and update the Service Account JSON with the new key content
6. After confirming the Gent reconnects successfully, go back to the **Keys** tab in Cloud Console
7. Find the **old** key (by key ID or creation date) and click the **trash icon** to delete it

### Revoking Access Entirely

1. Go to **IAM & Admin > Service Accounts**
2. Find the service account and click the **three-dot menu** > **Delete**
3. Confirm deletion — this immediately revokes all access
4. Uninstall the BigQuery skill from the Gent in the GentiqOS dashboard

## Security Notes

- The SA JSON key is stored at `~/.config/gent-bq/credentials.json` with `chmod 600`
- The config directory has `chmod 700`
- Only SELECT queries are allowed (enforced at application, `bq` CLI, and IAM levels)
- A cost guard (`BQ_MAX_BYTES_BILLED`) limits maximum bytes per query (default: 1 GB)
- The service account should have minimal permissions (dataViewer + jobUser only)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "curl not installed" | Install curl: `apt install curl` (Debian/Ubuntu) or `yum install curl` (RHEL) |
| "openssl not installed" | Install openssl: `apt install openssl` (usually pre-installed) |
| "jq not installed" | Install jq: `apt install jq` or `yum install jq` |
| "Failed to obtain access token" | Check SA JSON is valid, private key is present, and the SA is not disabled in GCP Console |
| "BigQuery connection verification failed" | Check SA has correct roles (`dataViewer` + `jobUser`) and BigQuery API is enabled |
| "API error (HTTP 403)" | The service account lacks required permissions — check IAM roles |
| "API error (HTTP 404)" | Dataset or table not found — check the project ID and resource names |
| "Query exceeded maximum bytes billed" | Add partition filters, select fewer columns, or increase `BQ_MAX_BYTES_BILLED` |
| "Forbidden SQL keyword detected" | Only SELECT/WITH queries are allowed — no DDL/DML |

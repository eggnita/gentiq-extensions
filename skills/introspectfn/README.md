# IntrospectFN Skill

Virtual bookkeeper skill for the Gentiq platform. Connects to the [IntrospectFN](https://introspectfn.com) ERP management API for Fortnox-based accounting, settlement reconciliation, and bookkeeping automation.

## CLI Tool: `ifn`

All operations use the `ifn` CLI (v0.2.6). Installed at `~/bin/ifn`.

```
ifn <command> [subcommand] [options]
```

### Global Options

| Flag | Description |
|------|-------------|
| `--json` | Raw JSON output (no formatting) |
| `--verbose`, `-v` | Verbose output |
| `--insecure` | Skip SSL certificate validation |
| `--help`, `-h` | Show help |

---

## Commands

### `ifn health`

Check API connectivity and authentication status.

```bash
ifn health
```

Returns: `{ ok, status, base_url }`

---

### `ifn companies`

List connected ERP companies and their document types.

```bash
ifn companies list                        # List all connected companies
ifn companies doc-types <company_id>      # Allowed document types for a company
```

The `list` output includes: company name, org number, company ID, token health, and creation date.

---

### `ifn dashboard`

Dashboard metrics for a specific company.

```bash
ifn dashboard <company_id>
```

Returns: unbooked vouchers, staged actions, sync freshness.

---

### `ifn browse`

Browse **live** ERP records (proxied directly from Fortnox).

```bash
ifn browse <company_id> <resource> [record_id] [options]
```

**Resources:** `customers`, `invoices`, `articles`, `accounts`, `vouchers`, `suppliers`, `orders`, `offers`, `projects`, `costcenters`, `supplierinvoices`, `companyinformation`, `financialyears`, `voucherseries`

**Options:**

| Flag | Description |
|------|-------------|
| `--page <n>` | Page number (default: 1) |
| `--limit <n>` | Records per page (default: 100) |
| `--filter <expr>` | Fortnox filter expression |
| `--sortby <field>` | Sort field |
| `--sortorder <dir>` | `asc` or `desc` |
| `--fy <id>` | Financial year ID |

**Special subcommands:**

```bash
ifn browse <company_id> account-info <account_number>   # Account description by number
ifn browse <company_id> fileconnections --entity <type>  # File attachments for an entity
ifn browse <company_id> file-counts --entity <type>      # Batch file-connection counts
ifn browse <company_id> record-counts                    # Live record counts from Fortnox
ifn browse <company_id> archive <file_id>                # Download an archive file
ifn browse <company_id> inbox [folder_id]                # List ERP inbox contents
ifn browse <company_id> inbox-file <file_id>             # Download an inbox file
```

---

### `ifn records`

Browse **locally synced** ERP records (faster, works offline).

```bash
ifn records <company_id> <doc_type> [record_id] [options]
```

**Doc types:** `vouchers`, `invoices`, `supplierinvoices`, `customers`, `suppliers`, `accounts`, `financialyears`, `voucherseries`

**Options:**

| Flag | Description |
|------|-------------|
| `--page <n>` | Page number |
| `--limit <n>` | Records per page |
| `--fy <id>` | Financial year ID |
| `--include-staged` | Include staged actions (vouchers only) |
| `--refresh` | Re-fetch a specific record from ERP |
| `--email <email>` | Filter by email |
| `--phone <phone>` | Filter by phone |
| `--referencenumber <ref>` | Filter by reference number |

**Files subcommand:**

```bash
ifn records <company_id> files [options]    # List synced file attachments
    --doc-type <type>                       # Filter by document type
    --search <query>                        # Search text
```

---

### `ifn analysis`

Financial analysis commands.

```bash
ifn analysis accounts <company_id> [--fy <id>] [--include-staged]   # Vouchers grouped by account
ifn analysis balances <company_id> <account_number>                  # Account balance across FYs
ifn analysis integrity <company_id>                                  # Data integrity check
ifn analysis series <company_id>                                     # Voucher series mapping
```

---

### `ifn sync`

Sync management for ERP data.

```bash
ifn sync status <company_id>                 # Current sync job status
ifn sync overview                            # Global sync status across all companies
ifn sync years <company_id>                  # List financial years

ifn sync trigger <company_id> [options]      # Trigger ERP sync
    --doc-types <types>                      # Comma-separated (default: all)
    --fy <id>                                # Financial year ID
    --mode <mode>                            # incremental (default), full, or enrich_only
    --from <date>                            # Start date (YYYY-MM-DD)
    --to <date>                              # End date (YYYY-MM-DD)

ifn sync cancel <company_id> <job_id>        # Cancel a running sync
ifn sync batch                               # Trigger sync across all companies
ifn sync cancel-all <company_id>             # Cancel all running syncs
    --parent-job-id <n>                      # Cancel children of a specific parent
```

---

### `ifn staging`

Bookkeeping staging workflow. Staged actions go through propose -> review -> approve/reject.

```bash
ifn staging list <company_id>               # List staged actions for a company
ifn staging list-all                        # List all staged actions across companies
ifn staging get <action_id>                 # Get staged action details

ifn staging propose <company_id> <json_file>  # Propose a new staging action
ifn staging edit <action_id> <json_file>      # Edit own staged action
ifn staging clone <action_id>                 # Clone a staged action
ifn staging reject <action_id>                # Reject own staged action

ifn staging next-number <company_id>        # Predicted next voucher number
    --series <code>                         # Voucher series (default: A)
    --fy <id>                               # Financial year ID

ifn staging upload <company_id> <file_path>       # Upload file (company-scoped)
ifn staging upload-action <action_id> <file_path> # Upload file to a specific action
ifn staging uploads <action_id>                    # List staged uploads
ifn staging remove-upload <action_id> <file_id>    # Remove a staged upload
ifn staging file-refs <action_id> --data <json>    # Replace file refs on action

ifn staging write-windows <company_id>      # List write windows
ifn staging archive [--action-id <id>]      # Archive rejected/failed actions
```

---

### `ifn files`

File attachment management.

```bash
ifn files list <company_id> [options]       # List synced file attachments
    --page <n>                              # Page number
    --limit <n>                             # Records per page
    --doc-type <type>                       # Filter by document type
    --search <query>                        # Search text
    --sort <field>                          # Sort field
    --sortdir <dir>                         # asc or desc
    --category <cat>                        # Filter by category
    --group-id <id>                         # Filter by metadata group
    --needs-categorization                  # Only uncategorized files
    --financial-year-id <id>                # Filter by financial year
    --voucher-series <code>                 # Filter by voucher series
    --inbox-folder <id>                     # Filter by inbox folder

ifn files fetch <company_id> <file_id>      # Download file to /tmp/ifn-<file_id>
    --live                                  # Fetch directly from Fortnox (not cache)

ifn files refresh <company_id> <file_id>    # Re-download from Fortnox into local storage
ifn files categories <company_id>           # List file categories with counts
ifn files groups <company_id> [group_id]    # List groups or files in a group
ifn files inbox-folders <company_id>        # Inbox folder breakdown
ifn files refs <company_id> <file_id>       # List ERP records referencing a file
ifn files metadata <company_id> <file_id>   # Set file metadata
    --category <cat>
    --group-id <id>
    --details <text>
```

---

### `ifn link`

Generate web app deep links for entities.

```bash
ifn link company <company_id>
ifn link voucher <company_id> <series> <number> [--fy <id>]
ifn link vouchers <company_id> [--fy <id>] [--from <date>] [--to <date>]
ifn link invoice <company_id> <number>
ifn link invoices <company_id> [--from <date>] [--to <date>]
ifn link supplier-invoice <company_id> <number>
ifn link supplier-invoices <company_id> [--from <date>] [--to <date>]
ifn link account-analysis <company_id> [--account <n>] [--from <date>]
ifn link staging <company_id> <action_id>
ifn link staging-list <company_id>
ifn link file <company_id> <file_id>
ifn link files <company_id> [--doc-type <type>] [--search <q>]
ifn link inbox <company_id> [folder_id] [file_id]
ifn link integrity <company_id>
ifn link sync <company_id>
ifn link customer <company_id> <number>
ifn link supplier <company_id> <number>
ifn link resource <company_id> <resource> [record_id]
```

---

### `ifn xcompanies`

Cross-company aggregation queries.

```bash
ifn xcompanies summary                      # Section counts across all companies
ifn xcompanies vouchers [options]           # Cross-company voucher list
ifn xcompanies invoices [options]           # Cross-company invoice list
ifn xcompanies supplierinvoices [options]   # Cross-company supplier invoices
ifn xcompanies suppliers [options]          # Cross-company supplier list
ifn xcompanies customers [options]          # Cross-company customer list
ifn xcompanies accounts [options]           # Cross-company account list
ifn xcompanies files [options]              # Cross-company file list
ifn xcompanies files-categories             # Cross-company category directory
ifn xcompanies files-groups                 # Cross-company group directory
```

**Common options:** `--page`, `--limit`, `--search`, `--sort`, `--sortdir`

**Date filters** (vouchers, invoices, supplierinvoices): `--from-date`, `--to-date`

---

### `ifn auth`

Authentication and API key management.

```bash
ifn auth login                         # Authenticate via browser (OAuth flow)
ifn auth login --token                 # Paste an existing API key
ifn auth login --email me@co.com       # Pre-fill email for OAuth
ifn auth status                        # Current API key and session info (email, role, is_bot)
ifn auth rotate                        # Self-rotate API key (grace period until new key is first used)
```

`login` stores credentials in `~/.ifn/config`. `rotate` updates the config file automatically if it exists.

---

### `ifn jobs`

Job inspection (developer role required).

```bash
ifn jobs sync <job_id>                      # Sync job details
ifn jobs sync-log <job_id>                  # Sync job log
ifn jobs list <company_id> [--limit <n>]    # List copy/purge jobs
ifn jobs stale                              # Preview stale jobs
ifn jobs restart-history [--limit <n>]      # Recent server restart events
```

---

### `ifn bk`

Bookkeeping operations — settlement reconciliation and voucher proposal automation for delivery partners.

#### Settlement File Discovery

```bash
ifn bk find <company_id> --partner <foodora|wolt|ubereats>
```

Searches the ERP inbox for settlement files matching the partner's naming pattern. Groups related files together:
- **Foodora**: pairs XLS (order detail) + PDF (summary)
- **Wolt**: groups 3 PDFs (payout + sales + commission) by date range
- **Uber Eats**: matches individual PDFs

#### Settlement Parsing

```bash
ifn bk parse <company_id> --partner <partner> --file-id <id1,id2,...>
```

Parses settlement files into structured JSON using partner-specific Python parsers:

| Partner | Input Files | Parser Output |
|---------|------------|---------------|
| **Foodora** | XLS + PDF | Order-level VAT breakdown (6%/12%/25%), commissions, charges, net payout |
| **Wolt** | 3 PDFs (payout, sales, commission) | Order-level detail, commission/delivery/service/transaction fees |
| **Uber Eats** | 1 PDF | Daily breakdown, Uber fee, promotions, net payout |

All parsers output: `{ partner, restaurant, period, orders[], summary }`.

#### Voucher Proposal

```bash
ifn bk propose <company_id> --partner <partner> --file-id <ids>
```

Builds balanced voucher entry proposals:
1. Loads account mapping from `~/.ifn/booking-templates/<partner>.json`
2. If missing, auto-discovers via `ifn bk discover-accounts`
3. Parses settlement files
4. Generates debit/credit entries via `build_proposal.py`

#### Account Mapping

```bash
ifn bk mapping show <company_id> --partner <partner>       # Display current mapping
ifn bk mapping set <company_id> --partner <partner> \
    --key <template_key> --account <number>                 # Override an account
ifn bk mapping confirm <company_id> --partner <partner>     # Mark mapping as validated
ifn bk mapping reset <company_id> --partner <partner>       # Clear overrides

ifn bk discover-accounts <company_id> --partner <partner>   # Auto-discover from chart of accounts
```

Template keys per partner: `sales_revenue`, `delivery_fee_cost`, `commission_cost`, `bank_payout`, `vat_*`, etc.

#### Revenue Adjustments

```bash
ifn bk adjust <company_id> --partner <partner> --from <date> --to <date>
```

Identifies POS orders booked as revenue but never settled by the delivery partner:
1. Queries POS orders from BigQuery
2. Queries cancellation data
3. Compares against delivery partner settlements
4. Outputs correction entry proposals

#### BigQuery Data Connector

```bash
ifn bk bq pos-orders <company_id> --from <date> --to <date>   # POS order data
ifn bk bq cancelled <company_id> --from <date> --to <date>     # Cancelled orders
ifn bk bq daily-totals <company_id> --from <date> --to <date>  # Daily totals
```

#### Staging

```bash
ifn bk stage <company_id> --partner <partner> --file-id <ids>
```

Creates IFN staging entries from proposals. Uploads settlement PDFs as attachments and generates staging payloads for review/approval.

#### Other

```bash
ifn bk status                               # Mapping cache status (templates, TTL)
ifn bk learn <company_id> --partner <partner> # Learn templates from historical vouchers
```

---

## Settlement Reconciliation Workflow

The typical end-to-end flow for processing a delivery partner settlement:

```
1. ifn bk find <company> --partner foodora
   → Lists unprocessed settlement files in inbox

2. ifn bk parse <company> --partner foodora --file-id 123,456
   → Structured JSON with orders, VAT, commissions

3. ifn bk propose <company> --partner foodora --file-id 123,456
   → Balanced voucher entries (debit/credit)

4. ifn bk stage <company> --partner foodora --file-id 123,456
   → Staged for accountant review in the web app

5. Accountant reviews and approves in the web app
   → Written to Fortnox as a voucher
```

For revenue adjustments (orders in POS but not settled):

```
1. ifn bk adjust <company> --partner foodora --from 2025-01-01 --to 2025-01-31
   → Correction entry proposals for unsettled orders

2. ifn staging propose <company> adjustment.json
   → Staged for review
```

---

## Local Setup

To run the `ifn` CLI locally (outside of a deployed Gent), follow these steps.

### Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| `bash` 5.0+ | CLI runtime | Pre-installed on macOS/Linux |
| `curl` | HTTP requests | Pre-installed on macOS/Linux |
| `jq` | JSON parsing | `brew install jq` / `apt install jq` |
| `python3` | Settlement parsers | `brew install python3` / `apt install python3` |
| `pdftotext` | PDF text extraction | `brew install poppler` / `apt install poppler-utils` |
| `openpyxl` | Excel parsing (Foodora XLS) | `pip3 install openpyxl` |

> `python3`, `pdftotext`, and `openpyxl` are only needed for settlement parsing (`ifn bk parse/propose`). All other commands work with just `bash`, `curl`, and `jq`.

### 1. Add `ifn` to your PATH

```bash
# Option A: symlink into ~/bin
mkdir -p ~/bin
ln -sf "$(pwd)/skills/introspectfn/tools/ifn" ~/bin/ifn

# Option B: symlink into /usr/local/bin
sudo ln -sf "$(pwd)/skills/introspectfn/tools/ifn" /usr/local/bin/ifn
```

### 2. Authenticate

**Option A: Browser login (OAuth)**

```bash
ifn auth login
```

This will:
1. Prompt for the IntrospectFN server URL (if not already configured)
2. Prompt for your email
3. Open your browser for authorization
4. Exchange the auth code for an API key
5. Store everything in `~/.ifn/config`

You can pre-fill values:

```bash
ifn auth login --email me@company.com --name "My Name"
```

**Option B: Paste an existing API key**

If you already have an API key (from the IntrospectFN web UI or another source):

```bash
ifn auth login --token
```

This prompts for the server URL and API key, verifies the key, and saves to config.

**Option C: Manual environment variables**

```bash
export IFN_API_KEY="your-api-key-here"
export IFN_BASE_URL="https://your-instance.example.com"
```

Or write them directly to the config file:

```bash
mkdir -p ~/.ifn
cat > ~/.ifn/config << 'EOF'
IFN_API_KEY=your-api-key-here
IFN_BASE_URL=https://your-instance.example.com
IFN_INSECURE=true
EOF
chmod 600 ~/.ifn/config
```

Environment variables take precedence over the config file.

### 3. Verify connectivity

```bash
ifn health           # Check API is reachable
ifn auth status      # Verify API key (shows email, role)
ifn companies list   # List connected companies
```

### 5. (Optional) Deploy parsers for settlement processing

```bash
mkdir -p ~/.ifn/parsers ~/.ifn/booking-templates
cp skills/introspectfn/tools/parsers/*.py ~/.ifn/parsers/
```

### SSL Notes

Most deployments use self-signed certificates. SSL validation is skipped by default (`IFN_INSECURE=true`). To enable strict SSL:

```bash
export IFN_INSECURE=false
```

Or pass `--insecure` per-command to override.

---

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `IFN_API_KEY` | Bearer token (required) | Set by skill credential system |
| `IFN_BASE_URL` | API base URL (required) | None — must be set |
| `IFN_WEB_URL` | Web app URL for deep links | Same as `IFN_BASE_URL` |
| `IFN_INSECURE` | Skip SSL validation | `true` |
| `IFN_CONFIG` | Config file path | `~/.ifn/config` |

**Config loading priority:** Environment variables > `~/.ifn/config` > error (no defaults for required values).

Config file format is simple `KEY=value` pairs with `#` comments. Written atomically by lifecycle hooks.

Booking templates: `~/.ifn/booking-templates/<partner>.json` (auto-discovered or manually configured).

---

## Architecture

```
ifn CLI (bash)
├── ifn-cli/
│   ├── config.sh           # Config loading
│   ├── commands/*.sh        # All command implementations
│   └── lib/
│       ├── http.sh          # curl wrappers with Bearer auth
│       ├── format.sh        # Output formatting
│       ├── auth.sh          # Auth helpers
│       └── deeplink.sh      # Web app URL builders
├── settlement-cli/
│   ├── find.sh              # File discovery
│   ├── parse.sh             # Parser dispatcher
│   ├── propose.sh           # Proposal builder
│   ├── mapping.sh           # Account mapping mgmt
│   ├── discover.sh          # Auto-discover accounts
│   ├── adjust.sh            # Revenue adjustments
│   ├── stage.sh             # Staging entry creation
│   ├── bq.sh                # BigQuery connector
│   ├── learn.sh             # Template learning
│   ├── status.sh            # Cache status
│   └── lib/
│       ├── build_proposal.py      # Voucher proposal logic
│       ├── build_adjustment.py    # Adjustment proposal logic
│       ├── mapping.py             # Mapping persistence (v2)
│       ├── discover_accounts.py   # Account discovery
│       └── merge_foodora.py       # Foodora XLS+PDF merging
└── parsers/
    ├── parse_foodora_xls.py       # Foodora XLS parser
    ├── parse_foodora_pdf.py       # Foodora PDF summary parser
    ├── parse_wolt.py              # Wolt 3-PDF parser
    └── parse_ubereats.py          # Uber Eats PDF parser
```

All commands use the IntrospectFN REST API via `curl`/`jq`. No ERP SDK or Fortnox CLI required. Python 3 is used only for settlement file parsing (`pdftotext`, `openpyxl`).

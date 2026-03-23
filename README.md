# Gentiq Extensions

Community and first-party skill packages for [Gentiq](https://gentiq.com) virtual employees.

## What are Skills?

Skills are capability packages that can be pushed to Gents (Gentiq virtual employees). Each skill contains:

- **`skill.toml`** - Package manifest with metadata, routing config, and permissions
- **`SKILL.md`** - Markdown instructions that tell the agent how to behave
- **`tools/`** - Optional executable scripts the agent can invoke
- **`config/`** - Optional configuration templates

## Skill Package Format

```
my-skill/
  skill.toml          # Package manifest (required)
  SKILL.md            # Agent instructions (required)
  tools/              # Executable scripts (optional)
    do_thing.js
    helper.sh
  config/             # Config templates (optional)
    settings.yml
  setup/              # Setup UI page (v2, optional)
    index.html
  hooks/              # Lifecycle & cron hooks (v2, optional)
    health_check.sh
    on_install.sh
```

## Available Skills

| Skill | Description | Category |
|-------|-------------|----------|
| [weather-lookup](skills/weather-lookup/) | Look up current weather for any city using wttr.in | utilities |
| [introspectfn-erp](skills/introspectfn/) | Virtual accountant — ERP analysis, bookkeeping proposals, and financial insights via IntrospectFN | accounting |

## Creating a Skill

1. Create a directory under `skills/`
2. Add a `skill.toml` manifest (see [skill.toml reference](#skilltoml-reference) below)
3. Write `SKILL.md` with agent instructions
4. Optionally add tool scripts in `tools/`
5. Package with `tar -czf my-skill-1.0.0.tar.gz my-skill/`
6. Upload via `POST /api/v1/skills/upload` or the web admin

## skill.toml Reference

```toml
[package]
name = "my-skill"
version = "1.0.0"
description = "What this skill does"
author = "Your Name"
icon = "emoji"
category = "general"
tags = ["tag1", "tag2"]

[routing]
default_operation = "generate"
default_complexity = "routine"

[routing.tasks.main_task]
operation = "generate"
complexity = "routine"
description = "Primary task description"
triggers = ["keyword1", "keyword2"]

[credentials]
required = ["MY_API_KEY"]
optional = []

[permissions]
network = ["api.example.com:443"]
tools = ["my_tool"]
```

### V2 Manifest Extensions

Skills can declare setup flows, cron jobs, lifecycle hooks, and status widgets. V1 skills (without these sections) remain fully valid.

#### Setup UI

The `[setup]` section declares a bundled HTML page that the dashboard renders for credential provisioning.

```toml
[setup]
ui = "setup/index.html"                   # HTML page loaded by dashboard
type = "oauth_provision"                   # "oauth_provision" | "manual" | "none"
display_name = "Connect to My Service"
description = "Authorize this Gent to access your data"
```

Supported `type` values:
- `oauth_provision` — OAuth-style redirect flow with server-side token exchange
- `manual` — User manually enters credentials (API keys, tokens)
- `none` — No setup needed (credentials pushed by admin)

#### Credentials (extended)

```toml
[credentials]
required = ["MY_API_KEY"]                  # Must be set before skill works
configurable = ["MY_BASE_URL"]             # Admin can override; has default

[credentials.defaults]
MY_BASE_URL = "https://api.example.com"
```

`configurable` credentials have defaults in `[credentials.defaults]` and can optionally be overridden by the admin.

#### Cron Jobs

```toml
[[cron]]
name = "health_check"
schedule = "0 */6 * * *"                   # Standard 5-field cron expression
hook = "hooks/health_check.sh"
description = "Check API connectivity"
timeout = 30                               # Max runtime in seconds
```

Multiple `[[cron]]` entries are supported. gentd schedules and executes them, passing credentials as environment variables.

#### Lifecycle Hooks

```toml
[lifecycle]
on_install = "hooks/on_install.sh"
on_setup_complete = "hooks/on_setup_complete.sh"
on_credential_update = "hooks/on_credential_update.sh"
on_uninstall = "hooks/on_uninstall.sh"
```

All hooks are executable scripts that receive credentials as env vars and output JSON to stdout.

#### Status Widget

```toml
[status]
hook = "hooks/status.sh"
refresh_interval = 3600                    # Seconds between refreshes
```

The status hook provides data for the dashboard's skill status widget.

#### Permissions (extended)

```toml
[permissions]
network = ["api.example.com:443"]
tools = ["my_tool"]
cron = true                                # Skill uses cron jobs
setup_ui = true                            # Skill has a setup UI page
```

#### Setup UI postMessage Contract

The setup page communicates with the dashboard via `postMessage`:

| Direction | Type | Payload |
|-----------|------|---------|
| Dashboard → Extension | `setup:init` | `{gent_email, gent_name, credentials, base_url}` |
| Extension → Dashboard | `setup:ready` | `{}` — page loaded |
| Extension → Dashboard | `setup:exchange` | `{code, client_id, token_url}` — request token exchange |
| Dashboard → Extension | `setup:exchange_result` | `{ok, credentials}` or `{ok: false, error}` |
| Extension → Dashboard | `setup:complete` | `{credentials: {KEY: val}}` |
| Extension → Dashboard | `setup:error` | `{message}` |

The `setup:exchange` message is critical for OAuth flows — it delegates the server-to-server code-to-key exchange to the dashboard backend, keeping raw keys out of the browser.

### Routing Operations

| Operation | Description | Tier (routine) |
|-----------|-------------|----------------|
| `reason` | Complex reasoning, analysis | thinking |
| `generate` | Content generation | standard |
| `analyze` | Data analysis, review | standard |
| `converse` | Conversation, chat | standard |
| `summarize` | Summarization | fast |
| `extract` | Data extraction | fast |
| `classify` | Classification | fast |
| `transform` | Format conversion | fast |

### Complexity Modifiers

- **`trivial`** - Downgrades tier by 1
- **`routine`** - No change
- **`complex`** - Upgrades tier by 1

## Building a Package

```bash
cd skills/weather-lookup
tar -czf ../../dist/weather-lookup-1.0.0.tar.gz -C .. weather-lookup
```

## License

MIT

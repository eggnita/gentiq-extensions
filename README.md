# Gentiq Extensions

Skill packages for [Gentiq](https://gentiq.com) virtual employees, compatible with the **v2 runtime**.

## What are Skills?

Skills are capability packages that can be pushed to Gents (Gentiq virtual employees). Each skill contains:

- **`SKILL.md`** — Markdown instructions with YAML frontmatter (metadata)
- **`tools.json`** — Declarative tool definitions the runtime exposes to the LLM
- **`tools/`** — Executable tool scripts
- **`crons/`** — Optional scheduled-turn definitions (one JSON per cron)
- **`skill.toml`** — Optional package manifest read by GentOS (packaging, setup UI, lifecycle hooks). The runtime does not read this file.
- **`setup/`**, **`hooks/`**, **`config/`**, **`docs/`** — Optional resources consumed by GentOS/gentd during install, not by the runtime

## Package layout

```
my-skill/
  SKILL.md            # Required — agent instructions + frontmatter
  tools.json          # Required — tool declarations
  tools/              # Tool scripts (referenced from tools.json)
    my-tool.sh
  crons/              # Optional v2 cron definitions
    nightly.json
  skill.toml          # Optional — GentOS package manifest
  setup/index.html    # Optional — setup UI (GentOS)
  hooks/              # Optional — lifecycle hooks (gentd)
```

## Available Skills

| Skill | Description | Category |
|-------|-------------|----------|
| [weather-lookup](skills/weather-lookup/) | Look up current weather for any city using wttr.in | utilities |
| [bigquery-datalake](skills/bigquery/) | Virtual data analyst — BigQuery schema discovery and read-only SQL | data |
| [introspectfn-erp](skills/introspectfn/) | Virtual accountant — ERP analysis and bookkeeping proposals via IntrospectFN | accounting |

## SKILL.md frontmatter (v2)

Validated against `gentiq-gent-runtime/src/schemas/skill.json`.

```markdown
---
id: my-skill                      # pattern: ^[a-z0-9-]+$
name: My Skill
description: What this skill does
activation: on-demand              # "always" | "on-demand"
task_type: conversation            # optional, used for routing
tools: [my-tool]                   # tool names declared in tools.json
requires_auth: [MY_API_KEY]        # secret names the runtime injects as env vars
schema_version: "1.0.0"
---

# My Skill — agent instructions go here
...
```

## tools.json (v2)

Validated against `gentiq-gent-runtime/src/schemas/tools.json`.

```json
{
  "my-tool": {
    "exec": "tools/my-tool.sh",
    "description": "What the tool does (shown to the LLM)",
    "args_schema": {
      "type": "object",
      "properties": {
        "query": {"type": "string", "description": "User query"}
      },
      "required": ["query"]
    },
    "side_effects": false,
    "timeout_ms": 30000
  }
}
```

## v2 tool-invocation contract

The v2 runtime invokes a tool by spawning the `exec` command with:

- **`cwd`** = skill directory
- **Arguments** passed as a **JSON blob in the `TOOL_ARGS` environment variable** (not positional CLI args)
- **Secrets** from `requires_auth` injected as env vars (decrypted from `secrets.enc`)
- **Timeout** from `tools.json` (default 180 s), killed on expiry
- **Stdout** captured; if it parses as JSON → returned as structured `data`, otherwise returned as `text`
- **Non-zero exit** → tool result marked as error with captured stderr

### Minimum tool script (bash)

```bash
#!/usr/bin/env bash
set -euo pipefail
ARGS="${TOOL_ARGS:-{}}"
QUERY=$(printf '%s' "$ARGS" | jq -r '.query // empty')
[ -z "$QUERY" ] && { echo '{"error":"Missing query"}' >&2; exit 1; }
# ... do work, emit JSON on stdout ...
```

### Adapter pattern for existing CLIs

When wrapping an existing CLI (positional args), add a thin adapter shim that
reads `TOOL_ARGS` and translates to CLI arguments. Reference `tools.json`
entries at the adapter with a subcommand:

```json
"exec": "tools/my-adapter.sh query"
```

See `skills/bigquery/tools/bq-adapter.sh` and `skills/introspectfn/tools/ifn-adapter.sh` for working examples.

## crons/ (v2)

One JSON file per cron, validated against `gentiq-gent-runtime/src/schemas/cron.json`. The runtime treats crons as synthetic turn triggers — it does **not** tick its own clock; gentd dispatches crons on schedule.

```json
{
  "id": "my-skill.nightly",
  "schedule": "0 2 * * *",
  "timezone": "UTC",
  "invoke": {
    "type": "skill",
    "skill": "my-skill",
    "tool": "my-tool",
    "args": {"query": "nightly report"}
  },
  "schema_version": "1.0.0"
}
```

`invoke.type` is either:
- `"skill"` — calls a skill tool directly with the provided args
- `"prompt"` — fires a turn with the given prompt; the agent picks the tools

At install time, gentd copies these files into the gent workspace `crons/` directory where the runtime loads them.

## Routing

Task-type routing is declared via the `task_type` field in SKILL.md. Complex per-trigger routing tables belong in GentOS's task-type routing config — they're no longer read from `skill.toml` by the runtime.

## Creating a skill

1. Create a directory under `skills/`.
2. Write `SKILL.md` with frontmatter (above).
3. Write `tools.json` declaring the tools your skill exposes.
4. Write tool scripts under `tools/`. Read args from `TOOL_ARGS`, emit JSON on stdout.
5. Optionally add `crons/*.json` for scheduled turns.
6. Optionally add `skill.toml` for GentOS packaging (setup UI, permissions, lifecycle hooks).
7. Package: `tar -czf dist/my-skill-1.0.0.tar.gz -C skills my-skill`.
8. Upload via `POST /api/v1/skills/upload` or the web admin.

## skill.toml (GentOS-side only)

The v2 runtime ignores `skill.toml`. GentOS still reads it for:

- Package metadata (`[package]`)
- Setup UI definition (`[setup]`)
- Credential declarations and defaults (`[credentials]`, `[credentials.defaults]`)
- Lifecycle hooks (`[lifecycle]`) — `on_install`, `on_setup_complete`, etc.
- Status widget (`[status]`)
- Permissions (`[permissions]`) — network egress, declared tools, cron/setup_ui flags

### Setup UI postMessage contract

Setup page ↔ dashboard communication:

| Direction | Type | Payload |
|-----------|------|---------|
| Dashboard → Extension | `setup:init` | `{gent_email, gent_name, credentials, base_url}` |
| Extension → Dashboard | `setup:ready` | `{}` — page loaded |
| Extension → Dashboard | `setup:exchange` | `{code, client_id, token_url}` — request token exchange |
| Dashboard → Extension | `setup:exchange_result` | `{ok, credentials}` or `{ok: false, error}` |
| Extension → Dashboard | `setup:complete` | `{credentials: {KEY: val}}` |
| Extension → Dashboard | `setup:error` | `{message}` |

The `setup:exchange` message delegates OAuth code-to-token exchange to the dashboard backend, keeping raw secrets out of the browser.

## Building a package

```bash
cd skills/weather-lookup
tar -czf ../../dist/weather-lookup-1.0.0.tar.gz -C .. weather-lookup
```

## License

MIT

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

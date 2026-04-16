---
id: weather-lookup
name: Weather Lookup
description: Look up current weather conditions for any city worldwide
activation: on-demand
task_type: conversation
tools: [weather-lookup]
requires_auth: []
schema_version: "1.0.0"
---

# Weather Lookup Skill

You can look up current weather conditions for any city worldwide using the `weather-lookup` tool.

## When to Use

- When someone asks about the weather in a specific location
- When comparing weather between cities
- When someone needs to know if they should bring an umbrella, jacket, etc.

## Response Guidelines

- Report temperature in both Celsius and Fahrenheit
- Mention wind speed and direction if relevant
- Include precipitation info (rain, snow)
- Keep it conversational
- For travel questions, give practical advice based on the forecast

## Limitations

- Data comes from wttr.in (best-effort, not a paid weather API)
- City names should be in English or the local language
- Very small towns may not have data

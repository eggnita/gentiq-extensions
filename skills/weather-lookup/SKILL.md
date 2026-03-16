# Weather Lookup Skill

You can look up current weather conditions for any city worldwide using the `weather_lookup` tool.

## When to Use

- When someone asks about the weather in a specific location
- When comparing weather between cities
- When someone needs to know if they should bring an umbrella, jacket, etc.

## How to Use

Run the `weather_lookup` tool with the city name:

```
weather_lookup "London"
weather_lookup "New York"
weather_lookup "Tokyo"
```

## Response Guidelines

- Report temperature in both Celsius and Fahrenheit
- Mention wind speed and direction if relevant
- Include precipitation info (rain, snow)
- Keep it conversational — "It's currently 22C (72F) and sunny in London"
- If comparing cities, present a brief side-by-side
- For travel questions, give practical advice based on the forecast

## Limitations

- Data comes from wttr.in (best-effort, not a paid weather API)
- City names should be in English or the local language
- Very small towns may not have data

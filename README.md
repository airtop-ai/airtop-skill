# Airtop Agents Skill for Claude Code

A [Claude Code](https://claude.com/claude-code) skill that lets you list, run, and monitor your [Airtop](https://airtop.ai) agents directly from the CLI.

## Installation

```bash
claude skill add --from https://github.com/airtop-ai/airtop-skill
```

Or add to your `.claude/settings.json`:

```json
{
  "skills": ["https://github.com/airtop-ai/airtop-skill"]
}
```

## Setup

1. Get your API key from [portal.airtop.ai/api-keys](https://portal.airtop.ai/api-keys)
2. Set it as an environment variable:
   ```bash
   export AIRTOP_API_KEY=your-api-key-here
   ```
   Or copy `.env.example` to `.env` in the skill directory and fill in your key.

## Usage

### List agents

```
/airtop-agents list
/airtop-agents list --name "price"
```

### Run an agent

```
/airtop-agents run "Price Tracker"
/airtop-agents run "Price Tracker" --vars '{"url": "https://example.com"}'
/airtop-agents run 550e8400-e29b-41d4-a716-446655440000
```

### Check invocation status

```
/airtop-agents status <agentId> <invocationId>
```

### Cancel a running invocation

```
/airtop-agents cancel <agentId> <invocationId>
```

### View invocation history

```
/airtop-agents history <agentId>
```

## How It Works

The skill uses the Airtop REST API to manage agents:

- **List**: Queries `GET /v2/agents` and displays a formatted table
- **Run**: Resolves the agent by name or ID, fetches its webhook, invokes it, and polls for the result
- **Status/Cancel/History**: Direct API calls to the corresponding endpoints

Polling runs every 5 seconds with a 5-minute timeout. If the agent hasn't finished by then, you'll get the invocation ID to check later.

## Requirements

- [Claude Code](https://claude.com/claude-code) CLI
- An [Airtop](https://airtop.ai) account with at least one agent configured with a webhook
- `curl` and `jq` available in your shell

## License

MIT

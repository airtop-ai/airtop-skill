# Airtop Agents Skill

An [Agent Skill](https://agentskills.io) that lets you list, run, monitor, create and edit your [Airtop](https://airtop.ai) agents directly from your coding agent.

## Installation

Install with the [skills CLI](https://github.com/vercel-labs/skills) (works with Claude Code, Cursor, Windsurf, Cline, Copilot, and 40+ other agents):

```bash
npx skills add airtop-ai/airtop-skill
```

Or install for Claude Code directly:

```bash
claude skill add --from https://github.com/airtop-ai/airtop-skill
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

### Create an agent

```
/airtop-agents create an agent named "Executive Brief" that accepts a company URL and returns a cited summary of its leadership, products, and recent news
```

### Modify an existing agent

```
/airtop-agents edit agent 550e8400-e29b-41d4-a716-446655440000 to include the research date in its output
```

## How It Works

The skill uses the Airtop REST API to manage agents:

- **List**: Queries `GET /v2/agents` and displays a formatted table
- **Run**: Resolves the agent by name or ID, fetches its webhook, invokes it, and polls for the result
- **Status/Cancel/History**: Direct API calls to the corresponding endpoints
- **Create/Edit**: Sends the complete free-form request to Airtop Director and polls for newly observed Director messages

Published-agent invocation polling runs every 5 seconds with a 5-minute timeout. If the agent hasn't finished by then, you'll get the invocation ID to check later.

Airtop Director polling runs every minute with a 30-minute timeout. If the agent hasn't finished by then, Director will be asked for a status update.

## Requirements

- An [Airtop](https://airtop.ai) account with at least one agent configured with a webhook
- `curl` available in your shell

## License

MIT

---
name: airtop-agents
description: List, run, and monitor Airtop agents. Use when asked to run an Airtop agent, check agent status, list agents, or invoke a webhook agent.
allowed-tools: Bash, Read, Write
---

# Airtop Agents Skill

You can list, run, monitor, and cancel Airtop agents using their REST API.

## Authentication

The Airtop API key is required for all operations. Resolve it in this order:

1. `$AIRTOP_API_KEY` environment variable
2. A `.env` file in this skill's directory containing `AIRTOP_API_KEY=...`
3. If neither is found, ask the user to provide their API key (available at https://portal.airtop.ai/api-keys) and offer to save it to the skill's `.env` file.

Store the resolved key in a shell variable for the session:

```bash
API_KEY="${AIRTOP_API_KEY}"
```

If loading from `.env`:
```bash
API_KEY=$(grep AIRTOP_API_KEY /path/to/skill/.env | cut -d= -f2-)
```

## Base URL

All authenticated API endpoints use: `https://api.airtop.ai/api`

Webhook endpoints (run agent, poll result) use the public path: `https://api.airtop.ai/api/hooks/`

## Argument Parsing

Parse `$ARGUMENTS` as follows:

```
list [--name <filter>]              List agents
run <agent-name-or-id> [--vars {}]  Run an agent with optional config variables
status <invocationId>               Check invocation status
cancel <agentId> <invocationId>     Cancel a running invocation
history <agentId>                   View recent invocations
```

If `$ARGUMENTS` is empty or unrecognized, show the usage summary above and ask the user what they'd like to do.

## Commands

### 1. List Agents

```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.airtop.ai/api/v2/agents?limit=25&sortBy=lastRun&sortOrder=desc"
```

Optional query parameters to append:
- `&name=<filter>` — case-insensitive partial match (use when `--name` is provided)
- `&enabled=true` — filter to enabled agents only
- `&published=true` — filter to published agents only

**Display**: Format the response as a markdown table with columns: Name, ID, Enabled, Last Run. Show the `pagination.total` count in a header line.

Example output:
```
Found 3 agents:
| Name              | ID                                   | Enabled | Last Run    |
|-------------------|--------------------------------------|---------|-------------|
| Price Tracker     | 550e8400-e29b-41d4-a716-446655440000 | Yes     | 2 hours ago |
| Lead Enricher     | 6ba7b810-9dad-11d1-80b4-00c04fd430c8 | Yes     | Yesterday   |
| Competitor Monitor| 6ba7b811-9dad-11d1-80b4-00c04fd430c8 | No      | Never       |
```

### 2. Run Agent

This is a multi-step process:

**Step 1 — Resolve agent by name or ID.**

If the argument looks like a UUID, use it directly as the agent ID. Otherwise, search by name:

```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.airtop.ai/api/v2/agents?name=$(echo '<agent-name>' | jq -sRr @uri)"
```

- If exactly one agent matches, use it.
- If multiple agents match, display them in a table and ask the user to pick one.
- If no agents match, tell the user no agent was found and suggest running `list`.

**Step 2 — Get the agent's webhook.**

```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.airtop.ai/api/v2/agents/<agentId>/webhooks?limit=10"
```

Use the first webhook from the `webhooks` array. If no webhooks exist, tell the user the agent needs a webhook configured in the Airtop portal (https://portal.airtop.ai).

**Step 3 — Invoke the webhook.**

```bash
curl -s -X POST "https://api.airtop.ai/api/hooks/agents/<agentId>/webhooks/<webhookId>" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "configVars": { <user-provided key-value pairs from --vars, or empty object {}> },
    "version": 1
  }'
```

The response contains `{ "invocationId": "<uuid>" }`. Save this for polling.

Note: Include the `Authorization` header if the webhook has `requireAuth: true` (check the webhook object from Step 2).

**Step 4 — Poll for the result.**

```bash
curl -s "https://api.airtop.ai/api/hooks/agents/<agentId>/invocations/<invocationId>/result" \
  -H "Authorization: Bearer $API_KEY"
```

Polling rules:
- Poll every **5 seconds**
- Print a status update to the user after each poll (e.g., "Status: Running...")
- Terminal statuses: `Completed`, `Failed`, `Cancelled`
- **Timeout after 5 minutes** (60 polls). If not complete, tell the user the invocation is still running and provide the invocation ID so they can check later with the `status` command.

**Step 5 — Display the result.**

- On `Completed`: Show the `output` field. If it's JSON, format it nicely. If it's a string, display it directly.
- On `Failed`: Show the `error` field and the full status.
- On `Cancelled`: Inform the user the invocation was cancelled.

### 3. Check Status

Poll a specific invocation's result:

```bash
curl -s "https://api.airtop.ai/api/hooks/agents/<agentId>/invocations/<invocationId>/result" \
  -H "Authorization: Bearer $API_KEY"
```

Display the `status` field. If terminal, also display `output` or `error`.

Note: This requires the agent ID. If the user only provides an invocation ID, ask for the agent ID as well, or search recent invocations across agents to find it.

### 4. Cancel Invocation

```bash
curl -s -X DELETE -H "Authorization: Bearer $API_KEY" \
  "https://api.airtop.ai/api/v2/agents/<agentId>/invocations/<invocationId>?reason=user_requested"
```

Confirm to the user that the cancellation was requested.

### 5. View History

```bash
curl -s -H "Authorization: Bearer $API_KEY" \
  "https://api.airtop.ai/api/v2/agents/<agentId>/invocations?limit=10"
```

Display results as a table with columns: Invocation ID, Status, Trigger, Started At.

## Error Handling

- **401 Unauthorized**: Tell the user their API key is invalid or expired. Direct them to https://portal.airtop.ai/api-keys.
- **404 Not Found**: The agent or invocation doesn't exist. Suggest checking the ID or running `list`.
- **429 Rate Limited**: Tell the user they've hit the rate limit and should wait before retrying.
- **No webhook configured**: Explain that the agent needs a webhook set up in the Airtop portal before it can be invoked from the CLI.
- **Multiple name matches**: List all matches and ask the user to pick one or use the agent ID directly.
- **Empty API key**: Guide the user to set `AIRTOP_API_KEY` or provide it interactively.

## Important Notes

- Always use `curl -s` (silent mode) to avoid progress bars in output.
- Parse all JSON responses with `jq` or inline JSON parsing in bash.
- The webhook invoke and poll endpoints are under `/api/hooks/` (public path), NOT `/api/v2/`.
- The list, webhooks, history, and cancel endpoints are under `/api/v2/` (authenticated path).
- When displaying times, convert ISO timestamps to human-readable relative times (e.g., "2 hours ago").

# Airtop Agents Skill — Examples

## List All Agents

```
/airtop-agents list
```

Lists all agents sorted by last run time.

## List Agents by Name

```
/airtop-agents list --name "price"
```

Filters agents whose name contains "price" (case-insensitive).

## Run an Agent by Name

```
/airtop-agents run "Price Tracker"
```

Resolves the agent by name, gets its webhook, invokes it with no config variables, and polls until completion.

## Run an Agent with Variables

```
/airtop-agents run "Price Tracker" --vars '{"url": "https://example.com/product", "currency": "USD"}'
```

Passes the JSON object as `configVars` to the webhook invocation.

## Run an Agent by ID

```
/airtop-agents run 550e8400-e29b-41d4-a716-446655440000
```

Skips the name resolution step and uses the ID directly.

## Check Invocation Status

```
/airtop-agents status 550e8400-e29b-41d4-a716-446655440000 7c9e6679-7425-40de-944b-e07fc1f90ae7
```

First argument is the agent ID, second is the invocation ID.

## Cancel a Running Invocation

```
/airtop-agents cancel 550e8400-e29b-41d4-a716-446655440000 7c9e6679-7425-40de-944b-e07fc1f90ae7
```

Sends a cancellation request for the specified invocation.

## View Agent History

```
/airtop-agents history 550e8400-e29b-41d4-a716-446655440000
```

Shows the 10 most recent invocations for the agent.

## Common Scenarios

### Agent name matches multiple results

When running `run "Monitor"` and multiple agents match:

```
Multiple agents match "Monitor":
| # | Name               | ID                                   |
|---|--------------------|--------------------------------------|
| 1 | Price Monitor      | 550e8400-e29b-41d4-a716-446655440000 |
| 2 | Competitor Monitor | 6ba7b811-9dad-11d1-80b4-00c04fd430c8 |

Which agent would you like to run? (Enter number or ID)
```

### Agent has no webhook

```
Agent "My Agent" does not have a webhook configured.
Set up a webhook in the Airtop portal: https://portal.airtop.ai
```

### Invocation times out

If polling exceeds 5 minutes:

```
The invocation is still running after 5 minutes.
Invocation ID: 7c9e6679-7425-40de-944b-e07fc1f90ae7
Agent ID: 550e8400-e29b-41d4-a716-446655440000

Check status later with:
/airtop-agents status 550e8400-e29b-41d4-a716-446655440000 7c9e6679-7425-40de-944b-e07fc1f90ae7
```

### Missing API key

```
No Airtop API key found. Set it in one of these ways:
1. Export AIRTOP_API_KEY environment variable
2. Add it to the skill's .env file
3. Get your key at https://portal.airtop.ai/api-keys
```

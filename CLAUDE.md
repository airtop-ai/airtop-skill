# CLAUDE.md

## Project Overview

This is an Airtop Agents skill for Claude Code (and other AI coding agents). The skill file is `SKILL.md` and it teaches Claude how to list, run, monitor, and cancel Airtop agents via their REST API.

## Project Structure

- `SKILL.md` — The skill definition (frontmatter + instructions)
- `evals/evals.json` — 8 eval cases testing skill behavior
- `README.md` — User-facing documentation
- `EXAMPLES.md` — Usage examples
- `.env` — Local API key (not committed)

## Running Evals

### Important: Do NOT run evals from inside Claude Code

Running `claude -p` from within a Claude Code session (via the Bash tool or subagents) is unreliable:

- **Nested session detection**: Claude Code blocks nested launches via the `CLAUDECODE` env var. Unsetting it bypasses the check but doesn't fix the underlying resource issues.
- **Process starvation**: Multiple concurrent `claude -p` processes compete for resources. Shell wrappers stay alive while the actual node processes silently die.
- **No output**: Even sequential runs from the Bash tool often produce empty output due to stdout/stderr capture issues in the nested environment.
- **Timeouts**: Evals that poll (evals 2, 6, 7) can run for minutes, exceeding the Bash tool's default 2-minute timeout.

### How to run evals manually

Run each eval from an **external terminal** (not from within Claude Code):

```bash
cd /path/to/claude-code-airtop-skill

# Ensure API key is available
export AIRTOP_API_KEY="your-key-here"
# Or have a .env file with AIRTOP_API_KEY=...

# Run a single eval (example: eval 1)
unset CLAUDECODE && claude -p \
  --system-prompt "$(cat SKILL.md)" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --model sonnet \
  "List my Airtop agents" 2>/dev/null | tee /tmp/eval1.jsonl
```

### Eval prompts reference

| Eval | Prompt | Timeout Needed |
|------|--------|----------------|
| 1 | `List my Airtop agents` | ~30s |
| 2 | `List my enabled Airtop agents and run the first one` | ~5min (polls) |
| 3 | `Cancel Airtop agent invocation 6ba7b810-9dad-11d1-80b4-00c04fd430c8 on agent 550e8400-e29b-41d4-a716-446655440000` | ~30s |
| 4 | `Check the status of Airtop invocation 7c9e6679-7425-40de-944b-e07fc1f90ae7 on agent 550e8400-e29b-41d4-a716-446655440000` | ~30s |
| 5 | `Show the invocation history for Airtop agent 550e8400-e29b-41d4-a716-446655440000` | ~30s |
| 6 | `Run the Airtop agent called "Price Tracker" with variables url set to https://example.com and currency set to USD` | ~5min (polls) |
| 7 | `Run Airtop agent 550e8400-e29b-41d4-a716-446655440000` | ~5min (polls) |
| 8 | `Run the Airtop agent called "Carrier Source" (assume the API returns one agent named "Carrier Source Search Agent" that is disabled with hasDraft=true and no publishedVersion)` | ~30s |

### Checking assertions from stream-json output

Use `--output-format stream-json` to capture tool calls. Then grep for evidence:

```bash
# Check which curl commands were executed
grep -o '"command":"[^"]*curl[^"]*"' /tmp/eval1.jsonl

# Check for specific endpoints
grep "v2/agents" /tmp/eval1.jsonl

# Check for DELETE method (eval 3)
grep "DELETE" /tmp/eval3.jsonl
```

### Concurrency limits

If running multiple evals, limit to **2-3 concurrent** `claude -p` processes. Running all 8 in parallel will cause process starvation.

### Static analysis (alternative)

When live API testing isn't feasible (no API key, rate limits, fake UUIDs in evals 3-5 and 7), you can do a static analysis: review SKILL.md line-by-line against each eval's assertions to verify the instructions would produce the correct behavior. This is what was done in the initial eval run — all 34/34 assertions pass under static analysis.

### Known eval limitations

- **Evals 3, 4, 5, 7** use fake UUIDs that don't exist in any real Airtop account. The API will return 404, and the skill will correctly handle the error per its error handling section — but the subsequent steps (webhook fetch, invoke, poll) will never be reached. These evals are best validated via static analysis or with a mocked API.
- **Eval 8** depends on the API returning a specific agent shape (disabled, draft-only). If that agent doesn't exist, the eval tests the skill's error handling path rather than the disabled-agent detection logic.
- **Eval 2** requires at least one enabled agent with a webhook configured in your Airtop account.

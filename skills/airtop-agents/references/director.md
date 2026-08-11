# Agent Director

Create, edit, configure, and troubleshoot Airtop agents through Director's text-only API. Sending a message and viewing Director output are separate operations; neither provides a completion signal.

## Argument Parsing

Interpret Director requests using these intent shapes:

```
create <free-form requirements>                    Create an agent
edit <agent-name-or-id> <free-form changes>        Edit an existing agent
configure <agent-name-or-id> <free-form request>   Configure an agent or integration
troubleshoot <agent-name-or-id> <problem>           Troubleshoot an agent
continue <free-form follow-up>                      Continue the observed conversation
```

If `$ARGUMENTS` is empty or unrecognized, show the usage summary above and ask the user what they'd like to do.

## Commands

### 1. Send Message

Start **View Messages** and wait for its first successful response before sending.

```bash
MESSAGE_ID="msg-$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}${RANDOM}"
MESSAGE_TEXT="Create an agent that accepts a company URL and returns a cited executive brief."
REQUEST_BODY=$(jq -n \
  --arg messageId "$MESSAGE_ID" \
  --arg text "$MESSAGE_TEXT" \
  '{messageId:$messageId, text:$text}')

curl -sS -w '\nHTTP_STATUS:%{http_code}\n' \
  -X POST "https://api.airtop.ai/api/v1/agent-director/messages" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  --data "$REQUEST_BODY"
```

- Send exactly `{"messageId":"...","text":"..."}`. Include no other fields.
- `messageId` must be 1–96 characters matching `^[A-Za-z0-9][A-Za-z0-9._:-]*$`; `text` must be 1–100,000 characters and not only whitespace.
- Require a successful `curl` exit, `HTTP_STATUS:202`, and a JSON result of `accepted` or `already_accepted`.
- Treat either result as asynchronous queue acknowledgement, not completion or response correlation.
- On an ambiguous transport result, retry the identical `REQUEST_BODY`; do not generate another ID or rephrase the text.
- Before a follow-up POST, check stdout once more and handle any new Director messages before sending.
- Stop visibly on 401/403 or another definitive client error.

### 2. View Messages

```bash
(
  while true; do
    curl -sS -w '\nHTTP_STATUS:%{http_code}\n' \
      -H "Authorization: Bearer ${API_KEY}" \
      "https://api.airtop.ai/api/v1/agent-director/messages?limit=100"
    sleep 5
  done
) &
POLL_PID=$!
```

- Keep the background process attached to the harness terminal.
- Each response ends with an `HTTP_STATUS` marker. Parse the preceding JSON only after a successful `curl` call with `HTTP_STATUS:200`.
- Validate `sessionId` as a string or null and `messages` as an array whose items contain string `messageId`, `text`, and `createdAt` fields.
- Check stdout periodically and present any new or updated Director messages, preserving their exact text and links.
- Let the loop retry HTTP 503 after five seconds. On 401/403 or another definitive client error, stop it with `kill "$POLL_PID"` and report the error.
- No active session is a successful empty response: `{"sessionId":null,"messages":[]}`.

Polling rules:
- Check stdout for status updates every minute
- Print a status update to the user after every new status update from Director, or after 5 minutes of polling without a status update
- **Timeout after 30 minutes**. Stop the observer, and if no update was received, ask Director for a status update.

## Important Notes

- GET defaults to 50 messages and caps `limit` at 100. Results are the active runtime's latest externally visible items in chronological order.
- Snapshots are shared with Portal and Slack and are not task-isolated or causally correlated. Describe output as newly observed Director text unless the text itself establishes more.
- Snapshot history is best effort, not durable delivery. Items can be missed if more than 100 updates arrive between polls, the runtime ends or changes, or the harness is inactive.
- Some messages require user action in Developer Portal. In these cases, Director will provide a link in its message, which should be presented verbatim to the user.

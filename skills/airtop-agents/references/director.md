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

```bash
MESSAGE_ID="msg-$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}${RANDOM}"
MESSAGE_TEXT="Create an agent that accepts a company URL and returns a cited executive brief."
REQUEST_BODY=$(jq -n \
  --arg messageId "$MESSAGE_ID" \
  --arg text "$MESSAGE_TEXT" \
  '{messageId:$messageId, text:$text}')

RESPONSE=$(curl -sS -w $'\n%{http_code}' \
  -X POST "${API_BASE}/v1/agent-director/messages" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  --data "$REQUEST_BODY")
CURL_STATUS=$?
HTTP_STATUS=${RESPONSE##*$'\n'}
POST_BODY=${RESPONSE%$'\n'*}
```

- Send exactly `{"messageId":"...","text":"..."}`. Include no other fields.
- `messageId` must be 1–96 characters matching `^[A-Za-z0-9][A-Za-z0-9._:-]*$`; `text` must be 1–100,000 characters and not only whitespace.
- Parse `POST_BODY` only when `CURL_STATUS` is zero and `HTTP_STATUS` is `202`. Require `.result` to be `accepted` or `already_accepted`.
- Treat either result as asynchronous queue acknowledgement, not completion or response correlation.
- On an ambiguous transport result, retry the identical `REQUEST_BODY`; do not fetch another baseline, generate another ID, or rephrase the text.
- Stop visibly on 401/403 or another definitive client error.

### 2. View Messages

```bash
RESPONSE=$(curl -sS -w $'\n%{http_code}' \
  -H "Authorization: Bearer ${API_KEY}" \
  "${API_BASE}/v1/agent-director/messages?limit=100")
CURL_STATUS=$?
HTTP_STATUS=${RESPONSE##*$'\n'}
SNAPSHOT=${RESPONSE%$'\n'*}
```

- Parse `SNAPSHOT` only when `CURL_STATUS` is zero and `HTTP_STATUS` is `200`.
- Validate `sessionId` as a string or null and `messages` as an array whose items contain string `messageId`, `text`, and `createdAt` fields.
- Retry HTTP 503 with bounded backoff, such as 2, 4, then 8 seconds. Stop visibly on 401/403 or another definitive client error.
- No active session is a successful empty response: `{"sessionId":null,"messages":[]}`.
- Present messages in returned order and preserve their exact text and links.

Polling rules:
- Poll every **5 seconds**
- Check stdout for status updates every minute
- Print a status update to the user after every new status update from Director, or after 5 minutes of polling without a status update
- **Timeout after 30 minutes**. If no update is received within this time, ask Director for a status update.

## Important Notes

- GET defaults to 50 messages and caps `limit` at 100. Results are the active runtime's latest externally visible items in chronological order.
- Snapshots are shared with Portal and Slack and are not task-isolated or causally correlated. Describe output as newly observed Director text unless the text itself establishes more.
- Snapshot history is best effort, not durable delivery. Items can be missed if more than 100 updates arrive between polls, the runtime ends or changes, or the harness is inactive.
- Some messages require user action in Developer Portal. In these cases, Director will provide a link in its message, which should be presented verbatim to the user.

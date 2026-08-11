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
MESSAGE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

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
- Generate a new UUID only for a new logical message, including a later status request.
- After HTTP 202, start **View Messages** immediately.
- Stop visibly on 401/403 or another definitive client error.

### 2. View Messages

One polling iteration is:

```bash
curl -sS -w '\nHTTP_STATUS:%{http_code}\n' \
  -H "Authorization: Bearer ${API_KEY}" \
  "https://api.airtop.ai/api/v1/agent-director/messages?limit=100"
```

- Construct an observer as a background shell operation for the current task.
- Keep the background process attached to the harness terminal.
- Each response ends with an `HTTP_STATUS` marker. Parse the preceding JSON only after a successful `curl` call with `HTTP_STATUS:200`.
- Validate `sessionId` as a string or null and `messages` as an array whose items contain string `messageId`, `text`, and `createdAt` fields.
- Poll every 30 seconds. Keep responses and comparison state in task-local temporary files; do not print raw snapshots, unchanged messages, polling progress, or retryable errors into model context.
- Initialize an empty seen set once when beginning a Director conversation and preserve it across follow-ups and status checks. Identify output with the exact `(sessionId, messageId, text)` tuple; changed text or the same `messageId` in another session is new output.
- On the first successful non-empty snapshot, treat every tuple as unseen. Record and emit the entire batch as **recent Director conversation**, without claiming that the submitted request caused it.
- On later snapshots, record and emit the entire unseen batch once, then exit the observer immediately. Do not emit tuples already in the seen set.
- Retry HTTP 503 on the next polling interval. On 401/403 or another definitive client error, exit and report the error.
- No active session is a successful empty response: `{"sessionId":null,"messages":[]}`.

Use a 45-minute inactivity window:

- If the observer emits unseen messages, present every message with its exact text and links. If Director still appears to be working, start another observer with the same seen state. This starts a fresh 45-minute inactivity window.
- If no new Director text appears for 45 minutes, perform one final snapshot reconciliation. If that reveals new output, present it instead of requesting status.
- If the final reconciliation is still empty, exit the observer with one compact result; do not expose its repeated snapshots to the model.

### 3. Request Status After Prolonged Silence

After 45 minutes without new Director text and a final empty reconciliation, send one new logical message with a fresh UUID:

> Please provide a concise status update on the request to `<specific goal or agent>`. If work is blocked on user action, state exactly what is required and include the relevant Director Portal link.

- Preserve the existing seen state. The final reconciliation above is the status request's pre-POST snapshot.
- Observe for the status response for another 10–15 minutes, using the same local filtering and immediate-exit behavior.
- Send at most one automatic status request for the original request; never create a status-of-status loop.
- If Director requests approval, configuration, a connection, credentials, or another external action, present its exact request and link and wait for the user.
- If Director reports completion or failure, report Director's statement without asserting stronger causal correlation than the snapshot provides.
- If Director reports that work is continuing, tell the user and resume the normal 45-minute observation window with the same seen state.
- If no status response appears, tell the user that both messages were accepted but no new Director output was observed, stop polling, and ask whether they want to check again.

## Important Notes

- GET defaults to 50 messages and caps `limit` at 100. Results are the active runtime's latest externally visible items in chronological order.
- Snapshots are shared with Portal and Slack and are not task-isolated or causally correlated. Describe output as newly observed Director text unless the text itself establishes more.
- Snapshot history is best effort, not durable delivery. Items can be missed if more than 100 updates arrive between polls, the runtime ends or changes, or the harness is inactive.
- Some messages require user action in Developer Portal. In these cases, Director will provide a link in its message, which should be presented verbatim to the user.

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

Use the bundled observer. Replace `<skill-directory>` with the actual absolute path to the directory containing this skill, create one task-local directory for the Director conversation, and retain its log path:

```bash
OBSERVATION_DIR=$(mktemp -d "${TMPDIR:-/tmp}/airtop-director.XXXXXX")
OBSERVATION_LOG="$OBSERVATION_DIR/messages.jsonl"

<skill-directory>/scripts/director-observe \
  --log "$OBSERVATION_LOG" \
  --timeout-seconds 2700 \
  --poll-seconds 30
```

- Run the command as the foreground process inside one harness-managed background job. Keep the job attached to the harness.
- Run one observer per log and reuse that log throughout the conversation.
- On unseen output, read and retain the entire emitted array. Start the next observer if appropriate, then present every message’s exact text and links in the response. Never replace the batch with a progress summary.
- If Director requests approval, configuration, a connection, credentials, or another external action, present its exact request and link, then keep observing with the same log while waiting for the user's action.
- The first non-empty snapshot follows the same behavior. Because the log begins empty, present that batch as **recent Director conversation** without claiming that the submitted request caused it.
- After 45 minutes without unseen output, the script performs one final snapshot reconciliation. If still empty, it prints `{"result":"timeout","reason":"no_new_messages","elapsedSeconds":<number>}` and exits successfully.
- On a nonzero exit, report the compact stderr error. Do not replace, repair, or truncate the observation log automatically.

### 3. Request Status After Prolonged Silence

After the observer returns `result: "timeout"`, send one new logical message with a fresh UUID:

> Please provide a concise status update on the request to `<specific goal or agent>`. If work is blocked on user action, state exactly what is required and include the relevant Director Portal link.

- Observe for the status response with the same script and observation log, but use `--timeout-seconds 900`. Keep the 30-second polling interval.
- Send at most one automatic status request for the original request; never create a status-of-status loop.
- If Director reports completion or failure, report Director's statement without asserting stronger causal correlation than the snapshot provides.
- If Director reports that work is continuing, tell the user and resume the normal 45-minute observation window with the same observation log.
- If no status response appears, tell the user that both messages were accepted but no new Director output was observed, stop polling, and ask whether they want to check again.

## Important Notes

- GET defaults to 50 messages and caps `limit` at 100. Results are the active runtime's latest externally visible items in chronological order.
- Snapshots are shared with Portal and Slack and are not task-isolated or causally correlated. Describe output as newly observed Director text unless the text itself establishes more.
- Snapshot history is best effort, not durable delivery. Items can be missed if more than 100 updates arrive between polls, the runtime ends or changes, or the harness is inactive.
- Some messages require user action in Developer Portal. In these cases, Director will provide a link in its message, which should be presented verbatim to the user.

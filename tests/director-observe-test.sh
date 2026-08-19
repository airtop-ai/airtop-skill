#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OBSERVER="$ROOT_DIR/skills/airtop-agents/scripts/director-observe"
FAKE_BIN="$ROOT_DIR/tests/helpers"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/director-observe-test.XXXXXX")
PASSED=0

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  PASSED=$((PASSED + 1))
  printf 'ok %d - %s\n' "$PASSED" "$1"
}

new_case_dir() {
  local name="$1"
  local case_dir="$TEST_ROOT/$name"
  mkdir -p "$case_dir"
  printf '%s\n' "$case_dir"
}

run_observer() {
  local scenario="$1"
  local state_file="$2"
  shift 2

  PATH="$FAKE_BIN:$PATH" \
    AIRTOP_API_KEY="test-key" \
    FAKE_CURL_SCENARIO="$scenario" \
    FAKE_CURL_STATE="$state_file" \
    "$OBSERVER" "$@"
}

case_dir=$(new_case_dir "first-batch")
if ! output=$(run_observer "first-batch" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 2 --poll-seconds 1 2>"$case_dir/stderr"); then
  fail "first snapshot exits successfully"
fi
jq -e 'length == 2 and .[1].text == "Line one\nLine two"' <<<"$output" >/dev/null || fail "first snapshot emits the complete batch"
jq -e -s 'length == 2' "$case_dir/messages.jsonl" >/dev/null || fail "first snapshot appends every message as JSONL"
[[ ! -s "$case_dir/stderr" ]] || fail "first snapshot keeps stderr quiet"
pass "first snapshot appends and emits one compact batch"

case_dir=$(new_case_dir "duplicate-batch")
output=$(run_observer "duplicate-batch" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 2 --poll-seconds 1)
jq -e 'length == 1 and .[0].messageId == "update-1"' <<<"$output" >/dev/null || fail "duplicate snapshot entries are emitted once"
jq -e -s 'length == 1' "$case_dir/messages.jsonl" >/dev/null || fail "duplicate snapshot entries are appended once"
pass "duplicate identities within one snapshot are deduplicated"

case_dir=$(new_case_dir "changed-text")
printf '%s\n' '{"sessionId":"session-a","messageId":"approval-1","text":"Approval pending","createdAt":"2026-08-18T12:00:00Z"}' > "$case_dir/messages.jsonl"
output=$(run_observer "changed-text" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 2 --poll-seconds 1)
jq -e 'length == 1 and .[0].text == "Approval granted"' <<<"$output" >/dev/null || fail "changed text is treated as unseen"
jq -e -s 'length == 2' "$case_dir/messages.jsonl" >/dev/null || fail "unchanged tuple is not appended twice"
pass "deduplication uses sessionId, messageId, and text"

case_dir=$(new_case_dir "session-change")
printf '%s\n' '{"sessionId":"session-a","messageId":"update-1","text":"Working","createdAt":"2026-08-18T12:00:00Z"}' > "$case_dir/messages.jsonl"
output=$(run_observer "session-change" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 2 --poll-seconds 1)
jq -e 'length == 1 and .[0].sessionId == "session-b"' <<<"$output" >/dev/null || fail "session change is treated as unseen"
pass "message identity remains distinct across Director sessions"

case_dir=$(new_case_dir "retry")
output=$(run_observer "retry-then-message" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 5 --poll-seconds 1 2>"$case_dir/stderr")
jq -e 'length == 1 and .[0].text == "Recovered"' <<<"$output" >/dev/null || fail "observer emits output after retry"
[[ $(<"$case_dir/calls") == "3" ]] || fail "observer retries HTTP 503"
[[ ! -s "$case_dir/stderr" ]] || fail "retryable errors remain silent"
pass "HTTP 503 responses retry without entering model output"

case_dir=$(new_case_dir "final-retry")
if run_observer "unavailable" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 1 --poll-seconds 1 >"$case_dir/stdout" 2>"$case_dir/stderr"; then
  fail "a failed final reconciliation must fail"
fi
jq -e '.error == "final_reconciliation_failed"' "$case_dir/stderr" >/dev/null || fail "final retry error is structured"
[[ $(<"$case_dir/calls") == "2" ]] || fail "retryable snapshots stop after the final reconciliation"
pass "a retryable final snapshot reports a reconciliation failure"

case_dir=$(new_case_dir "timeout")
output=$(run_observer "empty" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 1 --poll-seconds 1)
jq -e '.result == "timeout" and .reason == "no_new_messages"' <<<"$output" >/dev/null || fail "empty snapshots end in a timeout result"
[[ $(<"$case_dir/calls") == "2" ]] || fail "timeout performs a final reconciliation"
[[ ! -d "$case_dir/messages.jsonl.lock" ]] || fail "observer releases its lock after timeout"
pass "inactivity timeout performs one final reconciliation"

case_dir=$(new_case_dir "final-message")
output=$(run_observer "final-message" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 1 --poll-seconds 1)
jq -e 'length == 1 and .[0].messageId == "update-final"' <<<"$output" >/dev/null || fail "final reconciliation surfaces late output"
pass "final reconciliation wins over a timeout"

case_dir=$(new_case_dir "invalid")
set +e
run_observer "invalid" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 1 --poll-seconds 1 >"$case_dir/stdout" 2>"$case_dir/stderr"
runtime_status=$?
set -e
if ((runtime_status == 0)); then
  fail "invalid snapshots must fail"
fi
((runtime_status == 1)) || fail "runtime failures must use exit code 1"
jq -e '.error == "invalid_snapshot"' "$case_dir/stderr" >/dev/null || fail "invalid snapshot error is structured"
[[ ! -s "$case_dir/messages.jsonl" ]] || fail "invalid snapshot must not modify the log"
pass "invalid snapshots fail without modifying observation state"

case_dir=$(new_case_dir "unauthorized")
if run_observer "unauthorized" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 1 --poll-seconds 1 >"$case_dir/stdout" 2>"$case_dir/stderr"; then
  fail "authentication failures must fail"
fi
jq -e '.error == "authentication_failed"' "$case_dir/stderr" >/dev/null || fail "authentication error is structured"
pass "authentication errors stop immediately"

case_dir=$(new_case_dir "corrupt-log")
printf '%s\n' 'not-json' > "$case_dir/messages.jsonl"
if run_observer "empty" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 1 --poll-seconds 1 >"$case_dir/stdout" 2>"$case_dir/stderr"; then
  fail "corrupt logs must fail"
fi
jq -e '.error == "invalid_observation_log"' "$case_dir/stderr" >/dev/null || fail "corrupt log error is structured"
[[ $(<"$case_dir/messages.jsonl") == "not-json" ]] || fail "corrupt log must never be truncated"
pass "corrupt append-only logs are preserved and rejected"

case_dir=$(new_case_dir "zero-timeout")
if run_observer "empty" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 0 --poll-seconds 1 >"$case_dir/stdout" 2>"$case_dir/stderr"; then
  fail "zero timeout must be rejected"
fi
jq -e '.error == "invalid_timeout_seconds"' "$case_dir/stderr" >/dev/null || fail "zero timeout error is structured"
pass "timeout must be a positive integer"

case_dir=$(new_case_dir "lock")
run_observer "empty" "$case_dir/calls" --log "$case_dir/messages.jsonl" --timeout-seconds 2 --poll-seconds 1 >"$case_dir/first.stdout" 2>"$case_dir/first.stderr" &
first_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -d "$case_dir/messages.jsonl.lock" ]] && break
  sleep 0.1
done
[[ ! -s "$case_dir/first.stdout" ]] || fail "running observer must remain silent before an outcome"
if run_observer "empty" "$case_dir/second.calls" --log "$case_dir/messages.jsonl" --timeout-seconds 1 --poll-seconds 1 >"$case_dir/second.stdout" 2>"$case_dir/second.stderr"; then
  kill "$first_pid" 2>/dev/null || true
  fail "a second observer must not acquire the same log"
fi
jq -e '.error == "observer_already_running"' "$case_dir/second.stderr" >/dev/null || fail "duplicate observer error is structured"
wait "$first_pid"
pass "one observer owns a conversation log at a time"

printf '%s\n' "1..$PASSED"

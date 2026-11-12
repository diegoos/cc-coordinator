#!/usr/bin/env bash
# Tests for scripts/coordinator-hook.cmd. Run: bash tests/coordinator-hook.test.sh
# Set COORDINATOR_HOOK_BIN to test a built binary directly instead of the wrapper.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="${COORDINATOR_HOOK_BIN:-$root/scripts/coordinator-hook.cmd}"
data_dir="$(mktemp -d)"
state="$data_dir/sessions/s1"
failures=0

command -v jq >/dev/null || { echo "jq is required to run these tests" >&2; exit 1; }

trap 'rm -rf "$data_dir"' EXIT

export CLAUDE_PLUGIN_ROOT="$root"
export CLAUDE_PLUGIN_DATA="$data_dir"

run_hook() {
  printf '%s' "$2" | "$hook" "$1" 2>/dev/null
}

expansion() {
  run_hook expansion "{\"session_id\":\"s1\",\"command_name\":\"$1\",\"command_args\":\"${2:-}\",\"command_source\":\"plugin\",\"prompt\":\"/$1 ${2:-}\"}"
}

submit() {
  run_hook submit "{\"session_id\":\"s1\",\"prompt\":\"$1\"}"
}

context_of() {
  jq -r '.hookSpecificOutput.additionalContext // empty'
}

check() {
  local name="$1"

  shift

  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

contains() {
  [[ "$1" == *"$2"* ]]
}

lacks() {
  [[ "$1" != *"$2"* ]]
}

out=$(expansion coordinator:start | context_of)
check "start creates state" test -f "$state"
check "start injects start" contains "$out" "set **coordinator mode** on"
check "start carries rules" contains "$out" 'subagent_type: "general-purpose"'
check "rules leave the model to the tier" lacks "$out" 'model: "haiku"'
check "rules point to the Model section" contains "$out" "Model section"
check "start asks for the on footer" contains "$out" '`**Coordinator**: on (low)`'
check "start resolves the coordinator path" contains "$out" "$root/references/coordinator.md"
check "start has no unresolved placeholder" lacks "$out" "{{COORDINATOR_PATH}}"

out=$(expansion coordinator:start "fix the bug" | context_of)
check "start with a prompt keeps state on" test -f "$state"

out=$(submit "fix the bug" | context_of)
check "submit with state injects continue" contains "$out" "still in **coordinator mode**"
check "continue asks for the on footer" contains "$out" '`**Coordinator**: on (low)`'
check "continue points to the coordinator" contains "$out" "$root/references/coordinator.md"

for prompt in "/coordinator:stop" "/coordinator:once fix it" "/coordinator:skip fix it" "/coordinator:start" "  /coordinator:skip"; do
  out=$(submit "$prompt")
  check "submit skips '$prompt'" test -z "$out"
done

for prompt in "/start" "/skip fix it" "/coordinator:startle" "/coordinator on" "/coordinator stop" "/coordinatoring stop"; do
  out=$(submit "$prompt" | context_of)
  check "submit treats '$prompt' as a request" contains "$out" "still in **coordinator mode**"
done

out=$(expansion coordinator:once "fix it" | context_of)
check "once with mode on keeps state on" test -f "$state"
check "once with mode on asks for the on footer" contains "$out" '`**Coordinator**: on (low)`'
check "once with mode on omits the once footer" lacks "$out" '`**Coordinator**: once`'

out=$(expansion coordinator:skip "what is the node version" | context_of)
check "skip keeps state on" test -f "$state"
check "skip injects skip" contains "$out" "this request skips it"
check "skip asks for the skip footer" contains "$out" '`**Coordinator**: on (skip)`'
check "skip omits worker rules" lacks "$out" 'subagent_type: "general-purpose"'

out=$(submit "fix the bug" | context_of)
check "request after skip injects continue" contains "$out" "still in **coordinator mode**"

out=$(expansion coordinator:skip "" | context_of)
check "empty skip asks to resend" contains "$out" "send the request again"
check "empty skip with mode on keeps the on footer" contains "$out" '`**Coordinator**: on (low)`'
check "empty skip keeps state on" test -f "$state"

out=$(expansion coordinator:once "   " | context_of)
check "blank once asks to resend" contains "$out" "send the request again"
check "blank once omits worker rules" lacks "$out" 'subagent_type: "general-purpose"'

out=$(expansion coordinator:stop | context_of)
check "stop removes state" test ! -f "$state"
check "stop injects stop" contains "$out" "turned off **coordinator mode**"
check "stop asks for the off footer" contains "$out" '`**Coordinator**: off`'

out=$(expansion coordinator:stop | context_of)
check "stop with mode off injects stop-off" contains "$out" "was already off"

out=$(submit "fix the bug")
check "submit without state is silent" test -z "$out"

out=$(expansion coordinator:skip "what is the node version" | context_of)
check "skip with mode off keeps state off" test ! -f "$state"
check "skip with mode off injects skip-off" contains "$out" "mode** is off"

out=$(expansion coordinator:once "fix test X" | context_of)
check "once keeps state off" test ! -f "$state"
check "once carries rules" contains "$out" 'subagent_type: "general-purpose"'
check "once with mode off uses the low tier" contains "$out" 'tier is `low`'
check "once asks for the once footer" contains "$out" '`**Coordinator**: once`'

out=$(expansion coordinator:once 'fix\nthe test' | context_of)
check "once accepts multi-line prompt" contains "$out" '`**Coordinator**: once`'

out=$(expansion coordinator:once "" | context_of)
check "empty once with mode off has no footer" lacks "$out" '**Coordinator**'

touch -t 202001010000 "$state" "$data_dir/sessions/old"
submit "fix the bug" >/dev/null
check "submit refreshes the state file" test -z "$(find "$state" -mtime +1)"
expansion coordinator:start >/dev/null
check "start removes a stale state file" test ! -f "$data_dir/sessions/old"
check "start keeps the current state file" test -f "$state"
run_hook session-end '{"session_id":"s1"}'
check "session-end removes state" test ! -f "$state"

for name in start other:start coordinator:on coordinator:off coordinator:coordinator coordinator multitask:start; do
  out=$(expansion "$name" "x")
  check "command '$name' is ignored" test -z "$out"
  check "command '$name' keeps state off" test ! -f "$state"
done

out=$(run_hook expansion '{"session_id":"../escape","command_name":"coordinator:start","command_args":""}')
check "invalid session_id is rejected" test -z "$out"
check "invalid session_id writes nothing outside" test ! -e "$data_dir/escape"

out=$(run_hook submit 'not json')
status=$?
check "malformed JSON exits 0" test "$status" -eq 0
check "malformed JSON prints nothing" test -z "$out"

json=$(cat <<'EOF'
{"session_id":"s1","command_name":"coordinator:once","command_args":"say \"hi\"\nnext","prompt":"/coordinator:once say \"hi\"\nnext"}
EOF
)
out=$(printf '%s' "$json" | "$hook" expansion 2>/dev/null | context_of)
check "once accepts quotes and a newline in args" contains "$out" '`**Coordinator**: once`'
check "once with quotes keeps state off" test ! -f "$state"

out=$(run_hook expansion '{"session_id":"s1","command_name":"coordinator:once","prompt":"/coordinator:once fix it"}' | context_of)
check "once without command_args reads the prompt" lacks "$out" "send the request again"
check "once from prompt keeps the once footer" contains "$out" '`**Coordinator**: once`'

out=$(run_hook expansion '{"session_id":"s1","command_name":"coordinator:skip","command_args":"","prompt":"/coordinator:skip"}' | context_of)
check "skip without a request asks to resend" contains "$out" "send the request again"

out=$(run_hook expansion '{"session_id":"s1","command_name":"coordinator:once","command_args":"","prompt":"/coordinator:once fix it"}' | context_of)
check "blank command_args falls back to the prompt" contains "$out" '`**Coordinator**: once`'

expansion coordinator:start >/dev/null
out=$(printf '{"session_id":"s1"}' | CLAUDE_PLUGIN_ROOT= "$hook" session-end 2>/dev/null; test ! -f "$state" && echo gone)
check "session-end works without a plugin root" contains "$out" gone

out=$(printf '{"session_id":"s1"}' | CLAUDE_PLUGIN_DATA= "$hook" submit 2>/dev/null)
check "missing plugin data dir is silent" test -z "$out"

expansion coordinator:start >/dev/null
check "expansion names its event" test "$(expansion coordinator:skip "what is the node version" | jq -r '.hookSpecificOutput.hookEventName')" = UserPromptExpansion
check "submit names its event" test "$(submit "fix the bug" | jq -r '.hookSpecificOutput.hookEventName')" = UserPromptSubmit

run_hook session-end 'not json'
check "session-end with invalid JSON exits 0" test $? -eq 0
check "session-end with invalid JSON keeps other state" test -f "$state"

run_hook bogus '{"session_id":"s1"}'
check "unknown event exits 0" test $? -eq 0
check "unknown event prints nothing" test -z "$(run_hook bogus '{"session_id":"s1"}')"
check "unknown event keeps state" test -f "$state"

printf '{"session_id":"s1"}' | "$hook" 2>/dev/null
check "missing event argument exits 0" test $? -eq 0
check "missing event argument prints nothing" test -z "$(printf '{"session_id":"s1"}' | "$hook" 2>/dev/null)"

out=$(printf '%s' '{"session_id":"s1","command_name":"coordinator:start","command_args":""}' | env -u CLAUDE_PLUGIN_ROOT "$hook" expansion 2>/dev/null | context_of)
check "missing plugin root falls back to the install path" contains "$out" "$root/references/coordinator.md"

long_id=$(head -c 200 /dev/zero | tr '\0' a)
out=$(printf '{"session_id":"%s","command_name":"coordinator:start","command_args":""}' "$long_id" | "$hook" expansion 2>/dev/null)
check "long session_id prints nothing" test -z "$out"
check "long session_id writes no state" test ! -e "$data_dir/sessions/$long_id"

max_id=$(head -c 128 /dev/zero | tr '\0' a)
printf '{"session_id":"%s","command_name":"coordinator:start","command_args":""}' "$max_id" | "$hook" expansion >/dev/null 2>&1
check "128-character session_id keeps state" test -f "$data_dir/sessions/$max_id"

bad_data="$(mktemp -d)"
: > "$bad_data/sessions"
out=$(printf '%s' '{"session_id":"s1","command_name":"coordinator:start","command_args":""}' | CLAUDE_PLUGIN_DATA="$bad_data" "$hook" expansion 2>/dev/null)
check "start that cannot write state warns the user" contains "$out" "could not turn on"
check "start that cannot write state says the mode did not change" contains "$(printf '%s' "$out" | context_of)" "did not change"
rm -rf "$bad_data"

expansion coordinator:start >/dev/null
chmod 444 "$state"
out=$(expansion coordinator:start | context_of)
check "start with a read-only state file reports the mode on" contains "$out" "set **coordinator mode** on"
check "start with a read-only state file asks for the on footer" contains "$out" '`**Coordinator**: on (low)`'
chmod 644 "$state"

chmod 555 "$data_dir/sessions"
out=$(expansion coordinator:stop)
check "stop that cannot remove state warns the user" contains "$out" "could not turn off"
check "stop that cannot remove state says the mode did not change" contains "$(printf '%s' "$out" | context_of)" "did not change"
check "stop that cannot remove state keeps the on footer" contains "$(printf '%s' "$out" | context_of)" '`**Coordinator**: on (low)`'
check "stop that cannot remove state keeps state on" test -f "$state"
chmod 755 "$data_dir/sessions"

rm -f "$state"
mkdir "$state"
out=$(expansion coordinator:stop | context_of)
check "stop with a directory as state injects stop-off" contains "$out" "was already off"
out=$(expansion coordinator:start)
check "start with a directory as state warns the user" contains "$out" "could not turn on"
run_hook session-end '{"session_id":"s1"}'
check "session-end that cannot remove state exits 0" test $? -eq 0
rmdir "$state"

models_of() {
  case "$1" in
    low) echo 'only `haiku`' ;;
    mid) echo '`haiku` or `sonnet`' ;;
    high) echo '`haiku`, `sonnet`, or `opus`' ;;
  esac
}

for tier in low mid high; do
  out=$(expansion coordinator:start "$tier fix the bug" | context_of)
  check "start $tier stores the tier" test "$(cat "$state")" = "$tier"
  check "start $tier names the tier" contains "$out" "tier is \`$tier\`"
  check "start $tier names its models" contains "$out" "$(models_of "$tier")"
  check "start $tier asks for the $tier footer" contains "$out" "\`**Coordinator**: on ($tier)\`"
  check "start $tier carries rules" contains "$out" 'subagent_type: "general-purpose"'
  expansion coordinator:stop >/dev/null
done

expansion coordinator:start >/dev/null
check "start with no tier and mode off stores low" test "$(cat "$state")" = low

out=$(expansion coordinator:start mid | context_of)
check "start with a tier and mode on changes the tier" test "$(cat "$state")" = mid
check "tier change asks for the new footer" contains "$out" '`**Coordinator**: on (mid)`'

out=$(expansion coordinator:start | context_of)
check "start with no tier keeps the saved tier" test "$(cat "$state")" = mid
check "start with no tier asks for the saved footer" contains "$out" '`**Coordinator**: on (mid)`'

out=$(expansion coordinator:start "fix the high bug" | context_of)
check "a first word that is not a tier keeps the saved tier" test "$(cat "$state")" = mid
check "a first word that is not a tier names the saved tier" contains "$out" 'tier is `mid`'

for args in "High priority bug" "high-priority bug" "higher limit"; do
  expansion coordinator:start "$args" >/dev/null
  check "start '$args' keeps the tier" test "$(cat "$state")" = mid
done

out=$(submit "fix the bug" | context_of)
check "submit names the saved tier" contains "$out" 'tier is `mid`'
check "submit names the models of the tier" contains "$out" "$(models_of mid)"
check "submit asks for the tier footer" contains "$out" '`**Coordinator**: on (mid)`'
check "continue points to the Model section" contains "$out" "Model section"

out=$(expansion coordinator:once "fix it" | context_of)
check "once with mode on uses the saved tier" contains "$out" 'tier is `mid`'
check "once with mode on asks for the tier footer" contains "$out" '`**Coordinator**: on (mid)`'

out=$(expansion coordinator:skip "" | context_of)
check "empty skip with mode on keeps the tier footer" contains "$out" '`**Coordinator**: on (mid)`'

expansion coordinator:start "high priority bug" >/dev/null
check "start 'high priority bug' stores high" test "$(cat "$state")" = high
expansion coordinator:start "low high priority bug" >/dev/null
check "start 'low high priority bug' stores low" test "$(cat "$state")" = low

run_hook expansion '{"session_id":"s1","command_name":"coordinator:start","prompt":"/coordinator:start high fix it"}' >/dev/null
check "start without command_args reads the tier from the prompt" test "$(cat "$state")" = high

for content in "" "max"; do
  printf '%s' "$content" > "$state"
  out=$(submit "fix the bug" | context_of)
  check "state '$content' reads as low on submit" contains "$out" '`**Coordinator**: on (low)`'
  out=$(expansion coordinator:start | context_of)
  check "state '$content' reads as low on start" contains "$out" 'tier is `low`'
done

printf mid > "$state"
chmod 555 "$data_dir/sessions"
out=$(expansion coordinator:start mid | context_of)
check "start with the saved tier needs no write" contains "$out" "set **coordinator mode** on"
out=$(expansion coordinator:start high)
check "tier change that cannot write state warns the user" contains "$(printf '%s' "$out" | jq -r '.systemMessage')" "coordinator: could not change"
out=$(printf '%s' "$out" | context_of)
check "tier change that cannot write state says the tier did not change" contains "$out" 'tier is still `mid`'
check "tier change that cannot write state keeps the previous footer" contains "$out" '`**Coordinator**: on (mid)`'
check "tier change that cannot write state keeps the previous models" contains "$out" "$(models_of mid)"
check "tier change that cannot write state keeps the tier" test "$(cat "$state")" = mid

out=$(expansion coordinator:stop | context_of)
check "stop that cannot remove state keeps the tier footer" contains "$out" '`**Coordinator**: on (mid)`'
chmod 755 "$data_dir/sessions"

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }

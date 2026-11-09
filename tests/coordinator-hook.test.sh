#!/usr/bin/env bash
# Tests for scripts/coordinator-hook.cmd. Run: bash tests/coordinator-hook.test.sh
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/scripts/coordinator-hook.cmd"
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
check "start injects start" contains "$out" "turned on **coordinator mode**"
check "start carries rules" contains "$out" 'model: "haiku"'
check "start asks for the on footer" contains "$out" '`**Coordinator**: on`'
check "start resolves the coordinator path" contains "$out" "$root/references/coordinator.md"
check "start has no unresolved placeholder" lacks "$out" "{{COORDINATOR_PATH}}"

out=$(expansion coordinator:start "fix the bug" | context_of)
check "start with a prompt keeps state on" test -f "$state"

out=$(submit "fix the bug" | context_of)
check "submit with state injects continue" contains "$out" "still in **coordinator mode**"
check "continue asks for the on footer" contains "$out" '`**Coordinator**: on`'
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
check "once with mode on asks for the on footer" contains "$out" '`**Coordinator**: on`'
check "once with mode on omits the once footer" lacks "$out" '`**Coordinator**: once`'

out=$(expansion coordinator:skip "what is the node version" | context_of)
check "skip keeps state on" test -f "$state"
check "skip injects skip" contains "$out" "this request skips it"
check "skip asks for the skip footer" contains "$out" '`**Coordinator**: on (skip)`'
check "skip omits worker rules" lacks "$out" 'model: "haiku"'

out=$(submit "fix the bug" | context_of)
check "request after skip injects continue" contains "$out" "still in **coordinator mode**"

out=$(expansion coordinator:skip "" | context_of)
check "empty skip asks to resend" contains "$out" "send the request again"
check "empty skip with mode on keeps the on footer" contains "$out" '`**Coordinator**: on`'
check "empty skip keeps state on" test -f "$state"

out=$(expansion coordinator:once "   " | context_of)
check "blank once asks to resend" contains "$out" "send the request again"
check "blank once omits worker rules" lacks "$out" 'model: "haiku"'

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
check "once carries rules" contains "$out" 'model: "haiku"'
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

expansion coordinator:start >/dev/null
out=$(printf '{"session_id":"s1"}' | CLAUDE_PLUGIN_ROOT= "$hook" session-end 2>/dev/null; test ! -f "$state" && echo gone)
check "session-end works without a plugin root" contains "$out" gone

out=$(printf '{"session_id":"s1"}' | CLAUDE_PLUGIN_DATA= "$hook" submit 2>/dev/null)
check "missing plugin data dir is silent" test -z "$out"

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }

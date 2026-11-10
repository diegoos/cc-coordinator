#!/usr/bin/env bash
# Tests scripts/coordinator-hook.cmd with stub binaries, stub uname and stub sysctl.
# Run: bash tests/coordinator-wrapper.test.sh
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
plugin="$work/plugin"
stubs="$work/stubs"
failures=0

trap 'rm -rf "$work"' EXIT

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

targets="macos-arm64 macos-x64 linux-arm64 linux-x64 windows-arm64.exe windows-x64.exe"

mkdir -p "$plugin/scripts/bin" "$stubs"
cp "$root/scripts/coordinator-hook.cmd" "$plugin/scripts/coordinator-hook.cmd"
chmod +x "$plugin/scripts/coordinator-hook.cmd"

for target in $targets; do
  printf '#!/bin/sh\necho "$(basename "$0") $*"\n' > "$plugin/scripts/bin/hook-$target"
  chmod +x "$plugin/scripts/bin/hook-$target"
done

printf '#!/bin/sh\ncase "$1" in -s) echo "$FAKE_OS" ;; -m) echo "$FAKE_ARCH" ;; esac\n' > "$stubs/uname"
printf '#!/bin/sh\necho "$FAKE_TRANSLATED"\n' > "$stubs/sysctl"
chmod +x "$stubs/uname" "$stubs/sysctl"

# Runs the wrapper of $plugin as if the host were $1 on architecture $2.
run_as() {
  FAKE_OS="$1" FAKE_ARCH="$2" FAKE_TRANSLATED="${3:-0}" PATH="$stubs:$PATH" \
    "$plugin/scripts/coordinator-hook.cmd" expansion
}

expect() {
  local name="$1" want="$2"
  local got

  shift 2
  got=$(run_as "$@" 2>/dev/null)
  check "$name" test "$got" = "$want"
}

expect "macOS arm64 runs the macos-arm64 binary" "hook-macos-arm64 expansion" Darwin arm64
expect "macOS x64 runs the macos-x64 binary" "hook-macos-x64 expansion" Darwin x86_64
expect "macOS x64 under Rosetta runs the macos-arm64 binary" "hook-macos-arm64 expansion" Darwin x86_64 1
expect "Linux x64 runs the linux-x64 binary" "hook-linux-x64 expansion" Linux x86_64
expect "Linux arm64 runs the linux-arm64 binary" "hook-linux-arm64 expansion" Linux aarch64
expect "Windows x64 runs the windows-x64 binary" "hook-windows-x64.exe expansion" MINGW64_NT-10.0 x86_64
expect "Windows arm64 runs the windows-arm64 binary" "hook-windows-arm64.exe expansion" MINGW64_NT-10.0 aarch64

out=$(run_as Linux riscv64 2>"$work/err")
status=$?
check "unsupported architecture exits 0" test "$status" -eq 0
check "unsupported architecture prints nothing" test -z "$out"
check "unsupported architecture warns on stderr" grep -q "unsupported architecture" "$work/err"

empty="$work/empty"
mkdir -p "$empty/scripts"
cp "$root/scripts/coordinator-hook.cmd" "$empty/scripts/"
chmod +x "$empty/scripts/coordinator-hook.cmd"

out=$(plugin="$empty" run_as Linux x86_64 2>"$work/err")
status=$?
check "missing binary exits 0" test "$status" -eq 0
check "missing binary prints nothing" test -z "$out"
check "missing binary warns on stderr" grep -q "binary not found" "$work/err"

for target in $targets; do
  check "scripts/bin has hook-$target" test -f "$root/scripts/bin/hook-$target"
done

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }

# Claude Code Coordinator

Plugin for Claude Code. It puts the session in coordinator mode. The main session sends work that needs more than a quick lookup to Haiku 5.5 workers in the background, and it stays free for new requests. When a worker finishes, Claude Code notifies the session. The session checks the files on disk and answers with the result, the evidence, and what is still open.

The plugin has four commands, one skill each in `skills/`. The coordinator instructions are in [`references/coordinator.md`](references/coordinator.md). `/coordinator:start` and `/coordinator:once` read that file. The commands load only when you type them. `disable-model-invocation: true` stops the model from loading them on its own.

## How it works

The main session routes the request, delegates it, and checks the result.

For each request it picks one path:

- It answers directly when the conversation already has the answer, or when zero or one quick tool call is enough.
- It sends one worker otherwise. That worker investigates, implements, and verifies, because those steps share context. A typical bug, a typical feature, and a medium refactor each go to one worker.
- It opens up to 5 workers in the same message only for independent fronts: separate areas of the code, separate requests, or a review where you compare independent answers.
- It runs one long command, such as a build or the test suite, with background Bash.

Each worker is a new `general-purpose` agent with `model: "haiku"`. A fork inherits the session model and ignores that setting. The coordinator chooses `low`, `medium`, or `high` from the task. If two levels both fit, it uses the higher one. When the `Agent` schema has no `effort`, the harness default applies, and the notice names it. A level you name has priority.

Workers edit the checkout you have open. Two workers run at the same time only when their files do not overlap and they do not share a port, a database, or a build target. The brief is [`references/brief-template.md`](references/brief-template.md). A worker cannot ask questions. If a decision is missing, it stops with `status: blocked`.

After a delegation, the coordinator ends the response. The completion notification starts the next turn. On that turn it compares the worker's claims with the files on disk, then answers.

Responses in the mode end with a footer, `**Coordinator**: on`, `once`, `on (skip)`, or `off`, so you can see the state.

The hook ([`hooks/hooks.json`](hooks/hooks.json), [`scripts/coordinator-hook.cmd`](scripts/coordinator-hook.cmd)) keeps the mode on across turns, including after `/compact`. The wrapper script selects the binary for macOS, Linux, or Windows, on x64 or arm64. The hook writes `${CLAUDE_PLUGIN_DATA}/sessions/<session_id>` when `/coordinator:start` runs, and removes it when `/coordinator:stop` runs or the session ends. `/clear` ends the session too, so the mode is off after `/clear`, and `/coordinator:start` turns it on again. While that file exists, each later prompt gets a short reminder that points at the coordinator instructions. This includes the turns that Claude Code starts on its own, such as a worker completion notification, because `UserPromptSubmit` fires on those turns too. A prompt that starts with a `/coordinator:` command gets no prompt reminder. Its reminder comes from the command hook, so `/coordinator:skip` and `/coordinator:once` get one while the mode is on. When `/coordinator:once` or `/coordinator:skip` comes with no request, the hook asks you to send it again. A resumed session starts with the mode off. `/coordinator:start` also deletes state files older than 30 days. The cleanup cannot tell an idle live session from a crashed one, so a session with no prompt for 30 days can lose its state, and its next prompt gets no reminder. If the hook cannot write or remove the state file, it shows a `coordinator:` warning, and tells the model that the mode did not change.

## Commands

| Command | Effect |
| --- | --- |
| `/coordinator:start` | Starts the coordinator for this session. Any text after the command is handled in the mode. |
| `/coordinator:stop` | Stops the coordinator. Workers that are still running continue. The session checks each one when it finishes. |
| `/coordinator:once PROMPT` | Applies the mode to `PROMPT` and to the turns where its workers finish. The session state stays as it was. If the mode is already on, `PROMPT` is an ordinary request in the mode. |
| `/coordinator:skip PROMPT` | Does `PROMPT` in the foreground, with no new worker. If the mode is on, it stays on, and the next request uses it again. If the mode is off, `PROMPT` is an ordinary request and there is no footer. |

## Install

This folder is the `ds-marketplace` marketplace, for diegoos's plugins and skills. From the GitHub repository that holds it, on Claude Code 2.1.311 or later:

```text
/plugin install coordinator --marketplace <owner>/<repo>
```

To load a local copy while you change the plugin:

```bash
claude --plugin-dir /path/to/cc-coordinator
```

## Contributing

The hook is a Rust program in [`hook/`](hook/). The reminders it injects are in [`hook/src/reminders.rs`](hook/src/reminders.rs). The binaries in [`scripts/bin/`](scripts/bin/) are committed, so a change to the hook is not complete until you rebuild them.

You need `rustup` and `zig`. Run `make install` once to add the Rust targets and `cargo-zigbuild`. Then run:

```bash
make
```

`make` builds the hook for macOS, Linux, and Windows on x64 and arm64, copies each binary to `scripts/bin/`, and runs the tests. To run only the tests, use `make test`. They are the Rust unit tests and [`tests/coordinator-hook.test.sh`](tests/coordinator-hook.test.sh), which needs `jq`, and [`tests/coordinator-wrapper.test.sh`](tests/coordinator-wrapper.test.sh), which runs the wrapper with stub binaries for each platform. `make test` runs the hook shell tests against the binary it builds, not against the ones in `scripts/bin/`. Add a check to that script for each change in hook behavior.

The behavior of the coordinator lives in [`references/coordinator.md`](references/coordinator.md) and in the skills. The cases in [`evals/`](evals/) test it. Each case sends one prompt with the mode off, so the `/coordinator:skip` case with the mode on is covered only by the shell tests. To run the cases:

```bash
make clean
claude plugin eval . --scaffold --allow-tools Bash Write Edit
```

`make clean` is required. Cargo creates hard links in `hook/target/`, and `claude plugin eval` refuses a plugin that contains them. `--scaffold` copies each case's input files. Add `--case NAME` to run one case. Results go to `evals/results/`, which is in `.gitignore`. A case passes when its `passRate` is `1`, and `aggregate-result.json` in the results folder has the numbers.

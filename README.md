# Claude Code Coordinator

Plugin for Claude Code. It puts the session in coordinator mode. The main session sends work that needs more than a quick lookup to workers in the background, and it stays free for new requests. A tier (`low`, `mid`, or `high`) sets the models a worker can use: Haiku, Sonnet, or Opus. When a worker finishes, Claude Code notifies the session. The session checks the files on disk and answers with the result, the evidence, and what is still open.

The plugin has four commands, one skill each in `skills/`. The coordinator instructions are in [`references/coordinator.md`](references/coordinator.md). `/coordinator:start` and `/coordinator:once` read that file. The commands load only when you type them. `disable-model-invocation: true` stops the model from loading them on its own.

## How it works

The main session routes the request, delegates it, and checks the result.

For each request it picks one path:

- It answers directly when the conversation already has the answer, or when zero or one quick tool call is enough.
- It sends one worker otherwise. That worker investigates, implements, and verifies, because those steps share context. A typical bug, a typical feature, and a medium refactor each go to one worker.
- It opens up to 5 workers in the same message only for independent fronts: separate areas of the code, separate requests, or a review where you compare independent answers.
- It runs one long command, such as a build or the test suite, with background Bash.

Each worker is a new `general-purpose` agent. A fork inherits the session model and ignores the `model` setting. The coordinator first chooses the model that the tier allows for the task, then the effort: `low`, `medium`, or `high`. A one-line notice names both. [Cost design](#cost-design) gives the rules and the reasons. When the `Agent` schema has no `effort`, the harness default applies, and the notice names it. A level you name has priority.

Workers edit the checkout you have open. Two workers run at the same time only when their files do not overlap and they do not share a port, a database, or a build target. The brief is [`references/brief-template.md`](references/brief-template.md). Its `Read:` list names the exact paths the worker reads. A worker cannot ask questions. If a decision is missing, it stops with `status: blocked`.

After a delegation, the coordinator ends the response. The completion notification starts the next turn. On that turn it compares the worker's claims with the files on disk, then answers. If the work failed, it first gives the worker a check to run, then raises the effort, then uses the next model of the tier. At the top of the tier it stops and reports.

Responses in the mode end with a footer, `**Coordinator**: on (low)`, `on (mid)`, `on (high)`, `once`, `on (skip)`, or `off`, so you can see the state and the tier.

The hook ([`hooks/hooks.json`](hooks/hooks.json), [`scripts/coordinator-hook.cmd`](scripts/coordinator-hook.cmd)) keeps the mode on across turns, including after `/compact`. The wrapper script selects the binary for macOS, Linux, or Windows, on x64 or arm64. The hook writes `${CLAUDE_PLUGIN_DATA}/sessions/<session_id>` when `/coordinator:start` runs, and removes it when `/coordinator:stop` runs or the session ends. That file holds the tier. An empty file or an unknown value means `low`. `/clear` ends the session too, so the mode is off after `/clear`, and `/coordinator:start` turns it on again. While that file exists, each later prompt gets a short reminder that points at the coordinator instructions and states the tier. This includes the turns that Claude Code starts on its own, such as a worker completion notification, because `UserPromptSubmit` fires on those turns too. A prompt that starts with a `/coordinator:` command gets no prompt reminder. Its reminder comes from the command hook, so `/coordinator:skip` and `/coordinator:once` get one while the mode is on. When `/coordinator:once` or `/coordinator:skip` comes with no request, the hook asks you to send it again. A resumed session starts with the mode off. `/coordinator:start` also deletes state files older than 30 days. The cleanup cannot tell an idle live session from a crashed one, so a session with no prompt for 30 days can lose its state, and its next prompt gets no reminder. If the hook cannot write or remove the state file, it shows a `coordinator:` warning, and tells the model that the mode did not change. If it cannot save a new tier while the mode is on, it shows the warning too, and the mode stays on with the previous tier.

## Commands

| Command | Effect |
| --- | --- |
| `/coordinator:start [low \| mid \| high] [PROMPT]` | Starts the coordinator for this session and sets the tier. `PROMPT` is handled in the mode. |
| `/coordinator:stop` | Stops the coordinator. Workers that are still running continue. The session checks each one when it finishes. |
| `/coordinator:once PROMPT` | Applies the mode to `PROMPT` and to the turns where its workers finish. The session state stays as it was. If the mode is already on, `PROMPT` is an ordinary request in the mode. |
| `/coordinator:skip PROMPT` | Does `PROMPT` in the foreground, with no new worker. If the mode is on, it stays on, and the next request uses it again. If the mode is off, `PROMPT` is an ordinary request and there is no footer. |

The tier sets the models a worker can use. `low` uses only Haiku. `mid` adds Sonnet. `high` adds Opus. With no tier, `/coordinator:start` uses `low` when the mode is off, and keeps the saved tier when the mode is on. With a tier and the mode on, it changes the tier. `/coordinator:once` uses the session tier, or `low` when the mode is off. The session state file holds the tier.

The tier is the first word after the command, and only the exact lowercase word counts. A request that starts with one of those words is ambiguous:

- `/coordinator:start high priority bug in the parser` sets the tier `high` and handles `priority bug in the parser` as the request.
- For a request that starts with `low`, `mid`, or `high`, write the tier first: `/coordinator:start low high priority bug in the parser`.
- The start confirmation and the `on (<tier>)` footer show the tier that the hook read, so a wrong reading shows in the first response. `/coordinator:start low` corrects it.
- `High`, `high-priority`, and `higher` are not tiers, so they stay in the request.

## Cost design

The plugin chooses the model, the effort, and the worker context to lower the cost of each finished task, not the price of each token. The rules are in [`references/coordinator.md`](references/coordinator.md) and [`references/brief-template.md`](references/brief-template.md). The reasons come from the [references](#references) below.

### Model by task class

| Model | Task class |
| --- | --- |
| `haiku` | Read, search, and summarize. Also a small code edit: the brief names one or two files, the `Read:` list has only those files, and the worker can run a check (a test, a build, or a command). |
| `sonnet` | Scoped work: a bug in a known area wider than two files, a feature against a specification, documentation, a task that crosses several rule documents, and each edit that misses one of the three small-edit conditions. |
| `opus` | Complex work: a bug with no known cause, a change across modules, a refactor or a migration that must keep the behavior, an architecture decision. |

The model guide (the first reference) says that a small model does well on work with an output that is easy to check, and that it is less suited to a long agentic loop. The guide keeps code edits off small models. The plugin makes one exception: a small edit goes to `haiku` when a check that the worker runs shows a mistake. When the tier does not have the model of the task class, the largest model of the tier does the work.

### Effort before model

When a result is not good enough, the model guide gives this order: give the model a way to verify its work, raise the effort one level, then move to the next model at a lower effort. The coordinator follows that order when a worker fails. Above `high`, one more effort level can cost as much as a larger model, so the effort ceiling is `high` in every tier. More effort does not give a model a skill that it lacks. So in `mid` and `high` the model carries the complexity: the effort is `medium` when the model matches the task class, and `high` when the tier caps the model below the class.

### Why Haiku alone can cost more

Haiku is the only model with a token price that depends on the prompt length. A prompt over 100K tokens bills at a higher rate. A worker in a large project with many documents reads much, so its prompt gets long. A model also recalls less from a context as that context fills. Both effects raise the cost of a finished task, although the price of a token stays low. The guide says to compare the cost of each finished task, not the list price. In `mid` and `high`, a task with much reading goes to `sonnet` or above. In `low`, the coordinator narrows the brief or splits the task into workers in sequence.

### Lean context

The brief gives paths, not file content. Its `Read:` list names the exact paths, and the worker loads them when it needs them. The worker returns a short summary, not a transcript. This keeps the coordinator's context for the decisions, and the verbose reading stays in the workers. A lean main context matters more as the main model gets larger.

### Simple harness

One worker owns one piece of work from investigation to verification, and the brief names a check that the worker runs before it reports the work as done. A worker starts from the brief and the files, not from the conversation. The coordinator compares the worker's claims with the files on disk, so the agent that judges the work is not the agent that did it. Each part of a harness is an assumption about what the model cannot do alone, so the plugin keeps few parts. A simple routing rule belongs in code: the hook reads the tier. The model choice inside the tier needs judgment, so the coordinator makes it.

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
claude plugin eval . --scaffold --allow-tools Bash Write Edit --model opus --ablation none --runs 1 --max-cost-usd 5
```

`make clean` is required. Cargo creates hard links in `hook/target/`, and `claude plugin eval` refuses a plugin that contains them. `--scaffold` copies each case's input files. `--model opus` runs the session under test on Opus. `--ablation none` removes the arm without the plugin, `--runs 1` runs each case once, and `--max-cost-usd 5` caps the cost. Do not run these cases on Fable. The judge stays on Haiku, which is the default of `--judge-model`. Add `--case NAME` to run one case. Results go to `evals/results/`, which is in `.gitignore`. A case passes when its `passRate` is `1`, and `aggregate-result.json` in the results folder has the numbers.

The cases with the tag `tier` test the model and the effort that the coordinator chooses in `mid` and `high`. Their workers run on Sonnet and Opus, so they cost more. To run only those cases:

```bash
make clean
claude plugin eval . --scaffold --allow-tools Bash Write Edit --model opus --tag tier --ablation none --max-cost-usd 3
```

`--ablation none` removes the arm that runs without the plugin. That arm doubles the runs, and it has no meaning for `/coordinator:start`. `--max-cost-usd 3` sets a cost cap for the run.

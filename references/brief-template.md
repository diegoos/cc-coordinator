# Worker brief

The brief is the worker's only channel. The worker starts without the conversation and cannot ask the user a question. Put in the brief the facts that change the work and that the worker cannot get from one read.

## Template

Fill each section that applies. Drop a section that does not. `Read:` always applies, because each file the worker loads makes its prompt longer.

```text
Objective: <one question to answer or one concrete deliverable>

Scope: <exact paths and modules that this worker owns>. Out of scope: <what not to touch, including the files of other active workers>. Work in the current workspace.

Read: <exact paths to read, and no other file>. Search with grep before you open a whole file. Read other documentation only when a listed file points to it.

Context: <errors, messages, branch, decisions already made, previous findings>.

Rules: <user and project rules that apply here, for example: a push stays with the user, commit only on request, reply language, preferred commands>.

Constraints: <read-only | can edit the scope area>. If a decision that changes the result is missing, stop with `status: blocked` and describe the question.

Split: <only when the work is parallel inside> You can split the work into your own subagents, with `model` <this worker's model, or a smaller one of the tier, by name> and effort `low` (easy task), `medium` (needs attention), or `high` (complex).

Done when: <verifiable criterion> and <verification to run: test, build, or command>.

Stop: after three consecutive failures with the same error, stop and report.

Return (short, no transcript and no verbose output):
- status: done | partial | blocked
- reason
- changed files
- verification evidence (command and short result)
- open items
```

**Done when:** each section that applies has a concrete fill, `Read:` lists exact paths, and Done when names a check the worker can run.

## Example

Bug fix that a failing test points at:

```text
Objective: make test_calc.py pass.
Scope: calc.py, test_calc.py. Out of scope: every other path. Work in the current workspace.
Read: calc.py, test_calc.py. Search with grep before you open a whole file. Read other documentation only when a listed file points to it.
Context: test_calc.py fails on add.
Constraints: can edit the scope area.
Done when: the failing test passes and the relevant suite stays green.
```

Model, effort, and the choice of siblings come from [`coordinator.md`](coordinator.md). Read it when this file is open without that one.

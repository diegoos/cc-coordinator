---
description: "Runs one request under coordinator rules until its worker result is reported. Session mode unchanged."
argument-hint: "PROMPT"
disable-model-invocation: true
---

# Coordinator once

Apply the coordinator to one request and to the turns where its workers finish. The session mode stays as it was.

## Inputs

- `PROMPT` (text, required): the text after the command.

## Steps

1. When `PROMPT` is empty, ask in one line for `/coordinator:once PROMPT` and stop. **Done when:** the reply is that line and this turn did no other work.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/coordinator.md` and follow it for `PROMPT`. The tier is the one in the hook reminder: the session tier when the mode is on, and `low` when the mode is off. Each response of the request ends with the once footer: the delegation response, the response that reports the result of the worker, or the answer when no worker runs. After that response, stop following that file unless the mode was already on. When the mode is already on, `PROMPT` is an ordinary request in the mode. **Done when:** this request has one selected path, each finished worker from it was checked against the disk, and a later request follows that file only when the mode was already on.

When the mode is off, the hook does not reinforce the once footer on later turns. A worker notification starts `UserPromptSubmit`, but with the mode off the hook has no state file and injects nothing. The once footer on the result response depends on this file and on the once reminder in the context.

That file is shared with `/coordinator:start` and with the session hook. Moving it breaks the command and the later-turn reminder.

When the file cannot be read, stop and report that path as the next thing to fix.

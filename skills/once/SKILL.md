---
description: "Runs one request in coordinator mode."
argument-hint: "PROMPT"
disable-model-invocation: true
---

# Coordinator once

Apply the coordinator to one request and to the turns where its workers finish. The session mode stays as it was.

## Inputs

- `PROMPT` (text, required): the text after the command.

## Steps

1. When `PROMPT` is empty, ask in one line for `/coordinator:once PROMPT` and stop. **Done when:** the reply is that line and this turn did no other work.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/coordinator.md` and follow it for `PROMPT` and for each turn where a worker from this request finishes. After the last of those turns, stop following that file unless the mode was already on. When the mode is already on, `PROMPT` is an ordinary request in the mode. **Done when:** this request has one selected path, each finished worker from it was checked against the disk, and a later request follows that file only when the mode was already on.

That file is shared with `/coordinator:start` and with the session hook. Moving it breaks the command and the later-turn reminder.

When the file cannot be read, stop and report that path as the next thing to fix.

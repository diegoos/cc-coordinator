---
description: "Starts the coordinator for this session."
argument-hint: "[PROMPT]"
disable-model-invocation: true
---

# Start coordinator

Turn this session into the coordinator until `/coordinator:stop`.

## Inputs

- `PROMPT` (text, optional): the text after the command.

## Steps

1. Read `${CLAUDE_PLUGIN_ROOT}/references/coordinator.md` and follow it until `/coordinator:stop`. **Done when:** that file is in the context.
2. Confirm in one line that the mode is on. When `PROMPT` is present, handle it with that file. **Done when:** the reply states that the mode is on, and a present prompt has one selected path.

That file is shared with `/coordinator:once` and with the session hook. Moving it breaks the command and the later-turn reminder.

When the file cannot be read, stop and report that path as the next thing to fix.

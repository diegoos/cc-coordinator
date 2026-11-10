---
description: "Turns on coordinator mode for this session until /coordinator:stop."
argument-hint: "[PROMPT]"
disable-model-invocation: true
---

# Start coordinator

Turn this session into the coordinator until `/coordinator:stop`.

## Inputs

- `PROMPT` (text, optional): the text after the command.

## Steps

1. Check the mode state that the hook reports. The mode is on, unless the hook reminder says the state did not change; then it is still off, and you handle this turn as an ordinary request. **Done when:** you know whether the mode is on or still off.
2. When the mode is on, read `${CLAUDE_PLUGIN_ROOT}/references/coordinator.md` and follow it until `/coordinator:stop`. **Done when:** that file is in the context, or the mode is still off.
3. Confirm that state in one line. When `PROMPT` is present and the mode is on, handle it with that file. **Done when:** the reply states that state, and a present prompt has one selected path when the mode is on.

That file is shared with `/coordinator:once` and with the session hook. Moving it breaks the command and the later-turn reminder.

When the file cannot be read, stop and report that path as the next thing to fix.

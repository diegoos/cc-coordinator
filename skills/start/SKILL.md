---
description: "Turns on coordinator mode for this session, at a model tier, until /coordinator:stop."
argument-hint: "[low|mid|high] [PROMPT]"
disable-model-invocation: true
---

# Start coordinator

Turn this session into the coordinator until `/coordinator:stop`.

## Inputs

- `TIER` (`low`, `mid`, or `high`, optional): the first word after the command, when it is exactly one of those words in lowercase. The hook reads it and states the tier in its reminder. Take the tier from that reminder, not from the arguments.
- `PROMPT` (text, optional): the text after the tier, or the text after the command when the first word is not a tier.

A first word that is a tier is never part of `PROMPT`. `/coordinator:start high priority bug in the parser` sets the tier `high`, and `PROMPT` is `priority bug in the parser`. To keep that word in the request, the user writes the tier first: `/coordinator:start low high priority bug in the parser`. Only the exact lowercase word counts, so `High`, `high-priority`, and `higher` stay in `PROMPT`. The confirmation line and the `on (<tier>)` footer show the tier that the hook read, so the user sees a wrong reading in the first response, and `/coordinator:start low` corrects it.

## Steps

1. Check the mode state and the tier that the hook reports. The mode is on, unless the hook reminder says the state did not change; then it is still off, and you handle this turn as an ordinary request. **Done when:** you know whether the mode is on or still off, and you know the tier when the mode is on.
2. When the mode is on, read `${CLAUDE_PLUGIN_ROOT}/references/coordinator.md` and follow it until `/coordinator:stop`. **Done when:** that file is in the context, or the mode is still off.
3. Confirm that state in one line, with the tier when the mode is on. When `PROMPT` is present and the mode is on, handle it with that file. **Done when:** the reply states that state, with the tier when the mode is on, and a present prompt has one selected path when the mode is on.

That file is shared with `/coordinator:once` and with the session hook. Moving it breaks the command and the later-turn reminder.

When the file cannot be read, stop and report that path as the next thing to fix.

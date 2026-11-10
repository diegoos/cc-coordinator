---
description: "Runs one request in the foreground, with no new worker. Session mode unchanged."
argument-hint: "PROMPT"
disable-model-invocation: true
---

# Coordinator skip

Do this request yourself in the foreground. The session mode stays as it was.

## Inputs

- `PROMPT` (text, required): the text after the command.

## Steps

1. When `PROMPT` is empty, ask in one line for `/coordinator:skip PROMPT` and stop. **Done when:** the reply is that line and this turn did no other work.
2. Do `PROMPT` yourself. A worker that is already running keeps its files until it delivers. **Done when:** the reply is that foreground work and this request sent no new `Agent` call.
3. Leave the session mode as it was. **Done when:** an on mode stays on for the next request, and an off mode stays off.

---
description: "Stops the coordinator for this session."
disable-model-invocation: true
---

# Stop coordinator

Leave coordinator mode. Later requests follow the other instructions, including subagents when those instructions call for them.

## Steps

1. Confirm in one line that the mode is off. **Done when:** the reply states that the mode is off and this turn did not delegate under the coordinator rules.
2. Let a worker that is still running finish. When it finishes, compare its claims with the files on disk and answer with the result, the evidence, and the open items. **Done when:** every worker that has finished has that answer, and every worker still running is named as still running.

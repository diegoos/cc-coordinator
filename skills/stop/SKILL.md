---
description: "Turns off coordinator mode for this session."
disable-model-invocation: true
---

# Stop coordinator

Leave coordinator mode. Later requests follow the session's normal instructions, not the coordinator rules.

## Steps

1. Confirm in one line the mode state that the hook reports. The mode is off, unless the hook reminder says the state did not change; then it is still on. **Done when:** the reply states that state, and this turn did not delegate under the coordinator rules.
2. Let a worker that is still running finish. When it finishes, compare its claims with the files on disk and answer with the result, the evidence, and the open items. **Done when:** every worker that has finished has that answer, and every worker still running is named as still running.

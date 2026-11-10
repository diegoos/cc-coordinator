# Security Policy

## Supported Versions

Only the latest release receives security updates.

## Scope

This plugin runs a Rust hook on every prompt. The hook reads JSON from stdin and writes one state file for each session. The repository also contains prebuilt hook binaries in `scripts/bin/`.

In scope:

- Path traversal or writes outside the state directory, for example through `session_id`.
- Code execution through input to the hook.
- A prebuilt binary in `scripts/bin/` that does not match the source.

Out of scope:

- Behavior of Claude Code itself. Report it to Anthropic.
- The text of the coordinator instructions. They are prompts, not code.

## Reporting a Vulnerability

Report vulnerabilities through GitHub. Do not open a public issue.

1. Open <https://github.com/diegoos/cc-coordinator/security>.
2. Select **Report a vulnerability**.
3. Describe the problem, the affected version, and the steps to reproduce it.

There is no fixed response time. The maintainer answers as soon as possible in the private advisory thread.

## Disclosure

Keep the report private. Do not disclose it publicly until a fix is released.

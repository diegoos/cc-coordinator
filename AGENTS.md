## Evals

The `tool_used` graders in `evals/*/graders/00-agent-call.md` match the `Read:` line of the worker brief with a regex. When you change the `Read:` format in `references/brief-template.md`, update those regexes and rerun the `tier` cases.

## Changelog

Record notable changes in the root `CHANGELOG.md` under `[Unreleased]`: one concise bullet in the matching Keep a Changelog section (Added, Changed, Deprecated, Removed, Fixed, Security). Omit empty sections. Bump a version only when the user explicitly asks.

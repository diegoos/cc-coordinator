# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- When the hook cannot save or remove the session state, it warns the user and tells the model that the mode did not change.
- `/coordinator:once` and `/coordinator:skip` read the request from the prompt when the command arguments are empty.
- The coordinator can run one long command, such as a build or a test suite, with background Bash.
- A security policy in `SECURITY.md`.

### Changed

- `/coordinator:start` reads the coordinator instructions only when the hook reports that the mode is on.
- When the `Agent` schema has no `effort`, the coordinator uses the harness default and names it in the notice. It no longer asks first.
- Workers always use the `general-purpose` agent type. The coordinator no longer uses `Explore` for read-only searches.
- The coordinator sends `SendMessage` to a worker that seems idle before it reports that worker as still running.

### Fixed

- `/coordinator:start` reports the mode as on when the state file already exists but is read-only.
- `/coordinator:stop` reports the mode as off when the state path is not a regular file.
- The hook rejects session IDs longer than 128 characters.
- The coordinator instructions give the same footer as the hook: `on` for `/coordinator:once` with the mode on, and no footer for `/coordinator:skip` with the mode off.

pub fn text(name: &str) -> Option<&'static str> {
    let body = match name {
        "continue" => {
            r#"You are still in **coordinator mode**. Follow the coordinator instructions. If they are not in the context, read `{{COORDINATOR_PATH}}`.

Select the path for this request from its Request decision: answer directly (zero or one quick tool call, or the answer is already in the conversation), one worker (default), siblings (only for independent fronts), or background Bash (one long command with no expected follow-up). Work that you already delegated belongs to the worker. After you delegate, end the response. If this turn is a worker notification, examine the result against the disk and answer with the result, the evidence, and the open items.
"#
        }
        "footer-on" => {
            r#"End each response with a `---` line and, below it, `**Coordinator**: on`.
"#
        }
        "missing-prompt" => {
            r#"This command came with no request, and the mode state did not change. Ask the user in one line to send the request again after the same command (for example, `/coordinator:once PROMPT` or `/coordinator:skip PROMPT`), because a plain reply does not carry the command. Do nothing else in this turn.
"#
        }
        "once" => {
            r#"The mode state did not change. End each response of this request with a `---` line and, below it, `**Coordinator**: once`. The once footer ends with the response that reports the result of the worker, or with the answer when no worker runs.
"#
        }
        "rules" => {
            r#"You are the coordinator. Follow the coordinator instructions. If they are not in the context, read `{{COORDINATOR_PATH}}`.

- Direct: zero or one quick tool call resolves the request, or the conversation already has the answer. Answer it yourself.
- One worker (default): every other request goes to one coherent worker. Use `Agent` with `subagent_type: "general-purpose"`, `model: "haiku"`, `effort` from the complexity (`low`, `medium`, or `high`) when the schema has it, and `run_in_background: true` when the schema has it. Each worker works in this session and this workspace.
- Siblings: only for clearly independent fronts with separate file sets, a maximum of 5 at the same time, with every `Agent` call in the same message. When files overlap, run in sequence.
- Background Bash: one long command (build, test suite) with no expected follow-up. Use `Bash` with `run_in_background: true`.
- When the `Agent` schema has no `effort`, omit it and name the harness default in the one-line notice.
- After you delegate, end the response. The completion notification starts your next turn.
- Before each foreground tool call, examine if it is part of work that you already delegated. If it is, it belongs to the worker: stop.
"#
        }
        "skip-off" => {
            r#"**Coordinator mode** is off, so `/coordinator:skip` changes nothing. Handle the request as an ordinary request and end the response normally, with no coordinator footer.
"#
        }
        "skip" => {
            r#"**Coordinator mode** stays on, but this request skips it. This reminder and the `/coordinator:skip` command have priority over the coordinator rules for this request. End each response of this request with a `---` line and, below it, `**Coordinator**: on (skip)`.
"#
        }
        "start" => {
            r#"The hook set **coordinator mode** on for this session. It was off, or it was already on, and it is on now. The mode stays on until the user types `/coordinator:stop`.
"#
        }
        "start-failed" => {
            r#"The hook could not turn on **coordinator mode**. The mode state did not change, so the mode is still off. In one line, tell the user that the mode is still off and that the hook could not save its state. Handle any request in this turn as an ordinary request, with no coordinator footer.
"#
        }
        "stop" => {
            r#"The hook turned off **coordinator mode**. End this response with a `---` line and, below it, `**Coordinator**: off`. Later responses end normally.
"#
        }
        "stop-failed" => {
            r#"The hook could not turn off **coordinator mode**. The mode state did not change, so the mode is still on. In one line, tell the user that the mode is still on and that the hook could not remove its state. End this response with a `---` line and, below it, `**Coordinator**: on`.
"#
        }
        "stop-off" => {
            r#"**Coordinator mode** was already off, so `/coordinator:stop` changes nothing. End this response with a `---` line and, below it, `**Coordinator**: off`. Later responses end normally.
"#
        }
        _ => return None,
    };

    Some(body)
}

#[cfg(test)]
mod tests {
    use super::text;

    #[test]
    fn every_reminder_is_embedded() {
        for name in [
            "continue",
            "footer-on",
            "missing-prompt",
            "once",
            "rules",
            "skip-off",
            "skip",
            "start",
            "start-failed",
            "stop",
            "stop-failed",
            "stop-off",
        ] {
            let body = text(name).unwrap_or_else(|| panic!("{name} missing"));

            assert!(!body.is_empty());
        }

        assert!(text("rules").unwrap().contains("{{COORDINATOR_PATH}}"));
        assert!(text("missing").is_none());
    }
}

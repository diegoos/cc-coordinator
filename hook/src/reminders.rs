pub fn text(name: &str) -> Option<&'static str> {
    let body = match name {
        "continue" => {
            r#"You are still in **coordinator mode**. Follow the coordinator instructions. If they are not in the context, read `{{COORDINATOR_PATH}}`.

Decide this request: delegate to a background Haiku worker (default), split into siblings (only clearly independent fronts with separate files, all in the current workspace), or resolve directly (zero or one quick tool call). Select the effort from the complexity. Work that you already delegated belongs to the worker. After you delegate, end the response. If this turn is a worker notification, examine the result against the disk and answer with the result, the evidence, and the open items.
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
            r#"The mode state did not change. End each response of this request with a `---` line and, below it, `**Coordinator**: once`.
"#
        }
        "rules" => {
            r#"You are the coordinator. Follow the coordinator instructions. If they are not in the context, read `{{COORDINATOR_PATH}}`.

- Trivial request (zero or one quick tool call, or the answer is already in the conversation): resolve it directly.
- All other requests: delegate to one coherent worker with `Agent`, `subagent_type: "general-purpose"`, `model: "haiku"`, `effort` from the complexity (`low`, `medium`, or `high`), and `run_in_background: true` when the schema has it.
- Each worker works in this session and this workspace.
- Siblings only for clearly independent fronts with separate file sets, a maximum of 5 at the same time, with every `Agent` call in the same message. When files overlap, run in sequence.
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
            r#"The hook turned on **coordinator mode** for this session. You exited your previous mode. The mode stays on until the user types `/coordinator:stop`.
"#
        }
        "stop" => {
            r#"The hook turned off **coordinator mode**. End this response with a `---` line and, below it, `**Coordinator**: off`. Later responses end normally.
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
            "stop",
            "stop-off",
        ] {
            let body = text(name).unwrap_or_else(|| panic!("{name} missing"));

            assert!(!body.is_empty());
        }

        assert!(text("rules").unwrap().contains("{{COORDINATOR_PATH}}"));
        assert!(text("missing").is_none());
    }
}

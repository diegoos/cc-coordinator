use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};

mod reminders;

const STALE_AFTER: Duration = Duration::from_secs(30 * 24 * 60 * 60);

#[derive(Deserialize)]
struct HookInput {
    session_id: String,
    #[serde(default)]
    command_name: String,
    #[serde(default)]
    command_args: String,
    #[serde(default)]
    prompt: String,
}

#[derive(Serialize)]
struct HookOutput {
    #[serde(rename = "hookSpecificOutput")]
    hook_specific_output: HookSpecificOutput,
}

#[derive(Serialize)]
struct HookSpecificOutput {
    #[serde(rename = "hookEventName")]
    hook_event_name: &'static str,
    #[serde(rename = "additionalContext")]
    additional_context: String,
}

fn main() {
    if let Err(message) = run() {
        warn(&message);
    }
}

fn run() -> Result<(), String> {
    let data = env::var("CLAUDE_PLUGIN_DATA").unwrap_or_default();

    if data.is_empty() {
        return Err("CLAUDE_PLUGIN_DATA not set; reminder skipped".to_string());
    }

    let input: HookInput =
        serde_json::from_reader(io::stdin()).map_err(|_| "invalid hook input".to_string())?;

    if !valid_session_id(&input.session_id) {
        return Err("invalid session_id".to_string());
    }

    let root = || plugin_root().ok_or_else(|| "plugin root not found".to_string());
    let state_file = PathBuf::from(data).join("sessions").join(&input.session_id);

    match env::args().nth(1).as_deref() {
        Some("expansion") => on_expansion(&root()?, &state_file, &input),
        Some("submit") => on_submit(&root()?, &state_file, &input),
        Some("session-end") => {
            let _ = fs::remove_file(&state_file);
        }
        Some(name) => return Err(format!("unknown event: {name}")),
        None => return Err("unknown event: ".to_string()),
    }

    Ok(())
}

enum Action {
    Start,
    Stop,
    Once,
    Skip,
}

fn coordinator_action(command_name: &str) -> Option<Action> {
    match command_name {
        "coordinator:start" => Some(Action::Start),
        "coordinator:stop" => Some(Action::Stop),
        "coordinator:once" => Some(Action::Once),
        "coordinator:skip" => Some(Action::Skip),
        _ => None,
    }
}

fn on_expansion(root: &Path, state_file: &Path, input: &HookInput) {
    let Some(action) = coordinator_action(&input.command_name) else {
        return;
    };

    if matches!(action, Action::Once | Action::Skip) && is_blank(&input.command_args) {
        let names: &[&str] = if state_file.is_file() {
            &["missing-prompt", "footer-on"]
        } else {
            &["missing-prompt"]
        };
        emit_reminders(root, "UserPromptExpansion", names);

        return;
    }

    match action {
        Action::Start => {
            remove_stale_states(state_file);
            touch(state_file);
            emit_reminders(
                root,
                "UserPromptExpansion",
                &["start", "footer-on", "rules"],
            );
        }
        Action::Stop => {
            let name = if state_file.is_file() {
                "stop"
            } else {
                "stop-off"
            };
            let _ = fs::remove_file(state_file);
            emit_reminders(root, "UserPromptExpansion", &[name]);
        }
        Action::Once => {
            let names: &[&str] = if state_file.is_file() {
                &["continue", "footer-on"]
            } else {
                &["once", "rules"]
            };
            emit_reminders(root, "UserPromptExpansion", names);
        }
        Action::Skip => {
            let names: &[&str] = if state_file.is_file() {
                &["skip"]
            } else {
                &["skip-off"]
            };
            emit_reminders(root, "UserPromptExpansion", names);
        }
    }
}

/// Deletes state files that a crashed session left behind.
fn remove_stale_states(state_file: &Path) {
    let Some(dir) = state_file.parent() else {
        return;
    };
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let age = entry
            .metadata()
            .and_then(|meta| meta.modified())
            .ok()
            .and_then(|modified| modified.elapsed().ok());

        if age.is_some_and(|age| age > STALE_AFTER) {
            let _ = fs::remove_file(entry.path());
        }
    }
}

/// Marks the session as alive, so the stale cleanup keeps its state file.
fn refresh(path: &Path) {
    if let Ok(file) = fs::OpenOptions::new().write(true).open(path) {
        let _ = file.set_modified(SystemTime::now());
    }
}

fn touch(path: &Path) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    let _ = fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(path);
}

fn on_submit(root: &Path, state_file: &Path, input: &HookInput) {
    if !state_file.is_file() {
        return;
    }

    refresh(state_file);

    if is_coordinator_prompt(&input.prompt) {
        return;
    }

    emit_reminders(root, "UserPromptSubmit", &["continue", "footer-on"]);
}

fn emit_reminders(root: &Path, event: &'static str, names: &[&str]) {
    let mut text = String::new();

    for name in names {
        let Some(part) = reminders::text(name) else {
            warn(&format!("reminder not found: {name}"));

            return;
        };
        text.push_str(part);
    }

    let coordinator = root.join("references/coordinator.md");
    let context = text.replace("{{COORDINATOR_PATH}}", &coordinator.display().to_string());
    let output = HookOutput {
        hook_specific_output: HookSpecificOutput {
            hook_event_name: event,
            additional_context: context,
        },
    };
    let Ok(json) = serde_json::to_string(&output) else {
        warn("failed to encode hook output");

        return;
    };
    let mut stdout = io::stdout().lock();
    let _ = writeln!(stdout, "{json}");
}

fn plugin_root() -> Option<PathBuf> {
    if let Ok(root) = env::var("CLAUDE_PLUGIN_ROOT") {
        if !root.is_empty() {
            return Some(PathBuf::from(root));
        }
    }

    let mut dir = env::current_exe().ok()?;
    dir.pop();

    loop {
        if dir.join(".claude-plugin").is_dir() {
            return Some(dir);
        }

        if !dir.pop() {
            return None;
        }
    }
}

fn valid_session_id(session_id: &str) -> bool {
    !session_id.is_empty()
        && session_id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

fn is_blank(value: &str) -> bool {
    value.chars().all(is_posix_space)
}

fn is_coordinator_prompt(prompt: &str) -> bool {
    let rest = prompt.trim_start_matches(is_posix_space);
    let Some(rest) = rest.strip_prefix("/coordinator") else {
        return false;
    };
    let Some(rest) = rest.strip_prefix(':') else {
        return false;
    };

    ["start", "stop", "once", "skip"].iter().any(|action| {
        let Some(after) = rest.strip_prefix(action) else {
            return false;
        };

        after.is_empty() || after.starts_with(is_posix_space)
    })
}

fn is_posix_space(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\r' | '\u{000B}' | '\u{000C}')
}

fn warn(message: &str) {
    eprintln!("coordinator-hook: {message}");
}

#[cfg(test)]
mod tests {
    use super::{is_blank, is_coordinator_prompt, valid_session_id};

    #[test]
    fn rejects_a_session_id_that_escapes_the_directory() {
        assert!(!valid_session_id("../escape"));
        assert!(!valid_session_id(""));
        assert!(valid_session_id("s1"));
        assert!(valid_session_id("A_b-9"));
    }

    #[test]
    fn only_a_colon_after_coordinator_makes_a_command() {
        assert!(is_coordinator_prompt("  /coordinator:skip"));
        assert!(is_coordinator_prompt("/coordinator:stop"));
        assert!(!is_coordinator_prompt("/coordinator stop"));
        assert!(!is_coordinator_prompt("/coordinator:startle"));
        assert!(!is_coordinator_prompt("/coordinatoring stop"));
        assert!(!is_coordinator_prompt("/coordinator  start"));
    }

    #[test]
    fn args_of_only_space_are_blank() {
        assert!(is_blank(""));
        assert!(is_blank("   "));
        assert!(is_blank(" \n\t"));
        assert!(!is_blank("fix it"));
        assert!(!is_blank("say \"hi\"\nnext"));
    }
}

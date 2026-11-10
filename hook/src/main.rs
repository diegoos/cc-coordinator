use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};

mod reminders;

const STALE_AFTER: Duration = Duration::from_secs(30 * 24 * 60 * 60);
const MAX_SESSION_ID_LEN: usize = 128;

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
    #[serde(rename = "systemMessage", skip_serializing_if = "Option::is_none")]
    system_message: Option<String>,
    #[serde(rename = "hookSpecificOutput", skip_serializing_if = "Option::is_none")]
    hook_specific_output: Option<HookSpecificOutput>,
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
            remove_state(&state_file).map_err(|err| format!("could not remove state: {err}"))?;
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

    if matches!(action, Action::Once | Action::Skip) && is_blank(request_args(input)) {
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

            if state_file.is_file() {
                refresh(state_file);
            } else if let Err(err) = touch(state_file) {
                emit_failure(
                    root,
                    "start-failed",
                    &format!("could not turn on coordinator mode: {err}"),
                );

                return;
            }

            emit_reminders(
                root,
                "UserPromptExpansion",
                &["start", "footer-on", "rules"],
            );
        }
        Action::Stop if !state_file.is_file() => {
            emit_reminders(root, "UserPromptExpansion", &["stop-off"]);
        }
        Action::Stop => match remove_state(state_file) {
            Ok(true) => emit_reminders(root, "UserPromptExpansion", &["stop"]),
            Ok(false) => emit_reminders(root, "UserPromptExpansion", &["stop-off"]),
            Err(err) => emit_failure(
                root,
                "stop-failed",
                &format!("could not turn off coordinator mode: {err}"),
            ),
        },
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

fn touch(path: &Path) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(path)?;

    Ok(())
}

/// Returns false when there was no state file.
fn remove_state(path: &Path) -> io::Result<bool> {
    match fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(err),
    }
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
    if let Some(context) = render(root, names) {
        emit(event, None, Some(context));
    }
}

/// Warns the user and tells the model that the state did not change.
fn emit_failure(root: &Path, name: &str, message: &str) {
    let context = render(root, &[name]);

    emit(
        "UserPromptExpansion",
        Some(format!("coordinator: {message}")),
        context,
    );
}

fn render(root: &Path, names: &[&str]) -> Option<String> {
    let mut text = String::new();

    for name in names {
        let Some(part) = reminders::text(name) else {
            warn(&format!("reminder not found: {name}"));

            return None;
        };
        text.push_str(part);
    }

    let coordinator = root.join("references/coordinator.md");

    Some(text.replace("{{COORDINATOR_PATH}}", &coordinator.display().to_string()))
}

fn emit(event: &'static str, system_message: Option<String>, context: Option<String>) {
    let output = HookOutput {
        system_message,
        hook_specific_output: context.map(|additional_context| HookSpecificOutput {
            hook_event_name: event,
            additional_context,
        }),
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
        && session_id.len() <= MAX_SESSION_ID_LEN
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

/// Uses command_args. When it is empty, takes the text after the command name in prompt.
fn request_args(input: &HookInput) -> &str {
    if !is_blank(&input.command_args) {
        return &input.command_args;
    }

    let command = format!("/{}", input.command_name);

    match input
        .prompt
        .trim_start_matches(is_posix_space)
        .strip_prefix(&command)
    {
        Some(rest) if rest.is_empty() || rest.starts_with(is_posix_space) => rest,
        _ => "",
    }
}

fn warn(message: &str) {
    eprintln!("coordinator-hook: {message}");
}

#[cfg(test)]
mod tests {
    use super::{
        is_blank, is_coordinator_prompt, remove_state, request_args, touch, valid_session_id,
        HookInput,
    };
    use std::{env, fs, path::PathBuf};

    fn temp_dir(name: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!("coordinator-hook-{}-{name}", std::process::id()));

        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        dir
    }

    #[test]
    fn rejects_a_session_id_that_escapes_the_directory() {
        assert!(!valid_session_id("../escape"));
        assert!(!valid_session_id(""));
        assert!(valid_session_id("s1"));
        assert!(valid_session_id("A_b-9"));
    }

    #[test]
    fn caps_a_session_id_at_the_file_name_limit() {
        assert!(valid_session_id(&"a".repeat(128)));
        assert!(!valid_session_id(&"a".repeat(129)));
    }

    #[test]
    fn touch_reports_a_state_path_it_cannot_create() {
        let dir = temp_dir("touch");
        let blocker = dir.join("sessions");

        fs::write(&blocker, "").unwrap();

        assert!(touch(&blocker.join("s1")).is_err());
        assert!(touch(&dir.join("s2")).is_ok());

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn remove_state_reports_a_state_it_cannot_remove() {
        let dir = temp_dir("remove");
        let state = dir.join("s1");

        fs::create_dir(&state).unwrap();

        assert!(remove_state(&state).is_err());

        fs::remove_dir(&state).unwrap();
        fs::write(&state, "").unwrap();

        assert!(remove_state(&state).unwrap());
        assert!(!remove_state(&state).unwrap());

        fs::remove_dir_all(&dir).unwrap();
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

    #[test]
    fn request_args_fall_back_to_the_prompt_when_command_args_is_empty() {
        let input = |command_args: &str, prompt: &str| HookInput {
            session_id: "s1".to_string(),
            command_name: "coordinator:once".to_string(),
            command_args: command_args.to_string(),
            prompt: prompt.to_string(),
        };

        assert_eq!(
            request_args(&input("fix it", "/coordinator:once fix it")),
            "fix it"
        );
        assert_eq!(
            request_args(&input("", "/coordinator:once fix it")).trim(),
            "fix it"
        );
        assert!(is_blank(request_args(&input("", "/coordinator:once"))));
        assert!(is_blank(request_args(&input("", "/coordinator:oncex fix"))));
        assert!(is_blank(request_args(&input("", ""))));
    }
}

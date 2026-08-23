# Alerto

<p align="center">
  <img src="alerto/Assets.xcassets/AppIcon.imageset/AppIcon-1024.png" alt="Alerto Icon" width="128" height="128">
</p>

A macOS menu bar application that displays intelligent notifications from Claude Code, Codex, Pi, Oh My Pi, and OpenCode without interrupting your workflow.

## Features

- **Claude Code Integration**: Receives notifications from Claude Code hooks (stop, notification, permission request, session end, etc.)
- **Codex Integration**: Receives `Stop`, `PermissionRequest`, and `SubagentStop` lifecycle notifications
- **Pi, OMP, and OpenCode Integrations**: Installs managed extensions/plugins for completion, approval, question, and error notifications
- **Remaining Usage**: Shows the Claude Code and Codex Session/Weekly quota still available from your existing CLI sign-ins
- **Menu Bar Interface**: Accessible through system menu bar with minimal UI footprint
- **Customizable Settings**: Configure notification sounds and display preferences
- **Notification History**: View and manage recent notifications
- **Non-intrusive Design**: Runs as a menu bar utility (LSUIElement = true)

## Installation

Download the latest release from the [Releases page](https://github.com/thongntit/alerto/releases) and install the DMG.

## Usage

### HTTP API

Alerto exposes a local HTTP server on port 7531 for receiving notifications:

```bash
# POST notification
curl -X POST http://127.0.0.1:7531/notify \
  -H "Content-Type: application/json" \
  -d '{"hook_event_name": "Stop", "last_assistant_message": "Task completed"}'

# Health check
curl http://127.0.0.1:7531/health
```

### Coding Agent Integrations

Open Alerto's **Settings > Integrations** tab and enable the coding agents you use. Each agent card has a master install/remove toggle plus expandable event controls. Alerto detects default and environment-configured agent directories and lets you choose a custom directory before enabling an integration.

| Agent | Alerto-managed location | Default events |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | Completion, attention, session end |
| Codex | `~/.codex/hooks.json` | Completion, permission, subagent completion |
| Pi | `~/.pi/agent/extensions/alerto-agent-state.ts` | Completion |
| Oh My Pi | `~/.omp/agent/extensions/alerto-agent-state.ts` | Completion, permission, question, error |
| OpenCode | `~/.config/opencode/plugins/alerto-agent-state.js` | Completion, permission, question, error |

The Pi, OMP, and OpenCode approach follows the managed extension/plugin pattern used by [Herdr](https://herdr.dev). Alerto marks and versions its own files, refuses to overwrite foreign files, and preserves every unrelated hook, extension, plugin, and setting. Integrations send generic lifecycle messages only and never read provider credentials, full prompts, or assistant responses.

For custom locations, Alerto respects `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `PI_CODING_AGENT_DIR`, and `OPENCODE_CONFIG_DIR` when those variables are available to the app process.

### Codex Hook Activation

Alerto manages Codex command handlers in `~/.codex/hooks.json` and preserves unrelated hooks and fields.

Installed hooks forward Codex's stdin JSON payload to Alerto and identify the request with `source=codex`. Alerto does not modify `~/.codex/config.toml` or Codex's completion-only `notify` setting.

After installing or changing hooks:

1. Start a new Codex session.
2. Run `/hooks`.
3. Review and trust the installed Alerto hooks.

Codex skips new or changed command hooks until they are trusted.

See the official [Codex Hooks](https://developers.openai.com/codex/hooks) and [Advanced Configuration](https://developers.openai.com/codex/config-advanced) documentation for the lifecycle hook and configuration model.

### Remaining Claude Code and Codex Usage

Alerto can show your remaining Claude Code and Codex Session/Weekly quotas at the top of its menu without requiring OpenUsage. It reads Claude Code's OAuth login from `~/.claude/.credentials.json` (or `CLAUDE_CONFIG_DIR`) and does not request access to Claude Code's macOS Keychain item. It reads the Codex CLI login from `~/.codex/auth.json` (respecting `CODEX_HOME`). Quota checks never invoke a model or start an agent turn. If an OAuth session must be refreshed, Alerto writes the refreshed tokens back to the same credential source.

The app checks at launch and every five minutes. The manual refresh button is coalesced for 30 seconds to avoid accidental repeated requests. If the Claude credential file is unavailable, Alerto reports that Claude Code is not signed in instead of showing a Keychain authorization prompt.

## Configuration

The application supports several configurable options available in the Settings panel:

- Enable coding-agent integrations and select their lifecycle events
- Enable/disable notification sounds
- Select from system notification sounds
- View notification history
- Clear all notifications

## System Requirements

- macOS 15.0+
- Xcode 15.0+
- Swift 5.9+

## License

This project is licensed under the MIT License.

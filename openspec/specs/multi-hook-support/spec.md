## ADDED Requirements

### Requirement: Support Notification hook
The system SHALL handle Claude Code's Notification hook event and display appropriate notifications.

#### Scenario: Notification hook triggered
- **WHEN** Claude Code sends a notification (waiting for input, permission needed)
- **THEN** system displays notification with the message content from the hook payload

### Requirement: Support Stop hook
The system SHALL handle Claude Code's Stop hook event when the main agent finishes responding.

#### Scenario: Stop hook triggered
- **WHEN** Claude Code finishes responding (stop_hook_active is true)
- **THEN** system displays completion notification

### Requirement: Support SessionEnd hook
The system SHALL handle Claude Code's SessionEnd hook event when a session ends.

#### Scenario: SessionEnd hook triggered
- **WHEN** Claude Code session ends (exit, sigint, or error)
- **THEN** system displays session ended notification

### Requirement: Hook type detection
The system SHALL determine which hook triggered the notification based on payload or request metadata.

#### Scenario: Hook type in payload
- **WHEN** payload contains hook_type or event field
- **THEN** system uses that to determine notification behavior

#### Scenario: No hook type in payload
- **WHEN** payload lacks hook type information
- **THEN** system uses default behavior based on notification type

### Requirement: Support Codex lifecycle hooks
The system SHALL handle Codex `Stop`, `PermissionRequest`, and `SubagentStop` events.

#### Scenario: Codex main turn finishes
- **WHEN** Codex sends a `Stop` payload
- **THEN** system displays a Codex completion notification

#### Scenario: Codex needs approval
- **WHEN** Codex sends a `PermissionRequest` payload
- **THEN** system displays a Codex permission notification

#### Scenario: Codex subagent finishes
- **WHEN** Codex sends a `SubagentStop` payload
- **THEN** system displays a Codex subagent completion notification

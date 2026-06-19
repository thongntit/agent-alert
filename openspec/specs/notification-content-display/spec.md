## ADDED Requirements

### Requirement: Display hook message in notification
The system SHALL display the actual message content from Claude Code hooks in notifications instead of hardcoded messages, for both overlay and system-notification presentation modes.

#### Scenario: Notification with message content
- **WHEN** hook provides message content
- **THEN** notification displays the actual message text in whichever presentation mode is active

#### Scenario: Message truncation
- **WHEN** message content exceeds 200 characters
- **THEN** system truncates with "..." in the visible body and retains the full text for overlay expansion or notification history

### Requirement: Show hook type context
The system SHALL display the hook event type as context in the notification, in both overlay and system-notification modes.

#### Scenario: Notification hook
- **WHEN** Notification hook triggers
- **THEN** notification shows "Claude needs your input" as title with message as body, regardless of whether the active mode is overlay or system

#### Scenario: Stop hook
- **WHEN** Stop hook triggers
- **THEN** notification shows "Claude finished" as title in either presentation mode

### Requirement: Rich notification content
The system SHALL support notification titles, bodies, and subtitles for better context, mapped consistently into both the overlay view and the `UNMutableNotificationContent` used in system mode.

#### Scenario: Full notification context
- **WHEN** notification has title, body, and subtitle
- **THEN** all three are populated on the overlay view and on `UNMutableNotificationContent.title`, `.subtitle`, and `.body` respectively when in system mode

#### Scenario: Minimal notification
- **WHEN** only message is available
- **THEN** the system uses the same sensible defaults for missing title/subtitle in both presentation modes

### Requirement: Source-aware hook context
The system SHALL map hook context titles according to the notification source.

#### Scenario: Existing Claude notification
- **WHEN** a Claude Code hook notification is displayed
- **THEN** its existing Claude-specific title SHALL remain unchanged

#### Scenario: Codex lifecycle notification
- **WHEN** a Codex `Stop`, `PermissionRequest`, or `SubagentStop` notification is displayed
- **THEN** the title SHALL identify the corresponding Codex lifecycle event

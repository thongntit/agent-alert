## ADDED Requirements

### Requirement: Codex Detection

The system SHALL detect Codex through the default user-level `~/.codex` directory.

#### Scenario: Codex is installed
- **WHEN** the user opens Alerto integration settings
- **THEN** the system SHALL show Codex as detected when `~/.codex` exists

### Requirement: User-Level Codex Hook Ownership

The system SHALL manage Alerto handlers in `~/.codex/hooks.json` without modifying `~/.codex/config.toml` or Codex's `notify` setting.

#### Scenario: Install lifecycle hooks
- **WHEN** the user installs Codex hooks
- **THEN** the system SHALL install separate matcher groups for `Stop`, `PermissionRequest`, and `SubagentStop`
- **AND** each matcher group SHALL contain one Alerto command handler
- **AND** each command SHALL contain a stable Alerto marker

#### Scenario: Preserve existing configuration
- **WHEN** Alerto updates or removes Codex hooks
- **THEN** unrelated events, matcher groups, handlers, and unknown top-level fields SHALL remain unchanged

#### Scenario: Invalid existing configuration
- **WHEN** `hooks.json` contains malformed JSON or an invalid hook structure
- **THEN** installation or removal SHALL fail without modifying the file

#### Scenario: Atomic configuration update
- **WHEN** Alerto writes `hooks.json`
- **THEN** the complete configuration SHALL be replaced atomically

### Requirement: Non-Blocking Codex Hook Commands

The system SHALL forward Codex hook stdin payloads to Alerto without changing Codex lifecycle behavior.

#### Scenario: Hook notification delivery
- **WHEN** an installed Alerto command handler runs
- **THEN** it SHALL POST stdin JSON to `/notify`
- **AND** identify the request with `source=codex` and the event notification type
- **AND** use a short HTTP timeout
- **AND** always emit `{}` on stdout even when delivery fails

### Requirement: Codex Hook Trust Guidance

The system SHALL explain Codex's command-hook trust requirement after installation.

#### Scenario: Hooks installed
- **WHEN** a user installs a new or changed Codex hook
- **THEN** Alerto SHALL instruct the user to start a new Codex session, run `/hooks`, and trust the installed hooks

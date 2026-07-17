# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

**Alerto** is a macOS menu bar application that displays intelligent notifications from Codex without interrupting your workflow. It runs as a menu bar utility (LSUIElement = true) with no dock icon.

## Commands

### Build and Run

```bash
# Build the project
xcodebuild -project alerto.xcodeproj -scheme Alerto -configuration Release build

# Build with derived data
xcodebuild -project alerto.xcodeproj -scheme Alerto -configuration Release -derivedDataPath build build

# Open in Xcode
open alerto.xcodeproj
```

### HTTP API Testing

The app runs a local HTTP server on port 7531:

```bash
# POST notification (Codex hook format)
curl -X POST http://127.0.0.1:7531/notify \
  -H "Content-Type: application/json" \
  -d '{"hook_event_name": "Stop", "last_assistant_message": "Task completed"}'

# POST notification (legacy format)
curl -X POST http://127.0.0.1:7531/notify \
  -H "Content-Type: application/json" \
  -d '{"source": "Codex", "type": "complete", "message": "Task done"}'

# Health check
curl http://127.0.0.1:7531/health
```

## Architecture

### Entry Point
- **AlertoApp.swift**: SwiftUI App with `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Initializes managers on launch.

### Core Services (Singletons)
- **NotificationManager**: Central hub for notification state, handles display, sound playback, and manages notification queue/history.
- **HTTPServerManager**: Local HTTP server (Hummingbird) for receiving POST notifications on port 7531.

### Models
- **Notification.swift**: Defines `NotificationSource` (Codex only), `NotificationType` (complete, permission, question, idle, attention, error, start, stop), `HookType` (notification, stop, subagentStop, sessionEnd, userPromptSubmit, permissionRequest), and `AgenticNotification` struct.

### Views
- **MenuBarView**: SwiftUI menu bar interface.
- **SettingsView**: Configuration panel for sound preferences and notification history.
- **NotificationOverlayView**: Floating overlay for incoming notifications.

### Managers
- **NotificationOverlayManager**: Manages overlay window display.
- **SettingsWindowManager**: Manages settings window lifecycle.

## HTTP API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/notify` | GET/POST | Send notification |
| `/health` | GET | Server health check with uptime |

### HTTP Payload Formats

**Codex Hook Payload:**
```json
{
  "hook_event_name": "Stop",
  "last_assistant_message": "Task completed",
  "notification": { "message": "Important update" }
}
```

## System Requirements

- macOS 15.0+
- Xcode 15.0+
- Swift 5.9+

## Dependencies

- **Hummingbird**: Swift HTTP server framework
- **ServiceLifecycle**: For graceful HTTP server shutdown

## CI/CD

GitHub Actions workflow (`.github/workflows/release.yml`) builds a DMG on GitHub releases using the `Alerto` scheme.

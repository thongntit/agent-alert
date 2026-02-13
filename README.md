# Agent Alert

A macOS menu bar application that displays intelligent notifications from AI agents and tools without interrupting your workflow.

## Features

- **Smart Focus Detection**: Detects when you're typing and queues notifications to avoid interruptions
- **URL Scheme Integration**: Receive notifications from external applications via custom URL scheme
- **Menu Bar Interface**: Accessible through system menu bar with minimal UI footprint
- **Customizable Settings**: Configure notification sounds and display preferences
- **Notification History**: View and manage recent notifications

## Installation

1. Clone the repository
2. Open `agent-alert.xcodeproj` in Xcode
3. Build and run the application

## Usage

### URL Scheme Integration

Send notifications to Agent Alert using the custom URL scheme:

```
agent-alert://notify?source=claude&type=attention&message=Your notification here
```

#### Parameters:
- `source`: Notification source (claude, cursor, github, etc.)
- `type`: Notification type (attention, warning, error, success)
- `message`: The notification message text

### Test Notification

Trigger a test notification:
```
agent-alert://test
```

## Architecture

### Core Components

- **NotificationManager**: Central management of notifications and queuing logic
- **FocusMonitor**: Monitors keyboard activity to detect user typing state
- **URLSchemeHandler**: Processes incoming notification requests via URL scheme
- **NotificationOverlayManager**: Manages the display of notification overlays

### Key Features

- **Intelligent Queuing**: Notifications are queued when user is typing and displayed when idle
- **Non-intrusive Design**: Runs as a menu bar utility (LSUIElement = true)
- **Sound Alerts**: Optional audio notifications with customizable sound selection

## Configuration

The application supports several configurable options available in the Settings panel:

- Enable/disable notification sounds
- Select from system notification sounds
- View notification history
- Clear all notifications

## System Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## License

This project is licensed under the MIT License.
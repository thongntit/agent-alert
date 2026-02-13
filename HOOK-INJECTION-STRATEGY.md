# Hook Injection Strategy

## Overview

This document describes how the `@z_ai/coding-helper` package detects and injects configurations into Claude Code and OpenCode, and how the same strategy can be applied to manage hooks.

---

## Current Detection & Injection Mechanism

### MCP Server Detection

The package already has the ability to detect if a **specific MCP server** is installed:

#### Claude Code (`~/.claude.json`)

```js
isMCPInstalled(mcpId) {
  const config = this.getMCPConfig();
  if (!config.mcpServers) return false;
  return mcpId in config.mcpServers;
}
```

#### OpenCode (`~/.config/opencode/opencode.json`)

```js
isMCPInstalled(mcpId) {
  const config = this.getConfig();
  if (!config.mcp) return false;
  return mcpId in config.mcp;
}
```

### Configuration Paths

| Tool | Config File | MCP Key | Settings Key |
|------|-------------|---------|--------------|
| Claude Code | `~/.claude.json` | `mcpServers` | - |
| Claude Code Settings | `~/.claude/settings.json` | - | `env`, `hooks` |
| OpenCode | `~/.config/opencode/opencode.json` | `mcp` | `provider`, `hooks` |

---

## Applying the Same Strategy for Hooks

### Why Hooks Need Similar Detection

Hooks can be configured in multiple locations:
- `~/.claude/settings.json` (global)
- `.claude/settings.json` (project)
- Plugin `hooks/hooks.json`
- Skill/agent frontmatter

To avoid conflicts and ensure idempotent installations, we need to:
1. **Detect** if a specific hook is already installed
2. **Install/Update** hooks without duplicating
3. **Uninstall** hooks cleanly

### Proposed Implementation

#### 1. Hook Detection Methods

```js
// In claude-code-manager.js

/**
 * Check if a specific hook is installed
 * @param {string} eventName - Hook event (e.g., 'PostToolUse', 'PreToolUse')
 * @param {string} hookId - Unique identifier for the hook
 */
isHookInstalled(eventName, hookId) {
  const settings = this.getSettings();
  if (!settings.hooks?.[eventName]) return false;
  
  return settings.hooks[eventName].some(
    hookConfig => hookConfig.id === hookId
  );
}

/**
 * Get all hooks for a specific event
 */
getHooksForEvent(eventName) {
  const settings = this.getSettings();
  return settings.hooks?.[eventName] || [];
}
```

#### 2. Hook Installation with Idempotency

```js
/**
 * Install a hook (update if exists, add if not)
 * @param {string} eventName - Hook event name
 * @param {object} hookConfig - Hook configuration with unique id
 */
installHook(eventName, hookConfig) {
  const settings = this.getSettings();
  
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks[eventName]) settings.hooks[eventName] = [];
  
  // Remove existing hook with same id (idempotent)
  settings.hooks[eventName] = settings.hooks[eventName].filter(
    h => h.id !== hookConfig.id
  );
  
  // Add new hook
  settings.hooks[eventName].push(hookConfig);
  
  this.saveSettings(settings);
}
```

#### 3. Hook Uninstallation

```js
/**
 * Uninstall a hook by id
 */
uninstallHook(eventName, hookId) {
  const settings = this.getSettings();
  
  if (!settings.hooks?.[eventName]) return;
  
  settings.hooks[eventName] = settings.hooks[eventName].filter(
    h => h.id !== hookId
  );
  
  // Clean up empty arrays
  if (settings.hooks[eventName].length === 0) {
    delete settings.hooks[eventName];
  }
  if (Object.keys(settings.hooks).length === 0) {
    delete settings.hooks;
  }
  
  this.saveSettings(settings);
}
```

### Hook Configuration Schema with ID

To enable detection, each hook should have a unique `id` field:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "id": "zai-format-on-edit",
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "npx prettier --write $FILE_PATH"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "id": "zai-block-dangerous-commands",
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/validate-command.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Recommended Hook IDs Convention

Use namespaced IDs to avoid conflicts:

| Pattern | Example |
|---------|---------|
| `{package}:{event}:{action}` | `zai:posttool:format` |
| `{org}/{plugin}:{feature}` | `zai/glm-plan:block-drop-table` |

---

## OpenCode Hook Support

Apply the same pattern to `opencode-manager.js`:

```js
// OpenCode uses the same settings.json path for hooks
// ~/.config/opencode/opencode.json

isHookInstalled(eventName, hookId) {
  const config = this.getConfig();
  if (!config.hooks?.[eventName]) return false;
  return config.hooks[eventName].some(h => h.id === hookId);
}

installHook(eventName, hookConfig) {
  const config = this.getConfig();
  
  if (!config.hooks) config.hooks = {};
  if (!config.hooks[eventName]) config.hooks[eventName] = [];
  
  config.hooks[eventName] = config.hooks[eventName].filter(
    h => h.id !== hookConfig.id
  );
  config.hooks[eventName].push(hookConfig);
  
  this.saveConfig(config);
}
```

---

## Summary

| Feature | MCP Detection | Hook Detection (Proposed) |
|---------|---------------|---------------------------|
| Check specific item | `mcpId in mcpServers` | `hookConfig.id in hooks[event]` |
| Get all items | `Object.keys(mcpServers)` | `settings.hooks[event]` |
| Install | `mcpServers[id] = config` | Filter by id + push |
| Uninstall | `delete mcpServers[id]` | Filter out by id |

The key insight: **use unique IDs for hooks** (similar to MCP server IDs) to enable detection, idempotent installation, and clean uninstallation.

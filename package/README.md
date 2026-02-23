# Coding Tool Helper (chelper)

> A CLI helper for GLM Coding Plan Users to manage coding tools like claude-code.

Currently supported coding tools:

- Claude Code
- OpenCode
- Crush
- Factory Droid

## Features

- **Interactive wizard** – Friendly onboarding guidance on first launch
- **GLM Coding Plan integration** – Supports both Global and China plans
- **Tool management** – Automatically detects, installs, and configures CLI tools
- **MCP configuration** – Easily manage MCP services
- **Local storage** – All settings are stored securely on your machine
- **Internationalization support** – Chinese and English bilingual interface

## Quick Start

Prerequisite: make sure Node.js 18 or later is installed.

### Install and launch

#### Option 1

```shell
## Run directly with npx
npx @z_ai/coding-helper
```

#### Option 2

```shell
## Install @z_ai/coding-helper globally first
npm install -g @z_ai/coding-helper
## Then run chelper
chelper
```

### Complete the wizard

> Once you enter the wizard UI, use the Up/Down arrow keys to navigate and press Enter to confirm each action, following the guided initialization flow.

The wizard will help you complete:
1. Selecting the UI language
2. Choosing the coding plan
3. Entering your API key
4. Selecting the tools to manage
5. Automatically installing tools (if needed)
6. Entering the tool management menu
7. Loading the coding plan into the tools
8. Managing MCP services (optional)

## Command list

> Besides the interactive wizard, chelper also supports executing every feature directly through CLI arguments:

```bash
# Show help
chelper -h
chelper --help

# Show version
chelper -v
chelper --version

# Run the initialization wizard
chelper init

# Language management
chelper lang show              # Display the current language
chelper lang set zh_CN         # Switch to Chinese
chelper lang set en_US         # Switch to English
chelper lang --help            # Show help for language commands

# API key management
chelper auth                   # Interactively set the key
chelper auth glm_coding_plan_global <token>    # Choose the Global plan and set the key directly
chelper auth glm_coding_plan_china <token>     # Choose the China plan and set the key directly
chelper auth revoke            # Delete the saved key
chelper auth reload claude     # Load the latest plan info into the Claude Code tool
chelper auth --help            # Show help for auth commands

# Health check
chelper doctor                 # Inspect system configuration and tool status
```

## Configuration file

The configuration file is stored at `~/.chelper/config.yaml`:

```yaml
lang: zh_CN                    # UI language
plan: glm_coding_plan_global   # Plan type: glm_coding_plan_global or glm_coding_plan_china
api_key: your-api-key-here     # API key
```
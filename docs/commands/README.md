# Grim Commands Reference

Complete reference for all Grim editor commands.

## Command Categories

- [Editor Commands](editor.md) - Buffer, window, and file operations
- [Motion Commands](../motions/README.md) - Cursor movement and navigation
- [AI Commands](ai.md) - AI-powered completions and assistance
- [Git Commands](git.md) - Version control integration
- [LSP Commands](lsp.md) - Language Server Protocol features
- [Plugin Commands](plugins.md) - Plugin management
- [Collaboration Commands](collaboration.md) - Real-time collaborative editing

## Quick Reference

### Essential Commands

| Command | Description | Mode |
|---------|-------------|------|
| `:w` | Write buffer to file | Command |
| `:q` | Quit editor | Command |
| `:wq` | Write and quit | Command |
| `:e <file>` | Edit file | Command |
| `:help` | Show help | Command |

### AI Commands (via thanos.grim)

| Command | Description | Keybind |
|---------|-------------|---------|
| `:ThanosComplete` | AI code completion | `<leader>ak` |
| `:ThanosChat` | Open AI chat | `<leader>ac` |
| `:ThanosAsk <msg>` | Ask AI question | - |
| `:ThanosSwitch <provider>` | Switch provider | `<leader>ap` |
| `:ThanosProviders` | List providers | - |
| `:ThanosStats` | Show statistics | `<leader>as` |
| `:ThanosExplain` | Explain code | `<leader>ae` |
| `:ThanosReview` | Review code | `<leader>ar` |
| `:ThanosCommit` | Generate commit | - |

### Collaboration Commands

| Command | Description |
|---------|-------------|
| `:collab start [port]` | Start collaboration server (default: 8080) |
| `:collab join <url>` | Join collaboration session |
| `:collab stop` | Stop collaboration |
| `:collab users` | Show connected users |

## Command Syntax

Commands start with `:` in normal mode. Press `<Esc>` to cancel command input.

### Command Arguments

- `<required>` - Required argument
- `[optional]` - Optional argument
- `<choice1|choice2>` - Choose one option

### Examples

```vim
:e src/main.zig           " Open file
:w                        " Save current file
:ThanosAsk How do I...   " Ask AI a question
:collab start 9000       " Start server on port 9000
```

## See Also

- [Motions](../motions/README.md) - Cursor movement
- [Keybindings](../keybindings.md) - All keyboard shortcuts
- [Configuration](../configuration.md) - Customizing Grim

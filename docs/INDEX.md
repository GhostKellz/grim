# Grim Documentation Index

Complete documentation for the Grim editor.

## Quick Start

- [Installation Guide](../INSTALL.md)
- [Quick Start Guide](../README.md)
- [Configuration](configuration.md)

## Commands

- **[Commands Overview](commands/README.md)** - All available commands
  - [Editor Commands](commands/editor.md) - File, buffer, window operations
  - [AI Commands](commands/ai.md) - AI-powered completions and assistance
  - [Git Commands](commands/git.md) - Version control integration
  - [Collaboration Commands](commands/collaboration.md) - Real-time collaborative editing
  - [LSP Commands](commands/lsp.md) - Language Server Protocol

## Motions & Navigation

- **[Motions Reference](motions/README.md)** - Cursor movement and navigation
  - Basic motions (`hjkl`, `w`, `b`)
  - Line motions (`0`, `$`, `^`)
  - Screen motions (`H`, `M`, `L`, `<C-f>`, `<C-b>`)
  - Jump motions (`gg`, `G`, `%`)
  - Search motions (`f`, `t`, `/`, `*`)
  - Text objects (`iw`, `i(`, `i{`, `i"`)

## AI Integration

- **[AI Configuration](AI_CONFIGURATION.md)** - Multi-provider AI setup
  - API key management
  - Provider selection (Anthropic, OpenAI, xAI, Copilot, Ollama)
  - Model selection (GPT-5, Claude 4.5, Grok Code)
  - Cost optimization strategies
  - Omen gateway setup

## Features

### Core Features
- **Modal Editing** - Vim-inspired modal interface
- **Multi-Buffer** - Work with multiple files
- **Syntax Highlighting** - Grove-powered highlighting
- **LSP Integration** - Code intelligence (completion, diagnostics, jump-to-definition)
- **Terminal** - Integrated terminal with async I/O

### Advanced Features
- **AI Assistance** - Multi-provider AI completions (via thanos.grim)
- **Collaboration** - Real-time collaborative editing (WebSocket + OT)
- **Git Integration** - Built-in git commands and status
- **Plugin System** - Ghostlang + native plugins
- **Performance** - Sub-10ms startup, rope data structure

## Configuration

### Config Files
- `~/.config/grim/init.gza` - Main configuration (Ghostlang)
- `~/.config/grim/ai.toml` - AI provider configuration
- `~/.config/grim/collab.toml` - Collaboration settings
- `~/.config/grim/git.toml` - Git integration settings

### Keybindings
See [Keybindings Reference](keybindings.md)

**Leader Key:** `Space`

**Essential:**
- `<leader>ac` - AI Chat
- `<leader>ak` - AI Complete
- `<leader>gs` - Git Status
- `<leader>ff` - Find Files (Fuzzy Finder)
- `<C-w>s` - Split Horizontal
- `<C-w>v` - Split Vertical

## Architecture

- [Architecture Overview](architecture.md)
- [Plugin System](PLUGIN_DEVELOPMENT_GUIDE.md)
- [Core Modules](GRIM_MODULES_REFERENCE.md)
- [Rope Data Structure](core-rope.md)

## Plugin Development

- [Plugin Development Guide](PLUGIN_DEVELOPMENT_GUIDE.md)
- [Plugin API Reference](plugin-api.md)
- [Native Plugin Guide](native-plugins.md)
- [Hybrid Plugins](hybrid-plugins.md)

## Distribution-Specific

### Reaper Distribution
- [Reaper Overview](../reaper/README.md)
- [Reaper Quickstart](../reaper/QUICKSTART.md)
- [Reaper Plugin List](../reaper/docs/plugins/README.md)

### Phantom.grim (Coming Soon)
- Full-featured Grim distribution
- Pre-configured AI, LSP, Git integration
- Comprehensive plugin suite

## Troubleshooting

### Common Issues

**Slow Startup**
- Check plugin count: `:PluginList`
- Disable unnecessary plugins
- See [Performance Guide](performance.md)

**AI Not Working**
- Check API keys: `:ThanosProviders`
- Verify Omen health: `curl http://localhost:8080/health`
- See [AI Configuration](AI_CONFIGURATION.md)

**LSP Errors**
- Check LSP status: `:LspInfo`
- Install language servers: `:LspInstall <language>`
- See [LSP Guide](lsp.md)

**Git Commands Failing**
- Verify git installed: `git --version`
- Check repository: `git status`
- See [Git Commands](commands/git.md)

## Contributing

- [Contributing Guide](../CONTRIBUTING.md)
- [Code Style](code-style.md)
- [Testing](testing.md)

## Project Information

- [Roadmap](../STATUS.md)
- [Changelog](../CHANGELOG.md)
- [License](../LICENSE)

## External Links

- [GitHub Repository](https://github.com/ghostkellz/grim)
- [Thanos AI Gateway](https://github.com/ghostkellz/thanos)
- [Omen Router](https://github.com/ghostkellz/omen)
- [Phantom.grim](https://github.com/ghostkellz/phantom.grim)

## Quick Command Reference

### Editor
```vim
:e <file>       " Edit file
:w              " Write (save)
:q              " Quit
:split          " Horizontal split
:vsplit         " Vertical split
```

### AI
```vim
:ThanosComplete         " AI code completion
:ThanosChat             " Open AI chat
:ThanosSwitch ollama    " Switch to Ollama
:ThanosProviders        " List providers
```

### Git
```vim
:Gstatus        " Git status
:Gadd .         " Stage all
:Gcommit        " Commit
:Gpush          " Push
:Gdiff          " Show diff
```

### Collaboration
```vim
:collab start       " Start server
:collab join <url>  " Join session
:collab users       " Show users
```

## Search This Documentation

Use Grim's fuzzy finder to search docs:

```vim
:e ~/docs/
<leader>ff
```

Or use grep:

```vim
:!grep -r "keyword" ~/docs/grim/
```

---

**Last Updated:** 2025-10-24
**Grim Version:** 0.1.0
**Documentation Version:** 1.0

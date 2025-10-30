# Grim Documentation

Welcome to the Grim editor documentation!

## Table of Contents

### Getting Started

- [Installation](installation.md) - Installing Grim from source
- [Quick Start](quick-start.md) - Your first steps with Grim
- [Configuration](configuration.md) - Customizing Grim to your needs

### Core Features

- **[LSP Completion](lsp-completion.md)** - Intelligent code completion
- **[Status Bar](status-bar.md)** - Powerline-style status line with diagnostics
- **[Session Management](session-management.md)** - Auto-save and workspace restoration
- **[Split Windows](split-windows.md)** - Multi-window editing and navigation

### Editor Features

- [Vim Motions](vim-motions.md) - Modal editing keybindings
- [Buffer Management](buffers.md) - Working with multiple files
- [Search and Replace](search-replace.md) - Finding and replacing text
- [Macros](macros.md) - Recording and playing back commands

### Language Support

- [LSP Integration](lsp-integration.md) - Language Server Protocol setup
- [Tree-sitter](tree-sitter.md) - Syntax highlighting and parsing
- [Supported Languages](languages.md) - List of supported languages

### Advanced Topics

- [Plugin System](plugins.md) - Ghostlang plugin development
- [Performance](performance.md) - Profiling and optimization
- [Error Handling](error-handling.md) - Understanding and fixing errors
- [Keybindings](keybindings.md) - Complete keybinding reference

### Development

- [Contributing](../CONTRIBUTING.md) - How to contribute to Grim
- [Architecture](architecture.md) - Codebase structure and design
- [Testing](testing.md) - Running and writing tests
- [Building](building.md) - Build system and options

## Quick Reference

### Essential Keybindings

| Mode | Key | Action |
|------|-----|--------|
| Normal | `i` | Enter insert mode |
| Normal | `v` | Enter visual mode |
| Normal | `:` | Enter command mode |
| Normal | `/` | Search forward |
| Normal | `?` | Search backward |
| Normal | `<C-w>v` | Vertical split |
| Normal | `<C-w>s` | Horizontal split |
| Insert | `<C-n>` | Trigger LSP completion |
| Insert | `Esc` | Return to normal mode |

### Essential Commands

| Command | Description |
|---------|-------------|
| `:w` | Save current file |
| `:q` | Quit (close window) |
| `:wq` | Save and quit |
| `:e <file>` | Open file |
| `:vsplit` | Vertical split |
| `:SessionSave` | Save workspace session |

## Features at a Glance

### LSP Completion

Intelligent, context-aware code completion with:
- Fuzzy filtering
- Documentation preview
- Kind-specific icons
- Multi-provider support

[Learn more →](lsp-completion.md)

### Status Bar

Powerline-style status bar showing:
- Editor mode (Normal/Insert/Visual)
- LSP diagnostics (errors/warnings)
- Git branch
- File path and type
- Cursor position

[Learn more →](status-bar.md)

### Session Management

Never lose your workspace with:
- Auto-save every 30 seconds
- Restore on startup
- Named sessions for different projects
- Buffer states and positions preserved

[Learn more →](session-management.md)

### Split Windows

Edit multiple files simultaneously:
- Vertical and horizontal splits
- Vim-style window navigation
- Distance-based directional movement
- Flexible layouts

[Learn more →](split-windows.md)

## Getting Help

- **Documentation**: Browse this docs folder
- **Issues**: [GitHub Issues](https://github.com/ghostkellz/grim/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ghostkellz/grim/discussions)
- **Discord**: [Join our community](#) _(coming soon)_

## What's New

### Recent Features (2025-01-XX)

- ✅ LSP completion menu with fuzzy filtering
- ✅ Enhanced status bar with diagnostics
- ✅ Auto-save session management  
- ✅ Improved split window navigation
- ✅ Comprehensive error handling
- ✅ Developer documentation

See [CHANGELOG](../CHANGELOG.md) for full history.

## Contributing

We welcome contributions! See [CONTRIBUTING.md](../CONTRIBUTING.md) for:

- Development setup
- Code style guidelines
- Pull request process
- Testing requirements

## License

Grim is open source software. See [LICENSE](../LICENSE) for details.

# Phantom.grim Plugin Documentation

Complete reference for all 24 built-in plugins (8457 lines of Ghostlang).

---

## 📚 Plugin Categories

### [Core Plugins](core.md) (7 plugins - 4225 lines)
Essential functionality that powers Phantom.grim.

- **file-tree.gza** (1197 lines) - File explorer with git status
- **fuzzy-finder.gza** (733 lines) - FZF with ripgrep integration
- **statusline.gza** (477 lines) - Git-aware statusline
- **treesitter.gza** (214 lines) - Syntax highlighting via Grove
- **theme.gza** (492 lines) - Theme system
- **plugin-manager.gza** (964 lines) - Plugin management
- **zap-ai.gza** (148 lines) - AI integration (Zap)

### [Editor Plugins](editor.md) (7 plugins - 1761 lines)
Enhance the editing experience.

- **comment.gza** (288 lines) - Line/block comment toggling
- **autopairs.gza** (179 lines) - Auto-close brackets/quotes
- **textops.gza** (434 lines) - Buffer manipulation helpers
- **phantom.gza** (168 lines) - Core editor functions
- **terminal.gza** (362 lines) - Built-in terminal (Ctrl+`)
- **theme-commands.gza** (63 lines) - Theme switching commands
- **plugin-commands.gza** (267 lines) - Plugin management commands

### [LSP Plugins](lsp.md) (2 plugins - 270 lines)
Language Server Protocol integration.

- **config.gza** (135 lines) - LSP server configs (ghostls, zls, rust-analyzer)
- **lsp-config.gza** (135 lines) - Auto-start LSP servers

### [Git Plugins](git.md) (1 plugin - 497 lines)
Git integration and visualization.

- **git-signs.gza** (497 lines) - Gutter diff signs, blame, hunks

### [UI Plugins](ui.md) (5 plugins - 1298 lines)
User interface enhancements.

- **which-key.gza** (364 lines) - Keybinding discovery popup
- **dashboard.gza** (233 lines) - Welcome screen
- **bufferline.gza** (374 lines) - Visual buffer tabs
- **indent-guides.gza** (327 lines) - Indent visualization

### [Integration Plugins](integration.md) (1 plugin - 329 lines)
Third-party tool integrations.

- **tmux.gza** (329 lines) - Seamless tmux integration

### [Extras](extras.md) (3 plugins)
Additional utilities and testing infrastructure.

- **health.gza** - Health check system
- **test/** - Testing infrastructure

---

## 🎯 Quick Reference

### By Use Case

**File Navigation:**
- file-tree.gza - Browse files in sidebar
- fuzzy-finder.gza - Search files/grep/buffers

**Code Editing:**
- autopairs.gza - Auto-close brackets
- comment.gza - Toggle comments (gcc, gbc)
- textops.gza - Advanced text operations

**Code Intelligence:**
- LSP plugins - Auto-completion, go-to-definition
- treesitter.gza - Syntax highlighting

**Git Workflow:**
- git-signs.gza - See changes in gutter
- statusline.gza - Git branch/status in statusline

**Terminal:**
- terminal.gza - Integrated terminal
- tmux.gza - Tmux pane navigation

**Discoverability:**
- which-key.gza - Learn keybindings
- dashboard.gza - Welcome screen

**Visual Polish:**
- bufferline.gza - Buffer tabs at top
- indent-guides.gza - Visual indent levels
- theme.gza - Color schemes

---

## 📖 Reading Guide

### For Users
Start with:
1. [Core Plugins](core.md) - Understand the foundation
2. [UI Plugins](ui.md) - Learn the interface
3. [Editor Plugins](editor.md) - Master editing features

### For Plugin Developers
Read:
1. [Plugin Architecture](../plugin-development.md) - How plugins work
2. [Core Plugins](core.md) - Study plugin-manager.gza
3. [Best Practices](../best-practices.md) - Code patterns

### For Customization
Focus on:
1. [Theme System](core.md#theme) - Customize colors
2. [Keybindings](editor.md#keybindings) - Remap keys
3. [LSP Config](lsp.md) - Add language servers

---

## 🔌 Plugin Status

| Plugin | Status | Grim API Ready | Notes |
|--------|--------|----------------|-------|
| file-tree | ✅ Complete | 🚧 Mock | Awaiting grim file API |
| fuzzy-finder | ✅ Complete | 🚧 Mock | Awaiting grim fuzzy API |
| statusline | ✅ Complete | ✅ Ready | Uses grim.git |
| treesitter | ✅ Complete | ✅ Ready | Uses Grove |
| theme | ✅ Complete | ✅ Ready | Full FFI support |
| plugin-manager | ✅ Complete | ✅ Ready | - |
| zap-ai | ✅ Complete | 🚧 Partial | Needs HTTP client |
| comment | ✅ Complete | 🚧 Mock | Awaiting buffer API |
| autopairs | ✅ Complete | 🚧 Mock | Awaiting event API |
| textops | ✅ Complete | 🚧 Mock | Awaiting buffer API |
| phantom | ✅ Complete | ✅ Ready | - |
| terminal | ✅ Complete | 🚧 Mock | Awaiting terminal API |
| theme-commands | ✅ Complete | ✅ Ready | - |
| plugin-commands | ✅ Complete | ✅ Ready | - |
| config | ✅ Complete | ✅ Ready | - |
| lsp-config | ✅ Complete | ✅ Ready | Uses grim.lsp |
| git-signs | ✅ Complete | ✅ Ready | Uses grim.git |
| which-key | ✅ Complete | 🚧 Mock | Awaiting popup API |
| dashboard | ✅ Complete | 🚧 Mock | Awaiting buffer API |
| bufferline | ✅ Complete | 🚧 Mock | Awaiting bufferline API |
| indent-guides | ✅ Complete | 🚧 Mock | Awaiting virtual text API |
| tmux | ✅ Complete | ✅ Ready | Uses shell commands |
| health | ✅ Complete | ✅ Ready | - |
| test/integration | ✅ Complete | ✅ Ready | - |

**Legend:**
- ✅ Ready - Fully integrated with Grim APIs
- 🚧 Mock - Implementation complete, awaiting Grim API
- ❌ Blocked - Waiting on dependencies

---

## 🚀 Coming Soon

### Planned Plugins (v0.2.0+)
- **copilot.gza** - GitHub Copilot integration
- **reaper-client.gza** - Multi-provider AI completions
- **dap.gza** - Debug Adapter Protocol support
- **surround.gza** - Surround text objects (ys, cs, ds)
- **multicursor.gza** - Multiple cursor editing
- **session.gza** - Session management
- **project.gza** - Project-specific configs

See [TODO.md](../../TODO.md) for full roadmap.

---

**Last Updated:** 2025-10-12
**Phantom.grim Version:** v0.1.0-alpha

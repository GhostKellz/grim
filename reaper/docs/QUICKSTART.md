# Phantom.grim Quick Start

Get up and running with phantom.grim in 5 minutes.

## Installation

```bash
# Clone the repository
git clone https://github.com/ghostkellz/phantom.grim
cd phantom.grim

# Build
zig build

# Run
./zig-out/bin/phantom_grim
```

## First Steps

### Opening Files

```bash
# Open a specific file
./zig-out/bin/phantom_grim myfile.zig

# Start with empty buffer
./zig-out/bin/phantom_grim
```

### Basic Navigation

- **Normal Mode** (default):
  - `h` `j` `k` `l` - Move cursor left/down/up/right
  - `w` `b` - Jump forward/backward by word
  - `0` `$` - Start/end of line
  - `gg` `G` - Top/bottom of file

- **Insert Mode**:
  - `i` - Insert before cursor
  - `a` - Append after cursor
  - `o` - New line below
  - `Esc` - Return to Normal mode

- **Visual Mode**:
  - `v` - Enter visual mode
  - Move to select text
  - `y` - Yank (copy)
  - `d` - Delete
  - `c` - Change

### File Operations

- `<leader>ff` - Fuzzy find files (FZF)
- `<leader>fg` - Live grep in files
- `<leader>ft` - Toggle file tree
- `:w` - Save file
- `:q` - Quit
- `:wq` - Save and quit

### LSP Features

Phantom.grim includes LSP support for Zig, Rust, Go, C/C++, TypeScript/JavaScript, and Ghostlang:

- `K` - Show hover documentation
- `gd` - Go to definition
- `<Tab>` - Trigger completion
- Diagnostics appear automatically in gutter

### Git Integration

- Git diff markers in gutter (+/-/~)
- Current branch in statusline
- `<leader>gs` - Git status
- `<leader>gc` - Git commit

### Themes

```bash
# Start with specific theme
./zig-out/bin/phantom_grim --theme ghost-hacker-blue
./zig-out/bin/phantom_grim --theme tokyonight-moon

# Available themes:
# - ghost-hacker-blue (default - cyan/teal/mint hacker aesthetic)
# - tokyonight-moon (Tokyo Night Moon)
```

## Essential Keybindings

### Leader Key

Leader is `<Space>` by default.

### File Navigation

| Key | Action |
|-----|--------|
| `<leader>ff` | Fuzzy find files |
| `<leader>fg` | Live grep |
| `<leader>fr` | Recent files |
| `<leader>ft` | Toggle file tree |

### Buffer Management

| Key | Action |
|-----|--------|
| `<leader>bn` | Next buffer |
| `<leader>bp` | Previous buffer |
| `<leader>bd` | Delete buffer |
| `<Tab>` | Cycle buffers |

### LSP

| Key | Action |
|-----|--------|
| `K` | Hover documentation |
| `gd` | Go to definition |
| `gr` | Find references |
| `<leader>ca` | Code actions |
| `<leader>rn` | Rename symbol |

### Git

| Key | Action |
|-----|--------|
| `<leader>gs` | Git status |
| `<leader>gc` | Git commit |
| `<leader>gp` | Git push |
| `<leader>gl` | Git log |

### Terminal

| Key | Action |
|-----|--------|
| `Ctrl+\`` | Toggle terminal |
| `<leader>tt` | Open terminal |

### AI (Thanos) 🤖

| Key | Action |
|-----|--------|
| `<leader>ac` | Open AI chat |
| `<leader>ak` | AI code completion |
| `<leader>ap` | Switch AI provider |
| `<leader>as` | Show AI stats |
| `<leader>ae` | Explain code (visual selection) |
| `<leader>ar` | Review code |
| `:PhantomAI <query>` | Semantic file search |
| `:ThanosCommit` | AI commit message |

### Which-Key

Press `<Space>` and wait 500ms - a popup will show all available keybindings grouped by category.

## Plugin System

Phantom.grim includes 25 built-in plugins:

**Core Plugins:**
- fuzzy-finder - FZF-like file/text search
- file-tree - File explorer with git status
- statusline - Mode/git/LSP status bar
- treesitter - Syntax highlighting via Tree-sitter
- theme - Theme management system
- plugin-manager - Plugin loader and updater

**Editor Plugins:**
- autopairs - Auto-close brackets/quotes
- comment - Toggle line/block comments
- terminal - Built-in terminal emulator
- textops - Buffer manipulation helpers

**UI Plugins:**
- bufferline - Visual buffer tabs
- dashboard - Welcome screen with recent files
- which-key - Keybinding discovery
- indent-guides - Visual indent markers

**Git Plugins:**
- git-signs - Inline git diff and blame

**Integration:**
- tmux - Seamless tmux pane navigation

**LSP:**
- lsp-config - Auto-start LSP servers

**AI:**
- **thanos** - Multi-provider AI gateway (GitHub Copilot, Claude, GPT-4, Ollama, Grok) 🤖
  - AI code completion
  - AI chat interface
  - AI code review
  - AI commit messages
  - Semantic code search
- zap-ai - AI code assistance (Ollama)
- omen - AI completion (Omen gateway)

All plugins load lazily for fast startup (<50ms).

## Configuration

Edit `~/.config/phantom.grim/init.gza` to customize:

```ghostlang
-- Load phantom API
local phantom = require("plugins.editor.phantom")

-- Configure theme
phantom.theme({
    default = "ghost-hacker-blue",
    preview_random = false,
})

-- Add custom keymaps
phantom.setup({
    keymaps = {
        { "n", "<leader>w", ":w<CR>", "Save file" },
    },
})
```

## Next Steps

- Read [USER_GUIDE.md](USER_GUIDE.md) for comprehensive documentation
- Check [MIGRATION.md](MIGRATION.md) if coming from Neovim/LazyVim
- Explore `plugins/` directory for examples
- Join the community discussions

## Performance

- **Startup time:** <50ms (10x faster than LazyVim)
- **Memory usage:** ~28MB (3x less than LazyVim)
- **LSP support:** 6 languages out-of-box
- **Plugin count:** 25 built-in plugins

## Troubleshooting

**Editor won't start:**
```bash
# Check build
zig build clean
zig build
```

**LSP not working:**
```bash
# Ensure language servers are installed
# Zig: zls
# Rust: rust-analyzer
# Go: gopls
# C/C++: clangd
# TypeScript: typescript-language-server
# Ghostlang: ghostls
```

**Plugins not loading:**
```bash
# Check logs
./zig-out/bin/phantom_grim 2>&1 | grep ERROR
```

## Getting Help

- GitHub Issues: https://github.com/ghostkellz/phantom.grim/issues
- Documentation: [docs/](.)
- Example Plugins: [plugins/](../plugins/)

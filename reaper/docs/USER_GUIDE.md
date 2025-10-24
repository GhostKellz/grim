# Phantom.grim User Guide

Complete guide to using phantom.grim - the LazyVim-inspired distribution for the Grim editor.

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Core Concepts](#core-concepts)
4. [Modal Editing](#modal-editing)
5. [File Navigation](#file-navigation)
6. [LSP Integration](#lsp-integration)
7. [Plugin System](#plugin-system)
8. [Customization](#customization)
9. [Advanced Features](#advanced-features)
10. [Troubleshooting](#troubleshooting)

## Introduction

Phantom.grim is a batteries-included configuration for the Grim editor, inspired by LazyVim for Neovim. It provides:

- **Modal editing** - Vim-like modes (Normal, Insert, Visual)
- **LSP integration** - Code intelligence for 6 languages
- **Lazy loading** - Fast startup (<50ms) with 25 plugins
- **Modern UI** - Fuzzy finding, file tree, statusline, bufferline
- **Git integration** - Inline diffs, blame, commit helpers
- **AI assistance** - Code generation, commit messages
- **Ghostlang plugins** - Extensible via Lua-like scripts

## Installation

### Prerequisites

- Zig 0.16.0-dev or later
- Git
- Recommended LSP servers:
  - `zls` (Zig)
  - `rust-analyzer` (Rust)
  - `gopls` (Go)
  - `clangd` (C/C++)
  - `typescript-language-server` (TypeScript/JavaScript)
  - `ghostls` (Ghostlang)

### Build from Source

```bash
git clone https://github.com/ghostkellz/phantom.grim
cd phantom.grim
zig build
./zig-out/bin/phantom_grim
```

### Install System-Wide

```bash
zig build
sudo cp zig-out/bin/phantom_grim /usr/local/bin/
phantom_grim
```

## Core Concepts

### Modal Editing

Phantom.grim uses modal editing inspired by Vim:

**Normal Mode** (default):
- Navigate and manipulate text
- Press keys to execute commands
- No direct text insertion

**Insert Mode**:
- Type text directly
- Press `Esc` to return to Normal mode
- Entered via `i`, `a`, `o`, etc.

**Visual Mode**:
- Select text regions
- Operate on selections
- Entered via `v`

### Buffers and Windows

- **Buffer**: In-memory text content (like a file)
- **Window**: Viewport showing a buffer
- **Tab**: Container for window layouts (not implemented yet)

### Leader Key

The leader key is `<Space>`. Many commands start with leader:
- `<leader>ff` - Find files
- `<leader>fg` - Grep files
- `<leader>w` - Write file

Press `<Space>` and wait - which-key will show available commands.

## Modal Editing

### Normal Mode

#### Motion Commands

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | Left, Down, Up, Right |
| `w` | Next word start |
| `b` | Previous word start |
| `e` | Next word end |
| `0` | Start of line |
| `$` | End of line |
| `gg` | Top of file |
| `G` | Bottom of file |
| `{count}G` | Go to line {count} |
| `%` | Jump to matching bracket |

#### Edit Commands

| Key | Action |
|-----|--------|
| `i` | Insert before cursor |
| `a` | Append after cursor |
| `I` | Insert at line start |
| `A` | Append at line end |
| `o` | Open new line below |
| `O` | Open new line above |
| `r{char}` | Replace character |
| `x` | Delete character |
| `dd` | Delete line |
| `yy` | Yank (copy) line |
| `p` | Paste after cursor |
| `P` | Paste before cursor |
| `u` | Undo |
| `Ctrl+r` | Redo |

#### Text Objects

| Key | Action |
|-----|--------|
| `diw` | Delete inner word |
| `daw` | Delete around word |
| `ci(` | Change inside parentheses |
| `da{` | Delete around braces |
| `vi"` | Visual select inside quotes |

### Insert Mode

Type normally. Press `Esc` to return to Normal mode.

**Special keys:**
- `Ctrl+h` - Delete character
- `Ctrl+w` - Delete word
- `Ctrl+u` - Delete line
- `Tab` - Trigger LSP completion

### Visual Mode

Select text:
- `v` - Character-wise selection
- `V` - Line-wise selection (not implemented yet)
- `Ctrl+v` - Block selection (not implemented yet)

Once selected:
- `y` - Yank (copy)
- `d` - Delete
- `c` - Change (delete and enter Insert mode)
- `>` - Indent
- `<` - Dedent

## File Navigation

### Fuzzy Finder

Phantom.grim includes a powerful FZF-like fuzzy finder:

```
<leader>ff   Find files (respects .gitignore)
<leader>fg   Live grep (search file contents)
<leader>fr   Recent files
<leader>fb   Browse buffers
```

**Fuzzy Finder Keys:**
- `j` `k` / `Down` `Up` - Navigate results
- `Enter` - Open selected file
- `Esc` - Cancel
- Type to filter results in real-time

### File Tree

Toggle file tree sidebar:

```
<leader>ft   Toggle file tree
```

**File Tree Keys:**
- `j` `k` - Navigate
- `Enter` - Open file/expand directory
- `a` - Create new file
- `d` - Delete file
- `r` - Rename file
- `R` - Refresh tree
- `?` - Show help

### Buffer Management

```
<leader>bn   Next buffer
<leader>bp   Previous buffer
<leader>bd   Delete buffer
<leader>ba   Delete all buffers
Tab          Cycle buffers
```

## LSP Integration

Phantom.grim provides full LSP (Language Server Protocol) support.

### Supported Languages

| Language | LSP Server | Auto-start |
|----------|------------|-----------|
| Zig | zls | ✓ |
| Rust | rust-analyzer | ✓ |
| Go | gopls | ✓ |
| C/C++ | clangd | ✓ |
| TypeScript/JavaScript | typescript-language-server | ✓ |
| Ghostlang | ghostls | ✓ |

### LSP Features

**Diagnostics:**
- Appear in gutter as `E` (error), `W` (warning), `I` (info), `H` (hint)
- Status line shows diagnostic count
- Hover over line to see message

**Hover Documentation:**
```
K   Show documentation for symbol under cursor
```

**Code Completion:**
```
Tab          Trigger completion
Ctrl+n       Next completion
Ctrl+p       Previous completion
Enter        Accept completion
Esc          Cancel
```

**Navigation:**
```
gd           Go to definition
gr           Find references
gi           Go to implementation
gy           Go to type definition
```

**Code Actions:**
```
<leader>ca   Show code actions
<leader>rn   Rename symbol
<leader>f    Format document
```

**Signature Help:**
- Appears automatically in function calls
- Shows parameter information

**Inlay Hints:**
- Type hints appear inline (configurable)

### LSP Status

Status line shows:
- LSP server name (e.g., `zls ✓`)
- Connection status:
  - `✓` - Connected and ready
  - `✗` - Error
  - `⏳` - Starting

## Plugin System

Phantom.grim includes 25 plugins that load lazily for fast startup.

### Core Plugins

**fuzzy-finder** (733 lines)
- FZF-like file and text search
- Ripgrep integration
- Real-time filtering

**file-tree** (1197 lines)
- File explorer sidebar
- Git status integration
- Create/delete/rename operations

**statusline** (477 lines)
- Mode indicator
- Git branch and changes
- LSP status
- File info

**treesitter** (214 lines)
- Syntax highlighting via Tree-sitter
- Supports multiple languages

**theme** (492 lines)
- Theme management
- Color customization
- Built-in themes:
  - ghost-hacker-blue (default)
  - tokyonight-moon

**plugin-manager** (964 lines)
- Load/unload plugins
- Lazy loading engine
- Dependency resolution

**lsp-config** (135 lines)
- Auto-spawn LSP servers
- Language detection
- Server configuration

### Editor Plugins

**autopairs** (179 lines)
- Auto-close brackets: `()` `[]` `{}`
- Auto-close quotes: `"` `'` `` ` ``
- Smart deletion

**comment** (288 lines)
- Toggle line comments: `gcc`
- Toggle block comments: `gc` (visual mode)
- Language-aware comment styles

**terminal** (362 lines)
- Built-in terminal emulator
- Toggle with `Ctrl+\``
- Split horizontal/vertical
- Multiple terminals

**textops** (434 lines)
- Buffer manipulation helpers
- Text object operations
- Utility functions

### UI Plugins

**bufferline** (374 lines)
- Tab-like buffer display at top
- Close buttons
- Modified indicators
- Visual buffer switching

**dashboard** (233 lines)
- Welcome screen
- Recent files
- Quick actions
- Custom ASCII art

**which-key** (364 lines)
- Keybinding discovery
- Popup after `<leader>`
- Grouped by category
- Search functionality

**indent-guides** (planned)
- Visual indent markers
- Highlight active scope

### Git Plugins

**git-signs** (497 lines)
- Inline diff markers in gutter
- Git blame annotations
- Stage/unstage hunks
- Preview changes

### Integration Plugins

**tmux** (329 lines)
- Seamless tmux pane navigation
- `Ctrl+h/j/k/l` works across vim/tmux
- Auto-detect tmux session
- Send commands to panes

### AI Plugins

**zap-ai** (148 lines)
- AI code generation
- Code explanation
- Refactoring suggestions

**omen** (planned)
- AI commit message generation
- Smart git workflow

### Installing Additional Plugins

Use `grim-pkg` to manage plugins:

```bash
# Install from directory
grim-pkg install /path/to/plugin

# Install from .gza file
grim-pkg install plugin.gza

# List installed
grim-pkg list

# Show info
grim-pkg info plugin-id

# Remove plugin
grim-pkg remove plugin-id
```

## Customization

### Configuration File

Edit `~/.config/phantom.grim/init.gza`:

```ghostlang
local phantom = require("plugins.editor.phantom")

-- Configure theme
phantom.theme({
    default = "ghost-hacker-blue",
    preview_random = false,
})

-- Setup with options
phantom.setup({
    -- Custom keymaps
    keymaps = {
        { "n", "<leader>w", ":w<CR>", "Save file" },
        { "n", "<leader>q", ":q<CR>", "Quit" },
        { "n", "<C-s>", ":w<CR>", "Save file" },
    },

    -- Autocmds
    autocmds = {
        { "BufWritePre", "*.zig", ":ZigFmt" },
    },

    -- Plugin specs
    plugins = {
        "my-custom-plugin",
    },
})
```

### Keymaps

Custom keymaps in init.gza:

```ghostlang
local function map(mode, lhs, rhs, desc)
    -- mode: "n" (normal), "i" (insert), "v" (visual)
    -- lhs: key combo
    -- rhs: command
    -- desc: description for which-key
end

map("n", "<leader>w", ":w<CR>", "Save file")
map("n", "jk", "<Esc>", "Exit insert mode")
map("v", "<", "<gv", "Indent left and reselect")
```

### Themes

Switch themes:

```bash
# Command line
phantom_grim --theme tokyonight-moon

# In init.gza
phantom.theme({ default = "tokyonight-moon" })
```

Create custom theme in `~/.config/phantom.grim/themes/mytheme.toml`:

```toml
name = "mytheme"
description = "My custom theme"

[colors]
foreground = "#ffffff"
background = "#000000"
cursor = "#00ff00"
keyword = "#ff00ff"
string = "#00ffff"
```

### Plugin Development

Create a plugin at `~/.local/share/phantom.grim/plugins/myplugin/`:

**plugin.json:**
```json
{
  "id": "myplugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "Does something cool",
  "entry_point": "init.gza",
  "enable_on_startup": true
}
```

**init.gza:**
```ghostlang
local plugin = {
    name = "myplugin",
}

function plugin.setup()
    print("My plugin loaded!")
end

function plugin.on_key(mode, key)
    -- Handle key events
end

return plugin
```

## Advanced Features

### Lazy Loading

Plugins load on-demand based on:

**Events:**
```ghostlang
phantom.lazy({
    name = "my-plugin",
    event = { "BufReadPost", "BufNewFile" },
})
```

**Commands:**
```ghostlang
phantom.lazy({
    name = "my-plugin",
    cmd = { "MyCommand" },
})
```

**Keymaps:**
```ghostlang
phantom.lazy({
    name = "my-plugin",
    keys = {
        { "n", "<leader>mp", ":MyPlugin<CR>" },
    },
})
```

### Tmux Integration

Seamless navigation between vim and tmux:

```
Ctrl+h   Move to left pane (vim or tmux)
Ctrl+j   Move down
Ctrl+k   Move up
Ctrl+l   Move to right pane
```

Works automatically if tmux is detected.

### Git Workflow

```
<leader>gs   Git status (shows branch, staged, unstaged)
<leader>gc   Git commit
<leader>gp   Git push
<leader>gl   Git log
<leader>gb   Git blame
<leader>gd   Git diff
```

### AI Assistance

```
<leader>ai   Ask AI about code
<leader>ac   Generate commit message
<leader>ae   Explain selected code
<leader>ar   Refactor suggestion
```

## Troubleshooting

### LSP Not Working

**Check server is installed:**
```bash
which zls
which rust-analyzer
which gopls
which clangd
```

**Check LSP status:**
Status line shows server name and status (`zls ✓`).

**View LSP logs:**
```bash
phantom_grim 2>&1 | grep LSP
```

### Slow Startup

**Profile startup:**
```bash
time phantom_grim --version
```

Should be <50ms. If slower:
- Disable plugins in init.gza
- Check for slow autocmds
- Rebuild: `zig build clean && zig build`

### Plugin Not Loading

**Check plugin is installed:**
```bash
grim-pkg list
```

**Check plugin manifest:**
```bash
grim-pkg info plugin-id
```

**View plugin errors:**
```bash
phantom_grim 2>&1 | grep "plugin-id"
```

### Theme Not Applying

**List available themes:**
```bash
phantom_grim --help
```

**Force theme:**
```bash
phantom_grim --theme ghost-hacker-blue
```

**Check theme file exists:**
```bash
ls ~/.config/phantom.grim/themes/
```

### Memory Leaks

Run with valgrind:
```bash
valgrind --leak-check=full ./zig-out/bin/phantom_grim
```

Phantom.grim should have no leaks in normal operation.

## Performance Tips

1. **Lazy load plugins** - Use event/cmd/keys triggers
2. **Disable unused features** - Comment out plugins in init.gza
3. **Use ripgrep** - Faster than grep for fuzzy finding
4. **Reduce autocmds** - Too many can slow file opening
5. **Profile regularly** - `time phantom_grim` to catch regressions

## Keyboard Shortcuts Reference

### Global

| Key | Action |
|-----|--------|
| `Esc` | Normal mode |
| `i` | Insert mode |
| `v` | Visual mode |
| `:` | Command mode |
| `Ctrl+Q` | Quit |

### File Operations

| Key | Action |
|-----|--------|
| `<leader>ff` | Find files |
| `<leader>fg` | Grep files |
| `<leader>fr` | Recent files |
| `<leader>ft` | Toggle tree |
| `<leader>w` | Save |
| `<leader>q` | Quit |

### Navigation

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | Move |
| `w` `b` | Word |
| `gg` `G` | File top/bottom |
| `0` `$` | Line start/end |
| `%` | Matching bracket |

### Editing

| Key | Action |
|-----|--------|
| `dd` | Delete line |
| `yy` | Yank line |
| `p` | Paste |
| `u` | Undo |
| `Ctrl+r` | Redo |
| `gcc` | Comment line |

### LSP

| Key | Action |
|-----|--------|
| `K` | Hover |
| `gd` | Definition |
| `gr` | References |
| `<leader>ca` | Code actions |
| `<leader>rn` | Rename |
| `<leader>f` | Format |

### Git

| Key | Action |
|-----|--------|
| `<leader>gs` | Status |
| `<leader>gc` | Commit |
| `<leader>gp` | Push |
| `<leader>gl` | Log |

### Buffers

| Key | Action |
|-----|--------|
| `<leader>bn` | Next |
| `<leader>bp` | Previous |
| `<leader>bd` | Delete |
| `Tab` | Cycle |

### Terminal

| Key | Action |
|-----|--------|
| `Ctrl+\`` | Toggle |
| `<leader>tt` | Open |

## Additional Resources

- [QUICKSTART.md](QUICKSTART.md) - 5-minute quick start guide
- [MIGRATION.md](MIGRATION.md) - Migrating from Neovim/LazyVim
- [GitHub Repository](https://github.com/ghostkellz/phantom.grim)
- [Plugin Examples](../plugins/)
- [Ghostlang Documentation](https://github.com/ghostkellz/ghostlang)

## Contributing

Contributions welcome! See [CONTRIBUTING.md](../CONTRIBUTING.md).

## License

Phantom.grim is open source software. See [LICENSE](../LICENSE) for details.

# Phantom.grim - Quick Start Guide

## What is Phantom.grim?

**Phantom.grim** is to **Grim** what **LazyVim** is to **Neovim** — a fully-featured, batteries-included configuration framework that turns Grim into a modern IDE.

- 🚀 Works out-of-the-box with 24 pre-configured plugins
- ⚡ Blazing fast (native Zig performance)
- 🎨 Beautiful UI with modern themes
- 🧠 Full LSP support (Ghostls, ZLS, rust-analyzer)
- 🌲 Tree-sitter syntax highlighting (14+ languages)

---

## Installation (5 Minutes)

**Important:** Phantom.grim is a configuration FOR Grim editor. Install Grim first!

### Step 1: Install Grim Editor
```bash
# Clone and install Grim
git clone https://github.com/ghostkellz/grim.git
cd grim
./release/install.sh

# Verify
grim --version
```

### Step 2: Install Phantom.grim Configuration
```bash
# Clone Phantom.grim
git clone https://github.com/ghostkellz/phantom.grim.git
cd phantom.grim

# Run installer (installs to ~/.config/grim/)
./release/install.sh
```

### Step 3: Launch!
```bash
# Just run grim - it auto-loads Phantom.grim config
grim
```

### Manual Install
```bash
# Clone Phantom.grim
git clone https://github.com/ghostkellz/phantom.grim ~/.config/grim

# Run installer (builds plugins, sets up config)
cd ~/.config/grim
./install.sh

# Launch Grim
grim
```

---

## First Launch

When you first start Grim with Phantom.grim:

1. **Dashboard appears** - Welcome screen with recent files
2. **Plugins auto-load** - All 24 plugins initialize
3. **Press `<Space>`** - See Which-Key popup with available commands

---

## Essential Keybindings

### Leader Key: `<Space>`

### File Operations
| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>w` | Save file | Core |
| `<leader>q` | Quit | Core |
| `<leader>e` | Toggle file tree | file-tree.gza |

### Fuzzy Finder (Telescope-like)
| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>ff` | Find files | fuzzy-finder.gza |
| `<leader>fg` | Live grep | fuzzy-finder.gza |
| `<leader>fb` | Find buffers | fuzzy-finder.gza |
| `<leader>fh` | Help tags | fuzzy-finder.gza |

### LSP (Language Server)
| Key | Action | Plugin |
|-----|--------|--------|
| `gd` | Go to definition | lsp-config.gza |
| `gD` | Go to declaration | lsp-config.gza |
| `gr` | Find references | lsp-config.gza |
| `K` | Hover documentation | lsp-config.gza |
| `<leader>ca` | Code actions | lsp-config.gza |
| `<leader>rn` | Rename symbol | lsp-config.gza |
| `[d` | Previous diagnostic | lsp-config.gza |
| `]d` | Next diagnostic | lsp-config.gza |

### Git Integration
| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>gs` | Git status | git-signs.gza |
| `<leader>gc` | Git commit | git-signs.gza |
| `<leader>gp` | Git push | git-signs.gza |
| `<leader>gb` | Git blame | git-signs.gza |

### Buffer Management
| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>bn` | Next buffer | bufferline.gza |
| `<leader>bp` | Previous buffer | bufferline.gza |
| `<leader>bd` | Delete buffer | bufferline.gza |
| `<S-h>` | Previous tab | bufferline.gza |
| `<S-l>` | Next tab | bufferline.gza |

### Terminal
| Key | Action | Plugin |
|-----|--------|--------|
| `Ctrl-\` | Toggle terminal | terminal.gza |

---

## Customization

### User Config File
Your personal settings go in:
```
~/.config/grim/lua/user/config.gza
```

### Change Theme
```lua
-- In ~/.config/grim/lua/user/config.gza
phantom.theme = "tokyonight-storm"

-- Available themes:
-- "ghost-hacker-blue" (default)
-- "tokyonight-storm"
-- "tokyonight-night"
-- "catppuccin"
-- "gruvbox"
-- "nord"
-- "dracula"
```

### Disable Plugins
```lua
-- Disable plugins you don't want
phantom.plugins.disable({
    "dashboard",     -- No startup screen
    "which-key",     -- No keybinding hints
    "autopairs",     -- No auto-close brackets
})
```

### Add LSP Servers
```lua
-- Configure which LSP servers to use
phantom.lsp.servers = {
    "ghostls",       -- Ghostlang
    "zls",           -- Zig
    "rust_analyzer", -- Rust
    "ts_ls",         -- TypeScript
    "pyright",       -- Python
}
```

### Custom Keybindings
```lua
-- Add your own keybindings
register_keymap("n", "<leader>xx", ":TodoList<CR>", { desc = "Show TODOs" })
register_keymap("n", "<leader>rr", ":!cargo run<CR>", { desc = "Rust run" })
```

### Editor Options
```lua
-- Customize editor behavior
set_option("relative_line_numbers", true)
set_option("tab_width", 2)
set_option("auto_save", true)
```

---

## Included Plugins (24 Total)

### Core Plugins (7)
1. **file-tree.gza** (1197 lines) - Neo-tree-like file explorer
2. **fuzzy-finder.gza** (733 lines) - Telescope-like fuzzy finding
3. **statusline.gza** (477 lines) - Beautiful status bar
4. **treesitter.gza** (214 lines) - Syntax highlighting via Grove
5. **theme.gza** (492 lines) - Theme system
6. **plugin-manager.gza** (964 lines) - Plugin management
7. **zap-ai.gza** (148 lines) - AI integration

### Editor Plugins (7)
1. **comment.gza** (288 lines) - Comment toggling
2. **autopairs.gza** (179 lines) - Auto-close brackets
3. **textops.gza** (434 lines) - Text manipulation
4. **phantom.gza** (168 lines) - Core editor functions
5. **terminal.gza** (362 lines) - Built-in terminal
6. **theme-commands.gza** (63 lines) - Theme switching
7. **plugin-commands.gza** (267 lines) - Plugin commands

### LSP Plugins (2)
1. **config.gza** (135 lines) - LSP server configs
2. **lsp-config.gza** (135 lines) - Auto-start LSP

### Git Plugins (1)
1. **git-signs.gza** (497 lines) - Git integration

### UI Plugins (5)
1. **which-key.gza** (364 lines) - Keybinding hints
2. **dashboard.gza** (233 lines) - Welcome screen
3. **bufferline.gza** (374 lines) - Buffer tabs
4. **indent-guides.gza** (327 lines) - Indent visualization

### Integration Plugins (1)
1. **tmux.gza** (329 lines) - Tmux integration

---

## Installing LSP Servers

### Ghostlang (Ghostls)
```bash
git clone https://github.com/ghostkellz/ghostls
cd ghostls
zig build install
```

### Zig (ZLS)
```bash
# macOS
brew install zls

# Ubuntu/Debian
apt install zls

# From source
git clone https://github.com/zigtools/zls
cd zls && zig build install
```

### Rust (rust-analyzer)
```bash
rustup component add rust-analyzer
```

### TypeScript
```bash
npm install -g typescript-language-server
```

### Python
```bash
pip install pyright
```

---

## Installing AI Coding (Thanos)

```bash
# Clone Thanos AI plugin
git clone https://github.com/ghostkellz/thanos.grim \
  ~/.local/share/grim/plugins/thanos

# Build the plugin
cd ~/.local/share/grim/plugins/thanos
zig build

# Restart Grim
grim
```

**Thanos Commands:**
- `:ThanosComplete` - AI code completion
- `:ThanosChat` - AI chat window
- `:ThanosSwitch ollama` - Switch AI provider

---

## Common Workflows

### 1. Opening a Project
```bash
# Open project directory
grim ~/my-project

# File tree appears automatically
# Press <leader>ff to fuzzy find files
```

### 2. Editing Code with LSP
```
1. Open a file: grim main.zig
2. LSP auto-starts (you'll see "LSP attached" in status)
3. Hover on symbol: K
4. Go to definition: gd
5. Rename: <leader>rn
6. Code actions: <leader>ca
```

### 3. Git Workflow
```
1. Make changes to files
2. Check git status: <leader>gs
3. See diff in gutter (git-signs shows +/- lines)
4. View git blame: <leader>gb
5. Commit: <leader>gc
6. Push: <leader>gp
```

### 4. Search & Replace
```
1. Live grep: <leader>fg
2. Search for "foo"
3. Select results
4. Replace all: :%s/foo/bar/g
```

---

## Troubleshooting

### Plugins Not Loading
```bash
# Check plugin directory
ls ~/.config/grim/plugins/

# Rebuild plugins
cd ~/.config/grim
./install.sh
```

### LSP Not Working
```bash
# Check if LSP server is installed
which ghostls   # or zls, rust-analyzer, etc.

# Check LSP logs in Grim
:LspInfo
```

### Theme Not Applied
```lua
-- Make sure theme is set in user config
-- ~/.config/grim/lua/user/config.gza
phantom.theme = "tokyonight-storm"
```

### File Tree Not Showing
```
# Toggle file tree
<leader>e

# Or run command
:NeoTree
```

---

## Advanced Tips

### 1. Custom Plugin
Create `~/.config/grim/plugins/custom/my-plugin.gza`:
```lua
-- My custom plugin
return {
    name = "my-plugin",
    config = function()
        -- Setup code here
        print("My plugin loaded!")
    end
}
```

### 2. Project-Specific Config
Create `.grim/config.gza` in your project root:
```lua
-- Project-specific settings
set_option("tab_width", 2)
phantom.lsp.servers = { "ts_ls", "eslint" }
```

### 3. Performance Tuning
```lua
-- In user config
phantom.performance = {
    lazy_load = true,          -- Lazy load plugins
    treesitter_cache = true,   -- Cache syntax highlighting
    lsp_debounce = 200,        -- Debounce LSP (ms)
}
```

---

## Getting Help

### In-Editor
```
:help           # Phantom.grim help
:help phantom   # Phantom-specific help
:help plugins   # Plugin documentation
```

### Online
- **GitHub**: https://github.com/ghostkellz/phantom.grim
- **Wiki**: https://github.com/ghostkellz/phantom.grim/wiki
- **Issues**: https://github.com/ghostkellz/phantom.grim/issues
- **Discussions**: https://github.com/ghostkellz/phantom.grim/discussions

---

## Updating Phantom.grim

```bash
# Update to latest version
cd ~/.config/grim
./install.sh update

# Or manually
git pull origin main
./install.sh
```

---

## Uninstalling

```bash
cd ~/.config/grim
./install.sh uninstall

# Your config backup is saved automatically
# Restore: cp ~/.config/grim.backup.* ~/.config/grim
```

---

**Enjoy Phantom.grim!** 👻✨

You now have a full-featured IDE powered by Zig and Ghostlang! 🚀

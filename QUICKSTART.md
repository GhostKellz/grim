# Grim Editor - Quick Start Guide

## Installation (5 Minutes)

### Option 1: One-Line Install
```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/grim/main/install.sh | bash
```

### Option 2: Manual Install
```bash
# Clone repository
git clone https://github.com/ghostkellz/grim
cd grim

# Run installer
./install.sh

# Source your shell config
source ~/.bashrc  # or ~/.zshrc
```

### Option 3: Custom Install Location
```bash
# Install to /usr/local (system-wide)
PREFIX=/usr/local ./install.sh

# Or to custom location
PREFIX=$HOME/software ./install.sh
```

---

## First Launch

```bash
# Start Grim
grim

# Open a file
grim myfile.txt

# Open multiple files
grim file1.zig file2.zig

# Open directory
grim /path/to/project
```

---

## Essential Keybindings

### Leader Key
The leader key is `<Space>` by default.

### File Operations
| Key | Action |
|-----|--------|
| `<leader>w` | Save file |
| `<leader>q` | Quit |
| `<leader>x` | Save and quit |
| `:e filename` | Edit file |
| `:w` | Write (save) |
| `:q` | Quit |
| `:q!` | Quit without saving |

### Navigation
| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | Left, Down, Up, Right |
| `w` | Next word |
| `b` | Previous word |
| `0` | Start of line |
| `$` | End of line |
| `gg` | Top of file |
| `G` | Bottom of file |
| `Ctrl-d` | Page down |
| `Ctrl-u` | Page up |

### Editing
| Key | Action |
|-----|--------|
| `i` | Insert mode (before cursor) |
| `a` | Insert mode (after cursor) |
| `o` | New line below |
| `O` | New line above |
| `Esc` | Back to normal mode |
| `dd` | Delete line |
| `yy` | Yank (copy) line |
| `p` | Paste |
| `u` | Undo |
| `Ctrl-r` | Redo |

### Visual Mode
| Key | Action |
|-----|--------|
| `v` | Visual mode (character) |
| `V` | Visual mode (line) |
| `Ctrl-v` | Visual block mode |

### Search
| Key | Action |
|-----|--------|
| `/pattern` | Search forward |
| `?pattern` | Search backward |
| `n` | Next match |
| `N` | Previous match |

---

## Configuration

### Location
- **Config file**: `~/.config/grim/init.gza`
- **Plugins**: `~/.local/share/grim/plugins/`
- **Themes**: `~/.local/share/grim/themes/`

### Basic Configuration
Edit `~/.config/grim/init.gza`:

```lua
-- Editor settings
vim.opt.number = true              -- Show line numbers
vim.opt.relativenumber = true      -- Relative line numbers
vim.opt.tabstop = 4                -- Tab width
vim.opt.shiftwidth = 4             -- Indent width
vim.opt.expandtab = true           -- Use spaces instead of tabs

-- Leader key
vim.g.mapleader = " "

-- Custom keybindings
vim.keymap.set("n", "<leader>w", ":write<CR>", { desc = "Save" })
vim.keymap.set("n", "<leader>q", ":quit<CR>", { desc = "Quit" })

-- Theme
vim.cmd("colorscheme gruvbox")
```

---

## Installing Plugins

### Method 1: Clone to Plugin Directory
```bash
# Install Thanos AI plugin
git clone https://github.com/ghostkellz/thanos.grim \
  ~/.local/share/grim/plugins/thanos

# Restart Grim
grim
```

### Method 2: Use Phantom.grim
```bash
# Install full Phantom.grim distro (recommended)
cd /data/projects/phantom.grim
./install.sh
```

---

## Themes

### Built-in Themes
- `gruvbox` - Retro warm colors
- `nord` - Arctic-inspired
- `dracula` - Classic dark theme
- `tokyonight` - Modern dark blue

### Change Theme
In `~/.config/grim/init.gza`:
```lua
vim.cmd("colorscheme tokyonight")
```

---

## Common Tasks

### Open File Tree
```
:Explore
```
or
```
:NeoTree  # if installed
```

### Split Windows
```
:split          # Horizontal split
:vsplit         # Vertical split
Ctrl-w h/j/k/l  # Navigate splits
Ctrl-w c        # Close split
```

### Tabs
```
:tabnew         # New tab
:tabnext        # Next tab
:tabprev        # Previous tab
gt              # Next tab (normal mode)
gT              # Previous tab (normal mode)
```

### Terminal
```
:term           # Open terminal in split
```

---

## LSP (Language Server Protocol)

### Install LSP Servers
```bash
# Zig
brew install zls           # macOS
apt install zls            # Ubuntu

# Rust
rustup component add rust-analyzer

# Ghostlang
git clone https://github.com/ghostkellz/ghostls
cd ghostls && zig build install
```

### LSP Keybindings
| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gr` | Find references |
| `K` | Hover documentation |
| `<leader>ca` | Code actions |
| `<leader>rn` | Rename symbol |
| `[d` | Previous diagnostic |
| `]d` | Next diagnostic |

---

## Troubleshooting

### Grim Won't Start
```bash
# Check installation
which grim

# Check permissions
ls -l ~/.local/bin/grim

# Run with debug output
grim --debug
```

### Config Errors
```bash
# Reset to default config
mv ~/.config/grim ~/.config/grim.backup
grim  # Will create default config
```

### Plugin Not Loading
```bash
# Check plugin directory
ls -la ~/.local/share/grim/plugins/

# Check plugin has init.gza or init.lua
ls ~/.local/share/grim/plugins/YOUR_PLUGIN/
```

---

## Next Steps

### 1. Install Phantom.grim (Recommended)
Get a full IDE experience with pre-configured plugins:
```bash
cd /data/projects/phantom.grim
./install.sh
```

### 2. Install AI Coding Assistant
```bash
# Install Thanos AI plugin
git clone https://github.com/ghostkellz/thanos.grim \
  ~/.local/share/grim/plugins/thanos
```

### 3. Learn More
- **Documentation**: https://github.com/ghostkellz/grim/docs
- **Wiki**: https://github.com/ghostkellz/grim/wiki
- **Examples**: `~/.local/share/grim/examples/`

---

## Getting Help

### In-Editor Help
```
:help           # General help
:help motion    # Movement commands
:help insert    # Insert mode
```

### Online Resources
- **Issues**: https://github.com/ghostkellz/grim/issues
- **Discussions**: https://github.com/ghostkellz/grim/discussions
- **Discord**: https://discord.gg/grim-editor

---

## Tips & Tricks

### Productivity Boosters
1. **Learn hjkl navigation** - Avoid using arrow keys
2. **Use relative line numbers** - Jump quickly with `5j` or `10k`
3. **Master visual mode** - Select and manipulate text efficiently
4. **Use marks** - `ma` to set mark, `'a` to jump back
5. **Use registers** - `"ayy` to yank to register a, `"ap` to paste

### Must-Know Commands
```
:%s/old/new/g   # Replace all occurrences
:g/pattern/d    # Delete lines matching pattern
:sort           # Sort selected lines
:!command       # Run shell command
```

---

**Congratulations!** You're ready to start using Grim! 🚀

For a full IDE experience, install **Phantom.grim** next!

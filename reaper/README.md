# Reaper - The Default Grim Distribution

<div align="center">

**The Ultimate Grim Configuration Framework**
*LazyVim-inspired distribution built from the ground up in Zig and Ghostlang*

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-yellow?logo=zig&style=for-the-badge)
![Ghostlang](https://img.shields.io/badge/Config-Ghostlang-7FFFD4?style=for-the-badge)
![Grim](https://img.shields.io/badge/Editor-Grim-gray?style=for-the-badge)
![Tree-sitter](https://img.shields.io/badge/Parser-TreeSitter-green?style=for-the-badge)
![LSP](https://img.shields.io/badge/Protocol-LSP-blue?style=for-the-badge)

</div>

---

## 🌟 Overview

**Reaper** is the default distribution for **Grim** - a fully-featured, batteries-included configuration that transforms Grim into a modern, powerful IDE experience out of the box.

Just like **LazyVim** is to **Neovim**, Reaper provides:

- 🚀 **Instant Productivity** - Works out-of-the-box, customize as you learn
- ⚡ **Blazing Fast** - Native Zig performance with zero overhead
- 🎨 **Beautiful UI** - TokyoNight theme, statusline, file tree, fuzzy finder
- 🧠 **AI-Powered** - Thanos AI integration (GitHub Copilot, Claude, GPT-4, Ollama)
- 📝 **LSP Support** - Full Language Server Protocol integration
- 🌳 **Tree-sitter** - Advanced syntax highlighting (14+ languages)
- 🔌 **Plugin Ecosystem** - Extensible with Zig and Ghostlang plugins
- 🎯 **Vim Motions** - Complete modal editing with hjkl, dd, yy, visual mode
- 🔄 **1000-Level Undo** - Never lose your work
- 🎨 **Multiple Themes** - TokyoNight, Ghost Hacker Blue, and more

---

## 📦 What's Included

Reaper is installed automatically when you install Grim. It includes:

### Core Features
- **Plugin Manager** - Lazy-loaded plugin system
- **File Tree** - NERDTree-like file explorer
- **Fuzzy Finder** - Telescope-style file/text search
- **Statusline** - Lualine-inspired status bar with git integration
- **Tree-sitter** - Syntax highlighting for 14+ languages
- **LSP** - Language server support for code intelligence

### AI Integration
- **Thanos** - Multi-provider AI gateway
  - GitHub Copilot
  - Anthropic Claude
  - OpenAI GPT-4
  - Ollama (local models)
  - xAI Grok
- **Omen** - AI-powered code generation and refactoring

### Editor Enhancements
- **Autopairs** - Auto-close brackets and quotes
- **Comment** - Smart commenting (gc, gcc)
- **Terminal** - Integrated terminal support
- **Phantom Buffer** - Advanced multi-cursor and undo/redo

### UI Plugins
- **Bufferline** - Tab-like buffer management
- **Dashboard** - Startup screen
- **Indent Guides** - Visual indentation
- **Which-key** - Keybinding hints

### Git Integration
- **Git Signs** - Show git changes in gutter

---

## 📂 Distribution Structure

```
reaper/
├── init.gza           # Main configuration entry point
├── plugins/           # Ghostlang plugin implementations
│   ├── core/          # Core plugins (file-tree, fuzzy-finder, etc.)
│   ├── ai/            # AI plugins (thanos, omen)
│   ├── editor/        # Editor enhancements
│   ├── lsp/           # LSP integration
│   ├── git/           # Git integration
│   └── ui/            # UI plugins
├── runtime/           # Ghostlang runtime libraries
│   ├── defaults/      # Default keymaps, options, autocmds
│   └── lib/           # Core libraries (core.gza, bridge.gza)
├── src/               # Native Zig plugins source
├── themes/            # Color schemes
└── docs/              # Documentation
```

---

## 🚀 Installation

Reaper is installed automatically with Grim:

```bash
# Install Grim (includes Reaper distribution)
cd /path/to/grim
sudo ./release/install.sh

# Reaper will be installed to:
# ~/.config/grim/          (configuration files)
# ~/.local/share/grim/     (plugins and runtime)
```

---

## ⚙️ Configuration

Reaper is configured using **Ghostlang** (.gza files), a Lua-inspired language designed for Grim.

### Main Config: `~/.config/grim/init.gza`

```lua
-- Your Reaper configuration
local core = require("core")
core.init({ verbose = true })

-- Load defaults
require("runtime.defaults.options")
require("runtime.defaults.keymaps")
require("runtime.defaults.autocmds")

-- Ensure plugins are loaded
core.ensure_plugins({
    "core.fuzzy-finder",
    "core.file-tree",
    "core.statusline",
    "ai.thanos",
    -- Add your custom plugins here
})
```

### Custom Keymaps

Edit `~/.config/grim/runtime/defaults/keymaps.gza`:

```lua
-- Add custom keybindings
map("n", "<leader>ff", ":FuzzyFinder<CR>", { desc = "Find files" })
map("n", "<leader>fg", ":FuzzyGrep<CR>", { desc = "Live grep" })
map("n", "<leader>e", ":FileTree<CR>", { desc = "Toggle file tree" })
```

---

## 🔌 Plugin Development

Reaper supports both **Ghostlang** and **Zig** plugins.

### Ghostlang Plugin Example

```lua
-- ~/.config/grim/plugins/my-plugin.gza
local M = {}

function M.setup(opts)
    print("My plugin loaded!")
end

return M
```

### Zig Native Plugin

```zig
// src/plugins/my_plugin.zig
pub fn init() void {
    // Plugin initialization
}
```

See `/data/projects/grim/reaper/docs/` for full plugin API documentation.

---

## 🎨 Themes

Reaper includes multiple themes:

- **TokyoNight** (default) - Dark theme with vivid colors
- **Ghost Hacker Blue** - Cyan/teal hacker aesthetic
- **TokyoNight Moon** - Darker variant

Switch themes in your `init.gza`:

```lua
vim.cmd("colorscheme tokyonight")
```

---

## 🤝 Contributing

Reaper is part of the Grim project. Contributions welcome!

- **Issues**: https://github.com/ghostkellz/grim/issues
- **Discussions**: https://github.com/ghostkellz/grim/discussions

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details

---

## 🙏 Credits

Reaper was formerly known as **Phantom.grim** and is inspired by:
- **LazyVim** - For the distribution concept
- **Neovim** - For modal editing excellence
- **Helix** - For modern UX inspiration

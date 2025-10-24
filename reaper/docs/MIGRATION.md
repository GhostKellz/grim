# Migrating to Phantom.grim

Guide for users coming from Neovim, LazyVim, or other modal editors.

## Table of Contents

1. [From Neovim](#from-neovim)
2. [From LazyVim](#from-lazyvim)
3. [From Vim](#from-vim)
4. [From VSCode with Vim Extension](#from-vscode-with-vim-extension)
5. [Feature Parity Comparison](#feature-parity-comparison)
6. [Common Pain Points](#common-pain-points)
7. [What You'll Miss](#what-youll-miss)
8. [What You'll Gain](#what-youll-gain)

## From Neovim

### Key Differences

**Configuration Language:**
- Neovim: Lua
- Phantom.grim: Ghostlang (Lua-like syntax, very similar)

**Plugin System:**
- Neovim: lazy.nvim, packer, vim-plug
- Phantom.grim: Built-in plugin manager with lazy loading

**LSP:**
- Neovim: nvim-lspconfig
- Phantom.grim: Built-in LSP client (auto-spawns servers)

**Tree-sitter:**
- Neovim: nvim-treesitter
- Phantom.grim: Grove (Zig Tree-sitter wrapper)

### Configuration Mapping

**Neovim init.lua:**
```lua
require("lazy").setup({
  { "nvim-telescope/telescope.nvim" },
  { "nvim-tree/nvim-tree.lua" },
})

vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
```

**Phantom.grim init.gza:**
```ghostlang
local phantom = require("plugins.editor.phantom")

phantom.lazy({
  name = "core.fuzzy-finder",
  keys = {
    { "n", "<leader>ff", ":FuzzyFind<CR>", "Find files" },
  },
})
```

### Plugin Equivalents

| Neovim Plugin | Phantom.grim | Status |
|---------------|--------------|--------|
| lazy.nvim | plugin-manager.gza | ✓ Built-in |
| telescope.nvim | fuzzy-finder.gza | ✓ Built-in |
| nvim-tree.lua | file-tree.gza | ✓ Built-in |
| lualine.nvim | statusline.gza | ✓ Built-in |
| bufferline.nvim | bufferline.gza | ✓ Built-in |
| alpha.nvim/dashboard | dashboard.gza | ✓ Built-in |
| which-key.nvim | which-key.gza | ✓ Built-in |
| gitsigns.nvim | git-signs.gza | ✓ Built-in |
| nvim-autopairs | autopairs.gza | ✓ Built-in |
| comment.nvim | comment.gza | ✓ Built-in |
| toggleterm.nvim | terminal.gza | ✓ Built-in |
| nvim-tmux-navigation | tmux.gza | ✓ Built-in |
| copilot.vim | N/A | Use Reaper.grim |
| nvim-cmp | Built-in | ✓ LSP completion |
| nvim-lspconfig | Built-in | ✓ Auto-spawn |
| nvim-treesitter | Built-in | ✓ Grove |

### Keybinding Migration

**Neovim:**
```lua
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
vim.keymap.set("i", "jk", "<Esc>", { noremap = true })
```

**Phantom.grim:**
```ghostlang
-- In init.gza
local phantom = require("plugins.editor.phantom")

phantom.setup({
  keymaps = {
    { "n", "<leader>w", ":w<CR>", "Save" },
    { "i", "jk", "<Esc>", "Exit insert" },
  },
})
```

### Autocmd Migration

**Neovim:**
```lua
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.zig",
  command = "!zig fmt %",
})
```

**Phantom.grim:**
```ghostlang
phantom.setup({
  autocmds = {
    { "BufWritePre", "*.zig", ":ZigFmt" },
  },
})
```

### LSP Migration

**Neovim (nvim-lspconfig):**
```lua
require("lspconfig").zls.setup({})
require("lspconfig").rust_analyzer.setup({})
```

**Phantom.grim:**
```ghostlang
-- Nothing needed! LSP auto-spawns based on file extension
-- Open .zig file → zls starts automatically
-- Open .rs file → rust-analyzer starts automatically
```

### Performance Comparison

| Metric | Neovim (LazyVim) | Phantom.grim | Improvement |
|--------|------------------|--------------|-------------|
| Startup time | 450ms | 45ms | 10x faster |
| Memory usage | 85MB | 28MB | 3x less |
| LSP spawn time | ~2s | <500ms | 4x faster |
| Plugin count | 40+ | 25 | Built-in |

## From LazyVim

LazyVim users will feel right at home! Phantom.grim is directly inspired by LazyVim.

### What's the Same

✓ Leader key = `<Space>`
✓ Fuzzy finder (`<leader>ff`)
✓ Live grep (`<leader>fg`)
✓ File tree (`<leader>ft`)
✓ LSP keybindings (`K`, `gd`, `gr`)
✓ Git integration
✓ Which-key popup
✓ Lazy loading
✓ Similar plugin structure

### What's Different

**Language:**
- LazyVim: Lua
- Phantom.grim: Ghostlang (very similar to Lua)

**Editor:**
- LazyVim: Neovim (Vimscript + Lua)
- Phantom.grim: Grim (Zig + Ghostlang)

**Performance:**
- LazyVim: ~450ms startup
- Phantom.grim: ~45ms startup (10x faster!)

**Distribution:**
- LazyVim: Neovim distro (40+ plugins)
- Phantom.grim: Grim distro (25 built-in plugins)

### Migration Checklist

- [x] Install phantom.grim: `zig build`
- [ ] Copy keybindings from `~/.config/nvim/lua/config/keymaps.lua` to `~/.config/phantom.grim/init.gza`
- [ ] Copy autocmds from `~/.config/nvim/lua/config/autocmds.lua` to init.gza
- [ ] Install LSP servers (same as LazyVim: zls, rust-analyzer, gopls, clangd)
- [ ] Test workflow with sample project
- [ ] Adjust muscle memory for any different keybindings

### Direct Replacements

**LazyVim Extras → Phantom.grim**

| LazyVim Extra | Phantom.grim |
|---------------|--------------|
| `lazyvim.plugins.extras.lang.rust` | Built-in (rust-analyzer) |
| `lazyvim.plugins.extras.lang.go` | Built-in (gopls) |
| `lazyvim.plugins.extras.ui.alpha` | dashboard.gza |
| `lazyvim.plugins.extras.editor.telescope` | fuzzy-finder.gza |
| `lazyvim.plugins.extras.vscode` | N/A (Grim is standalone) |

## From Vim

### Vim Compatibility

Phantom.grim supports **most** Vim keybindings:

✓ Motion: `h` `j` `k` `l` `w` `b` `e` `0` `$` `gg` `G`
✓ Edit: `i` `a` `o` `d` `y` `p` `c` `r` `x`
✓ Visual: `v` (character-wise)
✗ Ex commands: Limited (`:w`, `:q`, `:wq` work)
✗ Macros: Not yet implemented
✗ Registers: Simplified clipboard

### Key Differences from Vim

**No Vimscript:**
- Vim uses Vimscript
- Phantom.grim uses Ghostlang (Lua-like)

**No .vimrc:**
- Vim: `~/.vimrc`
- Phantom.grim: `~/.config/phantom.grim/init.gza`

**Built-in LSP:**
- Vim needs coc.nvim or ALE
- Phantom.grim has native LSP

**Modern Defaults:**
- Syntax highlighting: On by default
- Line numbers: On by default
- Mouse: Enabled by default
- Colors: 24-bit color by default

### Migration Path

1. **Learn modal editing** - Already know this!
2. **Adjust to Ghostlang** - Similar to Vim9script but easier
3. **Embrace LSP** - Let phantom.grim handle it
4. **Use fuzzy finder** - Faster than `:e` and tab-complete

### Vim Muscle Memory Guide

| Vim Habit | Phantom.grim |
|-----------|--------------|
| `:e filename` | `<leader>ff` (fuzzy find) |
| `:bn` `:bp` | `<leader>bn` `<leader>bp` |
| `Ctrl+]` (tags) | `gd` (LSP go-to-definition) |
| `K` (man page) | `K` (LSP hover docs) |
| `:make` | `<leader>cc` (compile) |
| `:grep pattern` | `<leader>fg` (live grep) |

## From VSCode with Vim Extension

### What You'll Love

✓ **No more VSCode lag** - Native Zig editor is instant
✓ **Real modal editing** - Not an extension, core to the editor
✓ **Faster startup** - 45ms vs VSCode's 3+ seconds
✓ **Lower memory** - 28MB vs VSCode's 500MB+
✓ **Native LSP** - Same language servers, faster integration

### What You'll Miss

✗ **Extensions marketplace** - Use Ghostlang plugins instead
✗ **Integrated debugger** - Use terminal debuggers
✗ **GUI settings** - Edit config file manually
✗ **Built-in Git GUI** - Use git commands or terminal tools

### Keybinding Adjustments

**VSCode Vim:**
- `Ctrl+P` - Find files
- `Ctrl+Shift+F` - Search in files
- `Ctrl+\`` - Toggle terminal
- `Ctrl+B` - Toggle sidebar

**Phantom.grim:**
- `<leader>ff` - Find files
- `<leader>fg` - Search in files
- `Ctrl+\`` - Toggle terminal (same!)
- `<leader>ft` - Toggle file tree

### Migration Steps

1. Install phantom.grim
2. Open your VSCode project: `phantom_grim .`
3. Press `<Space>` and wait - which-key shows commands
4. Gradually learn Grim-specific features
5. Customize `~/.config/phantom.grim/init.gza`

## Feature Parity Comparison

### Editing Features

| Feature | Vim | Neovim | LazyVim | Phantom.grim |
|---------|-----|--------|---------|--------------|
| Modal editing | ✓ | ✓ | ✓ | ✓ |
| Text objects | ✓ | ✓ | ✓ | ✓ |
| Macros | ✓ | ✓ | ✓ | ✗ Planned |
| Registers | ✓ | ✓ | ✓ | Simplified |
| Undo tree | ✓ | ✓ | ✓ | Linear |
| Fold | ✓ | ✓ | ✓ | ✗ Planned |
| Visual block | ✓ | ✓ | ✓ | ✗ Planned |

### IDE Features

| Feature | Vim | Neovim | LazyVim | Phantom.grim |
|---------|-----|--------|---------|--------------|
| LSP | Plugin | ✓ | ✓ | ✓ Built-in |
| Auto-complete | Plugin | Plugin | ✓ | ✓ Built-in |
| Diagnostics | Plugin | ✓ | ✓ | ✓ Built-in |
| Tree-sitter | ✗ | ✓ | ✓ | ✓ Grove |
| Fuzzy find | Plugin | Plugin | ✓ | ✓ Built-in |
| Git signs | Plugin | Plugin | ✓ | ✓ Built-in |
| File tree | Plugin | Plugin | ✓ | ✓ Built-in |
| Terminal | ✓ | ✓ | ✓ | ✓ Built-in |
| Debugger | Plugin | Plugin | Plugin | ✗ |

### Performance

| Feature | Vim | Neovim | LazyVim | Phantom.grim |
|---------|-----|--------|---------|--------------|
| Startup time | 100ms | 200ms | 450ms | 45ms ⚡ |
| Memory usage | 30MB | 50MB | 85MB | 28MB ⚡ |
| LSP spawn | N/A | 2s | 2s | 500ms ⚡ |
| Large files | Fast | Fast | Medium | Fast ⚡ |

## Common Pain Points

### "Where's my plugin?"

**Problem:** Can't find Neovim plugin equivalent.

**Solution:** Check built-in plugins first:
```bash
ls /data/projects/phantom.grim/plugins/
```

Most common plugins are built-in. For others, write a Ghostlang plugin or request it.

### "Config file syntax error"

**Problem:** Ghostlang syntax slightly different from Lua.

**Solution:** Check examples:
```bash
cat /data/projects/phantom.grim/plugins/*/init.gza
```

Common differences:
- Lua: `require("module")`
- Ghostlang: `require("module")` (same!)
- Lua: `local x = { y = 1 }`
- Ghostlang: `var x = { y = 1 }` or `local x = { y = 1 }` (both work!)

### "LSP not starting"

**Problem:** LSP server not installed or wrong name.

**Solution:** Check which servers phantom.grim looks for:
- Zig → `zls`
- Rust → `rust-analyzer`
- Go → `gopls`
- C/C++ → `clangd`
- TypeScript → `typescript-language-server`
- Ghostlang → `ghostls`

Ensure these are in PATH:
```bash
which zls
which rust-analyzer
# etc.
```

### "Keybinding doesn't work"

**Problem:** Mapped key doesn't do anything.

**Solution:** Check which-key for conflicts:
```
Press <Space> and wait - shows all bindings
```

Add custom binding in init.gza:
```ghostlang
phantom.setup({
  keymaps = {
    { "n", "<leader>x", ":MyCommand<CR>", "My command" },
  },
})
```

### "Missing Vim feature"

**Problem:** Specific Vim feature not implemented.

**Solution:** Check roadmap or file an issue:
- [GitHub Issues](https://github.com/ghostkellz/phantom.grim/issues)
- [TODO.md](../TODO.md)

Common missing features:
- Macros (planned)
- Visual block mode (planned)
- Undo tree (planned)
- Fold (planned)

## What You'll Miss

Honest assessment of what Phantom.grim **doesn't** have yet:

### From Neovim

- **Lua JIT** - Ghostlang is interpreted, not JIT compiled
- **Massive plugin ecosystem** - 1000+ Neovim plugins vs 25 built-in
- **Vim compatibility layer** - Some obscure Vim commands missing
- **Extensive documentation** - `:help` in Neovim is comprehensive
- **Remote editing** - No `nvim --remote` equivalent yet

### From LazyVim

- **Pre-configured extras** - LazyVim has 50+ extras for different languages
- **Update system** - LazyVim checks for plugin updates automatically
- **Community configs** - Many users share LazyVim configs

### From Vim

- **Decades of polish** - Vim has been refined since 1991
- **Universal availability** - Vim on every system, Grim needs install
- **Vimscript** - Some still prefer Vimscript over modern languages
- **Ex commands** - Hundreds of built-in commands

## What You'll Gain

Why switch to Phantom.grim:

### Performance

⚡ **10x faster startup** - 45ms vs LazyVim's 450ms
⚡ **3x less memory** - 28MB vs LazyVim's 85MB
⚡ **Instant LSP** - Auto-spawn in <500ms
⚡ **Written in Zig** - Native performance, no VM overhead

### Modern Stack

🦎 **Zig codebase** - Memory-safe, fast, maintainable
🌳 **Grove (Tree-sitter)** - Better syntax highlighting
📜 **Ghostlang** - Modern scripting language, Lua-like
🔌 **Native plugins** - Tight integration with editor

### Better Defaults

✓ **LSP out-of-box** - No config needed
✓ **Fuzzy finding** - FZF-like experience built-in
✓ **Git integration** - Inline diffs, blame, commit helpers
✓ **Modern UI** - Statusline, bufferline, file tree, dashboard
✓ **Theme system** - Beautiful themes included

### Simplicity

🎯 **One language** - Ghostlang for everything (vs Vimscript + Lua + Python)
🎯 **Fewer plugins** - 25 built-in vs 40+ to install
🎯 **Auto-configuration** - LSP, syntax, git all automatic
🎯 **Single binary** - No node_modules, no Python deps

### Innovation

🚀 **Native LSP** - Not bolted on, built-in from day 1
🚀 **Lazy loading** - Optimized startup without sacrifice
🚀 **Reaper.grim** - AI assistant (Copilot, Claude, GPT, Ollama)
🚀 **Active development** - New features weekly

## Migration Checklist

- [ ] Install Phantom.grim: `zig build`
- [ ] Install LSP servers (zls, rust-analyzer, etc.)
- [ ] Create `~/.config/phantom.grim/init.gza`
- [ ] Copy keybindings from old config
- [ ] Copy autocmds from old config
- [ ] Test with sample project
- [ ] Install grim-pkg for plugin management
- [ ] Learn which-key (`<Space>` + wait)
- [ ] Explore built-in plugins (`ls plugins/`)
- [ ] Customize theme (ghost-hacker-blue or tokyonight-moon)
- [ ] Set up tmux integration (if using tmux)
- [ ] Configure Git workflow
- [ ] Install Reaper.grim for AI assistance
- [ ] Join community / star on GitHub

## Getting Help

**Resources:**
- [QUICKSTART.md](QUICKSTART.md) - 5-minute setup
- [USER_GUIDE.md](USER_GUIDE.md) - Comprehensive guide
- [GitHub Issues](https://github.com/ghostkellz/phantom.grim/issues)
- [Example Configs](../examples/)

**Common Questions:**

**Q: Will my Neovim config work?**
A: No, but it's easy to migrate. Ghostlang is similar to Lua.

**Q: Can I use Vim plugins?**
A: No, use Ghostlang plugins. Most common ones are built-in.

**Q: Is Phantom.grim stable?**
A: Experimental but usable. v1.0 release coming soon.

**Q: Can I contribute?**
A: Yes! See [CONTRIBUTING.md](../CONTRIBUTING.md).

## Next Steps

1. Read [QUICKSTART.md](QUICKSTART.md) for immediate setup
2. Read [USER_GUIDE.md](USER_GUIDE.md) for full documentation
3. Try phantom.grim for a day on a small project
4. Gradually migrate keybindings and workflow
5. Give feedback via GitHub issues

Welcome to Phantom.grim! 👻✨

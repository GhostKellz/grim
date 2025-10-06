# Grim

<div align="center">
  <img src="assets/icons/grim-logo.png" alt="grim logo" width="175" height="175">

**Lightweight, Zig-powered IDE/editor with Vim soul and modern brains.**

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-yellow?logo=zig)
![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-orange?logo=zig)
![ghostlang](https://img.shields.io/badge/Plugins-ghostlang-navyblue)
![tree-sitter](https://img.shields.io/badge/Parsing-TreeSitter-green)
![lsp](https://img.shields.io/badge/LanguageServer-LSP-orange)
![vim motions](https://img.shields.io/badge/Keybindings-Vim%20Motions-blue)

</div>

---

## Overview

**Grim** is a modern, performant alternative to Vim/Neovim.  
Built in **Zig**, it preserves the **modal editing power** of Vim while providing:

- **Instant startup** and low memory footprint  
- **Ghostlang plugin system** (typed, modern alternative to Lua)  
- **Tree-sitter integration** for fast, incremental syntax parsing  
- **First-class LSP support** out of the box  
- **TUI first**, with future GPU-accelerated GUI support  

Our goal is simple:  
**Keep the Vim motions, drop the baggage, and make editing blazing fast.**

---

## Features

- 🔑 Modal editing with Vim motions
- 🪶 Rope-based buffer for huge files
- 🌲 Tree-sitter 0.25.10 highlighting and navigation across 14 languages
- 🎯 **Jump to definition** (`gd`) - Fast tree-sitter-based code navigation
- 🔄 **Symbol rename** - Rename symbols within current file
- 🎨 **Dynamic theme system** - Customizable color schemes (dark/light themes)
- 📡 Built-in LSP client (hover, diagnostics, goto, completion)
- ⚡ Ghostlang configuration and plugins
- 🔌 Remote plugin protocol (any language over stdio/JSON)
- 📂 Fuzzy finder, quickfix list, registers, macros
- ⚙️ **Graceful fallbacks** - Syntax highlighting works even without tree-sitter  

### Supported languages (via Grove)

Grim bundles Grove's latest tree-sitter toolchain. When you build with `-Dghostlang=true`, you get:

- Zig, Rust, Go
- JavaScript, TypeScript, TSX
- Python, Bash, C, C++
- JSON, TOML, YAML, Markdown
- CMake, HTML, CSS
- Ghostlang utilities (symbols, folding, text objects)

---

## Roadmap

- [x] Rope buffer + undo/redo
- [x] Modal engine + keymaps
- [x] Tree-sitter highlighting (14 Grove grammars + Ghostlang services)
- [x] **Jump to definition** (tree-sitter-based, works across all grammars)
- [x] **Multi-key sequences** (`gd`, `gg`, `dd`, `yy`)
- [x] **Dynamic theme system** (RGB → ANSI 256, dark/light themes)
- [x] **Fallback tokenizer** (graceful degradation when parser unavailable)
- [ ] LSP client async integration (infrastructure complete)
- [ ] Ghostlang plugin runtime
- [ ] Fuzzy finder + file explorer
- [ ] Multi-cursor and macro improvements
- [ ] DAP debugging support  

---

## Getting Started

### Zig Integration
```bash
zig fetch --save https://github.com/ghostkellz/grim/archive/refs/heads/main.tar.gz
# Refresh dependencies (Grove, tree-sitter grammars)
zig build --fetch
```
### Build from source
```bash
git clone https://github.com/ghostkellz/grim.git
cd grim
# Optional: include Ghostlang + Grove (tree-sitter 0.25.10)
zig build run -Dghostlang=true
```
---

### Configuration 

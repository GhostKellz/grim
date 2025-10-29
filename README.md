# Grim

<div align="center">
  <img src="assets/icons/grim-reaper-distro.png" alt="grim logo" width="128" height="128">

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
- 🪶 Rope-based buffer for huge files  :
- 🌲 Tree-sitter 0.25.10 highlighting and navigation across 14 languages  
- 📡 Built-in LSP client (hover, diagnostics, goto, completion)  
- ⚡ Ghostlang configuration and plugins  
- 🔌 Remote plugin protocol (any language over stdio/JSON)  
- 📂 Fuzzy finder, quickfix list, registers, macros  

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
- [x] LSP client (hover, diagnostics, goto, completion)
- [x] Ghostlang plugin runtime + hot reload
- [x] Plugin system with dependency resolution
- [x] Multi-cursor editing (select next/all occurrences)
- [x] Macro recording and playback with persistence
- [x] Snippet system with tab stops
- [x] DAP debugging client
- [x] Visual mode with full command set
- [x] Command mode (:w, :q, :wq, /search, s/find/replace)
- [x] Fold operations (za, zR, zM)
- [x] Git integration (blame, diff panels)
- [x] File tree explorer UI with git status
- [x] Fuzzy finder with scoring algorithm
- [x] Project-wide search & replace UI  

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

Grim can be configured via JSON. Create `~/.config/grim/config.json`:

```bash
# Copy the example configuration
mkdir -p ~/.config/grim
cp config.example.json ~/.config/grim/config.json

# Edit to your preferences
$EDITOR ~/.config/grim/config.json
```

See [`config.example.json`](config.example.json) for all available options.

**Key Configuration Options:**
- **Editor**: Tab width, line numbers, auto-save
- **Theme**: Color scheme and syntax highlighting
- **LSP**: Language server configuration per filetype
- **Keybindings**: Custom keymaps and leader key
- **Plugins**: Enable/disable Ghostlang plugins

---

### Contributing

We welcome contributions! See [`CONTRIBUTING.md`](CONTRIBUTING.md) for:
- Development setup
- Code style guidelines
- Architecture overview
- Pull request process

 

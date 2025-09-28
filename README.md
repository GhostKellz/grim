# Grim

<div align="center">
  <img src="assets/icons/grim.png" alt="grim logo" width="128" height="128">

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
- 🌲 Tree-sitter highlighting and navigation  
- 📡 Built-in LSP client (hover, diagnostics, goto, completion)  
- ⚡ Ghostlang configuration and plugins  
- 🔌 Remote plugin protocol (any language over stdio/JSON)  
- 📂 Fuzzy finder, quickfix list, registers, macros  

---

## Roadmap

- [x] Rope buffer + undo/redo  
- [x] Modal engine + keymaps  
- [ ] Tree-sitter highlighting (Zig, Rust, JS, JSON, TOML)  
- [ ] LSP client (Zig + Rust servers first)  
- [ ] Ghostlang plugin runtime  
- [ ] Fuzzy finder + file explorer  
- [ ] Multi-cursor and macro improvements  
- [ ] DAP debugging support  

---

## Getting Started

### Zig Integration
```bash
zig fetch --save https://github.com/ghostkellz/grim/archive/refs/heads/main.tar.gz
```
### Build from source
```bash
git clone https://github.com/ghostkellz/grim.git
cd grim
zig build run
```
---

### Configuration 

# Grim Core vs Phantom.grim - Feature Distribution

**Analysis based on cktech config**
**Goal:** Determine what goes in Grim core vs Phantom.grim plugins

---

## 🎯 Design Philosophy

**Grim Core = Vim + Modern IDE Essentials**
- Fast, stable, batteries-included
- No external deps for core features
- Written in Zig for performance

**Phantom.grim = LazyVim Equivalent**
- Plugin ecosystem (Ghostlang .gza)
- User customization
- Optional enhancements

---

## ✅ GRIM CORE (Built-in, No Plugins Needed)

### 1. **LSP Integration** ✅ DONE
- [x] Multi-language support (ghostls, zls, rust-analyzer, ts-server)
- [x] Auto-spawn servers by file extension
- [x] Hover documentation (`K`)
- [x] Goto definition (`gd`)
- [ ] **TODO: Hover response parsing and display**
- [ ] Diagnostics display (inline squiggles)
- [ ] Code completion (basic)
- [ ] Signature help

**Why Core:** Essential for modern coding, already in progress

---

### 2. **Tree-sitter via Grove** ✅ DONE
- [x] Syntax highlighting (14 languages)
- [x] Smart text objects
- [ ] Fold expressions
- [ ] Incremental selection

**Why Core:** Already integrated, Grim's differentiator

---

### 3. **Git Integration** 🔥 HIGH PRIORITY
From your config: `gitsigns.lua`, `neogit.lua`

**Built into Core:**
- [ ] Git blame inline (like gitsigns)
- [ ] Hunk navigation (`]h`, `[h`)
- [ ] Stage/unstage hunks
- [ ] Git status in status line
- [ ] Diff view

**Why Core:** You use this constantly, should be zero-config

---

### 4. **Fuzzy Finding (Telescope)** 🔥 HIGH PRIORITY
From your config: `telescope.lua`

**Built into Core:**
- [ ] File finder (`<leader>ff`)
- [ ] Grep in files (`<leader>fg`)
- [ ] Buffer switcher (`<leader>fb`)
- [ ] Recent files (`<leader>fr`)
- [ ] LSP symbols (`<leader>fs`)

**Implementation:** Use Zig FZF algorithm (no external dep)

**Why Core:** Core workflow, used 100x/day

---

### 5. **File Navigation** 🔥 HIGH PRIORITY
From your config: `harpoon.lua`, file explorer

**Built into Core:**
- [ ] Harpoon-style pinned files (1-5 quick jump)
- [ ] File tree (`:Ex` equivalent)
- [ ] Oil.nvim-style edit filesystem as buffer

**Why Core:** Navigation is fundamental

---

### 6. **Undo Tree** ⚡ MEDIUM PRIORITY
From your config: `undotree.lua`

**Built into Core:**
- [ ] Persistent undo
- [ ] Visual undo tree (`<leader>u`)
- [ ] Time travel

**Why Core:** Rope already has undo, just need UI

---

### 7. **Which-key** ⚡ MEDIUM PRIORITY
From your config: `whichkey`

**Built into Core:**
- [ ] Popup showing available keybindings
- [ ] Leader key menu
- [ ] Searchable command palette

**Why Core:** Discoverability for new users

---

### 8. **Auto-pairs & Indentation** ⚡ MEDIUM PRIORITY
From your config: `enhancements.lua`

**Built into Core:**
- [ ] Auto-close brackets/quotes
- [ ] Smart indentation
- [ ] Indentation guides (visual lines)

**Why Core:** Basic editing QoL

---

### 9. **Status Line** ✅ PARTIAL
Currently have basic status line

**Enhanced:**
- [ ] Git branch
- [ ] LSP status (⚡ ghostls ✓)
- [ ] File type
- [ ] Cursor position
- [ ] Macro recording indicator

**Why Core:** Always visible, should look good

---

### 10. **Multi-LSP Support** 🔥 HIGH PRIORITY

**Auto-detect and configure:**
- [x] `.gza` → ghostls
- [x] `.zig` → zls
- [x] `.rs` → rust-analyzer
- [ ] `.ts/.js` → typescript-language-server
- [ ] `.py` → pyright
- [ ] `.go` → gopls
- [ ] `.c/.cpp` → clangd

**Implementation:** Expand `server_manager.zig` autoSpawn()

**Why Core:** You work in multiple languages

---

## 🔌 PHANTOM.GRIM PLUGINS (Ghostlang .gza)

### User-Installable via Phantom

1. **AI Coding Assistants**
   - Zeke.grim (Claude Code for Grim)
   - Copilot integration
   - Inline completions

2. **Advanced Git UI**
   - Neogit (full git client)
   - Diffview (3-way merge)
   - Git graph

3. **Testing Frameworks**
   - Neotest adapters
   - Test runner UI
   - Coverage display

4. **Debugging (DAP)**
   - Debug adapter protocol
   - Breakpoints, watches
   - Virtual text

5. **Colorschemes**
   - Tokyo Night
   - Catppuccin
   - Gruvbox
   - Custom themes

6. **Language-Specific**
   - Go tools
   - Rust crates
   - Web dev (Tailwind, etc.)

7. **Productivity**
   - TODO comments
   - Session management
   - Project templates

8. **UI Enhancements**
   - Noice.nvim (fancy popups)
   - Notify (notifications)
   - Symbols outline

---

## 🚀 IMPLEMENTATION ROADMAP

### Phase 1: Core Features (Next 2-4 weeks)
1. **Hover Response Parsing** (NOW)
   - Parse LSP JSON responses
   - Display in TUI popup
   - Handle markdown formatting

2. **Multi-LSP** (Week 1)
   - Expand server_manager for all languages
   - Auto-install LSP servers? (optional)

3. **Git Integration** (Week 2)
   - Git blame inline
   - Hunk navigation
   - Basic git commands

4. **Fuzzy Finder** (Week 2-3)
   - Zig FZF implementation
   - File/buffer/grep search
   - Keybindings

5. **File Navigation** (Week 3)
   - Harpoon-style pinning
   - File tree
   - Quick jump (1-5)

6. **Status Line** (Week 4)
   - Git branch
   - LSP status
   - Polish UI

### Phase 2: Polish (1-2 weeks)
- Which-key command palette
- Undo tree UI
- Auto-pairs
- Diagnostics display

### Phase 3: Phantom.grim (Parallel)
- Plugin loader (.gza)
- Registry system
- Zeke.grim
- Community plugins

---

## 💡 KEY DECISIONS

### ✅ YES - Built into Core
- LSP (multi-language)
- Tree-sitter/Grove
- Git integration
- Fuzzy finding
- File navigation
- Undo tree
- Which-key
- Status line
- Auto-pairs

### ❌ NO - Phantom.grim Plugins
- AI assistants (Zeke, Copilot)
- Advanced git UIs (Neogit)
- Testing frameworks
- Debugging (DAP)
- Themes
- Language-specific tools
- Optional UI candy

---

## 🎯 SUCCESS CRITERIA

**Grim Core should be:**
1. **Zero-config** - Works out of box for common workflows
2. **Fast** - Zig native, no plugin overhead
3. **Complete** - Cover 90% of your daily usage
4. **Extensible** - Phantom.grim for the other 10%

**User Experience:**
```bash
# Install Grim
curl -fsSL grim.sh | bash

# Open a project
grim .

# Everything just works:
# - LSP (ghostls/zls/rust-analyzer auto-detected)
# - Git integration
# - Fuzzy finding
# - File navigation
# - Beautiful UI

# Want more? Add Phantom.grim
grim --init phantom
# Now you have lazy.vim equivalent
```

---

## 📊 Feature Matrix

| Feature | Core | Phantom | Priority | Status |
|---------|------|---------|----------|--------|
| LSP (multi-lang) | ✅ | - | 🔥 | 90% |
| Tree-sitter | ✅ | - | ✅ | ✅ |
| Git integration | ✅ | Advanced UI | 🔥 | TODO |
| Fuzzy finder | ✅ | - | 🔥 | TODO |
| File nav (Harpoon) | ✅ | - | 🔥 | TODO |
| Undo tree | ✅ | - | ⚡ | TODO |
| Which-key | ✅ | - | ⚡ | TODO |
| Auto-pairs | ✅ | - | ⚡ | TODO |
| Diagnostics | ✅ | - | 🔥 | TODO |
| Zeke (AI) | - | ✅ | ⚡ | Planning |
| Neogit | - | ✅ | ⚡ | Planning |
| DAP | - | ✅ | ⏳ | Future |
| Themes | - | ✅ | ⚡ | Phantom |

---

## 🛠 NEXT STEPS

### Immediate (This Week)
1. ✅ Finish LSP hover parsing
2. ✅ Multi-LSP support (zls, rust-analyzer)
3. Start Git integration

### Short-term (2-4 weeks)
- Fuzzy finder
- File navigation
- Status line polish

### Medium-term (1-2 months)
- Which-key
- Undo tree UI
- Diagnostics display
- Phantom.grim plugin system

---

**TL;DR:** Grim should be **LazyVim without plugins**. Everything you use daily should work out-of-box. Phantom.grim is for customization and advanced features.

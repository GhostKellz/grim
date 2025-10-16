# Grim Development Roadmap

## Current State (Oct 2025)

### Grim Editor Core (~50% Complete)
**Fully Working**:
- ✅ Core rope buffer (production-ready, 95% complete)
- ✅ LSP client (functional, 85% complete)
- ✅ Syntax highlighting via Grove/tree-sitter (14 languages, 80% complete)
- ✅ Buffer management with undo/redo (PhantomBuffer, 90% complete)
- ✅ Multi-buffer support (BufferManager, 75% complete)
- ✅ Plugin API structure (70% complete - API defined, not wired)
- ✅ Theme system with dynamic colors
- ✅ AI client (Omen integration, 65% complete)

**Partially Working**:
- ⚠️ Editor core (60% - basic motions work, many stubs)
- ⚠️ Vim commands (50% - framework complete, many placeholders)
- ⚠️ LSP→UI integration (50% - client works, UI callbacks incomplete)
- ⚠️ TUI rendering (40% - relies on phantom framework)

**Stubbed/Minimal**:
- ❌ Ghostlang VM integration (10% - structure only, NOT wired up)
- ❌ File operations (30% - fuzzy finder, file tree mostly stubs)
- ❌ Git integration (20% - functions defined but empty)
- ❌ Ex commands (0% - :w, :q, :e not implemented)
- ❌ Text objects (20% - many return placeholder values)
- ❌ Visual mode operations (30% - selection works, operations stubbed)

### Phantom.grim Distribution (Exists!)
**Status**: Fully architected LazyVim-style config with 25 plugins (8,732 lines)

**Plugins Already Built** (in /data/projects/phantom.grim/plugins/):
- ✅ file-tree.gza (1197 lines) - Neo-tree style explorer
- ✅ fuzzy-finder.gza (733 lines) - Telescope-like search
- ✅ git-signs.gza (497 lines) - Gutter diff signs
- ✅ statusline.gza (477 lines) - Enhanced status bar
- ✅ autopairs.gza (179 lines) - Auto-close brackets
- ✅ comment.gza (288 lines) - gcc/gc commenting
- ✅ which-key.gza (364 lines) - Keybinding discovery
- ✅ lsp-config.gza (135 lines) - LSP server configs
- ✅ 17 more plugins (themes, terminal, dashboard, etc.)

**Phantom Infrastructure**:
- ✅ Plugin manager with lazy loading
- ✅ Dependency resolution
- ✅ Event/filetype/command/key triggers
- ✅ Default keybindings (LazyVim-inspired)
- ✅ init.gza bootstrap system

### What Actually Needs Work

**CRITICAL (blocks basic usage)**:
1. Command-line mode (`:` is not implemented - can't do :w, :q, :e)
2. Text objects (iw, i{, i", etc. are stubs - d{motion} doesn't work)
3. Visual mode operations (selection works, but d/c/y in visual are placeholders)
4. Yank/paste system (yy/p are stubs)

**HIGH PRIORITY (needed for real work)**:
5. LSP→UI wiring (client works, but no hover tooltips/diagnostics display)
6. Search/replace (/, ?, n, :%s not implemented)
7. File operations (fuzzy finder, file tree are stubs)
8. Git operations (status, diff, hunks are stubs)

**MEDIUM PRIORITY (nice to have)**:
9. Phantom.grim integration testing (plugins exist, need to verify they work)
10. Window splits
11. Advanced features (macros, marks, etc.)

**NOTE**: Ghostlang VM IS wired (main.zig:104-131), plugins CAN load. The real work is making Vim actually functional!

---

## Phase 1: Ex Commands & Core Usability (Priority: CRITICAL)

**Goal**: Make grim actually usable for basic editing

### 1.1 Ex Command Infrastructure
**Goal**: Implement command-line mode and essential Ex commands

**Tasks**:
- [ ] Implement command-line mode (`:` activates, shows prompt at bottom)
- [ ] Command parser (split by whitespace, handle quotes)
- [ ] Command registry and dispatcher
- [ ] Command completion (Tab in command mode)
- [ ] Command history (up/down arrows)

**Estimated**: 2 days
**Status**: Currently 0% - command mode is TODO in editor.zig:907

### 1.2 File Commands
**Goal**: Basic file operations via Ex commands

**Tasks**:
- [ ] `:w` - Save current buffer
- [ ] `:w <file>` - Save as
- [ ] `:wa` - Save all buffers
- [ ] `:e <file>` - Edit file (open in buffer)
- [ ] `:e!` - Reload file, discard changes
- [ ] File path completion for `:e` and `:w`

**Dependencies**: Command infrastructure (1.1)
**Estimated**: 1-2 days

### 1.3 Quit Commands
**Goal**: Exit editor properly

**Tasks**:
- [ ] `:q` - Quit (warn if unsaved)
- [ ] `:q!` - Force quit
- [ ] `:qa` - Quit all
- [ ] `:qa!` - Force quit all
- [ ] `:wq` - Save and quit
- [ ] `:x` - Save if modified, then quit

**Dependencies**: Command infrastructure (1.1)
**Estimated**: 1 day

### 1.4 Buffer Commands
**Goal**: Navigate between open buffers

**Tasks**:
- [ ] `:bn` `:bnext` - Next buffer
- [ ] `:bp` `:bprev` - Previous buffer
- [ ] `:bd` `:bdelete` - Delete buffer
- [ ] `:bd!` - Force delete buffer
- [ ] `:ls` `:buffers` - List open buffers
- [ ] `:b <n>` - Switch to buffer by number
- [ ] `:b <name>` - Switch to buffer by partial name match

**Dependencies**: Command infrastructure (1.1), BufferManager (exists)
**Estimated**: 1-2 days

---

## Phase 2: Complete Vim Implementation (Priority: HIGH)

### 2.1 Text Objects (CRITICAL)
**Goal**: Implement all standard Vim text objects

**Currently Stubbed** (return placeholder ranges):
- [ ] `iw/aw` - Inner/around word
- [ ] `i(/a(, i{/a{, i[/a[` - Bracket text objects
- [ ] `i"/a", i'/a'` - Quote text objects
- [ ] `it/at` - Tag text objects (XML/HTML)
- [ ] `ip/ap` - Paragraph text objects
- [ ] `is/as` - Sentence text objects

**Dependencies**: None (core vim)
**Estimated**: 3-4 days
**Impact**: CRITICAL - enables d{motion}, c{motion}, y{motion}

### 2.2 Visual Mode Operations
**Goal**: Complete visual mode functionality

**Tasks**:
- [ ] Visual mode delete/change/yank (currently placeholders)
- [ ] Visual block mode (Ctrl+V)
- [ ] Visual block insert/append (I/A in block mode)
- [ ] Visual mode indent/outdent (>, <)
- [ ] Visual mode case change (u, U, ~)
- [ ] Visual mode sort

**Dependencies**: Text objects (2.1)
**Estimated**: 3-4 days

### 2.3 Search and Replace
**Goal**: Find, navigate, and replace text

**Tasks**:
- [ ] `/pattern` - Forward search
- [ ] `?pattern` - Backward search
- [ ] `n` - Next match
- [ ] `N` - Previous match
- [ ] `*` - Search word under cursor forward
- [ ] `#` - Search word under cursor backward
- [ ] `:s/find/replace/` - Substitute on current line
- [ ] `:%s/find/replace/g` - Substitute in whole file
- [ ] `:'<,'>s/find/replace/g` - Substitute in visual selection
- [ ] Regex support (basic POSIX patterns)
- [ ] Search highlighting
- [ ] Incremental search

**Dependencies**: Command mode (Phase 1.1)
**Estimated**: 4-5 days

### 2.4 Yank/Paste System
**Goal**: Complete copy/paste functionality

**Currently**: Yank/paste are placeholder implementations

**Tasks**:
- [ ] Implement register system (", +, *, 0-9, a-z)
- [ ] `yy` - Yank line
- [ ] `y{motion}` - Yank motion (requires text objects)
- [ ] `p` - Paste after cursor
- [ ] `P` - Paste before cursor
- [ ] `"{register}y` - Yank to register
- [ ] `"{register}p` - Paste from register
- [ ] System clipboard integration (+, *)
- [ ] Visual mode yank

**Dependencies**: Text objects (2.1), registers
**Estimated**: 2-3 days

---

## Phase 3: LSP Integration (Priority: HIGH)

**Goal**: Make LSP actually work in the editor

### 3.1 LSP→UI Wiring
**Goal**: Display LSP results in the UI

**Currently**: LSP client works, but responses don't show in UI

**Tasks**:
- [ ] Wire hover response to show tooltip/popup
- [ ] Display diagnostics in gutter and inline
- [ ] Show completion menu with LSP results
- [ ] Display signature help during function calls
- [ ] Show code actions menu (quick fixes)
- [ ] Implement goto-definition navigation
- [ ] Show references list

**Dependencies**: LSP client (exists), popup rendering
**Estimated**: 4-5 days

### 3.2 LSP Server Lifecycle
**Goal**: Auto-start LSP servers for file types

**Tasks**:
- [ ] Auto-spawn zls for .zig files
- [ ] Auto-spawn rust-analyzer for .rs files
- [ ] Auto-spawn ghostls for .gza files
- [ ] Server health monitoring and restart
- [ ] Show LSP status in statusline
- [ ] `:LspInfo` command to show active servers
- [ ] `:LspRestart` command

**Dependencies**: Server manager (exists in lsp/server_manager.zig)
**Estimated**: 3-4 days

### 3.3 LSP Features
**Goal**: Complete LSP feature set

**Tasks**:
- [ ] Rename symbol (`:LspRename`)
- [ ] Format document (`:LspFormat`)
- [ ] Format range (visual mode format)
- [ ] Organize imports
- [ ] Inlay hints display
- [ ] Semantic tokens (enhanced highlighting)
- [ ] Call hierarchy
- [ ] Type hierarchy

**Dependencies**: LSP→UI wiring (3.1)
**Estimated**: 5-6 days

---

## Phase 4: Phantom.grim Integration (Priority: MEDIUM)

**NOTE**: Phantom.grim already exists with 25 plugins! Just needs to be connected to working grim.

### 4.1 Wire Phantom Plugins to Grim
**Goal**: Make existing phantom.grim plugins functional

**Tasks**:
- [x] Phantom plugins exist (file-tree, fuzzy-finder, git-signs, etc.) - DONE
- [ ] Test phantom.grim/init.gza loads correctly
- [ ] Verify plugin manager triggers work (events, filetypes, commands, keys)
- [ ] Test lazy loading system
- [ ] Ensure all 25 plugins activate properly
- [ ] Fix any bridge function incompatibilities

**Dependencies**: Ghostlang VM (Phase 1.1), Bridge functions (Phase 1.1)
**Estimated**: 2-3 days

### 4.2 Complete Missing Grim Features for Phantom
**Goal**: Implement Grim core features that plugins depend on

**Required for Phantom Plugins**:
- [ ] Implement fuzzy finding in Grim (for fuzzy-finder.gza)
- [ ] Implement file tree traversal (for file-tree.gza)
- [ ] Implement git operations (for git-signs.gza)
- [ ] Complete window splitting (for terminal.gza, splits)
- [ ] Complete buffer picker UI (for bufferline.gza)

**Dependencies**: File operations (Phase 1.4), Git integration
**Estimated**: 5-6 days

### 4.3 Grim Tutor (from Phantom)
**Goal**: Enable interactive tutorial

**Tasks**:
- [ ] Review phantom.grim/runtime/defaults/grim-tutor/ structure
- [ ] Implement tutor framework runner in Grim
- [ ] Add :GrimTutor command
- [ ] Add grim --tutor CLI flag
- [ ] Validate lesson progression works

**Dependencies**: Command mode (Phase 2.3)
**Estimated**: 3-4 days

---

## Phase 5: Performance & Polish (Priority: LOW)

### 5.1 Startup Optimization
**Goal**: <10ms startup time

**Tasks**:
- [ ] Profile startup with zsync runtime
- [ ] Lazy-load plugins by default
- [ ] Optimize rope initialization
- [ ] Cache tree-sitter parsers
- [ ] Benchmark vs Neovim

**Estimated**: 3-4 days

### 5.2 Rendering Optimization
**Goal**: 60 FPS rendering for large files

**Tasks**:
- [ ] Implement viewport culling (only render visible lines)
- [ ] Optimize tree-sitter highlight caching
- [ ] Profile render loop
- [ ] Add fps counter (debug mode)

**Estimated**: 3-4 days

### 5.3 Memory Optimization
**Goal**: <50MB for typical editing session

**Tasks**:
- [ ] Profile memory usage with allocator tracking
- [ ] Optimize undo stack memory (diff-based)
- [ ] Free unused tree-sitter trees
- [ ] Add arena allocators for per-frame allocations

**Estimated**: 2-3 days

---

## Phase 6: Advanced Features (Priority: LOW)

### 6.1 Multi-Cursor Editing
**Goal**: Visual block multi-cursor like Vim

**Tasks**:
- [ ] Wire PhantomBuffer multi-cursor to visual block mode
- [ ] Implement Ctrl+V block selection
- [ ] Implement I/A for block insert/append
- [ ] Sync all cursors on edit operations

**Estimated**: 3-4 days

### 6.2 DAP Debugging Support
**Goal**: Debugger integration

**Tasks**:
- [ ] Implement DAP client
- [ ] Add debugger UI (breakpoints, variables, stack)
- [ ] Support Zig/Rust debuggers (lldb)
- [ ] Create dap.gza plugin

**Estimated**: 7-10 days

### 6.3 Git Integration
**Goal**: First-class git support

**Tasks**:
- [ ] Implement git diff view
- [ ] Add git blame
- [ ] Integrate lazygit (external TUI)
- [ ] Create git.gza core plugin

**Estimated**: 4-5 days

---

## Dependencies Graph

```
Phase 1.1 (Ghostlang Runtime)
  ↓
Phase 2.1 (grim-pkg CLI) & Phase 2.2 (Core Plugins) & Phase 3.1 (Omen Testing)
  ↓
Phase 2.3 (Plugin Registry) & Phase 4.1 (Phantom Distribution)
  ↓
Phase 4.2 (Grim Tutor) & Phase 4.3 (Migration Tools)
  ↓
Phase 5 (Performance) & Phase 6 (Advanced Features)
```

**Critical Path**: Phase 1.1 → Phase 2.1 → Phase 2.2 → Phase 4.1

---

## Success Metrics

### Phase 1 Complete
- [ ] Can edit files with LSP hover/diagnostics
- [ ] Can switch between multiple buffers
- [ ] Can save/load files
- [ ] Undo/redo works reliably

### Phase 2 Complete
- [ ] Can install plugins with grim-pkg
- [ ] 6+ core plugins functional
- [ ] Plugin registry live
- [ ] Dependency resolution works

### Phase 3 Complete
- [ ] AI commit messages working
- [ ] AI code review functional
- [ ] Keybindings intuitive

### Phase 4 Complete
- [ ] phantom.grim installable in one command
- [ ] Tutor teaches new users
- [ ] Migration from Neovim works

### Phase 5 Complete
- [ ] Startup <20ms
- [ ] 60 FPS on 10k line files
- [ ] Memory <100MB for 10 buffers

### Phase 6 Complete
- [ ] Multi-cursor editing works
- [ ] DAP debugging functional
- [ ] Git integration seamless

---

## Phase 5: File Operations & Git (Priority: MEDIUM)

### 5.1 File Tree & Navigation
**Goal**: Implement file operations for phantom plugins

**Currently**: Stubbed in core/fuzzy.zig, ui-tui/file_ops.zig

**Tasks**:
- [ ] Recursive directory traversal
- [ ] File tree data structure
- [ ] Fuzzy matching algorithm (fzf-style scoring)
- [ ] File filtering (gitignore, hidden files)
- [ ] Recent files tracking
- [ ] File watcher for live updates

**Dependencies**: None (core feature)
**Estimated**: 4-5 days

### 5.2 Git Operations
**Goal**: Implement git integration for git-signs.gza plugin

**Currently**: Stubbed in core/git.zig (20% complete)

**Tasks**:
- [ ] Repository detection (.git directory)
- [ ] Current branch detection
- [ ] File status (modified, added, deleted, untracked)
- [ ] Git diff parsing (hunks)
- [ ] Git blame per line
- [ ] Stage/unstage files
- [ ] Stage/unstage hunks
- [ ] Discard changes

**Dependencies**: None (core feature)
**Estimated**: 5-6 days

### 5.3 Window Management
**Goal**: Split windows for multi-file editing

**Currently**: Stubbed in ui-tui/window_manager.zig

**Tasks**:
- [ ] Window splitting (horizontal/vertical)
- [ ] Window navigation (Ctrl+W h/j/k/l)
- [ ] Window resizing
- [ ] Window closing
- [ ] Focus tracking
- [ ] Split rendering in TUI

**Dependencies**: TUI rendering improvements
**Estimated**: 4-5 days

---

## Phase 6: Polish & Performance (Priority: LOW)

### 6.1 Rendering Optimization
- [ ] Viewport culling (only render visible lines)
- [ ] Dirty-rect optimization
- [ ] 60 FPS target for large files
- [ ] Benchmark suite

**Estimated**: 3-4 days

### 6.2 Memory Optimization
- [ ] Arena allocators for per-frame allocations
- [ ] Diff-based undo (reduce memory for undo stack)
- [ ] Free unused tree-sitter trees
- [ ] Profile memory usage

**Estimated**: 2-3 days

### 6.3 Advanced Vim Features
- [ ] Macros (q, @)
- [ ] Marks (m, ')
- [ ] Jump list (Ctrl+O, Ctrl+I)
- [ ] Change list (g;, g,)
- [ ] Dot repeat (.)
- [ ] Repeat counts (3dd, 5yy, etc.)

**Estimated**: 4-5 days

---

## Timeline Estimates (UPDATED)

**Phase 1 (Ex Commands)**: 5-7 days
**Phase 2 (Vim Motions)**: 12-16 days
**Phase 3 (LSP)**: 12-15 days
**Phase 4 (Phantom Integration)**: 10-13 days
**Phase 5 (File Ops & Git)**: 13-16 days
**Phase 6 (Polish)**: 9-12 days

**Total to Usable MVP (Phases 1-2)**: 3-4 weeks
**Total to Feature-Complete (Phases 1-4)**: 8-10 weeks
**Total to Production-Ready (Phases 1-6)**: 12-16 weeks

---

## Current Focus (Immediate Priority)

**CRITICAL PATH**:
1. **Phase 1.1**: Command-line mode infrastructure (BLOCKER for :w, :q, :e)
2. **Phase 1.2-1.4**: File/quit/buffer commands (make editor actually usable)
3. **Phase 2.1**: Text objects (BLOCKER for d{motion}, c{motion}, y{motion})
4. **Phase 2.2**: Visual mode operations (complete existing 30% implementation)

**Once Phases 1-2 are complete, grim becomes a minimally usable Vim-like editor.**

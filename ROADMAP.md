# Grim Editor - Strategic Roadmap

**Status**: Theme system complete. Planning next major features.

---

## Completed Features ✅

### Phase 1: Core Foundation
- [x] **Rope Buffer** - UTF-8 text buffer with zsync integration
- [x] **Modal Editing** - Vim-like normal/insert/visual modes
- [x] **Tree-sitter Syntax** - Grove integration with 15+ languages
- [x] **File I/O** - Loading/saving with error handling
- [x] **Terminal UI** - Phantom-based TUI rendering

### Phase 2: Development Tools
- [x] **LSP Integration** - Async language server support
- [x] **LSP Async** - Non-blocking message processing
- [x] **Fuzzy Finder** - File/buffer/symbol search
- [x] **Git Integration** - Status, diff, blame
- [x] **Harpoon** - Quick file navigation
- [x] **Zap AI** - Ollama-powered code assistance

### Phase 3: Theming & Customization
- [x] **Theme System** - TOML theme loader
- [x] **Ghost Hacker Blue** - Custom default theme
- [x] **Tokyo Night Collection** - 4 official variants (moon, storm, night, day)
- [x] **Theme FFI Bridge** - Ghostlang plugin integration
- [x] **CLI Theme Selection** - `--theme` flag

---

## Roadmap Overview

Five major features remain:

1. **Plugin System** (4-6 weeks) - Ghostlang plugin architecture
2. **Advanced Git** (2-3 weeks) - Diff view, merge conflict resolution
3. **Advanced LSP** (2-3 weeks) - Code actions, refactoring, diagnostics UI
4. **Terminal Integration** (1-2 weeks) - Embedded terminal emulator
5. **Project Management** (1-2 weeks) - Workspace/session management

**Total estimated time**: 10-16 weeks (2.5-4 months)

---

## Feature 1: Plugin System 🔌

**Priority**: HIGH (enables ecosystem)
**Complexity**: VERY HIGH
**Time**: 4-6 weeks

### Why It's Huge

The plugin system touches EVERYTHING:
- Ghostlang runtime integration
- FFI bridge expansion
- Event system architecture
- Hot reload infrastructure
- Security & sandboxing
- Package management
- Plugin discovery & loading
- Configuration API

### Phase 1: Plugin Runtime Foundation (Week 1-2)

**Goal**: Load and execute basic Ghostlang plugins

#### Tasks:
1. **Plugin Manager Infrastructure**
   - Plugin discovery (scan `~/.config/grim/plugins/`)
   - Manifest parsing (`plugin.toml`)
   - Dependency resolution
   - Load order determination
   - Version compatibility checking

2. **Ghostlang Runtime Integration**
   - Initialize Ghostlang VM for plugins
   - Standard library for plugins
   - Memory management (arena allocators)
   - Error handling & reporting

3. **Basic Plugin Lifecycle**
   - `setup()` - Plugin initialization
   - `teardown()` - Cleanup
   - `on_load()` - Lazy loading hooks
   - Health checks

4. **Example Plugins**
   - `hello-plugin.gza` - Minimal example
   - `status-plugin.gza` - Status line customization
   - `keymap-plugin.gza` - Custom keybindings

**Deliverable**: Load and execute simple Ghostlang plugins on startup

---

### Phase 2: Event System (Week 3)

**Goal**: Plugins can react to editor events

#### Tasks:
1. **Event Bus Architecture**
   - Event queue (ring buffer)
   - Event types enum
   - Event handler registration
   - Priority system

2. **Core Events**
   - `BufEnter`, `BufLeave` - Buffer navigation
   - `BufWrite`, `BufRead` - File I/O
   - `InsertEnter`, `InsertLeave` - Mode changes
   - `CursorMoved`, `CursorMovedI` - Cursor movement
   - `TextChanged`, `TextChangedI` - Text edits
   - `LspAttach`, `LspDetach` - LSP lifecycle
   - `ThemeChanged` - Theme switching

3. **Event API for Plugins**
   ```ghostlang
   grim.on("BufWrite", fn(event) {
       print("Saved: " + event.file)
   })

   grim.on("TextChanged", fn(event) {
       // Auto-format on change
       grim.lsp.format()
   })
   ```

4. **Performance**
   - Event batching
   - Debouncing/throttling
   - Async event handlers

**Deliverable**: Plugins can subscribe to and react to editor events

---

### Phase 3: Expanded FFI Bridge (Week 4)

**Goal**: Comprehensive API for plugins

#### Current FFI (Already Implemented):
- Fuzzy finder API (7 functions)
- Git API (13 functions)
- Harpoon API (6 functions)
- LSP API (stub)
- Zap AI API (8 functions)
- Theme API (6 functions)

#### New FFI APIs Needed:

1. **Buffer API**
   ```c
   grim_buffer_get_current()
   grim_buffer_get_line(line_num)
   grim_buffer_set_line(line_num, content)
   grim_buffer_insert(pos, text)
   grim_buffer_delete(start, end)
   grim_buffer_get_content()
   grim_buffer_set_content(text)
   grim_buffer_get_selection()
   ```

2. **Window API**
   ```c
   grim_window_get_current()
   grim_window_split(direction)
   grim_window_focus(window_id)
   grim_window_close(window_id)
   grim_window_get_cursor()
   grim_window_set_cursor(row, col)
   ```

3. **Command API**
   ```c
   grim_command_register(name, callback)
   grim_command_execute(name, args)
   grim_command_list()
   ```

4. **Keymap API**
   ```c
   grim_keymap_register(mode, key, callback)
   grim_keymap_unregister(mode, key)
   grim_keymap_list(mode)
   ```

5. **UI API**
   ```c
   grim_ui_popup(title, content, options)
   grim_ui_input(prompt, default_value)
   grim_ui_confirm(message)
   grim_ui_notify(message, level)
   grim_ui_progress(title, percent)
   ```

**Deliverable**: 40+ FFI functions exposing editor capabilities

---

### Phase 4: Hot Reload & Package Manager (Week 5)

**Goal**: Dynamic plugin loading and updates

#### Tasks:
1. **Hot Reload**
   - File watcher for plugin changes
   - Safe plugin unload/reload
   - State preservation
   - Event handler re-registration

2. **Package Manager (grimpack)**
   ```bash
   grim plugin install telescope-grim
   grim plugin update
   grim plugin list
   grim plugin search <query>
   grim plugin info <name>
   ```

3. **Plugin Registry**
   - GitHub-based registry
   - Plugin manifest format
   - Version resolution
   - Dependency fetching

4. **Security**
   - Plugin sandboxing
   - Permission system
   - Code signing (optional)
   - Safe API boundaries

**Deliverable**: Install community plugins from registry

---

### Phase 5: Plugin Ecosystem (Week 6+)

**Goal**: Build foundational plugins

#### Core Plugins to Build:
1. **telescope.grim** - Advanced fuzzy finder (LazyVim telescope)
2. **nvim-tree.grim** - File explorer sidebar
3. **which-key.grim** - Keybinding hints
4. **lualine.grim** - Status line customization
5. **indent-blankline.grim** - Indentation guides
6. **comment.grim** - Smart commenting
7. **surround.grim** - Surround text objects
8. **auto-pairs.grim** - Bracket/quote auto-pairing

**Deliverable**: 8+ essential plugins ready for users

---

## Feature 2: Advanced Git 🌿

**Priority**: MEDIUM-HIGH
**Complexity**: MEDIUM
**Time**: 2-3 weeks

### Current Git Integration:
- ✅ `git status` - File status
- ✅ `git diff` - Diff generation
- ✅ `git blame` - Line-by-line blame
- ✅ Basic FFI API

### What's Missing:

#### Phase 1: Diff View (Week 1)
- Unified diff viewer (side-by-side or vertical)
- Syntax highlighting in diffs
- Jump to next/previous hunk
- Stage/unstage hunks
- Interactive diff UI

#### Phase 2: Merge Conflict Resolution (Week 1.5)
- Detect merge conflicts in buffers
- Visual conflict markers
- Choose left/right/both actions
- Conflict navigation
- 3-way merge visualization

#### Phase 3: Enhanced Git Commands (Week 2)
- Commit UI with message preview
- Branch management (create, checkout, delete)
- Stash management
- Log viewer with graph
- Staging area UI

#### Phase 4: Git Integration UI (Week 2.5-3)
- Status window (fugitive-style)
- Commit history browser
- File history view
- Blame in sidebar
- Git signs in gutter (live updates)

**Deliverable**: Complete git workflow from within Grim

---

## Feature 3: Advanced LSP 🔧

**Priority**: HIGH
**Complexity**: MEDIUM-HIGH
**Time**: 2-3 weeks

### Current LSP:
- ✅ Async client/server
- ✅ Basic hover
- ✅ Partial completions

### What's Missing:

#### Phase 1: Code Actions & Refactoring (Week 1)
- Code action suggestions
- Quick fixes UI
- Refactoring commands:
  - Rename symbol
  - Extract function
  - Extract variable
  - Inline variable
  - Move to file
- Code action menu (fuzzy picker)

#### Phase 2: Diagnostics UI (Week 1.5)
- Diagnostic signs in gutter
- Diagnostic highlights in buffer
- Diagnostic window/panel
- Jump to next/previous diagnostic
- Diagnostic severity filtering
- Diagnostic quick fixes

#### Phase 3: Enhanced Completions (Week 2)
- Completion menu with kind icons
- Snippet support
- Signature help (parameter hints)
- Documentation preview
- Fuzzy matching in completions
- Completion ranking/sorting

#### Phase 4: Symbol Navigation (Week 2.5)
- Go to definition (improved)
- Go to type definition
- Go to implementation
- Find references
- Document symbols (outline)
- Workspace symbols
- Call hierarchy
- Type hierarchy

#### Phase 5: Formatting & Linting (Week 3)
- Format document
- Format selection
- Format on save
- Range formatting
- Linting integration
- Fix on save

**Deliverable**: Full-featured LSP like VSCode/NeoVim

---

## Feature 4: Terminal Integration 💻

**Priority**: MEDIUM
**Complexity**: MEDIUM
**Time**: 1-2 weeks

### Goal:
Embedded terminal emulator within Grim (like `:terminal` in Vim)

### Phase 1: Terminal Emulator Integration (Week 1)
- Choose terminal library:
  - Option A: libvterm (battle-tested)
  - Option B: Custom VT100 parser
  - Option C: PTY + minimal ANSI parser
- Spawn shell process with PTY
- Terminal buffer type
- Input/output handling
- ANSI escape sequence parsing

### Phase 2: Terminal UI & Keybindings (Week 1.5)
- Terminal window management
- Switch between terminal/editor
- Terminal-specific keybindings
- Copy/paste from terminal
- Terminal scrollback
- Terminal resizing

### Phase 3: Terminal Features (Week 2)
- Multiple terminals
- Named terminals
- Send commands to terminal
- Terminal history
- Terminal sessions
- Split terminal/editor views

**Use Cases**:
- Run build commands
- Interactive REPL
- Git commands
- Test runners
- Shell scripts

**Deliverable**: `:GrimTerminal` command opens embedded shell

---

## Feature 5: Project Management 📁

**Priority**: MEDIUM
**Complexity**: LOW-MEDIUM
**Time**: 1-2 weeks

### Goal:
Workspace/session management for projects

### Phase 1: Project Detection (Week 1)
- Auto-detect project root:
  - `.git` directory
  - `build.zig`, `Cargo.toml`, `package.json`, etc.
  - Custom `.grimproject` marker
- Project-specific configuration
- Project-local plugins

### Phase 2: Session Management (Week 1.5)
- Save/restore sessions:
  - Open buffers
  - Window layout
  - Cursor positions
  - Working directory
- Named sessions
- Session directory (`~/.config/grim/sessions/`)
- Auto-save on exit
- Auto-restore on startup

### Phase 3: Workspace Features (Week 2)
- Recent projects list
- Project switcher (fuzzy finder)
- Project-specific keybindings
- Project-specific LSP configs
- Project-specific themes
- `.grim/` directory support (like `.vscode/`)

**Deliverable**: Seamless multi-project workflow

---

## Implementation Strategy

### Recommended Order:

1. **Plugin System** (4-6 weeks)
   - **Why first**: Unlocks community contributions
   - **Blockers**: None (all deps ready)
   - **Enables**: Everything else can be plugins!

2. **Advanced LSP** (2-3 weeks)
   - **Why second**: High user value, builds on existing LSP
   - **Blockers**: None
   - **Synergy**: Plugins can extend LSP features

3. **Advanced Git** (2-3 weeks)
   - **Why third**: Can be partially built as plugins
   - **Blockers**: None
   - **Synergy**: Git plugins once system ready

4. **Terminal Integration** (1-2 weeks)
   - **Why fourth**: Independent feature, nice-to-have
   - **Blockers**: None
   - **Synergy**: Terminal plugins for customization

5. **Project Management** (1-2 weeks)
   - **Why last**: Ties everything together
   - **Blockers**: None
   - **Synergy**: Project-specific plugin configs

### Parallel Development Opportunities:

- **Week 1-2**: Plugin Runtime + Advanced LSP (different modules)
- **Week 3-4**: Plugin Events + Git Diff View (different contributors)
- **Week 5**: Plugin FFI + Terminal Integration (different systems)

### Milestones:

- **Month 1**: Plugin System Phase 1-3 + LSP Phase 1-2
- **Month 2**: Plugin System Phase 4-5 + LSP Phase 3-5
- **Month 3**: Git + Terminal + Project Management
- **Month 4**: Polish, docs, ecosystem

---

## Success Metrics

### Plugin System:
- ✅ Load 10+ plugins on startup
- ✅ Hot reload without crash
- ✅ 50+ FFI functions exposed
- ✅ Package manager working
- ✅ 5+ community plugins available

### Advanced LSP:
- ✅ Code actions UI complete
- ✅ Diagnostics fully integrated
- ✅ Refactoring works for 3+ languages
- ✅ Completion menu comparable to VSCode

### Advanced Git:
- ✅ Merge conflict resolution works
- ✅ Interactive staging functional
- ✅ Commit workflow smooth
- ✅ Log viewer usable

### Terminal:
- ✅ Shell spawns and works
- ✅ Copy/paste functional
- ✅ Multiple terminals supported
- ✅ Terminal persists in sessions

### Project Management:
- ✅ Auto-detect 10+ project types
- ✅ Session save/restore reliable
- ✅ Project switcher fast
- ✅ Project-specific configs work

---

## Resources Needed

### External Dependencies:
- **Terminal**: libvterm or similar
- **Session Storage**: SQLite (optional)
- **Package Manager**: HTTP client (std.http)

### Documentation:
- Plugin API reference
- FFI function catalog
- Event system guide
- Plugin development tutorial
- Example plugin repository

### Infrastructure:
- Plugin registry (GitHub org)
- Plugin template repository
- CI/CD for plugins
- Plugin testing framework

---

## Risk Assessment

### High Risk:
- **Plugin System complexity** - Might take longer than estimated
  - **Mitigation**: Start with MVP, iterate
- **Ghostlang runtime stability** - Unknown performance at scale
  - **Mitigation**: Extensive testing, benchmarks
- **Security** - Plugins could be malicious
  - **Mitigation**: Sandboxing, permission system

### Medium Risk:
- **Terminal emulator integration** - Platform differences
  - **Mitigation**: Use well-tested library
- **LSP feature parity** - Many edge cases
  - **Mitigation**: Focus on 80% use cases first

### Low Risk:
- **Git integration** - APIs well-defined
- **Project management** - Straightforward file I/O
- **Theme system** - Already working well

---

## Next Steps

### Immediate (This Week):
1. Review and approve this roadmap
2. Choose starting point (recommend: Plugin System Phase 1)
3. Set up tracking (GitHub Projects or similar)
4. Create architecture docs for chosen feature

### Week 1:
1. Implement Plugin Manager infrastructure
2. Design event system architecture
3. Create example plugins
4. Start FFI expansion planning

### Month 1 Goal:
Have basic plugins loading and responding to events.

---

## Questions to Answer

Before starting Plugin System:

1. **Ghostlang VM** - How do we initialize multiple plugin VMs?
2. **Memory Model** - Arena per plugin or shared arena?
3. **Error Handling** - How to handle plugin crashes gracefully?
4. **Config Format** - TOML vs GZA for `plugin.toml`?
5. **Registry** - GitHub-based or custom server?
6. **Versioning** - Semantic versioning enforced?
7. **Dependencies** - How to handle plugin → plugin deps?

---

**Ready to build the future of Grim!** 🚀

Let's start with Plugin System Phase 1 and make Grim the most hackable editor in Zig!

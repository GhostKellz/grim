# Grim Editor Architecture

## Vision
Grim is a Neovim alternative written in Zig, powered by the Phantom TUI framework. It aims to provide a modern, performant, and extensible text editing experience with first-class LSP support and AI integration.

## Architecture Overview

### Core Components

```
┌─────────────────────────────────────────────────────┐
│                  GrimApp (Main)                     │
│  - Phantom App instance                             │
│  - Event loop and rendering coordination            │
│  - Global state and configuration                   │
└─────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
┌───────▼──────┐ ┌─────▼──────┐ ┌─────▼──────┐
│   Layout     │ │  Command   │ │   Status   │
│   Manager    │ │    Bar     │ │    Bar     │
│              │ │            │ │            │
│ - Splits     │ │ - :command │ │ - Mode     │
│ - Tabs       │ │ - /search  │ │ - Position │
│ - Windows    │ │ - ?help    │ │ - Git      │
└──────┬───────┘ └────────────┘ └────────────┘
       │
  ┌────┴────┐
  │         │
┌─▼─────┐ ┌─▼─────┐
│Editor │ │Editor │  (Multiple editor instances in splits)
│Widget │ │Widget │
│       │ │       │
│ Text  │ │ Text  │
│ LSP   │ │ LSP   │
│ Cursor│ │ Cursor│
└───┬───┘ └───┬───┘
    │         │
┌───▼─────────▼───┐
│   LSP Widgets   │
│                 │
│ - Completion    │
│ - Hover         │
│ - Diagnostics   │
│ - Spinner       │
└─────────────────┘
```

### Component Breakdown

#### 1. GrimApp (`grim_app.zig`)
**Purpose**: Main application controller using Phantom App framework

**Responsibilities**:
- Initialize Phantom App with proper config (60 FPS, mouse support)
- Manage global state (buffers, windows, tabs)
- Coordinate event routing to active widgets
- Handle top-level commands (`:q`, `:w`, `:e`, etc.)
- Manage plugin system and configuration

**Key APIs**:
```zig
pub const GrimApp = struct {
    phantom_app: phantom.App,
    layout_manager: *LayoutManager,
    command_bar: *CommandBar,
    status_bar: *StatusBar,
    buffers: std.ArrayList(*Buffer),
    config: GrimConfig,

    pub fn init(allocator: Allocator) !*GrimApp;
    pub fn run() !void;
    pub fn handleCommand(cmd: []const u8) !void;
    pub fn openFile(path: []const u8) !void;
    pub fn closeBuffer() !void;
};
```

#### 2. LayoutManager (`grim_layout.zig`)
**Purpose**: Manage Neovim-like window layouts (splits, tabs)

**Responsibilities**:
- Vertical/horizontal splits
- Tab management
- Window focus and navigation (Ctrl+W commands)
- Layout rendering using Phantom FlexRow/FlexColumn

**Key Features**:
- `:split` / `:vsplit` - Create horizontal/vertical splits
- `:tabnew` - Create new tab
- `Ctrl+W h/j/k/l` - Navigate between splits
- `Ctrl+W =` - Equalize split sizes
- `Ctrl+W >/<` - Resize splits

**Key APIs**:
```zig
pub const LayoutManager = struct {
    root: *SplitNode,  // Tree of splits
    tabs: std.ArrayList(*TabPage),
    active_tab: usize,
    active_window: *EditorWidget,

    pub fn vsplit() !void;
    pub fn hsplit() !void;
    pub fn navigate(direction: Direction) void;
    pub fn resize(amount: i16) void;
    pub fn render(buffer: *phantom.Buffer, area: Rect) !void;
};

pub const SplitNode = union(enum) {
    leaf: *EditorWidget,
    vsplit: struct { left: *SplitNode, right: *SplitNode, ratio: f32 },
    hsplit: struct { top: *SplitNode, bottom: *SplitNode, ratio: f32 },
};
```

#### 3. EditorWidget (`grim_editor_widget.zig`)
**Purpose**: Core text editing widget (implements Phantom Widget interface)

**Responsibilities**:
- Text rendering with line numbers
- Cursor management (normal/insert/visual modes)
- Vim motions and commands
- LSP integration (completions, diagnostics, hover)
- Syntax highlighting integration
- Undo/redo with rope-based buffer

**Key APIs**:
```zig
pub const EditorWidget = struct {
    widget: phantom.Widget,  // Phantom widget vtable
    buffer: *Buffer,         // Rope-based text buffer
    cursor: Cursor,
    mode: Mode,
    lsp_client: ?*LSPClient,
    completion_menu: ?*LSPCompletionMenu,
    hover_widget: ?*LSPHoverWidget,
    diagnostics: std.ArrayList(Diagnostic),

    // Phantom Widget interface
    pub fn render(self: *Widget, buffer: *phantom.Buffer, area: Rect) void;
    pub fn handleEvent(self: *Widget, event: Event) bool;
    pub fn resize(self: *Widget, area: Rect) void;
    pub fn deinit(self: *Widget) void;

    // Editor-specific
    pub fn insertChar(c: u21) !void;
    pub fn deleteChar() !void;
    pub fn moveCursor(motion: Motion) void;
    pub fn executeCommand(cmd: Command) !void;
};
```

#### 4. CommandBar (`grim_command_bar.zig`)
**Purpose**: Command-line input (`:`, `/`, `?`)

**Responsibilities**:
- Command input (`:write`, `:quit`, etc.)
- Search input (`/pattern`, `?pattern`)
- Command history
- Tab completion

**Key APIs**:
```zig
pub const CommandBar = struct {
    input: phantom.widgets.Input,
    mode: CommandMode,  // .command, .search, .search_backward
    history: std.ArrayList([]const u8),

    pub fn show(mode: CommandMode) void;
    pub fn hide() void;
    pub fn execute() !void;
};
```

#### 5. StatusBar (`grim_status_bar.zig`)
**Purpose**: Status line showing mode, position, file info

**Responsibilities**:
- Mode indicator (NORMAL, INSERT, VISUAL, etc.)
- Cursor position (line:col)
- File path and modification status
- Git branch
- LSP status
- Recording macro indicator

**Implementation**: Use existing `status_bar_flex.zig` with StatusBarFlex widget

#### 6. LSP Integration
**Components**:
- `LSPCompletionMenu` - Completion popup (already exists)
- `LSPHoverWidget` - Documentation popup (already exists)
- `LSPDiagnosticsPanel` - Error/warning list (already exists)
- `LSPLoadingSpinner` - Operation indicator (already exists)

**Integration Points**:
- EditorWidget manages LSP client and triggers requests
- LSP widgets render as overlays on top of editor
- Proper z-ordering for popup widgets

### Event Flow

```
User Input (Key/Mouse)
        │
        ▼
  Phantom EventLoop
        │
        ▼
   GrimApp Handler
        │
        ├─── Command mode? ──▶ CommandBar
        │
        ├─── Global cmd? ───▶ GrimApp.handleCommand()
        │
        └─── Normal input ──▶ LayoutManager
                                    │
                                    ▼
                             Active EditorWidget
                                    │
                                    ├─── Vim motion ──▶ Cursor movement
                                    ├─── Insert mode ──▶ Text insertion
                                    ├─── LSP trigger ──▶ LSP request
                                    └─── Visual mode ──▶ Selection update

                                    ▼
                            Invalidate (redraw)
                                    ▼
                            Phantom.render()
                                    │
                                    ▼
                        Terminal.flush() (double-buffered)
```

### Rendering Pipeline

Phantom handles all rendering with double-buffering:

1. **Terminal.getBackBuffer()** - Get the back buffer
2. **Widget.render(buffer, area)** - Each widget renders to buffer
3. **Terminal.flush()** - Swap buffers and output to terminal
4. **No flickering** - Phantom handles cursor positioning and atomic updates

### Mode System

```zig
pub const Mode = enum {
    normal,
    insert,
    visual,
    visual_line,
    visual_block,
    command,
    search,
    replace,
    operator_pending,  // After 'd', 'y', 'c', etc.
};
```

Each mode has different event handlers and key bindings.

### Configuration

```zig
pub const GrimConfig = struct {
    // Editor settings
    tab_size: u8 = 4,
    expand_tab: bool = true,
    line_numbers: bool = true,
    relative_line_numbers: bool = true,

    // LSP settings
    lsp_enabled: bool = true,
    lsp_servers: std.StringHashMap(LSPConfig),

    // Appearance
    theme: Theme,
    status_line: []const StatusComponent,

    // Keybindings
    keymaps: std.StringHashMap(KeyMapping),
};
```

### Migration Strategy

1. **Phase 1**: Create new Phantom App-based architecture
   - Create `grim_app.zig` with basic Phantom App setup
   - Create `grim_editor_widget.zig` with basic text editing
   - Port essential functionality from `simple_tui.zig`

2. **Phase 2**: Add layout management
   - Implement `grim_layout.zig` with split support
   - Add tab management
   - Window navigation

3. **Phase 3**: Integrate LSP widgets properly
   - Wire LSPCompletionMenu into EditorWidget
   - Add LSPHoverWidget for 'K' command
   - Integrate LSPDiagnosticsPanel

4. **Phase 4**: Polish and features
   - Fix cursor flickering (Phantom handles this)
   - Add command bar with history
   - Implement macros and registers
   - Plugin system

5. **Phase 5**: Deprecate simple_tui.zig
   - Move to `simple_tui.zig.old`
   - Update build.zig to use new architecture

## Benefits of New Architecture

1. **No Flickering**: Phantom's double-buffering handles this properly
2. **Proper Widget System**: Clean separation of concerns
3. **Extensible**: Easy to add new widgets and features
4. **Maintainable**: ~1000 lines per component vs. 6986 line monolith
5. **Testable**: Each component can be tested independently
6. **Neovim-Quality**: Proper rendering, splits, tabs, LSP integration

## File Structure

```
ui-tui/
├── grim_app.zig                  # Main app (NEW)
├── grim_editor_widget.zig        # Text editor widget (NEW)
├── grim_layout.zig               # Split/tab manager (NEW)
├── grim_command_bar.zig          # Command input (NEW)
├── grim_status_bar.zig           # Status line wrapper (NEW)
├── lsp_completion_menu.zig       # LSP completion (EXISTS)
├── lsp_hover_widget.zig          # LSP hover (EXISTS)
├── lsp_diagnostics_panel.zig     # LSP diagnostics (EXISTS)
├── lsp_loading_spinner.zig       # LSP spinner (EXISTS)
├── status_bar_flex.zig           # Flex status bar (EXISTS)
└── simple_tui.zig.old            # Old monolith (DEPRECATED)
```

## Next Steps

1. Create `grim_app.zig` with Phantom App initialization
2. Create `grim_editor_widget.zig` with basic Vim editing
3. Wire in LSP widgets using proper Phantom rendering
4. Test with actual editor workflow
5. Iterate and improve

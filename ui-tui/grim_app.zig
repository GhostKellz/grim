//! Grim Editor - Neovim alternative in Zig powered by Phantom TUI
//! Main application structure using Phantom App framework

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const runtime = @import("runtime");
const Editor = @import("editor.zig").Editor;
const theme_mod = @import("theme.zig");
const editor_lsp_mod = @import("editor_lsp.zig");

// Extract MouseEvent type from Event union (not exported from phantom root)
const MouseEvent = @typeInfo(phantom.Event).@"union".fields[1].type;

// UI components
const grim_editor_widget = @import("grim_editor_widget.zig");
const grim_layout = @import("grim_layout.zig");
const grim_command_bar = @import("grim_command_bar.zig");
const powerline_status = @import("powerline_status.zig");
const tab_bar = @import("tab_bar.zig");

// LSP widgets
const lsp_completion_menu = @import("lsp_completion_menu.zig");
const lsp_hover_widget = @import("lsp_hover_widget.zig");
const lsp_diagnostics_panel = @import("lsp_diagnostics_panel.zig");
const lsp_loading_spinner = @import("lsp_loading_spinner.zig");

// Terminal widget
const terminal_widget = @import("terminal_widget.zig");

pub const GrimConfig = struct {
    // Editor settings
    tab_size: u8 = 4,
    expand_tab: bool = true,
    line_numbers: bool = true,
    relative_line_numbers: bool = false,

    // LSP settings
    lsp_enabled: bool = true,

    // Appearance
    tick_rate_ms: u64 = 16, // ~60 FPS for smooth rendering
    mouse_enabled: bool = true,

    // Initial file to open (optional)
    initial_file: ?[]const u8 = null,
};

pub const Mode = enum {
    normal,
    insert,
    visual,
    visual_line,
    visual_block,
    command,
    search,
    replace,
};

pub const GrimApp = struct {
    allocator: std.mem.Allocator,
    phantom_app: phantom.App,
    config: GrimConfig,

    // Core components
    layout_manager: *grim_layout.LayoutManager,
    command_bar: *grim_command_bar.CommandBar,
    status_bar: *powerline_status.PowerlineStatus,
    tab_bar: tab_bar.TabBar,

    // State
    mode: Mode,
    running: bool,
    waiting_for_window_command: bool,
    pending_operator: u8, // For vim operator pending (yy, dd, etc)

    // Macro replay state
    macro_replay_buffer: ?[]const phantom.Key,
    macro_replay_index: usize,

    // Plugin system
    plugin_manager: ?*runtime.PluginManager,
    editor_context: ?*runtime.PluginAPI.EditorContext,
    plugin_cursor: ?*runtime.PluginAPI.EditorContext.CursorPosition,

    // LSP integration
    editor_lsp: ?*editor_lsp_mod.EditorLSP,

    // Theme system
    theme_registry: theme_mod.ThemeRegistry,
    active_theme: theme_mod.Theme,

    // Buffer management
    current_buffer_id: runtime.PluginAPI.BufferId,

    // Git integration
    git: core.Git,

    // Harpoon integration
    harpoon: core.Harpoon,

    // Fuzzy finder
    fuzzy: core.FuzzyFinder,

    // Clipboard integration
    clipboard: core.Clipboard,

    // Config management
    config_manager: core.ConfigManager,

    // Search history
    search_history: core.SearchHistory,
    command_history: core.SearchHistory,

    pub fn init(allocator: std.mem.Allocator, config: GrimConfig) !*GrimApp {
        const self = try allocator.create(GrimApp);
        errdefer allocator.destroy(self);

        // Initialize Phantom App with config
        var phantom_app = try phantom.App.init(allocator, .{
            .title = "Grim",
            .tick_rate_ms = config.tick_rate_ms,
            .mouse_enabled = config.mouse_enabled,
            .resize_enabled = true,
            .add_default_handler = false, // NEW: Disable Escape/Ctrl+C auto-quit for vim compatibility
        });
        errdefer phantom_app.deinit();

        // Get terminal size
        const term_size = phantom_app.terminal.size;

        // Initialize layout manager (handles splits/tabs)
        const layout_manager = try grim_layout.LayoutManager.init(
            allocator,
            term_size.width,
            term_size.height - 2, // Reserve 2 rows for status bar and command bar
        );
        errdefer layout_manager.deinit();

        // Initialize command bar
        const command_bar = try grim_command_bar.CommandBar.init(allocator);
        errdefer command_bar.deinit();

        // Initialize status bar (powerlevel10k style)
        const status_bar = try powerline_status.PowerlineStatus.init(allocator, term_size.width);
        errdefer status_bar.deinit();

        // Initialize Git
        const git = core.Git.init(allocator);

        // Initialize Harpoon
        const harpoon = core.Harpoon.init(allocator);

        // Initialize Fuzzy finder
        const fuzzy = core.FuzzyFinder.init(allocator);

        // Initialize Clipboard
        const clipboard = try core.Clipboard.init(allocator);

        // Initialize Config Manager (load or create default config)
        const config_manager = try core.ConfigManager.init(allocator);

        // Initialize search and command history
        const search_history = core.SearchHistory.init(allocator, 100);
        const command_history = core.SearchHistory.init(allocator, 100);

        // Initialize theme registry
        var theme_registry = theme_mod.ThemeRegistry.init(allocator);
        errdefer theme_registry.deinit();

        // Get default theme
        const default_theme = try theme_mod.Theme.get("ghost-hacker-blue");

        self.* = .{
            .allocator = allocator,
            .phantom_app = phantom_app,
            .config = config,
            .layout_manager = layout_manager,
            .command_bar = command_bar,
            .status_bar = status_bar,
            .tab_bar = tab_bar.TabBar.init(layout_manager),
            .mode = .normal,
            .running = true,
            .waiting_for_window_command = false,
            .pending_operator = 0,
            .macro_replay_buffer = null,
            .macro_replay_index = 0,
            .plugin_manager = null,
            .editor_context = null,
            .plugin_cursor = null,
            .editor_lsp = null,
            .theme_registry = theme_registry,
            .active_theme = default_theme,
            .current_buffer_id = 1,
            .git = git,
            .harpoon = harpoon,
            .fuzzy = fuzzy,
            .clipboard = clipboard,
            .config_manager = config_manager,
            .search_history = search_history,
            .command_history = command_history,
        };

        // Create initial editor (needed even if opening a file)
        try self.layout_manager.createInitialEditor();

        // Wire clipboard to all editors
        if (self.layout_manager.getActiveEditor()) |editor| {
            editor.setClipboard(&self.clipboard);
        }

        // Load initial file if specified
        if (config.initial_file) |file_path| {
            try self.openFile(file_path);
        }

        return self;
    }

    pub fn deinit(self: *GrimApp) void {
        self.command_history.deinit();
        self.search_history.deinit();
        self.config_manager.deinit();
        self.clipboard.deinit();
        self.theme_registry.deinit();
        self.fuzzy.deinit();
        self.harpoon.deinit();
        self.git.deinit();
        if (self.plugin_manager) |pm| pm.deinit();
        self.status_bar.deinit();
        self.command_bar.deinit();
        self.layout_manager.deinit();
        self.phantom_app.deinit();
        self.allocator.destroy(self);
    }

    /// Main run loop
    pub fn run(self: *GrimApp) !void {
        // Set up global context for event handler
        grim_app_context = self;

        // Add our event handler
        try self.phantom_app.event_loop.addHandler(grimEventHandler);

        // Hide cursor (we'll draw it manually)
        try self.hideSystemCursor();
        defer self.showSystemCursor() catch {};

        // Use Phantom v0.6.3's runWithoutDefaults() for full control
        // This skips the default Escape/Ctrl+C handler, giving us vim compatibility
        try self.phantom_app.runWithoutDefaults();
    }

    /// Handle all events
    fn handleEvent(self: *GrimApp, event: phantom.Event) !bool {
        switch (event) {
            .key => |key| {
                return try self.handleKeyEvent(key);
            },
            .mouse => |mouse| {
                return try self.handleMouseEvent(mouse);
            },
            .system => |sys| {
                switch (sys) {
                    .resize => {
                        const new_size = self.phantom_app.terminal.size;
                        try self.handleResize(new_size);
                        return true;
                    },
                    else => return false,
                }
            },
            .tick => {
                // Render on each tick
                try self.render();
                return true;
            },
        }
    }

    /// Handle keyboard input based on current mode
    fn handleKeyEvent(self: *GrimApp, key: phantom.Key) !bool {
        // Command bar has priority
        if (self.command_bar.visible) {
            return try self.command_bar.handleKey(key, self);
        }

        // Terminal input routing - if terminal is focused
        if (self.layout_manager.isTerminalFocused()) {
            if (self.layout_manager.getActiveTerminal()) |term| {
                // Ctrl+X exits terminal focus (back to editor)
                if (key == .ctrl_x) {
                    self.layout_manager.hideTerminal();
                    return true;
                }

                // Page Up/Down for scrollback navigation
                switch (key) {
                    .page_up => {
                        term.scrollUp(10);
                        return true;
                    },
                    .page_down => {
                        term.scrollDown(10);
                        return true;
                    },
                    else => {},
                }

                // Route all other keys to terminal
                try term.handleInput(key);
                return true;
            }
        }

        // Process the actual key
        const handled = try self.processKey(key);

        // If we're replaying a macro, inject the next key
        if (self.macro_replay_buffer) |replay_keys| {
            if (self.macro_replay_index < replay_keys.len) {
                const next_key = replay_keys[self.macro_replay_index];
                self.macro_replay_index += 1;

                // Recursively process the macro key
                _ = try self.processKey(next_key);
            } else {
                // Macro replay finished
                self.macro_replay_buffer = null;
                self.macro_replay_index = 0;
            }
        }

        return handled;
    }

    fn processKey(self: *GrimApp, key: phantom.Key) !bool {
        // Route to mode-specific handler
        switch (self.mode) {
            .normal => return try self.handleNormalMode(key),
            .insert => return try self.handleInsertMode(key),
            .visual, .visual_line, .visual_block => return try self.handleVisualMode(key),
            .command => return try self.handleCommandMode(key),
            .search => return try self.handleSearchMode(key),
            .replace => return try self.handleReplaceMode(key),
        }
    }

    fn handleNormalMode(self: *GrimApp, key: phantom.Key) !bool {
        const editor = self.layout_manager.getActiveEditor();

        // Record key if macro recording is active
        if (editor) |ed| {
            if (ed.isRecording()) {
                try ed.recordKey(key);
            }
        }

        // Handle window commands (after Ctrl+W)
        if (self.waiting_for_window_command) {
            self.waiting_for_window_command = false;
            return try self.handleWindowCommand(key);
        }

        switch (key) {
            .char => |c| {
                switch (c) {
                    // Mode switches
                    'i' => {
                        self.mode = .insert;
                        return true;
                    },
                    'v' => {
                        self.mode = .visual;
                        try self.layout_manager.getActiveEditor().?.startVisualMode();
                        return true;
                    },
                    'V' => {
                        self.mode = .visual_line;
                        try self.layout_manager.getActiveEditor().?.startVisualLineMode();
                        return true;
                    },
                    ':' => {
                        self.mode = .command;
                        self.command_bar.show(.command);
                        return true;
                    },
                    '/' => {
                        self.mode = .search;
                        self.command_bar.show(.search);
                        return true;
                    },

                    // Navigation
                    'h' => {
                        try self.layout_manager.getActiveEditor().?.moveCursorLeft();
                        return true;
                    },
                    'j' => {
                        try self.layout_manager.getActiveEditor().?.moveCursorDown();
                        return true;
                    },
                    'k' => {
                        try self.layout_manager.getActiveEditor().?.moveCursorUp();
                        return true;
                    },
                    'l' => {
                        try self.layout_manager.getActiveEditor().?.moveCursorRight();
                        return true;
                    },

                    // Word navigation
                    'w' => {
                        try self.layout_manager.getActiveEditor().?.moveWordForward();
                        return true;
                    },
                    'b' => {
                        try self.layout_manager.getActiveEditor().?.moveWordBackward();
                        return true;
                    },

                    // Line navigation
                    '0' => {
                        try self.layout_manager.getActiveEditor().?.moveToLineStart();
                        return true;
                    },
                    '$' => {
                        try self.layout_manager.getActiveEditor().?.moveToLineEnd();
                        return true;
                    },

                    // File navigation
                    'g' => {
                        // Enter pending operator mode for gg
                        self.pending_operator = 'g';
                        return true;
                    },
                    'G' => {
                        try self.layout_manager.getActiveEditor().?.gotoLastLine();
                        return true;
                    },

                    // LSP features
                    'K' => {
                        try self.layout_manager.getActiveEditor().?.triggerHover();
                        return true;
                    },

                    // Search navigation
                    'n' => {
                        try self.layout_manager.getActiveEditor().?.searchNext();
                        return true;
                    },
                    'N' => {
                        try self.layout_manager.getActiveEditor().?.searchPrev();
                        return true;
                    },

                    // Character find motions
                    'f' => {
                        self.pending_operator = 'f';
                        return true;
                    },
                    'F' => {
                        self.pending_operator = 'F';
                        return true;
                    },
                    't' => {
                        self.pending_operator = 't';
                        return true;
                    },
                    'T' => {
                        self.pending_operator = 'T';
                        return true;
                    },
                    ';' => {
                        if (editor) |ed| {
                            ed.editor.repeatLastFind();
                        }
                        return true;
                    },
                    ',' => {
                        if (editor) |ed| {
                            ed.editor.repeatLastFindReverse();
                        }
                        return true;
                    },

                    // Paste
                    'p' => {
                        try self.layout_manager.getActiveEditor().?.paste(null);
                        return true;
                    },

                    // Undo
                    'u' => {
                        try self.layout_manager.getActiveEditor().?.undo();
                        return true;
                    },

                    // Yank line (yy is handled as two 'y' presses)
                    'y' => {
                        // Enter pending operator mode for yy
                        self.pending_operator = 'y';
                        return true;
                    },

                    // Delete line (dd is handled as two 'd' presses)
                    'd' => {
                        if (self.pending_operator == 'd') {
                            // dd - delete line
                            try self.layout_manager.getActiveEditor().?.deleteLine(null);
                            self.pending_operator = 0;
                            return true;
                        } else {
                            // First d - wait for second
                            self.pending_operator = 'd';
                            return true;
                        }
                    },

                    // Macro recording / Quit
                    'q' => {
                        if (editor) |ed| {
                            if (ed.isRecording()) {
                                // Stop recording
                                ed.stopRecordingMacro();
                                return true;
                            }
                        }
                        // TODO: Handle unsaved buffers
                        self.phantom_app.stop();
                        return true;
                    },

                    // Replay macro
                    '@' => {
                        // Wait for register
                        self.pending_operator = '@';
                        return true;
                    },

                    else => {
                        // Check pending operator
                        if (self.pending_operator == 'y') {
                            if (c == 'y') {
                                // yy - yank line
                                try self.layout_manager.getActiveEditor().?.yankLine(null);
                                self.pending_operator = 0;
                                return true;
                            }
                            self.pending_operator = 0;
                        } else if (self.pending_operator == 'd') {
                            // Reset pending operator if not 'd'
                            self.pending_operator = 0;
                        } else if (self.pending_operator == '@') {
                            // Replay macro from register
                            if (editor) |ed| {
                                const macro_keys = try ed.replayMacro(@intCast(c));
                                if (macro_keys) |keys| {
                                    self.macro_replay_buffer = keys;
                                    self.macro_replay_index = 0;
                                }
                            }
                            self.pending_operator = 0;
                            return true;
                        } else if (self.pending_operator == 'q') {
                            // Start recording macro to register
                            if (editor) |ed| {
                                try ed.startRecordingMacro(@intCast(c));
                            }
                            self.pending_operator = 0;
                            return true;
                        } else if (self.pending_operator == 'g') {
                            // gg - goto first line
                            if (c == 'g') {
                                try self.layout_manager.getActiveEditor().?.gotoFirstLine();
                                self.pending_operator = 0;
                                return true;
                            }
                            // gd - go to definition (LSP)
                            else if (c == 'd') {
                                if (self.editor_lsp) |lsp| {
                                    if (editor) |ed| {
                                        const pos = ed.editor.offsetToLineCol(ed.editor.cursor.offset) catch {
                                            std.log.warn("Failed to convert cursor position", .{});
                                            self.pending_operator = 0;
                                            return true;
                                        };

                                        lsp.requestDefinition(ed.editor.current_filename orelse "untitled", pos.line, pos.col) catch |err| {
                                            std.log.warn("LSP go-to-definition request failed: {}", .{err});
                                        };
                                    }
                                }
                                self.pending_operator = 0;
                                return true;
                            }
                            // gr - find references (LSP) - placeholder for now
                            else if (c == 'r') {
                                std.log.info("LSP find references not yet implemented", .{});
                                self.pending_operator = 0;
                                return true;
                            }
                            self.pending_operator = 0;
                        } else if (self.pending_operator == 'f') {
                            // f<char> - find character forward
                            if (editor) |ed| {
                                ed.editor.findCharForward(c);
                            }
                            self.pending_operator = 0;
                            return true;
                        } else if (self.pending_operator == 'F') {
                            // F<char> - find character backward
                            if (editor) |ed| {
                                ed.editor.findCharBackward(c);
                            }
                            self.pending_operator = 0;
                            return true;
                        } else if (self.pending_operator == 't') {
                            // t<char> - till character forward
                            if (editor) |ed| {
                                ed.editor.tillCharForward(c);
                            }
                            self.pending_operator = 0;
                            return true;
                        } else if (self.pending_operator == 'T') {
                            // T<char> - till character backward
                            if (editor) |ed| {
                                ed.editor.tillCharBackward(c);
                            }
                            self.pending_operator = 0;
                            return true;
                        }

                        // Check if 'q' followed by register for macro recording
                        if (c == 'q' and self.pending_operator == 0) {
                            self.pending_operator = 'q';
                            return true;
                        }

                        return false;
                    },
                }
            },
            .ctrl_c => {
                self.running = false;
                return true;
            },
            .ctrl_w => {
                // Enter window command mode - wait for next key
                self.waiting_for_window_command = true;
                return true;
            },
            .ctrl_v => {
                self.mode = .visual_block;
                try self.layout_manager.getActiveEditor().?.startVisualBlockMode();
                return true;
            },
            .ctrl_r => {
                // Redo
                try self.layout_manager.getActiveEditor().?.redo();
                return true;
            },
            .ctrl_d => {
                // Half page down
                try self.layout_manager.getActiveEditor().?.scrollHalfPageDown();
                return true;
            },
            .ctrl_u => {
                // Half page up
                try self.layout_manager.getActiveEditor().?.scrollHalfPageUp();
                return true;
            },
            .ctrl_f => {
                // Full page down
                try self.layout_manager.getActiveEditor().?.scrollFullPageDown();
                return true;
            },
            .ctrl_b => {
                // Full page up
                try self.layout_manager.getActiveEditor().?.scrollFullPageUp();
                return true;
            },
            else => return false,
        }
    }

    fn handleInsertMode(self: *GrimApp, key: phantom.Key) !bool {
        const editor = self.layout_manager.getActiveEditor() orelse return false;

        switch (key) {
            .escape => {
                self.mode = .normal;
                // End undo grouping when leaving insert mode
                editor.endUndoGroup();
                return true;
            },
            .char => |c| {
                try editor.insertChar(c);
                return true;
            },
            .enter => {
                try editor.insertNewline();
                return true;
            },
            .backspace => {
                try editor.deleteCharBackward();
                return true;
            },
            .delete => {
                try editor.deleteCharForward();
                return true;
            },
            .tab => {
                // Check for completion
                if (editor.lsp_completion_menu) |menu| {
                    if (menu.visible) {
                        menu.selectNext();
                        return true;
                    }
                }
                // Insert tab/spaces
                try editor.insertTab();
                return true;
            },
            .ctrl_n => {
                // Trigger LSP completion (Ctrl+N like vim)
                try editor.triggerCompletion();
                return true;
            },
            else => return false,
        }
    }

    fn handleVisualMode(self: *GrimApp, key: phantom.Key) !bool {
        const editor = self.layout_manager.getActiveEditor() orelse return false;

        switch (key) {
            .escape => {
                self.mode = .normal;
                try editor.clearSelection();
                return true;
            },
            .char => |c| {
                switch (c) {
                    // Movement extends selection
                    'h' => {
                        try editor.extendSelectionLeft();
                        return true;
                    },
                    'j' => {
                        try editor.extendSelectionDown();
                        return true;
                    },
                    'k' => {
                        try editor.extendSelectionUp();
                        return true;
                    },
                    'l' => {
                        try editor.extendSelectionRight();
                        return true;
                    },

                    // Operations on selection
                    'd' => {
                        if (self.mode == .visual_block) {
                            try editor.deleteBlockSelection();
                        } else {
                            try editor.deleteSelection();
                        }
                        self.mode = .normal;
                        return true;
                    },
                    'y' => {
                        if (self.mode == .visual_block) {
                            try editor.yankBlockSelection();
                        } else {
                            try editor.yankSelection();
                        }
                        self.mode = .normal;
                        return true;
                    },
                    'c' => {
                        if (self.mode == .visual_block) {
                            try editor.deleteBlockSelection();
                        } else {
                            try editor.deleteSelection();
                        }
                        self.mode = .insert;
                        return true;
                    },

                    // Block insert/append (only for visual_block)
                    'I' => {
                        if (self.mode == .visual_block) {
                            try editor.blockInsert();
                            self.mode = .insert;
                            return true;
                        }
                        return false;
                    },
                    'A' => {
                        if (self.mode == .visual_block) {
                            try editor.blockAppend();
                            self.mode = .insert;
                            return true;
                        }
                        return false;
                    },

                    // Indent/dedent
                    '>' => {
                        try editor.indentSelection();
                        self.mode = .normal;
                        return true;
                    },
                    '<' => {
                        try editor.dedentSelection();
                        self.mode = .normal;
                        return true;
                    },

                    else => return false,
                }
            },
            else => return false,
        }
    }

    fn handleCommandMode(_: *GrimApp, _: phantom.Key) !bool {
        // Handled by command_bar
        return false;
    }

    fn handleSearchMode(_: *GrimApp, _: phantom.Key) !bool {
        // Handled by command_bar
        return false;
    }

    fn handleReplaceMode(_: *GrimApp, _: phantom.Key) !bool {
        // TODO: Implement replace mode
        return false;
    }

    fn handleWindowCommand(self: *GrimApp, key: phantom.Key) !bool {
        switch (key) {
            .char => |c| {
                switch (c) {
                    // Split commands
                    's' => {
                        try self.layout_manager.horizontalSplit();
                        return true;
                    },
                    'v' => {
                        try self.layout_manager.verticalSplit();
                        return true;
                    },

                    // Navigation commands (TODO: implement in LayoutManager)
                    'h' => {
                        _ = try self.layout_manager.handleWindowCommand(.left);
                        return true;
                    },
                    'j' => {
                        _ = try self.layout_manager.handleWindowCommand(.down);
                        return true;
                    },
                    'k' => {
                        _ = try self.layout_manager.handleWindowCommand(.up);
                        return true;
                    },
                    'l' => {
                        _ = try self.layout_manager.handleWindowCommand(.right);
                        return true;
                    },

                    // Close window
                    'q' => {
                        self.layout_manager.closeWindow() catch |err| {
                            if (err == error.CannotCloseLastWindow) {
                                // Just ignore, can't close last window
                            } else {
                                return err;
                            }
                        };
                        return true;
                    },
                    'o' => {
                        try self.layout_manager.closeOtherWindows();
                        return true;
                    },

                    // Equalize splits
                    '=' => {
                        self.layout_manager.equalizeSplits();
                        return true;
                    },

                    // Resize horizontal
                    '<' => {
                        try self.layout_manager.resizeSplit(.decrease);
                        return true;
                    },
                    '>' => {
                        try self.layout_manager.resizeSplit(.increase);
                        return true;
                    },

                    // Resize vertical
                    '+' => {
                        try self.layout_manager.resizeSplit(.increase_vertical);
                        return true;
                    },
                    '-' => {
                        try self.layout_manager.resizeSplit(.decrease_vertical);
                        return true;
                    },

                    // Escape cancels
                    else => return false,
                }
            },
            .left => {
                _ = try self.layout_manager.handleWindowCommand(.left);
                return true;
            },
            .right => {
                _ = try self.layout_manager.handleWindowCommand(.right);
                return true;
            },
            .up => {
                _ = try self.layout_manager.handleWindowCommand(.up);
                return true;
            },
            .down => {
                _ = try self.layout_manager.handleWindowCommand(.down);
                return true;
            },
            .escape => {
                // Cancel window command mode
                return true;
            },
            else => return false,
        }
    }

    fn handleMouseEvent(self: *GrimApp, mouse: MouseEvent) !bool {
        // Delegate to layout manager to find which editor was clicked
        const term_size = self.phantom_app.terminal.size;
        const editor_area = phantom.Rect.init(0, 0, term_size.width, term_size.height - 2);
        return try self.layout_manager.handleMouse(mouse, editor_area);
    }

    fn handleResize(self: *GrimApp, new_size: phantom.Size) !void {
        try self.phantom_app.resize(new_size);
        try self.layout_manager.resize(new_size.width, new_size.height - 2);
        self.status_bar.resize(new_size.width);
    }

    /// Render all UI components using Phantom's double-buffered rendering
    fn render(self: *GrimApp) !void {
        // Get back buffer for rendering
        const buffer = self.phantom_app.terminal.getBackBuffer();

        // Clear buffer
        buffer.clear();

        // Calculate layout areas
        const term_size = self.phantom_app.terminal.size;

        // Tab bar area (top line if multiple tabs exist)
        const has_multiple_tabs = self.layout_manager.tabs.items.len > 1;
        const tab_bar_height: u16 = if (has_multiple_tabs) 1 else 0;
        const tab_bar_area = phantom.Rect{
            .x = 0,
            .y = 0,
            .width = term_size.width,
            .height = tab_bar_height,
        };

        // Editor area (below tab bar, above status line)
        const editor_area = phantom.Rect{
            .x = 0,
            .y = tab_bar_height,
            .width = term_size.width,
            .height = if (term_size.height > (2 + tab_bar_height)) term_size.height - 2 - tab_bar_height else 0,
        };

        // Command bar area (bottom line if in command/search mode)
        const command_bar_area = phantom.Rect{
            .x = 0,
            .y = if (term_size.height > 0) term_size.height - 1 else 0,
            .width = term_size.width,
            .height = 1,
        };

        // Status bar area (second to bottom line)
        const status_bar_area = phantom.Rect{
            .x = 0,
            .y = if (term_size.height > 1) term_size.height - 2 else 0,
            .width = term_size.width,
            .height = 1,
        };

        // Render tab bar if multiple tabs
        if (has_multiple_tabs) {
            var tab_bar_widget = &self.tab_bar;
            tab_bar_widget.render(buffer, tab_bar_area);
        }

        // Render layout manager (handles all editor windows/splits/tabs)
        self.layout_manager.render(buffer, editor_area);

        // Render status bar (powerlevel10k style)
        if (self.layout_manager.getActiveEditor()) |active_editor| {
            try self.status_bar.render(buffer, status_bar_area, active_editor, self.mode, &self.git);
        }

        // Render command bar if visible
        if (self.command_bar.visible) {
            self.command_bar.render(buffer, command_bar_area);
        }

        // Flush to terminal (diff-based rendering, no flickering!)
        try self.phantom_app.terminal.flush();
    }

    /// Execute a command (from :command mode)
    pub fn executeCommand(self: *GrimApp, command: []const u8) !void {
        if (command.len == 0) return;

        // Add to command history
        self.command_history.add(command) catch |err| {
            std.log.warn("Failed to add command to history: {}", .{err});
        };

        // Parse command
        if (std.mem.eql(u8, command, "q") or std.mem.eql(u8, command, "quit")) {
            // Check for unsaved buffers
            if (self.layout_manager.getActiveEditor()) |editor| {
                if (editor.is_modified) {
                    std.log.warn("No write since last change (add ! to override)", .{});
                    return;
                }
            }
            self.running = false;
        } else if (std.mem.eql(u8, command, "q!") or std.mem.eql(u8, command, "quit!")) {
            // Force quit without checking for unsaved changes
            self.running = false;
        } else if (std.mem.eql(u8, command, "w") or std.mem.eql(u8, command, "write")) {
            try self.saveCurrentBuffer();
        } else if (std.mem.eql(u8, command, "wq")) {
            try self.saveCurrentBuffer();
            self.running = false;
        } else if (std.mem.startsWith(u8, command, "e ")) {
            const filepath = std.mem.trim(u8, command[2..], " ");
            try self.openFile(filepath);
        } else if (std.mem.eql(u8, command, "split") or std.mem.eql(u8, command, "sp")) {
            try self.layout_manager.horizontalSplit();
        } else if (std.mem.eql(u8, command, "vsplit") or std.mem.eql(u8, command, "vsp")) {
            try self.layout_manager.verticalSplit();
        } else if (std.mem.eql(u8, command, "tabnew")) {
            try self.layout_manager.newTab();
        } else if (std.mem.eql(u8, command, "tabn") or std.mem.eql(u8, command, "tabnext")) {
            self.layout_manager.nextTab();
        } else if (std.mem.eql(u8, command, "tabp") or std.mem.eql(u8, command, "tabprev")) {
            self.layout_manager.prevTab();
        } else if (std.mem.eql(u8, command, "tabc") or std.mem.eql(u8, command, "tabclose")) {
            try self.layout_manager.closeTab();
        } else if (std.mem.startsWith(u8, command, "tabn ")) {
            const tab_num_str = std.mem.trim(u8, command[5..], " ");
            const tab_num = try std.fmt.parseInt(usize, tab_num_str, 10);
            if (tab_num > 0) {
                try self.layout_manager.switchTab(tab_num - 1); // 1-indexed to 0-indexed
            }
        } else if (std.mem.eql(u8, command, "LspDiagnostics") or std.mem.eql(u8, command, "lspdiag")) {
            // Toggle LSP diagnostics panel
            if (self.layout_manager.getActiveEditor()) |editor| {
                editor.toggleDiagnostics();
            }
        } else if (std.mem.eql(u8, command, "bnext") or std.mem.eql(u8, command, "bn")) {
            try self.layout_manager.bufferNext();
        } else if (std.mem.eql(u8, command, "bprev") or std.mem.eql(u8, command, "bp")) {
            try self.layout_manager.bufferPrev();
        } else if (std.mem.eql(u8, command, "bdelete") or std.mem.eql(u8, command, "bd")) {
            try self.layout_manager.bufferDelete();
        } else if (std.mem.eql(u8, command, "buffers") or std.mem.eql(u8, command, "ls")) {
            // List all buffers
            const buffers = self.layout_manager.getBufferList();
            std.log.info("=== Buffers ===", .{});
            for (buffers, 0..) |buffer, i| {
                std.log.info("  [{d}] {s}", .{ i + 1, buffer.name });
            }
        } else if (std.mem.eql(u8, command, "term") or std.mem.eql(u8, command, "terminal")) {
            // Open terminal in horizontal split
            try self.openTerminal(null);
        } else if (std.mem.startsWith(u8, command, "term ") or std.mem.startsWith(u8, command, "terminal ")) {
            // Open terminal with specific command
            const cmd_start = std.mem.indexOfScalar(u8, command, ' ') orelse command.len;
            const term_cmd = std.mem.trim(u8, command[cmd_start..], " ");
            try self.openTerminal(term_cmd);
        } else if (std.mem.startsWith(u8, command, "vsplit term://")) {
            // Vertical split with terminal
            const term_cmd_prefix = "vsplit term://";
            const term_cmd = if (command.len > term_cmd_prefix.len)
                std.mem.trim(u8, command[term_cmd_prefix.len..], " ")
            else
                null;
            try self.layout_manager.verticalSplit();
            try self.openTerminal(if (term_cmd != null and term_cmd.?.len > 0) term_cmd else null);
        } else if (std.mem.startsWith(u8, command, "split term://") or std.mem.startsWith(u8, command, "hsplit term://")) {
            // Horizontal split with terminal
            const term_cmd_prefix = if (std.mem.startsWith(u8, command, "split term://"))
                "split term://"
            else
                "hsplit term://";
            const term_cmd = if (command.len > term_cmd_prefix.len)
                std.mem.trim(u8, command[term_cmd_prefix.len..], " ")
            else
                null;
            try self.layout_manager.horizontalSplit();
            try self.openTerminal(if (term_cmd != null and term_cmd.?.len > 0) term_cmd else null);
        } else if (std.mem.startsWith(u8, command, "%s/") or std.mem.startsWith(u8, command, "s/")) {
            // Substitute command: :%s/pattern/replacement/flags or :s/pattern/replacement/flags
            try self.handleSubstitute(command);
        } else if (std.mem.startsWith(u8, command, "set ")) {
            // Handle :set commands
            const set_args = std.mem.trim(u8, command[4..], " ");
            try self.handleSetCommand(set_args);
        } else if (std.mem.eql(u8, command, "config") or std.mem.eql(u8, command, "editconfig")) {
            // Open config file for editing
            const config_path = try core.Config.getDefaultPath(self.allocator);
            defer self.allocator.free(config_path);
            try self.openFile(config_path);
            std.log.info("Opened config file: {s}", .{config_path});
        } else if (std.mem.eql(u8, command, "reload") or std.mem.eql(u8, command, "reloadconfig")) {
            // Reload config from disk
            if (try self.config_manager.checkAndReload()) {
                std.log.info("Config reloaded successfully", .{});
                try self.applyConfig();
            } else {
                std.log.info("Config unchanged", .{});
            }
        } else if (std.mem.eql(u8, command, "saveconfig")) {
            // Save current config to disk
            try self.config_manager.saveConfig();
            std.log.info("Config saved", .{});
        } else if (std.mem.startsWith(u8, command, "theme ")) {
            // Set theme: :theme ghost-hacker-blue
            const theme_name = std.mem.trim(u8, command[6..], " ");
            try self.setTheme(theme_name);
            std.log.info("Theme set to: {s}", .{theme_name});
        } else {
            // Unknown command
            std.log.warn("Unknown command: {s}", .{command});
        }
    }

    fn handleSetCommand(self: *GrimApp, args: []const u8) !void {
        const editor = self.layout_manager.getActiveEditor() orelse return error.NoActiveEditor;

        if (std.mem.eql(u8, args, "expandtab") or std.mem.eql(u8, args, "et")) {
            editor.expand_tab = true;
            std.log.info("expandtab enabled", .{});
        } else if (std.mem.eql(u8, args, "noexpandtab") or std.mem.eql(u8, args, "noet")) {
            editor.expand_tab = false;
            std.log.info("expandtab disabled", .{});
        } else if (std.mem.startsWith(u8, args, "tabstop=") or std.mem.startsWith(u8, args, "ts=")) {
            const eq_pos = std.mem.indexOfScalar(u8, args, '=') orelse return;
            const value_str = args[eq_pos + 1 ..];
            const tab_size = std.fmt.parseInt(u8, value_str, 10) catch {
                std.log.warn("Invalid tabstop value: {s}", .{value_str});
                return;
            };
            if (tab_size > 0 and tab_size <= 16) {
                editor.tab_size = tab_size;
                std.log.info("tabstop set to {d}", .{tab_size});
            } else {
                std.log.warn("tabstop must be between 1 and 16", .{});
            }
        } else {
            std.log.warn("Unknown set option: {s}", .{args});
        }
    }

    fn handleSubstitute(self: *GrimApp, command: []const u8) !void {
        const editor = self.layout_manager.getActiveEditor() orelse return error.NoActiveEditor;

        // Parse the substitute command
        // Format: %s/pattern/replacement/flags or s/pattern/replacement/flags
        const cmd_start = if (std.mem.startsWith(u8, command, "%s/")) @as(usize, 3) else @as(usize, 2);
        const rest = command[cmd_start..];

        // Find pattern (between first and second /)
        const first_slash = std.mem.indexOfScalar(u8, rest, '/') orelse return error.InvalidSubstituteFormat;
        const pattern = rest[0..first_slash];

        // Find replacement (between second and third /)
        const after_pattern = rest[first_slash + 1 ..];
        const second_slash = std.mem.indexOfScalar(u8, after_pattern, '/') orelse return error.InvalidSubstituteFormat;
        const replacement = after_pattern[0..second_slash];

        // Get flags (after third /)
        const flags = after_pattern[second_slash + 1 ..];
        const global = std.mem.indexOfScalar(u8, flags, 'g') != null;
        const confirm = std.mem.indexOfScalar(u8, flags, 'c') != null;

        // Determine if it's global (entire file) or current line
        const is_global_range = std.mem.startsWith(u8, command, "%s/");

        // Perform the substitution
        try editor.substitute(pattern, replacement, is_global_range, global, confirm);
    }

    fn openFile(self: *GrimApp, filepath: []const u8) !void {
        const editor = self.layout_manager.getActiveEditor() orelse return error.NoActiveEditor;
        try editor.loadFile(filepath);
    }

    fn saveCurrentBuffer(self: *GrimApp) !void {
        const editor = self.layout_manager.getActiveEditor() orelse return error.NoActiveEditor;
        try editor.saveFile();
    }

    fn openTerminal(self: *GrimApp, cmd: ?[]const u8) !void {
        // Get terminal size from layout manager
        const term_rows: u16 = @max(self.layout_manager.height / 2, 10);
        const term_cols: u16 = self.layout_manager.width;

        // Create terminal widget
        const term = try terminal_widget.TerminalWidget.init(self.allocator, term_rows, term_cols);
        errdefer term.deinit();

        // Spawn shell or command
        try term.spawn(cmd);

        // Store in layout manager's terminal list
        try self.layout_manager.terminals.append(self.allocator, term);

        // Activate the newly created terminal
        const term_index = self.layout_manager.terminals.items.len - 1;
        self.layout_manager.activateTerminal(term_index);

        std.log.info("Terminal opened{s}", .{if (cmd) |c| blk: {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, " with command: {s}", .{c}) catch "";
            break :blk msg;
        } else ""});
    }

    fn hideSystemCursor(_: *GrimApp) !void {
        try std.fs.File.stdout().writeAll("\x1b[?25l");
    }

    fn showSystemCursor(_: *GrimApp) !void {
        try std.fs.File.stdout().writeAll("\x1b[?25h");
    }

    // === Compatibility methods for main.zig ===

    pub fn setTheme(self: *GrimApp, name: []const u8) !void {
        // Check theme registry first (for plugin themes)
        if (self.theme_registry.get(name)) |plugin_theme| {
            self.active_theme = plugin_theme;
            return;
        }

        // Check for plugin::theme syntax
        if (std.mem.indexOf(u8, name, "::")) |sep| {
            const plugin_id = name[0..sep];
            const plugin_theme_name = name[sep + 2 ..];
            if (plugin_theme_name.len > 0) {
                if (self.theme_registry.getPluginTheme(plugin_id, plugin_theme_name)) |plugin_theme_value| {
                    self.active_theme = plugin_theme_value;
                    return;
                }
            }
        }

        // Load built-in theme
        self.active_theme = try theme_mod.Theme.get(name);
    }

    /// Apply configuration settings to the editor
    pub fn applyConfig(self: *GrimApp) !void {
        const config = self.config_manager.getConfig();

        // Apply theme if configured
        if (config.ui.theme.len > 0) {
            self.setTheme(config.ui.theme) catch |err| {
                std.log.warn("Failed to apply theme from config: {}", .{err});
            };
        }

        // Apply editor settings to all active editors
        if (self.layout_manager.getActiveEditor()) |editor| {
            editor.tab_size = @intCast(config.editor.tab_width);
            editor.expand_tab = config.editor.use_spaces;
            // More editor settings can be applied here
        }

        std.log.info("Applied configuration", .{});
    }

    pub fn attachPluginManager(self: *GrimApp, manager: *runtime.PluginManager) void {
        self.plugin_manager = manager;
        manager.setThemeCallbacks(
            @as(*anyopaque, @ptrCast(&self.theme_registry)),
            theme_mod.registerThemeCallback,
            theme_mod.unregisterThemeCallback,
        );
    }

    pub fn attachEditorLSP(self: *GrimApp, editor_lsp: *editor_lsp_mod.EditorLSP) void {
        self.editor_lsp = editor_lsp;

        // Attach LSP to all editor widgets in the layout
        const all_editors = self.layout_manager.getAllEditors();
        for (all_editors) |editor_widget| {
            editor_widget.attachLSP(editor_lsp);
        }
    }

    pub fn detachEditorLSP(self: *GrimApp) void {
        // Detach LSP from all editor widgets
        if (self.editor_lsp != null) {
            const all_editors = self.layout_manager.getAllEditors();
            for (all_editors) |editor_widget| {
                editor_widget.detachLSP();
            }
        }
        self.editor_lsp = null;
    }

    pub fn setEditorContext(self: *GrimApp, ctx: *runtime.PluginAPI.EditorContext) void {
        self.editor_context = ctx;
        ctx.active_buffer_id = self.current_buffer_id;
    }

    pub fn getActiveBufferId(self: *const GrimApp) runtime.PluginAPI.BufferId {
        return self.current_buffer_id;
    }

    pub fn makeEditorBridge(self: *GrimApp) runtime.PluginAPI.EditorContext.EditorBridge {
        return .{
            .ctx = @as(*anyopaque, @ptrCast(self)),
            .getCurrentBuffer = bridgeGetCurrentBuffer,
            .getCursorPosition = bridgeGetCursorPosition,
            .setCursorPosition = bridgeSetCursorPosition,
            .getSelection = bridgeGetSelection,
            .setSelection = bridgeSetSelection,
            .notifyChange = bridgeNotifyChange,
        };
    }

    pub fn closeActiveBuffer(self: *GrimApp) void {
        const editor = self.layout_manager.getActiveEditor() orelse return;
        if (editor.editor.current_filename) |path| {
            if (self.editor_lsp) |lsp| {
                lsp.closeFile(path) catch |err| {
                    std.log.warn("Failed to close LSP document: {}", .{err});
                };
            }
        }
    }

    pub fn loadFile(self: *GrimApp, filepath: []const u8) !void {
        try self.openFile(filepath);
    }

    /// Open a file in a new tab
    pub fn openFileInNewTab(self: *GrimApp, filepath: []const u8) !void {
        // Create new tab
        try self.layout_manager.newTab();

        // Load file into the new tab's editor
        try self.openFile(filepath);
    }
};

// === EditorBridge callbacks ===

fn bridgeGetCurrentBuffer(ctx: *anyopaque) runtime.PluginAPI.BufferId {
    const self: *GrimApp = @ptrCast(@alignCast(ctx));
    return self.current_buffer_id;
}

fn bridgeGetCursorPosition(ctx: *anyopaque) runtime.PluginAPI.EditorContext.CursorPosition {
    const self: *GrimApp = @ptrCast(@alignCast(ctx));
    const editor = self.layout_manager.getActiveEditor() orelse return .{ .line = 0, .column = 0, .byte_offset = 0 };
    const line_col = editor.editor.rope.lineColumnAtOffset(editor.editor.cursor.offset) catch return .{ .line = 0, .column = 0, .byte_offset = 0 };
    return .{
        .line = line_col.line,
        .column = line_col.column,
        .byte_offset = editor.editor.cursor.offset,
    };
}

fn bridgeSetCursorPosition(ctx: *anyopaque, pos: runtime.PluginAPI.EditorContext.CursorPosition) !void {
    const self: *GrimApp = @ptrCast(@alignCast(ctx));
    const editor = self.layout_manager.getActiveEditor() orelse return;
    // Convert line/column to offset using rope
    const line_col_result = editor.editor.rope.lineColumnAtOffset(editor.editor.cursor.offset) catch return;
    _ = line_col_result;
    _ = pos;
    // TODO: Implement proper line/column to offset conversion
}

fn bridgeGetSelection(ctx: *anyopaque) ?runtime.PluginAPI.EditorContext.SelectionRange {
    const self: *GrimApp = @ptrCast(@alignCast(ctx));
    const editor = self.layout_manager.getActiveEditor() orelse return null;
    if (editor.editor.selection_start) |start| {
        if (editor.editor.selection_end) |end| {
            return .{ .start = start, .end = end };
        }
    }
    return null;
}

fn bridgeSetSelection(ctx: *anyopaque, selection: ?runtime.PluginAPI.EditorContext.SelectionRange) !void {
    const self: *GrimApp = @ptrCast(@alignCast(ctx));
    const editor = self.layout_manager.getActiveEditor() orelse return;
    if (selection) |sel| {
        editor.editor.selection_start = sel.start;
        editor.editor.selection_end = sel.end;
    } else {
        editor.editor.selection_start = null;
        editor.editor.selection_end = null;
    }
}

fn bridgeNotifyChange(ctx: *anyopaque, change: runtime.PluginAPI.EditorContext.BufferChange) anyerror!void {
    const self: *GrimApp = @ptrCast(@alignCast(ctx));
    _ = change;

    // Mark syntax highlighting as dirty (needs re-parse)
    const editor = self.layout_manager.getActiveEditor() orelse return;
    editor.highlight_dirty = true;

    // Update cursor position if plugin modified it
    if (self.plugin_cursor) |cursor_ptr| {
        // TODO: Convert cursor_ptr line/column to offset
        _ = cursor_ptr;
    }

    // Notify LSP of buffer change
    if (self.editor_lsp) |lsp| {
        if (editor.editor.current_filename) |path| {
            lsp.notifyBufferChange(path) catch |err| {
                std.log.warn("Failed to notify LSP of buffer change: {}", .{err});
            };
        }
    }
}

// Global app context for event handler
var grim_app_context: ?*GrimApp = null;

/// Main Phantom event handler
fn grimEventHandler(event: phantom.Event) !bool {
    const app = grim_app_context orelse return false;
    return try app.handleEvent(event);
}

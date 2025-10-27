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
const status_bar_flex = @import("status_bar_flex.zig");

// LSP widgets
const lsp_completion_menu = @import("lsp_completion_menu.zig");
const lsp_hover_widget = @import("lsp_hover_widget.zig");
const lsp_diagnostics_panel = @import("lsp_diagnostics_panel.zig");
const lsp_loading_spinner = @import("lsp_loading_spinner.zig");

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
    status_bar: *status_bar_flex.StatusBar,

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

        // Initialize status bar
        const status_bar = try status_bar_flex.StatusBar.init(allocator, term_size.width);
        errdefer status_bar.deinit();

        // Initialize Git
        const git = core.Git.init(allocator);

        // Initialize Harpoon
        const harpoon = core.Harpoon.init(allocator);

        // Initialize Fuzzy finder
        const fuzzy = core.FuzzyFinder.init(allocator);

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
        };

        // Create initial editor (needed even if opening a file)
        try self.layout_manager.createInitialEditor();

        // Load initial file if specified
        if (config.initial_file) |file_path| {
            try self.openFile(file_path);
        }

        return self;
    }

    pub fn deinit(self: *GrimApp) void {
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
            .ctrl_r => {
                // Redo
                try self.layout_manager.getActiveEditor().?.redo();
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
                        try editor.deleteSelection();
                        self.mode = .normal;
                        return true;
                    },
                    'y' => {
                        try editor.yankSelection();
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

        // Editor area (everything except bottom 2 lines)
        const editor_area = phantom.Rect{
            .x = 0,
            .y = 0,
            .width = term_size.width,
            .height = if (term_size.height > 2) term_size.height - 2 else 0,
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

        // Render layout manager (handles all editor windows/splits/tabs)
        self.layout_manager.render(buffer, editor_area);

        // Update and render status bar
        if (self.layout_manager.getActiveEditor()) |active_editor| {
            try self.status_bar.update(active_editor, self.mode);
        }
        self.status_bar.render(buffer, status_bar_area);

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

        // Parse command
        if (std.mem.eql(u8, command, "q") or std.mem.eql(u8, command, "quit")) {
            // TODO: Check for unsaved buffers
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
        } else if (std.mem.startsWith(u8, command, "%s/") or std.mem.startsWith(u8, command, "s/")) {
            // Substitute command: :%s/pattern/replacement/flags or :s/pattern/replacement/flags
            try self.handleSubstitute(command);
        } else {
            // Unknown command
            std.log.warn("Unknown command: {s}", .{command});
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
    }

    pub fn detachEditorLSP(self: *GrimApp) void {
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

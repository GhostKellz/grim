//! Grim Editor - Neovim alternative in Zig powered by Phantom TUI
//! Main application structure using Phantom App framework

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const runtime = @import("runtime");
const Editor = @import("editor.zig").Editor;

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

    // Plugin system
    plugin_manager: ?*runtime.PluginManager,

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
        const phantom_config = phantom.AppConfig{
            .title = "Grim Editor",
            .tick_rate_ms = config.tick_rate_ms,
            .mouse_enabled = config.mouse_enabled,
            .resize_enabled = true,
        };

        var phantom_app = try phantom.App.init(allocator, phantom_config);
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

        self.* = .{
            .allocator = allocator,
            .phantom_app = phantom_app,
            .config = config,
            .layout_manager = layout_manager,
            .command_bar = command_bar,
            .status_bar = status_bar,
            .mode = .normal,
            .running = true,
            .plugin_manager = null,
            .git = git,
            .harpoon = harpoon,
            .fuzzy = fuzzy,
        };

        // Open initial file if specified
        if (config.initial_file) |file_path| {
            try self.openFile(file_path);
        } else {
            // Create empty buffer
            try self.layout_manager.createInitialEditor();
        }

        return self;
    }

    pub fn deinit(self: *GrimApp) void {
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

        // Add main event handler
        try self.phantom_app.event_loop.addHandler(grimEventHandler);

        // Enable raw mode and alternate screen
        try self.phantom_app.terminal.enableRawMode();
        defer self.phantom_app.terminal.disableRawMode() catch {};

        // Hide cursor (we'll draw it manually)
        try self.hideSystemCursor();
        defer self.showSystemCursor() catch {};

        // Main loop
        self.running = true;
        while (self.running) {
            // Handle events
            const event = try self.phantom_app.event_loop.pollEvent();

            if (event) |evt| {
                const handled = try self.handleEvent(evt);
                if (!handled) {
                    // Event wasn't handled, might need to stop
                    if (evt == .key and (evt.key == .ctrl_c or evt.key == .escape)) {
                        self.running = false;
                    }
                }
            }

            // Render
            try self.render();

            // Sleep for tick rate
            std.time.sleep(self.config.tick_rate_ms * std.time.ns_per_ms);
        }
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
                        const new_size = try phantom.getTerminalSize();
                        try self.handleResize(new_size);
                        return true;
                    },
                    else => return false,
                }
            },
            .tick => {
                // Tick events handled by render loop
                return false;
            },
        }
    }

    /// Handle keyboard input based on current mode
    fn handleKeyEvent(self: *GrimApp, key: phantom.Key) !bool {
        // Command bar has priority
        if (self.command_bar.visible) {
            return try self.command_bar.handleKey(key, self);
        }

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

                    // Quit
                    'q' => {
                        // TODO: Handle unsaved buffers
                        self.running = false;
                        return true;
                    },

                    else => return false,
                }
            },
            .ctrl_c => {
                self.running = false;
                return true;
            },
            .ctrl_w => {
                // Window commands - delegate to layout manager
                return try self.layout_manager.handleWindowCommand(self);
            },
            else => return false,
        }
    }

    fn handleInsertMode(self: *GrimApp, key: phantom.Key) !bool {
        const editor = self.layout_manager.getActiveEditor() orelse return false;

        switch (key) {
            .escape => {
                self.mode = .normal;
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

    fn handleCommandMode(self: *GrimApp, key: phantom.Key) !bool {
        // Handled by command_bar
        return false;
    }

    fn handleSearchMode(self: *GrimApp, key: phantom.Key) !bool {
        // Handled by command_bar
        return false;
    }

    fn handleReplaceMode(self: *GrimApp, key: phantom.Key) !bool {
        // TODO: Implement replace mode
        _ = key;
        return false;
    }

    fn handleMouseEvent(self: *GrimApp, mouse: phantom.MouseEvent) !bool {
        // Delegate to layout manager to find which editor was clicked
        return try self.layout_manager.handleMouse(mouse, self);
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
        try self.layout_manager.render(buffer, editor_area);

        // Update and render status bar
        if (self.layout_manager.getActiveEditor()) |active_editor| {
            try self.status_bar.update(active_editor.editor);
        }
        try self.status_bar.render(buffer, status_bar_area);

        // Render command bar if visible
        if (self.command_bar.visible) {
            try self.command_bar.render(buffer, command_bar_area);
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
        } else {
            // Unknown command
            std.log.warn("Unknown command: {s}", .{command});
        }
    }

    fn openFile(self: *GrimApp, filepath: []const u8) !void {
        const editor = self.layout_manager.getActiveEditor() orelse return error.NoActiveEditor;
        try editor.loadFile(filepath);
    }

    fn saveCurrentBuffer(self: *GrimApp) !void {
        const editor = self.layout_manager.getActiveEditor() orelse return error.NoActiveEditor;
        try editor.saveFile();
    }

    fn hideSystemCursor(self: *GrimApp) !void {
        try std.fs.File.stdout().writeAll("\x1b[?25l");
    }

    fn showSystemCursor(self: *GrimApp) !void {
        try std.fs.File.stdout().writeAll("\x1b[?25h");
    }
};

// Global app context for event handler
var grim_app_context: ?*GrimApp = null;

/// Main Phantom event handler
fn grimEventHandler(event: phantom.Event) !bool {
    const app = grim_app_context orelse return false;
    return try app.handleEvent(event);
}

/// GrimApp using ZigZag event loop for maximum performance
/// Alternative to grim_app.zig - uses ZigZag instead of Phantom's event loop

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const runtime = @import("runtime");
const lsp = @import("lsp");

const Editor = core.Editor;
const Rope = core.Rope;
const grim_layout = @import("grim_layout.zig");
const powerline_status = @import("powerline_status.zig");
const grim_command_bar = @import("grim_command_bar.zig");

const zigzag_adapter = @import("zigzag_adapter.zig");

/// Editor mode
pub const GrimMode = enum {
    normal,
    insert,
    visual,
    visual_line,
    visual_block,
    command,
    search,
    replace,
};

/// Configuration for Grim
pub const GrimConfig = struct {
    tick_rate_ms: u64 = 16, // ~60 FPS
    mouse_enabled: bool = false,
};

/// Main application state
pub const GrimAppZigZag = struct {
    allocator: std.mem.Allocator,

    // ZigZag event loop bridge
    zigzag_bridge: *zigzag_adapter.ZigZagPhantomBridge,

    // Phantom terminal for rendering
    phantom_terminal: phantom.Terminal,

    // UI components
    layout_manager: *grim_layout.LayoutManager,
    status_bar: *powerline_status.PowerlineStatus,
    command_bar_widget: *grim_command_bar.CommandBar,

    // LSP and plugins
    plugin_manager: ?*runtime.PluginManager,

    // State
    mode: GrimMode = .normal,
    running: bool = true,
    config: GrimConfig,

    // Git integration
    git: core.Git,

    pub fn init(allocator: std.mem.Allocator, config: GrimConfig) !*GrimAppZigZag {
        const self = try allocator.create(GrimAppZigZag);
        errdefer allocator.destroy(self);

        // Initialize Phantom Terminal (for rendering only, not event loop)
        var phantom_terminal = try phantom.Terminal.init(allocator);
        errdefer phantom_terminal.deinit();

        // Get terminal size
        const term_size = phantom_terminal.size;

        // Initialize ZigZag bridge
        var zigzag_bridge = try zigzag_adapter.ZigZagPhantomBridge.init(allocator, term_size);
        errdefer zigzag_bridge.deinit();

        // Initialize layout manager
        const layout_manager = try grim_layout.LayoutManager.init(
            allocator,
            term_size.width,
            term_size.height - 2, // Reserve 2 rows for status bar and command bar
        );
        errdefer layout_manager.deinit();

        // Initialize UI components (powerlevel10k style)
        const status_bar = try powerline_status.PowerlineStatus.init(allocator, term_size.width);
        errdefer status_bar.deinit();

        const command_bar_widget = try grim_command_bar.CommandBar.init(allocator);
        errdefer command_bar_widget.deinit();

        // Plugin manager (not initialized for ZigZag version)
        const plugin_manager: ?*runtime.PluginManager = null;

        self.* = .{
            .allocator = allocator,
            .zigzag_bridge = zigzag_bridge,
            .phantom_terminal = phantom_terminal,
            .layout_manager = layout_manager,
            .status_bar = status_bar,
            .command_bar_widget = command_bar_widget,
            .plugin_manager = plugin_manager,
            .config = config,
            .git = core.Git.init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *GrimAppZigZag) void {
        if (self.plugin_manager) |pm| pm.deinit();
        self.git.deinit();
        self.status_bar.deinit();
        self.command_bar_widget.deinit();
        self.layout_manager.deinit();
        self.phantom_terminal.deinit();
        self.zigzag_bridge.deinit();
        self.allocator.destroy(self);
    }

    /// Open a file in the editor
    pub fn openFile(self: *GrimAppZigZag, path: []const u8) !void {
        // Just load file into active editor
        if (self.layout_manager.getActiveEditor()) |editor_widget| {
            try editor_widget.editor.loadFile(path);
        }
    }

    /// Main run loop using ZigZag
    pub fn run(self: *GrimAppZigZag) !void {
        // Enable raw mode via Phantom terminal
        try self.phantom_terminal.enableRawMode();
        defer self.phantom_terminal.disableRawMode() catch {};

        // Add our event handler to ZigZag bridge
        try self.zigzag_bridge.addHandler(handleEventWrapper);

        // Set up global context for event handler
        grim_app_zigzag_context = self;

        // Watch stdin for keyboard input
        try self.zigzag_bridge.watchStdin();

        // Add tick timer for rendering (60 FPS = 16ms)
        try self.zigzag_bridge.addTickTimer(self.config.tick_rate_ms);

        // Hide cursor (we'll draw it manually)
        try self.hideSystemCursor();
        defer self.showSystemCursor() catch {};

        // Initial render
        try self.render();

        // Run ZigZag event loop
        try self.zigzag_bridge.run();
    }

    /// Handle events
    fn handleEvent(self: *GrimAppZigZag, event: phantom.Event) !bool {
        switch (event) {
            .key => |key| {
                return try self.handleKeyEvent(key);
            },
            .tick => {
                try self.render();
                return true;
            },
            else => return false,
        }
    }

    /// Handle keyboard input based on current mode
    fn handleKeyEvent(self: *GrimAppZigZag, key: phantom.Key) !bool {
        // TODO: Command bar handling
        _ = self.command_bar_widget;

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

    fn handleNormalMode(self: *GrimAppZigZag, key: phantom.Key) !bool {
        const editor = self.layout_manager.getActiveEditor() orelse return false;

        switch (key) {
            .char => |c| {
                switch (c) {
                    'i' => {
                        self.mode = .insert;
                        return true;
                    },
                    'v' => {
                        self.mode = .visual;
                        try editor.startVisualMode();
                        return true;
                    },
                    ':' => {
                        self.mode = .command;
                        self.command_bar_widget.show(.command);
                        return true;
                    },
                    'q' => {
                        self.running = false;
                        self.zigzag_bridge.stop();
                        return true;
                    },
                    'h' => try editor.moveCursorLeft(),
                    'j' => try editor.moveCursorDown(),
                    'k' => try editor.moveCursorUp(),
                    'l' => try editor.moveCursorRight(),
                    else => {},
                }
            },
            .left => try editor.moveCursorLeft(),
            .right => try editor.moveCursorRight(),
            .up => try editor.moveCursorUp(),
            .down => try editor.moveCursorDown(),
            .escape => {
                self.mode = .normal;
                return true;
            },
            else => {},
        }

        return true;
    }

    fn handleInsertMode(self: *GrimAppZigZag, key: phantom.Key) !bool {
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
                try editor.insertTab();
                return true;
            },
            .left => {
                try editor.moveCursorLeft();
                return true;
            },
            .right => {
                try editor.moveCursorRight();
                return true;
            },
            .up => {
                try editor.moveCursorUp();
                return true;
            },
            .down => {
                try editor.moveCursorDown();
                return true;
            },
            else => return false,
        }
    }

    fn handleVisualMode(self: *GrimAppZigZag, key: phantom.Key) !bool {
        const editor = self.layout_manager.getActiveEditor() orelse return false;

        switch (key) {
            .escape => {
                self.mode = .normal;
                return true;
            },
            .char => |c| {
                switch (c) {
                    'y' => {
                        // TODO: Yank selection
                        self.mode = .normal;
                        return true;
                    },
                    'd' => {
                        // TODO: Delete selection
                        self.mode = .normal;
                        return true;
                    },
                    'h' => {
                        try editor.moveCursorLeft();
                        return true;
                    },
                    'j' => {
                        try editor.moveCursorDown();
                        return true;
                    },
                    'k' => {
                        try editor.moveCursorUp();
                        return true;
                    },
                    'l' => {
                        try editor.moveCursorRight();
                        return true;
                    },
                    else => return false,
                }
            },
            .left => {
                try editor.moveCursorLeft();
                return true;
            },
            .right => {
                try editor.moveCursorRight();
                return true;
            },
            .up => {
                try editor.moveCursorUp();
                return true;
            },
            .down => {
                try editor.moveCursorDown();
                return true;
            },
            else => return false,
        }
    }

    fn handleCommandMode(self: *GrimAppZigZag, key: phantom.Key) !bool {
        _ = self;
        _ = key;
        return false;
    }

    fn handleSearchMode(self: *GrimAppZigZag, key: phantom.Key) !bool {
        _ = self;
        _ = key;
        return false;
    }

    fn handleReplaceMode(self: *GrimAppZigZag, key: phantom.Key) !bool {
        _ = self;
        _ = key;
        return false;
    }

    /// Render the application
    fn render(self: *GrimAppZigZag) !void {
        try self.phantom_terminal.clear();
        const buffer = self.phantom_terminal.getBackBuffer();

        // Render layout (editor windows)
        const term_size = self.phantom_terminal.size;
        const editor_area = phantom.Rect.init(0, 0, term_size.width, term_size.height - 2);
        self.layout_manager.render(buffer, editor_area);

        // Render status bar (powerlevel10k style)
        const status_area = phantom.Rect.init(0, term_size.height - 2, term_size.width, 1);
        if (self.layout_manager.getActiveEditor()) |active_editor| {
            try self.status_bar.render(buffer, status_area, active_editor, self.mode, &self.git);
        }

        // Render command bar
        const command_area = phantom.Rect.init(0, term_size.height - 1, term_size.width, 1);
        self.command_bar_widget.render(buffer, command_area);

        try self.phantom_terminal.flush();
    }

    fn hideSystemCursor(self: *GrimAppZigZag) !void {
        // Cursor is handled manually in rendering
        _ = self;
    }

    fn showSystemCursor(self: *GrimAppZigZag) !void {
        // Cursor is handled manually in rendering
        _ = self;
    }
};

// Global app context for event handler
var grim_app_zigzag_context: ?*GrimAppZigZag = null;

/// Wrapper for event handler to bridge C-style callback to method call
fn handleEventWrapper(event: phantom.Event) !bool {
    const app = grim_app_zigzag_context orelse return false;
    return try app.handleEvent(event);
}

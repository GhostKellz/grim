const std = @import("std");
const runtime = @import("runtime");
const syntax = @import("syntax");
const theme_mod = @import("theme.zig");
const Editor = @import("editor.zig").Editor;
const editor_lsp_mod = @import("editor_lsp.zig");
const buffer_manager_mod = @import("buffer_manager.zig");
const window_manager_mod = @import("window_manager.zig");
const buffer_picker_mod = @import("buffer_picker.zig");

pub const SimpleTUI = struct {
    allocator: std.mem.Allocator,
    editor: Editor,
    running: bool,
    stdin: std.fs.File,
    stdout: std.fs.File,
    theme_registry: theme_mod.ThemeRegistry,
    active_theme: theme_mod.Theme,
    plugin_manager: ?*runtime.PluginManager,
    editor_lsp: ?*editor_lsp_mod.EditorLSP,
    highlight_cache: []syntax.HighlightRange,
    highlight_dirty: bool,
    highlight_error: ?[]u8,
    highlight_error_flash: bool,
    highlight_error_flash_state: bool,
    highlight_error_logged: bool,
    command_buffer: std.ArrayList(u8),
    status_message: ?[]u8,
    plugin_cursor: ?*runtime.PluginAPI.EditorContext.CursorPosition,
    editor_context: ?*runtime.PluginAPI.EditorContext,
    current_buffer_id: runtime.PluginAPI.BufferId,
    next_buffer_id: runtime.PluginAPI.BufferId,
    completion_popup_active: bool,
    completion_selected_index: usize,
    completion_items: []editor_lsp_mod.Completion,
    completion_items_heap: bool,
    completion_prefix: std.ArrayList(u8),
    completion_anchor_offset: ?usize,
    completion_generation_seen: u64,
    completion_dirty: bool,
    // New integration components
    buffer_manager: ?*buffer_manager_mod.BufferManager,
    window_manager: ?*window_manager_mod.WindowManager,
    buffer_picker: ?*buffer_picker_mod.BufferPicker,
    buffer_picker_active: bool,
    window_command_pending: bool,

    pub fn init(allocator: std.mem.Allocator) !*SimpleTUI {
        var command_buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer command_buffer.deinit(allocator);
        var completion_prefix = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer completion_prefix.deinit(allocator);
        const self = try allocator.create(SimpleTUI);
        self.* = .{
            .allocator = allocator,
            .editor = try Editor.init(allocator),
            .running = true,
            .stdin = std.fs.File.stdin(),
            .stdout = std.fs.File.stdout(),
            .theme_registry = theme_mod.ThemeRegistry.init(allocator),
            .active_theme = theme_mod.Theme.defaultDark(),
            .plugin_manager = null,
            .editor_lsp = null,
            .highlight_cache = &.{},
            .highlight_dirty = true,
            .highlight_error = null,
            .highlight_error_flash = false,
            .highlight_error_flash_state = false,
            .highlight_error_logged = false,
            .command_buffer = command_buffer,
            .status_message = null,
            .plugin_cursor = null,
            .editor_context = null,
            .current_buffer_id = 1,
            .next_buffer_id = 2,
            .completion_popup_active = false,
            .completion_selected_index = 0,
            .completion_items = &.{},
            .completion_items_heap = false,
            .completion_prefix = completion_prefix,
            .completion_anchor_offset = null,
            .completion_generation_seen = 0,
            .completion_dirty = false,
            .buffer_manager = null,
            .window_manager = null,
            .buffer_picker = null,
            .buffer_picker_active = false,
            .window_command_pending = false,
        };
        return self;
    }

    pub fn deinit(self: *SimpleTUI) void {
        self.clearCompletionDisplay();
        self.completion_prefix.deinit(self.allocator);
        if (self.highlight_cache.len > 0) {
            self.allocator.free(self.highlight_cache);
        }
        if (self.highlight_error) |msg| {
            self.allocator.free(msg);
        }
        if (self.status_message) |msg| {
            self.allocator.free(msg);
        }
        if (self.buffer_picker) |picker| {
            picker.deinit();
            self.allocator.destroy(picker);
        }
        if (self.window_manager) |win_mgr| {
            win_mgr.deinit();
            self.allocator.destroy(win_mgr);
        }
        if (self.buffer_manager) |buf_mgr| {
            buf_mgr.deinit();
            self.allocator.destroy(buf_mgr);
        }
        self.command_buffer.deinit(self.allocator);
        self.theme_registry.deinit();
        self.editor.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *SimpleTUI) !void {
        try self.enableRawMode();
        defer self.disableRawMode() catch {};

        try self.clearScreen();
        try self.showCursor();

        while (self.running) {
            try self.render();
            try self.handleInput();
        }
    }

    pub fn loadFile(self: *SimpleTUI, path: []const u8) !void {
        const reuse_buffer = blk: {
            if (self.editor.current_filename) |existing| {
                break :blk std.mem.eql(u8, existing, path);
            }
            break :blk false;
        };

        try self.editor.loadFile(path);
        self.closeCompletionPopup();
        self.markHighlightsDirty();

        const filename = self.editor.current_filename orelse path;

        if (!reuse_buffer) {
            const previous_id = self.current_buffer_id;
            const new_id = self.allocateBufferId();
            self.setActiveBufferId(new_id);
            if (previous_id != new_id) {
                self.emitBufferClosed(previous_id);
            }
            self.emitBufferCreated(new_id);
            self.emitBufferOpened(new_id, filename);
        } else {
            self.emitBufferOpened(self.current_buffer_id, filename);
        }

        if (self.editor_lsp) |lsp| {
            lsp.openFile(filename) catch |err| {
                std.log.warn("Failed to open file for LSP: {}", .{err});
            };
        }

        if (self.plugin_manager) |manager| {
            manager.emitEvent(.file_opened, .{ .file_opened = path }) catch |err| {
                std.log.err("Failed to emit file_opened event: {}", .{err});
            };
        }
    }

    pub fn setTheme(self: *SimpleTUI, name: []const u8) !void {
        if (self.theme_registry.get(name)) |plugin_theme| {
            self.active_theme = plugin_theme;
            self.markHighlightsDirty();
            return;
        }

        if (std.mem.indexOf(u8, name, "::")) |sep| {
            const plugin_id = name[0..sep];
            const plugin_theme_name = name[sep + 2 ..];
            if (plugin_theme_name.len > 0) {
                if (self.theme_registry.getPluginTheme(plugin_id, plugin_theme_name)) |plugin_theme_value| {
                    self.active_theme = plugin_theme_value;
                    self.markHighlightsDirty();
                    return;
                }
            }
        }

        self.active_theme = try theme_mod.Theme.get(name);
        self.markHighlightsDirty();
    }

    fn setStatusMessage(self: *SimpleTUI, message: []const u8) void {
        if (self.status_message) |existing| {
            self.allocator.free(existing);
        }
        const duped = self.allocator.dupe(u8, message) catch |err| {
            std.log.warn("Failed to allocate status message: {}", .{err});
            self.status_message = null;
            return;
        };
        self.status_message = duped;
    }

    fn clearStatusMessage(self: *SimpleTUI) void {
        if (self.status_message) |existing| {
            self.allocator.free(existing);
            self.status_message = null;
        }
    }

    pub fn attachPluginManager(self: *SimpleTUI, manager: *runtime.PluginManager) void {
        self.plugin_manager = manager;
        manager.setThemeCallbacks(
            @as(*anyopaque, @ptrCast(&self.theme_registry)),
            theme_mod.registerThemeCallback,
            theme_mod.unregisterThemeCallback,
        );

        self.emitBufferCreated(self.current_buffer_id);
        if (self.editor.current_filename) |filename| {
            self.emitBufferOpened(self.current_buffer_id, filename);
        }
    }

    pub fn attachEditorLSP(self: *SimpleTUI, editor_lsp: *editor_lsp_mod.EditorLSP) void {
        self.editor_lsp = editor_lsp;
    }

    pub fn detachEditorLSP(self: *SimpleTUI) void {
        self.editor_lsp = null;
    }

    pub fn setEditorContext(self: *SimpleTUI, ctx: *runtime.PluginAPI.EditorContext) void {
        self.editor_context = ctx;
        ctx.active_buffer_id = self.current_buffer_id;
    }

    pub fn getActiveBufferId(self: *const SimpleTUI) runtime.PluginAPI.BufferId {
        return self.current_buffer_id;
    }

    fn setActiveBufferId(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId) void {
        self.current_buffer_id = buffer_id;
        if (self.editor_context) |ctx| {
            ctx.active_buffer_id = buffer_id;
        }
    }

    fn allocateBufferId(self: *SimpleTUI) runtime.PluginAPI.BufferId {
        const candidate = self.next_buffer_id;
        if (candidate == std.math.maxInt(runtime.PluginAPI.BufferId)) {
            std.log.err("Buffer id counter exhausted", .{});
            return candidate;
        }
        self.next_buffer_id = candidate + 1;
        return candidate;
    }

    fn emitBufferCreated(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_created, .{ .buffer_created = buffer_id }) catch |err| {
                std.log.err("Failed to emit buffer_created event: {}", .{err});
            };
        }
    }

    fn emitBufferOpened(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId, filename: []const u8) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_opened, .{ .buffer_opened = .{ .buffer_id = buffer_id, .filename = filename } }) catch |err| {
                std.log.err("Failed to emit buffer_opened event: {}", .{err});
            };
        }
    }

    fn emitBufferSaved(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId, filename: []const u8) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_saved, .{ .buffer_saved = .{ .buffer_id = buffer_id, .filename = filename } }) catch |err| {
                std.log.err("Failed to emit buffer_saved event: {}", .{err});
            };
        }
    }

    fn emitBufferClosed(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_closed, .{ .buffer_closed = buffer_id }) catch |err| {
                std.log.err("Failed to emit buffer_closed event: {}", .{err});
            };
        }
    }

    pub fn closeActiveBuffer(self: *SimpleTUI) void {
        if (self.editor.current_filename) |path| {
            if (self.editor_lsp) |lsp| {
                lsp.closeFile(path) catch |err| {
                    std.log.warn("Failed to close LSP document: {}", .{err});
                };
            }
        }
        self.emitBufferClosed(self.current_buffer_id);
    }

    fn render(self: *SimpleTUI) !void {
        // Get terminal size (simplified)
        const width = 80;
        const height = 24;

        self.applyPendingDefinition();

        try self.clearScreen();
        try self.setCursor(1, 1);

        self.refreshHighlights();
        self.updatePluginCursorFromEditor();

        if (self.highlight_error_flash) {
            self.highlight_error_flash_state = !self.highlight_error_flash_state;
        } else {
            self.highlight_error_flash_state = false;
        }

        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        defer self.allocator.free(content);

        const content_width: usize = if (width > 6) width - 6 else 0;

        var diagnostics_entries: []const editor_lsp_mod.Diagnostic = &[_]editor_lsp_mod.Diagnostic{};
        if (self.editor_lsp) |lsp| {
            if (self.editor.current_filename) |filename| {
                diagnostics_entries = lsp.getDiagnostics(filename) orelse diagnostics_entries;
            }
        }

        var line_start: usize = 0;
        var logical_line: usize = 0;

        while (logical_line < height - 2 and line_start <= content.len) {
            const remaining = content[line_start..];
            const rel_newline = std.mem.indexOfScalar(u8, remaining, '\n');
            const line_end = if (rel_newline) |rel| line_start + rel else content.len;
            const line_slice = content[line_start..line_end];

            // Line numbers + diagnostic marker column
            var line_buf: [16]u8 = undefined;
            const line_str = try std.fmt.bufPrint(&line_buf, "{d:4}", .{logical_line + 1});
            try self.stdout.writeAll(line_str);

            const line_diag = selectLineDiagnostic(diagnostics_entries, logical_line);
            const marker = if (line_diag) |diag| severityMarker(diag.severity) else ' ';
            var marker_buf = [1]u8{marker};
            try self.stdout.writeAll(marker_buf[0..]);
            try self.stdout.writeAll(" ");

            if (content_width > 0) {
                try self.renderHighlightedLine(line_slice, logical_line, content_width);
            }

            try self.stdout.writeAll("\r\n");

            line_start = if (rel_newline) |_| line_end + 1 else content.len + 1;
            logical_line += 1;
        }

        while (logical_line < height - 2) : (logical_line += 1) {
            try self.stdout.writeAll("~\r\n");
        }

        try self.renderCompletionBar(width, height);

        // Status line
        try self.setCursor(height, 1);
        const flash_on = self.highlight_error_flash and self.highlight_error_flash_state;
        if (flash_on) {
            try self.setColor(41, 97);
        } else blk: {
            var bg_buf: [32]u8 = undefined;
            var fg_buf: [32]u8 = undefined;
            const bg_seq = self.active_theme.status_bar_bg.toBgSequence(&bg_buf) catch |err| {
                std.log.warn("Failed to apply status bar background color: {}", .{err});
                try self.setColor(47, 30);
                break :blk;
            };
            const fg_seq = self.active_theme.status_bar_fg.toFgSequence(&fg_buf) catch |err| {
                std.log.warn("Failed to apply status bar foreground color: {}", .{err});
                try self.setColor(47, 30);
                break :blk;
            };
            try self.stdout.writeAll(bg_seq);
            try self.stdout.writeAll(fg_seq);
        }

        const mode_str = switch (self.editor.mode) {
            .normal => "NORMAL",
            .insert => "INSERT",
            .visual => "VISUAL",
            .command => "COMMAND",
        };

        const cursor_line = self.getCursorLine();
        const cursor_col = self.getCursorColumn();
        const cursor_diag = selectLineDiagnostic(diagnostics_entries, cursor_line);

        const language = self.editor.getLanguageName();

        var status_buf: [512]u8 = undefined;
        var status_len: usize = 0;
        const base_slice = try std.fmt.bufPrint(status_buf[status_len..], " {s} | {d},{d} | {d} bytes | {s}", .{
            mode_str,
            cursor_line + 1,
            cursor_col + 1,
            self.editor.rope.len(),
            language,
        });
        status_len += base_slice.len;

        if (self.highlight_error) |err_msg| {
            const max_err_len: usize = 48;
            const trimmed_len = if (err_msg.len > max_err_len) max_err_len else err_msg.len;
            const warn_slice = try std.fmt.bufPrint(status_buf[status_len..], " | ! {s}", .{err_msg[0..trimmed_len]});
            status_len += warn_slice.len;
            if (err_msg.len > max_err_len) {
                const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                status_len += ellipsis_slice.len;
            }
        }

        if (self.status_message) |msg| {
            const max_msg_len: usize = 48;
            const trimmed_len = if (msg.len > max_msg_len) max_msg_len else msg.len;
            const msg_slice = try std.fmt.bufPrint(status_buf[status_len..], " | {s}", .{msg[0..trimmed_len]});
            status_len += msg_slice.len;
            if (msg.len > max_msg_len) {
                const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                status_len += ellipsis_slice.len;
            }
        }

        if (cursor_diag) |diag| {
            const label = severityLabel(diag.severity);
            const max_diag_len: usize = 60;
            const trimmed_len = if (diag.message.len > max_diag_len) max_diag_len else diag.message.len;
            const diag_slice = try std.fmt.bufPrint(status_buf[status_len..], " | {s}: {s}", .{ label, diag.message[0..trimmed_len] });
            status_len += diag_slice.len;
            if (diag.message.len > max_diag_len) {
                const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                status_len += ellipsis_slice.len;
            }
        }

        if (self.editor_lsp) |lsp| {
            if (lsp.getHoverInfo()) |hover| {
                if (hover.len > 0) {
                    const max_hover_len: usize = 40;
                    const trimmed_len = if (hover.len > max_hover_len) max_hover_len else hover.len;
                    const hover_slice = try std.fmt.bufPrint(status_buf[status_len..], " | Hover: {s}", .{hover[0..trimmed_len]});
                    status_len += hover_slice.len;
                    if (hover.len > max_hover_len) {
                        const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                        status_len += ellipsis_slice.len;
                    }
                }
            }
        }

        var status_slice: []const u8 = status_buf[0..status_len];
        var command_line_buf: [512]u8 = undefined;
        if (self.editor.mode == .command) {
            const input = self.command_buffer.items;
            const max_input_len = if (command_line_buf.len > 4) command_line_buf.len - 4 else 0;
            const needs_ellipsis = input.len > max_input_len;
            if (needs_ellipsis) {
                status_slice = try std.fmt.bufPrint(&command_line_buf, ":{s}...", .{input[0..max_input_len]});
            } else {
                status_slice = try std.fmt.bufPrint(&command_line_buf, ":{s}", .{input});
            }
        }

        // Pad with spaces to fill width
        const padding_len = if (status_slice.len < width) width - status_slice.len else 0;
        var final_status_buf: [512]u8 = undefined;
        const max_status_len: usize = final_status_buf.len;
        const copy_len: usize = @min(status_slice.len, max_status_len);
        @memcpy(final_status_buf[0..copy_len], status_slice[0..copy_len]);
        var total_len: usize = copy_len;
        if (padding_len > 0 and total_len < max_status_len) {
            const pad_count: usize = @min(padding_len, max_status_len - total_len);
            @memset(final_status_buf[total_len .. total_len + pad_count], ' ');
            total_len += pad_count;
        }
        const status = final_status_buf[0..total_len];

        try self.stdout.writeAll(status[0..@min(status.len, width)]);
        try self.resetColor();

        // Position cursor
        const screen_line = @min(cursor_line + 1, height - 2);
        const screen_col = cursor_col + 6; // Account for line numbers
        try self.setCursor(screen_line, screen_col);

        // Flush stdout
    }

    fn handleInput(self: *SimpleTUI) !void {
        var buf: [8]u8 = undefined;
        const n = try self.stdin.read(buf[0..1]); // Read one byte at a time
        if (n == 0) return;

        var key_bytes: [4]u8 = undefined;
        key_bytes[0] = buf[0];
        var key_len: usize = 1;

        // Handle escape sequences (simplified - no timeout)
        if (buf[0] == 27) { // ESC
            // Try to read more bytes for escape sequences
            const next_n = self.stdin.read(buf[1..2]) catch 0;
            if (next_n > 0) {
                key_bytes[1] = buf[1];
                key_len = 2;

                if (buf[1] == '[') {
                    // Arrow keys and other sequences
                    const third_n = self.stdin.read(buf[2..3]) catch 0;
                    if (third_n > 0) {
                        key_bytes[2] = buf[2];
                        key_len = 3;
                    }
                }
            }
        }

        try self.processKeyInput(key_bytes[0..key_len]);
    }

    fn processKeyInput(self: *SimpleTUI, key_bytes: []const u8) !void {
        if (key_bytes.len == 1) {
            const key = key_bytes[0];

            // Global commands (work in any mode)
            switch (key) {
                17 => { // Ctrl+Q
                    self.running = false;
                    return;
                },
                else => {},
            }

            // Mode-specific commands
            switch (self.editor.mode) {
                .normal => try self.handleNormalMode(key),
                .insert => try self.handleInsertMode(key),
                .visual => try self.handleVisualMode(key),
                .command => try self.handleCommandMode(key),
            }
        } else if (key_bytes.len == 3 and key_bytes[0] == 27 and key_bytes[1] == '[') {
            // Arrow keys
            switch (key_bytes[2]) {
                'A' => { // Up arrow
                    if (self.editor.mode == .insert and self.completion_popup_active and self.completion_items.len > 0) {
                        self.moveCompletionSelection(-1);
                    } else {
                        self.editor.moveCursorUp();
                    }
                },
                'B' => { // Down arrow
                    if (self.editor.mode == .insert and self.completion_popup_active and self.completion_items.len > 0) {
                        self.moveCompletionSelection(1);
                    } else {
                        self.editor.moveCursorDown();
                    }
                },
                'C' => { // Right arrow
                    self.editor.moveCursorRight();
                    if (self.editor.mode == .insert and self.completion_popup_active) {
                        self.completion_dirty = true;
                    }
                },
                'D' => { // Left arrow
                    self.editor.moveCursorLeft();
                    if (self.editor.mode == .insert and self.completion_popup_active) {
                        self.completion_dirty = true;
                    }
                },
                else => {},
            }
        }
    }

    fn handleNormalMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => {}, // ESC in normal mode - already in normal
            2 => self.activateBufferPicker(), // Ctrl+B - buffer picker
            23 => { // Ctrl+W - window commands
                self.window_command_pending = true;
                self.setStatusMessage("Window command (s=split h, v=split v, c=close, h/j/k/l=navigate)");
            },
            'h' => self.editor.moveCursorLeft(),
            'j' => self.editor.moveCursorDown(),
            'k' => self.editor.moveCursorUp(),
            'l' => self.editor.moveCursorRight(),
            'i' => self.switchMode(.insert),
            'I' => {
                self.editor.moveCursorToLineStart();
                self.switchMode(.insert);
            },
            'a' => {
                self.editor.moveCursorRight();
                self.switchMode(.insert);
            },
            'A' => {
                self.editor.moveCursorToLineEnd();
                self.switchMode(.insert);
            },
            'o' => {
                try self.editor.insertNewlineAfter();
                self.switchMode(.insert);
            },
            'O' => {
                try self.editor.insertNewlineBefore();
                self.switchMode(.insert);
            },
            'x' => try self.editor.deleteChar(),
            'w' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                } else {
                    self.editor.moveWordForward();
                }
            },
            'b' => self.editor.moveWordBackward(),
            '0' => self.editor.moveCursorToLineStart(),
            '$' => self.editor.moveCursorToLineEnd(),
            'g' => {
                // TODO: Handle 'gg' for goto top
            },
            'G' => self.editor.moveCursorToEnd(),
            'H' => self.requestLspHover(),
            'D' => self.requestLspDefinition(),
            's' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                    // 's' means split - next key determines direction
                    self.setStatusMessage("Split (h=horizontal, v=vertical)");
                }
            },
            'c' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                    self.closeWindow() catch |err| {
                        std.log.warn("Failed to close window: {}", .{err});
                        self.setStatusMessage("Cannot close last window");
                    };
                }
            },
            ':' => self.startCommandMode(),
            'v' => self.switchMode(.visual),
            'q' => self.running = false, // Simple quit
            else => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                }
            },
        }
    }

    fn handleInsertMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.switchMode(.normal), // ESC
            0 => self.triggerCompletionRequest(), // Ctrl+Space
            8, 127 => { // Backspace/Delete
                try self.editor.backspace();
                self.afterTextEdit();
                if (self.completion_popup_active) {
                    self.completion_dirty = true;
                }
            },
            9 => { // Tab
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    self.moveCompletionSelection(1);
                } else {
                    try self.editor.insertChar('\t');
                    self.afterTextEdit();
                }
            },
            13 => { // Enter
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    try self.acceptCompletionSelection();
                } else {
                    try self.editor.insertChar('\n');
                    self.afterTextEdit();
                    self.closeCompletionPopup();
                }
            },
            14 => { // Ctrl+N
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    self.moveCompletionSelection(1);
                }
            },
            16 => { // Ctrl+P
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    self.moveCompletionSelection(-1);
                }
            },
            else => {
                if (key >= 32 and key < 127) { // Printable ASCII
                    try self.editor.insertChar(key);
                    self.afterTextEdit();
                    if (self.completion_popup_active) {
                        self.completion_dirty = true;
                    } else {
                        self.maybeTriggerAutoCompletion(key);
                    }
                }
            },
        }
    }

    fn handleVisualMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.switchMode(.normal), // ESC
            'h' => self.editor.moveCursorLeft(),
            'j' => self.editor.moveCursorDown(),
            'k' => self.editor.moveCursorUp(),
            'l' => self.editor.moveCursorRight(),
            'd' => {
                // TODO: Delete selection
                self.switchMode(.normal);
            },
            'y' => {
                // TODO: Yank selection
                self.switchMode(.normal);
            },
            else => {},
        }
    }

    fn handleCommandMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => {
                self.exitCommandMode();
                self.clearStatusMessage();
            },
            13 => try self.submitCommandLine(),
            8, 127 => {
                if (self.command_buffer.items.len > 0) {
                    _ = self.command_buffer.pop();
                }
            },
            else => {
                if (key >= 32 and key < 127) {
                    try self.command_buffer.append(self.allocator, key);
                }
            },
        }
    }

    fn modeToPluginMode(mode: Editor.Mode) runtime.PluginAPI.EditorContext.EditorMode {
        return switch (mode) {
            .normal => .normal,
            .insert => .insert,
            .visual => .visual,
            .command => .command,
        };
    }

    fn switchMode(self: *SimpleTUI, new_mode: Editor.Mode) void {
        const current = self.editor.mode;
        if (current == new_mode) return;
        self.editor.mode = new_mode;

        if (new_mode != .insert) {
            self.closeCompletionPopup();
        }

        if (self.plugin_manager) |manager| {
            const event_data = runtime.PluginAPI.EventData{
                .mode_changed = .{
                    .old_mode = modeToPluginMode(current),
                    .new_mode = modeToPluginMode(new_mode),
                },
            };
            manager.emitEvent(.mode_changed, event_data) catch |err| {
                std.log.err("Failed to emit mode_changed event: {}", .{err});
            };
        }
    }

    fn startCommandMode(self: *SimpleTUI) void {
        self.command_buffer.clearRetainingCapacity();
        self.switchMode(.command);
    }

    fn exitCommandMode(self: *SimpleTUI) void {
        self.command_buffer.clearRetainingCapacity();
        self.switchMode(.normal);
    }

    fn submitCommandLine(self: *SimpleTUI) !void {
        const trimmed = std.mem.trim(u8, self.command_buffer.items, " \t");
        if (trimmed.len == 0) {
            self.exitCommandMode();
            return;
        }

        var tokenizer = std.mem.tokenizeAny(u8, trimmed, " \t");
        const head = tokenizer.next() orelse {
            self.exitCommandMode();
            return;
        };

        if (std.mem.eql(u8, head, "q") or std.mem.eql(u8, head, "quit")) {
            self.running = false;
            self.setStatusMessage("Quit");
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "wq")) {
            self.saveCurrentFile() catch |err| {
                switch (err) {
                    error.NoActiveFile => self.setStatusMessage("No file to write"),
                    else => {
                        self.setStatusMessage("Write failed");
                        std.log.err("Failed to write file: {}", .{err});
                    },
                }
                self.exitCommandMode();
                return;
            };
            self.setStatusMessage("Wrote file");
            self.running = false;
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "w") or std.mem.eql(u8, head, "write")) {
            self.saveCurrentFile() catch |err| {
                switch (err) {
                    error.NoActiveFile => self.setStatusMessage("No file to write"),
                    else => {
                        self.setStatusMessage("Write failed");
                        std.log.err("Failed to write file: {}", .{err});
                    },
                }
                self.exitCommandMode();
                return;
            };
            self.setStatusMessage("Wrote file");
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "commands")) {
            self.showAvailableCommands() catch |err| {
                if (err != error.PluginUnavailable) {
                    std.log.err("Failed to show command list: {}", .{err});
                    self.setStatusMessage("Unable to list commands");
                }
            };
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "plugins")) {
            self.showLoadedPlugins() catch |err| {
                if (err != error.PluginUnavailable) {
                    std.log.err("Failed to show plugins: {}", .{err});
                    self.setStatusMessage("Unable to list plugins");
                }
            };
            self.exitCommandMode();
            return;
        }

        var args_builder = std.ArrayList([]const u8).initCapacity(self.allocator, 0) catch |err| {
            std.log.err("Failed to allocate command arguments: {}", .{err});
            self.setStatusMessage("Unable to process command arguments");
            self.exitCommandMode();
            return;
        };
        defer args_builder.deinit(self.allocator);
        while (tokenizer.next()) |token| {
            try args_builder.append(self.allocator, token);
        }

        const args = args_builder.items;
        self.executePluginCommand(head, args) catch |err| {
            switch (err) {
                error.PluginUnavailable => {},
                else => {
                    var msg_buf: [160]u8 = undefined;
                    const msg = std.fmt.bufPrint(&msg_buf, "Command '{s}' failed", .{head}) catch "Command failed";
                    self.setStatusMessage(msg);
                    std.log.err("Plugin command '{s}' failed: {}", .{ head, err });
                },
            }
            self.exitCommandMode();
            return;
        };

        self.exitCommandMode();
    }

    fn saveCurrentFile(self: *SimpleTUI) !void {
        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No file to write");
            return error.NoActiveFile;
        };
        try self.editor.saveFile(path);

        if (self.plugin_manager) |manager| {
            manager.emitEvent(.file_saved, .{ .file_saved = path }) catch |err| {
                std.log.err("Failed to emit file_saved event: {}", .{err});
            };
        }

        self.emitBufferSaved(self.current_buffer_id, path);

        if (self.editor_lsp) |lsp| {
            lsp.notifyFileSaved(path) catch |err| {
                std.log.warn("Failed to notify LSP about save: {}", .{err});
            };
        }
    }

    fn executePluginCommand(self: *SimpleTUI, name: []const u8, args: []const []const u8) !void {
        const manager = self.plugin_manager orelse {
            self.setStatusMessage("No plugin manager attached");
            return error.PluginUnavailable;
        };
        try manager.executeCommand(name, args);
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Executed {s}", .{name}) catch "Command executed";
        self.setStatusMessage(msg);
    }

    fn showAvailableCommands(self: *SimpleTUI) !void {
        const manager = self.plugin_manager orelse {
            self.setStatusMessage("No plugin manager attached");
            return error.PluginUnavailable;
        };

        const commands = manager.listCommands(self.allocator) catch |err| {
            std.log.err("Failed to list plugin commands: {}", .{err});
            self.setStatusMessage("Unable to list commands");
            return;
        };
        defer self.allocator.free(commands);

        if (commands.len == 0) {
            self.setStatusMessage("No plugin commands registered");
            return;
        }

        var builder = std.ArrayList(u8).initCapacity(self.allocator, 0) catch |err| {
            std.log.err("Failed to allocate command list buffer: {}", .{err});
            self.setStatusMessage("Unable to list commands");
            return;
        };
        defer builder.deinit(self.allocator);
        try builder.appendSlice(self.allocator, "Commands: ");

        const max_display: usize = 5;
        for (commands, 0..) |command, idx| {
            if (idx >= max_display) {
                try builder.appendSlice(self.allocator, "...");
                break;
            }

            if (idx > 0) {
                try builder.appendSlice(self.allocator, ", ");
            }

            try builder.appendSlice(self.allocator, command.name);
            try builder.appendSlice(self.allocator, " (");
            try builder.appendSlice(self.allocator, command.plugin_id);
            try builder.appendSlice(self.allocator, ")");
        }

        self.setStatusMessage(builder.items);
    }

    fn showLoadedPlugins(self: *SimpleTUI) !void {
        const manager = self.plugin_manager orelse {
            self.setStatusMessage("No plugin manager attached");
            return error.PluginUnavailable;
        };

        const plugins = manager.listLoadedPlugins(self.allocator) catch |err| {
            std.log.err("Failed to list plugins: {}", .{err});
            self.setStatusMessage("Unable to list plugins");
            return;
        };
        defer self.allocator.free(plugins);

        if (plugins.len == 0) {
            self.setStatusMessage("No plugins loaded");
            return;
        }

        var builder = std.ArrayList(u8).initCapacity(self.allocator, 0) catch |err| {
            std.log.err("Failed to allocate plugin list buffer: {}", .{err});
            self.setStatusMessage("Unable to list plugins");
            return;
        };
        defer builder.deinit(self.allocator);
        try builder.appendSlice(self.allocator, "Plugins: ");
        for (plugins, 0..) |plugin_id, idx| {
            if (idx > 0) try builder.appendSlice(self.allocator, ", ");
            try builder.appendSlice(self.allocator, plugin_id);
        }

        self.setStatusMessage(builder.items);
    }

    fn enableRawMode(self: *SimpleTUI) !void {
        _ = self;
        // Platform-specific raw mode setup would go here
        // For now, just a placeholder
    }

    fn bridgeGetCurrentBuffer(ctx: *anyopaque) runtime.PluginAPI.BufferId {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        return self.current_buffer_id;
    }

    fn bridgeGetCursorPosition(ctx: *anyopaque) runtime.PluginAPI.EditorContext.CursorPosition {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        const offset = self.editor.cursor.offset;
        const lc = self.editor.rope.lineColumnAtOffset(offset) catch {
            const fallback = runtime.PluginAPI.EditorContext.CursorPosition{ .line = 0, .column = 0, .byte_offset = offset };
            if (self.plugin_cursor) |cursor_ptr| {
                cursor_ptr.* = fallback;
            }
            return fallback;
        };
        const position = runtime.PluginAPI.EditorContext.CursorPosition{ .line = lc.line, .column = lc.column, .byte_offset = offset };
        if (self.plugin_cursor) |cursor_ptr| {
            cursor_ptr.* = position;
        }
        return position;
    }

    fn bridgeSetCursorPosition(ctx: *anyopaque, position: runtime.PluginAPI.EditorContext.CursorPosition) anyerror!void {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        const rope_len = self.editor.rope.len();
        const new_offset = if (position.byte_offset > rope_len) rope_len else position.byte_offset;
        self.editor.cursor.offset = new_offset;
        if (self.plugin_cursor) |cursor_ptr| {
            cursor_ptr.* = .{
                .line = position.line,
                .column = position.column,
                .byte_offset = new_offset,
            };
        }
    }

    fn bridgeGetSelection(ctx: *anyopaque) ?runtime.PluginAPI.EditorContext.SelectionRange {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        const start_opt = self.editor.selection_start;
        const end_opt = self.editor.selection_end;
        if (start_opt == null or end_opt == null) return null;

        const start_val = start_opt.?;
        const end_val = end_opt.?;
        const normalized_start = @min(start_val, end_val);
        const normalized_end = @max(start_val, end_val);
        return .{ .start = normalized_start, .end = normalized_end };
    }

    fn bridgeSetSelection(ctx: *anyopaque, selection: ?runtime.PluginAPI.EditorContext.SelectionRange) anyerror!void {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        if (selection) |sel| {
            const rope_len = self.editor.rope.len();
            const clamped_start = @min(sel.start, rope_len);
            const clamped_end = @min(sel.end, rope_len);
            const normalized_start = @min(clamped_start, clamped_end);
            const normalized_end = @max(clamped_start, clamped_end);
            self.editor.selection_start = normalized_start;
            self.editor.selection_end = normalized_end;
        } else {
            self.editor.selection_start = null;
            self.editor.selection_end = null;
        }
    }

    fn bridgeNotifyChange(ctx: *anyopaque, change: runtime.PluginAPI.EditorContext.BufferChange) anyerror!void {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        _ = change;
        self.markHighlightsDirty();
        if (self.plugin_cursor) |cursor_ptr| {
            self.editor.cursor.offset = cursor_ptr.byte_offset;
            self.updatePluginCursorFromEditor();
        }
        if (self.editor_lsp) |lsp| {
            if (self.editor.current_filename) |path| {
                lsp.notifyBufferChange(path) catch |err| {
                    std.log.warn("Failed to send LSP change notification: {}", .{err});
                };
            }
        }
    }

    pub fn makeEditorBridge(self: *SimpleTUI) runtime.PluginAPI.EditorContext.EditorBridge {
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

    fn requestLspHover(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No active file");
            return;
        };

        const line_idx = self.getCursorLine();
        const char_idx = self.getCursorColumn();
        const line = std.math.cast(u32, line_idx) orelse std.math.maxInt(u32);
        const character = std.math.cast(u32, char_idx) orelse std.math.maxInt(u32);

        lsp.requestHover(path, line, character) catch |err| {
            std.log.warn("Failed to request hover: {}", .{err});
            self.setStatusMessage("Hover request failed");
            return;
        };

        self.setStatusMessage("Hover requested");
    }

    fn requestLspDefinition(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No active file");
            return;
        };

        const line_idx = self.getCursorLine();
        const char_idx = self.getCursorColumn();
        const line = std.math.cast(u32, line_idx) orelse std.math.maxInt(u32);
        const character = std.math.cast(u32, char_idx) orelse std.math.maxInt(u32);

        lsp.requestDefinition(path, line, character) catch |err| {
            std.log.warn("Failed to request definition: {}", .{err});
            self.setStatusMessage("Definition request failed");
            return;
        };

        self.setStatusMessage("Definition requested");
    }

    fn applyPendingDefinition(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse return;

        while (lsp.takeDefinitionResult()) |result| {
            const def = result;
            defer lsp.freeDefinitionResult(def);

            const path_slice: []const u8 = def.path;
            const same_file = blk: {
                if (self.editor.current_filename) |current| {
                    break :blk std.mem.eql(u8, current, path_slice);
                }
                break :blk false;
            };

            if (!same_file) {
                const load_result = self.loadFile(path_slice);
                if (load_result) |_| {
                    self.markHighlightsDirty();
                } else |err| {
                    std.log.warn("Failed to open definition target '{s}': {}", .{ path_slice, err });
                    self.setStatusMessage("Definition open failed");
                    continue;
                }
            }

            const offset = lsp.offsetFromPosition(def.line, def.character);
            self.editor.cursor.offset = if (offset <= self.editor.rope.len()) offset else self.editor.rope.len();
            self.editor.selection_start = null;
            self.editor.selection_end = null;
            self.updatePluginCursorFromEditor();

            self.setStatusMessage("Jumped to definition");
        }
    }

    fn updatePluginCursorFromEditor(self: *SimpleTUI) void {
        if (self.plugin_cursor) |cursor_ptr| {
            const offset = self.editor.cursor.offset;
            cursor_ptr.byte_offset = offset;
            const lc = self.editor.rope.lineColumnAtOffset(offset) catch {
                cursor_ptr.line = 0;
                cursor_ptr.column = 0;
                return;
            };
            cursor_ptr.line = lc.line;
            cursor_ptr.column = lc.column;
        }
    }

    fn disableRawMode(self: *SimpleTUI) !void {
        _ = self;
        // Platform-specific raw mode cleanup would go here
    }

    fn clearScreen(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[2J");
    }

    fn setCursor(self: *SimpleTUI, row: usize, col: usize) !void {
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1B[{d};{d}H", .{ row, col });
        try self.stdout.writeAll(seq);
    }

    fn clearLineAt(self: *SimpleTUI, row: usize, width: usize) !void {
        try self.setCursor(row, 1);
        var blank: [128]u8 = undefined;
        const chunk = @min(blank.len, width);
        @memset(blank[0..chunk], ' ');
        var remaining = width;
        while (remaining > 0) {
            const emit = @min(chunk, remaining);
            try self.stdout.writeAll(blank[0..emit]);
            remaining -= emit;
        }
        try self.setCursor(row, 1);
    }

    fn renderCompletionBar(self: *SimpleTUI, width: usize, height: usize) !void {
        const status_row = if (height > 0) height else 1;
        const popup_height: usize = 6; // 4 entries + header/footer
        const popup_row = if (status_row > popup_height) status_row - popup_height else 1;

        var row = popup_row;
        var lines_to_clear: usize = popup_height;
        while (lines_to_clear > 0) : (lines_to_clear -= 1) {
            try self.clearLineAt(row, width);
            row += 1;
        }

        if (!self.completion_popup_active) return;

        const lsp = self.editor_lsp orelse {
            self.closeCompletionPopup();
            return;
        };

        var needs_refresh = self.completion_dirty;
        const generation = lsp.getCompletionGeneration();
        if (generation != self.completion_generation_seen) {
            self.completion_generation_seen = generation;
            needs_refresh = true;
        }

        if (needs_refresh) {
            self.refreshCompletionPrefix() catch {
                self.closeCompletionPopup();
                return;
            };

            if (self.completion_popup_active) {
                self.refreshCompletionDisplay(lsp);
            }
        }

        const list_window = popup_height - 2;
        if (self.completion_items.len == 0) {
            try self.displayCenteredMessage(popup_row, width, "Waiting for completions…");
            return;
        }

        const visible = self.computeVisibleCompletions(list_window);
        try self.renderCompletionList(popup_row, width, visible.start, visible.count);
    }

    const VisibleWindow = struct { start: usize, count: usize };

    fn computeVisibleCompletions(self: *SimpleTUI, capacity: usize) VisibleWindow {
        if (capacity == 0 or self.completion_items.len == 0) return .{ .start = 0, .count = 0 };

        const total = self.completion_items.len;
        const selected = self.completion_selected_index;

        const half = capacity / 2;
        var start = if (selected > half) selected - half else 0;
        if (start + capacity > total) {
            if (total > capacity) {
                start = total - capacity;
            } else {
                start = 0;
            }
        }

        const remaining = total - start;
        const count = if (remaining < capacity) remaining else capacity;
        return .{ .start = start, .count = count };
    }

    fn displayCenteredMessage(self: *SimpleTUI, row_start: usize, width: usize, message: []const u8) !void {
        const centered_col = if (message.len >= width) 1 else (width - message.len) / 2 + 1;
        try self.setCursor(row_start + 1, centered_col);
        try self.stdout.writeAll(message[0..@min(message.len, width)]);
    }

    fn renderCompletionList(self: *SimpleTUI, row_start: usize, width: usize, start: usize, count: usize) !void {
        const total = self.completion_items.len;
        const selected = self.completion_selected_index;
        const header_row = row_start;
        const list_row = row_start + 1;
        const detail_row = row_start + 4;
        const footer_row = row_start + 5;

        // Header
        try self.setCursor(header_row, 1);
        var header_buf: [128]u8 = undefined;
        const header_slice = try std.fmt.bufPrint(&header_buf, "Completions {d}/{d} (prefix: {s})", .{ selected + 1, total, self.completion_prefix.items });
        try self.stdout.writeAll(header_slice[0..@min(header_slice.len, width)]);

        // Entries
        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            const absolute = start + idx;
            const comp = self.completion_items[absolute];
            const is_selected = absolute == selected;

            var line_buf: [256]u8 = undefined;
            var written: usize = 0;
            const first = try std.fmt.bufPrint(line_buf[written..], "{s}{s}", .{ if (is_selected) "→ " else "  ", comp.label });
            written += first.len;
            if (comp.detail) |detail| {
                const detail_slice = try std.fmt.bufPrint(line_buf[written..], " — {s}", .{detail});
                written += detail_slice.len;
            }

            const slice = line_buf[0..written];
            try self.setCursor(list_row + idx, 1);
            try self.stdout.writeAll(slice[0..@min(slice.len, width)]);
        }

        // Inline documentation or detail preview
        try self.renderCompletionDetails(detail_row, width);

        // Footer
        try self.setCursor(footer_row, 1);
        const footer = "Tab/Ctrl+N next • Ctrl+P prev • Enter apply • Esc cancel";
        try self.stdout.writeAll(footer[0..@min(footer.len, width)]);
    }

    fn renderCompletionDetails(self: *SimpleTUI, row: usize, width: usize) !void {
        if (self.completion_items.len == 0) return;

        const comp = self.completion_items[self.completion_selected_index];
        try self.setCursor(row, 1);

        if (comp.documentation) |doc| {
            try self.writeWrapped(doc, width, row, 2);
        } else if (comp.detail) |detail| {
            try self.stdout.writeAll(detail[0..@min(detail.len, width)]);
        } else {
            const placeholder = "(no documentation available)";
            try self.stdout.writeAll(placeholder[0..@min(placeholder.len, width)]);
        }
    }

    fn writeWrapped(self: *SimpleTUI, text: []const u8, width: usize, row_start: usize, max_lines: usize) !void {
        var remaining = text;
        var row = row_start;
        var lines_written: usize = 0;
        while (remaining.len > 0 and lines_written < max_lines) {
            const take = @min(remaining.len, width);
            try self.setCursor(row, 1);
            try self.stdout.writeAll(remaining[0..take]);
            remaining = remaining[take..];
            row += 1;
            lines_written += 1;
        }
    }

    fn showCursor(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[?25h");
    }

    fn hideCursor(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[?25l");
    }

    fn setColor(self: *SimpleTUI, bg: u8, fg: u8) !void {
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1B[{d};{d}m", .{ bg, fg });
        try self.stdout.writeAll(seq);
    }

    fn resetColor(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[0m");
    }

    fn getCursorLine(self: *SimpleTUI) usize {
        const content = self.editor.rope.slice(.{
            .start = 0,
            .end = self.editor.cursor.offset,
        }) catch return 0;

        var lines: usize = 0;
        for (content) |ch| {
            if (ch == '\n') lines += 1;
        }
        return lines;
    }

    fn getCursorColumn(self: *SimpleTUI) usize {
        const content = self.editor.rope.slice(.{
            .start = 0,
            .end = self.editor.cursor.offset,
        }) catch return 0;

        var col: usize = 0;
        for (content) |ch| {
            if (ch == '\n') {
                col = 0;
            } else {
                col += 1;
            }
        }
        return col;
    }

    fn markHighlightsDirty(self: *SimpleTUI) void {
        self.highlight_dirty = true;
        if (self.highlight_error) |msg| {
            self.allocator.free(msg);
            self.highlight_error = null;
        }
        self.highlight_error_flash = false;
        self.highlight_error_flash_state = false;
        self.highlight_error_logged = false;
    }

    fn afterTextEdit(self: *SimpleTUI) void {
        self.markHighlightsDirty();
        self.updatePluginCursorFromEditor();
        if (self.editor_lsp) |lsp| {
            if (self.editor.current_filename) |path| {
                lsp.notifyBufferChange(path) catch |err| {
                    std.log.warn("Failed to send LSP change notification: {}", .{err});
                };
            }
        }
    }

    fn clearCompletionDisplay(self: *SimpleTUI) void {
        if (self.completion_items_heap) {
            self.allocator.free(self.completion_items);
        }
        self.completion_items = &.{};
        self.completion_items_heap = false;
        self.completion_selected_index = 0;
    }

    fn closeCompletionPopup(self: *SimpleTUI) void {
        if (!self.completion_popup_active) return;
        self.completion_popup_active = false;
        self.completion_anchor_offset = null;
        self.completion_generation_seen = 0;
        self.completion_dirty = false;
        self.clearCompletionDisplay();
        self.completion_prefix.clearRetainingCapacity();
    }

    fn isWordChar(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '_';
    }

    fn captureCompletionContext(self: *SimpleTUI) !void {
        const cursor_offset = self.editor.cursor.offset;
        const head = try self.editor.rope.slice(.{ .start = 0, .end = cursor_offset });
        defer self.allocator.free(head);

        var anchor = cursor_offset;
        while (anchor > 0) {
            const ch = head[anchor - 1];
            if (!isWordChar(ch)) break;
            anchor -= 1;
        }

        self.completion_anchor_offset = anchor;
        self.completion_prefix.clearRetainingCapacity();
        const prefix_slice = head[anchor..];
        if (prefix_slice.len > 0) {
            try self.completion_prefix.appendSlice(self.allocator, prefix_slice);
        }
    }

    fn refreshCompletionPrefix(self: *SimpleTUI) !void {
        const anchor = self.completion_anchor_offset orelse {
            self.closeCompletionPopup();
            return;
        };

        const cursor_offset = self.editor.cursor.offset;
        if (cursor_offset < anchor) {
            self.closeCompletionPopup();
            return;
        }

        const slice = try self.editor.rope.slice(.{ .start = anchor, .end = cursor_offset });
        defer self.allocator.free(slice);

        self.completion_prefix.clearRetainingCapacity();
        if (slice.len > 0) {
            try self.completion_prefix.appendSlice(self.allocator, slice);
        }
    }

    fn refreshCompletionDisplay(self: *SimpleTUI, lsp: *editor_lsp_mod.EditorLSP) void {
        self.clearCompletionDisplay();

        const filtered = lsp.filterCompletions(self.allocator, self.completion_prefix.items) catch |err| {
            std.log.warn("Failed to filter completions: {}", .{err});
            self.setStatusMessage("Completion update failed");
            return;
        };

        self.completion_items = filtered;
        self.completion_items_heap = true;
        if (self.completion_items.len == 0) {
            self.completion_selected_index = 0;
        } else if (self.completion_selected_index >= self.completion_items.len) {
            self.completion_selected_index = self.completion_items.len - 1;
        }
        self.completion_dirty = false;
    }

    fn triggerCompletionRequest(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No active file");
            return;
        };

        self.clearCompletionDisplay();

        self.captureCompletionContext() catch |err| {
            std.log.warn("Failed to capture completion context: {}", .{err});
            self.setStatusMessage("Completion unavailable");
            return;
        };

        const line_idx = self.getCursorLine();
        const col_idx = self.getCursorColumn();
        const line = std.math.cast(u32, line_idx) orelse std.math.maxInt(u32);
        const character = std.math.cast(u32, col_idx) orelse std.math.maxInt(u32);

        lsp.requestCompletion(path, line, character) catch |err| {
            std.log.warn("Failed to request completion: {}", .{err});
            self.setStatusMessage("Completion request failed");
            self.closeCompletionPopup();
            return;
        };

        self.completion_popup_active = true;
        self.completion_selected_index = 0;
        self.completion_dirty = true;
        self.completion_generation_seen = lsp.getCompletionGeneration();
    }

    fn maybeTriggerAutoCompletion(self: *SimpleTUI, typed_char: u8) void {
        const lsp = self.editor_lsp orelse return;
        if (!lsp.shouldTriggerCompletion(typed_char)) return;
        self.triggerCompletionRequest();
    }

    fn moveCompletionSelection(self: *SimpleTUI, direction: i32) void {
        if (!self.completion_popup_active) return;
        if (self.completion_items.len == 0) return;

        const len = self.completion_items.len;
        if (direction > 0) {
            self.completion_selected_index = (self.completion_selected_index + 1) % len;
        } else if (direction < 0) {
            if (self.completion_selected_index == 0) {
                self.completion_selected_index = len - 1;
            } else {
                self.completion_selected_index -= 1;
            }
        }
    }

    fn acceptCompletionSelection(self: *SimpleTUI) !void {
        if (!self.completion_popup_active) return;
        if (self.completion_items.len == 0) {
            self.closeCompletionPopup();
            return;
        }

        const anchor = self.completion_anchor_offset orelse {
            self.closeCompletionPopup();
            return;
        };

        const comp = self.completion_items[self.completion_selected_index];
        try self.applyCompletion(comp, anchor);
        self.setStatusMessage("Inserted completion");
        self.closeCompletionPopup();
    }

    const SelectionRange = struct { start: usize, end: usize };

    fn applyCompletion(self: *SimpleTUI, comp: editor_lsp_mod.Completion, anchor: usize) !void {
        var selection: ?SelectionRange = null;

        if (comp.text_edit) |edit| {
            selection = try self.applyTextEditCompletion(edit, comp.insert_text_format);
        } else {
            const cursor_offset = self.editor.cursor.offset;
            if (cursor_offset < anchor) return;

            const prefix_len = cursor_offset - anchor;
            if (prefix_len > 0) {
                try self.editor.rope.delete(anchor, prefix_len);
            }

            const insert_text = comp.insert_text orelse comp.label;
            if (comp.insert_text_format == .snippet) {
                selection = try self.insertSnippetText(anchor, insert_text);
            } else {
                try self.editor.rope.insert(anchor, insert_text);
                self.editor.cursor.offset = anchor + insert_text.len;
            }
        }

        if (selection) |sel| {
            if (sel.start != sel.end) {
                self.editor.selection_start = sel.start;
                self.editor.selection_end = sel.end;
            } else {
                self.editor.selection_start = null;
                self.editor.selection_end = null;
            }
        } else {
            self.editor.selection_start = null;
            self.editor.selection_end = null;
        }

        self.updatePluginCursorFromEditor();
        self.afterTextEdit();
    }

    fn applyTextEditCompletion(
        self: *SimpleTUI,
        edit: editor_lsp_mod.Completion.TextEdit,
        format: editor_lsp_mod.Completion.InsertTextFormat,
    ) !?SelectionRange {
        if (self.editor_lsp == null) return null;

        const lsp = self.editor_lsp.?;
        const start_offset = lsp.offsetFromPosition(edit.range.start.line, edit.range.start.character);
        const end_offset = lsp.offsetFromPosition(edit.range.end.line, edit.range.end.character);

        if (end_offset > start_offset) {
            try self.editor.rope.delete(start_offset, end_offset - start_offset);
        }

        switch (format) {
            .snippet => {
                const expansion = self.expandSnippet(edit.new_text) catch |err| {
                    std.log.warn("Failed to expand snippet text edit: {}", .{err});
                    try self.editor.rope.insert(start_offset, edit.new_text);
                    self.editor.cursor.offset = start_offset + edit.new_text.len;
                    return null;
                };
                defer self.allocator.free(expansion.text);

                try self.editor.rope.insert(start_offset, expansion.text);
                self.editor.cursor.offset = start_offset + expansion.caret;

                if (expansion.selection) |sel| {
                    return .{ .start = start_offset + sel.start, .end = start_offset + sel.end };
                }
                return null;
            },
            .plain_text => {
                try self.editor.rope.insert(start_offset, edit.new_text);
                self.editor.cursor.offset = start_offset + edit.new_text.len;
                return null;
            },
        }
    }

    fn insertSnippetText(self: *SimpleTUI, anchor: usize, snippet: []const u8) !?SelectionRange {
        const expansion = self.expandSnippet(snippet) catch |err| {
            std.log.warn("Failed to expand snippet: {}", .{err});
            try self.editor.rope.insert(anchor, snippet);
            self.editor.cursor.offset = anchor + snippet.len;
            return null;
        };
        defer self.allocator.free(expansion.text);

        try self.editor.rope.insert(anchor, expansion.text);
        self.editor.cursor.offset = anchor + expansion.caret;

        if (expansion.selection) |sel| {
            return .{ .start = anchor + sel.start, .end = anchor + sel.end };
        }
        return null;
    }

    const SnippetExpansion = struct {
        text: []u8,
        caret: usize,
        selection: ?SelectionRange,
    };

    fn expandSnippet(self: *SimpleTUI, snippet: []const u8) !SnippetExpansion {
        var buffer = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        errdefer buffer.deinit(self.allocator);

        const PlaceholderInfo = struct {
            id: u32,
            offset: usize,
            length: usize,
        };

        var best_placeholder: ?PlaceholderInfo = null;
        var final_stop: ?PlaceholderInfo = null;

        var idx: usize = 0;
        while (idx < snippet.len) {
            const ch = snippet[idx];
            if (ch == '\\' and idx + 1 < snippet.len) {
                try buffer.append(self.allocator, snippet[idx + 1]);
                idx += 2;
                continue;
            }

            if (ch == '$') {
                if (idx + 1 < snippet.len and std.ascii.isDigit(snippet[idx + 1])) {
                    var j = idx + 1;
                    while (j < snippet.len and std.ascii.isDigit(snippet[j])) j += 1;
                    const id_slice = snippet[idx + 1 .. j];
                    const id = std.fmt.parseUnsigned(u32, id_slice, 10) catch {
                        try buffer.append(self.allocator, '$');
                        idx += 1;
                        continue;
                    };

                    const info = PlaceholderInfo{ .id = id, .offset = buffer.items.len, .length = 0 };
                    if (id == 0) {
                        if (final_stop == null) final_stop = info;
                    } else if (best_placeholder == null or id < best_placeholder.?.id) {
                        best_placeholder = info;
                    }
                    idx = j;
                    continue;
                } else if (idx + 1 < snippet.len and snippet[idx + 1] == '{') {
                    var j = idx + 2;
                    var depth: usize = 1;
                    while (j < snippet.len) {
                        const c = snippet[j];
                        if (c == '\\' and j + 1 < snippet.len) {
                            j += 2;
                            continue;
                        } else if (c == '{') {
                            depth += 1;
                            j += 1;
                            continue;
                        } else if (c == '}') {
                            depth -= 1;
                            if (depth == 0) break;
                            j += 1;
                            continue;
                        } else {
                            j += 1;
                        }
                    }

                    if (depth != 0 or j >= snippet.len) {
                        try buffer.append(self.allocator, '$');
                        idx += 1;
                        continue;
                    }

                    const body = snippet[idx + 2 .. j];
                    if (parseSnippetPlaceholder(body)) |placeholder| {
                        const placeholder_offset = buffer.items.len;
                        var inserted_len: usize = 0;
                        if (placeholder.default_text) |default_slice| {
                            const normalized = normalizePlaceholderDefault(default_slice);
                            inserted_len = buffer.items.len;
                            try appendSnippetPlain(&buffer, self.allocator, normalized);
                            inserted_len = buffer.items.len - placeholder_offset;
                        }

                        const info = PlaceholderInfo{
                            .id = placeholder.id,
                            .offset = placeholder_offset,
                            .length = inserted_len,
                        };

                        if (placeholder.id == 0) {
                            if (final_stop == null) final_stop = info;
                        } else if (best_placeholder == null or placeholder.id < best_placeholder.?.id) {
                            best_placeholder = info;
                        }

                        idx = j + 1;
                        continue;
                    }

                    try buffer.append(self.allocator, '$');
                    idx += 1;
                    continue;
                }
            }

            try buffer.append(self.allocator, ch);
            idx += 1;
        }

        const final_len = buffer.items.len;
        const fallback = PlaceholderInfo{ .id = 0, .offset = final_len, .length = 0 };
        const chosen = if (best_placeholder) |sel|
            sel
        else if (final_stop) |sel|
            sel
        else
            fallback;

        const text = try buffer.toOwnedSlice(self.allocator);
        const caret = chosen.offset + chosen.length;
        const selection = if (chosen.length > 0)
            SelectionRange{ .start = chosen.offset, .end = chosen.offset + chosen.length }
        else
            null;

        return SnippetExpansion{
            .text = text,
            .caret = caret,
            .selection = selection,
        };
    }

    const SnippetPlaceholder = struct {
        id: u32,
        default_text: ?[]const u8,
    };

    fn parseSnippetPlaceholder(body: []const u8) ?SnippetPlaceholder {
        if (body.len == 0) return null;
        var i: usize = 0;
        while (i < body.len and std.ascii.isDigit(body[i])) : (i += 1) {}
        if (i == 0) return null;

        const id_slice = body[0..i];
        const id = std.fmt.parseUnsigned(u32, id_slice, 10) catch return null;

        if (i >= body.len) {
            return SnippetPlaceholder{ .id = id, .default_text = null };
        }

        return SnippetPlaceholder{ .id = id, .default_text = body[i..] };
    }

    fn normalizePlaceholderDefault(default_slice: []const u8) []const u8 {
        if (default_slice.len == 0) return default_slice;

        if (default_slice[0] == ':') {
            return default_slice[1..];
        }

        if (default_slice[0] == '|' and default_slice.len > 1) {
            const rest = default_slice[1..];
            if (std.mem.indexOfScalar(u8, rest, '|')) |end_idx| {
                const choices = rest[0..end_idx];
                if (std.mem.indexOfScalar(u8, choices, ',')) |comma| {
                    return choices[0..comma];
                }
                return choices;
            }
            return rest;
        }

        return default_slice;
    }

    fn appendSnippetPlain(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
        var idx: usize = 0;
        while (idx < text.len) {
            const ch = text[idx];
            if (ch == '\\' and idx + 1 < text.len) {
                try buffer.append(allocator, text[idx + 1]);
                idx += 2;
            } else {
                try buffer.append(allocator, ch);
                idx += 1;
            }
        }
    }

    fn refreshHighlights(self: *SimpleTUI) void {
        if (!self.highlight_dirty) return;

        // Free old cache
        if (self.highlight_cache.len > 0) {
            self.allocator.free(self.highlight_cache);
            self.highlight_cache = &.{};
        }

        // Try to get new highlights
        const new_highlights = self.editor.getSyntaxHighlights() catch |err| {
            // Store error message
            const err_msg = std.fmt.allocPrint(
                self.allocator,
                "Highlight error: {s}",
                .{@errorName(err)},
            ) catch return;

            if (self.highlight_error) |old_msg| {
                self.allocator.free(old_msg);
            }
            self.highlight_error = err_msg;
            self.highlight_error_flash = true;
            self.highlight_error_flash_state = false;
            if (!self.highlight_error_logged) {
                std.log.err("Highlight refresh failed: {s}", .{err_msg});
                self.highlight_error_logged = true;
            }
            return;
        };

        if (self.highlight_error) |old_msg| {
            self.allocator.free(old_msg);
            self.highlight_error = null;
        }
        self.highlight_error_flash = false;
        self.highlight_error_flash_state = false;
        self.highlight_error_logged = false;

        self.highlight_cache = new_highlights;
        self.highlight_dirty = false;
    }

    const LineDiagnostic = struct {
        severity: editor_lsp_mod.Diagnostic.Severity,
        message: []const u8,
    };

    fn selectLineDiagnostic(diags: []const editor_lsp_mod.Diagnostic, line_usize: usize) ?LineDiagnostic {
        if (line_usize > std.math.maxInt(u32)) return null;
        const line_val: u32 = @intCast(line_usize);
        var best: ?LineDiagnostic = null;
        var best_score: u8 = 0;

        for (diags) |diag| {
            if (line_val < diag.range.start.line or line_val > diag.range.end.line) continue;
            const score = severityScore(diag.severity);
            if (score > best_score) {
                best_score = score;
                best = .{ .severity = diag.severity, .message = diag.message };
            }
        }

        return best;
    }

    fn severityScore(severity: editor_lsp_mod.Diagnostic.Severity) u8 {
        return switch (severity) {
            .error_sev => 4,
            .warning => 3,
            .information => 2,
            .hint => 1,
        };
    }

    fn severityMarker(severity: editor_lsp_mod.Diagnostic.Severity) u8 {
        return switch (severity) {
            .error_sev => 'E',
            .warning => 'W',
            .information => 'I',
            .hint => 'H',
        };
    }

    fn severityLabel(severity: editor_lsp_mod.Diagnostic.Severity) []const u8 {
        return switch (severity) {
            .error_sev => "ERR",
            .warning => "WARN",
            .information => "INFO",
            .hint => "HINT",
        };
    }

    fn renderPlainLine(self: *SimpleTUI, line: []const u8, max_width: usize) !void {
        const display_len = @min(line.len, max_width);
        if (display_len > 0) {
            try self.stdout.writeAll(line[0..display_len]);
        }

        var remaining = max_width - display_len;
        while (remaining > 0) : (remaining -= 1) {
            try self.stdout.writeAll(" ");
        }
    }

    fn renderHighlightedLine(self: *SimpleTUI, line: []const u8, line_num: usize, max_width: usize) !void {
        if (max_width == 0) return;

        const line_len = line.len;
        if (self.highlight_cache.len == 0) {
            try self.renderPlainLine(line, max_width);
            return;
        }

        const Segment = struct {
            start: usize,
            end: usize,
            highlight_type: syntax.HighlightType,

            fn lessThan(lhs: @This(), rhs: @This()) bool {
                if (lhs.start == rhs.start) return lhs.end < rhs.end;
                return lhs.start < rhs.start;
            }
        };

        var segments = std.ArrayListUnmanaged(Segment){};
        defer segments.deinit(self.allocator);

        for (self.highlight_cache) |range| {
            if (line_num < range.start_line or line_num > range.end_line) continue;
            if (range.highlight_type == .none) continue;

            var start_col = if (range.start_line == line_num) range.start_col else 0;
            var end_col = if (range.end_line == line_num) range.end_col else line_len;

            if (start_col > line_len) start_col = line_len;
            if (end_col > line_len) end_col = line_len;
            if (end_col <= start_col) continue;

            segments.append(self.allocator, .{ .start = start_col, .end = end_col, .highlight_type = range.highlight_type }) catch |err| {
                if (err == error.OutOfMemory) {
                    std.log.warn("Highlight segment allocation failed; falling back to plain rendering", .{});
                    try self.renderPlainLine(line, max_width);
                    return;
                }
                return err;
            };
        }

        if (segments.items.len == 0) {
            try self.renderPlainLine(line, max_width);
            return;
        }

        var segs = segments.items;
        var i: usize = 0;
        while (i < segs.len) : (i += 1) {
            var j = i + 1;
            while (j < segs.len) : (j += 1) {
                if (Segment.lessThan(segs[j], segs[i])) {
                    const tmp = segs[i];
                    segs[i] = segs[j];
                    segs[j] = tmp;
                }
            }
        }

        var col: usize = 0;
        var written: usize = 0;
        var seg_idx: usize = 0;
        var color_active = false;
        var active_type: ?syntax.HighlightType = null;
        var seq_buf: [32]u8 = undefined;

        while (col < line_len and written < max_width) {
            while (seg_idx < segments.items.len and segments.items[seg_idx].end <= col) : (seg_idx += 1) {}

            var run_type: ?syntax.HighlightType = null;
            var run_end = line_len;

            if (seg_idx < segments.items.len) {
                const seg = segments.items[seg_idx];
                if (seg.start > col) {
                    run_end = seg.start;
                } else {
                    run_type = seg.highlight_type;
                    run_end = seg.end;
                }
            }

            if (run_end <= col) {
                col += 1;
                continue;
            }

            const remaining = max_width - written;
            if (run_end - col > remaining) {
                run_end = col + remaining;
            }

            if (run_type) |ht| {
                if (!color_active or active_type != ht) {
                    if (color_active) try self.resetColor();
                    const seq = self.active_theme.getHighlightSequence(ht, &seq_buf) catch |err| {
                        std.log.err("Failed to build highlight sequence: {}", .{err});
                        return err;
                    };
                    try self.stdout.writeAll(seq);
                    color_active = true;
                    active_type = ht;
                }
            } else if (color_active) {
                try self.resetColor();
                color_active = false;
                active_type = null;
            }

            if (run_end > col) {
                try self.stdout.writeAll(line[col..run_end]);
                written += run_end - col;
            }

            col = run_end;
        }

        if (color_active) {
            try self.resetColor();
        }

        while (written < max_width) : (written += 1) {
            try self.stdout.writeAll(" ");
        }
    }

    // Buffer picker and window management functions

    fn activateBufferPicker(self: *SimpleTUI) void {
        self.setStatusMessage("Buffer picker: Ctrl+B - not yet implemented");
        // TODO: Initialize buffer picker if needed
        // if (self.buffer_picker == null) {
        //     const buf_mgr = self.buffer_manager orelse return;
        //     const picker = self.allocator.create(buffer_picker_mod.BufferPicker) catch {
        //         self.setStatusMessage("Failed to create buffer picker");
        //         return;
        //     };
        //     picker.* = buffer_picker_mod.BufferPicker.init(self.allocator, buf_mgr) catch {
        //         self.allocator.destroy(picker);
        //         self.setStatusMessage("Failed to initialize buffer picker");
        //         return;
        //     };
        //     self.buffer_picker = picker;
        // }
        // self.buffer_picker_active = true;
    }

    fn closeWindow(self: *SimpleTUI) !void {
        _ = self;
        return error.NotImplemented;
        // TODO: Implement window closing
        // if (self.window_manager) |win_mgr| {
        //     try win_mgr.closeWindow();
        //     self.setStatusMessage("Window closed");
        // } else {
        //     return error.NoWindowManager;
        // }
    }
};

test "simple tui expand snippet captures default placeholder" {
    var tui = try SimpleTUI.init(std.testing.allocator);
    defer tui.deinit();

    const expansion = try tui.expandSnippet("${1:foo}bar");
    defer tui.allocator.free(expansion.text);

    try std.testing.expectEqualStrings("foobar", expansion.text);
    try std.testing.expectEqual(@as(usize, 3), expansion.caret);
    try std.testing.expect(expansion.selection != null);
    const sel = expansion.selection.?;
    try std.testing.expectEqual(@as(usize, 0), sel.start);
    try std.testing.expectEqual(@as(usize, 3), sel.end);
}

test "simple tui expand snippet falls back to final stop" {
    var tui = try SimpleTUI.init(std.testing.allocator);
    defer tui.deinit();

    const expansion = try tui.expandSnippet("print($0)");
    defer tui.allocator.free(expansion.text);

    try std.testing.expectEqualStrings("print()", expansion.text);
    try std.testing.expectEqual(@as(usize, 6), expansion.caret);
    try std.testing.expect(expansion.selection == null);
}

test "simple tui expand snippet handles plain tab stop" {
    var tui = try SimpleTUI.init(std.testing.allocator);
    defer tui.deinit();

    const expansion = try tui.expandSnippet("$1");
    defer tui.allocator.free(expansion.text);

    try std.testing.expectEqualStrings("", expansion.text);
    try std.testing.expectEqual(@as(usize, 0), expansion.caret);
    try std.testing.expect(expansion.selection == null);
}

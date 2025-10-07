const std = @import("std");
const runtime = @import("runtime");
const syntax = @import("syntax");
const theme_mod = @import("theme.zig");
const Editor = @import("editor.zig").Editor;

pub const SimpleTUI = struct {
    allocator: std.mem.Allocator,
    editor: Editor,
    running: bool,
    stdin: std.fs.File,
    stdout: std.fs.File,
    theme_registry: theme_mod.ThemeRegistry,
    active_theme: theme_mod.Theme,
    plugin_manager: ?*runtime.PluginManager,
    highlight_cache: []syntax.HighlightRange,
    highlight_dirty: bool,
    highlight_error: ?[]u8,
    highlight_error_flash: bool,
    highlight_error_flash_state: bool,
    highlight_error_logged: bool,
    command_buffer: std.ArrayList(u8),
    status_message: ?[]u8,
    plugin_cursor: ?*runtime.PluginAPI.EditorContext.CursorPosition,

    pub fn init(allocator: std.mem.Allocator) !*SimpleTUI {
        const command_buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
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
            .highlight_cache = &.{},
            .highlight_dirty = true,
            .highlight_error = null,
            .highlight_error_flash = false,
            .highlight_error_flash_state = false,
            .highlight_error_logged = false,
            .command_buffer = command_buffer,
            .status_message = null,
            .plugin_cursor = null,
        };
        return self;
    }

    pub fn deinit(self: *SimpleTUI) void {
        if (self.highlight_cache.len > 0) {
            self.allocator.free(self.highlight_cache);
        }
        if (self.highlight_error) |msg| {
            self.allocator.free(msg);
        }
        if (self.status_message) |msg| {
            self.allocator.free(msg);
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
        try self.editor.loadFile(path);
        self.markHighlightsDirty();

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
    }

    fn render(self: *SimpleTUI) !void {
        // Get terminal size (simplified)
        const width = 80;
        const height = 24;

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

        var line_start: usize = 0;
        var logical_line: usize = 0;

        while (logical_line < height - 2 and line_start <= content.len) {
            const remaining = content[line_start..];
            const rel_newline = std.mem.indexOfScalar(u8, remaining, '\n');
            const line_end = if (rel_newline) |rel| line_start + rel else content.len;
            const line_slice = content[line_start..line_end];

            // Line numbers
            var line_buf: [16]u8 = undefined;
            const line_str = try std.fmt.bufPrint(&line_buf, "{d:4} ", .{logical_line + 1});
            try self.stdout.writeAll(line_str);

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
                'A' => self.editor.moveCursorUp(), // Up arrow
                'B' => self.editor.moveCursorDown(), // Down arrow
                'C' => self.editor.moveCursorRight(), // Right arrow
                'D' => self.editor.moveCursorLeft(), // Left arrow
                else => {},
            }
        }
    }

    fn handleNormalMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => {}, // ESC in normal mode - already in normal
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
            'w' => self.editor.moveWordForward(),
            'b' => self.editor.moveWordBackward(),
            '0' => self.editor.moveCursorToLineStart(),
            '$' => self.editor.moveCursorToLineEnd(),
            'g' => {
                // TODO: Handle 'gg' for goto top
            },
            'G' => self.editor.moveCursorToEnd(),
            ':' => self.startCommandMode(),
            'v' => self.switchMode(.visual),
            'q' => self.running = false, // Simple quit
            else => {}, // Ignore unhandled keys
        }
    }

    fn handleInsertMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.switchMode(.normal), // ESC
            8, 127 => try self.editor.backspace(), // Backspace/Delete
            13 => try self.editor.insertChar('\n'), // Enter
            else => {
                if (key >= 32 and key < 127) { // Printable ASCII
                    try self.editor.insertChar(key);
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
        _ = self;
        return 1;
    }

    fn bridgeGetCursorPosition(ctx: *anyopaque) runtime.PluginAPI.EditorContext.CursorPosition {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        const offset = self.editor.cursor.offset;
        const lc = self.editor.rope.lineColumnAtOffset(offset) catch {
            const fallback = .{ .line = 0, .column = 0, .byte_offset = offset };
            if (self.plugin_cursor) |cursor_ptr| {
                cursor_ptr.* = fallback;
            }
            return fallback;
        };
        const position = .{ .line = lc.line, .column = lc.column, .byte_offset = offset };
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

    fn bridgeNotifyChange(ctx: *anyopaque, change: runtime.PluginAPI.EditorContext.BufferChange) anyerror!void {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        _ = change;
        self.markHighlightsDirty();
        if (self.plugin_cursor) |cursor_ptr| {
            self.editor.cursor.offset = cursor_ptr.byte_offset;
            self.updatePluginCursorFromEditor();
        }
    }

    pub fn makeEditorBridge(self: *SimpleTUI) runtime.PluginAPI.EditorContext.EditorBridge {
        return .{
            .ctx = @as(*anyopaque, @ptrCast(self)),
            .getCurrentBuffer = bridgeGetCurrentBuffer,
            .getCursorPosition = bridgeGetCursorPosition,
            .setCursorPosition = bridgeSetCursorPosition,
            .notifyChange = bridgeNotifyChange,
        };
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
};

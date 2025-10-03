const std = @import("std");
const Editor = @import("editor.zig").Editor;

pub const SimpleTUI = struct {
    allocator: std.mem.Allocator,
    editor: Editor,
    running: bool,
    stdin: std.fs.File,
    stdout: std.fs.File,

    pub fn init(allocator: std.mem.Allocator) !*SimpleTUI {
        const self = try allocator.create(SimpleTUI);
        self.* = .{
            .allocator = allocator,
            .editor = try Editor.init(allocator),
            .running = true,
            .stdin = std.fs.File.stdin(),
            .stdout = std.fs.File.stdout(),
        };
        return self;
    }

    pub fn deinit(self: *SimpleTUI) void {
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
    }

    fn render(self: *SimpleTUI) !void {
        // Get terminal size (simplified)
        const width = 80;
        const height = 24;

        try self.clearScreen();
        try self.setCursor(1, 1);

        // Render content
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        var lines = std.mem.tokenizeAny(u8, content, "\n");
        var line_num: usize = 1;

        while (lines.next()) |line| {
            if (line_num > height - 2) break; // Leave space for status line

            // Line numbers
            var line_buf: [16]u8 = undefined;
            const line_str = try std.fmt.bufPrint(&line_buf, "{d:4} ", .{line_num});
            try self.stdout.writeAll(line_str);

            // Content (truncate to screen width)
            const display_line = if (line.len > width - 6) line[0..width - 6] else line;
            try self.stdout.writeAll(display_line);
            try self.stdout.writeAll("\r\n");

            line_num += 1;
        }

        // Fill remaining lines
        while (line_num <= height - 2) : (line_num += 1) {
            try self.stdout.writeAll("~\r\n");
        }

        // Status line
        try self.setCursor(height, 1);
        try self.setColor(47, 30); // White background, black text

        const mode_str = switch (self.editor.mode) {
            .normal => "NORMAL",
            .insert => "INSERT",
            .visual => "VISUAL",
            .command => "COMMAND",
        };

        const cursor_line = self.getCursorLine();
        const cursor_col = self.getCursorColumn();

        var status_buf: [256]u8 = undefined;
        const base_status = try std.fmt.bufPrint(&status_buf, " {s} | {d},{d} | {d} bytes", .{
            mode_str,
            cursor_line + 1,
            cursor_col + 1,
            self.editor.rope.len(),
        });

        // Pad with spaces to fill width
        const padding_len = if (base_status.len < width) width - base_status.len else 0;
        var final_status_buf: [256]u8 = undefined;
        @memcpy(final_status_buf[0..base_status.len], base_status);
        @memset(final_status_buf[base_status.len..base_status.len + padding_len], ' ');
        const status = final_status_buf[0..base_status.len + padding_len];

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
                'A' => self.editor.moveCursorUp(),    // Up arrow
                'B' => self.editor.moveCursorDown(),  // Down arrow
                'C' => self.editor.moveCursorRight(), // Right arrow
                'D' => self.editor.moveCursorLeft(),  // Left arrow
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
            'i' => self.editor.mode = .insert,
            'I' => {
                self.editor.moveCursorToLineStart();
                self.editor.mode = .insert;
            },
            'a' => {
                self.editor.moveCursorRight();
                self.editor.mode = .insert;
            },
            'A' => {
                self.editor.moveCursorToLineEnd();
                self.editor.mode = .insert;
            },
            'o' => {
                try self.editor.insertNewlineAfter();
                self.editor.mode = .insert;
            },
            'O' => {
                try self.editor.insertNewlineBefore();
                self.editor.mode = .insert;
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
            ':' => self.editor.mode = .command,
            'v' => self.editor.mode = .visual,
            'q' => self.running = false, // Simple quit
            else => {}, // Ignore unhandled keys
        }
    }

    fn handleInsertMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.editor.mode = .normal, // ESC
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
            27 => self.editor.mode = .normal, // ESC
            'h' => self.editor.moveCursorLeft(),
            'j' => self.editor.moveCursorDown(),
            'k' => self.editor.moveCursorUp(),
            'l' => self.editor.moveCursorRight(),
            'd' => {
                // TODO: Delete selection
                self.editor.mode = .normal;
            },
            'y' => {
                // TODO: Yank selection
                self.editor.mode = .normal;
            },
            else => {},
        }
    }

    fn handleCommandMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.editor.mode = .normal, // ESC
            13 => { // Enter
                // TODO: Execute command
                self.editor.mode = .normal;
            },
            else => {
                // TODO: Build command string
            },
        }
    }

    fn enableRawMode(self: *SimpleTUI) !void {
        _ = self;
        // Platform-specific raw mode setup would go here
        // For now, just a placeholder
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
};
const std = @import("std");
const core = @import("core");
const syntax = @import("syntax");

pub const Editor = struct {
    allocator: std.mem.Allocator,
    rope: core.Rope,
    mode: Mode,
    cursor: Position,
    highlighter: syntax.SyntaxHighlighter,
    current_filename: ?[]const u8,

    pub const Mode = enum {
        normal,
        insert,
        visual,
        command,
    };

    pub const Position = struct {
        offset: usize = 0, // Byte offset in the rope

        pub fn moveLeft(self: *Position, rope: *core.Rope) void {
            if (self.offset == 0) return;

            // Move to previous UTF-8 character boundary
            const slice = rope.slice(.{ .start = 0, .end = self.offset }) catch return;
            var i = self.offset - 1;
            while (i > 0 and (slice[i] & 0xC0) == 0x80) : (i -= 1) {}
            self.offset = i;
        }

        pub fn moveRight(self: *Position, rope: *core.Rope) void {
            if (self.offset >= rope.len()) return;

            // Move to next UTF-8 character boundary
            const slice = rope.slice(.{ .start = self.offset, .end = rope.len() }) catch return;
            var i: usize = 1;
            while (i < slice.len and (slice[i] & 0xC0) == 0x80) : (i += 1) {}
            self.offset = @min(self.offset + i, rope.len());
        }

        pub fn moveToLineStart(self: *Position, rope: *core.Rope) void {
            if (self.offset == 0) return;

            // Find previous newline
            const slice = rope.slice(.{ .start = 0, .end = self.offset }) catch return;
            var i = self.offset;
            while (i > 0) : (i -= 1) {
                if (slice[i - 1] == '\n') break;
            }
            self.offset = i;
        }

        pub fn moveToLineEnd(self: *Position, rope: *core.Rope) void {
            const len = rope.len();
            if (self.offset >= len) return;

            // Find next newline
            const slice = rope.slice(.{ .start = self.offset, .end = len }) catch return;
            for (slice, 0..) |ch, i| {
                if (ch == '\n') {
                    self.offset += i;
                    return;
                }
            }
            self.offset = len;
        }
    };

    pub const Command = enum {
        move_left,
        move_right,
        move_up,
        move_down,
        move_word_forward,
        move_word_backward,
        move_line_start,
        move_line_end,
        move_file_start,
        move_file_end,
        enter_insert,
        enter_insert_after,
        enter_visual,
        enter_command,
        escape_to_normal,
        delete_char,
        delete_line,
        yank_line,
        paste_after,
    };

    pub const Error = error{
        UnhandledKey,
        RopeError,
        Utf8CannotEncodeSurrogateHalf,
        CodepointTooLarge,
    } || std.mem.Allocator.Error || core.Rope.Error;

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return .{
            .allocator = allocator,
            .rope = try core.Rope.init(allocator),
            .mode = .normal,
            .cursor = .{},
            .highlighter = syntax.SyntaxHighlighter.init(allocator),
            .current_filename = null,
        };
    }

    pub fn deinit(self: *Editor) void {
        self.rope.deinit();
        self.highlighter.deinit();
        if (self.current_filename) |filename| {
            self.allocator.free(filename);
        }
        self.* = undefined;
    }

    pub fn loadFile(self: *Editor, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);

        _ = try file.read(content);
        try self.rope.insert(0, content);

        // Update filename and initialize syntax highlighting
        if (self.current_filename) |old_filename| {
            self.allocator.free(old_filename);
        }
        self.current_filename = try self.allocator.dupe(u8, path);
        try self.highlighter.setLanguage(path);
    }

    pub fn saveFile(self: *Editor, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        try file.writeAll(content);
    }

    pub fn handleKey(self: *Editor, key: u21) Error!void {
        switch (self.mode) {
            .normal => {
                if (self.commandForNormalKey(key)) |cmd| {
                    try self.dispatch(cmd);
                } else {
                    return Error.UnhandledKey;
                }
            },
            .insert => {
                if (key == 0x1B) { // ESC
                    self.mode = .normal;
                } else {
                    try self.insertChar(key);
                }
            },
            .visual => {
                if (key == 0x1B) { // ESC
                    self.mode = .normal;
                }
                // TODO: Implement visual mode commands
            },
            .command => {
                if (key == 0x1B) { // ESC
                    self.mode = .normal;
                }
                // TODO: Implement command mode
            },
        }
    }

    pub fn dispatch(self: *Editor, command: Command) Error!void {
        switch (command) {
            .move_left => self.cursor.moveLeft(&self.rope),
            .move_right => self.cursor.moveRight(&self.rope),
            .move_up => self.moveCursorUp(),
            .move_down => self.moveCursorDown(),
            .move_word_forward => self.moveCursorWordForward(),
            .move_word_backward => self.moveCursorWordBackward(),
            .move_line_start => self.cursor.moveToLineStart(&self.rope),
            .move_line_end => self.cursor.moveToLineEnd(&self.rope),
            .move_file_start => self.cursor.offset = 0,
            .move_file_end => self.cursor.offset = self.rope.len(),
            .enter_insert => self.mode = .insert,
            .enter_insert_after => {
                self.cursor.moveRight(&self.rope);
                self.mode = .insert;
            },
            .enter_visual => self.mode = .visual,
            .enter_command => self.mode = .command,
            .escape_to_normal => self.mode = .normal,
            .delete_char => try self.deleteCharAtCursor(),
            .delete_line => try self.deleteCurrentLine(),
            .yank_line => {}, // TODO: Implement yank
            .paste_after => {}, // TODO: Implement paste
        }
    }

    fn commandForNormalKey(self: *Editor, key: u21) ?Command {
        _ = self;
        return switch (key) {
            'h' => .move_left,
            'j' => .move_down,
            'k' => .move_up,
            'l' => .move_right,
            'w' => .move_word_forward,
            'b' => .move_word_backward,
            '0' => .move_line_start,
            '$' => .move_line_end,
            'g' => null, // TODO: Handle gg
            'G' => .move_file_end,
            'i' => .enter_insert,
            'a' => .enter_insert_after,
            'v' => .enter_visual,
            ':' => .enter_command,
            'x' => .delete_char,
            'd' => null, // TODO: Handle dd
            'y' => null, // TODO: Handle yy
            'p' => .paste_after,
            0x1B => .escape_to_normal,
            else => null,
        };
    }

    pub fn insertChar(self: *Editor, key: u21) !void {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(key, &buf);
        try self.rope.insert(self.cursor.offset, buf[0..len]);
        self.cursor.offset += len;
    }

    pub fn getSyntaxHighlights(self: *Editor) ![]syntax.HighlightRange {
        const highlights = try self.highlighter.highlight(&self.rope);
        defer self.allocator.free(highlights);
        return syntax.convertHighlightsToRanges(self.allocator, highlights, &self.rope);
    }

    pub fn getLanguageName(self: *const Editor) []const u8 {
        return self.highlighter.getLanguageName();
    }

    fn deleteCharAtCursor(self: *Editor) !void {
        if (self.cursor.offset >= self.rope.len()) return;

        // Find the end of the current UTF-8 character
        const slice = try self.rope.slice(.{ .start = self.cursor.offset, .end = self.rope.len() });
        var char_len: usize = 1;
        while (char_len < slice.len and (slice[char_len] & 0xC0) == 0x80) : (char_len += 1) {}

        try self.rope.delete(self.cursor.offset, char_len);
    }

    fn deleteCurrentLine(self: *Editor) !void {
        // Find line boundaries
        self.cursor.moveToLineStart(&self.rope);
        const start = self.cursor.offset;
        self.cursor.moveToLineEnd(&self.rope);
        var end = self.cursor.offset;

        // Include the newline if not at end of file
        if (end < self.rope.len()) {
            end += 1;
        }

        if (end > start) {
            try self.rope.delete(start, end - start);
            self.cursor.offset = start;
        }
    }

    pub fn moveCursorUp(self: *Editor) void {
        // Save current column position
        const current_col = self.getColumnPosition();

        // Move to previous line
        self.cursor.moveToLineStart(&self.rope);
        if (self.cursor.offset > 0) {
            self.cursor.offset -= 1; // Move past previous newline
            self.cursor.moveToLineStart(&self.rope);

            // Restore column position
            self.moveToColumn(current_col);
        }
    }

    pub fn moveCursorDown(self: *Editor) void {
        // Save current column position
        const current_col = self.getColumnPosition();

        // Move to next line
        self.cursor.moveToLineEnd(&self.rope);
        if (self.cursor.offset < self.rope.len()) {
            self.cursor.offset += 1; // Move past newline

            // Restore column position
            self.moveToColumn(current_col);
        }
    }

    fn getColumnPosition(self: *Editor) usize {
        const line_start = blk: {
            var pos = Position{ .offset = self.cursor.offset };
            pos.moveToLineStart(&self.rope);
            break :blk pos.offset;
        };

        return self.cursor.offset - line_start;
    }

    fn moveToColumn(self: *Editor, col: usize) void {
        const line_start = self.cursor.offset;
        const line_end = blk: {
            var pos = Position{ .offset = self.cursor.offset };
            pos.moveToLineEnd(&self.rope);
            break :blk pos.offset;
        };

        self.cursor.offset = @min(line_start + col, line_end);
    }

    pub fn moveCursorWordForward(self: *Editor) void {
        const len = self.rope.len();
        if (self.cursor.offset >= len) return;

        const slice = self.rope.slice(.{ .start = self.cursor.offset, .end = len }) catch return;

        var i: usize = 0;
        var in_word = false;

        // Skip current word/whitespace
        while (i < slice.len) : (i += 1) {
            const is_word_char = std.ascii.isAlphanumeric(slice[i]) or slice[i] == '_';
            if (!in_word and is_word_char) {
                in_word = true;
            } else if (in_word and !is_word_char) {
                break;
            }
        }

        // Skip whitespace to next word
        while (i < slice.len and std.ascii.isWhitespace(slice[i])) : (i += 1) {}

        self.cursor.offset = @min(self.cursor.offset + i, len);
    }

    pub fn moveCursorWordBackward(self: *Editor) void {
        if (self.cursor.offset == 0) return;

        const slice = self.rope.slice(.{ .start = 0, .end = self.cursor.offset }) catch return;

        var i = slice.len;

        // Skip whitespace
        while (i > 0 and std.ascii.isWhitespace(slice[i - 1])) : (i -= 1) {}

        // Skip word characters
        while (i > 0 and (std.ascii.isAlphanumeric(slice[i - 1]) or slice[i - 1] == '_')) : (i -= 1) {}

        self.cursor.offset = i;
    }

    // Public interface aliases for SimpleTUI
    pub fn moveCursorLeft(self: *Editor) void {
        self.cursor.moveLeft(&self.rope);
    }

    pub fn moveCursorRight(self: *Editor) void {
        self.cursor.moveRight(&self.rope);
    }

    pub fn moveCursorToLineStart(self: *Editor) void {
        self.cursor.moveToLineStart(&self.rope);
    }

    pub fn moveCursorToLineEnd(self: *Editor) void {
        self.cursor.moveToLineEnd(&self.rope);
    }

    pub fn moveCursorToEnd(self: *Editor) void {
        self.cursor.offset = self.rope.len();
    }

    pub fn moveWordForward(self: *Editor) void {
        self.moveCursorWordForward();
    }

    pub fn moveWordBackward(self: *Editor) void {
        self.moveCursorWordBackward();
    }

    pub fn deleteChar(self: *Editor) !void {
        try self.deleteCharAtCursor();
    }

    pub fn insertNewlineAfter(self: *Editor) !void {
        self.cursor.moveToLineEnd(&self.rope);
        try self.rope.insert(self.cursor.offset, "\n");
        self.cursor.offset += 1;
    }

    pub fn insertNewlineBefore(self: *Editor) !void {
        self.cursor.moveToLineStart(&self.rope);
        try self.rope.insert(self.cursor.offset, "\n");
        // Don't move cursor - we want to be on the new line above
    }

    pub fn backspace(self: *Editor) !void {
        if (self.cursor.offset == 0) return;
        self.cursor.moveLeft(&self.rope);
        try self.rope.delete(self.cursor.offset, 1);
    }
};

test "editor basic operations" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Insert some text
    try editor.rope.insert(0, "Hello, world!\nThis is a test.");

    // Test movement
    try editor.handleKey('l');
    try std.testing.expectEqual(@as(usize, 1), editor.cursor.offset);

    try editor.handleKey('w');
    try std.testing.expect(editor.cursor.offset > 1);

    try editor.handleKey('0');
    try std.testing.expectEqual(@as(usize, 0), editor.cursor.offset);

    // Test mode switching
    try editor.handleKey('i');
    try std.testing.expect(editor.mode == .insert);

    try editor.handleKey('a');
    try std.testing.expect(editor.rope.len() > 30);

    try editor.handleKey(0x1B); // ESC
    try std.testing.expect(editor.mode == .normal);
}
const std = @import("std");
const core = @import("core");

pub const Mode = enum {
    normal,
    insert,
};

pub const Command = enum {
    move_left,
    move_right,
    move_up,
    move_down,
    enter_insert,
    escape_to_normal,
    quit,
};

pub const Error = error{
    UnhandledKey,
} || std.mem.Allocator.Error || core.Rope.Error;

pub const App = struct {
    allocator: std.mem.Allocator,
    mode: Mode,
    cursor: Position,
    buffer: core.Rope,
    insert_buffer: std.ArrayListUnmanaged(u8),
    should_quit: bool,

    const ESCAPE: u21 = 0x1B;

    pub const Position = struct {
        row: usize = 0,
        column: usize = 0,

        fn moveLeft(self: *Position) void {
            if (self.column > 0) self.column -= 1;
        }

        fn moveRight(self: *Position) void {
            self.column += 1;
        }

        fn moveUp(self: *Position) void {
            if (self.row > 0) self.row -= 1;
        }

        fn moveDown(self: *Position) void {
            self.row += 1;
        }
    };

    pub fn init(allocator: std.mem.Allocator) Error!App {
        const buffer = try core.Rope.init(allocator);
        
        return .{
            .allocator = allocator,
            .mode = .normal,
            .cursor = .{},
            .buffer = buffer,
            .insert_buffer = .{},
            .should_quit = false,
        };
    }

    pub fn deinit(self: *App) void {
        self.insert_buffer.deinit(self.allocator);
        self.buffer.deinit();
        self.* = undefined;
    }

    pub fn run(self: *App) Error!void {
        // For now, just render once and exit
        try self.render();
        std.debug.print("Editor initialized with {} characters\n", .{self.buffer.len()});
    }

    fn render(self: *App) Error!void {
        // Clear screen and render simple text-based UI
        std.debug.print("\x1B[2J\x1B[H", .{}); // Clear screen and move cursor to top
        
        // Draw buffer content
        if (self.buffer.len() > 0) {
            const content = try self.buffer.slice(.{ .start = 0, .end = self.buffer.len() });
            std.debug.print("{s}\n", .{content});
        } else {
            std.debug.print("~ (empty buffer)\n", .{});
        }
        
        // Draw mode indicator
        const mode_text = switch (self.mode) {
            .normal => "-- NORMAL --",
            .insert => "-- INSERT --",
        };
        
        std.debug.print("\n{s}\n", .{mode_text});
        std.debug.print("Cursor: row={}, col={}\n", .{ self.cursor.row, self.cursor.column });
        std.debug.print("Commands: h/j/k/l=move, i=insert, ESC=normal, q=quit\n", .{});
    }

    pub fn handleKey(self: *App, key: u21) Error!void {
        switch (self.mode) {
            .normal => {
                if (self.commandForNormalKey(key)) |cmd| {
                    try self.dispatch(cmd);
                } else {
                    return Error.UnhandledKey;
                }
            },
            .insert => {
                if (key == ESCAPE) {
                    try self.dispatch(.escape_to_normal);
                } else {
                    try self.recordInsert(key);
                }
            },
        }
    }

    pub fn dispatch(self: *App, command: Command) Error!void {
        switch (command) {
            .move_left => {
                if (self.cursor.column > 0) {
                    self.cursor.column -= 1;
                }
            },
            .move_right => {
                if (self.buffer.len() > 0) {
                    const line_end = try self.findLineEnd(self.cursor.row);
                    if (self.cursor.column < line_end) {
                        self.cursor.column += 1;
                    }
                }
            },
            .move_up => {
                if (self.cursor.row > 0) {
                    self.cursor.row -= 1;
                }
            },
            .move_down => {
                const line_count = try self.countLines();
                if (self.cursor.row < line_count - 1) {
                    self.cursor.row += 1;
                }
            },
            .enter_insert => {
                self.mode = .insert;
                self.insert_buffer.clearRetainingCapacity();
            },
            .escape_to_normal => {
                if (self.mode == .insert and self.insert_buffer.items.len > 0) {
                    // Insert the buffered text at cursor position
                    const cursor_pos = try self.cursorToBytePos();
                    try self.buffer.insert(cursor_pos, self.insert_buffer.items);
                    self.insert_buffer.clearRetainingCapacity();
                }
                self.mode = .normal;
            },
            .quit => {
                self.should_quit = true;
            },
        }
    }

    pub fn commandForNormalKey(self: *App, key: u21) ?Command {
        _ = self;
        return switch (key) {
            'h' => .move_left,
            'j' => .move_down,
            'k' => .move_up,
            'l' => .move_right,
            'i' => .enter_insert,
            'q' => .quit,
            ESCAPE => .escape_to_normal,
            else => null,
        };
    }

    pub fn lastInserted(self: *const App) []const u8 {
        return self.insert_buffer.items[0..self.insert_buffer.items.len];
    }

    fn recordInsert(self: *App, key: u21) !void {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(key, &buf);
        try self.insert_buffer.ensureTotalCapacity(self.allocator, self.insert_buffer.items.len + len);
        for (buf[0..len]) |byte| {
            self.insert_buffer.appendAssumeCapacity(byte);
        }
    }

    fn cursorToBytePos(self: *App) Error!usize {
        if (self.buffer.len() == 0) return 0;
        
        var current_row: usize = 0;
        var current_col: usize = 0;
        
        const content = try self.buffer.slice(.{ .start = 0, .end = self.buffer.len() });
        
        for (content, 0..) |byte, i| {
            if (current_row == self.cursor.row and current_col == self.cursor.column) {
                return i;
            }
            
            if (byte == '\n') {
                current_row += 1;
                current_col = 0;
                if (current_row > self.cursor.row) {
                    return i;
                }
            } else {
                current_col += 1;
            }
        }
        
        return content.len;
    }

    fn findLineEnd(self: *App, row: usize) Error!usize {
        if (self.buffer.len() == 0) return 0;
        
        var current_row: usize = 0;
        var line_start: usize = 0;
        
        const content = try self.buffer.slice(.{ .start = 0, .end = self.buffer.len() });
        
        for (content, 0..) |byte, i| {
            if (current_row == row) {
                if (byte == '\n') {
                    return i - line_start;
                }
            } else if (current_row > row) {
                break;
            }
            
            if (byte == '\n') {
                if (current_row == row) {
                    return i - line_start;
                }
                current_row += 1;
                line_start = i + 1;
            }
        }
        
        return if (current_row == row) content.len - line_start else 0;
    }

    fn countLines(self: *App) Error!usize {
        if (self.buffer.len() == 0) return 1;
        
        const content = try self.buffer.slice(.{ .start = 0, .end = self.buffer.len() });
        var count: usize = 1;
        
        for (content) |byte| {
            if (byte == '\n') {
                count += 1;
            }
        }
        
        return count;
    }
};

test "normal mode movement dispatch" {
    const allocator = std.testing.allocator;
    var app = App.init(allocator);
    defer app.deinit();

    try app.handleKey('l');
    try app.handleKey('l');
    try app.handleKey('j');
    try std.testing.expectEqual(@as(usize, 2), app.cursor.column);
    try std.testing.expectEqual(@as(usize, 1), app.cursor.row);

    try app.handleKey('h');
    try std.testing.expectEqual(@as(usize, 1), app.cursor.column);
}

test "mode transitions and insert recording" {
    const allocator = std.testing.allocator;
    var app = App.init(allocator);
    defer app.deinit();

    try app.handleKey('i');
    try std.testing.expect(app.mode == .insert);

    try app.handleKey('a');
    try app.handleKey('b');
    try std.testing.expectEqualStrings("ab", app.lastInserted());

    try app.handleKey(App.ESCAPE);
    try std.testing.expect(app.mode == .normal);
}

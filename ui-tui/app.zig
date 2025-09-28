const std = @import("std");

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
};

pub const Error = error{
    UnhandledKey,
} || std.mem.Allocator.Error;

pub const App = struct {
    allocator: std.mem.Allocator,
    mode: Mode,
    cursor: Position,
    insert_buffer: std.ArrayListUnmanaged(u8),

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

    pub fn init(allocator: std.mem.Allocator) App {
        return .{
            .allocator = allocator,
            .mode = .normal,
            .cursor = .{},
            .insert_buffer = .{},
        };
    }

    pub fn deinit(self: *App) void {
        self.insert_buffer.deinit(self.allocator);
        self.* = undefined;
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
            .move_left => self.cursor.moveLeft(),
            .move_right => self.cursor.moveRight(),
            .move_up => self.cursor.moveUp(),
            .move_down => self.cursor.moveDown(),
            .enter_insert => self.mode = .insert,
            .escape_to_normal => self.mode = .normal,
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
            ESCAPE => .escape_to_normal,
            else => null,
        };
    }

    pub fn lastInserted(self: *const App) []const u8 {
        return self.insert_buffer.items[0..self.insert_buffer.len];
    }

    fn recordInsert(self: *App, key: u21) !void {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(key, &buf);
        try self.insert_buffer.ensureTotalCapacity(self.allocator, self.insert_buffer.len + len);
        for (buf[0..len]) |byte| {
            self.insert_buffer.appendAssumeCapacity(byte);
        }
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

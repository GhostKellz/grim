//! CommandBar - Command line input widget (:, /, ?)

const std = @import("std");
const phantom = @import("phantom");


pub const CommandMode = enum {
    command, // :command
    search, // /search
    search_backward, // ?search
};

pub const CommandBar = struct {
    allocator: std.mem.Allocator,
    visible: bool,
    mode: CommandMode,

    // Input buffer
    buffer: std.ArrayList(u8),
    cursor_pos: usize,

    // History
    history: std.ArrayList([]const u8),
    history_index: ?usize,

    pub fn init(allocator: std.mem.Allocator) !*CommandBar {
        const self = try allocator.create(CommandBar);

        self.* = .{
            .allocator = allocator,
            .visible = false,
            .mode = .command,
            .buffer = std.ArrayList(u8).init(allocator),
            .cursor_pos = 0,
            .history = std.ArrayList([]const u8).init(allocator),
            .history_index = null,
        };

        return self;
    }

    pub fn deinit(self: *CommandBar) void {
        for (self.history.items) |item| {
            self.allocator.free(item);
        }
        self.history.deinit();
        self.buffer.deinit();
        self.allocator.destroy(self);
    }

    pub fn show(self: *CommandBar, mode: CommandMode) void {
        self.visible = true;
        self.mode = mode;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.history_index = null;
    }

    pub fn hide(self: *CommandBar) void {
        self.visible = false;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn handleKey(self: *CommandBar, key: phantom.Key, app: anytype) !bool {
        switch (key) {
            .escape => {
                self.hide();
                app.mode = .normal;
                return true;
            },
            .enter => {
                // Execute command
                try self.execute(app);
                return true;
            },
            .backspace => {
                if (self.cursor_pos > 0) {
                    _ = self.buffer.orderedRemove(self.cursor_pos - 1);
                    self.cursor_pos -= 1;
                }
                return true;
            },
            .delete => {
                if (self.cursor_pos < self.buffer.items.len) {
                    _ = self.buffer.orderedRemove(self.cursor_pos);
                }
                return true;
            },
            .left => {
                if (self.cursor_pos > 0) {
                    self.cursor_pos -= 1;
                }
                return true;
            },
            .right => {
                if (self.cursor_pos < self.buffer.items.len) {
                    self.cursor_pos += 1;
                }
                return true;
            },
            .home => {
                self.cursor_pos = 0;
                return true;
            },
            .end => {
                self.cursor_pos = self.buffer.items.len;
                return true;
            },
            .up => {
                // Navigate history
                try self.historyPrev();
                return true;
            },
            .down => {
                // Navigate history
                try self.historyNext();
                return true;
            },
            .char => |c| {
                try self.buffer.insert(self.cursor_pos, c);
                self.cursor_pos += 1;
                return true;
            },
            else => return false,
        }
    }

    fn execute(self: *CommandBar, app: anytype) !void {
        const command = self.buffer.items;

        if (command.len > 0) {
            // Add to history
            const history_item = try self.allocator.dupe(u8, command);
            try self.history.append(history_item);

            // Execute based on mode
            switch (self.mode) {
                .command => {
                    try app.executeCommand(command);
                },
                .search, .search_backward => {
                    // TODO: Implement search
                    std.log.warn("Search not yet implemented: {s}", .{command});
                },
            }
        }

        self.hide();
        app.mode = .normal;
    }

    fn historyPrev(self: *CommandBar) !void {
        if (self.history.items.len == 0) return;

        if (self.history_index) |idx| {
            if (idx > 0) {
                self.history_index = idx - 1;
            }
        } else {
            self.history_index = self.history.items.len - 1;
        }

        if (self.history_index) |idx| {
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.history.items[idx]);
            self.cursor_pos = self.buffer.items.len;
        }
    }

    fn historyNext(self: *CommandBar) !void {
        if (self.history_index) |idx| {
            if (idx + 1 < self.history.items.len) {
                self.history_index = idx + 1;
                self.buffer.clearRetainingCapacity();
                try self.buffer.appendSlice(self.history.items[idx + 1]);
                self.cursor_pos = self.buffer.items.len;
            } else {
                // At end of history, clear
                self.history_index = null;
                self.buffer.clearRetainingCapacity();
                self.cursor_pos = 0;
            }
        }
    }

    pub fn render(self: *CommandBar, buffer: anytype, area: phantom.Rect) void {
        if (!self.visible) return;

        // Render prompt
        const prompt = switch (self.mode) {
            .command => ":",
            .search => "/",
            .search_backward => "?",
        };

        const style = phantom.Style.default()
            .withFg(phantom.Color.white)
            .withBg(phantom.Color.black);

        buffer.writeText(area.x, area.y, prompt, style);

        // Render input text
        const text_start_x = area.x + 1;
        var current_x = text_start_x;
        var i: usize = 0;

        while (i < self.buffer.items.len and current_x < area.x + area.width) : (i += 1) {
            const c = self.buffer.items[i];
            buffer.setCell(current_x, area.y, phantom.Cell.init(c, style));
            current_x += 1;
        }

        // Render cursor
        const cursor_x = text_start_x + @as(u16, @intCast(self.cursor_pos));
        if (cursor_x < area.x + area.width) {
            const cursor_char: u21 = if (self.cursor_pos < self.buffer.items.len)
                self.buffer.items[self.cursor_pos]
            else
                ' ';

            const cursor_style = phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.white);

            buffer.setCell(cursor_x, area.y, phantom.Cell.init(cursor_char, cursor_style));
        }
    }
};

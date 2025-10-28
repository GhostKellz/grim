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
            .buffer = .{},
            .cursor_pos = 0,
            .history = .{},
            .history_index = null,
        };

        return self;
    }

    pub fn deinit(self: *CommandBar) void {
        for (self.history.items) |item| {
            self.allocator.free(item);
        }
        self.history.deinit(self.allocator);
        self.buffer.deinit(self.allocator);
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
            .tab => {
                // Tab completion
                try self.tabComplete();
                return true;
            },
            .char => |c| {
                try self.buffer.insert(self.allocator, self.cursor_pos, @intCast(c));
                self.cursor_pos += 1;
                return true;
            },
            else => return false,
        }
    }

    fn tabComplete(self: *CommandBar) !void {
        if (self.mode != .command) return;
        if (self.buffer.items.len == 0) return;

        const input = self.buffer.items;

        // List of completable commands
        const commands = [_][]const u8{
            "quit",     "q",
            "write",    "w",
            "wq",
            "split",    "sp",
            "vsplit",   "vsp",
            "tabnew",
            "tabn",     "tabnext",
            "tabp",     "tabprev",
            "tabc",     "tabclose",
            "edit",     "e",
            "bnext",    "bn",
            "bprev",    "bp",
            "bdelete",  "bd",
            "buffers",  "ls",
            "LspDiagnostics",
            "lspdiag",
            "%s/",      "s/",
        };

        // Find matches
        var matches = std.ArrayList([]const u8){};
        defer matches.deinit(self.allocator);

        for (commands) |cmd| {
            if (std.mem.startsWith(u8, cmd, input)) {
                try matches.append(self.allocator, cmd);
            }
        }

        if (matches.items.len == 1) {
            // Single match, complete it
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.allocator, matches.items[0]);
            self.cursor_pos = self.buffer.items.len;
        } else if (matches.items.len > 1) {
            // Multiple matches, complete to longest common prefix
            const common = longestCommonPrefix(matches.items);
            if (common.len > input.len) {
                self.buffer.clearRetainingCapacity();
                try self.buffer.appendSlice(self.allocator, common);
                self.cursor_pos = self.buffer.items.len;
            }
        }
    }

    fn longestCommonPrefix(strings: []const []const u8) []const u8 {
        if (strings.len == 0) return "";
        if (strings.len == 1) return strings[0];

        var prefix_len: usize = 0;
        const first = strings[0];

        outer: while (prefix_len < first.len) {
            const ch = first[prefix_len];
            for (strings[1..]) |str| {
                if (prefix_len >= str.len or str[prefix_len] != ch) {
                    break :outer;
                }
            }
            prefix_len += 1;
        }

        return first[0..prefix_len];
    }

    fn execute(self: *CommandBar, app: anytype) !void {
        const command = self.buffer.items;

        if (command.len > 0) {
            // Add to history
            const history_item = try self.allocator.dupe(u8, command);
            try self.history.append(self.allocator, history_item);

            // Execute based on mode
            switch (self.mode) {
                .command => {
                    try app.executeCommand(command);
                },
                .search => {
                    // Forward search
                    if (app.layout_manager.getActiveEditor()) |editor| {
                        try editor.search(command, true);
                    }
                },
                .search_backward => {
                    // Backward search
                    if (app.layout_manager.getActiveEditor()) |editor| {
                        try editor.search(command, false);
                    }
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
            try self.buffer.appendSlice(self.allocator, self.history.items[idx]);
            self.cursor_pos = self.buffer.items.len;
        }
    }

    fn historyNext(self: *CommandBar) !void {
        if (self.history_index) |idx| {
            if (idx + 1 < self.history.items.len) {
                self.history_index = idx + 1;
                self.buffer.clearRetainingCapacity();
                try self.buffer.appendSlice(self.allocator, self.history.items[idx + 1]);
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

        // Clear the command bar line
        const bg_style = phantom.Style.default()
            .withBg(phantom.Color.black);
        var x: u16 = 0;
        while (x < area.width) : (x += 1) {
            buffer.setCell(area.x + x, area.y, .{ .char = ' ', .style = bg_style });
        }

        // Render "Cmdline:" label with styled background
        const label_style = phantom.Style.default()
            .withFg(phantom.Color.black)
            .withBg(phantom.Color.cyan)
            .withBold();

        const label = " Cmdline ";
        var label_x = area.x;
        for (label) |c| {
            buffer.setCell(label_x, area.y, .{ .char = c, .style = label_style });
            label_x += 1;
        }

        // Render prompt character
        const prompt = switch (self.mode) {
            .command => " : ",
            .search => " / ",
            .search_backward => " ? ",
        };

        const prompt_style = phantom.Style.default()
            .withFg(phantom.Color.bright_yellow)
            .withBg(phantom.Color.black)
            .withBold();

        var prompt_x = label_x;
        for (prompt) |c| {
            buffer.setCell(prompt_x, area.y, .{ .char = c, .style = prompt_style });
            prompt_x += 1;
        }

        // Render input text
        const text_start_x = prompt_x;
        const text_style = phantom.Style.default()
            .withFg(phantom.Color.white)
            .withBg(phantom.Color.black);

        var current_x = text_start_x;
        var i: usize = 0;

        while (i < self.buffer.items.len and current_x < area.x + area.width) : (i += 1) {
            const c = self.buffer.items[i];
            buffer.setCell(current_x, area.y, .{ .char = c, .style = text_style });
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
                .withBg(phantom.Color.bright_white);

            buffer.setCell(cursor_x, area.y, .{ .char = cursor_char, .style = cursor_style });
        }
    }
};

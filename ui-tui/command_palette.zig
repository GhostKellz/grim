//! Command Palette - Fuzzy-searchable command launcher (Ctrl+Shift+P)
//! Similar to VS Code's command palette or Telescope in Neovim

const std = @import("std");
const phantom = @import("phantom");

/// Registered command entry
pub const Command = struct {
    /// Command ID (e.g., "editor.save", "window.split")
    id: []const u8,

    /// Display name shown in palette
    name: []const u8,

    /// Description text
    description: []const u8,

    /// Keybinding hint (optional, e.g., "Ctrl+S")
    keybinding: ?[]const u8,

    /// Category for grouping (e.g., "Editor", "Window", "LSP")
    category: []const u8,

    /// Callback function to execute when selected
    callback: *const fn (ctx: *anyopaque) anyerror!void,
};

pub const CommandPalette = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(Command),

    // UI state
    is_open: bool,
    search_query: std.ArrayList(u8),
    selected_index: usize,
    scroll_offset: usize,

    // Context for command execution
    context: ?*anyopaque,

    pub fn init(allocator: std.mem.Allocator) !*CommandPalette {
        const self = try allocator.create(CommandPalette);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .commands = std.ArrayList(Command){},
            .is_open = false,
            .search_query = std.ArrayList(u8){},
            .selected_index = 0,
            .scroll_offset = 0,
            .context = null,
        };

        return self;
    }

    pub fn deinit(self: *CommandPalette) void {
        self.commands.deinit(self.allocator);
        self.search_query.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Register a command in the palette
    pub fn registerCommand(self: *CommandPalette, command: Command) !void {
        try self.commands.append(self.allocator, command);
    }

    /// Open the command palette
    pub fn open(self: *CommandPalette, context: ?*anyopaque) void {
        self.is_open = true;
        self.context = context;
        self.search_query.clearRetainingCapacity();
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Close the command palette
    pub fn close(self: *CommandPalette) void {
        self.is_open = false;
        self.search_query.clearRetainingCapacity();
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Handle input for the command palette
    pub fn handleInput(self: *CommandPalette, key: phantom.Key) !bool {
        if (!self.is_open) return false;

        switch (key) {
            .escape => {
                self.close();
                return true;
            },
            .enter => {
                try self.executeSelectedCommand();
                self.close();
                return true;
            },
            .up => {
                if (self.selected_index > 0) {
                    self.selected_index -= 1;
                    self.adjustScroll();
                }
                return true;
            },
            .down => {
                const filtered = try self.getFilteredCommands();
                defer self.allocator.free(filtered);

                if (self.selected_index + 1 < filtered.len) {
                    self.selected_index += 1;
                    self.adjustScroll();
                }
                return true;
            },
            .backspace => {
                if (self.search_query.items.len > 0) {
                    _ = self.search_query.pop();
                    self.selected_index = 0;
                    self.scroll_offset = 0;
                }
                return true;
            },
            .char => |ch| {
                // Add character to search query
                const buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(ch, @constCast(&buf)) catch return true;
                try self.search_query.appendSlice(self.allocator, buf[0..len]);
                self.selected_index = 0;
                self.scroll_offset = 0;
                return true;
            },
            else => return true,
        }
    }

    /// Render the command palette
    pub fn render(self: *CommandPalette, buffer: anytype, term_width: u16, term_height: u16) !void {
        if (!self.is_open) return;

        // Palette dimensions (centered)
        const palette_width = @min(80, term_width - 4);
        const palette_height = @min(20, term_height - 4);
        const x = (term_width / 2) -| (palette_width / 2);
        const y = (term_height / 2) -| (palette_height / 2);

        // Draw background box
        try self.drawBox(buffer, x, y, palette_width, palette_height);

        // Draw title
        const title = " Command Palette ";
        const title_x = x + (palette_width / 2) -| @as(u16, @intCast(title.len / 2));
        const title_style = phantom.Style.default()
            .withFg(phantom.Color.bright_cyan)
            .withBold();

        for (title, 0..) |ch, i| {
            buffer.setCell(title_x + @as(u16, @intCast(i)), y, .{
                .char = ch,
                .style = title_style,
            });
        }

        // Draw search input box
        const search_y = y + 2;
        const search_prefix = "> ";
        const search_style = phantom.Style.default()
            .withFg(phantom.Color.bright_white);

        // Render search prefix
        for (search_prefix, 0..) |ch, i| {
            buffer.setCell(x + 2 + @as(u16, @intCast(i)), search_y, .{
                .char = ch,
                .style = search_style,
            });
        }

        // Render search query
        const query_x = x + 2 + @as(u16, @intCast(search_prefix.len));
        for (self.search_query.items, 0..) |ch, i| {
            if (query_x + @as(u16, @intCast(i)) < x + palette_width - 2) {
                buffer.setCell(query_x + @as(u16, @intCast(i)), search_y, .{
                    .char = ch,
                    .style = search_style,
                });
            }
        }

        // Draw cursor at end of search query
        const cursor_x = query_x + @as(u16, @intCast(self.search_query.items.len));
        if (cursor_x < x + palette_width - 2) {
            buffer.setCell(cursor_x, search_y, .{
                .char = '█',
                .style = phantom.Style.default().withFg(phantom.Color.bright_cyan),
            });
        }

        // Draw separator
        const sep_y = y + 3;
        var sep_x: u16 = x + 1;
        while (sep_x < x + palette_width - 1) : (sep_x += 1) {
            buffer.setCell(sep_x, sep_y, .{
                .char = '─',
                .style = phantom.Style.default().withFg(phantom.Color.bright_black),
            });
        }

        // Draw filtered commands
        const filtered = try self.getFilteredCommands();
        defer self.allocator.free(filtered);

        const list_y_start = y + 4;
        const list_height = palette_height - 5;

        if (filtered.len == 0) {
            // Show "No matches" message
            const no_matches = "No commands found";
            const no_matches_x = x + (palette_width / 2) -| @as(u16, @intCast(no_matches.len / 2));
            const no_matches_style = phantom.Style.default()
                .withFg(phantom.Color.bright_black);

            for (no_matches, 0..) |ch, i| {
                buffer.setCell(no_matches_x + @as(u16, @intCast(i)), list_y_start + 2, .{
                    .char = ch,
                    .style = no_matches_style,
                });
            }
        } else {
            // Render command list
            const visible_count = @min(list_height, filtered.len);

            for (0..visible_count) |i| {
                const cmd_idx = self.scroll_offset + i;
                if (cmd_idx >= filtered.len) break;

                const cmd = filtered[cmd_idx];
                const is_selected = (cmd_idx == self.selected_index);

                const item_y = list_y_start + @as(u16, @intCast(i));

                // Background for selected item
                if (is_selected) {
                    var bg_x: u16 = x + 1;
                    while (bg_x < x + palette_width - 1) : (bg_x += 1) {
                        buffer.setCell(bg_x, item_y, .{
                            .char = ' ',
                            .style = phantom.Style.default().withBg(phantom.Color.blue),
                        });
                    }
                }

                // Selection indicator
                const indicator = if (is_selected) "▶ " else "  ";
                const indicator_style = phantom.Style.default()
                    .withFg(if (is_selected) phantom.Color.bright_cyan else phantom.Color.bright_black)
                    .withBg(if (is_selected) phantom.Color.blue else phantom.Color.black);

                for (indicator, 0..) |ch, j| {
                    buffer.setCell(x + 2 + @as(u16, @intCast(j)), item_y, .{
                        .char = ch,
                        .style = indicator_style,
                    });
                }

                // Command name
                const name_x = x + 4;
                const name_style = phantom.Style.default()
                    .withFg(if (is_selected) phantom.Color.bright_white else phantom.Color.white)
                    .withBg(if (is_selected) phantom.Color.blue else phantom.Color.black);

                const max_name_len = @min(cmd.name.len, palette_width - 30);
                for (cmd.name[0..max_name_len], 0..) |ch, j| {
                    if (name_x + @as(u16, @intCast(j)) < x + palette_width - 2) {
                        buffer.setCell(name_x + @as(u16, @intCast(j)), item_y, .{
                            .char = ch,
                            .style = name_style,
                        });
                    }
                }

                // Keybinding (right-aligned)
                if (cmd.keybinding) |kb| {
                    const kb_x = x + palette_width - @as(u16, @intCast(kb.len)) - 3;
                    const kb_style = phantom.Style.default()
                        .withFg(phantom.Color.bright_black)
                        .withBg(if (is_selected) phantom.Color.blue else phantom.Color.black);

                    for (kb, 0..) |ch, j| {
                        buffer.setCell(kb_x + @as(u16, @intCast(j)), item_y, .{
                            .char = ch,
                            .style = kb_style,
                        });
                    }
                }
            }
        }

        // Draw status line at bottom
        const status_y = y + palette_height - 1;
        const status = if (filtered.len > 0)
            try std.fmt.allocPrint(self.allocator, " {d}/{d} commands ", .{ self.selected_index + 1, filtered.len })
        else
            try std.fmt.allocPrint(self.allocator, " 0 commands ", .{});
        defer self.allocator.free(status);

        const status_style = phantom.Style.default()
            .withFg(phantom.Color.bright_black);

        for (status, 0..) |ch, i| {
            if (x + 2 + @as(u16, @intCast(i)) < x + palette_width - 2) {
                buffer.setCell(x + 2 + @as(u16, @intCast(i)), status_y, .{
                    .char = ch,
                    .style = status_style,
                });
            }
        }
    }

    /// Draw a box with borders
    fn drawBox(self: *CommandPalette, buffer: anytype, x: u16, y: u16, width: u16, height: u16) !void {
        _ = self;

        const border_style = phantom.Style.default()
            .withFg(phantom.Color.bright_black);

        const bg_style = phantom.Style.default()
            .withBg(phantom.Color.black);

        // Draw background
        var row: u16 = y;
        while (row < y + height) : (row += 1) {
            var col: u16 = x;
            while (col < x + width) : (col += 1) {
                buffer.setCell(col, row, .{
                    .char = ' ',
                    .style = bg_style,
                });
            }
        }

        // Draw corners
        buffer.setCell(x, y, .{ .char = '╭', .style = border_style });
        buffer.setCell(x + width - 1, y, .{ .char = '╮', .style = border_style });
        buffer.setCell(x, y + height - 1, .{ .char = '╰', .style = border_style });
        buffer.setCell(x + width - 1, y + height - 1, .{ .char = '╯', .style = border_style });

        // Draw horizontal borders
        var col: u16 = x + 1;
        while (col < x + width - 1) : (col += 1) {
            buffer.setCell(col, y, .{ .char = '─', .style = border_style });
            buffer.setCell(col, y + height - 1, .{ .char = '─', .style = border_style });
        }

        // Draw vertical borders
        row = y + 1;
        while (row < y + height - 1) : (row += 1) {
            buffer.setCell(x, row, .{ .char = '│', .style = border_style });
            buffer.setCell(x + width - 1, row, .{ .char = '│', .style = border_style });
        }
    }

    /// Get filtered list of commands based on search query
    fn getFilteredCommands(self: *CommandPalette) ![]const *Command {
        var result = std.ArrayList(*Command){};
        defer result.deinit(self.allocator);

        if (self.search_query.items.len == 0) {
            // No filter - return all commands
            for (self.commands.items) |*cmd| {
                try result.append(self.allocator, cmd);
            }
        } else {
            // Simple case-insensitive substring match
            const query_lower = try std.ascii.allocLowerString(self.allocator, self.search_query.items);
            defer self.allocator.free(query_lower);

            for (self.commands.items) |*cmd| {
                const name_lower = try std.ascii.allocLowerString(self.allocator, cmd.name);
                defer self.allocator.free(name_lower);

                // Check if query is substring of command name
                if (std.mem.indexOf(u8, name_lower, query_lower) != null) {
                    try result.append(self.allocator, cmd);
                }
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Adjust scroll offset to keep selected item visible
    fn adjustScroll(self: *CommandPalette) void {
        const visible_items = 15; // palette_height - 5

        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + visible_items) {
            self.scroll_offset = self.selected_index - visible_items + 1;
        }
    }

    /// Execute the currently selected command
    fn executeSelectedCommand(self: *CommandPalette) !void {
        const filtered = try self.getFilteredCommands();
        defer self.allocator.free(filtered);

        if (filtered.len == 0 or self.selected_index >= filtered.len) {
            return;
        }

        const cmd = filtered[self.selected_index];

        // Execute callback with context
        if (self.context) |ctx| {
            try cmd.callback(ctx);
        }
    }
};

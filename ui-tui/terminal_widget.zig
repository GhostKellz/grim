//! Terminal widget for embedded terminal support
//! Integrates core.Terminal with Phantom TUI rendering

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const Terminal = core.Terminal;

pub const TerminalWidget = struct {
    allocator: std.mem.Allocator,
    terminal: *Terminal,
    scroll_offset: usize,
    is_focused: bool,

    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !*TerminalWidget {
        const self = try allocator.create(TerminalWidget);
        errdefer allocator.destroy(self);

        const terminal = try Terminal.init(allocator, rows, cols);
        errdefer terminal.deinit();

        self.* = .{
            .allocator = allocator,
            .terminal = terminal,
            .scroll_offset = 0,
            .is_focused = true,
        };

        return self;
    }

    pub fn deinit(self: *TerminalWidget) void {
        self.terminal.deinit();
        self.allocator.destroy(self);
    }

    /// Spawn shell or command in terminal
    pub fn spawn(self: *TerminalWidget, cmd: ?[]const u8) !void {
        try self.terminal.spawn(cmd);
    }

    /// Handle input key
    pub fn handleInput(self: *TerminalWidget, key: phantom.Key) !void {
        if (!self.terminal.running) return;

        // Convert Phantom key to terminal input
        var buf: [16]u8 = undefined;
        const input = try self.keyToTerminalInput(key, &buf);
        if (input.len > 0) {
            _ = try self.terminal.write(input);
        }
    }

    /// Render terminal to buffer
    pub fn render(self: *TerminalWidget, buffer: anytype, area: phantom.Rect) !void {
        // Poll for new data
        _ = try self.terminal.poll(0);

        // Get screen buffer from terminal
        if (self.terminal.screen) |screen| {
            try self.renderScreenBuffer(buffer, area, screen);
        } else {
            // Fallback: render raw scrollback
            try self.renderScrollback(buffer, area);
        }

        // Show exit message if terminal closed
        if (!self.terminal.running) {
            const msg = "Terminal closed. Press Enter to continue.";
            const msg_x = area.x + (area.width / 2) -| @as(u16, @intCast(msg.len / 2));
            const msg_y = area.y + area.height / 2;

            const style = phantom.Style.default()
                .withFg(phantom.Color.red)
                .withBg(phantom.Color.black)
                .withBold();

            for (msg, 0..) |ch, i| {
                if (msg_x + @as(u16, @intCast(i)) < area.x + area.width) {
                    buffer.setCell(msg_x + @as(u16, @intCast(i)), msg_y, .{
                        .char = ch,
                        .style = style,
                    });
                }
            }
        }
    }

    /// Render ANSI screen buffer
    fn renderScreenBuffer(self: *TerminalWidget, buffer: anytype, area: phantom.Rect, screen: *core.ansi.ScreenBuffer) !void {
        const rows = @min(area.height, screen.rows);
        const cols = @min(area.width, screen.cols);

        for (0..rows) |row| {
            for (0..cols) |col| {
                const cell = screen.getCell(@intCast(row), @intCast(col));

                // Convert ANSI cell to Phantom style
                var style = phantom.Style.default()
                    .withFg(ansiColorToPhantom(cell.fg))
                    .withBg(ansiColorToPhantom(cell.bg));

                // Conditionally apply attributes
                if (cell.attrs.bold) style = style.withBold();
                if (cell.attrs.italic) style = style.withItalic();
                if (cell.attrs.underline) style = style.withUnderline();

                buffer.setCell(
                    area.x + @as(u16, @intCast(col)),
                    area.y + @as(u16, @intCast(row)),
                    .{
                        .char = cell.char,
                        .style = style,
                    },
                );
            }
        }

        // Render cursor if focused
        if (self.is_focused and self.terminal.running) {
            const cursor_style = phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.white);

            if (screen.cursor_row < rows and screen.cursor_col < cols) {
                buffer.setCell(
                    area.x + @as(u16, @intCast(screen.cursor_col)),
                    area.y + @as(u16, @intCast(screen.cursor_row)),
                    .{
                        .char = ' ',
                        .style = cursor_style,
                    },
                );
            }
        }
    }

    /// Render raw scrollback (fallback)
    fn renderScrollback(self: *TerminalWidget, buffer: anytype, area: phantom.Rect) !void {
        const scrollback = self.terminal.getScrollback();

        var lines = std.ArrayList([]const u8){};
        defer lines.deinit(self.allocator);

        // Split scrollback into lines
        var iter = std.mem.splitScalar(u8, scrollback, '\n');
        while (iter.next()) |line| {
            try lines.append(self.allocator, line);
        }

        // Calculate visible lines with scroll offset
        const total_lines = lines.items.len;
        const visible_lines = @min(area.height, total_lines);
        const start_line = if (total_lines > area.height)
            total_lines - visible_lines - self.scroll_offset
        else
            0;

        // Render visible lines
        for (0..visible_lines) |i| {
            const line_idx = start_line + i;
            if (line_idx >= total_lines) break;

            const line = lines.items[line_idx];
            const y = area.y + @as(u16, @intCast(i));

            for (line, 0..) |ch, col| {
                if (col >= area.width) break;

                buffer.setCell(area.x + @as(u16, @intCast(col)), y, .{
                    .char = ch,
                    .style = phantom.Style.default(),
                });
            }
        }
    }

    /// Resize terminal
    pub fn resize(self: *TerminalWidget, rows: u16, cols: u16) !void {
        try self.terminal.resize(rows, cols);
    }

    /// Check if terminal is still running
    pub fn isRunning(self: *TerminalWidget) bool {
        return self.terminal.running;
    }

    /// Scroll up
    pub fn scrollUp(self: *TerminalWidget, amount: usize) void {
        self.scroll_offset +|= amount;
    }

    /// Scroll down
    pub fn scrollDown(self: *TerminalWidget, amount: usize) void {
        self.scroll_offset -|= amount;
    }

    // =========================================================================
    // Private helper functions
    // =========================================================================

    fn keyToTerminalInput(self: *TerminalWidget, key: phantom.Key, buf: []u8) ![]const u8 {
        _ = self;

        return switch (key) {
            .char => |ch| blk: {
                const len = std.unicode.utf8Encode(ch, buf) catch 0;
                break :blk buf[0..len];
            },
            .enter => "\r",
            .backspace => "\x7f",
            .tab => "\t",
            .escape => "\x1b",
            .up => "\x1b[A",
            .down => "\x1b[B",
            .right => "\x1b[C",
            .left => "\x1b[D",
            .home => "\x1b[H",
            .end => "\x1b[F",
            .page_up => "\x1b[5~",
            .page_down => "\x1b[6~",
            .delete => "\x1b[3~",
            .f1 => "\x1bOP",
            .f2 => "\x1bOQ",
            .f3 => "\x1bOR",
            .f4 => "\x1bOS",
            .f5 => "\x1b[15~",
            .f6 => "\x1b[17~",
            .f7 => "\x1b[18~",
            .f8 => "\x1b[19~",
            .f9 => "\x1b[20~",
            .f10 => "\x1b[21~",
            .f11 => "\x1b[23~",
            .f12 => "\x1b[24~",
            else => "",
        };
    }

    fn ansiColorToPhantom(color: core.ansi.Color) phantom.Color {
        // Map RGB color to closest Phantom color
        // Check for exact matches with standard colors first
        if (std.meta.eql(color, core.ansi.Color.black)) return phantom.Color.black;
        if (std.meta.eql(color, core.ansi.Color.red)) return phantom.Color.red;
        if (std.meta.eql(color, core.ansi.Color.green)) return phantom.Color.green;
        if (std.meta.eql(color, core.ansi.Color.yellow)) return phantom.Color.yellow;
        if (std.meta.eql(color, core.ansi.Color.blue)) return phantom.Color.blue;
        if (std.meta.eql(color, core.ansi.Color.magenta)) return phantom.Color.magenta;
        if (std.meta.eql(color, core.ansi.Color.cyan)) return phantom.Color.cyan;
        if (std.meta.eql(color, core.ansi.Color.white)) return phantom.Color.white;
        if (std.meta.eql(color, core.ansi.Color.bright_black)) return phantom.Color.bright_black;
        if (std.meta.eql(color, core.ansi.Color.bright_red)) return phantom.Color.bright_red;
        if (std.meta.eql(color, core.ansi.Color.bright_green)) return phantom.Color.bright_green;
        if (std.meta.eql(color, core.ansi.Color.bright_yellow)) return phantom.Color.bright_yellow;
        if (std.meta.eql(color, core.ansi.Color.bright_blue)) return phantom.Color.bright_blue;
        if (std.meta.eql(color, core.ansi.Color.bright_magenta)) return phantom.Color.bright_magenta;
        if (std.meta.eql(color, core.ansi.Color.bright_cyan)) return phantom.Color.bright_cyan;
        if (std.meta.eql(color, core.ansi.Color.bright_white)) return phantom.Color.bright_white;

        // Fallback to white for unmatched colors
        return phantom.Color.white;
    }
};

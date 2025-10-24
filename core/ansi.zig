//! ANSI Escape Sequence Parser
//! For terminal emulation - Sprint 12

const std = @import("std");

/// ANSI color
pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,

    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 205, .g = 49, .b = 49 };
    pub const green = Color{ .r = 13, .g = 188, .b = 121 };
    pub const yellow = Color{ .r = 229, .g = 181, .b = 103 };
    pub const blue = Color{ .r = 36, .g = 114, .b = 200 };
    pub const magenta = Color{ .r = 188, .g = 63, .b = 188 };
    pub const cyan = Color{ .r = 17, .g = 168, .b = 205 };
    pub const white = Color{ .r = 229, .g = 229, .b = 229 };
    pub const bright_black = Color{ .r = 102, .g = 102, .b = 102 };
    pub const bright_red = Color{ .r = 241, .g = 76, .b = 76 };
    pub const bright_green = Color{ .r = 35, .g = 209, .b = 139 };
    pub const bright_yellow = Color{ .r = 245, .g = 199, .b = 129 };
    pub const bright_blue = Color{ .r = 59, .g = 142, .b = 234 };
    pub const bright_magenta = Color{ .r = 214, .g = 112, .b = 214 };
    pub const bright_cyan = Color{ .r = 41, .g = 184, .b = 219 };
    pub const bright_white = Color{ .r = 255, .g = 255, .b = 255 };
};

/// Cell attributes
pub const CellAttrs = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    hidden: bool = false,
    strikethrough: bool = false,
};

/// Screen cell
pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = Color.white,
    bg: Color = Color.black,
    attrs: CellAttrs = .{},
};

/// Terminal screen buffer
pub const ScreenBuffer = struct {
    allocator: std.mem.Allocator,
    cells: []Cell,
    rows: usize,
    cols: usize,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    current_fg: Color = Color.white,
    current_bg: Color = Color.black,
    current_attrs: CellAttrs = .{},
    saved_cursor_row: usize = 0,
    saved_cursor_col: usize = 0,

    pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !*ScreenBuffer {
        const self = try allocator.create(ScreenBuffer);
        const cells = try allocator.alloc(Cell, rows * cols);

        // Initialize cells
        for (cells) |*cell| {
            cell.* = .{};
        }

        self.* = .{
            .allocator = allocator,
            .cells = cells,
            .rows = rows,
            .cols = cols,
        };

        return self;
    }

    pub fn deinit(self: *ScreenBuffer) void {
        self.allocator.free(self.cells);
        self.allocator.destroy(self);
    }

    /// Get cell at position
    pub fn getCell(self: *ScreenBuffer, row: usize, col: usize) *Cell {
        const idx = row * self.cols + col;
        return &self.cells[idx];
    }

    /// Write character at cursor
    pub fn writeChar(self: *ScreenBuffer, char: u21) void {
        if (self.cursor_row >= self.rows) return;
        if (self.cursor_col >= self.cols) return;

        const cell = self.getCell(self.cursor_row, self.cursor_col);
        cell.char = char;
        cell.fg = self.current_fg;
        cell.bg = self.current_bg;
        cell.attrs = self.current_attrs;

        self.cursor_col += 1;
        if (self.cursor_col >= self.cols) {
            self.cursor_col = 0;
            self.cursor_row += 1;
            if (self.cursor_row >= self.rows) {
                self.scrollUp();
            }
        }
    }

    /// Move cursor
    pub fn moveCursor(self: *ScreenBuffer, row: usize, col: usize) void {
        self.cursor_row = @min(row, self.rows - 1);
        self.cursor_col = @min(col, self.cols - 1);
    }

    /// Clear screen
    pub fn clear(self: *ScreenBuffer) void {
        for (self.cells) |*cell| {
            cell.* = .{};
        }
        self.cursor_row = 0;
        self.cursor_col = 0;
    }

    /// Scroll screen up by one line
    pub fn scrollUp(self: *ScreenBuffer) void {
        // Move lines up
        const line_size = self.cols;
        std.mem.copyForwards(
            Cell,
            self.cells[0 .. (self.rows - 1) * line_size],
            self.cells[line_size..],
        );

        // Clear bottom line
        const bottom_line = self.cells[(self.rows - 1) * line_size ..];
        for (bottom_line) |*cell| {
            cell.* = .{};
        }

        if (self.cursor_row > 0) {
            self.cursor_row -= 1;
        }
    }

    /// Save cursor position
    pub fn saveCursor(self: *ScreenBuffer) void {
        self.saved_cursor_row = self.cursor_row;
        self.saved_cursor_col = self.cursor_col;
    }

    /// Restore cursor position
    pub fn restoreCursor(self: *ScreenBuffer) void {
        self.cursor_row = self.saved_cursor_row;
        self.cursor_col = self.saved_cursor_col;
    }

    /// Erase from cursor to end of line
    pub fn eraseToEndOfLine(self: *ScreenBuffer) void {
        for (self.cursor_col..self.cols) |col| {
            const cell = self.getCell(self.cursor_row, col);
            cell.* = .{};
        }
    }

    /// Erase from cursor to end of screen
    pub fn eraseToEndOfScreen(self: *ScreenBuffer) void {
        self.eraseToEndOfLine();
        for ((self.cursor_row + 1)..self.rows) |row| {
            for (0..self.cols) |col| {
                const cell = self.getCell(row, col);
                cell.* = .{};
            }
        }
    }
};

/// ANSI escape sequence parser
pub const AnsiParser = struct {
    allocator: std.mem.Allocator,
    screen: *ScreenBuffer,
    state: ParserState = .normal,
    escape_buf: std.array_list.AlignedManaged(u8, null),
    params: std.array_list.AlignedManaged(i32, null),

    const ParserState = enum {
        normal,
        escape,
        csi,  // Control Sequence Introducer
        osc,  // Operating System Command
    };

    pub fn init(allocator: std.mem.Allocator, screen: *ScreenBuffer) !*AnsiParser {
        const self = try allocator.create(AnsiParser);
        self.* = .{
            .allocator = allocator,
            .screen = screen,
            .escape_buf = std.array_list.AlignedManaged(u8, null).init(allocator),
            .params = std.array_list.AlignedManaged(i32, null).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *AnsiParser) void {
        self.escape_buf.deinit();
        self.params.deinit();
        self.allocator.destroy(self);
    }

    /// Process input bytes
    pub fn process(self: *AnsiParser, input: []const u8) !void {
        for (input) |byte| {
            try self.processByte(byte);
        }
    }

    fn processByte(self: *AnsiParser, byte: u8) !void {
        switch (self.state) {
            .normal => {
                if (byte == 0x1B) { // ESC
                    self.state = .escape;
                    self.escape_buf.clearRetainingCapacity();
                } else if (byte == '\r') {
                    self.screen.cursor_col = 0;
                } else if (byte == '\n') {
                    self.screen.cursor_row += 1;
                    if (self.screen.cursor_row >= self.screen.rows) {
                        self.screen.scrollUp();
                    }
                } else if (byte == '\t') {
                    // Tab to next 8-column boundary
                    const next_tab = ((self.screen.cursor_col + 8) / 8) * 8;
                    self.screen.cursor_col = @min(next_tab, self.screen.cols - 1);
                } else if (byte == 0x08) { // Backspace
                    if (self.screen.cursor_col > 0) {
                        self.screen.cursor_col -= 1;
                    }
                } else if (byte >= 0x20) { // Printable character
                    self.screen.writeChar(byte);
                }
            },
            .escape => {
                if (byte == '[') {
                    self.state = .csi;
                    try self.escape_buf.append( byte);
                } else if (byte == ']') {
                    self.state = .osc;
                    try self.escape_buf.append( byte);
                } else {
                    // Simple escape sequence
                    try self.handleEscapeSequence(byte);
                    self.state = .normal;
                }
            },
            .csi => {
                try self.escape_buf.append( byte);
                // CSI sequences end with a letter (A-Z, a-z)
                if ((byte >= 'A' and byte <= 'Z') or (byte >= 'a' and byte <= 'z')) {
                    try self.handleCsiSequence();
                    self.state = .normal;
                }
            },
            .osc => {
                try self.escape_buf.append( byte);
                // OSC sequences end with BEL (0x07) or ST (ESC \)
                if (byte == 0x07) {
                    try self.handleOscSequence();
                    self.state = .normal;
                }
            },
        }
    }

    fn handleEscapeSequence(self: *AnsiParser, command: u8) !void {
        switch (command) {
            'c' => self.screen.clear(), // Reset
            '7' => self.screen.saveCursor(),
            '8' => self.screen.restoreCursor(),
            'M' => { // Reverse index (scroll down)
                if (self.screen.cursor_row > 0) {
                    self.screen.cursor_row -= 1;
                }
            },
            else => {}, // Ignore unknown
        }
    }

    fn handleCsiSequence(self: *AnsiParser) !void {
        const seq = self.escape_buf.items;
        if (seq.len < 2) return;

        // Parse parameters
        self.params.clearRetainingCapacity();
        var param_start: usize = 1; // Skip '['
        for (seq[1..], 1..) |byte, i| {
            if (byte == ';' or !std.ascii.isDigit(byte)) {
                if (i > param_start) {
                    const param_str = seq[param_start..i];
                    const param = std.fmt.parseInt(i32, param_str, 10) catch 0;
                    try self.params.append( param);
                }
                if (byte == ';') {
                    param_start = i + 1;
                }
            }
        }

        const command = seq[seq.len - 1];

        switch (command) {
            'A' => { // Cursor up
                const n = if (self.params.items.len > 0) @as(usize, @intCast(@max(1, self.params.items[0]))) else 1;
                if (self.screen.cursor_row >= n) {
                    self.screen.cursor_row -= n;
                } else {
                    self.screen.cursor_row = 0;
                }
            },
            'B' => { // Cursor down
                const n = if (self.params.items.len > 0) @as(usize, @intCast(@max(1, self.params.items[0]))) else 1;
                self.screen.cursor_row = @min(self.screen.cursor_row + n, self.screen.rows - 1);
            },
            'C' => { // Cursor forward
                const n = if (self.params.items.len > 0) @as(usize, @intCast(@max(1, self.params.items[0]))) else 1;
                self.screen.cursor_col = @min(self.screen.cursor_col + n, self.screen.cols - 1);
            },
            'D' => { // Cursor back
                const n = if (self.params.items.len > 0) @as(usize, @intCast(@max(1, self.params.items[0]))) else 1;
                if (self.screen.cursor_col >= n) {
                    self.screen.cursor_col -= n;
                } else {
                    self.screen.cursor_col = 0;
                }
            },
            'H', 'f' => { // Cursor position
                const row = if (self.params.items.len > 0) @as(usize, @intCast(@max(1, self.params.items[0]))) - 1 else 0;
                const col = if (self.params.items.len > 1) @as(usize, @intCast(@max(1, self.params.items[1]))) - 1 else 0;
                self.screen.moveCursor(row, col);
            },
            'J' => { // Erase display
                const mode = if (self.params.items.len > 0) self.params.items[0] else 0;
                if (mode == 2) {
                    self.screen.clear();
                } else if (mode == 0) {
                    self.screen.eraseToEndOfScreen();
                }
            },
            'K' => { // Erase line
                self.screen.eraseToEndOfLine();
            },
            'm' => { // SGR - Select Graphic Rendition
                try self.handleSgr();
            },
            else => {}, // Ignore unknown
        }
    }

    fn handleSgr(self: *AnsiParser) !void {
        if (self.params.items.len == 0) {
            // Reset
            self.screen.current_fg = Color.white;
            self.screen.current_bg = Color.black;
            self.screen.current_attrs = .{};
            return;
        }

        for (self.params.items) |param| {
            switch (param) {
                0 => { // Reset
                    self.screen.current_fg = Color.white;
                    self.screen.current_bg = Color.black;
                    self.screen.current_attrs = .{};
                },
                1 => self.screen.current_attrs.bold = true,
                2 => self.screen.current_attrs.dim = true,
                3 => self.screen.current_attrs.italic = true,
                4 => self.screen.current_attrs.underline = true,
                5 => self.screen.current_attrs.blink = true,
                7 => self.screen.current_attrs.reverse = true,
                8 => self.screen.current_attrs.hidden = true,
                9 => self.screen.current_attrs.strikethrough = true,
                22 => {
                    self.screen.current_attrs.bold = false;
                    self.screen.current_attrs.dim = false;
                },
                23 => self.screen.current_attrs.italic = false,
                24 => self.screen.current_attrs.underline = false,
                25 => self.screen.current_attrs.blink = false,
                27 => self.screen.current_attrs.reverse = false,
                28 => self.screen.current_attrs.hidden = false,
                29 => self.screen.current_attrs.strikethrough = false,
                // Foreground colors
                30 => self.screen.current_fg = Color.black,
                31 => self.screen.current_fg = Color.red,
                32 => self.screen.current_fg = Color.green,
                33 => self.screen.current_fg = Color.yellow,
                34 => self.screen.current_fg = Color.blue,
                35 => self.screen.current_fg = Color.magenta,
                36 => self.screen.current_fg = Color.cyan,
                37 => self.screen.current_fg = Color.white,
                39 => self.screen.current_fg = Color.white, // Default
                // Background colors
                40 => self.screen.current_bg = Color.black,
                41 => self.screen.current_bg = Color.red,
                42 => self.screen.current_bg = Color.green,
                43 => self.screen.current_bg = Color.yellow,
                44 => self.screen.current_bg = Color.blue,
                45 => self.screen.current_bg = Color.magenta,
                46 => self.screen.current_bg = Color.cyan,
                47 => self.screen.current_bg = Color.white,
                49 => self.screen.current_bg = Color.black, // Default
                // Bright colors
                90 => self.screen.current_fg = Color.bright_black,
                91 => self.screen.current_fg = Color.bright_red,
                92 => self.screen.current_fg = Color.bright_green,
                93 => self.screen.current_fg = Color.bright_yellow,
                94 => self.screen.current_fg = Color.bright_blue,
                95 => self.screen.current_fg = Color.bright_magenta,
                96 => self.screen.current_fg = Color.bright_cyan,
                97 => self.screen.current_fg = Color.bright_white,
                else => {},
            }
        }
    }

    fn handleOscSequence(self: *AnsiParser) !void {
        // OSC sequences (window title, etc.)
        // Format: ESC ] Ps ; Pt BEL
        _ = self;
        // TODO: Implement if needed
    }
};

test "screen buffer" {
    const allocator = std.testing.allocator;
    const screen = try ScreenBuffer.init(allocator, 24, 80);
    defer screen.deinit();

    screen.writeChar('H');
    screen.writeChar('i');

    try std.testing.expect(screen.getCell(0, 0).char == 'H');
    try std.testing.expect(screen.getCell(0, 1).char == 'i');
}

test "ansi parser" {
    const allocator = std.testing.allocator;
    const screen = try ScreenBuffer.init(allocator, 24, 80);
    defer screen.deinit();

    const parser = try AnsiParser.init(allocator, screen);
    defer parser.deinit();

    try parser.process("Hello\x1B[31mRed\x1B[0m");

    try std.testing.expect(screen.getCell(0, 5).char == 'R');
    try std.testing.expect(screen.getCell(0, 5).fg.r == Color.red.r);
}

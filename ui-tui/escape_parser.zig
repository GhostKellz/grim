// Escape sequence parser for terminal input
// Converts ANSI/VT100 sequences to Phantom Key events

const std = @import("std");
const phantom = @import("phantom");

/// Parse result from escape sequence parsing
pub const ParseResult = union(enum) {
    key: phantom.Key,
    incomplete, // Need more bytes
    invalid, // Invalid sequence

    pub fn isKey(self: ParseResult) bool {
        return switch (self) {
            .key => true,
            else => false,
        };
    }
};

/// Escape sequence parser state machine
pub const EscapeParser = struct {
    buffer: []const u8,
    pos: usize = 0,

    pub fn init(buffer: []const u8) EscapeParser {
        return .{ .buffer = buffer };
    }

    /// Parse the next key event from the buffer
    pub fn next(self: *EscapeParser) ?phantom.Key {
        if (self.pos >= self.buffer.len) return null;

        const result = self.parseOne();
        return switch (result) {
            .key => |k| k,
            .incomplete, .invalid => null,
        };
    }

    /// Parse a single key/sequence from current position
    fn parseOne(self: *EscapeParser) ParseResult {
        if (self.pos >= self.buffer.len) return .incomplete;

        const first_byte = self.buffer[self.pos];

        // Handle escape sequences
        if (first_byte == 0x1b) { // ESC
            return self.parseEscape();
        }

        // Handle control characters
        if (first_byte < 32) {
            return self.parseControl(first_byte);
        }

        // Handle Del (0x7F)
        if (first_byte == 0x7F) {
            self.pos += 1;
            return .{ .key = .backspace };
        }

        // Regular printable character
        self.pos += 1;
        return .{ .key = .{ .char = first_byte } };
    }

    /// Parse escape sequences (ESC + ...)
    fn parseEscape(self: *EscapeParser) ParseResult {
        if (self.pos + 1 >= self.buffer.len) {
            // Just ESC alone
            self.pos += 1;
            return .{ .key = .escape };
        }

        const second_byte = self.buffer[self.pos + 1];

        // ESC [ ... (CSI sequences)
        if (second_byte == '[') {
            return self.parseCSI();
        }

        // ESC O ... (SS3 sequences - function keys)
        if (second_byte == 'O') {
            return self.parseSS3();
        }

        // Alt+key combinations - Phantom doesn't have .alt, so treat as separate ESC + char
        // User code should handle this pattern if needed

        // Unknown sequence, treat as ESC alone
        self.pos += 1;
        return .{ .key = .escape };
    }

    /// Parse CSI sequences (ESC [ ...)
    fn parseCSI(self: *EscapeParser) ParseResult {
        // ESC [ already confirmed
        var pos = self.pos + 2;

        // Collect parameters
        var params: [4]u16 = undefined;
        var param_count: usize = 0;
        var current_param: u16 = 0;
        var has_param = false;

        while (pos < self.buffer.len) : (pos += 1) {
            const byte = self.buffer[pos];

            if (byte >= '0' and byte <= '9') {
                current_param = current_param * 10 + (byte - '0');
                has_param = true;
            } else if (byte == ';') {
                if (param_count < params.len) {
                    params[param_count] = current_param;
                    param_count += 1;
                }
                current_param = 0;
                has_param = false;
            } else if (byte >= '@' and byte <= '~') {
                // Final byte
                if (has_param and param_count < params.len) {
                    params[param_count] = current_param;
                    param_count += 1;
                }

                self.pos = pos + 1;
                return self.interpretCSI(byte, params[0..param_count]);
            } else {
                // Invalid sequence
                self.pos = pos;
                return .invalid;
            }
        }

        // Incomplete sequence
        return .incomplete;
    }

    /// Interpret CSI sequence based on final byte and parameters
    fn interpretCSI(self: *EscapeParser, final_byte: u8, params: []const u16) ParseResult {
        _ = self;

        return switch (final_byte) {
            'A' => .{ .key = .up },
            'B' => .{ .key = .down },
            'C' => .{ .key = .right },
            'D' => .{ .key = .left },
            'H' => .{ .key = .home },
            'F' => .{ .key = .end },
            '~' => blk: {
                if (params.len == 0) break :blk .invalid;
                break :blk switch (params[0]) {
                    1 => .{ .key = .home },
                    2 => .{ .key = .insert },
                    3 => .{ .key = .delete },
                    4 => .{ .key = .end },
                    5 => .{ .key = .page_up },
                    6 => .{ .key = .page_down },
                    11 => .{ .key = .f1 },
                    12 => .{ .key = .f2 },
                    13 => .{ .key = .f3 },
                    14 => .{ .key = .f4 },
                    15 => .{ .key = .f5 },
                    17 => .{ .key = .f6 },
                    18 => .{ .key = .f7 },
                    19 => .{ .key = .f8 },
                    20 => .{ .key = .f9 },
                    21 => .{ .key = .f10 },
                    23 => .{ .key = .f11 },
                    24 => .{ .key = .f12 },
                    else => .invalid,
                };
            },
            else => .invalid,
        };
    }

    /// Parse SS3 sequences (ESC O ...)
    fn parseSS3(self: *EscapeParser) ParseResult {
        if (self.pos + 2 >= self.buffer.len) return .incomplete;

        const third_byte = self.buffer[self.pos + 2];
        self.pos += 3;

        return switch (third_byte) {
            'P' => .{ .key = .f1 },
            'Q' => .{ .key = .f2 },
            'R' => .{ .key = .f3 },
            'S' => .{ .key = .f4 },
            'H' => .{ .key = .home },
            'F' => .{ .key = .end },
            else => .invalid,
        };
    }

    /// Parse control characters (Ctrl+key)
    fn parseControl(self: *EscapeParser, byte: u8) ParseResult {
        self.pos += 1;

        return switch (byte) {
            0x01 => .{ .key = .ctrl_a },
            0x02 => .{ .key = .ctrl_b },
            0x03 => .{ .key = .ctrl_c },
            0x04 => .{ .key = .ctrl_d },
            0x05 => .{ .key = .ctrl_e },
            0x06 => .{ .key = .ctrl_f },
            0x07 => .{ .key = .ctrl_g },
            0x08 => .{ .key = .ctrl_h },
            0x09 => .{ .key = .tab }, // Ctrl+I is Tab
            0x0A => .{ .key = .ctrl_j },
            0x0B => .{ .key = .ctrl_k },
            0x0C => .{ .key = .ctrl_l },
            0x0D => .{ .key = .enter }, // Ctrl+M is Enter
            0x0E => .{ .key = .ctrl_n },
            0x0F => .{ .key = .ctrl_o },
            0x10 => .{ .key = .ctrl_p },
            0x11 => .{ .key = .ctrl_q },
            0x12 => .{ .key = .ctrl_r },
            0x13 => .{ .key = .ctrl_s },
            0x14 => .{ .key = .ctrl_t },
            0x15 => .{ .key = .ctrl_u },
            0x16 => .{ .key = .ctrl_v },
            0x17 => .{ .key = .ctrl_w },
            0x18 => .{ .key = .ctrl_x },
            0x19 => .{ .key = .ctrl_y },
            0x1A => .{ .key = .ctrl_z },
            0x1B => .{ .key = .escape }, // ESC
            '\r', '\n' => .{ .key = .enter },
            '\t' => .{ .key = .tab },
            else => .invalid,
        };
    }
};

test "parse regular characters" {
    var parser = EscapeParser.init("abc");

    try std.testing.expectEqual(phantom.Key{ .char = 'a' }, parser.next().?);
    try std.testing.expectEqual(phantom.Key{ .char = 'b' }, parser.next().?);
    try std.testing.expectEqual(phantom.Key{ .char = 'c' }, parser.next().?);
    try std.testing.expectEqual(@as(?phantom.Key, null), parser.next());
}

test "parse arrow keys" {
    var parser = EscapeParser.init("\x1b[A\x1b[B\x1b[C\x1b[D");

    try std.testing.expectEqual(phantom.Key.up, parser.next().?);
    try std.testing.expectEqual(phantom.Key.down, parser.next().?);
    try std.testing.expectEqual(phantom.Key.right, parser.next().?);
    try std.testing.expectEqual(phantom.Key.left, parser.next().?);
}

test "parse control characters" {
    var parser = EscapeParser.init("\x01\x03\x0e\x11"); // Ctrl+A, Ctrl+C, Ctrl+N, Ctrl+Q

    try std.testing.expectEqual(phantom.Key.ctrl_a, parser.next().?);
    try std.testing.expectEqual(phantom.Key.ctrl_c, parser.next().?);
    try std.testing.expectEqual(phantom.Key.ctrl_n, parser.next().?);
    try std.testing.expectEqual(phantom.Key.ctrl_q, parser.next().?);
}

test "parse escape key" {
    var parser = EscapeParser.init("\x1b");
    try std.testing.expectEqual(phantom.Key.escape, parser.next().?);
}

test "parse enter and tab" {
    var parser = EscapeParser.init("\r\n\t");
    try std.testing.expectEqual(phantom.Key.enter, parser.next().?);
    try std.testing.expectEqual(phantom.Key.enter, parser.next().?);
    try std.testing.expectEqual(phantom.Key.tab, parser.next().?);
}

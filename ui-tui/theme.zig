const std = @import("std");
const syntax = @import("syntax");

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Convert to ANSI 256-color code (approximation)
    pub fn toAnsi256(self: Color) u8 {
        // Convert RGB to 256-color palette
        // Using 6x6x6 color cube (colors 16-231)
        const r: u8 = @min(5, (@as(u16, self.r) * 6) / 256);
        const g: u8 = @min(5, (@as(u16, self.g) * 6) / 256);
        const b: u8 = @min(5, (@as(u16, self.b) * 6) / 256);
        return 16 + (36 * r) + (6 * g) + b;
    }

    /// Get ANSI escape sequence for foreground color
    pub fn toFgSequence(self: Color, buf: []u8) ![]const u8 {
        const code = self.toAnsi256();
        return try std.fmt.bufPrint(buf, "\x1B[38;5;{d}m", .{code});
    }

    /// Get ANSI escape sequence for background color
    pub fn toBgSequence(self: Color, buf: []u8) ![]const u8 {
        const code = self.toAnsi256();
        return try std.fmt.bufPrint(buf, "\x1B[48;5;{d}m", .{code});
    }
};

/// Editor theme with syntax highlighting colors
pub const Theme = struct {
    // Syntax colors
    keyword: Color,
    string_literal: Color,
    number_literal: Color,
    comment: Color,
    function_name: Color,
    type_name: Color,
    variable: Color,
    operator: Color,
    punctuation: Color,
    error_bg: Color,
    error_fg: Color,

    // UI colors
    background: Color,
    foreground: Color,
    cursor: Color,
    selection: Color,
    line_number: Color,
    status_bar_bg: Color,
    status_bar_fg: Color,

    /// Get ANSI sequence for a highlight type
    pub fn getHighlightSequence(self: *const Theme, highlight_type: syntax.HighlightType, buf: []u8) ![]const u8 {
        const color = switch (highlight_type) {
            .keyword => self.keyword,
            .string_literal => self.string_literal,
            .number_literal => self.number_literal,
            .comment => self.comment,
            .function_name => self.function_name,
            .type_name => self.type_name,
            .variable => self.variable,
            .operator => self.operator,
            .punctuation => self.punctuation,
            .@"error" => return try std.fmt.bufPrint(buf, "\x1B[48;5;{d};38;5;{d}m", .{
                self.error_bg.toAnsi256(),
                self.error_fg.toAnsi256(),
            }),
            .none => return "",
        };
        return try color.toFgSequence(buf);
    }

    /// Default dark theme (current Grim colors)
    pub fn defaultDark() Theme {
        return .{
            // Syntax (matching current HighlightPalette)
            .keyword = .{ .r = 255, .g = 0, .b = 135 }, // Pink/Magenta
            .string_literal = .{ .r = 135, .g = 215, .b = 95 }, // Green
            .number_literal = .{ .r = 255, .g = 135, .b = 0 }, // Orange
            .comment = .{ .r = 135, .g = 135, .b = 135 }, // Gray
            .function_name = .{ .r = 95, .g = 215, .b = 255 }, // Cyan
            .type_name = .{ .r = 175, .g = 95, .b = 215 }, // Purple
            .variable = .{ .r = 215, .g = 215, .b = 215 }, // Light gray
            .operator = .{ .r = 215, .g = 135, .b = 95 }, // Brown
            .punctuation = .{ .r = 135, .g = 135, .b = 135 }, // Gray
            .error_bg = .{ .r = 95, .g = 0, .b = 0 }, // Dark red
            .error_fg = .{ .r = 255, .g = 255, .b = 255 }, // White

            // UI
            .background = .{ .r = 0, .g = 0, .b = 0 },
            .foreground = .{ .r = 215, .g = 215, .b = 215 },
            .cursor = .{ .r = 255, .g = 255, .b = 255 },
            .selection = .{ .r = 60, .g = 60, .b = 60 },
            .line_number = .{ .r = 100, .g = 100, .b = 100 },
            .status_bar_bg = .{ .r = 40, .g = 40, .b = 40 },
            .status_bar_fg = .{ .r = 200, .g = 200, .b = 200 },
        };
    }

    /// Light theme alternative
    pub fn defaultLight() Theme {
        return .{
            // Syntax
            .keyword = .{ .r = 175, .g = 0, .b = 95 },
            .string_literal = .{ .r = 0, .g = 135, .b = 0 },
            .number_literal = .{ .r = 175, .g = 95, .b = 0 },
            .comment = .{ .r = 95, .g = 95, .b = 95 },
            .function_name = .{ .r = 0, .g = 95, .b = 175 },
            .type_name = .{ .r = 95, .g = 0, .b = 135 },
            .variable = .{ .r = 60, .g = 60, .b = 60 },
            .operator = .{ .r = 135, .g = 95, .b = 0 },
            .punctuation = .{ .r = 80, .g = 80, .b = 80 },
            .error_bg = .{ .r = 255, .g = 200, .b = 200 },
            .error_fg = .{ .r = 135, .g = 0, .b = 0 },

            // UI
            .background = .{ .r = 255, .g = 255, .b = 255 },
            .foreground = .{ .r = 40, .g = 40, .b = 40 },
            .cursor = .{ .r = 0, .g = 0, .b = 0 },
            .selection = .{ .r = 200, .g = 220, .b = 255 },
            .line_number = .{ .r = 150, .g = 150, .b = 150 },
            .status_bar_bg = .{ .r = 220, .g = 220, .b = 220 },
            .status_bar_fg = .{ .r = 60, .g = 60, .b = 60 },
        };
    }

    /// Load theme from TOML config file
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Theme {
        _ = allocator;
        _ = path;
        // TODO: Implement TOML parsing
        // For now, return default theme
        return defaultDark();
    }
};

test "theme color conversion" {
    const theme = Theme.defaultDark();

    var buf: [32]u8 = undefined;
    const seq = try theme.keyword.toFgSequence(&buf);

    // Should produce valid ANSI escape sequence
    try std.testing.expect(seq.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, seq, "\x1B[38;5;"));
}

test "theme get highlight sequence" {
    const theme = Theme.defaultDark();

    var buf: [32]u8 = undefined;
    const seq = try theme.getHighlightSequence(.keyword, &buf);

    try std.testing.expect(seq.len > 0);
}

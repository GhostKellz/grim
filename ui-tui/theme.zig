const std = @import("std");
const syntax = @import("syntax");

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Parse hex color string "#RRGGBB" or "RRGGBB"
    pub fn fromHex(hex: []const u8) !Color {
        const start: usize = if (hex.len > 0 and hex[0] == '#') 1 else 0;
        if (hex.len - start != 6) return error.InvalidHexColor;

        const r = try std.fmt.parseInt(u8, hex[start..][0..2], 16);
        const g = try std.fmt.parseInt(u8, hex[start..][2..4], 16);
        const b = try std.fmt.parseInt(u8, hex[start..][4..6], 16);

        return Color{ .r = r, .g = g, .b = b };
    }

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
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const content = try allocator.alloc(u8, file_size);
        defer allocator.free(content);

        _ = try file.readAll(content);

        return try parseToml(allocator, content);
    }

    /// Load ghost-hacker-blue theme as default
    pub fn loadDefault(allocator: std.mem.Allocator) !Theme {
        // Try to load ghost-hacker-blue.toml, fallback to built-in
        const paths = [_][]const u8{
            "themes/ghost-hacker-blue.toml",
            "/usr/share/grim/themes/ghost-hacker-blue.toml",
            "/usr/local/share/grim/themes/ghost-hacker-blue.toml",
        };

        for (paths) |path| {
            if (loadFromFile(allocator, path)) |theme| {
                return theme;
            } else |_| {
                continue;
            }
        }

        // Fallback to built-in ghost-hacker-blue colors
        return ghostHackerBlue();
    }

    /// Built-in Ghost Hacker Blue theme (fallback)
    fn ghostHackerBlue() Theme {
        return .{
            // Syntax - Ghost Hacker Blue colors
            .keyword = Color.fromHex("89ddff") catch unreachable, // cyan (blue5)
            .string_literal = Color.fromHex("c3e88d") catch unreachable, // green
            .number_literal = Color.fromHex("ffc777") catch unreachable, // yellow
            .comment = Color.fromHex("57c7ff") catch unreachable, // hacker blue
            .function_name = Color.fromHex("8aff80") catch unreachable, // mint green
            .type_name = Color.fromHex("65bcff") catch unreachable, // blue1
            .variable = Color.fromHex("c8d3f5") catch unreachable, // fg
            .operator = Color.fromHex("c0caf5") catch unreachable, // blue_moon
            .punctuation = Color.fromHex("c8d3f5") catch unreachable, // fg
            .error_bg = Color.fromHex("c53b53") catch unreachable, // error
            .error_fg = Color.fromHex("c8d3f5") catch unreachable, // fg

            // UI - Ghost Hacker Blue aesthetic
            .background = Color.fromHex("222436") catch unreachable, // bg
            .foreground = Color.fromHex("8aff80") catch unreachable, // mint
            .cursor = Color.fromHex("8aff80") catch unreachable, // mint
            .selection = Color.fromHex("a0ffe8") catch unreachable, // aqua_ice
            .line_number = Color.fromHex("636da6") catch unreachable, // comment
            .status_bar_bg = Color.fromHex("1e2030") catch unreachable, // bg_dark
            .status_bar_fg = Color.fromHex("c0caf5") catch unreachable, // blue_moon
        };
    }

    /// Parse TOML theme file
    fn parseToml(allocator: std.mem.Allocator, content: []const u8) !Theme {
        var palette = std.StringHashMap([]const u8).init(allocator);
        defer palette.deinit();

        var syntax_map = std.StringHashMap([]const u8).init(allocator);
        defer syntax_map.deinit();

        var ui_map = std.StringHashMap([]const u8).init(allocator);
        defer ui_map.deinit();

        // Parse TOML content
        var lines = std.mem.tokenizeScalar(u8, content, '\n');
        var current_section: []const u8 = "";

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Section header
            if (trimmed[0] == '[') {
                const end = std.mem.indexOfScalar(u8, trimmed, ']') orelse continue;
                current_section = trimmed[1..end];
                continue;
            }

            // Key-value pair
            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            // Remove quotes from value
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            // Store in appropriate map
            if (std.mem.eql(u8, current_section, "palette") or
                std.mem.startsWith(u8, current_section, "palette."))
            {
                try palette.put(key, value);
            } else if (std.mem.eql(u8, current_section, "syntax")) {
                try syntax_map.put(key, value);
            } else if (std.mem.eql(u8, current_section, "ui")) {
                try ui_map.put(key, value);
            }
        }

        // Helper to resolve color (hex or palette reference)
        const ResolveContext = struct {
            pal: *const std.StringHashMap([]const u8),

            fn resolve(self: @This(), value: []const u8) !Color {
                // Direct hex color
                if (value.len > 0 and value[0] == '#') {
                    return try Color.fromHex(value);
                }

                // Palette reference - resolve recursively
                if (self.pal.get(value)) |hex| {
                    return try self.resolve(hex);
                }

                // Fallback to parsing as hex without #
                return Color.fromHex(value) catch Color{ .r = 128, .g = 128, .b = 128 };
            }
        };

        const resolver = ResolveContext{ .pal = &palette };

        // Build theme from maps
        return Theme{
            // Syntax colors
            .keyword = try resolveWithFallback(resolver, syntax_map, "keyword", "89ddff"),
            .string_literal = try resolveWithFallback(resolver, syntax_map, "string", "c3e88d"),
            .number_literal = try resolveWithFallback(resolver, syntax_map, "number", "ffc777"),
            .comment = try resolveWithFallback(resolver, syntax_map, "comment", "636da6"),
            .function_name = try resolveWithFallback(resolver, syntax_map, "function", "82aaff"),
            .type_name = try resolveWithFallback(resolver, syntax_map, "type", "65bcff"),
            .variable = try resolveWithFallback(resolver, syntax_map, "variable", "c8d3f5"),
            .operator = try resolveWithFallback(resolver, syntax_map, "operator", "86e1fc"),
            .punctuation = try resolveWithFallback(resolver, syntax_map, "punctuation", "c8d3f5"),
            .error_bg = try resolveWithFallback(resolver, syntax_map, "error_token", "c53b53"),
            .error_fg = try resolveWithFallback(resolver, ui_map, "foreground", "c8d3f5"),

            // UI colors
            .background = try resolveWithFallback(resolver, ui_map, "background", "222436"),
            .foreground = try resolveWithFallback(resolver, ui_map, "foreground", "c8d3f5"),
            .cursor = try resolveWithFallback(resolver, ui_map, "cursor", "c8d3f5"),
            .selection = try resolveWithFallback(resolver, ui_map, "selection", "2d3f76"),
            .line_number = try resolveWithFallback(resolver, ui_map, "line_number", "3b4261"),
            .status_bar_bg = try resolveWithFallback(resolver, ui_map, "background_alt", "1e2030"),
            .status_bar_fg = try resolveWithFallback(resolver, ui_map, "status_line", "828bb8"),
        };
    }
};

/// Helper to resolve color with fallback
fn resolveWithFallback(
    resolver: anytype,
    map: std.StringHashMap([]const u8),
    key: []const u8,
    fallback: []const u8,
) !Color {
    const value = map.get(key) orelse fallback;
    return try resolver.resolve(value);
}

test "color from hex" {
    const color = try Color.fromHex("#8aff80");
    try std.testing.expectEqual(@as(u8, 0x8a), color.r);
    try std.testing.expectEqual(@as(u8, 0xff), color.g);
    try std.testing.expectEqual(@as(u8, 0x80), color.b);

    // Without # prefix
    const color2 = try Color.fromHex("c0caf5");
    try std.testing.expectEqual(@as(u8, 0xc0), color2.r);
    try std.testing.expectEqual(@as(u8, 0xca), color2.g);
    try std.testing.expectEqual(@as(u8, 0xf5), color2.b);
}

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

test "ghost hacker blue theme" {
    const theme = Theme.ghostHackerBlue();

    // Verify signature colors
    try std.testing.expectEqual(@as(u8, 0x8a), theme.function_name.r); // mint green
    try std.testing.expectEqual(@as(u8, 0xff), theme.function_name.g);
    try std.testing.expectEqual(@as(u8, 0x80), theme.function_name.b);

    try std.testing.expectEqual(@as(u8, 0x57), theme.comment.r); // hacker blue
    try std.testing.expectEqual(@as(u8, 0xc7), theme.comment.g);
    try std.testing.expectEqual(@as(u8, 0xff), theme.comment.b);
}

test "toml parser basic" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[palette]
        \\mint = "#8aff80"
        \\blue_hacker = "#57c7ff"
        \\
        \\[syntax]
        \\function = "mint"
        \\comment = "blue_hacker"
        \\
        \\[ui]
        \\foreground = "mint"
    ;

    const theme = try Theme.parseToml(allocator, toml_content);

    // Verify mint green function color
    try std.testing.expectEqual(@as(u8, 0x8a), theme.function_name.r);
    try std.testing.expectEqual(@as(u8, 0xff), theme.function_name.g);
    try std.testing.expectEqual(@as(u8, 0x80), theme.function_name.b);

    // Verify hacker blue comment color
    try std.testing.expectEqual(@as(u8, 0x57), theme.comment.r);
    try std.testing.expectEqual(@as(u8, 0xc7), theme.comment.g);
    try std.testing.expectEqual(@as(u8, 0xff), theme.comment.b);

    // Verify mint foreground
    try std.testing.expectEqual(@as(u8, 0x8a), theme.foreground.r);
}

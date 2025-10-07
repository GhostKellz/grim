const std = @import("std");
const json = std.json;
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

    /// Get the default theme
    pub fn getDefault() Theme {
        return defaultDark();
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

    /// Get theme by name
    pub fn get(name: []const u8) !Theme {
        if (std.mem.eql(u8, name, "ghost-hacker-blue")) {
            return ghostHackerBlue();
        } else if (std.mem.eql(u8, name, "default-dark")) {
            return defaultDark();
        } else if (std.mem.eql(u8, name, "default-light")) {
            return defaultLight();
        } else {
            return error.ThemeNotFound;
        }
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

const ThemeRegistryError = error{
    InvalidThemeJson,
    InvalidThemeName,
    InvalidPluginId,
    KeyTooLong,
};

const ParseThemeError = ThemeRegistryError || error{ InvalidHexColor, InvalidCharacter, Overflow, OutOfMemory };

pub const ThemeRegistry = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    plugin_themes: std.StringHashMap(Theme),

    pub fn init(allocator: std.mem.Allocator) ThemeRegistry {
        return .{
            .allocator = allocator,
            .plugin_themes = std.StringHashMap(Theme).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.plugin_themes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.plugin_themes.deinit();
    }

    pub fn registerPluginTheme(
        self: *Self,
        plugin_id: []const u8,
        theme_name: []const u8,
        colors_json: []const u8,
    ) ParseThemeError!void {
        if (plugin_id.len == 0) return ThemeRegistryError.InvalidPluginId;
        if (theme_name.len == 0) return ThemeRegistryError.InvalidThemeName;

        var parsed = json.parseFromSlice(json.Value, self.allocator, colors_json, .{}) catch {
            std.log.err("Failed to parse theme JSON from plugin {s}: invalid JSON", .{plugin_id});
            return ThemeRegistryError.InvalidThemeJson;
        };
        defer parsed.deinit();

        if (parsed.value != .object) {
            std.log.err("Theme registration for plugin {s} must provide a JSON object", .{plugin_id});
            return ThemeRegistryError.InvalidThemeJson;
        }

        var theme = Theme.defaultDark();
        try applyThemeJson(&theme, "", parsed.value);

        const key_owned = try allocPluginKey(self.allocator, plugin_id, theme_name);
        errdefer self.allocator.free(key_owned);

        if (self.plugin_themes.getPtr(key_owned)) |existing| {
            existing.* = theme;
            self.allocator.free(key_owned);
            std.log.info("Updated theme {s} from plugin {s}", .{ theme_name, plugin_id });
            return;
        }

        try self.plugin_themes.put(key_owned, theme);
        std.log.info("Registered plugin theme {s}::{s}", .{ plugin_id, theme_name });
    }

    pub fn unregisterPluginTheme(
        self: *Self,
        plugin_id: []const u8,
        theme_name: []const u8,
    ) void {
        const key = allocPluginKey(self.allocator, plugin_id, theme_name) catch {
            std.log.err("Failed to allocate key while unregistering theme {s}::{s}", .{ plugin_id, theme_name });
            return;
        };
        defer self.allocator.free(key);

        if (self.plugin_themes.fetchRemove(key)) |removed| {
            self.allocator.free(removed.key);
            std.log.info("Unregistered plugin theme {s}::{s}", .{ plugin_id, theme_name });
        }
    }

    pub fn getPluginTheme(self: *Self, plugin_id: []const u8, theme_name: []const u8) ?Theme {
        const key = allocPluginKey(self.allocator, plugin_id, theme_name) catch {
            return null;
        };
        defer self.allocator.free(key);
        return self.plugin_themes.get(key);
    }

    pub fn get(self: *Self, name: []const u8) ?Theme {
        return self.plugin_themes.get(name);
    }
};

pub fn registerThemeCallback(
    ctx: *anyopaque,
    plugin_id: []const u8,
    theme_name: []const u8,
    colors_json: []const u8,
) ParseThemeError!void {
    const registry = @as(*ThemeRegistry, @ptrCast(@alignCast(ctx)));
    try registry.registerPluginTheme(plugin_id, theme_name, colors_json);
}

pub fn unregisterThemeCallback(
    ctx: *anyopaque,
    plugin_id: []const u8,
    theme_name: []const u8,
) void {
    const registry = @as(*ThemeRegistry, @ptrCast(@alignCast(ctx)));
    registry.unregisterPluginTheme(plugin_id, theme_name);
}

fn allocPluginKey(allocator: std.mem.Allocator, plugin_id: []const u8, theme_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}::{s}", .{ plugin_id, theme_name });
}

fn applyThemeJson(theme: *Theme, parent_key: []const u8, value: json.Value) ParseThemeError!void {
    switch (value) {
        .object => {
            var it = value.object.iterator();
            while (it.next()) |entry| {
                const child_key = entry.key_ptr.*;
                if (parent_key.len == 0) {
                    try applyThemeJson(theme, child_key, entry.value_ptr.*);
                } else {
                    var combined_buf: [128]u8 = undefined;
                    const combined = combineKey(parent_key, child_key, &combined_buf) catch {
                        std.log.err("Theme key '{s}.{s}' is too long", .{ parent_key, child_key });
                        return ThemeRegistryError.KeyTooLong;
                    };
                    try applyThemeJson(theme, combined, entry.value_ptr.*);
                }
            }
        },
        .string => {
            if (parent_key.len == 0) {
                return ThemeRegistryError.InvalidThemeJson;
            }
            const recognized = try assignColor(theme, parent_key, value.string);
            if (!recognized) {
                std.log.warn("Ignoring unknown theme field '{s}'", .{parent_key});
            }
        },
        else => return ThemeRegistryError.InvalidThemeJson,
    }
}

fn combineKey(parent: []const u8, child: []const u8, buffer: *[128]u8) ![]const u8 {
    const total = parent.len + 1 + child.len;
    if (total > buffer.len) return ThemeRegistryError.KeyTooLong;
    @memcpy(buffer[0..parent.len], parent);
    buffer[parent.len] = '_';
    @memcpy(buffer[parent.len + 1 .. parent.len + 1 + child.len], child);
    return buffer[0..total];
}

fn assignColor(theme: *Theme, key: []const u8, value: []const u8) ParseThemeError!bool {
    var normalized_buf: [96]u8 = undefined;
    const normalized = normalizeKey(key, &normalized_buf) catch {
        return ThemeRegistryError.InvalidThemeJson;
    };

    if (normalized.len == 0) {
        return ThemeRegistryError.InvalidThemeJson;
    }

    var slice = normalized;
    const prefixes = [_][]const u8{ "syntax_", "ui_", "palette_", "editor_" };
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, slice, prefix)) {
            slice = slice[prefix.len..];
            break;
        }
    }

    const color = try Color.fromHex(value);

    if (std.mem.eql(u8, slice, "keyword")) {
        theme.keyword = color;
        return true;
    } else if (std.mem.eql(u8, slice, "string") or std.mem.eql(u8, slice, "string_literal")) {
        theme.string_literal = color;
        return true;
    } else if (std.mem.eql(u8, slice, "number") or std.mem.eql(u8, slice, "number_literal")) {
        theme.number_literal = color;
        return true;
    } else if (std.mem.eql(u8, slice, "comment")) {
        theme.comment = color;
        return true;
    } else if (std.mem.eql(u8, slice, "function") or std.mem.eql(u8, slice, "function_name")) {
        theme.function_name = color;
        return true;
    } else if (std.mem.eql(u8, slice, "type") or std.mem.eql(u8, slice, "type_name")) {
        theme.type_name = color;
        return true;
    } else if (std.mem.eql(u8, slice, "variable")) {
        theme.variable = color;
        return true;
    } else if (std.mem.eql(u8, slice, "operator")) {
        theme.operator = color;
        return true;
    } else if (std.mem.eql(u8, slice, "punctuation")) {
        theme.punctuation = color;
        return true;
    } else if (std.mem.eql(u8, slice, "error_bg") or std.mem.eql(u8, slice, "error_background") or std.mem.eql(u8, slice, "error")) {
        theme.error_bg = color;
        return true;
    } else if (std.mem.eql(u8, slice, "error_fg") or std.mem.eql(u8, slice, "error_foreground")) {
        theme.error_fg = color;
        return true;
    } else if (std.mem.eql(u8, slice, "background")) {
        theme.background = color;
        return true;
    } else if (std.mem.eql(u8, slice, "foreground")) {
        theme.foreground = color;
        return true;
    } else if (std.mem.eql(u8, slice, "cursor")) {
        theme.cursor = color;
        return true;
    } else if (std.mem.eql(u8, slice, "selection")) {
        theme.selection = color;
        return true;
    } else if (std.mem.eql(u8, slice, "line_number") or std.mem.eql(u8, slice, "linenumber")) {
        theme.line_number = color;
        return true;
    } else if (std.mem.eql(u8, slice, "status_bar_bg") or std.mem.eql(u8, slice, "status_bar_background")) {
        theme.status_bar_bg = color;
        return true;
    } else if (std.mem.eql(u8, slice, "status_bar_fg") or std.mem.eql(u8, slice, "status_bar_foreground") or std.mem.eql(u8, slice, "status_bar_text")) {
        theme.status_bar_fg = color;
        return true;
    }

    return false;
}

fn normalizeKey(key: []const u8, buffer: []u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, key, " \t\r\n");
    if (trimmed.len == 0) {
        return ThemeRegistryError.InvalidThemeJson;
    }
    if (trimmed.len > buffer.len) {
        return ThemeRegistryError.KeyTooLong;
    }

    const lower = buffer[0..trimmed.len];
    _ = std.ascii.lowerString(lower, trimmed);
    for (lower) |*ch| {
        if (ch.* == '-' or ch.* == '.' or ch.* == ' ') {
            ch.* = '_';
        }
    }
    return lower;
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

test "theme registry plugin registration" {
    var registry = ThemeRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const plugin_id = "example.plugin";
    const theme_name = "midnight";

    const colors_json =
        \\{
        \\  "syntax": {
        \\    "keyword": "#ff00ff",
        \\    "string": "#00ff7f",
        \\    "number": "#ffaa00"
        \\  },
        \\  "ui": {
        \\    "background": "#101020",
        \\    "foreground": "#f0f0f0",
        \\    "status_bar": {
        \\      "bg": "#1a1a2a",
        \\      "fg": "#e0e0ff"
        \\    }
        \\  },
        \\  "error": {
        \\    "bg": "#330000",
        \\    "fg": "#ffcccc"
        \\  }
        \\}
    ;

    try registry.registerPluginTheme(plugin_id, theme_name, colors_json);

    const theme_value_opt = registry.getPluginTheme(plugin_id, theme_name);
    try std.testing.expect(theme_value_opt != null);
    const theme_value = theme_value_opt.?;

    try std.testing.expectEqual(@as(u8, 0xff), theme_value.keyword.r);
    try std.testing.expectEqual(@as(u8, 0x00), theme_value.keyword.g);
    try std.testing.expectEqual(@as(u8, 0xff), theme_value.keyword.b);

    try std.testing.expectEqual(@as(u8, 0x10), theme_value.background.r);
    try std.testing.expectEqual(@as(u8, 0x10), theme_value.background.g);
    try std.testing.expectEqual(@as(u8, 0x20), theme_value.background.b);

    // Update the theme with a new background color
    const update_json =
        \\{ "background": "#222244" }
    ;

    try registry.registerPluginTheme(plugin_id, theme_name, update_json);

    const updated_opt = registry.getPluginTheme(plugin_id, theme_name);
    try std.testing.expect(updated_opt != null);
    const updated = updated_opt.?;
    try std.testing.expectEqual(@as(u8, 0x22), updated.background.r);
    try std.testing.expectEqual(@as(u8, 0x22), updated.background.g);
    try std.testing.expectEqual(@as(u8, 0x44), updated.background.b);

    registry.unregisterPluginTheme(plugin_id, theme_name);
    try std.testing.expect(registry.getPluginTheme(plugin_id, theme_name) == null);
}

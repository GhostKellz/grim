const std = @import("std");

/// Highlight Group and Theme Bridge API
/// Provides stable highlight IDs and theme system integration
pub const HighlightThemeAPI = struct {
    allocator: std.mem.Allocator,
    highlight_groups: std.StringHashMap(HighlightGroup),
    themes: std.StringHashMap(Theme),
    active_theme: ?[]const u8 = null,
    namespace_counter: u32 = 0,
    namespaces: std.StringHashMap(Namespace),

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8 = 255,

        pub fn fromHex(hex: []const u8) !Color {
            if (hex.len != 6 and hex.len != 7) return error.InvalidHexColor;
            const start: usize = if (hex[0] == '#') 1 else 0;

            const r = try std.fmt.parseInt(u8, hex[start .. start + 2], 16);
            const g = try std.fmt.parseInt(u8, hex[start + 2 .. start + 4], 16);
            const b = try std.fmt.parseInt(u8, hex[start + 4 .. start + 6], 16);

            return Color{ .r = r, .g = g, .b = b };
        }

        pub fn toHex(self: Color, allocator: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
        }

        pub fn blend(self: Color, other: Color, ratio: f32) Color {
            const r1 = @as(f32, @floatFromInt(self.r));
            const g1 = @as(f32, @floatFromInt(self.g));
            const b1 = @as(f32, @floatFromInt(self.b));

            const r2 = @as(f32, @floatFromInt(other.r));
            const g2 = @as(f32, @floatFromInt(other.g));
            const b2 = @as(f32, @floatFromInt(other.b));

            return Color{
                .r = @intFromFloat(r1 * (1.0 - ratio) + r2 * ratio),
                .g = @intFromFloat(g1 * (1.0 - ratio) + g2 * ratio),
                .b = @intFromFloat(b1 * (1.0 - ratio) + b2 * ratio),
            };
        }
    };

    pub const Style = packed struct {
        bold: bool = false,
        italic: bool = false,
        underline: bool = false,
        undercurl: bool = false,
        strikethrough: bool = false,
        reverse: bool = false,
        standout: bool = false,
        _padding: u1 = 0,

        pub fn none() Style {
            return .{};
        }
    };

    pub const HighlightGroup = struct {
        id: u32,
        name: []const u8,
        fg: ?Color = null,
        bg: ?Color = null,
        sp: ?Color = null, // Special color (for undercurl, etc.)
        style: Style = Style.none(),
        link: ?[]const u8 = null, // Link to another highlight group

        pub fn clone(self: *const HighlightGroup, allocator: std.mem.Allocator) !HighlightGroup {
            return HighlightGroup{
                .id = self.id,
                .name = try allocator.dupe(u8, self.name),
                .fg = self.fg,
                .bg = self.bg,
                .sp = self.sp,
                .style = self.style,
                .link = if (self.link) |link| try allocator.dupe(u8, link) else null,
            };
        }

        pub fn deinit(self: *HighlightGroup, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            if (self.link) |link| allocator.free(link);
        }
    };

    pub const Theme = struct {
        name: []const u8,
        variant: ThemeVariant,
        groups: std.StringHashMap(HighlightGroup),
        palette: Palette,

        pub const ThemeVariant = enum {
            dark,
            light,
        };

        pub const Palette = struct {
            bg: Color,
            fg: Color,
            bg0: Color,
            bg1: Color,
            bg2: Color,
            bg3: Color,
            fg0: Color,
            fg1: Color,
            fg2: Color,
            fg3: Color,

            red: Color,
            green: Color,
            yellow: Color,
            blue: Color,
            magenta: Color,
            cyan: Color,
            orange: Color,
            purple: Color,

            pub fn gruvboxDark() !Palette {
                return Palette{
                    .bg = try Color.fromHex("282828"),
                    .fg = try Color.fromHex("ebdbb2"),
                    .bg0 = try Color.fromHex("1d2021"),
                    .bg1 = try Color.fromHex("3c3836"),
                    .bg2 = try Color.fromHex("504945"),
                    .bg3 = try Color.fromHex("665c54"),
                    .fg0 = try Color.fromHex("fbf1c7"),
                    .fg1 = try Color.fromHex("ebdbb2"),
                    .fg2 = try Color.fromHex("d5c4a1"),
                    .fg3 = try Color.fromHex("bdae93"),
                    .red = try Color.fromHex("fb4934"),
                    .green = try Color.fromHex("b8bb26"),
                    .yellow = try Color.fromHex("fabd2f"),
                    .blue = try Color.fromHex("83a598"),
                    .magenta = try Color.fromHex("d3869b"),
                    .cyan = try Color.fromHex("8ec07c"),
                    .orange = try Color.fromHex("fe8019"),
                    .purple = try Color.fromHex("d3869b"),
                };
            }

            pub fn tokyonightStorm() !Palette {
                return Palette{
                    .bg = try Color.fromHex("24283b"),
                    .fg = try Color.fromHex("c0caf5"),
                    .bg0 = try Color.fromHex("1f2335"),
                    .bg1 = try Color.fromHex("292e42"),
                    .bg2 = try Color.fromHex("414868"),
                    .bg3 = try Color.fromHex("565f89"),
                    .fg0 = try Color.fromHex("c0caf5"),
                    .fg1 = try Color.fromHex("a9b1d6"),
                    .fg2 = try Color.fromHex("9aa5ce"),
                    .fg3 = try Color.fromHex("737aa2"),
                    .red = try Color.fromHex("f7768e"),
                    .green = try Color.fromHex("9ece6a"),
                    .yellow = try Color.fromHex("e0af68"),
                    .blue = try Color.fromHex("7aa2f7"),
                    .magenta = try Color.fromHex("bb9af7"),
                    .cyan = try Color.fromHex("7dcfff"),
                    .orange = try Color.fromHex("ff9e64"),
                    .purple = try Color.fromHex("9d7cd8"),
                };
            }
        };

        pub fn init(allocator: std.mem.Allocator, name: []const u8, variant: ThemeVariant) Theme {
            return .{
                .name = name,
                .variant = variant,
                .groups = std.StringHashMap(HighlightGroup).init(allocator),
                .palette = undefined,
            };
        }

        pub fn deinit(self: *Theme) void {
            var it = self.groups.iterator();
            while (it.next()) |entry| {
                var group = entry.value_ptr.*;
                group.deinit(self.groups.allocator);
            }
            self.groups.deinit();
        }
    };

    pub const Namespace = struct {
        id: u32,
        name: []const u8,
        highlights: std.ArrayList(NamespaceHighlight),

        pub const NamespaceHighlight = struct {
            buffer_id: u32,
            line: usize,
            col_start: usize,
            col_end: usize,
            group_id: u32,
        };

        pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8) !Namespace {
            return Namespace{
                .id = id,
                .name = try allocator.dupe(u8, name),
                .highlights = std.ArrayList(NamespaceHighlight){},
            };
        }

        pub fn deinit(self: *Namespace, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            self.highlights.deinit(allocator);
        }
    };

    pub fn init(allocator: std.mem.Allocator) HighlightThemeAPI {
        return .{
            .allocator = allocator,
            .highlight_groups = std.StringHashMap(HighlightGroup).init(allocator),
            .themes = std.StringHashMap(Theme).init(allocator),
            .namespaces = std.StringHashMap(Namespace).init(allocator),
        };
    }

    pub fn deinit(self: *HighlightThemeAPI) void {
        var it = self.highlight_groups.iterator();
        while (it.next()) |entry| {
            var group = entry.value_ptr.*;
            group.deinit(self.allocator);
        }
        self.highlight_groups.deinit();

        var theme_it = self.themes.iterator();
        while (theme_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.themes.deinit();

        var ns_it = self.namespaces.iterator();
        while (ns_it.next()) |entry| {
            var ns = entry.value_ptr.*;
            ns.deinit(self.allocator);
        }
        self.namespaces.deinit();
    }

    /// Define a highlight group
    pub fn defineHighlight(
        self: *HighlightThemeAPI,
        name: []const u8,
        fg: ?Color,
        bg: ?Color,
        sp: ?Color,
        style: Style,
    ) !u32 {
        const id = @as(u32, @intCast(self.highlight_groups.count()));

        const group = HighlightGroup{
            .id = id,
            .name = try self.allocator.dupe(u8, name),
            .fg = fg,
            .bg = bg,
            .sp = sp,
            .style = style,
        };

        try self.highlight_groups.put(name, group);
        return id;
    }

    /// Link a highlight group to another
    pub fn linkHighlight(self: *HighlightThemeAPI, from: []const u8, to: []const u8) !void {
        var group = self.highlight_groups.getPtr(from) orelse return error.GroupNotFound;
        if (group.link) |old_link| {
            self.allocator.free(old_link);
        }
        group.link = try self.allocator.dupe(u8, to);
    }

    /// Get a highlight group by name
    pub fn getHighlight(self: *const HighlightThemeAPI, name: []const u8) ?HighlightGroup {
        return self.highlight_groups.get(name);
    }

    /// Get a highlight group, following links
    pub fn resolveHighlight(self: *const HighlightThemeAPI, name: []const u8) ?HighlightGroup {
        var current_name = name;
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        while (true) {
            const group = self.highlight_groups.get(current_name) orelse return null;

            if (group.link) |link| {
                // Check for circular links
                if (visited.contains(link)) return group;
                visited.put(link, {}) catch return group;
                current_name = link;
            } else {
                return group;
            }
        }
    }

    /// Create a new highlight namespace
    pub fn createNamespace(self: *HighlightThemeAPI, name: []const u8) !u32 {
        const id = self.namespace_counter;
        self.namespace_counter += 1;

        const ns = try Namespace.init(self.allocator, id, name);
        try self.namespaces.put(name, ns);

        return id;
    }

    /// Add a highlight to a namespace
    pub fn addNamespaceHighlight(
        self: *HighlightThemeAPI,
        ns_name: []const u8,
        buffer_id: u32,
        group_name: []const u8,
        line: usize,
        col_start: usize,
        col_end: usize,
    ) !void {
        var ns = self.namespaces.getPtr(ns_name) orelse return error.NamespaceNotFound;
        const group = self.highlight_groups.get(group_name) orelse return error.GroupNotFound;

        try ns.highlights.append(self.allocator, .{
            .buffer_id = buffer_id,
            .line = line,
            .col_start = col_start,
            .col_end = col_end,
            .group_id = group.id,
        });
    }

    /// Clear highlights in a namespace
    pub fn clearNamespace(self: *HighlightThemeAPI, ns_name: []const u8, buffer_id: ?u32) !void {
        var ns = self.namespaces.getPtr(ns_name) orelse return error.NamespaceNotFound;

        if (buffer_id) |buf_id| {
            // Clear only for specific buffer
            var i: usize = ns.highlights.items.len;
            while (i > 0) : (i -= 1) {
                const idx = i - 1;
                if (ns.highlights.items[idx].buffer_id == buf_id) {
                    _ = ns.highlights.orderedRemove(idx);
                }
            }
        } else {
            // Clear all
            ns.highlights.clearRetainingCapacity();
        }
    }

    /// Load a theme
    pub fn loadTheme(self: *HighlightThemeAPI, name: []const u8) !void {
        if (!self.themes.contains(name)) return error.ThemeNotFound;
        self.active_theme = name;

        // Apply theme highlight groups
        const theme = self.themes.get(name).?;
        var it = theme.groups.iterator();
        while (it.next()) |entry| {
            const group = entry.value_ptr.*;
            _ = try self.defineHighlight(group.name, group.fg, group.bg, group.sp, group.style);
        }
    }

    /// Register a theme
    pub fn registerTheme(self: *HighlightThemeAPI, theme: Theme) !void {
        try self.themes.put(theme.name, theme);
    }

    /// Create default highlight groups
    pub fn setupDefaultHighlights(self: *HighlightThemeAPI) !void {
        const palette = try Theme.Palette.gruvboxDark();

        // Editor highlights
        _ = try self.defineHighlight("Normal", palette.fg, palette.bg, null, Style.none());
        _ = try self.defineHighlight("Comment", palette.fg3, null, null, .{ .italic = true });
        _ = try self.defineHighlight("Constant", palette.purple, null, null, Style.none());
        _ = try self.defineHighlight("String", palette.green, null, null, Style.none());
        _ = try self.defineHighlight("Character", palette.green, null, null, Style.none());
        _ = try self.defineHighlight("Number", palette.purple, null, null, Style.none());
        _ = try self.defineHighlight("Boolean", palette.purple, null, null, Style.none());
        _ = try self.defineHighlight("Function", palette.green, null, null, .{ .bold = true });
        _ = try self.defineHighlight("Identifier", palette.blue, null, null, Style.none());
        _ = try self.defineHighlight("Statement", palette.red, null, null, Style.none());
        _ = try self.defineHighlight("Keyword", palette.red, null, null, Style.none());
        _ = try self.defineHighlight("Type", palette.yellow, null, null, Style.none());
        _ = try self.defineHighlight("Special", palette.orange, null, null, Style.none());
        _ = try self.defineHighlight("Error", palette.red, null, null, .{ .bold = true });
        _ = try self.defineHighlight("Warning", palette.yellow, null, null, .{ .bold = true });
        _ = try self.defineHighlight("Info", palette.blue, null, null, Style.none());
        _ = try self.defineHighlight("Hint", palette.cyan, null, null, Style.none());

        // UI highlights
        _ = try self.defineHighlight("LineNr", palette.fg3, null, null, Style.none());
        _ = try self.defineHighlight("CursorLine", null, palette.bg1, null, Style.none());
        _ = try self.defineHighlight("CursorLineNr", palette.yellow, null, null, .{ .bold = true });
        _ = try self.defineHighlight("Visual", null, palette.bg2, null, Style.none());
        _ = try self.defineHighlight("StatusLine", palette.fg0, palette.bg2, null, .{ .bold = true });
        _ = try self.defineHighlight("TabLine", palette.fg2, palette.bg1, null, Style.none());
    }
};

test "HighlightThemeAPI define and get" {
    const allocator = std.testing.allocator;
    var api = HighlightThemeAPI.init(allocator);
    defer api.deinit();

    const red = try HighlightThemeAPI.Color.fromHex("#ff0000");
    const id = try api.defineHighlight("ErrorMsg", red, null, null, .{ .bold = true });

    try std.testing.expectEqual(@as(u32, 0), id);

    const group = api.getHighlight("ErrorMsg").?;
    try std.testing.expectEqualStrings("ErrorMsg", group.name);
    try std.testing.expectEqual(red.r, group.fg.?.r);
    try std.testing.expect(group.style.bold);
}

test "HighlightThemeAPI link resolution" {
    const allocator = std.testing.allocator;
    var api = HighlightThemeAPI.init(allocator);
    defer api.deinit();

    const red = try HighlightThemeAPI.Color.fromHex("#ff0000");
    _ = try api.defineHighlight("Error", red, null, null, .{ .bold = true });
    _ = try api.defineHighlight("ErrorMsg", null, null, null, HighlightThemeAPI.Style.none());

    try api.linkHighlight("ErrorMsg", "Error");

    const resolved = api.resolveHighlight("ErrorMsg").?;
    try std.testing.expectEqual(red.r, resolved.fg.?.r);
    try std.testing.expect(resolved.style.bold);
}

test "HighlightThemeAPI namespace" {
    const allocator = std.testing.allocator;
    var api = HighlightThemeAPI.init(allocator);
    defer api.deinit();

    const red = try HighlightThemeAPI.Color.fromHex("#ff0000");
    _ = try api.defineHighlight("Error", red, null, null, HighlightThemeAPI.Style.none());

    const ns_id = try api.createNamespace("diagnostics");
    try std.testing.expectEqual(@as(u32, 0), ns_id);

    try api.addNamespaceHighlight("diagnostics", 1, "Error", 10, 5, 15);

    const ns = api.namespaces.get("diagnostics").?;
    try std.testing.expectEqual(@as(usize, 1), ns.highlights.items.len);
    try std.testing.expectEqual(@as(u32, 1), ns.highlights.items[0].buffer_id);
    try std.testing.expectEqual(@as(usize, 10), ns.highlights.items[0].line);
}

test "Color blend" {
    const red = HighlightThemeAPI.Color{ .r = 255, .g = 0, .b = 0 };
    const blue = HighlightThemeAPI.Color{ .r = 0, .g = 0, .b = 255 };

    const purple = red.blend(blue, 0.5);
    try std.testing.expect(purple.r > 0 and purple.r < 255);
    try std.testing.expect(purple.b > 0 and purple.b < 255);
}

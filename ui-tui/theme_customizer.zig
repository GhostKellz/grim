const std = @import("std");
const runtime = @import("runtime");
const config_mod = @import("config.zig");

/// Theme Customization System
/// Load custom color schemes from config, create themes, and provide theme preview
pub const ThemeCustomizer = struct {
    allocator: std.mem.Allocator,
    custom_themes: std.StringHashMap(CustomTheme),
    active_theme_name: []const u8,

    pub const CustomTheme = struct {
        name: []const u8,
        colors: ThemeColors,

        pub fn deinit(self: *CustomTheme, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };

    pub const ThemeColors = struct {
        // Base colors
        background: runtime.HighlightThemeAPI.Color,
        foreground: runtime.HighlightThemeAPI.Color,
        cursor: runtime.HighlightThemeAPI.Color,
        selection: runtime.HighlightThemeAPI.Color,

        // UI colors
        status_bar_bg: runtime.HighlightThemeAPI.Color,
        status_bar_fg: runtime.HighlightThemeAPI.Color,
        line_number: runtime.HighlightThemeAPI.Color,
        current_line_bg: runtime.HighlightThemeAPI.Color,

        // Syntax colors
        keyword: runtime.HighlightThemeAPI.Color,
        string: runtime.HighlightThemeAPI.Color,
        number: runtime.HighlightThemeAPI.Color,
        comment: runtime.HighlightThemeAPI.Color,
        function: runtime.HighlightThemeAPI.Color,
        type: runtime.HighlightThemeAPI.Color,
        variable: runtime.HighlightThemeAPI.Color,
        operator: runtime.HighlightThemeAPI.Color,

        // Diagnostic colors
        error_fg: runtime.HighlightThemeAPI.Color,
        warning_fg: runtime.HighlightThemeAPI.Color,
        info_fg: runtime.HighlightThemeAPI.Color,
        hint_fg: runtime.HighlightThemeAPI.Color,
    };

    pub fn init(allocator: std.mem.Allocator) ThemeCustomizer {
        return ThemeCustomizer{
            .allocator = allocator,
            .custom_themes = std.StringHashMap(CustomTheme).init(allocator),
            .active_theme_name = "default",
        };
    }

    pub fn deinit(self: *ThemeCustomizer) void {
        var iter = self.custom_themes.iterator();
        while (iter.next()) |entry| {
            var theme = entry.value_ptr;
            theme.deinit(self.allocator);
        }
        self.custom_themes.deinit();
    }

    /// Load custom themes from config
    pub fn loadFromConfig(self: *ThemeCustomizer, config: *const config_mod.Config) !void {
        // Load theme from config color_scheme
        const theme_name = @tagName(config.color_scheme);

        const colors = switch (config.color_scheme) {
            .gruvbox_dark => getGruvboxDark(),
            .gruvbox_light => getGruvboxLight(),
            .one_dark => getOneDark(),
            .nord => getNord(),
            .dracula => getDracula(),
            .custom => try loadCustomFromConfig(config),
        };

        const theme_name_owned = try self.allocator.dupe(u8, theme_name);
        try self.custom_themes.put(theme_name_owned, .{
            .name = theme_name_owned,
            .colors = colors,
        });

        self.active_theme_name = theme_name_owned;
    }

    /// Get the active theme
    pub fn getActiveTheme(self: *const ThemeCustomizer) ?CustomTheme {
        return self.custom_themes.get(self.active_theme_name);
    }

    /// Switch to a different theme
    pub fn switchTheme(self: *ThemeCustomizer, name: []const u8) !void {
        if (self.custom_themes.contains(name)) {
            self.active_theme_name = name;
        } else {
            return error.ThemeNotFound;
        }
    }

    /// Create a theme from custom color definitions
    pub fn createCustomTheme(
        self: *ThemeCustomizer,
        name: []const u8,
        colors: ThemeColors,
    ) !void {
        const name_owned = try self.allocator.dupe(u8, name);
        try self.custom_themes.put(name_owned, .{
            .name = name_owned,
            .colors = colors,
        });
    }

    /// Apply theme to HighlightThemeAPI
    pub fn applyToHighlightAPI(
        self: *const ThemeCustomizer,
        api: *runtime.HighlightThemeAPI,
    ) !void {
        const theme = self.getActiveTheme() orelse return error.NoActiveTheme;

        // Define all highlight groups
        _ = try api.defineHighlight("Background", null, theme.colors.background, null, .{});
        _ = try api.defineHighlight("Foreground", theme.colors.foreground, null, null, .{});
        _ = try api.defineHighlight("Cursor", theme.colors.cursor, null, null, .{});
        _ = try api.defineHighlight("Selection", null, theme.colors.selection, null, .{});

        // Syntax
        _ = try api.defineHighlight("Keyword", theme.colors.keyword, null, null, .{ .bold = true });
        _ = try api.defineHighlight("String", theme.colors.string, null, null, .{});
        _ = try api.defineHighlight("Number", theme.colors.number, null, null, .{});
        _ = try api.defineHighlight("Comment", theme.colors.comment, null, null, .{ .italic = true });
        _ = try api.defineHighlight("Function", theme.colors.function, null, null, .{ .bold = true });
        _ = try api.defineHighlight("Type", theme.colors.type, null, null, .{});
        _ = try api.defineHighlight("Identifier", theme.colors.variable, null, null, .{});
        _ = try api.defineHighlight("Operator", theme.colors.operator, null, null, .{});

        // Diagnostics
        _ = try api.defineHighlight("LspError", theme.colors.error_fg, null, null, .{ .bold = true, .undercurl = true });
        _ = try api.defineHighlight("LspWarning", theme.colors.warning_fg, null, null, .{ .bold = true });
        _ = try api.defineHighlight("LspInfo", theme.colors.info_fg, null, null, .{});
        _ = try api.defineHighlight("LspHint", theme.colors.hint_fg, null, null, .{ .italic = true });
    }

    // Predefined themes

    fn getGruvboxDark() ThemeColors {
        return .{
            .background = runtime.HighlightThemeAPI.Color.fromHex("#282828") catch unreachable,
            .foreground = runtime.HighlightThemeAPI.Color.fromHex("#ebdbb2") catch unreachable,
            .cursor = runtime.HighlightThemeAPI.Color.fromHex("#fe8019") catch unreachable,
            .selection = runtime.HighlightThemeAPI.Color.fromHex("#504945") catch unreachable,
            .status_bar_bg = runtime.HighlightThemeAPI.Color.fromHex("#3c3836") catch unreachable,
            .status_bar_fg = runtime.HighlightThemeAPI.Color.fromHex("#ebdbb2") catch unreachable,
            .line_number = runtime.HighlightThemeAPI.Color.fromHex("#7c6f64") catch unreachable,
            .current_line_bg = runtime.HighlightThemeAPI.Color.fromHex("#3c3836") catch unreachable,
            .keyword = runtime.HighlightThemeAPI.Color.fromHex("#d3869b") catch unreachable,
            .string = runtime.HighlightThemeAPI.Color.fromHex("#b8bb26") catch unreachable,
            .number = runtime.HighlightThemeAPI.Color.fromHex("#d3869b") catch unreachable,
            .comment = runtime.HighlightThemeAPI.Color.fromHex("#928374") catch unreachable,
            .function = runtime.HighlightThemeAPI.Color.fromHex("#8ec07c") catch unreachable,
            .type = runtime.HighlightThemeAPI.Color.fromHex("#fabd2f") catch unreachable,
            .variable = runtime.HighlightThemeAPI.Color.fromHex("#ebdbb2") catch unreachable,
            .operator = runtime.HighlightThemeAPI.Color.fromHex("#fe8019") catch unreachable,
            .error_fg = runtime.HighlightThemeAPI.Color.fromHex("#fb4934") catch unreachable,
            .warning_fg = runtime.HighlightThemeAPI.Color.fromHex("#fabd2f") catch unreachable,
            .info_fg = runtime.HighlightThemeAPI.Color.fromHex("#83a598") catch unreachable,
            .hint_fg = runtime.HighlightThemeAPI.Color.fromHex("#8ec07c") catch unreachable,
        };
    }

    fn getGruvboxLight() ThemeColors {
        return .{
            .background = runtime.HighlightThemeAPI.Color.fromHex("#fbf1c7") catch unreachable,
            .foreground = runtime.HighlightThemeAPI.Color.fromHex("#3c3836") catch unreachable,
            .cursor = runtime.HighlightThemeAPI.Color.fromHex("#af3a03") catch unreachable,
            .selection = runtime.HighlightThemeAPI.Color.fromHex("#ebdbb2") catch unreachable,
            .status_bar_bg = runtime.HighlightThemeAPI.Color.fromHex("#d5c4a1") catch unreachable,
            .status_bar_fg = runtime.HighlightThemeAPI.Color.fromHex("#3c3836") catch unreachable,
            .line_number = runtime.HighlightThemeAPI.Color.fromHex("#bdae93") catch unreachable,
            .current_line_bg = runtime.HighlightThemeAPI.Color.fromHex("#ebdbb2") catch unreachable,
            .keyword = runtime.HighlightThemeAPI.Color.fromHex("#9d0006") catch unreachable,
            .string = runtime.HighlightThemeAPI.Color.fromHex("#79740e") catch unreachable,
            .number = runtime.HighlightThemeAPI.Color.fromHex("#8f3f71") catch unreachable,
            .comment = runtime.HighlightThemeAPI.Color.fromHex("#928374") catch unreachable,
            .function = runtime.HighlightThemeAPI.Color.fromHex("#427b58") catch unreachable,
            .type = runtime.HighlightThemeAPI.Color.fromHex("#b57614") catch unreachable,
            .variable = runtime.HighlightThemeAPI.Color.fromHex("#3c3836") catch unreachable,
            .operator = runtime.HighlightThemeAPI.Color.fromHex("#af3a03") catch unreachable,
            .error_fg = runtime.HighlightThemeAPI.Color.fromHex("#cc241d") catch unreachable,
            .warning_fg = runtime.HighlightThemeAPI.Color.fromHex("#d79921") catch unreachable,
            .info_fg = runtime.HighlightThemeAPI.Color.fromHex("#458588") catch unreachable,
            .hint_fg = runtime.HighlightThemeAPI.Color.fromHex("#689d6a") catch unreachable,
        };
    }

    fn getOneDark() ThemeColors {
        return .{
            .background = runtime.HighlightThemeAPI.Color.fromHex("#282c34") catch unreachable,
            .foreground = runtime.HighlightThemeAPI.Color.fromHex("#abb2bf") catch unreachable,
            .cursor = runtime.HighlightThemeAPI.Color.fromHex("#528bff") catch unreachable,
            .selection = runtime.HighlightThemeAPI.Color.fromHex("#3e4451") catch unreachable,
            .status_bar_bg = runtime.HighlightThemeAPI.Color.fromHex("#21252b") catch unreachable,
            .status_bar_fg = runtime.HighlightThemeAPI.Color.fromHex("#abb2bf") catch unreachable,
            .line_number = runtime.HighlightThemeAPI.Color.fromHex("#495162") catch unreachable,
            .current_line_bg = runtime.HighlightThemeAPI.Color.fromHex("#2c323c") catch unreachable,
            .keyword = runtime.HighlightThemeAPI.Color.fromHex("#c678dd") catch unreachable,
            .string = runtime.HighlightThemeAPI.Color.fromHex("#98c379") catch unreachable,
            .number = runtime.HighlightThemeAPI.Color.fromHex("#d19a66") catch unreachable,
            .comment = runtime.HighlightThemeAPI.Color.fromHex("#5c6370") catch unreachable,
            .function = runtime.HighlightThemeAPI.Color.fromHex("#61afef") catch unreachable,
            .type = runtime.HighlightThemeAPI.Color.fromHex("#e5c07b") catch unreachable,
            .variable = runtime.HighlightThemeAPI.Color.fromHex("#abb2bf") catch unreachable,
            .operator = runtime.HighlightThemeAPI.Color.fromHex("#56b6c2") catch unreachable,
            .error_fg = runtime.HighlightThemeAPI.Color.fromHex("#e06c75") catch unreachable,
            .warning_fg = runtime.HighlightThemeAPI.Color.fromHex("#e5c07b") catch unreachable,
            .info_fg = runtime.HighlightThemeAPI.Color.fromHex("#61afef") catch unreachable,
            .hint_fg = runtime.HighlightThemeAPI.Color.fromHex("#56b6c2") catch unreachable,
        };
    }

    fn getNord() ThemeColors {
        return .{
            .background = runtime.HighlightThemeAPI.Color.fromHex("#2e3440") catch unreachable,
            .foreground = runtime.HighlightThemeAPI.Color.fromHex("#d8dee9") catch unreachable,
            .cursor = runtime.HighlightThemeAPI.Color.fromHex("#88c0d0") catch unreachable,
            .selection = runtime.HighlightThemeAPI.Color.fromHex("#434c5e") catch unreachable,
            .status_bar_bg = runtime.HighlightThemeAPI.Color.fromHex("#3b4252") catch unreachable,
            .status_bar_fg = runtime.HighlightThemeAPI.Color.fromHex("#d8dee9") catch unreachable,
            .line_number = runtime.HighlightThemeAPI.Color.fromHex("#4c566a") catch unreachable,
            .current_line_bg = runtime.HighlightThemeAPI.Color.fromHex("#3b4252") catch unreachable,
            .keyword = runtime.HighlightThemeAPI.Color.fromHex("#81a1c1") catch unreachable,
            .string = runtime.HighlightThemeAPI.Color.fromHex("#a3be8c") catch unreachable,
            .number = runtime.HighlightThemeAPI.Color.fromHex("#b48ead") catch unreachable,
            .comment = runtime.HighlightThemeAPI.Color.fromHex("#616e88") catch unreachable,
            .function = runtime.HighlightThemeAPI.Color.fromHex("#88c0d0") catch unreachable,
            .type = runtime.HighlightThemeAPI.Color.fromHex("#8fbcbb") catch unreachable,
            .variable = runtime.HighlightThemeAPI.Color.fromHex("#d8dee9") catch unreachable,
            .operator = runtime.HighlightThemeAPI.Color.fromHex("#81a1c1") catch unreachable,
            .error_fg = runtime.HighlightThemeAPI.Color.fromHex("#bf616a") catch unreachable,
            .warning_fg = runtime.HighlightThemeAPI.Color.fromHex("#ebcb8b") catch unreachable,
            .info_fg = runtime.HighlightThemeAPI.Color.fromHex("#81a1c1") catch unreachable,
            .hint_fg = runtime.HighlightThemeAPI.Color.fromHex("#88c0d0") catch unreachable,
        };
    }

    fn getDracula() ThemeColors {
        return .{
            .background = runtime.HighlightThemeAPI.Color.fromHex("#282a36") catch unreachable,
            .foreground = runtime.HighlightThemeAPI.Color.fromHex("#f8f8f2") catch unreachable,
            .cursor = runtime.HighlightThemeAPI.Color.fromHex("#bd93f9") catch unreachable,
            .selection = runtime.HighlightThemeAPI.Color.fromHex("#44475a") catch unreachable,
            .status_bar_bg = runtime.HighlightThemeAPI.Color.fromHex("#21222c") catch unreachable,
            .status_bar_fg = runtime.HighlightThemeAPI.Color.fromHex("#f8f8f2") catch unreachable,
            .line_number = runtime.HighlightThemeAPI.Color.fromHex("#6272a4") catch unreachable,
            .current_line_bg = runtime.HighlightThemeAPI.Color.fromHex("#44475a") catch unreachable,
            .keyword = runtime.HighlightThemeAPI.Color.fromHex("#ff79c6") catch unreachable,
            .string = runtime.HighlightThemeAPI.Color.fromHex("#f1fa8c") catch unreachable,
            .number = runtime.HighlightThemeAPI.Color.fromHex("#bd93f9") catch unreachable,
            .comment = runtime.HighlightThemeAPI.Color.fromHex("#6272a4") catch unreachable,
            .function = runtime.HighlightThemeAPI.Color.fromHex("#50fa7b") catch unreachable,
            .type = runtime.HighlightThemeAPI.Color.fromHex("#8be9fd") catch unreachable,
            .variable = runtime.HighlightThemeAPI.Color.fromHex("#f8f8f2") catch unreachable,
            .operator = runtime.HighlightThemeAPI.Color.fromHex("#ff79c6") catch unreachable,
            .error_fg = runtime.HighlightThemeAPI.Color.fromHex("#ff5555") catch unreachable,
            .warning_fg = runtime.HighlightThemeAPI.Color.fromHex("#ffb86c") catch unreachable,
            .info_fg = runtime.HighlightThemeAPI.Color.fromHex("#8be9fd") catch unreachable,
            .hint_fg = runtime.HighlightThemeAPI.Color.fromHex("#50fa7b") catch unreachable,
        };
    }

    fn loadCustomFromConfig(config: *const config_mod.Config) !ThemeColors {
        // For custom themes, use defaults for now
        // TODO: Load from config file custom color definitions
        _ = config;
        return getGruvboxDark();
    }
};

test "ThemeCustomizer init" {
    const allocator = std.testing.allocator;

    var customizer = ThemeCustomizer.init(allocator);
    defer customizer.deinit();

    try std.testing.expectEqual(@as(usize, 0), customizer.custom_themes.count());
}

test "ThemeCustomizer load gruvbox" {
    const allocator = std.testing.allocator;

    var config = config_mod.Config.init(allocator);
    defer config.deinit();
    config.color_scheme = .gruvbox_dark;

    var customizer = ThemeCustomizer.init(allocator);
    defer customizer.deinit();

    try customizer.loadFromConfig(&config);

    try std.testing.expect(customizer.getActiveTheme() != null);
}

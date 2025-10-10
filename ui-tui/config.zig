const std = @import("std");

/// Configuration System for GRIM
/// Supports loading user config from ~/.config/grim/config.grim
pub const Config = struct {
    allocator: std.mem.Allocator,

    // Editor settings
    tab_width: u8 = 4,
    use_spaces: bool = true,
    show_line_numbers: bool = true,
    relative_line_numbers: bool = false,
    wrap_lines: bool = false,
    cursor_line_highlight: bool = true,

    // UI settings
    theme: []const u8,
    color_scheme: ColorScheme = .gruvbox_dark,
    font_size: u16 = 14,
    font_family: []const u8,
    show_statusline: bool = true,
    show_tabline: bool = true,
    show_gutter_signs: bool = true,

    // LSP settings
    lsp_enabled: bool = true,
    lsp_diagnostics_enabled: bool = true,
    lsp_hover_enabled: bool = true,
    lsp_completion_enabled: bool = true,

    // Syntax highlighting
    syntax_enabled: bool = true,
    tree_sitter_enabled: bool = true,

    // Performance
    max_file_size_mb: u32 = 100,
    scroll_off: u8 = 3,

    // Keybindings (custom overrides)
    keybindings: std.StringHashMap([]const u8),

    pub const ColorScheme = enum {
        gruvbox_dark,
        gruvbox_light,
        one_dark,
        nord,
        dracula,
        custom,
    };

    pub fn init(allocator: std.mem.Allocator) Config {
        return Config{
            .allocator = allocator,
            .theme = "gruvbox",
            .font_family = "JetBrains Mono",
            .keybindings = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Config) void {
        var iter = self.keybindings.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.keybindings.deinit();
    }

    /// Load configuration from file
    pub fn loadFromFile(self: *Config, path: []const u8) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Use defaults
                return;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        try self.parse(content);
    }

    /// Load from default location (~/.config/grim/config.grim)
    pub fn loadDefault(self: *Config) !void {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

        const config_path = try std.fs.path.join(self.allocator, &.{
            home,
            ".config",
            "grim",
            "config.grim",
        });
        defer self.allocator.free(config_path);

        try self.loadFromFile(config_path);
    }

    /// Parse configuration content
    /// Format: KEY = VALUE (simple key-value pairs, one per line)
    fn parse(self: *Config, content: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            // Skip empty lines and comments
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Parse KEY = VALUE
            var parts = std.mem.split(u8, trimmed, "=");
            const key = std.mem.trim(u8, parts.next() orelse continue, &std.ascii.whitespace);
            const value = std.mem.trim(u8, parts.next() orelse continue, &std.ascii.whitespace);

            try self.setSetting(key, value);
        }
    }

    /// Set a configuration setting
    fn setSetting(self: *Config, key: []const u8, value: []const u8) !void {
        // Editor settings
        if (std.mem.eql(u8, key, "tab_width")) {
            self.tab_width = try std.fmt.parseInt(u8, value, 10);
        } else if (std.mem.eql(u8, key, "use_spaces")) {
            self.use_spaces = try parseBool(value);
        } else if (std.mem.eql(u8, key, "show_line_numbers")) {
            self.show_line_numbers = try parseBool(value);
        } else if (std.mem.eql(u8, key, "relative_line_numbers")) {
            self.relative_line_numbers = try parseBool(value);
        } else if (std.mem.eql(u8, key, "wrap_lines")) {
            self.wrap_lines = try parseBool(value);
        } else if (std.mem.eql(u8, key, "cursor_line_highlight")) {
            self.cursor_line_highlight = try parseBool(value);
        }
        // UI settings
        else if (std.mem.eql(u8, key, "theme")) {
            self.theme = value; // Note: Should be duped for ownership
        } else if (std.mem.eql(u8, key, "color_scheme")) {
            self.color_scheme = try parseColorScheme(value);
        } else if (std.mem.eql(u8, key, "font_size")) {
            self.font_size = try std.fmt.parseInt(u16, value, 10);
        } else if (std.mem.eql(u8, key, "font_family")) {
            self.font_family = value; // Note: Should be duped for ownership
        } else if (std.mem.eql(u8, key, "show_statusline")) {
            self.show_statusline = try parseBool(value);
        } else if (std.mem.eql(u8, key, "show_tabline")) {
            self.show_tabline = try parseBool(value);
        } else if (std.mem.eql(u8, key, "show_gutter_signs")) {
            self.show_gutter_signs = try parseBool(value);
        }
        // LSP settings
        else if (std.mem.eql(u8, key, "lsp_enabled")) {
            self.lsp_enabled = try parseBool(value);
        } else if (std.mem.eql(u8, key, "lsp_diagnostics")) {
            self.lsp_diagnostics_enabled = try parseBool(value);
        } else if (std.mem.eql(u8, key, "lsp_hover")) {
            self.lsp_hover_enabled = try parseBool(value);
        } else if (std.mem.eql(u8, key, "lsp_completion")) {
            self.lsp_completion_enabled = try parseBool(value);
        }
        // Syntax highlighting
        else if (std.mem.eql(u8, key, "syntax_enabled")) {
            self.syntax_enabled = try parseBool(value);
        } else if (std.mem.eql(u8, key, "tree_sitter")) {
            self.tree_sitter_enabled = try parseBool(value);
        }
        // Performance
        else if (std.mem.eql(u8, key, "max_file_size_mb")) {
            self.max_file_size_mb = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, key, "scroll_off")) {
            self.scroll_off = try std.fmt.parseInt(u8, value, 10);
        }
        // Keybindings (format: bind_KEY = COMMAND)
        else if (std.mem.startsWith(u8, key, "bind_")) {
            const key_seq = key[5..]; // Skip "bind_"
            const key_copy = try self.allocator.dupe(u8, key_seq);
            const cmd_copy = try self.allocator.dupe(u8, value);
            try self.keybindings.put(key_copy, cmd_copy);
        }
    }

    /// Get keybinding for a key sequence
    pub fn getKeybinding(self: *const Config, key_seq: []const u8) ?[]const u8 {
        return self.keybindings.get(key_seq);
    }

    /// Save current configuration to file
    pub fn saveToFile(self: *const Config, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var writer = file.writer();

        try writer.writeAll("# GRIM Configuration File\n\n");

        // Editor settings
        try writer.writeAll("# Editor Settings\n");
        try writer.print("tab_width = {d}\n", .{self.tab_width});
        try writer.print("use_spaces = {s}\n", .{if (self.use_spaces) "true" else "false"});
        try writer.print("show_line_numbers = {s}\n", .{if (self.show_line_numbers) "true" else "false"});
        try writer.print("relative_line_numbers = {s}\n", .{if (self.relative_line_numbers) "true" else "false"});
        try writer.print("wrap_lines = {s}\n", .{if (self.wrap_lines) "true" else "false"});
        try writer.print("cursor_line_highlight = {s}\n\n", .{if (self.cursor_line_highlight) "true" else "false"});

        // UI settings
        try writer.writeAll("# UI Settings\n");
        try writer.print("theme = {s}\n", .{self.theme});
        try writer.print("color_scheme = {s}\n", .{@tagName(self.color_scheme)});
        try writer.print("font_size = {d}\n", .{self.font_size});
        try writer.print("font_family = {s}\n", .{self.font_family});
        try writer.print("show_statusline = {s}\n", .{if (self.show_statusline) "true" else "false"});
        try writer.print("show_tabline = {s}\n", .{if (self.show_tabline) "true" else "false"});
        try writer.print("show_gutter_signs = {s}\n\n", .{if (self.show_gutter_signs) "true" else "false"});

        // LSP settings
        try writer.writeAll("# LSP Settings\n");
        try writer.print("lsp_enabled = {s}\n", .{if (self.lsp_enabled) "true" else "false"});
        try writer.print("lsp_diagnostics = {s}\n", .{if (self.lsp_diagnostics_enabled) "true" else "false"});
        try writer.print("lsp_hover = {s}\n", .{if (self.lsp_hover_enabled) "true" else "false"});
        try writer.print("lsp_completion = {s}\n\n", .{if (self.lsp_completion_enabled) "true" else "false"});

        // Keybindings
        try writer.writeAll("# Keybindings\n");
        var iter = self.keybindings.iterator();
        while (iter.next()) |entry| {
            try writer.print("bind_{s} = {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    /// Create default config file
    pub fn createDefaultConfig(allocator: std.mem.Allocator) !void {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

        // Create ~/.config/grim directory
        const config_dir = try std.fs.path.join(allocator, &.{
            home,
            ".config",
            "grim",
        });
        defer allocator.free(config_dir);

        std.fs.cwd().makePath(config_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Create default config
        var config = Config.init(allocator);
        defer config.deinit();

        const config_path = try std.fs.path.join(allocator, &.{
            home,
            ".config",
            "grim",
            "config.grim",
        });
        defer allocator.free(config_path);

        // Add some default keybindings
        try config.keybindings.put(
            try allocator.dupe(u8, "ctrl_s"),
            try allocator.dupe(u8, "save"),
        );
        try config.keybindings.put(
            try allocator.dupe(u8, "ctrl_q"),
            try allocator.dupe(u8, "quit"),
        );
        try config.keybindings.put(
            try allocator.dupe(u8, "ctrl_n"),
            try allocator.dupe(u8, "new_buffer"),
        );
        try config.keybindings.put(
            try allocator.dupe(u8, "ctrl_w"),
            try allocator.dupe(u8, "close_buffer"),
        );
        try config.keybindings.put(
            try allocator.dupe(u8, "ctrl_tab"),
            try allocator.dupe(u8, "next_buffer"),
        );

        try config.saveToFile(config_path);
    }

    // Helper functions

    fn parseBool(value: []const u8) !bool {
        if (std.mem.eql(u8, value, "true")) return true;
        if (std.mem.eql(u8, value, "false")) return false;
        if (std.mem.eql(u8, value, "1")) return true;
        if (std.mem.eql(u8, value, "0")) return false;
        return error.InvalidBoolValue;
    }

    fn parseColorScheme(value: []const u8) !ColorScheme {
        if (std.mem.eql(u8, value, "gruvbox_dark")) return .gruvbox_dark;
        if (std.mem.eql(u8, value, "gruvbox_light")) return .gruvbox_light;
        if (std.mem.eql(u8, value, "one_dark")) return .one_dark;
        if (std.mem.eql(u8, value, "nord")) return .nord;
        if (std.mem.eql(u8, value, "dracula")) return .dracula;
        if (std.mem.eql(u8, value, "custom")) return .custom;
        return error.InvalidColorScheme;
    }
};

test "Config init and defaults" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try std.testing.expectEqual(@as(u8, 4), config.tab_width);
    try std.testing.expect(config.use_spaces);
    try std.testing.expect(config.show_line_numbers);
    try std.testing.expect(config.lsp_enabled);
}

test "Config parse settings" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    const content =
        \\# Test config
        \\tab_width = 2
        \\use_spaces = false
        \\show_line_numbers = false
        \\theme = nord
        \\color_scheme = one_dark
        \\bind_ctrl_s = save_file
    ;

    try config.parse(content);

    try std.testing.expectEqual(@as(u8, 2), config.tab_width);
    try std.testing.expect(!config.use_spaces);
    try std.testing.expect(!config.show_line_numbers);
    try std.testing.expectEqual(Config.ColorScheme.one_dark, config.color_scheme);

    const binding = config.getKeybinding("ctrl_s");
    try std.testing.expect(binding != null);
    try std.testing.expectEqualStrings("save_file", binding.?);
}

test "Config bool parsing" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.setSetting("use_spaces", "true");
    try std.testing.expect(config.use_spaces);

    try config.setSetting("use_spaces", "false");
    try std.testing.expect(!config.use_spaces);

    try config.setSetting("use_spaces", "1");
    try std.testing.expect(config.use_spaces);

    try config.setSetting("use_spaces", "0");
    try std.testing.expect(!config.use_spaces);
}

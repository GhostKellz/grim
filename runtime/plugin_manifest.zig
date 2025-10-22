const std = @import("std");

/// Plugin manifest parsed from plugin.toml
pub const PluginManifest = struct {
    // [plugin] section
    name: []const u8,
    version: []const u8,
    author: []const u8,
    description: []const u8,
    main: []const u8,
    license: ?[]const u8 = null,
    homepage: ?[]const u8 = null,
    min_grim_version: ?[]const u8 = null,

    // [config] section
    enable_on_startup: bool = true,
    lazy_load: bool = false,
    load_after: [][]const u8 = &.{},
    priority: u8 = 50,

    // [dependencies] section
    requires: [][]const u8 = &.{},
    optional_deps: [][]const u8 = &.{},
    conflicts: [][]const u8 = &.{},

    // [optimize] section
    auto_optimize: bool = false,
    hot_functions: [][]const u8 = &.{},
    compile_on_install: bool = false,

    // [native] section
    native_library: ?[]const u8 = null,
    native_functions: [][]const u8 = &.{},

    allocator: std.mem.Allocator,

    pub fn deinit(self: *PluginManifest) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.author);
        self.allocator.free(self.description);
        self.allocator.free(self.main);

        if (self.license) |license| self.allocator.free(license);
        if (self.homepage) |homepage| self.allocator.free(homepage);
        if (self.min_grim_version) |ver| self.allocator.free(ver);

        for (self.load_after) |item| self.allocator.free(item);
        self.allocator.free(self.load_after);

        for (self.requires) |item| self.allocator.free(item);
        self.allocator.free(self.requires);

        for (self.optional_deps) |item| self.allocator.free(item);
        self.allocator.free(self.optional_deps);

        for (self.conflicts) |item| self.allocator.free(item);
        self.allocator.free(self.conflicts);

        for (self.hot_functions) |item| self.allocator.free(item);
        self.allocator.free(self.hot_functions);

        if (self.native_library) |lib| self.allocator.free(lib);
        for (self.native_functions) |item| self.allocator.free(item);
        self.allocator.free(self.native_functions);
    }

    /// Parse plugin.toml file
    pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !PluginManifest {
        const content = try std.fs.cwd().readFileAlloc(path, allocator, .limited(1024 * 1024));
        defer allocator.free(content);

        return try parse(allocator, content);
    }

    /// Parse plugin.toml content
    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !PluginManifest {
        var manifest = PluginManifest{
            .name = undefined,
            .version = undefined,
            .author = undefined,
            .description = undefined,
            .main = undefined,
            .allocator = allocator,
        };

        // Simple TOML parser (similar to theme parser)
        var plugin_section = std.StringHashMap([]const u8).init(allocator);
        defer plugin_section.deinit();

        var config_section = std.StringHashMap([]const u8).init(allocator);
        defer config_section.deinit();

        var deps_section = std.StringHashMap([]const u8).init(allocator);
        defer deps_section.deinit();

        var optimize_section = std.StringHashMap([]const u8).init(allocator);
        defer optimize_section.deinit();

        var native_section = std.StringHashMap([]const u8).init(allocator);
        defer native_section.deinit();

        // Parse sections
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

            // Remove quotes
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            // Store in appropriate section
            if (std.mem.eql(u8, current_section, "plugin")) {
                try plugin_section.put(key, value);
            } else if (std.mem.eql(u8, current_section, "config")) {
                try config_section.put(key, value);
            } else if (std.mem.eql(u8, current_section, "dependencies")) {
                try deps_section.put(key, value);
            } else if (std.mem.eql(u8, current_section, "optimize")) {
                try optimize_section.put(key, value);
            } else if (std.mem.eql(u8, current_section, "native")) {
                try native_section.put(key, value);
            }
        }

        // Extract required [plugin] fields
        manifest.name = try allocator.dupe(u8, plugin_section.get("name") orelse return error.MissingPluginName);
        manifest.version = try allocator.dupe(u8, plugin_section.get("version") orelse return error.MissingPluginVersion);
        manifest.author = try allocator.dupe(u8, plugin_section.get("author") orelse return error.MissingPluginAuthor);
        manifest.description = try allocator.dupe(u8, plugin_section.get("description") orelse return error.MissingPluginDescription);
        manifest.main = try allocator.dupe(u8, plugin_section.get("main") orelse "init.gza");

        // Extract optional [plugin] fields
        if (plugin_section.get("license")) |license| {
            manifest.license = try allocator.dupe(u8, license);
        }
        if (plugin_section.get("homepage")) |homepage| {
            manifest.homepage = try allocator.dupe(u8, homepage);
        }
        if (plugin_section.get("min_grim_version")) |ver| {
            manifest.min_grim_version = try allocator.dupe(u8, ver);
        }

        // Extract [config] fields
        if (config_section.get("enable_on_startup")) |value| {
            manifest.enable_on_startup = std.mem.eql(u8, value, "true");
        }
        if (config_section.get("lazy_load")) |value| {
            manifest.lazy_load = std.mem.eql(u8, value, "true");
        }
        if (config_section.get("priority")) |value| {
            manifest.priority = std.fmt.parseInt(u8, value, 10) catch 50;
        }

        // Extract [optimize] fields
        if (optimize_section.get("auto_optimize")) |value| {
            manifest.auto_optimize = std.mem.eql(u8, value, "true");
        }
        if (optimize_section.get("compile_on_install")) |value| {
            manifest.compile_on_install = std.mem.eql(u8, value, "true");
        }

        // Extract [native] fields
        if (native_section.get("library")) |lib_path| {
            manifest.native_library = try allocator.dupe(u8, lib_path);
        }

        // Parse array fields
        if (config_section.get("load_after")) |value| {
            manifest.load_after = try parseStringArray(allocator, value);
        }

        if (deps_section.get("requires")) |value| {
            manifest.requires = try parseStringArray(allocator, value);
        }
        if (deps_section.get("optional")) |value| {
            manifest.optional_deps = try parseStringArray(allocator, value);
        }
        if (deps_section.get("conflicts")) |value| {
            manifest.conflicts = try parseStringArray(allocator, value);
        }

        if (optimize_section.get("hot_functions")) |value| {
            manifest.hot_functions = try parseStringArray(allocator, value);
        }

        if (native_section.get("functions")) |value| {
            manifest.native_functions = try parseStringArray(allocator, value);
        }

        return manifest;
    }

    /// Parse TOML array syntax: ["item1", "item2", "item3"]
    fn parseStringArray(allocator: std.mem.Allocator, value: []const u8) ![][]const u8 {
        var trimmed = std.mem.trim(u8, value, " \t");

        // Check for array brackets
        if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') {
            // Not an array, treat as single item
            const item = try allocator.dupe(u8, trimmed);
            const result = try allocator.alloc([]const u8, 1);
            result[0] = item;
            return result;
        }

        // Remove brackets
        trimmed = trimmed[1 .. trimmed.len - 1];

        // Parse comma-separated values
        var items = std.ArrayList([]const u8){};
        errdefer {
            for (items.items) |item| allocator.free(item);
            items.deinit(allocator);
        }

        var iter = std.mem.tokenizeScalar(u8, trimmed, ',');
        while (iter.next()) |item| {
            var clean_item = std.mem.trim(u8, item, " \t");

            // Remove quotes if present
            if (clean_item.len >= 2 and clean_item[0] == '"' and clean_item[clean_item.len - 1] == '"') {
                clean_item = clean_item[1 .. clean_item.len - 1];
            }

            if (clean_item.len > 0) {
                const dup = try allocator.dupe(u8, clean_item);
                try items.append(allocator, dup);
            }
        }

        return items.toOwnedSlice(allocator);
    }
};

test "parse basic manifest" {
    const allocator = std.testing.allocator;

    const toml =
        \\[plugin]
        \\name = "test-plugin"
        \\version = "1.0.0"
        \\author = "Test Author"
        \\description = "Test description"
        \\main = "init.gza"
        \\
        \\[config]
        \\enable_on_startup = true
        \\priority = 60
    ;

    var manifest = try PluginManifest.parse(allocator, toml);
    defer manifest.deinit();

    try std.testing.expectEqualStrings("test-plugin", manifest.name);
    try std.testing.expectEqualStrings("1.0.0", manifest.version);
    try std.testing.expectEqualStrings("Test Author", manifest.author);
    try std.testing.expectEqual(true, manifest.enable_on_startup);
    try std.testing.expectEqual(@as(u8, 60), manifest.priority);
}

test "parse manifest with arrays" {
    const allocator = std.testing.allocator;

    const toml =
        \\[plugin]
        \\name = "advanced-plugin"
        \\version = "2.0.0"
        \\author = "Test Author"
        \\description = "Advanced test"
        \\main = "init.gza"
        \\
        \\[config]
        \\load_after = ["base-plugin", "other-plugin"]
        \\
        \\[dependencies]
        \\requires = ["fuzzy-finder", "git"]
        \\optional = ["lsp-support"]
        \\conflicts = ["old-plugin"]
        \\
        \\[optimize]
        \\hot_functions = ["search", "parse"]
        \\compile_on_install = true
        \\
        \\[native]
        \\library = "native/libplugin.so"
        \\functions = ["fast_search", "parse_buffer"]
    ;

    var manifest = try PluginManifest.parse(allocator, toml);
    defer manifest.deinit();

    try std.testing.expectEqualStrings("advanced-plugin", manifest.name);

    // Test arrays
    try std.testing.expectEqual(@as(usize, 2), manifest.load_after.len);
    try std.testing.expectEqualStrings("base-plugin", manifest.load_after[0]);
    try std.testing.expectEqualStrings("other-plugin", manifest.load_after[1]);

    try std.testing.expectEqual(@as(usize, 2), manifest.requires.len);
    try std.testing.expectEqualStrings("fuzzy-finder", manifest.requires[0]);
    try std.testing.expectEqualStrings("git", manifest.requires[1]);

    try std.testing.expectEqual(@as(usize, 1), manifest.optional_deps.len);
    try std.testing.expectEqualStrings("lsp-support", manifest.optional_deps[0]);

    try std.testing.expectEqual(@as(usize, 1), manifest.conflicts.len);
    try std.testing.expectEqualStrings("old-plugin", manifest.conflicts[0]);

    try std.testing.expectEqual(@as(usize, 2), manifest.hot_functions.len);
    try std.testing.expectEqualStrings("search", manifest.hot_functions[0]);
    try std.testing.expectEqualStrings("parse", manifest.hot_functions[1]);

    try std.testing.expectEqual(@as(usize, 2), manifest.native_functions.len);
    try std.testing.expectEqualStrings("fast_search", manifest.native_functions[0]);
    try std.testing.expectEqualStrings("parse_buffer", manifest.native_functions[1]);

    try std.testing.expectEqual(true, manifest.compile_on_install);
    try std.testing.expect(manifest.native_library != null);
    try std.testing.expectEqualStrings("native/libplugin.so", manifest.native_library.?);
}

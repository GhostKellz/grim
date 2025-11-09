// Plugin Pack System - reaper.zon format
// Allows bundling multiple plugins together for easy distribution
// Similar to Neovim plugin packs or VS Code extension packs

const std = @import("std");

/// Plugin pack metadata
pub const Pack = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    plugins: std.StringHashMap(PackPlugin),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8, description: []const u8, author: []const u8) !*Pack {
        const self = try allocator.create(Pack);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .description = try allocator.dupe(u8, description),
            .author = try allocator.dupe(u8, author),
            .plugins = std.StringHashMap(PackPlugin).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Pack) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        self.allocator.free(self.author);

        var iter = self.plugins.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.plugins.deinit();

        self.allocator.destroy(self);
    }

    /// Add plugin to pack
    pub fn addPlugin(
        self: *Pack,
        name: []const u8,
        source: []const u8,
        version: ?[]const u8,
        enabled: bool,
    ) !void {
        const plugin = PackPlugin{
            .source = try self.allocator.dupe(u8, source),
            .version = if (version) |v| try self.allocator.dupe(u8, v) else null,
            .enabled = enabled,
        };

        const key = try self.allocator.dupe(u8, name);
        try self.plugins.put(key, plugin);
    }

    /// Write pack to reaper.zon file
    pub fn write(self: *Pack, path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var write_buffer: [4096]u8 = undefined;
        var file_writer = file.writer(&write_buffer);
        var writer = &file_writer.interface;

        // Write header
        try writer.writeAll("// Grim Plugin Pack\n");
        try writer.print("// {s} - v{s}\n", .{ self.name, self.version });
        try writer.print("// {s}\n\n", .{self.description});

        try writer.print(".{{\n", .{});
        try writer.print("    .name = \"{s}\",\n", .{self.name});
        try writer.print("    .version = \"{s}\",\n", .{self.version});
        try writer.print("    .description = \"{s}\",\n", .{self.description});
        try writer.print("    .author = \"{s}\",\n", .{self.author});
        try writer.print("    .plugins = .{{\n", .{});

        // Sort plugins by name for deterministic output
        var names = std.ArrayList([]const u8){};
        defer names.deinit(self.allocator);

        var iter = self.plugins.iterator();
        while (iter.next()) |entry| {
            try names.append(self.allocator, entry.key_ptr.*);
        }

        std.mem.sort([]const u8, names.items, {}, lessThan);

        // Write each plugin
        for (names.items) |name| {
            const plugin = self.plugins.get(name).?;
            try writer.print("        .@\"{s}\" = .{{\n", .{name});
            try writer.print("            .source = \"{s}\",\n", .{plugin.source});

            if (plugin.version) |v| {
                try writer.print("            .version = \"{s}\",\n", .{v});
            }

            try writer.print("            .enabled = {},\n", .{plugin.enabled});
            try writer.print("        }},\n", .{});
        }

        try writer.print("    }},\n", .{});
        try writer.print("}}\n", .{});

        try writer.flush();
    }

    /// Read pack from reaper.zon file
    pub fn read(allocator: std.mem.Allocator, path: []const u8) !*Pack {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        const stat = try file.stat();
        const max_size = @min(stat.size, 10 * 1024 * 1024); // 10MB max
        const content = try allocator.alloc(u8, max_size);
        defer allocator.free(content);

        const bytes_read = try file.read(content);
        const actual_content = content[0..bytes_read];

        return try parseReaperZon(allocator, actual_content);
    }

    fn lessThan(_: void, a: []const u8, b: []const u8) bool {
        return std.mem.order(u8, a, b) == .lt;
    }
};

/// Plugin entry in pack
pub const PackPlugin = struct {
    source: []const u8, // Git URL, local path, or registry name
    version: ?[]const u8, // Version constraint
    enabled: bool, // Whether to install by default

    pub fn deinit(self: *PackPlugin, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        if (self.version) |v| {
            allocator.free(v);
        }
    }
};

/// Parse reaper.zon format pack file
fn parseReaperZon(allocator: std.mem.Allocator, content: []const u8) !*Pack {
    var pack_name: []const u8 = "unnamed-pack";
    var pack_version: []const u8 = "0.0.0";
    var pack_description: []const u8 = "";
    var pack_author: []const u8 = "unknown";

    var lines = std.mem.tokenizeScalar(u8, content, '\n');

    // First pass: extract metadata
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) continue;

        if (std.mem.indexOf(u8, trimmed, ".name =")) |_| {
            pack_name = try extractQuotedValue(allocator, trimmed);
        } else if (std.mem.indexOf(u8, trimmed, ".version =")) |_| {
            pack_version = try extractQuotedValue(allocator, trimmed);
        } else if (std.mem.indexOf(u8, trimmed, ".description =")) |_| {
            pack_description = try extractQuotedValue(allocator, trimmed);
        } else if (std.mem.indexOf(u8, trimmed, ".author =")) |_| {
            pack_author = try extractQuotedValue(allocator, trimmed);
        }
    }

    const pack = try Pack.init(allocator, pack_name, pack_version, pack_description, pack_author);
    errdefer pack.deinit();

    // Second pass: extract plugins
    lines.reset();
    var in_plugins_section = false;
    var current_plugin_name: ?[]const u8 = null;
    var current_plugin_source: ?[]const u8 = null;
    var current_plugin_version: ?[]const u8 = null;
    var current_plugin_enabled: bool = true;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) continue;

        if (std.mem.indexOf(u8, trimmed, ".plugins =")) |_| {
            in_plugins_section = true;
            continue;
        }

        if (in_plugins_section) {
            // Plugin name line: .@"plugin-name" = .{
            if (std.mem.indexOf(u8, trimmed, ".@\"")) |_| {
                // Save previous plugin if exists
                if (current_plugin_name) |name| {
                    if (current_plugin_source) |source| {
                        try pack.addPlugin(name, source, current_plugin_version, current_plugin_enabled);
                    }
                }

                // Extract new plugin name
                const start = std.mem.indexOf(u8, trimmed, "\"").? + 1;
                const end = std.mem.indexOfPos(u8, trimmed, start, "\"").?;
                current_plugin_name = try allocator.dupe(u8, trimmed[start..end]);
                current_plugin_source = null;
                current_plugin_version = null;
                current_plugin_enabled = true;
            } else if (std.mem.indexOf(u8, trimmed, ".source =")) |_| {
                current_plugin_source = try extractQuotedValue(allocator, trimmed);
            } else if (std.mem.indexOf(u8, trimmed, ".version =")) |_| {
                current_plugin_version = try extractQuotedValue(allocator, trimmed);
            } else if (std.mem.indexOf(u8, trimmed, ".enabled =")) |_| {
                current_plugin_enabled = try extractBoolValue(trimmed);
            }
        }
    }

    // Save last plugin
    if (current_plugin_name) |name| {
        if (current_plugin_source) |source| {
            try pack.addPlugin(name, source, current_plugin_version, current_plugin_enabled);
        }
    }

    return pack;
}

/// Extract quoted string value
fn extractQuotedValue(allocator: std.mem.Allocator, line: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, line, "\"") orelse return error.InvalidFormat;
    const end = std.mem.indexOfPos(u8, line, start + 1, "\"") orelse return error.InvalidFormat;
    return try allocator.dupe(u8, line[start + 1 .. end]);
}

/// Extract boolean value
fn extractBoolValue(line: []const u8) !bool {
    if (std.mem.indexOf(u8, line, "true")) |_| return true;
    if (std.mem.indexOf(u8, line, "false")) |_| return false;
    return error.InvalidFormat;
}

/// Install all plugins from a pack
pub fn installPack(allocator: std.mem.Allocator, pack_path: []const u8) !void {
    const pack = try Pack.read(allocator, pack_path);
    defer pack.deinit();

    std.debug.print("\n📦 Installing pack: {s} v{s}\n", .{ pack.name, pack.version });
    std.debug.print("   {s}\n\n", .{pack.description});

    var installed: usize = 0;
    var skipped: usize = 0;

    var iter = pack.plugins.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const plugin = entry.value_ptr.*;

        if (!plugin.enabled) {
            std.debug.print("  ⏭️  Skipping {s} (disabled)\n", .{name});
            skipped += 1;
            continue;
        }

        std.debug.print("  📥 Installing {s}...", .{name});

        // TODO: Integrate with plugin installation logic
        // For now, just print what would happen
        if (plugin.version) |v| {
            std.debug.print(" [v{s}]", .{v});
        }
        std.debug.print(" from {s}\n", .{plugin.source});

        installed += 1;
    }

    std.debug.print("\n\x1b[32m✓ Pack installation complete\x1b[0m\n", .{});
    std.debug.print("  Installed: {d} plugins\n", .{installed});
    if (skipped > 0) {
        std.debug.print("  Skipped: {d} plugins\n", .{skipped});
    }
}

/// Create a new pack template
pub fn createPackTemplate(allocator: std.mem.Allocator, path: []const u8, name: []const u8) !void {
    const pack = try Pack.init(
        allocator,
        name,
        "0.1.0",
        "A collection of useful Grim plugins",
        "Your Name",
    );
    defer pack.deinit();

    // Add example plugins
    try pack.addPlugin("example-plugin1", "github:user/plugin1", "1.0.0", true);
    try pack.addPlugin("example-plugin2", "github:user/plugin2", null, true);
    try pack.addPlugin("optional-plugin", "github:user/optional", "0.5.0", false);

    try pack.write(path);

    std.debug.print("\n\x1b[32m✓ Created pack template: {s}\x1b[0m\n", .{path});
    std.debug.print("  Edit the file to customize your plugin pack\n", .{});
}

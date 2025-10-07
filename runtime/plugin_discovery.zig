const std = @import("std");
const PluginManifest = @import("plugin_manifest.zig").PluginManifest;

/// Discovered plugin (not yet loaded)
pub const DiscoveredPlugin = struct {
    name: []const u8,
    path: []const u8, // Full path to plugin directory
    manifest_path: []const u8, // Full path to plugin.toml
    manifest: PluginManifest,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiscoveredPlugin) void {
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        self.allocator.free(self.manifest_path);
        self.manifest.deinit();
    }
};

/// Plugin discovery service
pub const PluginDiscovery = struct {
    allocator: std.mem.Allocator,
    plugin_dirs: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) PluginDiscovery {
        return .{
            .allocator = allocator,
            .plugin_dirs = .{},
        };
    }

    pub fn deinit(self: *PluginDiscovery) void {
        for (self.plugin_dirs.items) |dir| {
            self.allocator.free(dir);
        }
        self.plugin_dirs.deinit(self.allocator);
    }

    /// Add a plugin search directory
    pub fn addSearchPath(self: *PluginDiscovery, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.plugin_dirs.append(self.allocator, owned_path);
    }

    /// Add default search paths
    pub fn addDefaultPaths(self: *PluginDiscovery) !void {
        // 1. User plugins directory
        if (std.posix.getenv("HOME")) |home| {
            const user_plugins = try std.fs.path.join(self.allocator, &.{ home, ".config", "grim", "plugins" });
            defer self.allocator.free(user_plugins);
            try self.addSearchPath(user_plugins);
        }

        // 2. Project plugins directory (relative to cwd)
        try self.addSearchPath("plugins");

        // 3. System plugins
        try self.addSearchPath("/usr/share/grim/plugins");
        try self.addSearchPath("/usr/local/share/grim/plugins");
    }

    /// Discover all plugins in search paths
    pub fn discoverAll(self: *PluginDiscovery) !std.ArrayList(DiscoveredPlugin) {
        var plugins: std.ArrayList(DiscoveredPlugin) = .{};

        for (self.plugin_dirs.items) |search_dir| {
            // Try to discover plugins in this directory
            self.discoverInDirectory(search_dir, &plugins) catch |err| {
                std.log.debug("Failed to discover plugins in {s}: {}", .{ search_dir, err });
                continue;
            };
        }

        return plugins;
    }

    /// Discover plugins in a specific directory
    fn discoverInDirectory(
        self: *PluginDiscovery,
        dir_path: []const u8,
        plugins: *std.ArrayList(DiscoveredPlugin),
    ) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return; // Directory doesn't exist, skip
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .directory) continue;

            // Check for plugin.toml in this directory
            const manifest_path = try std.fs.path.join(
                self.allocator,
                &.{ dir_path, entry.name, "plugin.toml" },
            );
            defer self.allocator.free(manifest_path);

            // Try to parse manifest
            const manifest = PluginManifest.parseFile(self.allocator, manifest_path) catch |err| {
                std.log.debug("Skipping {s}: {}", .{ entry.name, err });
                continue;
            };

            // Success! Add to discovered plugins
            const plugin_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
            const owned_manifest_path = try self.allocator.dupe(u8, manifest_path);

            const plugin = DiscoveredPlugin{
                .name = try self.allocator.dupe(u8, manifest.name),
                .path = plugin_path,
                .manifest_path = owned_manifest_path,
                .manifest = manifest,
                .allocator = self.allocator,
            };

            try plugins.append(self.allocator, plugin);
            std.log.info("Discovered plugin: {s} v{s} at {s}", .{ plugin.name, manifest.version, plugin_path });
        }
    }

    /// Sort plugins by load priority (higher priority first)
    pub fn sortByPriority(plugins: *std.ArrayList(DiscoveredPlugin)) void {
        const lessThan = struct {
            fn lessThan(_: void, a: DiscoveredPlugin, b: DiscoveredPlugin) bool {
                return a.manifest.priority > b.manifest.priority; // Higher priority first
            }
        }.lessThan;

        std.sort.insertion(DiscoveredPlugin, plugins.items, {}, lessThan);
    }

    /// Check if all dependencies are satisfied
    pub fn checkDependencies(plugins: []const DiscoveredPlugin) !void {
        // Build name->plugin map
        var plugin_map = std.StringHashMap(*const DiscoveredPlugin).init(std.heap.page_allocator);
        defer plugin_map.deinit();

        for (plugins) |*plugin| {
            try plugin_map.put(plugin.name, plugin);
        }

        // Check each plugin's dependencies
        for (plugins) |*plugin| {
            for (plugin.manifest.requires) |required| {
                if (!plugin_map.contains(required)) {
                    std.log.err("Plugin '{s}' requires '{s}' which is not installed", .{ plugin.name, required });
                    return error.MissingDependency;
                }
            }
        }
    }
};

test "discover example plugins" {
    const allocator = std.testing.allocator;

    var discovery = PluginDiscovery.init(allocator);
    defer discovery.deinit();

    // Add example plugins directory
    try discovery.addSearchPath("plugins/examples");

    var plugins = try discovery.discoverAll();
    defer {
        for (plugins.items) |*plugin| {
            plugin.deinit();
        }
        plugins.deinit(allocator);
    }

    // Should discover at least hello-world
    try std.testing.expect(plugins.items.len > 0);

    // Check if hello-world was found
    var found_hello = false;
    for (plugins.items) |plugin| {
        if (std.mem.eql(u8, plugin.name, "hello-world")) {
            found_hello = true;
            try std.testing.expectEqualStrings("1.0.0", plugin.manifest.version);
            break;
        }
    }

    try std.testing.expect(found_hello);
}

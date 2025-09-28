const std = @import("std");
const runtime = @import("mod.zig");
const host = @import("host");

pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugin_api: *runtime.PluginAPI,
    plugin_directories: [][]const u8,
    ghostlang_host: host.Host,

    pub const Error = error{
        PluginDirectoryNotFound,
        InvalidPluginScript,
        PluginLoadFailed,
        SecurityViolation,
    } || runtime.PluginAPI.Error || host.Host.Error || std.fs.File.OpenError || std.mem.Allocator.Error;

    const PLUGIN_EXTENSION = ".gza";
    const PLUGIN_MANIFEST_FILE = "plugin.json";

    pub const PluginManifest = struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
        author: []const u8,
        description: []const u8,
        entry_point: []const u8,
        dependencies: [][]const u8,
        permissions: PluginPermissions,

        pub const PluginPermissions = struct {
            file_system_access: bool = false,
            network_access: bool = false,
            system_calls: bool = false,
            editor_full_access: bool = true,
            allowed_directories: [][]const u8 = &.{},
            blocked_directories: [][]const u8 = &.{},
        };
    };

    pub const PluginInfo = struct {
        manifest: PluginManifest,
        plugin_path: []const u8,
        script_content: []const u8,
        loaded: bool,
    };

    pub fn init(allocator: std.mem.Allocator, plugin_api: *runtime.PluginAPI, plugin_directories: [][]const u8) !PluginManager {
        const ghostlang_host = try host.Host.init(allocator);
        return PluginManager{
            .allocator = allocator,
            .plugin_api = plugin_api,
            .plugin_directories = plugin_directories,
            .ghostlang_host = ghostlang_host,
        };
    }

    pub fn deinit(self: *PluginManager) void {
        self.ghostlang_host.deinit();
    }

    pub fn discoverPlugins(self: *PluginManager) ![]PluginInfo {
        var discovered_plugins = std.ArrayList(PluginInfo).init(self.allocator);
        errdefer {
            for (discovered_plugins.items) |plugin_info| {
                self.allocator.free(plugin_info.plugin_path);
                self.allocator.free(plugin_info.script_content);
            }
            discovered_plugins.deinit();
        }

        for (self.plugin_directories) |plugin_dir| {
            try self.discoverPluginsInDirectory(plugin_dir, &discovered_plugins);
        }

        return discovered_plugins.toOwnedSlice();
    }

    fn discoverPluginsInDirectory(self: *PluginManager, directory: []const u8, plugins: *std.ArrayList(PluginInfo)) !void {
        var dir = std.fs.cwd().openDir(directory, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                std.log.warn("Plugin directory not found: {s}", .{directory});
                return;
            }
            return err;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                // Check for plugin manifest in subdirectory
                const plugin_path = try std.fs.path.join(self.allocator, &.{ directory, entry.name });
                defer self.allocator.free(plugin_path);

                if (try self.loadPluginFromDirectory(plugin_path)) |plugin_info| {
                    try plugins.append(plugin_info);
                }
            } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, PLUGIN_EXTENSION)) {
                // Single-file plugin
                const plugin_path = try std.fs.path.join(self.allocator, &.{ directory, entry.name });
                defer self.allocator.free(plugin_path);

                if (try self.loadSingleFilePlugin(plugin_path)) |plugin_info| {
                    try plugins.append(plugin_info);
                }
            }
        }
    }

    fn loadPluginFromDirectory(self: *PluginManager, plugin_dir: []const u8) !?PluginInfo {
        // Try to read plugin manifest
        const manifest_path = try std.fs.path.join(self.allocator, &.{ plugin_dir, PLUGIN_MANIFEST_FILE });
        defer self.allocator.free(manifest_path);

        const manifest_content = std.fs.cwd().readFileAlloc(self.allocator, manifest_path, 1024 * 1024) catch |err| {
            if (err == error.FileNotFound) {
                return null; // No manifest, skip this directory
            }
            return err;
        };
        defer self.allocator.free(manifest_content);

        const manifest = try self.parsePluginManifest(manifest_content);

        // Load script content
        const script_path = try std.fs.path.join(self.allocator, &.{ plugin_dir, manifest.entry_point });
        defer self.allocator.free(script_path);

        const script_content = try std.fs.cwd().readFileAlloc(self.allocator, script_path, 10 * 1024 * 1024);

        return PluginInfo{
            .manifest = manifest,
            .plugin_path = try self.allocator.dupe(u8, plugin_dir),
            .script_content = script_content,
            .loaded = false,
        };
    }

    fn loadSingleFilePlugin(self: *PluginManager, plugin_path: []const u8) !?PluginInfo {
        const script_content = try std.fs.cwd().readFileAlloc(self.allocator, plugin_path, 10 * 1024 * 1024);
        errdefer self.allocator.free(script_content);

        // Parse embedded manifest from script comments
        const manifest = self.parseEmbeddedManifest(script_content) catch |err| {
            self.allocator.free(script_content);
            std.log.warn("Failed to parse manifest from {s}: {}", .{ plugin_path, err });
            return null;
        };

        return PluginInfo{
            .manifest = manifest,
            .plugin_path = try self.allocator.dupe(u8, plugin_path),
            .script_content = script_content,
            .loaded = false,
        };
    }

    fn parsePluginManifest(self: *PluginManager, manifest_content: []const u8) !PluginManifest {
        // Simple JSON parsing - in a real implementation, you'd use a proper JSON parser
        _ = self;
        _ = manifest_content;

        // Placeholder implementation
        return PluginManifest{
            .id = "example-plugin",
            .name = "Example Plugin",
            .version = "1.0.0",
            .author = "Unknown",
            .description = "Example plugin",
            .entry_point = "main.gza",
            .dependencies = &.{},
            .permissions = .{},
        };
    }

    fn parseEmbeddedManifest(self: *PluginManager, script_content: []const u8) !PluginManifest {
        _ = self;

        // Look for plugin metadata in comments at the top of the file
        // Format: // @plugin-id: example-plugin
        //         // @plugin-name: Example Plugin
        //         // @plugin-version: 1.0.0
        //         // etc.

        var id: ?[]const u8 = null;
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var author: ?[]const u8 = null;
        var description: ?[]const u8 = null;

        var lines = std.mem.split(u8, script_content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Stop parsing metadata when we reach non-comment line
            if (!std.mem.startsWith(u8, trimmed, "//")) {
                break;
            }

            // Parse metadata tags
            if (std.mem.startsWith(u8, trimmed, "// @plugin-id:")) {
                id = std.mem.trim(u8, trimmed[14..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-name:")) {
                name = std.mem.trim(u8, trimmed[16..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-version:")) {
                version = std.mem.trim(u8, trimmed[19..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-author:")) {
                author = std.mem.trim(u8, trimmed[18..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-description:")) {
                description = std.mem.trim(u8, trimmed[23..], " \t");
            }
        }

        return PluginManifest{
            .id = id orelse "unknown-plugin",
            .name = name orelse "Unknown Plugin",
            .version = version orelse "0.0.0",
            .author = author orelse "Unknown",
            .description = description orelse "No description provided",
            .entry_point = "main.gza",
            .dependencies = &.{},
            .permissions = .{},
        };
    }

    pub fn loadPlugin(self: *PluginManager, plugin_info: *PluginInfo) !void {
        if (plugin_info.loaded) {
            return; // Already loaded
        }

        // Create sandbox configuration based on plugin permissions
        const sandbox_config = host.Host.SandboxConfig{
            .enable_filesystem_access = plugin_info.manifest.permissions.file_system_access,
            .enable_network_access = plugin_info.manifest.permissions.network_access,
            .enable_system_calls = plugin_info.manifest.permissions.system_calls,
            .allowed_file_patterns = plugin_info.manifest.permissions.allowed_directories,
            .blocked_file_patterns = plugin_info.manifest.permissions.blocked_directories,
        };

        // Initialize Ghostlang host with sandbox
        self.ghostlang_host = try host.Host.initWithSandbox(self.allocator, sandbox_config);

        // Load and execute plugin script
        try self.ghostlang_host.loadConfig(plugin_info.plugin_path);

        // TODO: Execute plugin script through Ghostlang VM
        // This would involve:
        // 1. Parsing the Ghostlang script
        // 2. Setting up FFI bindings for plugin API functions
        // 3. Executing the script in sandboxed environment
        // 4. Registering plugin with the API

        // For now, create a dummy plugin
        const plugin = try self.createDummyPlugin(plugin_info.manifest);

        try self.plugin_api.loadPlugin(plugin);
        plugin_info.loaded = true;

        std.log.info("Loaded plugin: {s} v{s} from {s}", .{
            plugin_info.manifest.name,
            plugin_info.manifest.version,
            plugin_info.plugin_path,
        });
    }

    fn createDummyPlugin(self: *PluginManager, manifest: PluginManifest) !*runtime.Plugin {
        const plugin = try self.allocator.create(runtime.Plugin);
        plugin.* = runtime.Plugin{
            .id = manifest.id,
            .name = manifest.name,
            .version = manifest.version,
            .author = manifest.author,
            .description = manifest.description,
            .context = undefined, // Will be set by plugin system
            .init_fn = dummyInitPlugin,
            .deinit_fn = null,
            .activate_fn = null,
            .deactivate_fn = null,
        };
        return plugin;
    }

    fn dummyInitPlugin(ctx: *runtime.PluginContext) !void {
        try ctx.showMessage("Dummy plugin loaded successfully");
    }

    pub fn unloadPlugin(self: *PluginManager, plugin_id: []const u8) !void {
        try self.plugin_api.unloadPlugin(plugin_id);
    }

    pub fn reloadPlugin(self: *PluginManager, plugin_info: *PluginInfo) !void {
        if (plugin_info.loaded) {
            try self.unloadPlugin(plugin_info.manifest.id);
            plugin_info.loaded = false;
        }

        // Reload script content
        self.allocator.free(plugin_info.script_content);
        plugin_info.script_content = try std.fs.cwd().readFileAlloc(self.allocator, plugin_info.plugin_path, 10 * 1024 * 1024);

        try self.loadPlugin(plugin_info);
    }

    pub fn getPluginStats(self: *PluginManager) host.Host.ExecutionStats {
        return self.ghostlang_host.getExecutionStats();
    }

    pub fn resetStats(self: *PluginManager) void {
        self.ghostlang_host.resetStats();
    }
};
const std = @import("std");
const runtime = @import("mod.zig");
const host = @import("host");

const GhostlangLoadedPlugin = struct {
    runtime_plugin: runtime.Plugin,
    host: host.Host,
    compiled: host.Host.CompiledPlugin,
    host_deinitialized: bool = false,
};

fn pluginStateFromContext(ctx: *runtime.PluginAPI.PluginContext) *GhostlangLoadedPlugin {
    const raw = ctx.userData() orelse @panic("Ghostlang plugin context missing state");
    return @as(*GhostlangLoadedPlugin, @ptrCast(@alignCast(raw)));
}

fn ghostlangShowMessageCallback(ctx_ptr: *anyopaque, message: []const u8) anyerror!void {
    const plugin_ctx = @as(*runtime.PluginAPI.PluginContext, @ptrCast(@alignCast(ctx_ptr)));
    try plugin_ctx.showMessage(message);
}

fn ghostlangPluginInit(ctx: *runtime.PluginAPI.PluginContext) anyerror!void {
    var state = pluginStateFromContext(ctx);
    const start_time = state.host.startExecution();
    errdefer state.host.endExecution(start_time) catch {};

    const callbacks = host.Host.ActionCallbacks{
        .ctx = @as(*anyopaque, @ptrCast(ctx)),
        .show_message = ghostlangShowMessageCallback,
    };

    try state.compiled.executeSetup(callbacks);
    try state.host.endExecution(start_time);
}

fn ghostlangPluginDeinit(ctx: *runtime.PluginAPI.PluginContext) anyerror!void {
    var state = pluginStateFromContext(ctx);
    state.compiled.deinit();
    if (!state.host_deinitialized) {
        state.host.deinit();
        state.host_deinitialized = true;
    }
}

pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugin_api: *runtime.PluginAPI,
    plugin_directories: [][]const u8,
    ghostlang_host: host.Host,
    loaded_plugin_states: std.StringHashMap(*GhostlangLoadedPlugin),

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
        state: ?*GhostlangLoadedPlugin = null,
    };

    pub fn init(allocator: std.mem.Allocator, plugin_api: *runtime.PluginAPI, plugin_directories: [][]const u8) !PluginManager {
        const ghostlang_host = try host.Host.init(allocator);
        return PluginManager{
            .allocator = allocator,
            .plugin_api = plugin_api,
            .plugin_directories = plugin_directories,
            .ghostlang_host = ghostlang_host,
            .loaded_plugin_states = std.StringHashMap(*GhostlangLoadedPlugin).init(allocator),
        };
    }

    pub fn deinit(self: *PluginManager) void {
        var iter = self.loaded_plugin_states.iterator();
        while (iter.next()) |entry| {
            self.cleanupGhostlangState(entry.value_ptr.*);
        }
        self.loaded_plugin_states.deinit();
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
        const PermissionsDTO = struct {
            file_system_access: ?bool = null,
            network_access: ?bool = null,
            system_calls: ?bool = null,
            editor_full_access: ?bool = null,
            allowed_directories: ?[]const []const u8 = null,
            blocked_directories: ?[]const []const u8 = null,
        };

        const ManifestDTO = struct {
            id: []const u8,
            name: []const u8,
            version: []const u8,
            author: ?[]const u8 = null,
            description: ?[]const u8 = null,
            entry_point: []const u8,
            dependencies: ?[]const []const u8 = null,
            permissions: ?PermissionsDTO = null,
        };

        var parsed = try std.json.parseFromSlice(ManifestDTO, self.allocator, manifest_content, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const dto = parsed.value;

        var manifest = PluginManifest{
            .id = try self.allocator.dupe(u8, dto.id),
            .name = try self.allocator.dupe(u8, dto.name),
            .version = try self.allocator.dupe(u8, dto.version),
            .author = try duplicateOptionalString(self.allocator, dto.author, "Unknown"),
            .description = try duplicateOptionalString(self.allocator, dto.description, ""),
            .entry_point = try self.allocator.dupe(u8, dto.entry_point),
            .dependencies = if (dto.dependencies) |deps| try duplicateStringSlice(self.allocator, deps) else &.{},
            .permissions = .{},
        };

        errdefer freeManifest(self.allocator, &manifest);

        if (dto.permissions) |perms| {
            manifest.permissions.file_system_access = perms.file_system_access orelse manifest.permissions.file_system_access;
            manifest.permissions.network_access = perms.network_access orelse manifest.permissions.network_access;
            manifest.permissions.system_calls = perms.system_calls orelse manifest.permissions.system_calls;
            manifest.permissions.editor_full_access = perms.editor_full_access orelse manifest.permissions.editor_full_access;
            manifest.permissions.allowed_directories = if (perms.allowed_directories) |dirs| try duplicateStringSlice(self.allocator, dirs) else manifest.permissions.allowed_directories;
            manifest.permissions.blocked_directories = if (perms.blocked_directories) |dirs| try duplicateStringSlice(self.allocator, dirs) else manifest.permissions.blocked_directories;
        }

        try self.validatePermissions(&manifest.permissions);
        return manifest;
    }

    fn duplicateOptionalString(allocator: std.mem.Allocator, value: ?[]const u8, default_value: []const u8) ![]const u8 {
        if (value) |val| {
            return try allocator.dupe(u8, val);
        }
        return try allocator.dupe(u8, default_value);
    }

    fn duplicateStringSlice(allocator: std.mem.Allocator, source: []const []const u8) ![][]const u8 {
        if (source.len == 0) return &.{};
        var dest = try allocator.alloc([]const u8, source.len);
        var i: usize = 0;
        errdefer {
            while (i > 0) : (i -= 1) {
                allocator.free(dest[i - 1]);
            }
            allocator.free(dest);
        }
        while (i < source.len) : (i += 1) {
            dest[i] = try allocator.dupe(u8, source[i]);
        }
        return dest;
    }

    fn freeManifest(allocator: std.mem.Allocator, manifest: *PluginManifest) void {
        allocator.free(manifest.id);
        allocator.free(manifest.name);
        allocator.free(manifest.version);
        allocator.free(manifest.author);
        allocator.free(manifest.description);
        allocator.free(manifest.entry_point);

        if (manifest.dependencies.len > 0) {
            for (manifest.dependencies) |dep| allocator.free(dep);
            allocator.free(manifest.dependencies);
        }

        if (manifest.permissions.allowed_directories.len > 0) {
            for (manifest.permissions.allowed_directories) |dir| allocator.free(dir);
            allocator.free(manifest.permissions.allowed_directories);
        }

        if (manifest.permissions.blocked_directories.len > 0) {
            for (manifest.permissions.blocked_directories) |dir| allocator.free(dir);
            allocator.free(manifest.permissions.blocked_directories);
        }
    }

    fn validatePermissions(self: *PluginManager, permissions: *PluginManifest.PluginPermissions) !void {
        _ = self;
        const forbidden = &.{ "..", "~", "//" };
        for (permissions.allowed_directories) |dir| {
            for (forbidden) |marker| {
                if (std.mem.indexOf(u8, dir, marker)) |_| {
                    return Error.SecurityViolation;
                }
            }
        }
        for (permissions.blocked_directories) |dir| {
            for (forbidden) |marker| {
                if (std.mem.indexOf(u8, dir, marker)) |_| {
                    return Error.SecurityViolation;
                }
            }
        }
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

        var plugin_host = try host.Host.initWithSandbox(self.allocator, sandbox_config);
        var host_cleanup = true;
        defer if (host_cleanup) plugin_host.deinit();

        const compiled = plugin_host.compilePluginScript(plugin_info.script_content) catch |err| {
            return err;
        };

        var state = try self.allocator.create(GhostlangLoadedPlugin);
        errdefer self.cleanupGhostlangState(state);

        state.* = .{
            .runtime_plugin = runtime.Plugin{
                .id = plugin_info.manifest.id,
                .name = plugin_info.manifest.name,
                .version = plugin_info.manifest.version,
                .author = plugin_info.manifest.author,
                .description = plugin_info.manifest.description,
                .context = undefined,
                .user_data = null,
                .init_fn = ghostlangPluginInit,
                .deinit_fn = ghostlangPluginDeinit,
                .activate_fn = null,
                .deactivate_fn = null,
            },
            .host = plugin_host,
            .compiled = compiled,
            .host_deinitialized = false,
        };
        host_cleanup = false;

        state.runtime_plugin.user_data = state;

        try self.plugin_api.loadPlugin(&state.runtime_plugin);

        try self.loaded_plugin_states.put(plugin_info.manifest.id, state);
        plugin_info.state = state;
        plugin_info.loaded = true;

        std.log.info("Loaded plugin: {s} v{s} from {s}", .{
            plugin_info.manifest.name,
            plugin_info.manifest.version,
            plugin_info.plugin_path,
        });
    }

    pub fn unloadPlugin(self: *PluginManager, plugin_id: []const u8) !void {
        try self.plugin_api.unloadPlugin(plugin_id);
        if (self.loaded_plugin_states.fetchRemove(plugin_id)) |entry| {
            self.cleanupGhostlangState(entry.value);
        }
    }

    pub fn reloadPlugin(self: *PluginManager, plugin_info: *PluginInfo) !void {
        if (plugin_info.loaded) {
            try self.unloadPlugin(plugin_info.manifest.id);
            plugin_info.loaded = false;
            plugin_info.state = null;
        }

        // Reload script content
        self.allocator.free(plugin_info.script_content);
        plugin_info.script_content = try std.fs.cwd().readFileAlloc(self.allocator, plugin_info.plugin_path, 10 * 1024 * 1024);

        try self.loadPlugin(plugin_info);
    }

    pub fn getPluginStats(self: *PluginManager) host.Host.ExecutionStats {
        var aggregate = host.Host.ExecutionStats{};
        var iter = self.loaded_plugin_states.iterator();
        while (iter.next()) |entry| {
            const state = entry.value_ptr.*;
            const stats = state.host.getExecutionStats();
            aggregate.execution_count += stats.execution_count;
            aggregate.total_execution_time_ms += stats.total_execution_time_ms;
            aggregate.peak_memory_usage = @max(aggregate.peak_memory_usage, stats.peak_memory_usage);
            aggregate.file_operations_count += stats.file_operations_count;
            aggregate.network_requests_count += stats.network_requests_count;
            aggregate.sandbox_violations += stats.sandbox_violations;
            aggregate.last_execution_time = stats.last_execution_time;
        }
        return aggregate;
    }

    pub fn resetStats(self: *PluginManager) void {
        var iter = self.loaded_plugin_states.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.host.resetStats();
        }
    }

    fn cleanupGhostlangState(self: *PluginManager, state: *GhostlangLoadedPlugin) void {
        if (!state.host_deinitialized) {
            state.compiled.deinit();
            state.host.deinit();
            state.host_deinitialized = true;
        }
        self.allocator.destroy(state);
    }
};
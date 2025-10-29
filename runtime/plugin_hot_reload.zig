const std = @import("std");
const runtime = @import("mod.zig");

/// Hot-reload system for Grim plugins
/// Watches plugin files and reloads them when changed
pub const HotReloader = struct {
    allocator: std.mem.Allocator,
    plugin_manager: *runtime.PluginManager,
    watched_files: std.StringHashMap(WatchEntry),
    enabled: bool,

    pub const WatchEntry = struct {
        plugin_id: []const u8,
        file_path: []const u8,
        last_modified: i128,
    };

    pub fn init(allocator: std.mem.Allocator, manager: *runtime.PluginManager) !HotReloader {
        return HotReloader{
            .allocator = allocator,
            .plugin_manager = manager,
            .watched_files = std.StringHashMap(WatchEntry).init(allocator),
            .enabled = true,
        };
    }

    pub fn deinit(self: *HotReloader) void {
        var iter = self.watched_files.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.plugin_id);
            self.allocator.free(entry.value_ptr.file_path);
        }
        self.watched_files.deinit();
    }

    /// Watch a plugin file for changes
    pub fn watchPlugin(self: *HotReloader, plugin_id: []const u8, file_path: []const u8) !void {
        const stat = try std.fs.cwd().statFile(file_path);
        const mtime = stat.mtime;

        const entry = WatchEntry{
            .plugin_id = try self.allocator.dupe(u8, plugin_id),
            .file_path = try self.allocator.dupe(u8, file_path),
            .last_modified = mtime,
        };

        try self.watched_files.put(file_path, entry);
        std.log.debug("Watching plugin file: {s} (id: {s})", .{ file_path, plugin_id });
    }

    /// Unwatch a plugin file
    pub fn unwatchPlugin(self: *HotReloader, file_path: []const u8) void {
        if (self.watched_files.fetchRemove(file_path)) |kv| {
            self.allocator.free(kv.value.plugin_id);
            self.allocator.free(kv.value.file_path);
        }
    }

    /// Check all watched files for changes and reload if needed
    pub fn checkForChanges(self: *HotReloader) !void {
        if (!self.enabled) return;

        var to_reload = std.ArrayList([]const u8){};
        defer to_reload.deinit(self.allocator);

        var iter = self.watched_files.iterator();
        while (iter.next()) |entry| {
            const file_path = entry.value_ptr.file_path;
            const last_mtime = entry.value_ptr.last_modified;

            // Check if file still exists and get new mtime
            const stat = std.fs.cwd().statFile(file_path) catch |err| {
                if (err == error.FileNotFound) {
                    std.log.warn("Watched file no longer exists: {s}", .{file_path});
                    continue;
                }
                return err;
            };

            const new_mtime = stat.mtime;

            // File was modified?
            if (new_mtime > last_mtime) {
                std.log.info("Detected change in {s}", .{file_path});
                try to_reload.append(self.allocator, entry.value_ptr.plugin_id);
                // Update mtime
                entry.value_ptr.last_modified = new_mtime;
            }
        }

        // Reload changed plugins
        for (to_reload.items) |plugin_id| {
            self.reloadPlugin(plugin_id) catch |err| {
                std.log.err("Failed to reload plugin {s}: {}", .{ plugin_id, err });
            };
        }
    }

    /// Reload a specific plugin
    pub fn reloadPlugin(self: *HotReloader, plugin_id: []const u8) !void {
        std.log.info("Reloading plugin: {s}", .{plugin_id});

        // Find plugin in loaded plugins
        const plugin_state = self.plugin_manager.loaded_plugin_states.get(plugin_id) orelse {
            std.log.warn("Plugin {s} not loaded, cannot reload", .{plugin_id});
            return error.PluginNotLoaded;
        };

        // 1. Call teardown if it exists
        const teardown_result = self.callPluginTeardown(plugin_state) catch |err| {
            std.log.warn("Plugin {s} teardown failed: {}", .{ plugin_id, err });
            // Continue anyway - we still want to reload
        };
        _ = teardown_result;

        // 2. Unload plugin (remove commands, keymaps, events)
        try self.unloadPluginBindings(plugin_id);

        // 3. Reload plugin script from disk
        const script_path = try self.getPluginScriptPath(plugin_id);
        defer self.allocator.free(script_path);

        const new_script = try std.fs.cwd().readFileAlloc(
            self.allocator,
            script_path,
            10 * 1024 * 1024, // 10MB max
        );
        defer self.allocator.free(new_script);

        // 4. Re-compile and execute new script
        const compiled = try plugin_state.host.compile(new_script);
        plugin_state.compiled.deinit();
        plugin_state.compiled = compiled;

        // 5. Call setup() to re-register commands/keymaps
        try self.callPluginSetup(plugin_state);

        std.log.info("Plugin {s} reloaded successfully", .{plugin_id});
    }

    /// Get the script path for a plugin
    fn getPluginScriptPath(self: *HotReloader, plugin_id: []const u8) ![]const u8 {
        // Search watched files for this plugin
        var iter = self.watched_files.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.plugin_id, plugin_id)) {
                return try self.allocator.dupe(u8, entry.value_ptr.file_path);
            }
        }
        return error.PluginFileNotFound;
    }

    /// Call plugin's teardown() function
    fn callPluginTeardown(self: *HotReloader, plugin_state: anytype) !void {
        _ = self;
        // Call the Ghostlang teardown() function if it exists
        const result = plugin_state.host.call(plugin_state.compiled, "teardown", &.{}) catch |err| {
            if (err == error.FunctionNotFound) {
                // teardown() is optional
                return;
            }
            return err;
        };
        _ = result;
    }

    /// Call plugin's setup() function
    fn callPluginSetup(self: *HotReloader, plugin_state: anytype) !void {
        _ = self;
        const result = plugin_state.host.call(plugin_state.compiled, "setup", &.{}) catch |err| {
            std.log.err("Plugin setup() failed: {}", .{err});
            return err;
        };
        _ = result;
    }

    /// Unload plugin bindings (commands, keymaps, events)
    fn unloadPluginBindings(self: *HotReloader, plugin_id: []const u8) !void {
        // Remove commands registered by this plugin
        self.plugin_manager.plugin_api.command_registry.unregister(self.allocator, plugin_id);

        // Remove keymaps registered by this plugin
        self.plugin_manager.plugin_api.keystroke_handlers.unregister(plugin_id);

        // Remove event handlers registered by this plugin
        self.plugin_manager.plugin_api.event_handlers.unregister(plugin_id);

        std.log.debug("Unloaded bindings for plugin: {s}", .{plugin_id});
    }

    /// Enable/disable hot-reloading
    pub fn setEnabled(self: *HotReloader, enabled: bool) void {
        self.enabled = enabled;
        std.log.info("Hot-reload {s}", .{if (enabled) "enabled" else "disabled"});
    }

    /// Manually trigger reload of a plugin (for testing or CLI command)
    pub fn triggerReload(self: *HotReloader, plugin_id: []const u8) !void {
        try self.reloadPlugin(plugin_id);
    }
};

/// Convenience wrapper for periodic checking
pub fn runHotReloadLoop(
    allocator: std.mem.Allocator,
    manager: *runtime.PluginManager,
    check_interval_ms: u64,
) !void {
    var reloader = try HotReloader.init(allocator, manager);
    defer reloader.deinit();

    // Watch all loaded plugins
    var iter = manager.loaded_plugin_states.iterator();
    while (iter.next()) |entry| {
        const plugin_id = entry.key_ptr.*;
        // Get plugin file path from manager
        // TODO: Store file paths in plugin manager for easy access
        _ = plugin_id;
    }

    // Polling loop
    while (true) {
        try reloader.checkForChanges();
        std.time.sleep(check_interval_ms * std.time.ns_per_ms);
    }
}

test "hot reloader init and deinit" {
    const allocator = std.testing.allocator;

    // Can't fully test without PluginManager, but ensure init/deinit works
    // This is a placeholder - real tests need integration with plugin manager
    _ = allocator;
}

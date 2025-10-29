//! Plugin Hot Reload System
//! Watches plugin files and triggers reload on changes

const std = @import("std");
const FileWatcher = @import("file_watcher.zig").FileWatcher;
const PluginLoader = @import("plugin_ffi.zig").PluginLoader;

pub const HotReloadManager = struct {
    allocator: std.mem.Allocator,
    watcher: *FileWatcher,
    plugin_loader: *PluginLoader,
    watched_plugins: std.StringHashMap([]const u8), // name -> path

    pub fn init(allocator: std.mem.Allocator, plugin_loader: *PluginLoader) !*HotReloadManager {
        const self = try allocator.create(HotReloadManager);
        errdefer allocator.destroy(self);

        const watcher = try FileWatcher.init(allocator);
        errdefer watcher.deinit();

        self.* = .{
            .allocator = allocator,
            .watcher = watcher,
            .plugin_loader = plugin_loader,
            .watched_plugins = std.StringHashMap([]const u8).init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *HotReloadManager) void {
        var iter = self.watched_plugins.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.watched_plugins.deinit();
        self.watcher.deinit();
        self.allocator.destroy(self);
    }

    /// Watch a plugin for changes
    pub fn watchPlugin(self: *HotReloadManager, name: []const u8, path: []const u8) !void {
        try self.watcher.watch(path);

        const name_copy = try self.allocator.dupe(u8, name);
        const path_copy = try self.allocator.dupe(u8, path);

        try self.watched_plugins.put(name_copy, path_copy);

        std.log.info("Watching plugin {s} at {s} for hot reload", .{ name, path });
    }

    /// Check for changes and reload if needed
    pub fn checkAndReload(self: *HotReloadManager) !void {
        const events = try self.watcher.poll();
        defer self.allocator.free(events);

        for (events) |event| {
            // Find which plugin this path belongs to
            var iter = self.watched_plugins.iterator();
            while (iter.next()) |entry| {
                const plugin_name = entry.key_ptr.*;
                const plugin_path = entry.value_ptr.*;

                if (std.mem.eql(u8, event.path, plugin_path)) {
                    std.log.info("Detected changes in {s}, reloading...", .{plugin_name});

                    self.plugin_loader.reloadPlugin(plugin_name, plugin_path) catch |err| {
                        std.log.err("Failed to reload {s}: {}", .{ plugin_name, err });
                    };
                }
            }
        }
    }
};

const std = @import("std");
const config_mod = @import("config.zig");

/// Config file watcher for hot-reload
/// Monitors ~/.config/grim/config.grim for changes and reloads automatically
pub const ConfigWatcher = struct {
    allocator: std.mem.Allocator,
    config: *config_mod.Config,
    config_path: []const u8,
    last_modified_time: i128,
    check_interval_ms: u64,
    callback: ?*const fn (config: *config_mod.Config) void,

    pub fn init(
        allocator: std.mem.Allocator,
        config: *config_mod.Config,
    ) !ConfigWatcher {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

        const config_path = try std.fs.path.join(allocator, &.{
            home,
            ".config",
            "grim",
            "config.grim",
        });

        const last_modified = getFileModTime(config_path) catch 0;

        return ConfigWatcher{
            .allocator = allocator,
            .config = config,
            .config_path = config_path,
            .last_modified_time = last_modified,
            .check_interval_ms = 1000, // Check every second
            .callback = null,
        };
    }

    pub fn deinit(self: *ConfigWatcher) void {
        self.allocator.free(self.config_path);
    }

    /// Set callback to be called when config changes
    pub fn setCallback(self: *ConfigWatcher, callback: *const fn (config: *config_mod.Config) void) void {
        self.callback = callback;
    }

    /// Check if config file has changed and reload if needed
    /// Returns true if config was reloaded
    pub fn checkAndReload(self: *ConfigWatcher) !bool {
        const current_mod_time = getFileModTime(self.config_path) catch {
            // File doesn't exist or can't be read
            return false;
        };

        if (current_mod_time > self.last_modified_time) {
            // File has been modified, reload
            try self.config.loadFromFile(self.config_path);
            self.last_modified_time = current_mod_time;

            // Call callback if set
            if (self.callback) |cb| {
                cb(self.config);
            }

            return true;
        }

        return false;
    }

    /// Background watcher thread (optional)
    pub fn startWatchThread(self: *ConfigWatcher) !std.Thread {
        return try std.Thread.spawn(.{}, watchLoop, .{self});
    }

    fn watchLoop(self: *ConfigWatcher) void {
        while (true) {
            self.checkAndReload() catch |err| {
                std.log.warn("Config reload failed: {}", .{err});
            };

            std.time.sleep(self.check_interval_ms * std.time.ns_per_ms);
        }
    }

    fn getFileModTime(path: []const u8) !i128 {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        return stat.mtime;
    }
};

/// Config change detector for manual polling
pub const ConfigChangeDetector = struct {
    config_path: []const u8,
    last_check_time: i64,
    last_modified_time: i128,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ConfigChangeDetector {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

        const config_path = try std.fs.path.join(allocator, &.{
            home,
            ".config",
            "grim",
            "config.grim",
        });

        const last_modified = ConfigWatcher.getFileModTime(config_path) catch 0;

        return ConfigChangeDetector{
            .allocator = allocator,
            .config_path = config_path,
            .last_check_time = std.time.timestamp(),
            .last_modified_time = last_modified,
        };
    }

    pub fn deinit(self: *ConfigChangeDetector) void {
        self.allocator.free(self.config_path);
    }

    /// Check if config file has changed
    /// This is a lightweight check suitable for every render loop
    pub fn hasChanged(self: *ConfigChangeDetector) bool {
        const now = std.time.timestamp();

        // Only check once per second to avoid excessive syscalls
        if (now - self.last_check_time < 1) {
            return false;
        }

        self.last_check_time = now;

        const current_mod_time = ConfigWatcher.getFileModTime(self.config_path) catch {
            return false;
        };

        if (current_mod_time > self.last_modified_time) {
            self.last_modified_time = current_mod_time;
            return true;
        }

        return false;
    }
};

test "ConfigWatcher init" {
    const allocator = std.testing.allocator;

    var config = config_mod.Config.init(allocator);
    defer config.deinit();

    var watcher = try ConfigWatcher.init(allocator, &config);
    defer watcher.deinit();

    try std.testing.expect(watcher.check_interval_ms == 1000);
}

test "ConfigChangeDetector init" {
    const allocator = std.testing.allocator;

    var detector = try ConfigChangeDetector.init(allocator);
    defer detector.deinit();

    const changed = detector.hasChanged();
    _ = changed; // First call may or may not detect changes
}

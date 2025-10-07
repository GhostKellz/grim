const std = @import("std");

/// Binary cache system for pre-compiled plugins
/// Innovation: Faster updates than LazyVim's git-only approach

pub const PluginCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !PluginCache {
        // Determine cache directory
        const cache_dir = try getCacheDir(allocator);

        // Ensure cache directory exists
        std.fs.cwd().makePath(cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                std.log.warn("Failed to create cache dir {s}: {}", .{ cache_dir, err });
            }
        };

        return PluginCache{
            .allocator = allocator,
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *PluginCache) void {
        self.allocator.free(self.cache_dir);
    }

    /// Get cache directory path
    fn getCacheDir(allocator: std.mem.Allocator) ![]const u8 {
        if (std.posix.getenv("HOME")) |home| {
            return std.fs.path.join(allocator, &.{ home, ".cache", "grim", "plugins" });
        }
        return std.fs.path.join(allocator, &.{ "/tmp", "grim-plugin-cache" });
    }

    /// Check if plugin binary exists in cache
    pub fn has(self: *PluginCache, name: []const u8, version: []const u8) bool {
        const cache_path = self.getCachePath(name, version) catch return false;
        defer self.allocator.free(cache_path);

        std.fs.cwd().access(cache_path, .{}) catch return false;
        return true;
    }

    /// Get path to cached plugin binary
    pub fn getCachePath(self: *PluginCache, name: []const u8, version: []const u8) ![]const u8 {
        const platform = try getPlatformString(self.allocator);
        defer self.allocator.free(platform);

        // Format: ~/.cache/grim/plugins/{name}-{version}-{platform}
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}-{s}-{s}",
            .{ name, version, platform },
        );
        defer self.allocator.free(filename);

        return std.fs.path.join(self.allocator, &.{ self.cache_dir, filename });
    }

    /// Store plugin binary in cache
    pub fn store(
        self: *PluginCache,
        name: []const u8,
        version: []const u8,
        data: []const u8,
    ) !void {
        const cache_path = try self.getCachePath(name, version);
        defer self.allocator.free(cache_path);

        std.log.info("Caching plugin: {s} v{s}", .{ name, version });

        const file = try std.fs.cwd().createFile(cache_path, .{});
        defer file.close();

        try file.writeAll(data);

        std.log.debug("Cached to: {s}", .{cache_path});
    }

    /// Retrieve plugin binary from cache
    pub fn retrieve(
        self: *PluginCache,
        name: []const u8,
        version: []const u8,
    ) ![]const u8 {
        const cache_path = try self.getCachePath(name, version);
        defer self.allocator.free(cache_path);

        std.log.info("Loading from cache: {s} v{s}", .{ name, version });

        return std.fs.cwd().readFileAlloc(cache_path, self.allocator, .limited(100 * 1024 * 1024)); // 100MB max
    }

    /// Clear cache for specific plugin
    pub fn clear(self: *PluginCache, name: []const u8, version: []const u8) !void {
        const cache_path = try self.getCachePath(name, version);
        defer self.allocator.free(cache_path);

        std.fs.cwd().deleteFile(cache_path) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };

        std.log.info("Cleared cache: {s} v{s}", .{ name, version });
    }

    /// Clear entire plugin cache
    pub fn clearAll(self: *PluginCache) !void {
        std.log.info("Clearing entire plugin cache...");

        var dir = try std.fs.cwd().openIterableDir(self.cache_dir, .{});
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                const path = try std.fs.path.join(self.allocator, &.{ self.cache_dir, entry.name });
                defer self.allocator.free(path);

                std.fs.cwd().deleteFile(path) catch {};
            }
        }

        std.log.info("Cache cleared");
    }

    /// Get cache size in bytes
    pub fn getSize(self: *PluginCache) !u64 {
        var total: u64 = 0;

        var dir = try std.fs.cwd().openIterableDir(self.cache_dir, .{});
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                const path = try std.fs.path.join(self.allocator, &.{ self.cache_dir, entry.name });
                defer self.allocator.free(path);

                const file = std.fs.cwd().openFile(path, .{}) catch continue;
                defer file.close();

                const stat = try file.stat();
                total += stat.size;
            }
        }

        return total;
    }
};

/// Get platform string for cache key
fn getPlatformString(allocator: std.mem.Allocator) ![]const u8 {
    const os_name = @tagName(std.Target.current.os.tag);
    const arch_name = @tagName(std.Target.current.cpu.arch);

    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ os_name, arch_name });
}

/// Binary cache URL builder
pub const CacheURL = struct {
    base_url: []const u8,

    pub fn init(base_url: []const u8) CacheURL {
        return .{ .base_url = base_url };
    }

    /// Build URL for plugin binary
    pub fn buildURL(
        self: CacheURL,
        allocator: std.mem.Allocator,
        name: []const u8,
        version: []const u8,
    ) ![]const u8 {
        const platform = try getPlatformString(allocator);
        defer allocator.free(platform);

        // Format: https://plugins.grim.dev/{name}/{version}/{platform}/plugin.tar.gz
        return std.fmt.allocPrint(
            allocator,
            "{s}/{s}/{s}/{s}/plugin.tar.gz",
            .{ self.base_url, name, version, platform },
        );
    }
};

/// Update strategy for plugins
pub const UpdateStrategy = enum {
    git,         // Always use git clone/pull
    binary,      // Always use pre-compiled binaries
    smart,       // Try binary first, fallback to git
    dev,         // Use local development version (symlink)

    pub fn fromString(s: []const u8) UpdateStrategy {
        if (std.mem.eql(u8, s, "git")) return .git;
        if (std.mem.eql(u8, s, "binary")) return .binary;
        if (std.mem.eql(u8, s, "dev")) return .dev;
        return .smart; // Default
    }
};

test "cache path generation" {
    const allocator = std.testing.allocator;

    var cache = try PluginCache.init(allocator);
    defer cache.deinit();

    const path = try cache.getCachePath("telescope", "1.0.0");
    defer allocator.free(path);

    // Should contain plugin name, version, and platform
    try std.testing.expect(std.mem.indexOf(u8, path, "telescope") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "1.0.0") != null);
}

test "platform string" {
    const allocator = std.testing.allocator;

    const platform = try getPlatformString(allocator);
    defer allocator.free(platform);

    // Should contain OS and architecture
    try std.testing.expect(platform.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, platform, "-") != null);
}

const std = @import("std");

/// File watcher for detecting external file modifications
/// Uses inotify (Linux) or kqueue (BSD/macOS) for efficient monitoring
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watched_files: std.StringHashMap(WatchedFile),
    callbacks: std.ArrayList(Callback),

    const WatchedFile = struct {
        path: []const u8,
        last_modified: i128,
        watch_descriptor: i32,
    };

    const Callback = struct {
        ctx: *anyopaque,
        fn_ptr: *const fn (ctx: *anyopaque, path: []const u8) anyerror!void,
    };

    pub fn init(allocator: std.mem.Allocator) FileWatcher {
        return FileWatcher{
            .allocator = allocator,
            .watched_files = std.StringHashMap(WatchedFile).init(allocator),
            .callbacks = std.ArrayList(Callback).init(allocator),
        };
    }

    pub fn deinit(self: *FileWatcher) void {
        var iter = self.watched_files.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.watched_files.deinit();
        self.callbacks.deinit();
    }

    /// Register a callback to be invoked when files change
    pub fn registerCallback(self: *FileWatcher, ctx: *anyopaque, callback: *const fn (ctx: *anyopaque, path: []const u8) anyerror!void) !void {
        try self.callbacks.append(.{
            .ctx = ctx,
            .fn_ptr = callback,
        });
    }

    /// Add a file to watch for modifications
    pub fn watch(self: *FileWatcher, path: []const u8) !void {
        const stat = try std.fs.cwd().statFile(path);
        const last_modified = stat.mtime;

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        try self.watched_files.put(owned_path, .{
            .path = owned_path,
            .last_modified = last_modified,
            .watch_descriptor = -1, // Placeholder for inotify/kqueue descriptor
        });
    }

    /// Remove a file from watch list
    pub fn unwatch(self: *FileWatcher, path: []const u8) void {
        if (self.watched_files.fetchRemove(path)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    /// Poll watched files for changes (simple polling implementation)
    /// For production, this should use inotify/kqueue for event-driven monitoring
    pub fn poll(self: *FileWatcher) !void {
        var iter = self.watched_files.iterator();
        while (iter.next()) |entry| {
            const file_info = entry.value_ptr;

            const stat = std.fs.cwd().statFile(file_info.path) catch |err| {
                if (err == error.FileNotFound) {
                    // File was deleted
                    try self.notifyCallbacks(file_info.path);
                    continue;
                }
                return err;
            };

            if (stat.mtime != file_info.last_modified) {
                // File was modified
                file_info.last_modified = stat.mtime;
                try self.notifyCallbacks(file_info.path);
            }
        }
    }

    fn notifyCallbacks(self: *FileWatcher, path: []const u8) !void {
        for (self.callbacks.items) |callback| {
            try callback.fn_ptr(callback.ctx, path);
        }
    }

    /// Check if a file is being watched
    pub fn isWatching(self: *FileWatcher, path: []const u8) bool {
        return self.watched_files.contains(path);
    }

    /// Get count of watched files
    pub fn watchCount(self: *FileWatcher) usize {
        return self.watched_files.count();
    }
};

test "file watcher basic" {
    const allocator = std.testing.allocator;

    var watcher = FileWatcher.init(allocator);
    defer watcher.deinit();

    // Create temp file
    const test_file = "test_watcher.tmp";
    var file = try std.fs.cwd().createFile(test_file, .{});
    file.close();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Watch the file
    try watcher.watch(test_file);
    try std.testing.expect(watcher.isWatching(test_file));
    try std.testing.expectEqual(@as(usize, 1), watcher.watchCount());

    // Unwatch
    watcher.unwatch(test_file);
    try std.testing.expect(!watcher.isWatching(test_file));
    try std.testing.expectEqual(@as(usize, 0), watcher.watchCount());
}

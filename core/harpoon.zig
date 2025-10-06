const std = @import("std");

/// Harpoon-style file pinning for quick navigation
/// Pin up to 5 files and jump between them with number keys
pub const Harpoon = struct {
    allocator: std.mem.Allocator,
    pinned_files: [5]?PinnedFile,
    current_idx: usize,

    pub const PinnedFile = struct {
        path: []u8,
        display_name: []u8,
        cursor_line: usize,
        cursor_col: usize,
    };

    pub fn init(allocator: std.mem.Allocator) Harpoon {
        return .{
            .allocator = allocator,
            .pinned_files = [_]?PinnedFile{null} ** 5,
            .current_idx = 0,
        };
    }

    pub fn deinit(self: *Harpoon) void {
        for (self.pinned_files) |maybe_file| {
            if (maybe_file) |file| {
                self.allocator.free(file.path);
                self.allocator.free(file.display_name);
            }
        }
    }

    /// Pin a file to a slot (0-4)
    pub fn pin(self: *Harpoon, slot: usize, path: []const u8, line: usize, col: usize) !void {
        if (slot >= 5) return error.InvalidSlot;

        // Free old file if exists
        if (self.pinned_files[slot]) |old_file| {
            self.allocator.free(old_file.path);
            self.allocator.free(old_file.display_name);
        }

        // Get display name (just filename)
        const display_name = std.fs.path.basename(path);

        self.pinned_files[slot] = .{
            .path = try self.allocator.dupe(u8, path),
            .display_name = try self.allocator.dupe(u8, display_name),
            .cursor_line = line,
            .cursor_col = col,
        };
    }

    /// Pin current file to next available slot
    pub fn pinNext(self: *Harpoon, path: []const u8, line: usize, col: usize) !usize {
        // Find first empty slot
        for (self.pinned_files, 0..) |maybe_file, idx| {
            if (maybe_file == null) {
                try self.pin(idx, path, line, col);
                return idx;
            }
        }

        // No empty slots, use current_idx and cycle
        const slot = self.current_idx;
        try self.pin(slot, path, line, col);
        self.current_idx = (self.current_idx + 1) % 5;
        return slot;
    }

    /// Unpin a file from a slot
    pub fn unpin(self: *Harpoon, slot: usize) void {
        if (slot >= 5) return;

        if (self.pinned_files[slot]) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.display_name);
            self.pinned_files[slot] = null;
        }
    }

    /// Get pinned file at slot
    pub fn get(self: *Harpoon, slot: usize) ?PinnedFile {
        if (slot >= 5) return null;
        return self.pinned_files[slot];
    }

    /// Get all pinned files
    pub fn getAll(self: *Harpoon) []const ?PinnedFile {
        return &self.pinned_files;
    }

    /// Update cursor position for a pinned file
    pub fn updateCursor(self: *Harpoon, slot: usize, line: usize, col: usize) void {
        if (slot >= 5) return;

        if (self.pinned_files[slot]) |*file| {
            file.cursor_line = line;
            file.cursor_col = col;
        }
    }

    /// Find slot for a given path (returns null if not pinned)
    pub fn findSlot(self: *Harpoon, path: []const u8) ?usize {
        for (self.pinned_files, 0..) |maybe_file, idx| {
            if (maybe_file) |file| {
                if (std.mem.eql(u8, file.path, path)) {
                    return idx;
                }
            }
        }
        return null;
    }

    /// Clear all pins
    pub fn clearAll(self: *Harpoon) void {
        for (0..5) |idx| {
            self.unpin(idx);
        }
    }

    /// Save harpoon state to file
    pub fn save(self: *Harpoon, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var writer = file.writer();

        for (self.pinned_files, 0..) |maybe_file, idx| {
            if (maybe_file) |pinned| {
                try writer.print("{d}|{s}|{d}|{d}\n", .{
                    idx,
                    pinned.path,
                    pinned.cursor_line,
                    pinned.cursor_col,
                });
            }
        }
    }

    /// Load harpoon state from file
    pub fn load(self: *Harpoon, path: []const u8) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch return;
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var parts = std.mem.split(u8, line, "|");
            const idx_str = parts.next() orelse continue;
            const file_path = parts.next() orelse continue;
            const line_str = parts.next() orelse continue;
            const col_str = parts.next() orelse continue;

            const idx = std.fmt.parseInt(usize, idx_str, 10) catch continue;
            const cursor_line = std.fmt.parseInt(usize, line_str, 10) catch 0;
            const cursor_col = std.fmt.parseInt(usize, col_str, 10) catch 0;

            try self.pin(idx, file_path, cursor_line, cursor_col);
        }
    }
};

test "harpoon basic" {
    const allocator = std.testing.allocator;

    var harpoon = Harpoon.init(allocator);
    defer harpoon.deinit();

    // Pin a file
    try harpoon.pin(0, "/tmp/test.zig", 10, 5);

    // Check it's pinned
    const pinned = harpoon.get(0);
    try std.testing.expect(pinned != null);
    try std.testing.expectEqualStrings("/tmp/test.zig", pinned.?.path);
    try std.testing.expectEqual(@as(usize, 10), pinned.?.cursor_line);

    // Unpin
    harpoon.unpin(0);
    try std.testing.expect(harpoon.get(0) == null);
}

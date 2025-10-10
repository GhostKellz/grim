const std = @import("std");
const core = @import("core");
const syntax = @import("syntax");
const editor_mod = @import("editor.zig");

/// Multi-Buffer Management System
/// Manages multiple buffers, buffer switching, and tab line
pub const BufferManager = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(Buffer),
    active_buffer_id: u32 = 0,
    next_buffer_id: u32 = 1,

    pub const Buffer = struct {
        id: u32,
        editor: editor_mod.Editor,
        file_path: ?[]const u8 = null,
        modified: bool = false,
        display_name: []const u8,
        last_accessed: i64,

        pub fn init(allocator: std.mem.Allocator, id: u32) !Buffer {
            const editor = try editor_mod.Editor.init(allocator);
            const display_name = try std.fmt.allocPrint(allocator, "[No Name {d}]", .{id});

            return Buffer{
                .id = id,
                .editor = editor,
                .display_name = display_name,
                .last_accessed = std.time.timestamp(),
            };
        }

        pub fn deinit(self: *Buffer, allocator: std.mem.Allocator) void {
            self.editor.deinit();
            if (self.file_path) |path| {
                allocator.free(path);
            }
            allocator.free(self.display_name);
        }

        pub fn setFilePath(self: *Buffer, allocator: std.mem.Allocator, path: []const u8) !void {
            // Free old path
            if (self.file_path) |old_path| {
                allocator.free(old_path);
            }

            // Set new path and update display name
            self.file_path = try allocator.dupe(u8, path);

            // Update display name to basename
            const basename = std.fs.path.basename(path);
            allocator.free(self.display_name);
            self.display_name = try allocator.dupe(u8, basename);
        }

        pub fn markModified(self: *Buffer) void {
            self.modified = true;
        }

        pub fn markSaved(self: *Buffer) void {
            self.modified = false;
        }

        pub fn updateAccessTime(self: *Buffer) void {
            self.last_accessed = std.time.timestamp();
        }
    };

    pub const TabItem = struct {
        id: u32,
        display_name: []const u8,
        modified: bool,
        is_active: bool,
    };

    pub const BufferInfo = struct {
        id: u32,
        display_name: []const u8,
        file_path: ?[]const u8,
        modified: bool,
        line_count: usize,
        language: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) !BufferManager {
        var buffers = std.ArrayList(Buffer).init(allocator);

        // Create initial buffer
        const initial_buffer = try Buffer.init(allocator, 0);
        try buffers.append(initial_buffer);

        return BufferManager{
            .allocator = allocator,
            .buffers = buffers,
        };
    }

    pub fn deinit(self: *BufferManager) void {
        for (self.buffers.items) |*buffer| {
            buffer.deinit(self.allocator);
        }
        self.buffers.deinit();
    }

    /// Get the currently active buffer
    pub fn getActiveBuffer(self: *BufferManager) ?*Buffer {
        for (self.buffers.items) |*buffer| {
            if (buffer.id == self.active_buffer_id) {
                return buffer;
            }
        }
        return null;
    }

    /// Get buffer by ID
    pub fn getBuffer(self: *BufferManager, buffer_id: u32) ?*Buffer {
        for (self.buffers.items) |*buffer| {
            if (buffer.id == buffer_id) {
                return buffer;
            }
        }
        return null;
    }

    /// Create a new buffer
    pub fn createBuffer(self: *BufferManager) !u32 {
        const id = self.next_buffer_id;
        self.next_buffer_id += 1;

        const new_buffer = try Buffer.init(self.allocator, id);
        try self.buffers.append(new_buffer);

        return id;
    }

    /// Create a buffer from file
    pub fn openFile(self: *BufferManager, path: []const u8) !u32 {
        // Check if file is already open
        for (self.buffers.items) |*buffer| {
            if (buffer.file_path) |existing_path| {
                if (std.mem.eql(u8, existing_path, path)) {
                    // File already open, switch to it
                    self.active_buffer_id = buffer.id;
                    buffer.updateAccessTime();
                    return buffer.id;
                }
            }
        }

        // Create new buffer
        const id = try self.createBuffer();
        const buffer = self.getBuffer(id).?;

        // Load file
        try buffer.editor.loadFile(path);
        try buffer.setFilePath(self.allocator, path);
        buffer.updateAccessTime();

        // Switch to new buffer
        self.active_buffer_id = id;

        return id;
    }

    /// Save active buffer
    pub fn saveActiveBuffer(self: *BufferManager) !void {
        const buffer = self.getActiveBuffer() orelse return error.NoActiveBuffer;

        const path = buffer.file_path orelse return error.NoFilePath;
        try buffer.editor.saveFile(path);
        buffer.markSaved();
    }

    /// Save buffer as...
    pub fn saveBufferAs(self: *BufferManager, buffer_id: u32, path: []const u8) !void {
        const buffer = self.getBuffer(buffer_id) orelse return error.BufferNotFound;

        try buffer.editor.saveFile(path);
        try buffer.setFilePath(self.allocator, path);
        buffer.markSaved();
    }

    /// Close a buffer
    pub fn closeBuffer(self: *BufferManager, buffer_id: u32) !void {
        // Don't close the last buffer
        if (self.buffers.items.len == 1) {
            return error.CannotCloseLastBuffer;
        }

        // Find buffer index
        var buffer_index: ?usize = null;
        for (self.buffers.items, 0..) |buffer, i| {
            if (buffer.id == buffer_id) {
                buffer_index = i;
                break;
            }
        }

        const index = buffer_index orelse return error.BufferNotFound;

        // If closing active buffer, switch to next/previous
        if (buffer_id == self.active_buffer_id) {
            if (index > 0) {
                self.active_buffer_id = self.buffers.items[index - 1].id;
            } else if (self.buffers.items.len > 1) {
                self.active_buffer_id = self.buffers.items[1].id;
            }
        }

        // Remove and deinit buffer
        var removed_buffer = self.buffers.orderedRemove(index);
        removed_buffer.deinit(self.allocator);
    }

    /// Switch to next buffer
    pub fn nextBuffer(self: *BufferManager) void {
        if (self.buffers.items.len <= 1) return;

        var current_index: ?usize = null;
        for (self.buffers.items, 0..) |buffer, i| {
            if (buffer.id == self.active_buffer_id) {
                current_index = i;
                break;
            }
        }

        if (current_index) |index| {
            const next_index = (index + 1) % self.buffers.items.len;
            self.active_buffer_id = self.buffers.items[next_index].id;
            self.buffers.items[next_index].updateAccessTime();
        }
    }

    /// Switch to previous buffer
    pub fn previousBuffer(self: *BufferManager) void {
        if (self.buffers.items.len <= 1) return;

        var current_index: ?usize = null;
        for (self.buffers.items, 0..) |buffer, i| {
            if (buffer.id == self.active_buffer_id) {
                current_index = i;
                break;
            }
        }

        if (current_index) |index| {
            const prev_index = if (index == 0) self.buffers.items.len - 1 else index - 1;
            self.active_buffer_id = self.buffers.items[prev_index].id;
            self.buffers.items[prev_index].updateAccessTime();
        }
    }

    /// Switch to specific buffer
    pub fn switchToBuffer(self: *BufferManager, buffer_id: u32) !void {
        // Verify buffer exists
        const buffer = self.getBuffer(buffer_id) orelse return error.BufferNotFound;

        self.active_buffer_id = buffer_id;
        buffer.updateAccessTime();
    }

    /// Get tab line items for UI rendering
    pub fn getTabLine(self: *BufferManager, allocator: std.mem.Allocator) ![]TabItem {
        var tabs = try allocator.alloc(TabItem, self.buffers.items.len);

        for (self.buffers.items, 0..) |buffer, i| {
            tabs[i] = .{
                .id = buffer.id,
                .display_name = buffer.display_name,
                .modified = buffer.modified,
                .is_active = buffer.id == self.active_buffer_id,
            };
        }

        return tabs;
    }

    /// Get buffer list for picker/selector UI
    pub fn getBufferList(self: *BufferManager, allocator: std.mem.Allocator) ![]BufferInfo {
        var infos = try allocator.alloc(BufferInfo, self.buffers.items.len);

        for (self.buffers.items, 0..) |buffer, i| {
            infos[i] = .{
                .id = buffer.id,
                .display_name = buffer.display_name,
                .file_path = buffer.file_path,
                .modified = buffer.modified,
                .line_count = self.countLines(&buffer.editor.rope),
                .language = buffer.editor.getLanguageName(),
            };
        }

        return infos;
    }

    /// Get list of modified buffers
    pub fn getModifiedBuffers(self: *BufferManager, allocator: std.mem.Allocator) ![]u32 {
        var modified = std.ArrayList(u32).init(allocator);
        defer modified.deinit();

        for (self.buffers.items) |buffer| {
            if (buffer.modified) {
                try modified.append(buffer.id);
            }
        }

        return modified.toOwnedSlice();
    }

    /// Check if there are unsaved changes
    pub fn hasUnsavedChanges(self: *BufferManager) bool {
        for (self.buffers.items) |buffer| {
            if (buffer.modified) return true;
        }
        return false;
    }

    /// Sort buffers by last accessed (for MRU - Most Recently Used)
    pub fn sortByMRU(self: *BufferManager) void {
        std.mem.sort(Buffer, self.buffers.items, {}, struct {
            fn lessThan(_: void, a: Buffer, b: Buffer) bool {
                return a.last_accessed > b.last_accessed;
            }
        }.lessThan);
    }

    // Helper functions

    fn countLines(self: *BufferManager, rope: *const core.Rope) usize {
        _ = self;
        const content = rope.slice(.{ .start = 0, .end = rope.len() }) catch return 0;

        var count: usize = 1;
        for (content) |ch| {
            if (ch == '\n') count += 1;
        }
        return count;
    }
};

test "BufferManager init and basic operations" {
    const allocator = std.testing.allocator;

    var manager = try BufferManager.init(allocator);
    defer manager.deinit();

    // Should have one initial buffer
    try std.testing.expectEqual(@as(usize, 1), manager.buffers.items.len);
    try std.testing.expectEqual(@as(u32, 0), manager.active_buffer_id);
}

test "BufferManager create and switch buffers" {
    const allocator = std.testing.allocator;

    var manager = try BufferManager.init(allocator);
    defer manager.deinit();

    // Create second buffer
    const buf2 = try manager.createBuffer();
    try std.testing.expectEqual(@as(u32, 1), buf2);
    try std.testing.expectEqual(@as(usize, 2), manager.buffers.items.len);

    // Switch to buffer 2
    try manager.switchToBuffer(buf2);
    try std.testing.expectEqual(buf2, manager.active_buffer_id);

    // Switch back
    try manager.switchToBuffer(0);
    try std.testing.expectEqual(@as(u32, 0), manager.active_buffer_id);
}

test "BufferManager next/previous navigation" {
    const allocator = std.testing.allocator;

    var manager = try BufferManager.init(allocator);
    defer manager.deinit();

    _ = try manager.createBuffer(); // id=1
    _ = try manager.createBuffer(); // id=2

    // Current: 0, next should be 1
    manager.nextBuffer();
    try std.testing.expectEqual(@as(u32, 1), manager.active_buffer_id);

    // Current: 1, next should be 2
    manager.nextBuffer();
    try std.testing.expectEqual(@as(u32, 2), manager.active_buffer_id);

    // Current: 2, next wraps to 0
    manager.nextBuffer();
    try std.testing.expectEqual(@as(u32, 0), manager.active_buffer_id);

    // Test previous
    manager.previousBuffer();
    try std.testing.expectEqual(@as(u32, 2), manager.active_buffer_id);
}

test "BufferManager close buffer" {
    const allocator = std.testing.allocator;

    var manager = try BufferManager.init(allocator);
    defer manager.deinit();

    const buf1 = try manager.createBuffer();
    const buf2 = try manager.createBuffer();

    // Switch to buf1 and close it
    try manager.switchToBuffer(buf1);
    try manager.closeBuffer(buf1);

    // Should have 2 buffers left (0 and 2)
    try std.testing.expectEqual(@as(usize, 2), manager.buffers.items.len);

    // Active should have switched (to buf0 since it was before buf1)
    try std.testing.expect(manager.active_buffer_id != buf1);

    // Cannot close last buffer
    try manager.closeBuffer(buf2);
    try std.testing.expectEqual(@as(usize, 1), manager.buffers.items.len);

    const result = manager.closeBuffer(manager.active_buffer_id);
    try std.testing.expectError(error.CannotCloseLastBuffer, result);
}

test "BufferManager tab line" {
    const allocator = std.testing.allocator;

    var manager = try BufferManager.init(allocator);
    defer manager.deinit();

    _ = try manager.createBuffer();
    _ = try manager.createBuffer();

    const tabs = try manager.getTabLine(allocator);
    defer allocator.free(tabs);

    try std.testing.expectEqual(@as(usize, 3), tabs.len);
    try std.testing.expect(tabs[0].is_active); // First buffer is active
    try std.testing.expect(!tabs[1].is_active);
    try std.testing.expect(!tabs[2].is_active);
}

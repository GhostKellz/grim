const std = @import("std");
const core = @import("core");
const phantom_buffer_mod = @import("phantom_buffer.zig");

/// PhantomBuffer-based Multi-Buffer Management System
/// Drop-in replacement for BufferManager with native undo/redo and multi-cursor support
pub const PhantomBufferManager = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(ManagedBuffer),
    active_buffer_id: u32 = 0,
    next_buffer_id: u32 = 1,

    pub const ManagedBuffer = struct {
        id: u32,
        phantom_buffer: phantom_buffer_mod.PhantomBuffer,
        display_name: []const u8,
        last_accessed: i64,

        pub fn deinit(self: *ManagedBuffer, allocator: std.mem.Allocator) void {
            self.phantom_buffer.deinit();
            allocator.free(self.display_name);
        }

        pub fn setFilePath(self: *ManagedBuffer, allocator: std.mem.Allocator, path: []const u8) !void {
            // PhantomBuffer handles file_path internally when loading
            // Update display name to basename
            const basename = std.fs.path.basename(path);
            allocator.free(self.display_name);
            self.display_name = try allocator.dupe(u8, basename);
        }

        pub fn markModified(self: *ManagedBuffer) void {
            self.phantom_buffer.modified = true;
        }

        pub fn markSaved(self: *ManagedBuffer) void {
            self.phantom_buffer.modified = false;
        }

        pub fn updateAccessTime(self: *ManagedBuffer) void {
            self.last_accessed = std.time.timestamp();
        }

        /// Get file path from PhantomBuffer
        pub fn filePath(self: *const ManagedBuffer) ?[]const u8 {
            return self.phantom_buffer.file_path;
        }

        /// Check if buffer is modified
        pub fn isModified(self: *const ManagedBuffer) bool {
            return self.phantom_buffer.modified;
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

    pub fn init(allocator: std.mem.Allocator) !PhantomBufferManager {
        // Create initial PhantomBuffer
        const initial_phantom = try phantom_buffer_mod.PhantomBuffer.init(allocator, 0, .{
            .use_phantom = true, // Enable PhantomTUI features
        });

        const initial_buffer = ManagedBuffer{
            .id = 0,
            .phantom_buffer = initial_phantom,
            .display_name = try std.fmt.allocPrint(allocator, "[No Name 0]", .{}),
            .last_accessed = std.time.timestamp(),
        };

        var manager = PhantomBufferManager{
            .allocator = allocator,
            .buffers = .{},
        };

        try manager.buffers.append(allocator, initial_buffer);

        return manager;
    }

    pub fn deinit(self: *PhantomBufferManager) void {
        for (self.buffers.items) |*buffer| {
            buffer.deinit(self.allocator);
        }
        self.buffers.deinit(self.allocator);
    }

    /// Get the currently active buffer
    pub fn getActiveBuffer(self: *PhantomBufferManager) ?*ManagedBuffer {
        for (self.buffers.items) |*buffer| {
            if (buffer.id == self.active_buffer_id) {
                return buffer;
            }
        }
        return null;
    }

    /// Get buffer by ID
    pub fn getBuffer(self: *PhantomBufferManager, buffer_id: u32) ?*ManagedBuffer {
        for (self.buffers.items) |*buffer| {
            if (buffer.id == buffer_id) {
                return buffer;
            }
        }
        return null;
    }

    /// Create a new buffer
    pub fn createBuffer(self: *PhantomBufferManager) !u32 {
        const id = self.next_buffer_id;
        self.next_buffer_id += 1;

        const new_phantom = try phantom_buffer_mod.PhantomBuffer.init(self.allocator, id, .{
            .use_phantom = true,
        });

        const new_buffer = ManagedBuffer{
            .id = id,
            .phantom_buffer = new_phantom,
            .display_name = try std.fmt.allocPrint(self.allocator, "[No Name {d}]", .{id}),
            .last_accessed = std.time.timestamp(),
        };

        try self.buffers.append(self.allocator, new_buffer);

        return id;
    }

    /// Create a buffer from file
    pub fn openFile(self: *PhantomBufferManager, path: []const u8) !u32 {
        // Check if file is already open
        for (self.buffers.items) |*buffer| {
            if (buffer.phantom_buffer.file_path) |existing_path| {
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

        // Load file using PhantomBuffer
        try buffer.phantom_buffer.loadFile(path);
        try buffer.setFilePath(self.allocator, path);
        buffer.updateAccessTime();

        // Switch to new buffer
        self.active_buffer_id = id;

        return id;
    }

    /// Save active buffer
    pub fn saveActiveBuffer(self: *PhantomBufferManager) !void {
        const buffer = self.getActiveBuffer() orelse return error.NoActiveBuffer;

        // PhantomBuffer requires file_path to be set before saving
        if (buffer.phantom_buffer.file_path == null) {
            return error.NoFilePath;
        }

        try buffer.phantom_buffer.saveFile();
        buffer.markSaved();
    }

    /// Save buffer as...
    pub fn saveBufferAs(self: *PhantomBufferManager, buffer_id: u32, path: []const u8) !void {
        const buffer = self.getBuffer(buffer_id) orelse return error.BufferNotFound;

        // Set file path then save
        if (buffer.phantom_buffer.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        buffer.phantom_buffer.file_path = try self.allocator.dupe(u8, path);

        try buffer.phantom_buffer.saveFile();
        try buffer.setFilePath(self.allocator, path);
        buffer.markSaved();
    }

    /// Close a buffer
    pub fn closeBuffer(self: *PhantomBufferManager, buffer_id: u32) !void {
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
    pub fn nextBuffer(self: *PhantomBufferManager) void {
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
    pub fn previousBuffer(self: *PhantomBufferManager) void {
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
    pub fn switchToBuffer(self: *PhantomBufferManager, buffer_id: u32) !void {
        // Verify buffer exists
        const buffer = self.getBuffer(buffer_id) orelse return error.BufferNotFound;

        self.active_buffer_id = buffer_id;
        buffer.updateAccessTime();
    }

    /// Get tab line items for UI rendering
    pub fn getTabLine(self: *PhantomBufferManager, allocator: std.mem.Allocator) ![]TabItem {
        var tabs = try allocator.alloc(TabItem, self.buffers.items.len);

        for (self.buffers.items, 0..) |buffer, i| {
            tabs[i] = .{
                .id = buffer.id,
                .display_name = buffer.display_name,
                .modified = buffer.phantom_buffer.modified,
                .is_active = buffer.id == self.active_buffer_id,
            };
        }

        return tabs;
    }

    /// Get buffer list for picker/selector UI
    pub fn getBufferList(self: *PhantomBufferManager, allocator: std.mem.Allocator) ![]BufferInfo {
        var infos = try allocator.alloc(BufferInfo, self.buffers.items.len);

        for (self.buffers.items, 0..) |buffer, i| {
            const language_name = languageToString(buffer.phantom_buffer.language);

            infos[i] = .{
                .id = buffer.id,
                .display_name = buffer.display_name,
                .file_path = buffer.phantom_buffer.file_path,
                .modified = buffer.phantom_buffer.modified,
                .line_count = buffer.phantom_buffer.lineCount(),
                .language = language_name,
            };
        }

        return infos;
    }

    /// Get list of modified buffers
    pub fn getModifiedBuffers(self: *PhantomBufferManager, allocator: std.mem.Allocator) ![]u32 {
        var modified = std.ArrayList(u32){};
        defer modified.deinit(allocator);

        for (self.buffers.items) |buffer| {
            if (buffer.phantom_buffer.modified) {
                try modified.append(allocator, buffer.id);
            }
        }

        return modified.toOwnedSlice();
    }

    /// Check if there are unsaved changes
    pub fn hasUnsavedChanges(self: *PhantomBufferManager) bool {
        for (self.buffers.items) |buffer| {
            if (buffer.phantom_buffer.modified) return true;
        }
        return false;
    }

    /// Sort buffers by last accessed (for MRU - Most Recently Used)
    pub fn sortByMRU(self: *PhantomBufferManager) void {
        std.mem.sort(ManagedBuffer, self.buffers.items, {}, struct {
            fn lessThan(_: void, a: ManagedBuffer, b: ManagedBuffer) bool {
                return a.last_accessed > b.last_accessed;
            }
        }.lessThan);
    }

    // Helper functions

    fn languageToString(language: phantom_buffer_mod.PhantomBuffer.Language) []const u8 {
        return switch (language) {
            .unknown => "unknown",
            .zig => "zig",
            .rust => "rust",
            .go => "go",
            .javascript => "javascript",
            .typescript => "typescript",
            .python => "python",
            .c => "c",
            .cpp => "cpp",
            .markdown => "markdown",
            .json => "json",
            .html => "html",
            .css => "css",
            .ghostlang => "ghostlang",
        };
    }
};

test "PhantomBufferManager init and basic operations" {
    const allocator = std.testing.allocator;

    var manager = try PhantomBufferManager.init(allocator);
    defer manager.deinit();

    // Should have one initial buffer
    try std.testing.expectEqual(@as(usize, 1), manager.buffers.items.len);
    try std.testing.expectEqual(@as(u32, 0), manager.active_buffer_id);
}

test "PhantomBufferManager create and switch buffers" {
    const allocator = std.testing.allocator;

    var manager = try PhantomBufferManager.init(allocator);
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

test "PhantomBufferManager next/previous navigation" {
    const allocator = std.testing.allocator;

    var manager = try PhantomBufferManager.init(allocator);
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

test "PhantomBufferManager close buffer" {
    const allocator = std.testing.allocator;

    var manager = try PhantomBufferManager.init(allocator);
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

test "PhantomBufferManager tab line" {
    const allocator = std.testing.allocator;

    var manager = try PhantomBufferManager.init(allocator);
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

test "PhantomBufferManager undo/redo support" {
    const allocator = std.testing.allocator;

    var manager = try PhantomBufferManager.init(allocator);
    defer manager.deinit();

    const buffer = manager.getActiveBuffer().?;

    // Insert text
    try buffer.phantom_buffer.insertText(0, "hello");

    const content1 = try buffer.phantom_buffer.getContent();
    defer allocator.free(content1);
    try std.testing.expectEqualStrings("hello", content1);

    // Undo (only works if PhantomTUI TextEditor is available)
    buffer.phantom_buffer.undo() catch |err| {
        // Expected to fail in test environment (no PhantomTUI available)
        try std.testing.expectEqual(error.UndoNotAvailableInFallbackMode, err);
        return;
    };

    // If we got here, PhantomTUI is available
    const content2 = try buffer.phantom_buffer.getContent();
    defer allocator.free(content2);
    try std.testing.expectEqualStrings("", content2);
}

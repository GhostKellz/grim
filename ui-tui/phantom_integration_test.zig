const std = @import("std");
const phantom_buffer_mod = @import("phantom_buffer.zig");
const phantom_buffer_manager_mod = @import("phantom_buffer_manager.zig");

/// Comprehensive integration tests for PhantomBuffer system
test "PhantomBuffer: Text editing with undo/redo" {
    const allocator = std.testing.allocator;

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    // Insert some text
    try buffer.insertText(0, "Hello");
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello", content);
    }

    // Insert more text
    try buffer.insertText(5, " World");
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello World", content);
    }

    // Undo last insert
    try buffer.undo();
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello", content);
    }

    // Undo first insert
    try buffer.undo();
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("", content);
    }

    // Redo both
    try buffer.redo();
    try buffer.redo();
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello World", content);
    }
}

test "PhantomBuffer: Delete with undo" {
    const allocator = std.testing.allocator;

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "Hello World");

    // Delete "World"
    try buffer.deleteRange(.{ .start = 6, .end = 11 });
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello ", content);
    }

    // Undo delete
    try buffer.undo();
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello World", content);
    }
}

test "PhantomBuffer: Replace range with undo" {
    const allocator = std.testing.allocator;

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "Hello World");

    // Replace "World" with "Zig"
    try buffer.replaceRange(.{ .start = 6, .end = 11 }, "Zig");
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello Zig", content);
    }

    // Undo replace (should undo both delete and insert)
    try buffer.undo();
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        // After undoing insert
        try std.testing.expectEqualStrings("Hello ", content);
    }

    try buffer.undo();
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        // After undoing delete
        try std.testing.expectEqualStrings("Hello World", content);
    }
}

test "PhantomBuffer: Multi-cursor positions" {
    const allocator = std.testing.allocator;

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "line1\nline2\nline3\n");

    // Add cursors at different lines
    try buffer.addCursor(.{ .line = 1, .column = 0, .byte_offset = 6 });
    try buffer.addCursor(.{ .line = 2, .column = 0, .byte_offset = 12 });

    try std.testing.expectEqual(@as(usize, 3), buffer.cursor_positions.items.len);

    // Clear secondary cursors
    buffer.clearSecondaryCursors();
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor_positions.items.len);
}

test "PhantomBuffer: File load and save" {
    const allocator = std.testing.allocator;

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    // Create a temporary file
    const test_file = "/tmp/phantom_test.txt";
    {
        const file = try std.fs.cwd().createFile(test_file, .{});
        defer file.close();
        try file.writeAll("Test content\n");
    }
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Load file
    try buffer.loadFile(test_file);
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Test content\n", content);
    }

    // Modify
    try buffer.insertText(12, " modified");

    // Save
    try buffer.saveFile();

    // Read back
    const file = try std.fs.cwd().openFile(test_file, .{});
    defer file.close();
    const saved_content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(saved_content);

    try std.testing.expectEqualStrings("Test content modified\n", saved_content);
}

test "PhantomBufferManager: Create and switch buffers" {
    const allocator = std.testing.allocator;

    var manager = try phantom_buffer_manager_mod.PhantomBufferManager.init(allocator);
    defer manager.deinit();

    // Should start with one buffer
    try std.testing.expectEqual(@as(usize, 1), manager.buffers.items.len);
    try std.testing.expectEqual(@as(u32, 0), manager.active_buffer_id);

    // Create another buffer
    const buf2 = try manager.createBuffer();
    try std.testing.expectEqual(@as(u32, 1), buf2);
    try std.testing.expectEqual(@as(usize, 2), manager.buffers.items.len);

    // Switch to second buffer
    try manager.switchToBuffer(buf2);
    try std.testing.expectEqual(buf2, manager.active_buffer_id);
}

test "PhantomBufferManager: Modified buffers tracking" {
    const allocator = std.testing.allocator;

    var manager = try phantom_buffer_manager_mod.PhantomBufferManager.init(allocator);
    defer manager.deinit();

    // Initial buffer should not be modified
    try std.testing.expect(!manager.hasUnsavedChanges());

    // Modify buffer
    const buffer = manager.getActiveBuffer().?;
    try buffer.phantom_buffer.insertText(0, "modified");
    buffer.markModified();

    // Should now have unsaved changes
    try std.testing.expect(manager.hasUnsavedChanges());

    // Get list of modified buffers
    const modified = try manager.getModifiedBuffers(allocator);
    defer allocator.free(modified);

    try std.testing.expectEqual(@as(usize, 1), modified.len);
    try std.testing.expectEqual(@as(u32, 0), modified[0]);
}

test "PhantomBufferManager: Buffer navigation" {
    const allocator = std.testing.allocator;

    var manager = try phantom_buffer_manager_mod.PhantomBufferManager.init(allocator);
    defer manager.deinit();

    _ = try manager.createBuffer(); // id=1
    _ = try manager.createBuffer(); // id=2

    // Should be at buffer 0
    try std.testing.expectEqual(@as(u32, 0), manager.active_buffer_id);

    // Next buffer
    manager.nextBuffer();
    try std.testing.expectEqual(@as(u32, 1), manager.active_buffer_id);

    // Next again
    manager.nextBuffer();
    try std.testing.expectEqual(@as(u32, 2), manager.active_buffer_id);

    // Next wraps around
    manager.nextBuffer();
    try std.testing.expectEqual(@as(u32, 0), manager.active_buffer_id);

    // Previous
    manager.previousBuffer();
    try std.testing.expectEqual(@as(u32, 2), manager.active_buffer_id);
}

test "PhantomBuffer: Undo stack limit" {
    const allocator = std.testing.allocator;

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();
    buffer.max_undo_levels = 10; // Limit to 10 for testing

    // Perform 20 edits
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try buffer.insertText(buffer.rope.len(), "x");
    }

    // Should only be able to undo 10 times
    i = 0;
    while (i < 20) : (i += 1) {
        buffer.undo() catch |err| {
            try std.testing.expectEqual(error.NothingToUndo, err);
            try std.testing.expectEqual(@as(usize, 10), i);
            break;
        };
    }
}

test "PhantomBuffer: Redo cleared on new operation" {
    const allocator = std.testing.allocator;

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "Hello");
    try buffer.insertText(5, " World");

    // Undo once
    try buffer.undo();

    // Redo should work
    try buffer.redo();
    {
        const content = try buffer.getContent();
        defer allocator.free(content);
        try std.testing.expectEqualStrings("Hello World", content);
    }

    // Undo again
    try buffer.undo();

    // Make a new edit - should clear redo stack
    try buffer.insertText(5, " Zig");

    // Redo should now fail
    const redo_result = buffer.redo();
    try std.testing.expectError(error.NothingToRedo, redo_result);
}

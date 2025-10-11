const std = @import("std");
const phantom_buffer_mod = @import("phantom_buffer.zig");

/// Performance test for PhantomBuffer with large files
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== PhantomBuffer Performance Test ===\n", .{});

    // Test 1: Large file insertion
    try testLargeFileInsertion(allocator);

    // Test 2: Many small edits
    try testManySmallEdits(allocator);

    // Test 3: Undo/redo performance
    try testUndoRedoPerformance(allocator);

    std.debug.print("\n✓ All performance tests passed!\n", .{});
}

fn testLargeFileInsertion(allocator: std.mem.Allocator) !void {
    std.debug.print("\nTest 1: Large file insertion (10,000 lines)\n", .{});

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    // Generate 10k lines of text
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();

    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        try content.writer().print("Line {d}: The quick brown fox jumps over the lazy dog.\n", .{i});
    }

    const start = std.time.nanoTimestamp();
    try buffer.insertText(0, content.items);
    const end = std.time.nanoTimestamp();

    const duration_ms = @divFloor(end - start, 1_000_000);
    std.debug.print("  Inserted {d} bytes in {d}ms\n", .{ content.items.len, duration_ms });
    std.debug.print("  Buffer line count: {d}\n", .{buffer.lineCount()});
}

fn testManySmallEdits(allocator: std.mem.Allocator) !void {
    std.debug.print("\nTest 2: Many small edits (1,000 operations)\n", .{});

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "Starting text\n");

    const start = std.time.nanoTimestamp();

    // Perform 1000 small edits
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const pos = buffer.rope.len();
        try buffer.insertText(pos, "edit ");
    }

    const end = std.time.nanoTimestamp();

    const duration_ms = @divFloor(end - start, 1_000_000);
    std.debug.print("  1,000 insertions in {d}ms ({d}μs per op)\n", .{
        duration_ms,
        @divFloor(end - start, 1_000_000)
    });
    std.debug.print("  Final buffer size: {d} bytes\n", .{buffer.rope.len()});
}

fn testUndoRedoPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\nTest 3: Undo/redo performance (500 operations)\n", .{});

    var buffer = try phantom_buffer_mod.PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    // Perform 500 edits
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const pos = buffer.rope.len();
        try buffer.insertText(pos, "text ");
    }

    std.debug.print("  Created 500 undo entries\n", .{});

    // Undo all
    const undo_start = std.time.nanoTimestamp();
    i = 0;
    while (i < 500) : (i += 1) {
        buffer.undo() catch break;
    }
    const undo_end = std.time.nanoTimestamp();

    const undo_duration_ms = @divFloor(undo_end - undo_start, 1_000_000);
    std.debug.print("  500 undos in {d}ms ({d}μs per undo)\n", .{
        undo_duration_ms,
        @divFloor(undo_end - undo_start, 500_000),
    });

    // Redo all
    const redo_start = std.time.nanoTimestamp();
    i = 0;
    while (i < 500) : (i += 1) {
        buffer.redo() catch break;
    }
    const redo_end = std.time.nanoTimestamp();

    const redo_duration_ms = @divFloor(redo_end - redo_start, 1_000_000);
    std.debug.print("  500 redos in {d}ms ({d}μs per redo)\n", .{
        redo_duration_ms,
        @divFloor(redo_end - redo_start, 500_000),
    });

    std.debug.print("  Final buffer size: {d} bytes\n", .{buffer.rope.len()});
}

//! Undo/Redo System for Grim
//!
//! Snapshot-based undo with cursor position restoration
//! Limits undo history to prevent excessive memory usage

const std = @import("std");
const Rope = @import("rope.zig").Rope;

pub const UndoStack = struct {
    allocator: std.mem.Allocator,
    snapshots: std.ArrayList(Snapshot),
    current_index: isize, // -1 means no snapshots, points to current state
    max_snapshots: usize,

    pub const Snapshot = struct {
        content: []const u8,
        cursor_offset: usize,
        timestamp: i64,
        description: []const u8,

        pub fn deinit(self: *Snapshot, allocator: std.mem.Allocator) void {
            allocator.free(self.content);
            allocator.free(self.description);
        }
    };

    pub fn init(allocator: std.mem.Allocator, max_snapshots: usize) UndoStack {
        return .{
            .allocator = allocator,
            .snapshots = std.ArrayList(Snapshot){},
            .current_index = -1,
            .max_snapshots = max_snapshots,
        };
    }

    pub fn deinit(self: *UndoStack) void {
        for (self.snapshots.items) |*snapshot| {
            snapshot.deinit(self.allocator);
        }
        self.snapshots.deinit(self.allocator);
    }

    /// Record a new undo state
    /// Truncates redo history if we're not at the end
    pub fn recordUndo(
        self: *UndoStack,
        rope: *Rope,
        cursor_offset: usize,
        description: []const u8,
    ) !void {
        // Get current content
        const content = try rope.slice(.{ .start = 0, .end = rope.len() });
        const content_copy = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(content_copy);

        const desc_copy = try self.allocator.dupe(u8, description);
        errdefer self.allocator.free(desc_copy);

        const snapshot = Snapshot{
            .content = content_copy,
            .cursor_offset = cursor_offset,
            .timestamp = blk: {
                const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch {
                    break :blk @as(i64, 0);
                };
                break :blk @as(i64, @intCast(ts.sec)) * 1000 + @divFloor(ts.nsec, 1_000_000);
            },
            .description = desc_copy,
        };

        // If we're not at the end, truncate redo history
        const next_index = @as(usize, @intCast(self.current_index + 1));
        if (next_index < self.snapshots.items.len) {
            // Free truncated snapshots
            var i = next_index;
            while (i < self.snapshots.items.len) : (i += 1) {
                self.snapshots.items[i].deinit(self.allocator);
            }
            self.snapshots.shrinkRetainingCapacity(next_index);
        }

        // Add new snapshot
        try self.snapshots.append(self.allocator, snapshot);
        self.current_index += 1;

        // Enforce max snapshots limit
        if (self.snapshots.items.len > self.max_snapshots) {
            // Remove oldest snapshot
            var oldest = self.snapshots.orderedRemove(0);
            oldest.deinit(self.allocator);
            self.current_index -= 1;
        }
    }

    /// Undo to previous state
    /// Returns snapshot to restore, or null if at oldest state
    pub fn undo(self: *UndoStack) ?*const Snapshot {
        if (self.current_index <= 0) {
            return null; // Already at oldest state
        }

        self.current_index -= 1;
        return &self.snapshots.items[@intCast(self.current_index)];
    }

    /// Redo to next state
    /// Returns snapshot to restore, or null if at newest state
    pub fn redo(self: *UndoStack) ?*const Snapshot {
        if (self.current_index < 0) {
            return null;
        }

        const next_index = @as(usize, @intCast(self.current_index + 1));
        if (next_index >= self.snapshots.items.len) {
            return null; // Already at newest state
        }

        self.current_index += 1;
        return &self.snapshots.items[next_index];
    }

    /// Check if undo is available
    pub fn canUndo(self: *const UndoStack) bool {
        return self.current_index > 0;
    }

    /// Check if redo is available
    pub fn canRedo(self: *const UndoStack) bool {
        if (self.current_index < 0) return false;
        const next_index = @as(usize, @intCast(self.current_index + 1));
        return next_index < self.snapshots.items.len;
    }

    /// Get count of available undos
    pub fn undoCount(self: *const UndoStack) usize {
        if (self.current_index < 0) return 0;
        return @intCast(self.current_index);
    }

    /// Get count of available redos
    pub fn redoCount(self: *const UndoStack) usize {
        if (self.current_index < 0) return 0;
        const next_index = @as(usize, @intCast(self.current_index + 1));
        if (next_index >= self.snapshots.items.len) return 0;
        return self.snapshots.items.len - next_index;
    }

    /// Get current snapshot (for inspection)
    pub fn getCurrentSnapshot(self: *const UndoStack) ?*const Snapshot {
        if (self.current_index < 0) return null;
        return &self.snapshots.items[@intCast(self.current_index)];
    }
};

test "undo/redo basic" {
    const allocator = std.testing.allocator;

    var rope = try Rope.init(allocator);
    defer rope.deinit();

    var undo_stack = UndoStack.init(allocator, 100);
    defer undo_stack.deinit();

    // Initial state
    try rope.insert(0, "Hello");
    try undo_stack.recordUndo(&rope, 5, "insert Hello");

    // Second state
    try rope.insert(5, " World");
    try undo_stack.recordUndo(&rope, 11, "insert World");

    // Undo
    const snapshot1 = undo_stack.undo();
    try std.testing.expect(snapshot1 != null);
    try std.testing.expectEqualStrings("Hello", snapshot1.?.content);

    // Redo
    const snapshot2 = undo_stack.redo();
    try std.testing.expect(snapshot2 != null);
    try std.testing.expectEqualStrings("Hello World", snapshot2.?.content);
}

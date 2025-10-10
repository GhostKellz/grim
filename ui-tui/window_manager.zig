const std = @import("std");
const buffer_manager = @import("buffer_manager.zig");

/// Window Manager - Split windows and pane management
/// Supports horizontal and vertical splits, window navigation, and layouts
pub const WindowManager = struct {
    allocator: std.mem.Allocator,
    root_window: ?*Window,
    active_window_id: u32,
    next_window_id: u32,
    buffer_manager: *buffer_manager.BufferManager,

    pub const SplitDirection = enum {
        horizontal,
        vertical,
    };

    pub const WindowLayout = struct {
        x: u16,
        y: u16,
        width: u16,
        height: u16,
    };

    pub const Window = struct {
        id: u32,
        buffer_id: u32,
        layout: WindowLayout,
        parent: ?*Window,
        children: ?struct {
            left: *Window,
            right: *Window,
            direction: SplitDirection,
        },

        pub fn isLeaf(self: *const Window) bool {
            return self.children == null;
        }

        pub fn deinit(self: *Window, allocator: std.mem.Allocator) void {
            if (self.children) |children| {
                children.left.deinit(allocator);
                children.right.deinit(allocator);
                allocator.destroy(children.left);
                allocator.destroy(children.right);
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, buffer_mgr: *buffer_manager.BufferManager) !WindowManager {
        const first_window = try allocator.create(Window);
        first_window.* = .{
            .id = 0,
            .buffer_id = 0, // First buffer
            .layout = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
            .parent = null,
            .children = null,
        };

        return WindowManager{
            .allocator = allocator,
            .root_window = first_window,
            .active_window_id = 0,
            .next_window_id = 1,
            .buffer_manager = buffer_mgr,
        };
    }

    pub fn deinit(self: *WindowManager) void {
        if (self.root_window) |root| {
            root.deinit(self.allocator);
            self.allocator.destroy(root);
        }
    }

    /// Split the active window in the specified direction
    pub fn splitWindow(self: *WindowManager, direction: SplitDirection) !void {
        const active = try self.getActiveWindow();

        // Create two new windows
        const left = try self.allocator.create(Window);
        const right = try self.allocator.create(Window);

        const layout = active.layout;

        switch (direction) {
            .horizontal => {
                // Split left/right
                const mid_x = layout.x + layout.width / 2;

                left.* = .{
                    .id = self.next_window_id,
                    .buffer_id = active.buffer_id,
                    .layout = .{
                        .x = layout.x,
                        .y = layout.y,
                        .width = layout.width / 2,
                        .height = layout.height,
                    },
                    .parent = active,
                    .children = null,
                };
                self.next_window_id += 1;

                right.* = .{
                    .id = self.next_window_id,
                    .buffer_id = active.buffer_id,
                    .layout = .{
                        .x = mid_x,
                        .y = layout.y,
                        .width = layout.width - layout.width / 2,
                        .height = layout.height,
                    },
                    .parent = active,
                    .children = null,
                };
                self.next_window_id += 1;
            },
            .vertical => {
                // Split top/bottom
                const mid_y = layout.y + layout.height / 2;

                left.* = .{
                    .id = self.next_window_id,
                    .buffer_id = active.buffer_id,
                    .layout = .{
                        .x = layout.x,
                        .y = layout.y,
                        .width = layout.width,
                        .height = layout.height / 2,
                    },
                    .parent = active,
                    .children = null,
                };
                self.next_window_id += 1;

                right.* = .{
                    .id = self.next_window_id,
                    .buffer_id = active.buffer_id,
                    .layout = .{
                        .x = layout.x,
                        .y = mid_y,
                        .width = layout.width,
                        .height = layout.height - layout.height / 2,
                    },
                    .parent = active,
                    .children = null,
                };
                self.next_window_id += 1;
            },
        }

        // Convert active window to container
        active.children = .{
            .left = left,
            .right = right,
            .direction = direction,
        };

        // Set active to the right (new) window
        self.active_window_id = right.id;
    }

    /// Close the active window (merge with sibling if possible)
    pub fn closeWindow(self: *WindowManager) !void {
        const active = try self.getActiveWindow();

        // Can't close root window if it's a leaf
        if (active == self.root_window and active.isLeaf()) {
            return error.CannotCloseLastWindow;
        }

        const parent = active.parent orelse return error.NoParent;

        // Find sibling
        const children = parent.children orelse return error.NoSiblings;
        const sibling = if (children.left == active) children.right else children.left;

        // Replace parent with sibling
        parent.* = sibling.*;

        // Update children's parent pointers
        if (parent.children) |new_children| {
            new_children.left.parent = parent;
            new_children.right.parent = parent;
        }

        // Switch active to parent
        self.active_window_id = parent.id;

        // Cleanup
        if (children.left == active) {
            self.allocator.destroy(children.right);
        } else {
            self.allocator.destroy(children.left);
        }
    }

    /// Navigate to window in direction
    pub fn navigateWindow(self: *WindowManager, direction: Direction) !void {
        _ = direction;
        // TODO: Implement directional navigation
        // For now, cycle through leaf windows
        const leaves = try self.getLeafWindows();
        defer self.allocator.free(leaves);

        for (leaves, 0..) |window, i| {
            if (window.id == self.active_window_id) {
                const next_idx = (i + 1) % leaves.len;
                self.active_window_id = leaves[next_idx].id;
                return;
            }
        }
    }

    pub const Direction = enum {
        left,
        right,
        up,
        down,
    };

    /// Get the currently active window
    pub fn getActiveWindow(self: *WindowManager) !*Window {
        const root = self.root_window orelse return error.NoWindows;
        return try self.findWindowById(root, self.active_window_id) orelse error.WindowNotFound;
    }

    /// Get all leaf (visible) windows
    pub fn getLeafWindows(self: *WindowManager) ![]const *Window {
        var leaves = std.ArrayList(*Window).init(self.allocator);
        defer leaves.deinit();

        if (self.root_window) |root| {
            try self.collectLeaves(root, &leaves);
        }

        return leaves.toOwnedSlice();
    }

    /// Recalculate layouts after terminal resize
    pub fn resize(self: *WindowManager, width: u16, height: u16) void {
        if (self.root_window) |root| {
            root.layout = .{ .x = 0, .y = 0, .width = width, .height = height };
            self.recalculateLayouts(root);
        }
    }

    // Private helpers

    fn findWindowById(self: *WindowManager, window: *Window, id: u32) !?*Window {
        if (window.id == id) return window;

        if (window.children) |children| {
            if (try self.findWindowById(children.left, id)) |found| return found;
            if (try self.findWindowById(children.right, id)) |found| return found;
        }

        return null;
    }

    fn collectLeaves(self: *WindowManager, window: *Window, list: *std.ArrayList(*Window)) !void {
        if (window.isLeaf()) {
            try list.append(window);
        } else if (window.children) |children| {
            try self.collectLeaves(children.left, list);
            try self.collectLeaves(children.right, list);
        }
    }

    fn recalculateLayouts(self: *WindowManager, window: *Window) void {
        if (window.children) |children| {
            const layout = window.layout;

            switch (children.direction) {
                .horizontal => {
                    const mid_x = layout.x + layout.width / 2;

                    children.left.layout = .{
                        .x = layout.x,
                        .y = layout.y,
                        .width = layout.width / 2,
                        .height = layout.height,
                    };

                    children.right.layout = .{
                        .x = mid_x,
                        .y = layout.y,
                        .width = layout.width - layout.width / 2,
                        .height = layout.height,
                    };
                },
                .vertical => {
                    const mid_y = layout.y + layout.height / 2;

                    children.left.layout = .{
                        .x = layout.x,
                        .y = layout.y,
                        .width = layout.width,
                        .height = layout.height / 2,
                    };

                    children.right.layout = .{
                        .x = layout.x,
                        .y = mid_y,
                        .width = layout.width,
                        .height = layout.height - layout.height / 2,
                    };
                },
            }

            self.recalculateLayouts(children.left);
            self.recalculateLayouts(children.right);
        }
    }
};

test "WindowManager init" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var win_mgr = try WindowManager.init(allocator, &buffer_mgr);
    defer win_mgr.deinit();

    try std.testing.expect(win_mgr.root_window != null);
    try std.testing.expectEqual(@as(u32, 0), win_mgr.active_window_id);
}

test "WindowManager horizontal split" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var win_mgr = try WindowManager.init(allocator, &buffer_mgr);
    defer win_mgr.deinit();

    try win_mgr.splitWindow(.horizontal);

    const leaves = try win_mgr.getLeafWindows();
    defer allocator.free(leaves);

    try std.testing.expectEqual(@as(usize, 2), leaves.len);
}

test "WindowManager vertical split" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var win_mgr = try WindowManager.init(allocator, &buffer_mgr);
    defer win_mgr.deinit();

    try win_mgr.splitWindow(.vertical);

    const leaves = try win_mgr.getLeafWindows();
    defer allocator.free(leaves);

    try std.testing.expectEqual(@as(usize, 2), leaves.len);
}

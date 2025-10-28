//! LayoutManager - Manages editor windows, splits, and tabs (Neovim-style)

const std = @import("std");
const phantom = @import("phantom");
const grim_editor_widget = @import("grim_editor_widget.zig");

// Extract MouseEvent type from Event union (not exported from phantom root)
const MouseEvent = @typeInfo(phantom.Event).@"union".fields[1].type;

/// Direction for window navigation
pub const Direction = enum {
    left,
    right,
    up,
    down,
};

/// Direction for window resize
pub const ResizeDirection = enum {
    increase,
    decrease,
    increase_vertical,
    decrease_vertical,
};

/// Split node - represents either a leaf (editor) or a container (split)
pub const SplitNode = union(enum) {
    leaf: *grim_editor_widget.GrimEditorWidget,
    vsplit: struct {
        left: *SplitNode,
        right: *SplitNode,
        ratio: f32, // 0.0 to 1.0 (position of divider)
    },
    hsplit: struct {
        top: *SplitNode,
        bottom: *SplitNode,
        ratio: f32, // 0.0 to 1.0 (position of divider)
    },

    pub fn deinit(self: *SplitNode, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .leaf => |editor| {
                editor.widget.vtable.deinit(&editor.widget);
            },
            .vsplit => |vsplit| {
                vsplit.left.deinit(allocator);
                allocator.destroy(vsplit.left);
                vsplit.right.deinit(allocator);
                allocator.destroy(vsplit.right);
            },
            .hsplit => |hsplit| {
                hsplit.top.deinit(allocator);
                allocator.destroy(hsplit.top);
                hsplit.bottom.deinit(allocator);
                allocator.destroy(hsplit.bottom);
            },
        }
    }

    /// Collect all editors in this split tree
    pub fn collectEditors(self: *SplitNode, editors: *std.ArrayList(*grim_editor_widget.GrimEditorWidget), allocator: std.mem.Allocator) !void {
        switch (self.*) {
            .leaf => |editor| {
                try editors.append(allocator, editor);
            },
            .vsplit => |vsplit| {
                try vsplit.left.collectEditors(editors, allocator);
                try vsplit.right.collectEditors(editors, allocator);
            },
            .hsplit => |hsplit| {
                try hsplit.top.collectEditors(editors, allocator);
                try hsplit.bottom.collectEditors(editors, allocator);
            },
        }
    }

    /// Get the editor at the given position, or null if out of bounds
    pub fn getEditorAt(self: *SplitNode, area: phantom.Rect, x: u16, y: u16) ?*grim_editor_widget.GrimEditorWidget {
        switch (self.*) {
            .leaf => |editor| {
                return editor;
            },
            .vsplit => |vsplit| {
                const split_x = area.x + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.width)) * vsplit.ratio));
                if (x < split_x) {
                    const left_area = phantom.Rect.init(area.x, area.y, split_x - area.x, area.height);
                    return vsplit.left.getEditorAt(left_area, x, y);
                } else {
                    const right_area = phantom.Rect.init(split_x, area.y, area.x + area.width - split_x, area.height);
                    return vsplit.right.getEditorAt(right_area, x, y);
                }
            },
            .hsplit => |hsplit| {
                const split_y = area.y + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.height)) * hsplit.ratio));
                if (y < split_y) {
                    const top_area = phantom.Rect.init(area.x, area.y, area.width, split_y - area.y);
                    return hsplit.top.getEditorAt(top_area, x, y);
                } else {
                    const bottom_area = phantom.Rect.init(area.x, split_y, area.width, area.y + area.height - split_y);
                    return hsplit.bottom.getEditorAt(bottom_area, x, y);
                }
            },
        }
    }

    /// Render this split node and all children
    pub fn render(self: *SplitNode, buffer: anytype, area: phantom.Rect) void {
        switch (self.*) {
            .leaf => |editor| {
                editor.widget.render(buffer, area);
            },
            .vsplit => |vsplit| {
                const split_x = area.x + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.width)) * vsplit.ratio));
                const left_width = if (split_x > area.x) split_x - area.x else 0;
                const right_width = if (area.x + area.width > split_x) area.x + area.width - split_x else 0;

                // Render left side
                const left_area = phantom.Rect.init(area.x, area.y, left_width, area.height);
                vsplit.left.render(buffer, left_area);

                // Render vertical divider
                if (split_x < area.x + area.width) {
                    var y: u16 = area.y;
                    while (y < area.y + area.height) : (y += 1) {
                        buffer.setCell(split_x, y, .{ .char = '│', .style = phantom.Style.default() });
                    }
                }

                // Render right side (if there's room)
                if (right_width > 0 and split_x + 1 < area.x + area.width) {
                    const right_area = phantom.Rect.init(split_x + 1, area.y, right_width - 1, area.height);
                    vsplit.right.render(buffer, right_area);
                }
            },
            .hsplit => |hsplit| {
                const split_y = area.y + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.height)) * hsplit.ratio));
                const top_height = if (split_y > area.y) split_y - area.y else 0;
                const bottom_height = if (area.y + area.height > split_y) area.y + area.height - split_y else 0;

                // Render top side
                const top_area = phantom.Rect.init(area.x, area.y, area.width, top_height);
                hsplit.top.render(buffer, top_area);

                // Render horizontal divider
                if (split_y < area.y + area.height) {
                    var x: u16 = area.x;
                    while (x < area.x + area.width) : (x += 1) {
                        buffer.setCell(x, split_y, .{ .char = '─', .style = phantom.Style.default() });
                    }
                }

                // Render bottom side (if there's room)
                if (bottom_height > 0 and split_y + 1 < area.y + area.height) {
                    const bottom_area = phantom.Rect.init(area.x, split_y + 1, area.width, bottom_height - 1);
                    hsplit.bottom.render(buffer, bottom_area);
                }
            },
        }
    }
};

/// Tab page containing a split tree
pub const TabPage = struct {
    allocator: std.mem.Allocator,
    root: *SplitNode,
    active_editor: *grim_editor_widget.GrimEditorWidget,
    name: []const u8,

    pub fn init(allocator: std.mem.Allocator, editor: *grim_editor_widget.GrimEditorWidget, name: []const u8) !*TabPage {
        const self = try allocator.create(TabPage);
        errdefer allocator.destroy(self);

        const root = try allocator.create(SplitNode);
        errdefer allocator.destroy(root);
        root.* = .{ .leaf = editor };

        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        self.* = .{
            .allocator = allocator,
            .root = root,
            .active_editor = editor,
            .name = owned_name,
        };

        return self;
    }

    pub fn deinit(self: *TabPage) void {
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }
};

pub const Buffer = struct {
    editor: *grim_editor_widget.GrimEditorWidget,
    filepath: ?[]const u8,
    name: []const u8,
};

pub const LayoutManager = struct {
    allocator: std.mem.Allocator,

    // Tab management
    tabs: std.ArrayList(*TabPage),
    active_tab_index: usize,

    // Buffer management
    buffers: std.ArrayList(Buffer),

    // Rendering area
    width: u16,
    height: u16,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !*LayoutManager {
        const self = try allocator.create(LayoutManager);
        errdefer allocator.destroy(self);

        // Create initial tab with editor
        const initial_editor = try grim_editor_widget.GrimEditorWidget.init(allocator);
        errdefer initial_editor.widget.vtable.deinit(&initial_editor.widget);

        const initial_tab = try TabPage.init(allocator, initial_editor, "Tab 1");
        errdefer initial_tab.deinit();

        var tabs = std.ArrayList(*TabPage){};
        errdefer tabs.deinit(allocator);
        try tabs.append(allocator, initial_tab);

        // Create buffer list
        var buffers = std.ArrayList(Buffer){};
        errdefer buffers.deinit(allocator);
        try buffers.append(allocator, Buffer{
            .editor = initial_editor,
            .filepath = null,
            .name = try allocator.dupe(u8, "[No Name]"),
        });

        self.* = .{
            .allocator = allocator,
            .tabs = tabs,
            .active_tab_index = 0,
            .buffers = buffers,
            .width = width,
            .height = height,
        };

        return self;
    }

    pub fn deinit(self: *LayoutManager) void {
        for (self.tabs.items) |tab| {
            tab.deinit();
        }
        self.tabs.deinit(self.allocator);

        // Free buffer list (editors are freed by tabs)
        for (self.buffers.items) |buffer| {
            self.allocator.free(buffer.name);
            if (buffer.filepath) |path| {
                self.allocator.free(path);
            }
        }
        self.buffers.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Create initial editor (called on startup) - DEPRECATED, now done in init()
    pub fn createInitialEditor(self: *LayoutManager) !void {
        // No-op: editor is now created in init()
        _ = self;
    }

    /// Get currently active editor
    pub fn getActiveEditor(self: *LayoutManager) ?*grim_editor_widget.GrimEditorWidget {
        if (self.tabs.items.len == 0) return null;
        return self.tabs.items[self.active_tab_index].active_editor;
    }

    /// Get all editor widgets across all tabs (for LSP attachment, etc.)
    pub fn getAllEditors(self: *LayoutManager) []*grim_editor_widget.GrimEditorWidget {
        var editors = std.ArrayList(*grim_editor_widget.GrimEditorWidget){};
        for (self.tabs.items) |tab| {
            tab.root.collectEditors(&editors, self.allocator) catch {};
        }
        return editors.toOwnedSlice(self.allocator) catch &[_]*grim_editor_widget.GrimEditorWidget{};
    }

    /// Get currently active tab
    pub fn getActiveTab(self: *LayoutManager) ?*TabPage {
        if (self.tabs.items.len == 0) return null;
        return self.tabs.items[self.active_tab_index];
    }

    /// Render all editor windows
    pub fn render(self: *LayoutManager, buffer: anytype, area: phantom.Rect) void {
        const tab = self.getActiveTab() orelse return;
        tab.root.render(buffer, area);
    }

    /// Handle window resize
    pub fn resize(self: *LayoutManager, new_width: u16, new_height: u16) !void {
        self.width = new_width;
        self.height = new_height;
        // Splits will automatically resize on next render
    }

    /// Handle mouse events (dispatch to correct editor)
    pub fn handleMouse(self: *LayoutManager, mouse: MouseEvent, area: phantom.Rect) !bool {
        const tab = self.getActiveTab() orelse return false;
        if (tab.root.getEditorAt(area, mouse.position.x, mouse.position.y)) |editor| {
            tab.active_editor = editor;
            return true;
        }
        return false;
    }

    /// Handle Ctrl+W window commands
    pub fn handleWindowCommand(self: *LayoutManager, direction: Direction) !bool {
        const tab = self.getActiveTab() orelse return false;
        const current_editor = tab.active_editor;

        // Find the editor in the given direction
        const editor_area = phantom.Rect.init(0, 0, self.width, self.height);
        if (try self.findEditorInDirection(tab.root, current_editor, direction, editor_area)) |new_editor| {
            tab.active_editor = new_editor;
            return true;
        }

        return false;
    }

    /// Find the editor in a given direction from the current editor
    fn findEditorInDirection(
        self: *LayoutManager,
        node: *SplitNode,
        current: *grim_editor_widget.GrimEditorWidget,
        direction: Direction,
        area: phantom.Rect,
    ) !?*grim_editor_widget.GrimEditorWidget {

        // Get current editor position
        const current_pos = try self.getEditorPosition(node, current, area) orelse return null;

        // Find all editors and their positions
        var candidates = std.ArrayList(EditorCandidate){};
        defer candidates.deinit(self.allocator);

        try self.collectEditorPositions(node, area, &candidates);

        // Filter candidates by direction
        var best_candidate: ?*grim_editor_widget.GrimEditorWidget = null;
        var best_distance: i32 = std.math.maxInt(i32);

        for (candidates.items) |candidate| {
            if (candidate.editor == current) continue;

            const valid = switch (direction) {
                .left => candidate.center_x < current_pos.center_x,
                .right => candidate.center_x > current_pos.center_x,
                .up => candidate.center_y < current_pos.center_y,
                .down => candidate.center_y > current_pos.center_y,
            };

            if (!valid) continue;

            // Calculate distance (Manhattan distance)
            const dx = candidate.center_x - current_pos.center_x;
            const dy = candidate.center_y - current_pos.center_y;
            const distance: i32 = @intCast(@abs(dx) + @abs(dy));

            if (distance < best_distance) {
                best_distance = distance;
                best_candidate = candidate.editor;
            }
        }

        return best_candidate;
    }

    const EditorCandidate = struct {
        editor: *grim_editor_widget.GrimEditorWidget,
        center_x: i32,
        center_y: i32,
    };

    fn getEditorPosition(
        self: *LayoutManager,
        node: *SplitNode,
        target: *grim_editor_widget.GrimEditorWidget,
        area: phantom.Rect,
    ) !?EditorCandidate {

        switch (node.*) {
            .leaf => |editor| {
                if (editor == target) {
                    return EditorCandidate{
                        .editor = editor,
                        .center_x = @as(i32, @intCast(area.x)) + @divTrunc(@as(i32, @intCast(area.width)), 2),
                        .center_y = @as(i32, @intCast(area.y)) + @divTrunc(@as(i32, @intCast(area.height)), 2),
                    };
                }
                return null;
            },
            .vsplit => |vsplit| {
                const split_x = area.x + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.width)) * vsplit.ratio));
                const left_area = phantom.Rect.init(area.x, area.y, split_x - area.x, area.height);
                const right_area = phantom.Rect.init(split_x + 1, area.y, area.x + area.width - split_x - 1, area.height);

                if (try self.getEditorPosition(vsplit.left, target, left_area)) |pos| {
                    return pos;
                }
                if (try self.getEditorPosition(vsplit.right, target, right_area)) |pos| {
                    return pos;
                }
                return null;
            },
            .hsplit => |hsplit| {
                const split_y = area.y + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.height)) * hsplit.ratio));
                const top_area = phantom.Rect.init(area.x, area.y, area.width, split_y - area.y);
                const bottom_area = phantom.Rect.init(area.x, split_y + 1, area.width, area.y + area.height - split_y - 1);

                if (try self.getEditorPosition(hsplit.top, target, top_area)) |pos| {
                    return pos;
                }
                if (try self.getEditorPosition(hsplit.bottom, target, bottom_area)) |pos| {
                    return pos;
                }
                return null;
            },
        }
    }

    fn collectEditorPositions(
        self: *LayoutManager,
        node: *SplitNode,
        area: phantom.Rect,
        candidates: *std.ArrayList(EditorCandidate),
    ) !void {

        switch (node.*) {
            .leaf => |editor| {
                try candidates.append(self.allocator, EditorCandidate{
                    .editor = editor,
                    .center_x = @as(i32, @intCast(area.x)) + @divTrunc(@as(i32, @intCast(area.width)), 2),
                    .center_y = @as(i32, @intCast(area.y)) + @divTrunc(@as(i32, @intCast(area.height)), 2),
                });
            },
            .vsplit => |vsplit| {
                const split_x = area.x + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.width)) * vsplit.ratio));
                const left_area = phantom.Rect.init(area.x, area.y, split_x - area.x, area.height);
                const right_area = phantom.Rect.init(split_x + 1, area.y, area.x + area.width - split_x - 1, area.height);

                try self.collectEditorPositions(vsplit.left, left_area, candidates);
                try self.collectEditorPositions(vsplit.right, right_area, candidates);
            },
            .hsplit => |hsplit| {
                const split_y = area.y + @as(u16, @intFromFloat(@as(f32, @floatFromInt(area.height)) * hsplit.ratio));
                const top_area = phantom.Rect.init(area.x, area.y, area.width, split_y - area.y);
                const bottom_area = phantom.Rect.init(area.x, split_y + 1, area.width, area.y + area.height - split_y - 1);

                try self.collectEditorPositions(hsplit.top, top_area, candidates);
                try self.collectEditorPositions(hsplit.bottom, bottom_area, candidates);
            },
        }
    }

    // === Window resize ===

    pub fn resizeSplit(self: *LayoutManager, direction: ResizeDirection) !void {
        const tab = self.getActiveTab() orelse return;
        const current_editor = tab.active_editor;

        const delta: f32 = 0.1; // 10% resize increment

        try self.resizeSplitRecursive(tab.root, current_editor, direction, delta);
    }

    fn resizeSplitRecursive(
        self: *LayoutManager,
        node: *SplitNode,
        target: *grim_editor_widget.GrimEditorWidget,
        direction: ResizeDirection,
        delta: f32,
    ) !void {
        switch (node.*) {
            .leaf => {},
            .vsplit => |*vsplit| {
                // Check if target is in left or right
                if (try self.containsEditor(vsplit.left, target)) {
                    // Target is on the left
                    switch (direction) {
                        .increase => {
                            // Increase width of left pane
                            vsplit.ratio = @min(0.9, vsplit.ratio + delta);
                        },
                        .decrease => {
                            // Decrease width of left pane
                            vsplit.ratio = @max(0.1, vsplit.ratio - delta);
                        },
                        else => {},
                    }
                } else if (try self.containsEditor(vsplit.right, target)) {
                    // Target is on the right
                    switch (direction) {
                        .increase => {
                            // Increase width of right pane
                            vsplit.ratio = @max(0.1, vsplit.ratio - delta);
                        },
                        .decrease => {
                            // Decrease width of right pane
                            vsplit.ratio = @min(0.9, vsplit.ratio + delta);
                        },
                        else => {},
                    }
                }

                // Recursively resize children
                try self.resizeSplitRecursive(vsplit.left, target, direction, delta);
                try self.resizeSplitRecursive(vsplit.right, target, direction, delta);
            },
            .hsplit => |*hsplit| {
                // Check if target is in top or bottom
                if (try self.containsEditor(hsplit.top, target)) {
                    // Target is on the top
                    switch (direction) {
                        .increase_vertical => {
                            // Increase height of top pane
                            hsplit.ratio = @min(0.9, hsplit.ratio + delta);
                        },
                        .decrease_vertical => {
                            // Decrease height of top pane
                            hsplit.ratio = @max(0.1, hsplit.ratio - delta);
                        },
                        else => {},
                    }
                } else if (try self.containsEditor(hsplit.bottom, target)) {
                    // Target is on the bottom
                    switch (direction) {
                        .increase_vertical => {
                            // Increase height of bottom pane
                            hsplit.ratio = @max(0.1, hsplit.ratio - delta);
                        },
                        .decrease_vertical => {
                            // Decrease height of bottom pane
                            hsplit.ratio = @min(0.9, hsplit.ratio + delta);
                        },
                        else => {},
                    }
                }

                // Recursively resize children
                try self.resizeSplitRecursive(hsplit.top, target, direction, delta);
                try self.resizeSplitRecursive(hsplit.bottom, target, direction, delta);
            },
        }
    }

    fn containsEditor(self: *LayoutManager, node: *SplitNode, target: *grim_editor_widget.GrimEditorWidget) !bool {
        switch (node.*) {
            .leaf => |editor| return editor == target,
            .vsplit => |vsplit| {
                return try self.containsEditor(vsplit.left, target) or try self.containsEditor(vsplit.right, target);
            },
            .hsplit => |hsplit| {
                return try self.containsEditor(hsplit.top, target) or try self.containsEditor(hsplit.bottom, target);
            },
        }
    }

    pub fn equalizeSplits(self: *LayoutManager) void {
        const tab = self.getActiveTab() orelse return;
        self.equalizeSplitsRecursive(tab.root);
    }

    fn equalizeSplitsRecursive(self: *LayoutManager, node: *SplitNode) void {
        switch (node.*) {
            .leaf => {},
            .vsplit => |*vsplit| {
                vsplit.ratio = 0.5;
                self.equalizeSplitsRecursive(vsplit.left);
                self.equalizeSplitsRecursive(vsplit.right);
            },
            .hsplit => |*hsplit| {
                hsplit.ratio = 0.5;
                self.equalizeSplitsRecursive(hsplit.top);
                self.equalizeSplitsRecursive(hsplit.bottom);
            },
        }
    }

    // === Close window ===

    pub fn closeWindow(self: *LayoutManager) !void {
        const tab = self.getActiveTab() orelse return;
        const current_editor = tab.active_editor;

        // Count editors
        const editor_count = try self.countEditors(tab.root);
        if (editor_count <= 1) {
            return error.CannotCloseLastWindow;
        }

        // Close the editor and collapse the split
        if (try self.closeEditorAndCollapse(tab.root, current_editor)) |new_root| {
            // If root changed, update it
            const old_root = tab.root;
            tab.root = new_root;
            self.allocator.destroy(old_root);

            // Find a new active editor
            tab.active_editor = try self.findAnyEditor(tab.root) orelse return error.NoEditorsLeft;
        } else {
            // Root didn't change, find new active editor
            tab.active_editor = try self.findAnyEditor(tab.root) orelse return error.NoEditorsLeft;
        }
    }

    fn countEditors(self: *LayoutManager, node: *SplitNode) !usize {
        switch (node.*) {
            .leaf => return 1,
            .vsplit => |vsplit| {
                return try self.countEditors(vsplit.left) + try self.countEditors(vsplit.right);
            },
            .hsplit => |hsplit| {
                return try self.countEditors(hsplit.top) + try self.countEditors(hsplit.bottom);
            },
        }
    }

    fn closeEditorAndCollapse(self: *LayoutManager, node: *SplitNode, target: *grim_editor_widget.GrimEditorWidget) !?*SplitNode {
        switch (node.*) {
            .leaf => |editor| {
                if (editor == target) {
                    // Clean up this editor
                    editor.widget.vtable.deinit(&editor.widget);
                    return null; // Signal that this node should be removed
                }
                return null;
            },
            .vsplit => |*vsplit| {
                // Check if target is in left
                if (try self.containsEditor(vsplit.left, target)) {
                    if (try self.closeEditorAndCollapse(vsplit.left, target)) |_| {
                        // Left was replaced, shouldn't happen at this level
                    } else {
                        // Left was removed, promote right
                        const promoted = vsplit.right;
                        vsplit.left.deinit(self.allocator);
                        self.allocator.destroy(vsplit.left);
                        return promoted;
                    }
                }

                // Check if target is in right
                if (try self.containsEditor(vsplit.right, target)) {
                    if (try self.closeEditorAndCollapse(vsplit.right, target)) |_| {
                        // Right was replaced
                    } else {
                        // Right was removed, promote left
                        const promoted = vsplit.left;
                        vsplit.right.deinit(self.allocator);
                        self.allocator.destroy(vsplit.right);
                        return promoted;
                    }
                }

                return null;
            },
            .hsplit => |*hsplit| {
                // Check if target is in top
                if (try self.containsEditor(hsplit.top, target)) {
                    if (try self.closeEditorAndCollapse(hsplit.top, target)) |_| {
                        // Top was replaced
                    } else {
                        // Top was removed, promote bottom
                        const promoted = hsplit.bottom;
                        hsplit.top.deinit(self.allocator);
                        self.allocator.destroy(hsplit.top);
                        return promoted;
                    }
                }

                // Check if target is in bottom
                if (try self.containsEditor(hsplit.bottom, target)) {
                    if (try self.closeEditorAndCollapse(hsplit.bottom, target)) |_| {
                        // Bottom was replaced
                    } else {
                        // Bottom was removed, promote top
                        const promoted = hsplit.top;
                        hsplit.bottom.deinit(self.allocator);
                        self.allocator.destroy(hsplit.bottom);
                        return promoted;
                    }
                }

                return null;
            },
        }
    }

    fn findAnyEditor(self: *LayoutManager, node: *SplitNode) !?*grim_editor_widget.GrimEditorWidget {
        switch (node.*) {
            .leaf => |editor| return editor,
            .vsplit => |vsplit| {
                if (try self.findAnyEditor(vsplit.left)) |ed| return ed;
                return try self.findAnyEditor(vsplit.right);
            },
            .hsplit => |hsplit| {
                if (try self.findAnyEditor(hsplit.top)) |ed| return ed;
                return try self.findAnyEditor(hsplit.bottom);
            },
        }
    }

    pub fn closeOtherWindows(self: *LayoutManager) !void {
        const tab = self.getActiveTab() orelse return;
        const current_editor = tab.active_editor;

        // Clean up old root (but not the current editor)
        self.cleanupNodeExcept(tab.root, current_editor);

        // Create new root with just current editor
        const new_root = try self.allocator.create(SplitNode);
        new_root.* = .{ .leaf = current_editor };

        // Free old root structure (but not the editor itself)
        const old_root = tab.root;
        if (old_root != new_root) {
            self.allocator.destroy(old_root);
        }

        tab.root = new_root;
        tab.active_editor = current_editor;
    }

    fn cleanupNodeExcept(self: *LayoutManager, node: *SplitNode, keep: *grim_editor_widget.GrimEditorWidget) void {
        switch (node.*) {
            .leaf => |editor| {
                if (editor != keep) {
                    editor.widget.vtable.deinit(&editor.widget);
                }
            },
            .vsplit => |vsplit| {
                self.cleanupNodeExcept(vsplit.left, keep);
                self.cleanupNodeExcept(vsplit.right, keep);
                self.allocator.destroy(vsplit.left);
                self.allocator.destroy(vsplit.right);
            },
            .hsplit => |hsplit| {
                self.cleanupNodeExcept(hsplit.top, keep);
                self.cleanupNodeExcept(hsplit.bottom, keep);
                self.allocator.destroy(hsplit.top);
                self.allocator.destroy(hsplit.bottom);
            },
        }
    }

    // === Split management ===

    /// Split current window horizontally (top/bottom)
    pub fn horizontalSplit(self: *LayoutManager) !void {
        const tab = self.getActiveTab() orelse return error.NoActiveTab;
        const current_editor = tab.active_editor;

        // Create new editor
        const new_editor = try grim_editor_widget.GrimEditorWidget.init(self.allocator);
        errdefer new_editor.widget.vtable.deinit(&new_editor.widget);

        // Find the current editor in the tree and replace it with an hsplit
        try self.replaceEditorWithHSplit(tab.root, current_editor, new_editor);

        // New editor becomes active
        tab.active_editor = new_editor;
    }

    /// Split current window vertically (left/right)
    pub fn verticalSplit(self: *LayoutManager) !void {
        const tab = self.getActiveTab() orelse return error.NoActiveTab;
        const current_editor = tab.active_editor;

        // Create new editor
        const new_editor = try grim_editor_widget.GrimEditorWidget.init(self.allocator);
        errdefer new_editor.widget.vtable.deinit(&new_editor.widget);

        // Find the current editor in the tree and replace it with a vsplit
        try self.replaceEditorWithVSplit(tab.root, current_editor, new_editor);

        // New editor becomes active
        tab.active_editor = new_editor;
    }

    fn replaceEditorWithHSplit(self: *LayoutManager, node: *SplitNode, target: *grim_editor_widget.GrimEditorWidget, new_editor: *grim_editor_widget.GrimEditorWidget) !void {
        switch (node.*) {
            .leaf => |editor| {
                if (editor == target) {
                    // Replace this leaf with an hsplit
                    const top = try self.allocator.create(SplitNode);
                    top.* = .{ .leaf = editor };

                    const bottom = try self.allocator.create(SplitNode);
                    bottom.* = .{ .leaf = new_editor };

                    node.* = .{ .hsplit = .{ .top = top, .bottom = bottom, .ratio = 0.5 } };
                }
            },
            .vsplit => |*vsplit| {
                // Recursively search
                self.replaceEditorWithHSplit(vsplit.left, target, new_editor) catch {
                    try self.replaceEditorWithHSplit(vsplit.right, target, new_editor);
                };
            },
            .hsplit => |*hsplit| {
                // Recursively search
                self.replaceEditorWithHSplit(hsplit.top, target, new_editor) catch {
                    try self.replaceEditorWithHSplit(hsplit.bottom, target, new_editor);
                };
            },
        }
    }

    fn replaceEditorWithVSplit(self: *LayoutManager, node: *SplitNode, target: *grim_editor_widget.GrimEditorWidget, new_editor: *grim_editor_widget.GrimEditorWidget) !void {
        switch (node.*) {
            .leaf => |editor| {
                if (editor == target) {
                    // Replace this leaf with a vsplit
                    const left = try self.allocator.create(SplitNode);
                    left.* = .{ .leaf = editor };

                    const right = try self.allocator.create(SplitNode);
                    right.* = .{ .leaf = new_editor };

                    node.* = .{ .vsplit = .{ .left = left, .right = right, .ratio = 0.5 } };
                }
            },
            .vsplit => |*vsplit| {
                // Recursively search
                self.replaceEditorWithVSplit(vsplit.left, target, new_editor) catch {
                    try self.replaceEditorWithVSplit(vsplit.right, target, new_editor);
                };
            },
            .hsplit => |*hsplit| {
                // Recursively search
                self.replaceEditorWithVSplit(hsplit.top, target, new_editor) catch {
                    try self.replaceEditorWithVSplit(hsplit.bottom, target, new_editor);
                };
            },
        }
    }

    // === Tab management ===

    /// Create a new tab
    pub fn newTab(self: *LayoutManager) !void {
        const new_editor = try grim_editor_widget.GrimEditorWidget.init(self.allocator);
        errdefer new_editor.widget.vtable.deinit(&new_editor.widget);

        const tab_name = try std.fmt.allocPrint(self.allocator, "Tab {}", .{self.tabs.items.len + 1});
        defer self.allocator.free(tab_name);

        const new_tab = try TabPage.init(self.allocator, new_editor, tab_name);
        errdefer new_tab.deinit();

        try self.tabs.append(self.allocator, new_tab);
        self.active_tab_index = self.tabs.items.len - 1;
    }

    /// Switch to next tab
    pub fn nextTab(self: *LayoutManager) void {
        if (self.tabs.items.len == 0) return;
        self.active_tab_index = (self.active_tab_index + 1) % self.tabs.items.len;
    }

    /// Switch to previous tab
    pub fn prevTab(self: *LayoutManager) void {
        if (self.tabs.items.len == 0) return;
        if (self.active_tab_index == 0) {
            self.active_tab_index = self.tabs.items.len - 1;
        } else {
            self.active_tab_index -= 1;
        }
    }

    /// Switch to specific tab by index
    pub fn switchTab(self: *LayoutManager, index: usize) !void {
        if (index >= self.tabs.items.len) return error.InvalidTabIndex;
        self.active_tab_index = index;
    }

    /// Close current tab
    pub fn closeTab(self: *LayoutManager) !void {
        if (self.tabs.items.len <= 1) return error.CannotCloseLastTab;

        const tab = self.tabs.orderedRemove(self.active_tab_index);
        tab.deinit();

        // Adjust active tab index
        if (self.active_tab_index >= self.tabs.items.len) {
            self.active_tab_index = self.tabs.items.len - 1;
        }
    }

    // === Buffer management ===

    /// Get index of buffer containing the active editor
    pub fn getActiveBufferIndex(self: *LayoutManager) ?usize {
        const active_editor = self.getActiveEditor() orelse return null;
        for (self.buffers.items, 0..) |buffer, i| {
            if (buffer.editor == active_editor) {
                return i;
            }
        }
        return null;
    }

    /// Switch to next buffer
    pub fn bufferNext(self: *LayoutManager) !void {
        const current_idx = self.getActiveBufferIndex() orelse return;
        const next_idx = (current_idx + 1) % self.buffers.items.len;

        const tab = self.getActiveTab() orelse return;
        tab.active_editor = self.buffers.items[next_idx].editor;
    }

    /// Switch to previous buffer
    pub fn bufferPrev(self: *LayoutManager) !void {
        const current_idx = self.getActiveBufferIndex() orelse return;
        const prev_idx = if (current_idx == 0)
            self.buffers.items.len - 1
        else
            current_idx - 1;

        const tab = self.getActiveTab() orelse return;
        tab.active_editor = self.buffers.items[prev_idx].editor;
    }

    /// Delete/close current buffer
    pub fn bufferDelete(self: *LayoutManager) !void {
        const current_idx = self.getActiveBufferIndex() orelse return;

        if (self.buffers.items.len <= 1) {
            return error.CannotCloseLastBuffer;
        }

        // Get the buffer to delete
        const buffer = self.buffers.orderedRemove(current_idx);

        // Free buffer data
        self.allocator.free(buffer.name);
        if (buffer.filepath) |path| {
            self.allocator.free(path);
        }

        // Switch to next buffer before deleting editor
        const next_idx = if (current_idx >= self.buffers.items.len)
            self.buffers.items.len - 1
        else
            current_idx;

        const tab = self.getActiveTab() orelse return;
        tab.active_editor = self.buffers.items[next_idx].editor;

        // Free the editor widget
        buffer.editor.widget.vtable.deinit(&buffer.editor.widget);
    }

    /// Get list of all buffers (for display)
    pub fn getBufferList(self: *LayoutManager) []const Buffer {
        return self.buffers.items;
    }
};

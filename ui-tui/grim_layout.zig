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

pub const LayoutManager = struct {
    allocator: std.mem.Allocator,

    // Tab management
    tabs: std.ArrayList(*TabPage),
    active_tab_index: usize,

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

        self.* = .{
            .allocator = allocator,
            .tabs = tabs,
            .active_tab_index = 0,
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
        // TODO: Implement window navigation
        _ = self;
        _ = direction;
        std.log.warn("Window navigation not yet implemented", .{});
        return false;
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
};

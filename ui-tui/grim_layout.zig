//! LayoutManager - Manages editor windows, splits, and tabs (Neovim-style)

const std = @import("std");
const phantom = @import("phantom");
const grim_editor_widget = @import("grim_editor_widget.zig");

// Extract MouseEvent type from Event union (not exported from phantom root)
const MouseEvent = @typeInfo(phantom.Event).@"union".fields[1].type;


pub const LayoutManager = struct {
    allocator: std.mem.Allocator,

    // For MVP: Single editor window (no splits/tabs yet)
    active_editor: ?*grim_editor_widget.GrimEditorWidget,

    // Rendering area
    width: u16,
    height: u16,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !*LayoutManager {
        const self = try allocator.create(LayoutManager);

        self.* = .{
            .allocator = allocator,
            .active_editor = null,
            .width = width,
            .height = height,
        };

        return self;
    }

    pub fn deinit(self: *LayoutManager) void {
        if (self.active_editor) |editor| {
            editor.widget.vtable.deinit(&editor.widget);
        }
        self.allocator.destroy(self);
    }

    /// Create initial editor (called on startup)
    pub fn createInitialEditor(self: *LayoutManager) !void {
        const editor = try grim_editor_widget.GrimEditorWidget.init(self.allocator);
        self.active_editor = editor;
    }

    /// Get currently active editor
    pub fn getActiveEditor(self: *LayoutManager) ?*grim_editor_widget.GrimEditorWidget {
        return self.active_editor;
    }

    /// Render all editor windows
    pub fn render(self: *LayoutManager, buffer: anytype, area: phantom.Rect) void {
        if (self.active_editor) |editor| {
            editor.widget.render(buffer, area);
        }
    }

    /// Handle window resize
    pub fn resize(self: *LayoutManager, new_width: u16, new_height: u16) !void {
        self.width = new_width;
        self.height = new_height;

        if (self.active_editor) |editor| {
            const area = phantom.Rect.init(0, 0, new_width, new_height);
            editor.widget.resize(area);
        }
    }

    /// Handle mouse events (dispatch to correct editor)
    pub fn handleMouse(_: *LayoutManager, _: MouseEvent, _: anytype) !bool {
        // TODO: Implement mouse handling
        return false;
    }

    /// Handle Ctrl+W window commands
    pub fn handleWindowCommand(self: *LayoutManager, app: anytype) !bool {
        _ = app;
        // TODO: Implement window navigation commands
        // For now, just ignore
        _ = self;
        return false;
    }

    // === Split/Tab management (TODO for later) ===

    pub fn horizontalSplit(self: *LayoutManager) !void {
        // TODO: Implement horizontal split
        _ = self;
        std.log.warn("Horizontal split not yet implemented", .{});
    }

    pub fn verticalSplit(self: *LayoutManager) !void {
        // TODO: Implement vertical split
        _ = self;
        std.log.warn("Vertical split not yet implemented", .{});
    }

    pub fn newTab(self: *LayoutManager) !void {
        // TODO: Implement tab creation
        _ = self;
        std.log.warn("Tabs not yet implemented", .{});
    }
};

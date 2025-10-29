//! File tree widget for rendering

const std = @import("std");
const phantom = @import("phantom");
const file_tree = @import("file_tree.zig");

pub const FileTreeWidget = struct {
    allocator: std.mem.Allocator,
    tree: file_tree.FileTree,
    visible: bool,
    width: u16,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !FileTreeWidget {
        return .{
            .allocator = allocator,
            .tree = try file_tree.FileTree.init(allocator, root_path),
            .visible = false,
            .width = 30,
        };
    }

    pub fn deinit(self: *FileTreeWidget) void {
        self.tree.deinit();
    }

    pub fn toggle(self: *FileTreeWidget) !void {
        self.visible = !self.visible;
        if (self.visible) {
            try self.tree.refresh();
        }
    }

    pub fn render(self: *FileTreeWidget, buffer: anytype, area: phantom.Rect) !void {
        if (!self.visible) return;

        // Draw border
        const style = phantom.Style.default().withFg(phantom.Color.blue);
        buffer.drawRect(area, style);
        buffer.writeText(area.x + 2, area.y, " File Explorer ", style);

        // Render tree nodes
        var y: u16 = area.y + 1;
        for (self.tree.visible_nodes.items, 0..) |node, i| {
            if (y >= area.y + area.height - 1) break;

            const selected = (i == self.tree.selected_index);
            const line_style = if (selected)
                phantom.Style.default().withBg(phantom.Color.blue).withFg(phantom.Color.white)
            else
                phantom.Style.default();

            // Calculate depth
            var depth: usize = 0;
            var current_path = node.path;
            const root_path = self.tree.root.path;
            if (std.mem.startsWith(u8, current_path, root_path)) {
                const rel_path = current_path[root_path.len..];
                depth = std.mem.count(u8, rel_path, "/");
            }

            // Build display string with indentation
            var buf: [256]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            const writer = stream.writer();

            // Indentation
            var d: usize = 0;
            while (d < depth) : (d += 1) {
                writer.writeAll("  ") catch break;
            }

            // Icon
            const icon = if (node.is_dir)
                if (node.expanded) "[-] " else "[+] "
            else
                "    ";
            writer.writeAll(icon) catch {};

            // Git status indicator
            const git_icon = switch (node.git_status) {
                .modified => "M ",
                .added => "A ",
                .deleted => "D ",
                .untracked => "? ",
                .unmodified => "  ",
            };
            writer.writeAll(git_icon) catch {};

            // Name
            writer.writeAll(node.name) catch {};

            const display_text = stream.getWritten();
            const final_text = if (display_text.len > area.width - 2)
                display_text[0 .. area.width - 2]
            else
                display_text;

            buffer.writeText(area.x + 1, y, final_text, line_style);
            y += 1;
        }

        // Show help text at bottom
        buffer.writeText(area.x + 1, area.y + area.height - 1, " j/k: navigate, Enter: open/toggle ", style);
    }

    pub fn handleKey(self: *FileTreeWidget, key: phantom.Key) !bool {
        switch (key) {
            .char => |c| {
                switch (c) {
                    'j' => {
                        self.tree.selectNext();
                        return true;
                    },
                    'k' => {
                        self.tree.selectPrev();
                        return true;
                    },
                    'a' => {
                        // Create file
                        // TODO: Implement
                        return true;
                    },
                    'd' => {
                        // Delete file
                        // TODO: Implement
                        return true;
                    },
                    'r' => {
                        // Rename file
                        // TODO: Implement
                        return true;
                    },
                    else => return false,
                }
            },
            .enter => {
                try self.tree.toggleSelected();
                try self.tree.refresh();
                return true;
            },
            .escape => {
                self.visible = false;
                return true;
            },
            else => return false,
        }
    }

    pub fn getSelectedPath(self: *FileTreeWidget) ?[]const u8 {
        if (self.tree.getSelected()) |node| {
            return node.path;
        }
        return null;
    }

    pub fn refresh(self: *FileTreeWidget) !void {
        try self.tree.refresh();
        try self.tree.updateGitStatus();
    }
};

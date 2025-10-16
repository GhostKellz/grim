const std = @import("std");

/// File tree entry representing a file or directory
pub const TreeEntry = struct {
    name: []const u8,
    path: []const u8,
    is_dir: bool,
    depth: usize,
    expanded: bool,
    children: std.ArrayList(*TreeEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8, is_dir: bool, depth: usize) !*TreeEntry {
        const entry = try allocator.create(TreeEntry);
        entry.* = .{
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .is_dir = is_dir,
            .depth = depth,
            .expanded = false,
            .children = .empty,
            .allocator = allocator,
        };
        return entry;
    }

    pub fn deinit(self: *TreeEntry) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }
};

/// File tree viewer with navigation and expansion
pub const FileTree = struct {
    allocator: std.mem.Allocator,
    root: ?*TreeEntry,
    root_path: []const u8,
    visible_entries: std.ArrayList(*TreeEntry),
    selected_index: usize,
    scroll_offset: usize,
    show_hidden: bool,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !FileTree {
        return FileTree{
            .allocator = allocator,
            .root = null,
            .root_path = try allocator.dupe(u8, root_path),
            .visible_entries = .empty,
            .selected_index = 0,
            .scroll_offset = 0,
            .show_hidden = false,
        };
    }

    pub fn deinit(self: *FileTree) void {
        if (self.root) |root| {
            root.deinit();
        }
        self.visible_entries.deinit(self.allocator);
        self.allocator.free(self.root_path);
    }

    /// Load directory tree starting from root_path
    pub fn load(self: *FileTree) !void {
        // Clean up existing tree
        if (self.root) |root| {
            root.deinit();
        }
        self.visible_entries.clearRetainingCapacity();

        // Create root entry
        const root_name = std.fs.path.basename(self.root_path);
        self.root = try TreeEntry.init(self.allocator, root_name, self.root_path, true, 0);
        self.root.?.expanded = true;

        // Load root directory
        try self.loadDirectory(self.root.?);

        // Rebuild visible entries list
        try self.rebuildVisibleList();
    }

    /// Load directory contents into a tree entry
    fn loadDirectory(self: *FileTree, entry: *TreeEntry) !void {
        if (!entry.is_dir) return;

        var dir = try std.fs.cwd().openDir(entry.path, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();

        // Collect entries for sorting
        var entries: std.ArrayList(std.fs.Dir.Entry) = .empty;
        defer entries.deinit(self.allocator);

        while (try it.next()) |dir_entry| {
            // Skip hidden files unless show_hidden is true
            if (!self.show_hidden and dir_entry.name[0] == '.') {
                continue;
            }

            try entries.append(self.allocator, dir_entry);
        }

        // Sort: directories first, then alphabetically
        std.mem.sort(std.fs.Dir.Entry, entries.items, {}, struct {
            fn lessThan(_: void, a: std.fs.Dir.Entry, b: std.fs.Dir.Entry) bool {
                const a_is_dir = a.kind == .directory;
                const b_is_dir = b.kind == .directory;

                if (a_is_dir != b_is_dir) {
                    return a_is_dir;
                }

                return std.mem.order(u8, a.name[0..], b.name[0..]) == .lt;
            }
        }.lessThan);

        // Create child entries
        for (entries.items) |dir_entry| {
            const child_path = try std.fs.path.join(self.allocator, &[_][]const u8{ entry.path, dir_entry.name[0..] });
            defer self.allocator.free(child_path);

            const is_dir = dir_entry.kind == .directory;
            const child = try TreeEntry.init(self.allocator, dir_entry.name[0..], child_path, is_dir, entry.depth + 1);
            try entry.children.append(entry.allocator, child);
        }
    }

    /// Rebuild the visible entries list based on expanded state
    fn rebuildVisibleList(self: *FileTree) !void {
        self.visible_entries.clearRetainingCapacity();
        if (self.root) |root| {
            try self.addVisibleEntry(root);
        }
    }

    fn addVisibleEntry(self: *FileTree, entry: *TreeEntry) !void {
        try self.visible_entries.append(self.allocator, entry);

        if (entry.expanded) {
            for (entry.children.items) |child| {
                try self.addVisibleEntry(child);
            }
        }
    }

    /// Toggle expansion of the selected entry
    pub fn toggleExpanded(self: *FileTree) !void {
        if (self.selected_index >= self.visible_entries.items.len) return;

        const entry = self.visible_entries.items[self.selected_index];
        if (!entry.is_dir) return;

        entry.expanded = !entry.expanded;

        // Load directory contents if expanding for the first time
        if (entry.expanded and entry.children.items.len == 0) {
            try self.loadDirectory(entry);
        }

        try self.rebuildVisibleList();
    }

    /// Get the currently selected entry
    pub fn getSelectedEntry(self: *FileTree) ?*TreeEntry {
        if (self.selected_index >= self.visible_entries.items.len) return null;
        return self.visible_entries.items[self.selected_index];
    }

    /// Move selection up
    pub fn moveUp(self: *FileTree) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    /// Move selection down
    pub fn moveDown(self: *FileTree) void {
        if (self.selected_index + 1 < self.visible_entries.items.len) {
            self.selected_index += 1;
        }
    }

    /// Move selection to top
    pub fn moveToTop(self: *FileTree) void {
        self.selected_index = 0;
    }

    /// Move selection to bottom
    pub fn moveToBottom(self: *FileTree) void {
        if (self.visible_entries.items.len > 0) {
            self.selected_index = self.visible_entries.items.len - 1;
        }
    }

    /// Render the file tree to a writer
    pub fn render(self: *FileTree, writer: anytype, width: usize, height: usize) !void {
        // Adjust scroll offset to keep selection visible
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + height) {
            self.scroll_offset = self.selected_index - height + 1;
        }

        const end_index = @min(self.scroll_offset + height, self.visible_entries.items.len);

        for (self.visible_entries.items[self.scroll_offset..end_index], self.scroll_offset..) |entry, idx| {
            const is_selected = idx == self.selected_index;

            // Selection indicator
            if (is_selected) {
                try writer.writeAll("> ");
            } else {
                try writer.writeAll("  ");
            }

            // Indentation
            var i: usize = 0;
            while (i < entry.depth) : (i += 1) {
                try writer.writeAll("  ");
            }

            // Expansion indicator for directories
            if (entry.is_dir) {
                if (entry.expanded) {
                    try writer.writeAll("▼ ");
                } else {
                    try writer.writeAll("▶ ");
                }
            } else {
                try writer.writeAll("  ");
            }

            // File/directory name (truncate if too long)
            const max_name_len = width - 4 - (entry.depth * 2) - 2;
            if (entry.name.len > max_name_len) {
                try writer.writeAll(entry.name[0..max_name_len]);
            } else {
                try writer.writeAll(entry.name);
            }

            try writer.writeAll("\r\n");
        }

        // Fill remaining lines with empty space
        var remaining = height;
        if (end_index > self.scroll_offset) {
            remaining = height -| (end_index - self.scroll_offset);
        }
        while (remaining > 0) : (remaining -= 1) {
            try writer.writeAll("~\r\n");
        }
    }

    /// Reload the current directory (useful after file system changes)
    pub fn reload(self: *FileTree) !void {
        const selected_path = if (self.getSelectedEntry()) |entry|
            try self.allocator.dupe(u8, entry.path)
        else
            null;
        defer if (selected_path) |path| self.allocator.free(path);

        try self.load();

        // Try to restore selection
        if (selected_path) |path| {
            for (self.visible_entries.items, 0..) |entry, idx| {
                if (std.mem.eql(u8, entry.path, path)) {
                    self.selected_index = idx;
                    break;
                }
            }
        }
    }

    /// Toggle show hidden files
    pub fn toggleHidden(self: *FileTree) !void {
        self.show_hidden = !self.show_hidden;
        try self.reload();
    }
};

test "file tree basic" {
    const allocator = std.testing.allocator;

    var tree = try FileTree.init(allocator, ".");
    defer tree.deinit();

    try tree.load();

    // Should have at least the root entry
    try std.testing.expect(tree.visible_entries.items.len > 0);
}

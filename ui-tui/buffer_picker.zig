const std = @import("std");
const buffer_manager = @import("buffer_manager.zig");

/// Buffer Picker UI - Fuzzy finder for buffer selection
/// Displays buffer list with fuzzy search, modified indicators, and quick navigation
pub const BufferPicker = struct {
    allocator: std.mem.Allocator,
    buffer_manager: *buffer_manager.BufferManager,
    search_query: std.ArrayList(u8),
    filtered_buffers: std.ArrayList(FilteredBuffer),
    selected_index: usize,
    visible_start: usize,
    visible_height: usize,

    pub const FilteredBuffer = struct {
        buffer_id: u32,
        display_name: []const u8,
        file_path: ?[]const u8,
        modified: bool,
        line_count: usize,
        language: []const u8,
        match_score: usize, // Higher score = better match
    };

    pub fn init(allocator: std.mem.Allocator, buffer_manager_ptr: *buffer_manager.BufferManager) BufferPicker {
        return BufferPicker{
            .allocator = allocator,
            .buffer_manager = buffer_manager_ptr,
            .search_query = std.ArrayList(u8).init(allocator),
            .filtered_buffers = std.ArrayList(FilteredBuffer).init(allocator),
            .selected_index = 0,
            .visible_start = 0,
            .visible_height = 10,
        };
    }

    pub fn deinit(self: *BufferPicker) void {
        self.search_query.deinit();
        self.filtered_buffers.deinit();
    }

    /// Update search query and refresh filtered list
    pub fn setSearchQuery(self: *BufferPicker, query: []const u8) !void {
        self.search_query.clearRetainingCapacity();
        try self.search_query.appendSlice(query);
        try self.refreshFilteredBuffers();
    }

    /// Append character to search query
    pub fn appendToQuery(self: *BufferPicker, char: u8) !void {
        try self.search_query.append(char);
        try self.refreshFilteredBuffers();
    }

    /// Remove last character from search query
    pub fn backspaceQuery(self: *BufferPicker) !void {
        if (self.search_query.items.len > 0) {
            _ = self.search_query.pop();
            try self.refreshFilteredBuffers();
        }
    }

    /// Clear search query
    pub fn clearQuery(self: *BufferPicker) !void {
        self.search_query.clearRetainingCapacity();
        try self.refreshFilteredBuffers();
    }

    /// Move selection up
    pub fn moveUp(self: *BufferPicker) void {
        if (self.filtered_buffers.items.len == 0) return;

        if (self.selected_index > 0) {
            self.selected_index -= 1;
        } else {
            self.selected_index = self.filtered_buffers.items.len - 1;
        }

        self.adjustVisibleWindow();
    }

    /// Move selection down
    pub fn moveDown(self: *BufferPicker) void {
        if (self.filtered_buffers.items.len == 0) return;

        self.selected_index = (self.selected_index + 1) % self.filtered_buffers.items.len;
        self.adjustVisibleWindow();
    }

    /// Get currently selected buffer ID
    pub fn getSelectedBufferId(self: *const BufferPicker) ?u32 {
        if (self.selected_index < self.filtered_buffers.items.len) {
            return self.filtered_buffers.items[self.selected_index].buffer_id;
        }
        return null;
    }

    /// Get visible buffer items for rendering
    pub fn getVisibleItems(self: *const BufferPicker) []const FilteredBuffer {
        const end = @min(self.visible_start + self.visible_height, self.filtered_buffers.items.len);
        if (self.visible_start >= self.filtered_buffers.items.len) {
            return &[_]FilteredBuffer{};
        }
        return self.filtered_buffers.items[self.visible_start..end];
    }

    /// Get render info for UI
    pub const RenderInfo = struct {
        query: []const u8,
        total_count: usize,
        visible_items: []const FilteredBuffer,
        selected_index: usize,
        visible_start: usize,
    };

    pub fn getRenderInfo(self: *const BufferPicker) RenderInfo {
        return .{
            .query = self.search_query.items,
            .total_count = self.filtered_buffers.items.len,
            .visible_items = self.getVisibleItems(),
            .selected_index = self.selected_index,
            .visible_start = self.visible_start,
        };
    }

    // Private methods

    fn refreshFilteredBuffers(self: *BufferPicker) !void {
        self.filtered_buffers.clearRetainingCapacity();

        const buffer_list = try self.buffer_manager.getBufferList(self.allocator);
        defer self.allocator.free(buffer_list);

        const query = self.search_query.items;

        for (buffer_list) |info| {
            const score = fuzzyMatch(query, info.display_name);

            // Also check file path if available
            const path_score = if (info.file_path) |path|
                fuzzyMatch(query, path)
            else
                0;

            const final_score = @max(score, path_score);

            // If query is empty, show all buffers
            // Otherwise only show matches
            if (query.len == 0 or final_score > 0) {
                try self.filtered_buffers.append(.{
                    .buffer_id = info.id,
                    .display_name = info.display_name,
                    .file_path = info.file_path,
                    .modified = info.modified,
                    .line_count = info.line_count,
                    .language = info.language,
                    .match_score = final_score,
                });
            }
        }

        // Sort by match score (descending)
        std.mem.sort(FilteredBuffer, self.filtered_buffers.items, {}, struct {
            fn lessThan(_: void, a: FilteredBuffer, b: FilteredBuffer) bool {
                return a.match_score > b.match_score;
            }
        }.lessThan);

        // Reset selection
        self.selected_index = 0;
        self.visible_start = 0;
    }

    fn adjustVisibleWindow(self: *BufferPicker) void {
        if (self.filtered_buffers.items.len == 0) return;

        // Ensure selected item is visible
        if (self.selected_index < self.visible_start) {
            self.visible_start = self.selected_index;
        } else if (self.selected_index >= self.visible_start + self.visible_height) {
            self.visible_start = self.selected_index - self.visible_height + 1;
        }
    }

    /// Simple fuzzy matching algorithm
    /// Returns score (0 = no match, higher = better match)
    fn fuzzyMatch(query: []const u8, text: []const u8) usize {
        if (query.len == 0) return 1; // Empty query matches everything with low score

        var score: usize = 0;
        var query_idx: usize = 0;
        var consecutive_matches: usize = 0;

        for (text, 0..) |char, text_idx| {
            if (query_idx >= query.len) break;

            // Case-insensitive matching
            const q_char = std.ascii.toLower(query[query_idx]);
            const t_char = std.ascii.toLower(char);

            if (q_char == t_char) {
                // Base score for match
                score += 1;

                // Bonus for consecutive matches
                consecutive_matches += 1;
                score += consecutive_matches;

                // Bonus for match at word start
                if (text_idx == 0 or text[text_idx - 1] == '/' or text[text_idx - 1] == '_') {
                    score += 5;
                }

                query_idx += 1;
            } else {
                consecutive_matches = 0;
            }
        }

        // Only consider it a match if all query characters were found
        if (query_idx < query.len) return 0;

        return score;
    }
};

test "BufferPicker init and basic operations" {
    const allocator = std.testing.allocator;

    var mgr = try buffer_manager.BufferManager.init(allocator);
    defer mgr.deinit();

    var picker = BufferPicker.init(allocator, &mgr);
    defer picker.deinit();

    try std.testing.expectEqual(@as(usize, 0), picker.selected_index);
}

test "BufferPicker fuzzy search" {
    const allocator = std.testing.allocator;

    var mgr = try buffer_manager.BufferManager.init(allocator);
    defer mgr.deinit();

    // Create some test buffers
    const buf1 = mgr.buffers.items[0];
    buf1.display_name = "main.zig";

    _ = try mgr.createBuffer();
    const buf2 = &mgr.buffers.items[1];
    try buf2.setFilePath(allocator, "src/editor.zig");

    var picker = BufferPicker.init(allocator, &mgr);
    defer picker.deinit();

    // Search for "main"
    try picker.setSearchQuery("main");

    const info = picker.getRenderInfo();
    try std.testing.expect(info.total_count >= 1);
}

test "BufferPicker navigation" {
    const allocator = std.testing.allocator;

    var mgr = try buffer_manager.BufferManager.init(allocator);
    defer mgr.deinit();

    _ = try mgr.createBuffer();
    _ = try mgr.createBuffer();

    var picker = BufferPicker.init(allocator, &mgr);
    defer picker.deinit();

    try picker.refreshFilteredBuffers();

    try std.testing.expectEqual(@as(usize, 0), picker.selected_index);

    picker.moveDown();
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);

    picker.moveDown();
    try std.testing.expectEqual(@as(usize, 2), picker.selected_index);

    picker.moveUp();
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);
}

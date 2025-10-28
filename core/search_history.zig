//! Search and command history management
//! Provides vim-style history for / ? : searches and commands

const std = @import("std");

pub const SearchHistory = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList([]const u8),
    max_entries: usize,
    current_index: ?usize,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize) SearchHistory {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .max_entries = max_entries,
            .current_index = null,
        };
    }

    pub fn deinit(self: *SearchHistory) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.entries.deinit(self.allocator);
    }

    /// Add a search pattern to history
    pub fn add(self: *SearchHistory, pattern: []const u8) !void {
        if (pattern.len == 0) return;

        // Don't add duplicates of the most recent entry
        if (self.entries.items.len > 0) {
            const last = self.entries.items[self.entries.items.len - 1];
            if (std.mem.eql(u8, last, pattern)) {
                return;
            }
        }

        // Add new entry
        const owned = try self.allocator.dupe(u8, pattern);
        errdefer self.allocator.free(owned);

        try self.entries.append(self.allocator, owned);

        // Remove oldest if we exceeded max
        if (self.entries.items.len > self.max_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed);
        }

        // Reset index
        self.current_index = null;
    }

    /// Get previous entry (up arrow)
    pub fn prev(self: *SearchHistory) ?[]const u8 {
        if (self.entries.items.len == 0) return null;

        if (self.current_index) |idx| {
            if (idx > 0) {
                self.current_index = idx - 1;
                return self.entries.items[idx - 1];
            }
            return self.entries.items[idx];
        } else {
            // Start from the end
            self.current_index = self.entries.items.len - 1;
            return self.entries.items[self.entries.items.len - 1];
        }
    }

    /// Get next entry (down arrow)
    pub fn next(self: *SearchHistory) ?[]const u8 {
        if (self.entries.items.len == 0) return null;

        if (self.current_index) |idx| {
            if (idx + 1 < self.entries.items.len) {
                self.current_index = idx + 1;
                return self.entries.items[idx + 1];
            }
            // At the end, clear index (user can type new search)
            self.current_index = null;
            return null;
        }

        return null;
    }

    /// Reset navigation index
    pub fn resetIndex(self: *SearchHistory) void {
        self.current_index = null;
    }

    /// Get all entries (for display)
    pub fn getAll(self: *const SearchHistory) []const []const u8 {
        return self.entries.items;
    }

    /// Get most recent entry
    pub fn getLast(self: *const SearchHistory) ?[]const u8 {
        if (self.entries.items.len > 0) {
            return self.entries.items[self.entries.items.len - 1];
        }
        return null;
    }
};

test "search history basic operations" {
    const allocator = std.testing.allocator;

    var history = SearchHistory.init(allocator, 5);
    defer history.deinit();

    // Add entries
    try history.add("foo");
    try history.add("bar");
    try history.add("baz");

    try std.testing.expectEqual(@as(usize, 3), history.entries.items.len);

    // Test prev navigation
    const entry1 = history.prev() orelse unreachable;
    try std.testing.expectEqualStrings("baz", entry1);

    const entry2 = history.prev() orelse unreachable;
    try std.testing.expectEqualStrings("bar", entry2);

    const entry3 = history.prev() orelse unreachable;
    try std.testing.expectEqualStrings("foo", entry3);

    // Test next navigation
    const entry4 = history.next() orelse unreachable;
    try std.testing.expectEqualStrings("bar", entry4);
}

test "search history max entries" {
    const allocator = std.testing.allocator;

    var history = SearchHistory.init(allocator, 3);
    defer history.deinit();

    try history.add("one");
    try history.add("two");
    try history.add("three");
    try history.add("four");

    // Should only have 3 entries (oldest removed)
    try std.testing.expectEqual(@as(usize, 3), history.entries.items.len);
    try std.testing.expectEqualStrings("two", history.entries.items[0]);
    try std.testing.expectEqualStrings("four", history.entries.items[2]);
}

test "search history no duplicates" {
    const allocator = std.testing.allocator;

    var history = SearchHistory.init(allocator, 5);
    defer history.deinit();

    try history.add("foo");
    try history.add("foo"); // Duplicate, should not be added

    try std.testing.expectEqual(@as(usize, 1), history.entries.items.len);
}

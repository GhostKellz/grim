const std = @import("std");

/// Fuzzy finder module for Grim (Telescope-style)
/// Fast fuzzy string matching using FZF algorithm
pub const FuzzyFinder = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry),
    filtered: std.ArrayList(ScoredEntry),

    pub const Entry = struct {
        path: []const u8,
        display: []const u8,
    };

    pub const ScoredEntry = struct {
        entry: Entry,
        score: i32,
        match_positions: []usize,
    };

    pub fn init(allocator: std.mem.Allocator) FuzzyFinder {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .filtered = .empty,
        };
    }

    pub fn deinit(self: *FuzzyFinder) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.path);
            self.allocator.free(entry.display);
        }
        self.entries.deinit(self.allocator);

        for (self.filtered.items) |scored| {
            self.allocator.free(scored.match_positions);
        }
        self.filtered.deinit(self.allocator);
    }

    /// Add an entry to the finder
    pub fn addEntry(self: *FuzzyFinder, path: []const u8, display: []const u8) !void {
        const entry = Entry{
            .path = try self.allocator.dupe(u8, path),
            .display = try self.allocator.dupe(u8, display),
        };
        try self.entries.append(self.allocator, entry);
    }

    const MatchResult = struct {
        score: i32,
        positions: []usize,
    };

    /// Fuzzy match algorithm (simplified FZF)
    pub fn fuzzyMatch(needle: []const u8, haystack: []const u8, allocator: std.mem.Allocator) !?MatchResult {
        if (needle.len == 0) {
            return .{ .score = 0, .positions = &.{} };
        }

        var positions: std.ArrayList(usize) = .empty;
        defer positions.deinit(allocator);

        var score: i32 = 0;
        var needle_idx: usize = 0;
        var consecutive_match: i32 = 0;

        for (haystack, 0..) |hay_char, hay_idx| {
            if (needle_idx >= needle.len) break;

            const needle_char = needle[needle_idx];
            const hay_lower = std.ascii.toLower(hay_char);
            const needle_lower = std.ascii.toLower(needle_char);

            if (hay_lower == needle_lower) {
                try positions.append(allocator, hay_idx);
                needle_idx += 1;

                // Bonus for consecutive matches
                consecutive_match += 1;
                score += 1 + consecutive_match;

                // Bonus for matching at word boundaries
                if (hay_idx == 0 or haystack[hay_idx - 1] == '/' or haystack[hay_idx - 1] == '_') {
                    score += 5;
                }

                // Bonus for camelCase matches
                if (hay_idx > 0 and std.ascii.isLower(haystack[hay_idx - 1]) and std.ascii.isUpper(hay_char)) {
                    score += 3;
                }
            } else {
                consecutive_match = 0;
                score -= 1; // Penalty for gaps
            }
        }

        // All needle chars must match
        if (needle_idx != needle.len) {
            return null;
        }

        return .{
            .score = score,
            .positions = try positions.toOwnedSlice(allocator),
        };
    }

    /// Filter entries by query string
    pub fn filter(self: *FuzzyFinder, query: []const u8) !void {
        // Clear previous results
        for (self.filtered.items) |scored| {
            self.allocator.free(scored.match_positions);
        }
        self.filtered.clearRetainingCapacity();

        if (query.len == 0) {
            // No filter, show all
            for (self.entries.items) |entry| {
                try self.filtered.append(self.allocator, .{
                    .entry = entry,
                    .score = 0,
                    .match_positions = &.{},
                });
            }
            return;
        }

        // Score all entries
        for (self.entries.items) |entry| {
            if (try fuzzyMatch(query, entry.display, self.allocator)) |match| {
                try self.filtered.append(self.allocator, .{
                    .entry = entry,
                    .score = match.score,
                    .match_positions = match.positions,
                });
            }
        }

        // Sort by score (descending)
        std.mem.sort(ScoredEntry, self.filtered.items, {}, compareScore);
    }

    fn compareScore(_: void, a: ScoredEntry, b: ScoredEntry) bool {
        return a.score > b.score;
    }

    /// Get filtered results
    pub fn getResults(self: *FuzzyFinder) []const ScoredEntry {
        return self.filtered.items;
    }

    /// Find files in directory recursively
    pub fn findFiles(self: *FuzzyFinder, root: []const u8, max_depth: usize) !void {
        try self.findFilesRecursive(root, root, 0, max_depth);
    }

    fn findFilesRecursive(self: *FuzzyFinder, root: []const u8, current: []const u8, depth: usize, max_depth: usize) !void {
        if (depth > max_depth) return;

        var dir = std.fs.cwd().openDir(current, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Skip hidden files and common ignore patterns
            if (entry.name[0] == '.') continue;
            if (std.mem.eql(u8, entry.name, "node_modules")) continue;
            if (std.mem.eql(u8, entry.name, "zig-cache")) continue;
            if (std.mem.eql(u8, entry.name, "zig-out")) continue;
            if (std.mem.eql(u8, entry.name, "target")) continue;

            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current, entry.name });
            defer self.allocator.free(full_path);

            if (entry.kind == .directory) {
                try self.findFilesRecursive(root, full_path, depth + 1, max_depth);
            } else if (entry.kind == .file) {
                // Get relative path from root
                const rel_path = if (std.mem.startsWith(u8, full_path, root))
                    full_path[root.len..]
                else
                    full_path;

                // Skip leading slash
                const display_path = if (rel_path.len > 0 and rel_path[0] == '/')
                    rel_path[1..]
                else
                    rel_path;

                try self.addEntry(full_path, display_path);
            }
        }
    }

    /// Grep files for pattern
    pub fn grepFiles(_: *FuzzyFinder, _: []const u8, _: []const u8) !void {
        // TODO: Implement grep functionality
        // For now, just a placeholder
    }
};

/// File picker (Telescope-style UI)
pub const FilePicker = struct {
    finder: FuzzyFinder,
    query: std.ArrayList(u8),
    selected_idx: usize,

    pub fn init(allocator: std.mem.Allocator) FilePicker {
        return .{
            .finder = FuzzyFinder.init(allocator),
            .query = .empty,
            .selected_idx = 0,
        };
    }

    pub fn deinit(self: *FilePicker) void {
        self.finder.deinit();
        self.query.deinit(self.finder.allocator);
    }

    pub fn updateQuery(self: *FilePicker, new_query: []const u8) !void {
        self.query.clearRetainingCapacity();
        try self.query.appendSlice(self.finder.allocator, new_query);
        try self.finder.filter(self.query.items);
        self.selected_idx = 0;
    }

    pub fn moveSelection(self: *FilePicker, delta: i32) void {
        const results = self.finder.getResults();
        if (results.len == 0) return;

        if (delta > 0) {
            self.selected_idx = @min(self.selected_idx + @as(usize, @intCast(delta)), results.len - 1);
        } else if (delta < 0) {
            const abs_delta = @as(usize, @intCast(-delta));
            if (self.selected_idx >= abs_delta) {
                self.selected_idx -= abs_delta;
            } else {
                self.selected_idx = 0;
            }
        }
    }

    pub fn getSelected(self: *FilePicker) ?[]const u8 {
        const results = self.finder.getResults();
        if (self.selected_idx < results.len) {
            return results[self.selected_idx].entry.path;
        }
        return null;
    }
};

test "fuzzy match basic" {
    const allocator = std.testing.allocator;

    const result = try FuzzyFinder.fuzzyMatch("fz", "fuzzy_finder.zig", allocator);
    try std.testing.expect(result != null);
    if (result) |match| {
        defer allocator.free(match.positions);
        try std.testing.expect(match.score > 0);
    }
}

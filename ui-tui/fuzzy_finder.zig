//! Fuzzy finder for quick file navigation

const std = @import("std");
const phantom = @import("phantom");

pub const FuzzyMatch = struct {
    path: []const u8,
    score: i32,
    indices: []usize, // Matching character indices
};

pub const FuzzyFinder = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayList([]const u8),
    matches: std.ArrayList(FuzzyMatch),
    query: []u8,
    selected_index: usize,
    visible: bool,

    pub fn init(allocator: std.mem.Allocator) FuzzyFinder {
        return .{
            .allocator = allocator,
            .files = std.ArrayList([]const u8){},
            .matches = std.ArrayList(FuzzyMatch){},
            .query = &.{},
            .selected_index = 0,
            .visible = false,
        };
    }

    pub fn deinit(self: *FuzzyFinder) void {
        for (self.files.items) |file| {
            self.allocator.free(file);
        }
        self.files.deinit(self.allocator);

        for (self.matches.items) |match| {
            self.allocator.free(match.indices);
        }
        self.matches.deinit(self.allocator);

        if (self.query.len > 0) {
            self.allocator.free(self.query);
        }
    }

    pub fn show(self: *FuzzyFinder) void {
        self.visible = true;
    }

    pub fn hide(self: *FuzzyFinder) void {
        self.visible = false;
        self.selected_index = 0;
    }

    /// Scan directory recursively for files
    pub fn scanDirectory(self: *FuzzyFinder, root_path: []const u8) !void {
        // Clear previous files
        for (self.files.items) |file| {
            self.allocator.free(file);
        }
        self.files.clearRetainingCapacity();

        var dir = try std.fs.cwd().openDir(root_path, .{ .iterate = true });
        defer dir.close();

        try self.scanDirectoryRecursive(dir, root_path, "");
    }

    fn scanDirectoryRecursive(
        self: *FuzzyFinder,
        dir: std.fs.Dir,
        root_path: []const u8,
        rel_path: []const u8,
    ) !void {
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Skip hidden files and directories
            if (entry.name[0] == '.') continue;

            const full_rel_path = if (rel_path.len > 0)
                try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ rel_path, entry.name })
            else
                try self.allocator.dupe(u8, entry.name);

            if (entry.kind == .directory) {
                // Recursively scan subdirectory
                var subdir = try dir.openDir(entry.name, .{ .iterate = true });
                defer subdir.close();
                try self.scanDirectoryRecursive(subdir, root_path, full_rel_path);
                self.allocator.free(full_rel_path);
            } else if (entry.kind == .file) {
                try self.files.append(self.allocator, full_rel_path);
            } else {
                self.allocator.free(full_rel_path);
            }
        }
    }

    /// Update query and recalculate matches
    pub fn setQuery(self: *FuzzyFinder, query: []const u8) !void {
        if (self.query.len > 0) {
            self.allocator.free(self.query);
        }
        self.query = try self.allocator.dupe(u8, query);

        // Clear old matches
        for (self.matches.items) |match| {
            self.allocator.free(match.indices);
        }
        self.matches.clearRetainingCapacity();

        if (query.len == 0) {
            // No query - show all files
            for (self.files.items) |file| {
                try self.matches.append(self.allocator, .{
                    .path = file,
                    .score = 0,
                    .indices = &.{},
                });
            }
        } else {
            // Calculate fuzzy matches
            for (self.files.items) |file| {
                if (try self.fuzzyMatch(query, file)) |match| {
                    try self.matches.append(self.allocator, match);
                }
            }

            // Sort by score (higher is better)
            std.mem.sort(FuzzyMatch, self.matches.items, {}, struct {
                fn lessThan(_: void, a: FuzzyMatch, b: FuzzyMatch) bool {
                    return a.score > b.score;
                }
            }.lessThan);
        }

        self.selected_index = 0;
    }

    /// Fuzzy match algorithm - returns match with score and indices
    fn fuzzyMatch(self: *FuzzyFinder, query: []const u8, target: []const u8) !?FuzzyMatch {
        var indices = std.ArrayList(usize){};
        defer indices.deinit(self.allocator);

        var query_idx: usize = 0;
        var score: i32 = 0;
        var consecutive: i32 = 0;

        for (target, 0..) |ch, i| {
            if (query_idx >= query.len) break;

            const q_ch = query[query_idx];
            const q_lower = std.ascii.toLower(q_ch);
            const t_lower = std.ascii.toLower(ch);

            if (q_lower == t_lower) {
                try indices.append(self.allocator, i);
                query_idx += 1;

                // Bonus for consecutive matches
                consecutive += 1;
                score += 1 + consecutive;

                // Bonus for matching at word boundaries
                if (i == 0 or target[i - 1] == '/' or target[i - 1] == '_') {
                    score += 10;
                }
            } else {
                consecutive = 0;
            }
        }

        // Match only if all query characters found
        if (query_idx < query.len) {
            return null;
        }

        return FuzzyMatch{
            .path = target,
            .score = score,
            .indices = try indices.toOwnedSlice(self.allocator),
        };
    }

    pub fn selectNext(self: *FuzzyFinder) void {
        if (self.matches.items.len == 0) return;
        self.selected_index = (self.selected_index + 1) % self.matches.items.len;
    }

    pub fn selectPrev(self: *FuzzyFinder) void {
        if (self.matches.items.len == 0) return;
        if (self.selected_index == 0) {
            self.selected_index = self.matches.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
    }

    pub fn getSelected(self: *FuzzyFinder) ?[]const u8 {
        if (self.selected_index < self.matches.items.len) {
            return self.matches.items[self.selected_index].path;
        }
        return null;
    }

    pub fn render(self: *FuzzyFinder, buffer: anytype, area: phantom.Rect) !void {
        if (!self.visible) return;

        // Draw border
        const border_style = phantom.Style.default().withFg(phantom.Color.green);
        buffer.drawRect(area, border_style);

        // Draw title
        var title_buf: [128]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buf, " Fuzzy Finder ({d} matches) ", .{self.matches.items.len});
        buffer.writeText(area.x + 2, area.y, title, border_style);

        // Draw query
        var query_buf: [256]u8 = undefined;
        const query_text = try std.fmt.bufPrint(&query_buf, "> {s}_", .{self.query});
        buffer.writeText(area.x + 1, area.y + 1, query_text, phantom.Style.default());

        // Draw matches
        var y: u16 = area.y + 2;
        const max_y = area.y + area.height - 1;
        const start_index = if (self.selected_index > 10) self.selected_index - 10 else 0;

        for (self.matches.items[start_index..], start_index..) |match, i| {
            if (y >= max_y) break;

            const selected = (i == self.selected_index);
            const style = if (selected)
                phantom.Style.default().withBg(phantom.Color.green).withFg(phantom.Color.black)
            else
                phantom.Style.default();

            const display_text = if (match.path.len > area.width - 2)
                match.path[0 .. area.width - 2]
            else
                match.path;

            buffer.writeText(area.x + 1, y, display_text, style);
            y += 1;
        }
    }
};

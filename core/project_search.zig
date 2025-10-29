//! Project-wide search and replace using ripgrep

const std = @import("std");

pub const SearchResult = struct {
    filepath: []const u8,
    line_number: usize,
    column: usize,
    matched_line: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SearchResult) void {
        self.allocator.free(self.filepath);
        self.allocator.free(self.matched_line);
    }
};

pub const ProjectSearch = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(SearchResult),

    pub fn init(allocator: std.mem.Allocator) ProjectSearch {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(SearchResult).init(allocator),
        };
    }

    pub fn deinit(self: *ProjectSearch) void {
        for (self.results.items) |*result| {
            result.deinit();
        }
        self.results.deinit();
    }

    /// Search for pattern in project using ripgrep
    pub fn search(self: *ProjectSearch, pattern: []const u8, cwd: ?[]const u8) !void {
        // Clear previous results
        for (self.results.items) |*result| {
            result.deinit();
        }
        self.results.clearRetainingCapacity();

        // Build ripgrep command
        // rg --json --line-number --column <pattern>
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append("rg");
        try argv.append("--json");
        try argv.append("--line-number");
        try argv.append("--column");
        try argv.append("--no-heading");
        try argv.append("--");
        try argv.append(pattern);

        // Run ripgrep
        var child = std.process.Child.init(argv.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        if (cwd) |dir| {
            child.cwd = dir;
        }

        try child.spawn();

        // Read output
        const stdout_reader = child.stdout.?.reader();
        var buf: [4096]u8 = undefined;

        while (try stdout_reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            try self.parseLine(line);
        }

        _ = try child.wait();
    }

    /// Parse ripgrep JSON output line
    fn parseLine(self: *ProjectSearch, line: []const u8) !void {
        // Simple JSON parsing for ripgrep output
        // Format: {"type":"match","data":{"path":{"text":"file.zig"},"lines":{"text":"matched line"},"line_number":42,"absolute_offset":100,"submatches":[{"match":{"text":"pattern"},"start":5,"end":12}]}}

        var parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer parser.deinit();

        var tree = parser.parse(line) catch return; // Skip invalid lines
        defer tree.deinit();

        const root = tree.root;
        if (root != .object) return;

        const type_field = root.object.get("type") orelse return;
        if (type_field != .string) return;
        if (!std.mem.eql(u8, type_field.string, "match")) return;

        const data = root.object.get("data") orelse return;
        if (data != .object) return;

        // Extract fields
        const path_obj = data.object.get("path") orelse return;
        if (path_obj != .object) return;
        const path_text = path_obj.object.get("text") orelse return;
        if (path_text != .string) return;

        const lines_obj = data.object.get("lines") orelse return;
        if (lines_obj != .object) return;
        const lines_text = lines_obj.object.get("text") orelse return;
        if (lines_text != .string) return;

        const line_num = data.object.get("line_number") orelse return;
        if (line_num != .integer) return;

        // Get column from first submatch
        var column: usize = 0;
        if (data.object.get("submatches")) |submatches| {
            if (submatches == .array and submatches.array.items.len > 0) {
                const first_match = submatches.array.items[0];
                if (first_match == .object) {
                    if (first_match.object.get("start")) |start| {
                        if (start == .integer) {
                            column = @intCast(start.integer);
                        }
                    }
                }
            }
        }

        const result = SearchResult{
            .filepath = try self.allocator.dupe(u8, path_text.string),
            .line_number = @intCast(line_num.integer),
            .column = column,
            .matched_line = try self.allocator.dupe(u8, lines_text.string),
            .allocator = self.allocator,
        };

        try self.results.append(result);
    }

    /// Perform project-wide replace
    pub fn replace(
        self: *ProjectSearch,
        pattern: []const u8,
        replacement: []const u8,
        cwd: ?[]const u8,
    ) !usize {
        // First, search for all occurrences
        try self.search(pattern, cwd);

        // Group results by file
        var file_map = std.StringHashMap(std.ArrayList(*SearchResult)).init(self.allocator);
        defer {
            var iter = file_map.valueIterator();
            while (iter.next()) |list| {
                list.deinit();
            }
            file_map.deinit();
        }

        for (self.results.items) |*result| {
            const entry = try file_map.getOrPut(result.filepath);
            if (!entry.found_existing) {
                entry.value_ptr.* = std.ArrayList(*SearchResult).init(self.allocator);
            }
            try entry.value_ptr.append(result);
        }

        var total_replacements: usize = 0;

        // Process each file
        var iter = file_map.iterator();
        while (iter.next()) |entry| {
            const filepath = entry.key_ptr.*;
            const file_results = entry.value_ptr.*;

            // Read file
            const file_content = try std.fs.cwd().readFileAlloc(self.allocator, filepath, 100 * 1024 * 1024);
            defer self.allocator.free(file_content);

            // Replace all occurrences
            const new_content = try std.mem.replaceOwned(u8, self.allocator, file_content, pattern, replacement);
            defer self.allocator.free(new_content);

            // Write back to file
            const file = try std.fs.cwd().createFile(filepath, .{});
            defer file.close();
            try file.writeAll(new_content);

            total_replacements += file_results.items.len;
        }

        return total_replacements;
    }
};

test "project search basic" {
    const allocator = std.testing.allocator;

    var search = ProjectSearch.init(allocator);
    defer search.deinit();

    // This test requires ripgrep to be installed
    // search.search("TODO", null) catch |err| {
    //     std.debug.print("Search failed (ripgrep not installed?): {}\n", .{err});
    //     return;
    // };

    // std.debug.print("Found {d} results\n", .{search.results.items.len});
}

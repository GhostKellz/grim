//! Snippet system for Grim
//! Loads snippets from ~/.config/grim/snippets/<filetype>.json
//! Supports tab stops: ${1:placeholder}, ${2}, $0 (final position)
//! Supports variables: ${DATE}, ${AUTHOR}, ${FILE}, ${DIR}, ${CLIPBOARD}

const std = @import("std");

pub const TabStop = struct {
    index: u8, // 0 = final position, 1-9 = tab stops
    start: usize, // Byte offset in expanded snippet
    end: usize, // End of placeholder
    placeholder: ?[]const u8, // Optional placeholder text
};

pub const Snippet = struct {
    prefix: []const u8,
    body: []const []const u8, // Lines of the snippet
    description: ?[]const u8,

    pub fn deinit(self: *Snippet, allocator: std.mem.Allocator) void {
        allocator.free(self.prefix);
        for (self.body) |line| {
            allocator.free(line);
        }
        allocator.free(self.body);
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};

pub const SnippetLibrary = struct {
    allocator: std.mem.Allocator,
    snippets: std.StringHashMap(Snippet), // prefix -> snippet

    pub fn init(allocator: std.mem.Allocator) SnippetLibrary {
        return .{
            .allocator = allocator,
            .snippets = std.StringHashMap(Snippet).init(allocator),
        };
    }

    pub fn deinit(self: *SnippetLibrary) void {
        var iter = self.snippets.valueIterator();
        while (iter.next()) |snippet| {
            var mut_snippet = snippet.*;
            mut_snippet.deinit(self.allocator);
        }
        self.snippets.deinit();
    }

    /// Load snippets from ~/.config/grim/snippets/<filetype>.json
    pub fn loadForFiletype(self: *SnippetLibrary, filetype: []const u8) !void {
        // Get config directory
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

        // Build path: ~/.config/grim/snippets/<filetype>.json
        const path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/.config/grim/snippets/{s}.json",
            .{ home, filetype },
        );
        defer self.allocator.free(path);

        // Try to open the file
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No snippets for this filetype - not an error
                return;
            }
            return err;
        };
        defer file.close();

        // Read file content
        const stat = try file.stat();
        const file_size = stat.size;
        if (file_size > 10 * 1024 * 1024) return error.FileTooLarge;
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        const bytes_read = try file.readAll(content);

        // Parse JSON
        try self.parseSnippets(content[0..bytes_read]);
    }

    /// Parse snippets from JSON content
    fn parseSnippets(self: *SnippetLibrary, json_content: []const u8) !void {
        // Simple JSON parser for snippet format:
        // {
        //   "trigger": {
        //     "prefix": "fn",
        //     "body": ["fn ${1:name}() {", "  ${2:body}", "}"],
        //     "description": "Function"
        //   }
        // }

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_content, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidSnippetFormat;

        var it = root.object.iterator();
        while (it.next()) |entry| {
            const trigger_name = entry.key_ptr.*;
            const snippet_obj = entry.value_ptr.*;

            if (snippet_obj != .object) continue;

            const prefix = if (snippet_obj.object.get("prefix")) |p|
                if (p == .string) p.string else continue
            else
                continue;

            const body_array = if (snippet_obj.object.get("body")) |b|
                if (b == .array) b.array else continue
            else
                continue;

            const description = if (snippet_obj.object.get("description")) |d|
                if (d == .string) try self.allocator.dupe(u8, d.string) else null
            else
                null;

            // Convert body array to slice of strings
            var body_lines = try self.allocator.alloc([]const u8, body_array.items.len);
            for (body_array.items, 0..) |line_value, i| {
                if (line_value == .string) {
                    body_lines[i] = try self.allocator.dupe(u8, line_value.string);
                } else {
                    // Free previously allocated lines
                    for (body_lines[0..i]) |allocated_line| {
                        self.allocator.free(allocated_line);
                    }
                    self.allocator.free(body_lines);
                    if (description) |desc| self.allocator.free(desc);
                    continue;
                }
            }

            const snippet = Snippet{
                .prefix = try self.allocator.dupe(u8, prefix),
                .body = body_lines,
                .description = description,
            };

            // Store with trigger name as key
            try self.snippets.put(try self.allocator.dupe(u8, trigger_name), snippet);
        }
    }

    /// Get snippet by prefix
    pub fn getSnippet(self: *SnippetLibrary, prefix: []const u8) ?Snippet {
        return self.snippets.get(prefix);
    }

    /// Get all snippet prefixes (for completion)
    pub fn getAllPrefixes(self: *SnippetLibrary, allocator: std.mem.Allocator) ![][]const u8 {
        var prefixes = try std.ArrayList([]const u8).initCapacity(allocator, self.snippets.count());
        defer prefixes.deinit();

        var iter = self.snippets.iterator();
        while (iter.next()) |entry| {
            try prefixes.append(entry.value_ptr.prefix);
        }

        return prefixes.toOwnedSlice();
    }
};

/// Context for variable expansion in snippets
pub const SnippetContext = struct {
    file_path: ?[]const u8 = null,
    author: ?[]const u8 = null,
    clipboard: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SnippetContext {
        return .{
            .allocator = allocator,
        };
    }

    /// Get the value for a variable name
    pub fn getVariable(self: *const SnippetContext, name: []const u8) !?[]const u8 {
        if (std.mem.eql(u8, name, "DATE")) {
            const timestamp = std.time.timestamp();
            const epoch_day = @divTrunc(timestamp, 86400) + 719468;
            const year = @divTrunc(epoch_day * 400, 146097);
            const day_of_year = epoch_day - @divTrunc(year * 146097, 400);
            const month = @divTrunc((day_of_year * 5 + 2), 153);
            const day = day_of_year - @divTrunc((month * 153 + 2), 5) + 1;
            const actual_month = if (month < 10) month + 3 else month - 9;
            const actual_year = if (month < 10) year else year + 1;

            return try std.fmt.allocPrint(self.allocator, "{d}-{d:0>2}-{d:0>2}", .{ actual_year, actual_month, day });
        } else if (std.mem.eql(u8, name, "TIME")) {
            const timestamp = std.time.timestamp();
            const seconds_today = @mod(timestamp, 86400);
            const hours = @divTrunc(seconds_today, 3600);
            const minutes = @divTrunc(@mod(seconds_today, 3600), 60);
            const seconds = @mod(seconds_today, 60);

            return try std.fmt.allocPrint(self.allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds });
        } else if (std.mem.eql(u8, name, "DATETIME")) {
            const date = try self.getVariable("DATE");
            defer if (date) |d| self.allocator.free(d);
            const time = try self.getVariable("TIME");
            defer if (time) |t| self.allocator.free(t);

            if (date != null and time != null) {
                return try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ date.?, time.? });
            }
            return null;
        } else if (std.mem.eql(u8, name, "AUTHOR")) {
            if (self.author) |author| {
                return try self.allocator.dupe(u8, author);
            }
            // Try to get from git config
            if (std.process.getEnvVarOwned(self.allocator, "USER")) |user| {
                return user;
            } else |_| {
                return null;
            }
        } else if (std.mem.eql(u8, name, "FILE")) {
            if (self.file_path) |path| {
                if (std.fs.path.basename(path).len > 0) {
                    return try self.allocator.dupe(u8, std.fs.path.basename(path));
                }
            }
            return try self.allocator.dupe(u8, "untitled");
        } else if (std.mem.eql(u8, name, "DIR")) {
            if (self.file_path) |path| {
                if (std.fs.path.dirname(path)) |dirname| {
                    return try self.allocator.dupe(u8, dirname);
                }
            }
            return try self.allocator.dupe(u8, ".");
        } else if (std.mem.eql(u8, name, "CLIPBOARD")) {
            if (self.clipboard) |clip| {
                return try self.allocator.dupe(u8, clip);
            }
            return null;
        } else if (std.mem.eql(u8, name, "YEAR")) {
            const timestamp = std.time.timestamp();
            const epoch_day = @divTrunc(timestamp, 86400) + 719468;
            const year = @divTrunc(epoch_day * 400, 146097);
            return try std.fmt.allocPrint(self.allocator, "{d}", .{year});
        }

        return null;
    }
};

/// Expand a snippet, extracting tab stops and expanding variables
pub fn expandSnippet(
    allocator: std.mem.Allocator,
    snippet: Snippet,
    tab_stops: *std.ArrayList(TabStop),
    context: ?*const SnippetContext,
) ![]u8 {
    // Join lines with newlines
    var expanded = std.ArrayList(u8){};
    defer expanded.deinit(allocator);

    for (snippet.body, 0..) |line, i| {
        if (i > 0) {
            try expanded.append(allocator, '\n');
        }
        try expanded.appendSlice(allocator, line);
    }

    // Parse tab stops and replace them
    const text = try expanded.toOwnedSlice(allocator);
    defer allocator.free(text);

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '$' and i + 1 < text.len) {
            if (text[i + 1] == '{') {
                // Parse ${N:placeholder} or ${N}
                const close_brace = std.mem.indexOfScalarPos(u8, text, i + 2, '}') orelse {
                    try result.append(allocator, text[i]);
                    i += 1;
                    continue;
                };

                const content = text[i + 2 .. close_brace];
                const colon_pos = std.mem.indexOfScalar(u8, content, ':');

                const index_str = if (colon_pos) |pos| content[0..pos] else content;
                const placeholder = if (colon_pos) |pos| content[pos + 1 ..] else null;

                // Try to parse as number (tab stop)
                if (std.fmt.parseInt(u8, index_str, 10)) |index| {
                    const tab_stop_start = result.items.len;

                    if (placeholder) |ph| {
                        try result.appendSlice(allocator, ph);
                    }

                    const tab_stop = TabStop{
                        .index = index,
                        .start = tab_stop_start,
                        .end = result.items.len,
                        .placeholder = if (placeholder) |ph| try allocator.dupe(u8, ph) else null,
                    };
                    try tab_stops.append(allocator, tab_stop);

                    i = close_brace + 1;
                    continue;
                } else |_| {
                    // Not a number - try as variable
                    if (context) |ctx| {
                        if (try ctx.getVariable(index_str)) |value| {
                            defer allocator.free(value);
                            try result.appendSlice(allocator, value);
                            i = close_brace + 1;
                            continue;
                        }
                    }

                    // Variable not found - keep original text
                    try result.append(allocator, text[i]);
                    i += 1;
                    continue;
                }
            } else if (std.ascii.isDigit(text[i + 1])) {
                // Simple $N format
                const index = text[i + 1] - '0';
                const tab_stop = TabStop{
                    .index = index,
                    .start = result.items.len,
                    .end = result.items.len,
                    .placeholder = null,
                };
                try tab_stops.append(allocator, tab_stop);
                i += 2;
                continue;
            }
        }

        try result.append(allocator, text[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

test "snippet expansion" {
    const allocator = std.testing.allocator;

    const snippet = Snippet{
        .prefix = "fn",
        .body = &.{ "fn ${1:name}() {", "  ${2:body}", "}" },
        .description = "Function",
    };

    var tab_stops = std.ArrayList(TabStop){};
    defer tab_stops.deinit(allocator);

    const expanded = try expandSnippet(allocator, snippet, &tab_stops, null);
    defer allocator.free(expanded);

    std.debug.print("Expanded: {s}\n", .{expanded});
    std.debug.print("Tab stops: {d}\n", .{tab_stops.items.len});

    try std.testing.expect(tab_stops.items.len == 2);
    try std.testing.expectEqual(@as(u8, 1), tab_stops.items[0].index);
    try std.testing.expectEqual(@as(u8, 2), tab_stops.items[1].index);
}

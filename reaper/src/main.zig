const std = @import("std");
const config = @import("core/config_manager.zig");
const ConfigManager = config.ConfigManager;
const SyntaxHighlighter = @import("core/syntax_highlighter.zig").SyntaxHighlighter;
const zlog = @import("zlog");

const ColorCache = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(u8),
    colors: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) ColorCache {
        return ColorCache{
            .allocator = allocator,
            .map = std.StringHashMap(u8).init(allocator),
            .colors = std.ArrayList([]const u8).empty,
        };
    }

    fn deinit(self: *ColorCache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.map.deinit();
        for (self.colors.items) |escape_seq| {
            self.allocator.free(escape_seq);
        }
        self.colors.deinit(self.allocator);
    }

    fn ensureReset(self: *ColorCache) !void {
        if (self.colors.items.len == 0) {
            const reset = try self.allocator.dupe(u8, "\x1b[0m");
            try self.colors.append(self.allocator, reset);
        }
    }

    fn buildEscape(self: *ColorCache, hex: []const u8) ![]u8 {
        if (hex.len != 7 or hex[0] != '#') {
            return try self.allocator.dupe(u8, "\x1b[0m");
        }

        const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return try self.allocator.dupe(u8, "\x1b[0m");
        const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return try self.allocator.dupe(u8, "\x1b[0m");
        const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return try self.allocator.dupe(u8, "\x1b[0m");
        return std.fmt.allocPrint(self.allocator, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
    }

    fn getIndex(self: *ColorCache, hex: []const u8) !u8 {
        try self.ensureReset();
        if (self.map.get(hex)) |existing| {
            return existing;
        }

        const max_entries = @as(usize, std.math.maxInt(u8)) + 1;
        if (self.colors.items.len >= max_entries) {
            return 0;
        }

        const escape_seq = try self.buildEscape(hex);
        const key_copy = try self.allocator.dupe(u8, hex);
        errdefer self.allocator.free(key_copy);

        const idx = @as(u8, @intCast(self.colors.items.len));
        try self.map.put(key_copy, idx);
        try self.colors.append(self.allocator, escape_seq);
        return idx;
    }

    fn escape(self: *ColorCache, index: u8) []const u8 {
        if (index >= self.colors.items.len) {
            return "\x1b[0m";
        }
        return self.colors.items[index];
    }
};

pub fn main() !void {
    // Initialize logging
    zlog.info("Starting phantom.grim", .{});

    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get config directory (default to current directory for now)
    const config_dir = ".";

    // Initialize configuration manager
    var config_manager = try ConfigManager.init(allocator, config_dir);
    defer config_manager.deinit();
    config.setGlobalManager(&config_manager);

    const syntax_highlighter = config_manager.syntaxHighlighter();

    // Load all configurations
    try config_manager.loadConfiguration();

    zlog.info("phantom.grim initialized successfully", .{});

    if (try config_manager.fileTreeListing()) |tree| {
        defer allocator.free(tree);
        std.debug.print("\n[files]\n{s}\n", .{tree});
    } else {
        std.debug.print("\n[files]\n<no entries>\n", .{});
    }

    if (try config_manager.fuzzyFinderListing("")) |fuzzy| {
        defer allocator.free(fuzzy);
        std.debug.print("\n[fuzzy]\n{s}\n", .{fuzzy});
    } else {
        std.debug.print("\n[fuzzy]\n<no results>\n", .{});
    }

    try demoFuzzyQueries(allocator, &config_manager);

    const sample_code =
        "fn main() {\n" ++
        "    const message = \"hello world\";\n" ++
        "    return message;\n" ++
        "}\n";

    const highlight_request = SyntaxHighlighter.Request{
        .buffer_id = 1,
        .language = "zig",
        .path = "sample.zig",
        .content = sample_code,
    };

    const highlight_result = try syntax_highlighter.getHighlights(highlight_request);
    const highlights = highlight_result.highlights;

    std.debug.print("\n[grim highlights] cache={s}\n", .{if (highlight_result.cache_hit) "hit" else "miss"});
    for (highlights.highlights) |hl| {
        std.debug.print("  {d}-{d}: {s}\n", .{ hl.start, hl.stop, hl.token_type });
    }

    try printHighlightedSample(allocator, sample_code, highlights.highlights, config_manager.themeRef());

    if (try config_manager.statuslineCurrent()) |line| {
        defer allocator.free(line);
        std.debug.print("\n{s}\n", .{line});
    } else {
        std.debug.print("\n[phantom.grim] statusline unavailable\n", .{});
    }

    // Keep running (in a real implementation, this would integrate with Grim)
    // For now, just demonstrate config loading
    if (config_manager.getString("editor.theme")) |theme| {
        std.debug.print("Loaded theme: {s}\n", .{theme});
    }
}

fn printColoredLine(allocator: std.mem.Allocator, text: []const u8, highlights: []const config.Highlight, theme: *const config.Theme) !void {
    if (text.len == 0) {
        std.debug.print("\n", .{});
        return;
    }

    var cache = ColorCache.init(allocator);
    defer cache.deinit();

    var color_ids = try allocator.alloc(u8, text.len);
    defer allocator.free(color_ids);
    @memset(color_ids, 0);

    for (highlights) |hl| {
        if (hl.stop <= hl.start or hl.start >= text.len) continue;
        const end_idx = @min(hl.stop, text.len);
        const color_hex = theme.colorFor(hl.token_type);
        const id = cache.getIndex(color_hex) catch 0;
        var idx = hl.start;
        while (idx < end_idx) : (idx += 1) {
            color_ids[idx] = id;
        }
    }

    try cache.ensureReset();
    const reset = cache.escape(0);
    var current: u8 = 0;
    for (text, 0..) |byte, idx| {
        const id = color_ids[idx];
        if (id != current) {
            current = id;
            std.debug.print("{s}", .{cache.escape(id)});
        }
        std.debug.print("{c}", .{byte});
    }
    if (current != 0) {
        std.debug.print("{s}", .{reset});
    }
    std.debug.print("\n", .{});
}

fn printHighlightedSample(allocator: std.mem.Allocator, code: []const u8, highlights: []const config.Highlight, theme: *const config.Theme) !void {
    if (code.len == 0) {
        std.debug.print("\n", .{});
        return;
    }

    std.debug.print("\n[highlighted sample]\n", .{});
    try printColoredLine(allocator, code, highlights, theme);
}

fn printFuzzyResults(allocator: std.mem.Allocator, results: config.FuzzyResults, theme: *const config.Theme) !void {
    if (results.entries.len == 0) {
        std.debug.print("<no results>\n", .{});
        return;
    }

    for (results.entries) |entry| {
        try printColoredLine(allocator, entry.path, entry.highlights, theme);
    }
}

fn demoFuzzyQueries(allocator: std.mem.Allocator, manager: *ConfigManager) !void {
    const theme = manager.themeRef();
    const queries = [_][]const u8{ "", "src", "config" };

    for (queries) |query| {
        var results = try manager.getFuzzyResults(query);
        defer results.deinit(allocator);

        const display_label = if (query.len == 0) "<empty>" else query;
        std.debug.print("\n[fuzzy finder decorated query={s}]\n", .{display_label});
        try printFuzzyResults(allocator, results, theme);
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");
const runtime = @import("runtime");
const syntax = @import("syntax");
const core = @import("core");

/// Tree-sitter/Grove → HighlightThemeAPI Integration
/// Bridges syntax highlighting with grim's theme system
pub const SyntaxHighlights = struct {
    allocator: std.mem.Allocator,
    highlight_api: runtime.HighlightThemeAPI,
    highlighter: syntax.SyntaxHighlighter,
    namespace_id: u32,

    const NAMESPACE_NAME = "syntax";

    pub fn init(allocator: std.mem.Allocator) !SyntaxHighlights {
        var highlight_api = runtime.HighlightThemeAPI.init(allocator);

        // Define syntax highlight groups
        try setupSyntaxHighlights(&highlight_api);

        // Create namespace for syntax highlighting
        const ns_id = try highlight_api.createNamespace(NAMESPACE_NAME);

        return SyntaxHighlights{
            .allocator = allocator,
            .highlight_api = highlight_api,
            .highlighter = syntax.SyntaxHighlighter.init(allocator),
            .namespace_id = ns_id,
        };
    }

    pub fn deinit(self: *SyntaxHighlights) void {
        self.highlighter.deinit();
        self.highlight_api.deinit();
    }

    /// Set language for syntax highlighting
    pub fn setLanguage(self: *SyntaxHighlights, filename: []const u8) !void {
        try self.highlighter.setLanguage(filename);
    }

    /// Apply syntax highlighting to a buffer
    pub fn applyHighlights(
        self: *SyntaxHighlights,
        buffer_id: u32,
        rope: *core.Rope,
    ) !void {
        // Clear previous syntax highlights
        try self.highlight_api.clearNamespace(NAMESPACE_NAME, buffer_id);

        // Get Grove highlights (byte offsets)
        const highlights = try self.highlighter.highlight(rope);
        defer self.allocator.free(highlights);

        // Convert to line/col ranges
        const ranges = try syntax.convertHighlightsToRanges(self.allocator, highlights, rope);
        defer self.allocator.free(ranges);

        // Apply each highlight to namespace
        for (ranges) |range| {
            const group_name = self.getHighlightGroupForType(range.highlight_type);

            // For single-line highlights
            if (range.start_line == range.end_line) {
                try self.highlight_api.addNamespaceHighlight(
                    NAMESPACE_NAME,
                    buffer_id,
                    group_name,
                    @intCast(range.start_line),
                    @intCast(range.start_col),
                    @intCast(range.end_col),
                );
            } else {
                // Multi-line highlights: apply to each line
                var line = range.start_line;
                while (line <= range.end_line) : (line += 1) {
                    const start_col: u32 = if (line == range.start_line) @intCast(range.start_col) else 0;
                    const end_col: u32 = if (line == range.end_line) @intCast(range.end_col) else std.math.maxInt(u32);

                    try self.highlight_api.addNamespaceHighlight(
                        NAMESPACE_NAME,
                        buffer_id,
                        group_name,
                        @intCast(line),
                        start_col,
                        end_col,
                    );
                }
            }
        }
    }

    /// Incremental update for changed lines (performance optimization)
    pub fn updateLines(
        self: *SyntaxHighlights,
        buffer_id: u32,
        rope: *core.Rope,
        start_line: u32,
        end_line: u32,
    ) !void {
        // For now, re-highlight entire buffer
        // TODO: Implement incremental parsing with Grove
        try self.applyHighlights(buffer_id, rope);
    }

    /// Get current language name
    pub fn getLanguageName(self: *const SyntaxHighlights) []const u8 {
        return self.highlighter.getLanguageName();
    }

    /// Check if language is supported
    pub fn supportsLanguage(language: syntax.grove.GroveParser.Language) bool {
        return syntax.SyntaxHighlighter.supportsLanguage(language);
    }

    // Private helpers

    fn getHighlightGroupForType(self: *SyntaxHighlights, highlight_type: syntax.grove.GroveParser.HighlightType) []const u8 {
        _ = self;
        return switch (highlight_type) {
            .keyword => "Keyword",
            .string_literal => "String",
            .number_literal => "Number",
            .comment => "Comment",
            .function_name => "Function",
            .type_name => "Type",
            .variable => "Identifier",
            .operator => "Operator",
            .punctuation => "Delimiter",
            .@"error" => "Error",
            .none => "Normal",
        };
    }

    fn setupSyntaxHighlights(api: *runtime.HighlightThemeAPI) !void {
        // Gruvbox-inspired syntax colors

        // Keywords - bold purple
        const purple = try runtime.HighlightThemeAPI.Color.fromHex("#d3869b");
        _ = try api.defineHighlight("Keyword", purple, null, null, .{ .bold = true });

        // Strings - green
        const green = try runtime.HighlightThemeAPI.Color.fromHex("#b8bb26");
        _ = try api.defineHighlight("String", green, null, null, .{});

        // Numbers - purple
        const number_purple = try runtime.HighlightThemeAPI.Color.fromHex("#d3869b");
        _ = try api.defineHighlight("Number", number_purple, null, null, .{});

        // Comments - gray italic
        const gray = try runtime.HighlightThemeAPI.Color.fromHex("#928374");
        _ = try api.defineHighlight("Comment", gray, null, null, .{ .italic = true });

        // Functions - bold green/aqua
        const aqua = try runtime.HighlightThemeAPI.Color.fromHex("#8ec07c");
        _ = try api.defineHighlight("Function", aqua, null, null, .{ .bold = true });

        // Types - yellow
        const yellow = try runtime.HighlightThemeAPI.Color.fromHex("#fabd2f");
        _ = try api.defineHighlight("Type", yellow, null, null, .{});

        // Identifiers - light gray
        const fg = try runtime.HighlightThemeAPI.Color.fromHex("#ebdbb2");
        _ = try api.defineHighlight("Identifier", fg, null, null, .{});

        // Operators - orange
        const orange = try runtime.HighlightThemeAPI.Color.fromHex("#fe8019");
        _ = try api.defineHighlight("Operator", orange, null, null, .{});

        // Delimiters - light gray
        _ = try api.defineHighlight("Delimiter", fg, null, null, .{});

        // Errors - bold red
        const red = try runtime.HighlightThemeAPI.Color.fromHex("#fb4934");
        _ = try api.defineHighlight("Error", red, null, null, .{ .bold = true });

        // Normal text - default foreground
        _ = try api.defineHighlight("Normal", fg, null, null, .{});
    }
};

test "SyntaxHighlights init" {
    const allocator = std.testing.allocator;

    var syntax_hl = try SyntaxHighlights.init(allocator);
    defer syntax_hl.deinit();

    // Verify namespace was created
    try std.testing.expectEqual(@as(u32, 0), syntax_hl.namespace_id);
}

test "SyntaxHighlights apply to buffer" {
    const allocator = std.testing.allocator;

    var syntax_hl = try SyntaxHighlights.init(allocator);
    defer syntax_hl.deinit();

    // Set language
    try syntax_hl.setLanguage("test.zig");

    // Create test rope with some Zig code
    var rope = try core.Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "const x = 42;");

    // Apply highlights
    try syntax_hl.applyHighlights(1, &rope);

    // Verify highlights were added to namespace
    const ns = syntax_hl.highlight_api.namespaces.get(NAMESPACE_NAME).?;
    try std.testing.expect(ns.highlights.items.len > 0);
}

test "SyntaxHighlights language detection" {
    const allocator = std.testing.allocator;

    var syntax_hl = try SyntaxHighlights.init(allocator);
    defer syntax_hl.deinit();

    try syntax_hl.setLanguage("example.rs");
    try std.testing.expectEqualStrings("rust", syntax_hl.getLanguageName());

    try syntax_hl.setLanguage("script.py");
    try std.testing.expectEqualStrings("python", syntax_hl.getLanguageName());

    try syntax_hl.setLanguage("plugin.gza");
    try std.testing.expectEqualStrings("ghostlang", syntax_hl.getLanguageName());
}

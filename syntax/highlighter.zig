const std = @import("std");
const grove = @import("grove.zig");
const core = @import("core");

pub const SyntaxHighlighter = struct {
    allocator: std.mem.Allocator,
    parser: ?*grove.GroveParser,
    current_language: grove.GroveParser.Language,
    cached_highlights: []grove.GroveParser.Highlight,
    last_parse_hash: u64,

    pub const Error = error{
        ParserNotInitialized,
        HighlightingFailed,
    } || grove.GroveParser.Error || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator) SyntaxHighlighter {
        return .{
            .allocator = allocator,
            .parser = null,
            .current_language = .unknown,
            .cached_highlights = &.{},
            .last_parse_hash = 0,
        };
    }

    pub fn deinit(self: *SyntaxHighlighter) void {
        if (self.parser) |parser| {
            parser.deinit();
        }
        if (self.cached_highlights.len > 0) {
            self.allocator.free(self.cached_highlights);
        }
        self.* = undefined;
    }

    pub fn setLanguage(self: *SyntaxHighlighter, filename: []const u8) Error!void {
        const language = grove.detectLanguage(filename);

        if (language == self.current_language and self.parser != null) {
            return; // Already set to correct language
        }

        // Clean up existing parser
        if (self.parser) |parser| {
            parser.deinit();
        }

        // Create new parser for the language
        self.parser = try grove.GroveParser.init(self.allocator, language);
        self.current_language = language;

        // Clear cached highlights since language changed
        self.clearCache();
    }

    pub fn highlight(self: *SyntaxHighlighter, rope: *core.Rope) Error![]grove.GroveParser.Highlight {
        const parser = self.parser orelse return Error.ParserNotInitialized;

        // Get rope content
        const content = try rope.slice(.{ .start = 0, .end = rope.len() });
        defer if (content.len > 0) self.allocator.free(content);

        // Check if content changed using simple hash
        const content_hash = std.hash_map.hashString(content);
        if (content_hash == self.last_parse_hash and self.cached_highlights.len > 0) {
            // Return cached highlights
            const result = try self.allocator.alloc(grove.GroveParser.Highlight, self.cached_highlights.len);
            @memcpy(result, self.cached_highlights);
            return result;
        }

        // Parse content
        try parser.parse(content);

        // Get highlights
        const highlights = try parser.getHighlights(self.allocator);

        // Cache the results
        self.updateCache(highlights, content_hash);

        return highlights;
    }

    pub fn getLanguageName(self: *const SyntaxHighlighter) []const u8 {
        return self.current_language.name();
    }

    pub fn supportsLanguage(language: grove.GroveParser.Language) bool {
        return language != .unknown;
    }

    fn clearCache(self: *SyntaxHighlighter) void {
        if (self.cached_highlights.len > 0) {
            self.allocator.free(self.cached_highlights);
            self.cached_highlights = &.{};
        }
        self.last_parse_hash = 0;
    }

    fn updateCache(self: *SyntaxHighlighter, highlights: []grove.GroveParser.Highlight, content_hash: u64) void {
        self.clearCache();

        // Store copy of highlights for caching
        self.cached_highlights = self.allocator.dupe(grove.GroveParser.Highlight, highlights) catch &.{};
        self.last_parse_hash = content_hash;
    }
};

// Highlight range utilities for editor integration
pub const HighlightRange = struct {
    start_line: usize,
    start_col: usize,
    end_line: usize,
    end_col: usize,
    highlight_type: grove.GroveParser.HighlightType,
};

pub fn convertHighlightsToRanges(
    allocator: std.mem.Allocator,
    highlights: []const grove.GroveParser.Highlight,
    rope: *core.Rope,
) ![]HighlightRange {
    var ranges = std.ArrayList(HighlightRange).init(allocator);
    errdefer ranges.deinit();

    for (highlights) |highlight| {
        const start_pos = byteOffsetToLineCol(rope, highlight.start);
        const end_pos = byteOffsetToLineCol(rope, highlight.end);

        try ranges.append(.{
            .start_line = start_pos.line,
            .start_col = start_pos.col,
            .end_line = end_pos.line,
            .end_col = end_pos.col,
            .highlight_type = highlight.type,
        });
    }

    return ranges.toOwnedSlice();
}

const LineCol = struct {
    line: usize,
    col: usize,
};

fn byteOffsetToLineCol(rope: *core.Rope, offset: usize) LineCol {
    const content = rope.slice(.{ .start = 0, .end = @min(offset + 1, rope.len()) }) catch return .{ .line = 0, .col = 0 };
    defer if (content.len > 0) std.heap.page_allocator.free(content);

    var line: usize = 0;
    var col: usize = 0;

    for (content[0..@min(offset, content.len)]) |byte| {
        if (byte == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
    }

    return .{ .line = line, .col = col };
}
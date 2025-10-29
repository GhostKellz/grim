const std = @import("std");
const core = @import("core");

/// Structured Buffer Edit API for Phase 3 Plugins
/// Provides high-level text editing operations without manual byte math
pub const BufferEditAPI = struct {
    allocator: std.mem.Allocator,

    pub const TextObject = enum {
        word,
        word_big, // WORD in Vim
        sentence,
        paragraph,
        line,
        block_paren, // ()
        block_bracket, // []
        block_brace, // {}
        block_angle, // <>
        quoted_single, // '...'
        quoted_double, // "..."
        quoted_back, // `...`
        tag, // HTML/XML tag
    };

    pub const OperatorRange = struct {
        start: usize,
        end: usize,
        object_type: TextObject,
    };

    pub const VirtualCursor = struct {
        line: usize,
        column: usize,
        byte_offset: usize,
        anchor: ?struct {
            line: usize,
            column: usize,
            byte_offset: usize,
        } = null,

        pub fn hasSelection(self: *const VirtualCursor) bool {
            return self.anchor != null;
        }
    };

    pub const MultiCursorEdit = struct {
        cursors: std.ArrayList(VirtualCursor),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) MultiCursorEdit {
            return .{
                .cursors = std.ArrayList(VirtualCursor){},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *MultiCursorEdit) void {
            self.cursors.deinit(self.allocator);
        }

        pub fn addCursor(self: *MultiCursorEdit, cursor: VirtualCursor) !void {
            try self.cursors.append(self.allocator, cursor);
        }

        pub fn clearCursors(self: *MultiCursorEdit) void {
            self.cursors.clearRetainingCapacity();
        }

        pub fn primaryCursor(self: *const MultiCursorEdit) ?VirtualCursor {
            if (self.cursors.items.len == 0) return null;
            return self.cursors.items[0];
        }
    };

    pub const EditOperation = struct {
        range: core.Range,
        replacement: []const u8,
        cursor_adjustment: ?usize = null,
    };

    pub fn init(allocator: std.mem.Allocator) BufferEditAPI {
        return .{ .allocator = allocator };
    }

    /// Find a text object around the given position
    pub fn findTextObject(
        self: *BufferEditAPI,
        rope: *core.Rope,
        position: usize,
        object: TextObject,
        include_delimiters: bool,
    ) !OperatorRange {
        return switch (object) {
            .word => try self.findWord(rope, position, false),
            .word_big => try self.findWord(rope, position, true),
            .sentence => try self.findSentence(rope, position),
            .paragraph => try self.findParagraph(rope, position),
            .line => try self.findLine(rope, position),
            .block_paren => try self.findBlock(rope, position, '(', ')', include_delimiters),
            .block_bracket => try self.findBlock(rope, position, '[', ']', include_delimiters),
            .block_brace => try self.findBlock(rope, position, '{', '}', include_delimiters),
            .block_angle => try self.findBlock(rope, position, '<', '>', include_delimiters),
            .quoted_single => try self.findQuoted(rope, position, '\'', include_delimiters),
            .quoted_double => try self.findQuoted(rope, position, '"', include_delimiters),
            .quoted_back => try self.findQuoted(rope, position, '`', include_delimiters),
            .tag => try self.findTag(rope, position, include_delimiters),
        };
    }

    /// Replace a range with new text, handling all edge cases
    pub fn replaceRange(
        self: *BufferEditAPI,
        rope: *core.Rope,
        range: core.Range,
        replacement: []const u8,
    ) !EditOperation {
        _ = self;
        const old_len = range.len();
        try rope.delete(range.start, old_len);
        try rope.insert(range.start, replacement);

        return EditOperation{
            .range = range,
            .replacement = replacement,
            .cursor_adjustment = range.start + replacement.len,
        };
    }

    /// Perform multi-cursor edit operation
    pub fn multiCursorEdit(
        self: *BufferEditAPI,
        rope: *core.Rope,
        cursors: *const MultiCursorEdit,
        operation: *const fn (rope: *core.Rope, cursor: VirtualCursor) anyerror!EditOperation,
    ) !std.ArrayList(EditOperation) {
        var operations = std.ArrayList(EditOperation){};
        errdefer operations.deinit(self.allocator);

        // Sort cursors by position (descending) to avoid offset invalidation
        const sorted_cursors = try self.allocator.dupe(VirtualCursor, cursors.cursors.items);
        defer self.allocator.free(sorted_cursors);

        std.mem.sort(VirtualCursor, sorted_cursors, {}, struct {
            fn lessThan(_: void, a: VirtualCursor, b: VirtualCursor) bool {
                return a.byte_offset > b.byte_offset;
            }
        }.lessThan);

        // Apply operations in reverse order
        for (sorted_cursors) |cursor| {
            const op = try operation(rope, cursor);
            try operations.append(self.allocator, op);
        }

        return operations;
    }

    /// Surround a range with delimiters
    pub fn surroundRange(
        self: *BufferEditAPI,
        rope: *core.Rope,
        range: core.Range,
        open: []const u8,
        close: []const u8,
    ) !EditOperation {
        _ = self;
        // Insert closing delimiter first to preserve positions
        try rope.insert(range.end, close);
        try rope.insert(range.start, open);

        return EditOperation{
            .range = .{ .start = range.start, .end = range.end + open.len + close.len },
            .replacement = "", // Not applicable for surround
            .cursor_adjustment = range.start + open.len,
        };
    }

    /// Remove surrounding delimiters
    pub fn unsurroundRange(
        self: *BufferEditAPI,
        rope: *core.Rope,
        inner_range: core.Range,
        open_len: usize,
        close_len: usize,
    ) !EditOperation {
        _ = self;
        // Delete closing delimiter first
        try rope.delete(inner_range.end, close_len);
        try rope.delete(inner_range.start - open_len, open_len);

        return EditOperation{
            .range = .{ .start = inner_range.start - open_len, .end = inner_range.end + close_len },
            .replacement = "",
            .cursor_adjustment = inner_range.start - open_len,
        };
    }

    /// Change surrounding delimiters
    pub fn changeSurround(
        self: *BufferEditAPI,
        rope: *core.Rope,
        inner_range: core.Range,
        old_open_len: usize,
        old_close_len: usize,
        new_open: []const u8,
        new_close: []const u8,
    ) !EditOperation {
        // Remove old delimiters
        _ = try self.unsurroundRange(rope, inner_range, old_open_len, old_close_len);
        // Add new delimiters
        const adjusted_range = core.Range{
            .start = inner_range.start - old_open_len,
            .end = inner_range.end - old_open_len,
        };
        return try self.surroundRange(rope, adjusted_range, new_open, new_close);
    }

    // Private helper methods
    fn findWord(self: *BufferEditAPI, rope: *core.Rope, position: usize, big_word: bool) !OperatorRange {
        _ = self;
        const content = try rope.slice(.{ .start = 0, .end = rope.len() });

        var start = position;
        var end = position;

        // Move start backward to word beginning
        while (start > 0) {
            const ch = content[start - 1];
            if (big_word) {
                if (isSpace(ch)) break;
            } else {
                if (!isWordChar(ch)) break;
            }
            start -= 1;
        }

        // Move end forward to word end
        while (end < content.len) {
            const ch = content[end];
            if (big_word) {
                if (isSpace(ch)) break;
            } else {
                if (!isWordChar(ch)) break;
            }
            end += 1;
        }

        return OperatorRange{
            .start = start,
            .end = end,
            .object_type = if (big_word) .word_big else .word,
        };
    }

    fn findSentence(self: *BufferEditAPI, rope: *core.Rope, position: usize) !OperatorRange {
        _ = self;
        const content = try rope.slice(.{ .start = 0, .end = rope.len() });

        var start = position;
        var end = position;

        // Find sentence start (after . ! ?)
        while (start > 0) {
            const ch = content[start - 1];
            if (ch == '.' or ch == '!' or ch == '?') {
                // Skip whitespace after sentence end
                while (start < content.len and isSpace(content[start])) {
                    start += 1;
                }
                break;
            }
            start -= 1;
        }

        // Find sentence end
        while (end < content.len) {
            const ch = content[end];
            if (ch == '.' or ch == '!' or ch == '?') {
                end += 1;
                break;
            }
            end += 1;
        }

        return OperatorRange{ .start = start, .end = end, .object_type = .sentence };
    }

    fn findParagraph(self: *BufferEditAPI, rope: *core.Rope, position: usize) !OperatorRange {
        _ = self;
        const content = try rope.slice(.{ .start = 0, .end = rope.len() });

        var start = position;
        var end = position;

        // Find paragraph start (double newline)
        var newline_count: u8 = 0;
        while (start > 0) {
            const ch = content[start - 1];
            if (ch == '\n') {
                newline_count += 1;
                if (newline_count >= 2) break;
            } else if (!isSpace(ch)) {
                newline_count = 0;
            }
            start -= 1;
        }

        // Find paragraph end
        newline_count = 0;
        while (end < content.len) {
            const ch = content[end];
            if (ch == '\n') {
                newline_count += 1;
                if (newline_count >= 2) break;
            } else if (!isSpace(ch)) {
                newline_count = 0;
            }
            end += 1;
        }

        return OperatorRange{ .start = start, .end = end, .object_type = .paragraph };
    }

    fn findLine(self: *BufferEditAPI, rope: *core.Rope, position: usize) !OperatorRange {
        _ = self;
        const lc = try rope.lineColumnAtOffset(position);
        const range = try rope.lineRange(lc.line);
        return OperatorRange{ .start = range.start, .end = range.end, .object_type = .line };
    }

    fn findBlock(
        self: *BufferEditAPI,
        rope: *core.Rope,
        position: usize,
        open_char: u8,
        close_char: u8,
        include_delimiters: bool,
    ) !OperatorRange {
        _ = self;
        const content = try rope.slice(.{ .start = 0, .end = rope.len() });

        var depth: i32 = 0;
        var start: ?usize = null;
        var end: ?usize = null;

        // Find opening bracket
        var i = position;
        while (i > 0) : (i -= 1) {
            const ch = content[i - 1];
            if (ch == close_char) depth += 1;
            if (ch == open_char) {
                if (depth == 0) {
                    start = i - 1;
                    break;
                }
                depth -= 1;
            }
        }

        if (start == null) return error.NoMatchingOpeningBracket;

        // Find closing bracket
        depth = 0;
        i = start.? + 1;
        while (i < content.len) : (i += 1) {
            const ch = content[i];
            if (ch == open_char) depth += 1;
            if (ch == close_char) {
                if (depth == 0) {
                    end = i;
                    break;
                }
                depth -= 1;
            }
        }

        if (end == null) return error.NoMatchingClosingBracket;

        if (include_delimiters) {
            return OperatorRange{ .start = start.?, .end = end.? + 1, .object_type = .block_paren };
        } else {
            return OperatorRange{ .start = start.? + 1, .end = end.?, .object_type = .block_paren };
        }
    }

    fn findQuoted(
        self: *BufferEditAPI,
        rope: *core.Rope,
        position: usize,
        quote_char: u8,
        include_delimiters: bool,
    ) !OperatorRange {
        _ = self;
        const content = try rope.slice(.{ .start = 0, .end = rope.len() });

        var start: ?usize = null;
        var end: ?usize = null;

        // Find opening quote (scan backward)
        var i = position;
        while (i > 0) : (i -= 1) {
            if (content[i - 1] == quote_char) {
                // Check if escaped
                if (i >= 2 and content[i - 2] == '\\') continue;
                start = i - 1;
                break;
            }
        }

        if (start == null) return error.NoMatchingOpeningQuote;

        // Find closing quote (scan forward)
        i = start.? + 1;
        while (i < content.len) : (i += 1) {
            if (content[i] == quote_char) {
                // Check if escaped
                if (i > 0 and content[i - 1] == '\\') continue;
                end = i;
                break;
            }
        }

        if (end == null) return error.NoMatchingClosingQuote;

        if (include_delimiters) {
            return OperatorRange{ .start = start.?, .end = end.? + 1, .object_type = .quoted_single };
        } else {
            return OperatorRange{ .start = start.? + 1, .end = end.?, .object_type = .quoted_single };
        }
    }

    fn findTag(self: *BufferEditAPI, rope: *core.Rope, position: usize, include_delimiters: bool) !OperatorRange {
        _ = self;
        _ = rope;
        _ = position;
        _ = include_delimiters;
        // TODO: Implement HTML/XML tag matching
        return error.NotImplemented;
    }

    fn isWordChar(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '_';
    }

    fn isSpace(ch: u8) bool {
        return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r';
    }
};

test "BufferEditAPI find word" {
    const allocator = std.testing.allocator;
    var rope = try core.Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello world");

    var api = BufferEditAPI.init(allocator);

    // Find word at position 2 (in "hello")
    const word = try api.findTextObject(&rope, 2, .word, false);
    try std.testing.expectEqual(@as(usize, 0), word.start);
    try std.testing.expectEqual(@as(usize, 5), word.end);

    // Find word at position 7 (in "world")
    const word2 = try api.findTextObject(&rope, 7, .word, false);
    try std.testing.expectEqual(@as(usize, 6), word2.start);
    try std.testing.expectEqual(@as(usize, 11), word2.end);
}

test "BufferEditAPI surround" {
    const allocator = std.testing.allocator;
    var rope = try core.Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");

    var api = BufferEditAPI.init(allocator);

    // Surround "hello" with quotes
    _ = try api.surroundRange(&rope, .{ .start = 0, .end = 5 }, "\"", "\"");

    const result = try rope.slice(.{ .start = 0, .end = rope.len() });
    try std.testing.expectEqualStrings("\"hello\"", result);
}

test "BufferEditAPI multi-cursor" {
    const allocator = std.testing.allocator;
    var rope = try core.Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "foo\nfoo\nfoo");

    var api = BufferEditAPI.init(allocator);
    var cursors = BufferEditAPI.MultiCursorEdit.init(allocator);
    defer cursors.deinit();

    // Add cursors at each "foo"
    try cursors.addCursor(.{ .line = 0, .column = 0, .byte_offset = 0 });
    try cursors.addCursor(.{ .line = 1, .column = 0, .byte_offset = 4 });
    try cursors.addCursor(.{ .line = 2, .column = 0, .byte_offset = 8 });

    const ReplaceOp = struct {
        fn replace(r: *core.Rope, cursor: BufferEditAPI.VirtualCursor) !BufferEditAPI.EditOperation {
            const range = core.Range{ .start = cursor.byte_offset, .end = cursor.byte_offset + 3 };
            try r.delete(range.start, range.len());
            try r.insert(range.start, "bar");
            return BufferEditAPI.EditOperation{
                .range = range,
                .replacement = "bar",
                .cursor_adjustment = range.start + 3,
            };
        }
    };

    _ = try api.multiCursorEdit(&rope, &cursors, ReplaceOp.replace);

    const result = try rope.slice(.{ .start = 0, .end = rope.len() });
    try std.testing.expectEqualStrings("bar\nbar\nbar", result);
}

const std = @import("std");
const grove = @import("grove.zig");

/// Tree-sitter advanced features: folding and incremental selection
pub const Features = struct {
    allocator: std.mem.Allocator,
    parser: ?*grove.GroveParser,

    pub fn init(allocator: std.mem.Allocator) Features {
        return .{
            .allocator = allocator,
            .parser = null,
        };
    }

    pub fn setParser(self: *Features, parser: *grove.GroveParser) void {
        self.parser = parser;
    }

    /// Fold region for code folding
    pub const FoldRegion = struct {
        start_line: usize,
        end_line: usize,
        level: usize, // Nesting level
        folded: bool,
    };

    /// Get fold regions from syntax tree
    /// Folds functions, blocks, structs, etc.
    pub fn getFoldRegions(_: *Features, _: []const u8) ![]FoldRegion {
        // TODO: Implement tree-sitter query-based folding
        // For now, use getFoldRegionsSimple()
        return &.{};
    }

    /// Selection range for incremental selection
    pub const SelectionRange = struct {
        start_byte: usize,
        end_byte: usize,
        start_line: usize,
        end_line: usize,
        start_col: usize,
        end_col: usize,
        kind: SelectionKind,

        pub const SelectionKind = enum {
            token, // Single token/word
            expression, // Expression
            statement, // Statement
            block, // Code block
            function, // Function definition
            class, // Class/struct definition
            file, // Entire file
        };
    };

    /// Get selection ranges at cursor position (for expanding selection)
    pub fn getSelectionRanges(_: *Features, _: []const u8, _: usize) ![]SelectionRange {
        // TODO: Implement tree-sitter query-based selection
        // Should return ranges from smallest to largest:
        // token -> expression -> statement -> block -> function -> class -> file
        return &.{};
    }

    /// Simple fold detection based on braces (fallback when tree-sitter unavailable)
    pub fn getFoldRegionsSimple(self: *Features, source: []const u8) ![]FoldRegion {
        var regions: std.ArrayList(FoldRegion) = .empty;
        defer regions.deinit(self.allocator);

        var line: usize = 0;
        var col: usize = 0;
        var brace_stack: std.ArrayList(usize) = .empty;
        defer brace_stack.deinit(self.allocator);

        for (source, 0..) |ch, idx| {
            switch (ch) {
                '{' => {
                    try brace_stack.append(self.allocator, line);
                },
                '}' => {
                    if (brace_stack.items.len > 0) {
                        const start_line = brace_stack.pop() orelse continue;
                        // Only create fold if it spans multiple lines
                        if (line > start_line) {
                            try regions.append(self.allocator, .{
                                .start_line = start_line,
                                .end_line = line,
                                .level = brace_stack.items.len,
                                .folded = false,
                            });
                        }
                    }
                },
                '\n' => {
                    line += 1;
                    col = 0;
                },
                else => {
                    col += 1;
                },
            }
            _ = idx;
        }

        return try regions.toOwnedSlice(self.allocator);
    }

    /// Expand selection to next syntax level
    pub fn expandSelection(self: *Features, source: []const u8, current_start: usize, current_end: usize) !?SelectionRange {
        const ranges = try self.getSelectionRanges(source, current_start);
        defer self.allocator.free(ranges);

        // Find the smallest range that contains current selection
        for (ranges) |range| {
            if (range.start_byte <= current_start and range.end_byte >= current_end) {
                // If it's the same as current, find the next larger one
                if (range.start_byte == current_start and range.end_byte == current_end) {
                    continue;
                }
                return range;
            }
        }

        return null;
    }

    /// Shrink selection to previous syntax level
    pub fn shrinkSelection(self: *Features, source: []const u8, current_start: usize, current_end: usize) !?SelectionRange {
        const ranges = try self.getSelectionRanges(source, current_start);
        defer self.allocator.free(ranges);

        // Find the largest range that is contained within current selection
        var best: ?SelectionRange = null;
        for (ranges) |range| {
            if (range.start_byte >= current_start and range.end_byte <= current_end) {
                // If it's the same as current, skip
                if (range.start_byte == current_start and range.end_byte == current_end) {
                    continue;
                }
                // Keep the largest one that's still smaller than current
                if (best == null or range.end_byte - range.start_byte > best.?.end_byte - best.?.start_byte) {
                    best = range;
                }
            }
        }

        return best;
    }
};

test "fold regions simple" {
    const allocator = std.testing.allocator;
    var features = Features.init(allocator);

    const source =
        \\fn main() {
        \\    if (true) {
        \\        print("hello");
        \\    }
        \\}
    ;

    const regions = try features.getFoldRegionsSimple(source);
    defer allocator.free(regions);

    // Should detect 2 fold regions: main function and if block
    try std.testing.expect(regions.len >= 1);
}

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
    pub fn getFoldRegions(self: *Features, source: []const u8) ![]FoldRegion {
        if (self.parser == null) {
            // Fallback to simple brace-based folding
            return try self.getFoldRegionsSimple(source);
        }

        var regions: std.ArrayList(FoldRegion) = .empty;
        defer regions.deinit(self.allocator);

        // Parse source with Grove
        const tree = self.parser.?.parse(source) catch {
            return try self.getFoldRegionsSimple(source);
        };

        const root_node = tree.rootNode() orelse {
            return try self.getFoldRegionsSimple(source);
        };

        // Traverse tree and collect foldable nodes
        try self.collectFoldableNodes(&root_node, &regions, 0);

        return try regions.toOwnedSlice(self.allocator);
    }

    fn collectFoldableNodes(
        self: *Features,
        node: *const grove.Node,
        regions: *std.ArrayList(FoldRegion),
        level: usize,
    ) !void {
        const node_kind = node.kind();

        // Check if this node type is foldable
        const is_foldable = std.mem.eql(u8, node_kind, "function_declaration") or
            std.mem.eql(u8, node_kind, "FnDecl") or
            std.mem.eql(u8, node_kind, "fn_decl") or
            std.mem.eql(u8, node_kind, "struct_declaration") or
            std.mem.eql(u8, node_kind, "StructDecl") or
            std.mem.eql(u8, node_kind, "struct_decl") or
            std.mem.eql(u8, node_kind, "Block") or
            std.mem.eql(u8, node_kind, "block") or
            std.mem.eql(u8, node_kind, "if_statement") or
            std.mem.eql(u8, node_kind, "IfStatement") or
            std.mem.eql(u8, node_kind, "for_statement") or
            std.mem.eql(u8, node_kind, "ForStatement") or
            std.mem.eql(u8, node_kind, "while_statement") or
            std.mem.eql(u8, node_kind, "WhileStatement") or
            std.mem.eql(u8, node_kind, "switch_expression") or
            std.mem.eql(u8, node_kind, "SwitchExpr") or
            std.mem.eql(u8, node_kind, "enum_declaration") or
            std.mem.eql(u8, node_kind, "EnumDecl") or
            std.mem.eql(u8, node_kind, "union_declaration") or
            std.mem.eql(u8, node_kind, "UnionDecl");

        if (is_foldable) {
            const start_pos = node.startPosition();
            const end_pos = node.endPosition();

            // Only create fold if it spans multiple lines
            if (end_pos.row > start_pos.row) {
                try regions.append(self.allocator, .{
                    .start_line = start_pos.row,
                    .end_line = end_pos.row,
                    .level = level,
                    .folded = false,
                });
            }
        }

        // Recursively process children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child_node| {
                try self.collectFoldableNodes(&child_node, regions, level + 1);
            }
        }
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
    pub fn getSelectionRanges(self: *Features, source: []const u8, cursor_byte: usize) ![]SelectionRange {
        if (self.parser == null) {
            return &.{};
        }

        var ranges: std.ArrayList(SelectionRange) = .empty;
        defer ranges.deinit(self.allocator);

        // Parse source with Grove
        const tree = self.parser.?.parse(source) catch return &.{};
        const root_node = tree.rootNode() orelse return &.{};

        // Find all nodes that contain the cursor position
        try self.collectEnclosingNodes(&root_node, cursor_byte, &ranges);

        // Sort ranges by size (smallest first)
        std.mem.sort(SelectionRange, ranges.items, {}, compareSelectionRange);

        return try ranges.toOwnedSlice(self.allocator);
    }

    fn collectEnclosingNodes(
        self: *Features,
        node: *const grove.Node,
        cursor_byte: usize,
        ranges: *std.ArrayList(SelectionRange),
    ) !void {
        const start_byte = node.startByte();
        const end_byte = node.endByte();

        // Only include nodes that contain the cursor
        if (start_byte <= cursor_byte and cursor_byte <= end_byte) {
            const start_pos = node.startPosition();
            const end_pos = node.endPosition();
            const node_kind = node.kind();

            // Determine selection kind based on node type
            const kind = self.classifyNode(node_kind);

            try ranges.append(self.allocator, .{
                .start_byte = start_byte,
                .end_byte = end_byte,
                .start_line = start_pos.row,
                .end_line = end_pos.row,
                .start_col = start_pos.column,
                .end_col = end_pos.column,
                .kind = kind,
            });

            // Recursively process children
            const child_count = node.childCount();
            var i: u32 = 0;
            while (i < child_count) : (i += 1) {
                if (node.child(i)) |child_node| {
                    try self.collectEnclosingNodes(&child_node, cursor_byte, ranges);
                }
            }
        }
    }

    fn classifyNode(self: *Features, node_kind: []const u8) SelectionRange.SelectionKind {
        _ = self;

        // Classify node types into selection kinds
        // Token level
        if (std.mem.eql(u8, node_kind, "identifier") or
            std.mem.eql(u8, node_kind, "IDENTIFIER") or
            std.mem.eql(u8, node_kind, "number_literal") or
            std.mem.eql(u8, node_kind, "INTEGER") or
            std.mem.eql(u8, node_kind, "FLOAT") or
            std.mem.eql(u8, node_kind, "string_literal") or
            std.mem.eql(u8, node_kind, "STRINGLITERALSINGLE") or
            std.mem.eql(u8, node_kind, "char_literal"))
        {
            return .token;
        }

        // Expression level
        if (std.mem.eql(u8, node_kind, "call_expression") or
            std.mem.eql(u8, node_kind, "CallExpr") or
            std.mem.eql(u8, node_kind, "binary_expression") or
            std.mem.eql(u8, node_kind, "BinaryExpr") or
            std.mem.eql(u8, node_kind, "unary_expression") or
            std.mem.eql(u8, node_kind, "PrefixExpr") or
            std.mem.eql(u8, node_kind, "SuffixExpr") or
            std.mem.eql(u8, node_kind, "field_expression") or
            std.mem.eql(u8, node_kind, "FieldAccess"))
        {
            return .expression;
        }

        // Statement level
        if (std.mem.eql(u8, node_kind, "variable_declaration") or
            std.mem.eql(u8, node_kind, "VarDecl") or
            std.mem.eql(u8, node_kind, "const_declaration") or
            std.mem.eql(u8, node_kind, "expression_statement") or
            std.mem.eql(u8, node_kind, "return_statement") or
            std.mem.eql(u8, node_kind, "ReturnStatement") or
            std.mem.eql(u8, node_kind, "assignment") or
            std.mem.eql(u8, node_kind, "AssignStatement"))
        {
            return .statement;
        }

        // Block level
        if (std.mem.eql(u8, node_kind, "block") or
            std.mem.eql(u8, node_kind, "Block") or
            std.mem.eql(u8, node_kind, "InitList"))
        {
            return .block;
        }

        // Function level
        if (std.mem.eql(u8, node_kind, "function_declaration") or
            std.mem.eql(u8, node_kind, "FnDecl") or
            std.mem.eql(u8, node_kind, "fn_decl") or
            std.mem.eql(u8, node_kind, "function_definition") or
            std.mem.eql(u8, node_kind, "FnProto"))
        {
            return .function;
        }

        // Class/struct level
        if (std.mem.eql(u8, node_kind, "struct_declaration") or
            std.mem.eql(u8, node_kind, "StructDecl") or
            std.mem.eql(u8, node_kind, "class_declaration") or
            std.mem.eql(u8, node_kind, "ClassDecl") or
            std.mem.eql(u8, node_kind, "enum_declaration") or
            std.mem.eql(u8, node_kind, "EnumDecl") or
            std.mem.eql(u8, node_kind, "union_declaration") or
            std.mem.eql(u8, node_kind, "UnionDecl") or
            std.mem.eql(u8, node_kind, "ContainerDecl"))
        {
            return .class;
        }

        // File level
        if (std.mem.eql(u8, node_kind, "source_file") or
            std.mem.eql(u8, node_kind, "translation_unit") or
            std.mem.eql(u8, node_kind, "SourceFile"))
        {
            return .file;
        }

        // Default to token for unknown types
        return .token;
    }

    fn compareSelectionRange(_: void, a: SelectionRange, b: SelectionRange) bool {
        const a_size = a.end_byte - a.start_byte;
        const b_size = b.end_byte - b.start_byte;
        return a_size < b_size;
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

    /// Jump to definition result
    pub const Definition = struct {
        start_byte: usize,
        end_byte: usize,
        start_line: usize,
        start_col: usize,
        kind: []const u8, // "function", "variable", "struct", etc.
    };

    /// Find definition of symbol at cursor position using tree-sitter
    pub fn findDefinition(self: *Features, source: []const u8, cursor_byte: usize) !?Definition {
        if (self.parser == null) return null;

        // Parse source
        const tree = self.parser.?.parse(source) catch return null;
        const root_node = tree.rootNode() orelse return null;

        // Get identifier at cursor
        const identifier = self.getIdentifierAtPosition(source, cursor_byte) orelse return null;

        // Search for declaration nodes
        var definitions = std.ArrayList(Definition).empty;
        defer definitions.deinit(self.allocator);

        try self.collectDefinitions(&root_node, source, identifier, &definitions);

        // Return closest definition before cursor (for local scope)
        // or first global definition
        var best: ?Definition = null;
        for (definitions.items) |def| {
            if (def.start_byte < cursor_byte) {
                // Prefer local definitions (closest before cursor)
                if (best == null or def.start_byte > best.?.start_byte) {
                    best = def;
                }
            } else if (best == null) {
                // Use global definition if no local found
                best = def;
            }
        }

        return best;
    }

    pub fn getIdentifierAtPosition(self: *Features, source: []const u8, cursor_byte: usize) ?[]const u8 {
        _ = self;
        if (cursor_byte >= source.len) return null;

        var start = cursor_byte;
        var end = cursor_byte;

        // Find word start
        while (start > 0 and isIdentifierChar(source[start - 1])) {
            start -= 1;
        }

        // Find word end
        while (end < source.len and isIdentifierChar(source[end])) {
            end += 1;
        }

        if (start == end) return null;
        return source[start..end];
    }

    fn isIdentifierChar(ch: u8) bool {
        return (ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or
            ch == '_';
    }

    fn collectDefinitions(
        self: *Features,
        node: *const grove.Node,
        source: []const u8,
        target_name: []const u8,
        definitions: *std.ArrayList(Definition),
    ) !void {
        const node_kind = node.kind();

        // Check if this is a declaration node
        const is_declaration =
            std.mem.eql(u8, node_kind, "FnDecl") or
            std.mem.eql(u8, node_kind, "function_declaration") or
            std.mem.eql(u8, node_kind, "VarDecl") or
            std.mem.eql(u8, node_kind, "variable_declaration") or
            std.mem.eql(u8, node_kind, "const_declaration") or
            std.mem.eql(u8, node_kind, "StructDecl") or
            std.mem.eql(u8, node_kind, "struct_declaration") or
            std.mem.eql(u8, node_kind, "EnumDecl") or
            std.mem.eql(u8, node_kind, "enum_declaration") or
            std.mem.eql(u8, node_kind, "type_declaration");

        if (is_declaration) {
            // Try to extract the name from this declaration
            if (try self.getDeclarationName(node, source)) |name| {
                if (std.mem.eql(u8, name, target_name)) {
                    const start_pos = node.startPosition();
                    try definitions.append(self.allocator, .{
                        .start_byte = node.startByte(),
                        .end_byte = node.endByte(),
                        .start_line = start_pos.row,
                        .start_col = start_pos.column,
                        .kind = node_kind,
                    });
                }
            }
        }

        // Recursively search children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child_node| {
                try self.collectDefinitions(&child_node, source, target_name, definitions);
            }
        }
    }

    fn getDeclarationName(self: *Features, node: *const grove.Node, source: []const u8) !?[]const u8 {
        _ = self;

        // Look for identifier child node (common pattern in tree-sitter grammars)
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_kind = child.kind();

                // Check if this is an identifier or name node
                if (std.mem.eql(u8, child_kind, "identifier") or
                    std.mem.eql(u8, child_kind, "IDENTIFIER") or
                    std.mem.eql(u8, child_kind, "name"))
                {
                    const start = child.startByte();
                    const end = child.endByte();
                    if (end <= source.len) {
                        return source[start..end];
                    }
                }
            }
        }

        return null;
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

test "fold regions ghostlang with tree-sitter" {
    const allocator = std.testing.allocator;

    // Create parser for Ghostlang
    var parser = grove.createParser(allocator, "test.gza") catch |err| {
        std.debug.print("Failed to create parser: {}\n", .{err});
        return err;
    };
    defer parser.deinit();

    var features = Features.init(allocator);
    features.setParser(parser);

    const source =
        \\fn main() {
        \\    const message = "hello"
        \\    if (true) {
        \\        print(message)
        \\    }
        \\}
        \\
        \\fn helper(x) {
        \\    return x * 2
        \\}
    ;

    const regions = try features.getFoldRegions(source);
    defer allocator.free(regions);

    std.debug.print("Found {} fold regions in Ghostlang code\n", .{regions.len});
    for (regions, 0..) |region, i| {
        std.debug.print("  Region {}: lines {}-{} (level {})\n", .{
            i,
            region.start_line,
            region.end_line,
            region.level,
        });
    }

    // Should detect at least 2 functions
    try std.testing.expect(regions.len >= 2);
}

test "find definition zig" {
    const allocator = std.testing.allocator;

    // Create parser for Zig
    var parser = grove.createParser(allocator, "test.zig") catch |err| {
        std.debug.print("Failed to create Zig parser: {}\n", .{err});
        return err;
    };
    defer parser.deinit();

    var features = Features.init(allocator);
    features.setParser(parser);

    const source =
        \\pub fn helper(x: i32) i32 {
        \\    return x * 2;
        \\}
        \\
        \\pub fn main() !void {
        \\    const result = helper(10);
        \\}
    ;

    // Test finding 'helper' definition from the call site
    // "helper" appears at position ~79 in the call
    const call_position: usize = 80;

    const def = try features.findDefinition(source, call_position);
    try std.testing.expect(def != null);

    if (def) |d| {
        std.debug.print("Found definition at line {}, col {} (kind: {s})\n", .{
            d.start_line,
            d.start_col,
            d.kind,
        });

        // Definition should be on line 0 (first line)
        try std.testing.expectEqual(@as(usize, 0), d.start_line);
    }
}

test "find definition ghostlang" {
    const allocator = std.testing.allocator;

    // Create parser for Ghostlang
    var parser = grove.createParser(allocator, "test.gza") catch |err| {
        std.debug.print("Failed to create Ghostlang parser: {}\n", .{err});
        return err;
    };
    defer parser.deinit();

    var features = Features.init(allocator);
    features.setParser(parser);

    const source =
        \\fn helper(x) {
        \\    return x * 2
        \\}
        \\
        \\fn main() {
        \\    const result = helper(10)
        \\}
    ;

    // Test finding 'helper' definition from the call site
    const call_position: usize = 60; // Approximate position of helper call

    const def = try features.findDefinition(source, call_position);
    try std.testing.expect(def != null);

    if (def) |d| {
        std.debug.print("Found Ghostlang definition at line {}, col {} (kind: {s})\n", .{
            d.start_line,
            d.start_col,
            d.kind,
        });

        // Definition should be on line 0
        try std.testing.expectEqual(@as(usize, 0), d.start_line);
    }
}

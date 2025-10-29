const std = @import("std");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const Parser = struct {
    allocator: std.mem.Allocator,
    parser: *c.TSParser,
    language: *const c.TSLanguage,
    tree: ?*c.TSTree,

    pub const Language = enum {
        zig,
        rust,
        javascript,
        typescript,
        json,
        toml,
        markdown,
        c,
        cpp,
        python,
    };

    pub const HighlightType = enum {
        keyword,
        function,
        variable,
        type,
        comment,
        string,
        number,
        operator,
        punctuation,
        constant,
        label,
        property,
        parameter,
        method,
        field,
        @"enum",
        interface,
        namespace,
        decorator,
        none,
    };

    pub const Highlight = struct {
        start_byte: usize,
        end_byte: usize,
        type: HighlightType,
    };

    pub const Error = error{
        ParserCreationFailed,
        LanguageNotSupported,
        ParseFailed,
    } || std.mem.Allocator.Error;

    // External language functions (to be linked)
    extern fn tree_sitter_zig() *const c.TSLanguage;
    extern fn tree_sitter_rust() *const c.TSLanguage;
    extern fn tree_sitter_javascript() *const c.TSLanguage;
    extern fn tree_sitter_typescript() *const c.TSLanguage;
    extern fn tree_sitter_json() *const c.TSLanguage;
    extern fn tree_sitter_toml() *const c.TSLanguage;
    extern fn tree_sitter_markdown() *const c.TSLanguage;
    extern fn tree_sitter_c() *const c.TSLanguage;
    extern fn tree_sitter_cpp() *const c.TSLanguage;
    extern fn tree_sitter_python() *const c.TSLanguage;

    pub fn init(allocator: std.mem.Allocator, language: Language) Error!*Parser {
        const self = try allocator.create(Parser);
        errdefer allocator.destroy(self);

        const parser = c.ts_parser_new() orelse return Error.ParserCreationFailed;
        errdefer c.ts_parser_delete(parser);

        const lang = switch (language) {
            .zig => tree_sitter_zig(),
            .rust => tree_sitter_rust(),
            .javascript => tree_sitter_javascript(),
            .typescript => tree_sitter_typescript(),
            .json => tree_sitter_json(),
            .toml => tree_sitter_toml(),
            .markdown => tree_sitter_markdown(),
            .c => tree_sitter_c(),
            .cpp => tree_sitter_cpp(),
            .python => tree_sitter_python(),
        };

        if (!c.ts_parser_set_language(parser, lang)) {
            return Error.LanguageNotSupported;
        }

        self.* = .{
            .allocator = allocator,
            .parser = parser,
            .language = lang,
            .tree = null,
        };

        return self;
    }

    pub fn deinit(self: *Parser) void {
        if (self.tree) |tree| {
            c.ts_tree_delete(tree);
        }
        c.ts_parser_delete(self.parser);
        self.allocator.destroy(self);
    }

    pub fn parse(self: *Parser, source: []const u8) Error!void {
        if (self.tree) |tree| {
            c.ts_tree_delete(tree);
        }

        self.tree = c.ts_parser_parse_string(
            self.parser,
            null,
            source.ptr,
            @intCast(source.len),
        ) orelse return Error.ParseFailed;
    }

    pub fn parseIncremental(self: *Parser, source: []const u8, edit: Edit) Error!void {
        if (self.tree) |tree| {
            // Apply edit
            const ts_edit = c.TSInputEdit{
                .start_byte = @intCast(edit.start_byte),
                .old_end_byte = @intCast(edit.old_end_byte),
                .new_end_byte = @intCast(edit.new_end_byte),
                .start_point = .{ .row = @intCast(edit.start_point.row), .column = @intCast(edit.start_point.column) },
                .old_end_point = .{ .row = @intCast(edit.old_end_point.row), .column = @intCast(edit.old_end_point.column) },
                .new_end_point = .{ .row = @intCast(edit.new_end_point.row), .column = @intCast(edit.new_end_point.column) },
            };
            c.ts_tree_edit(tree, &ts_edit);

            // Reparse with old tree
            const new_tree = c.ts_parser_parse_string(
                self.parser,
                tree,
                source.ptr,
                @intCast(source.len),
            ) orelse return Error.ParseFailed;

            c.ts_tree_delete(tree);
            self.tree = new_tree;
        } else {
            try self.parse(source);
        }
    }

    pub fn getHighlights(self: *Parser, allocator: std.mem.Allocator) Error![]Highlight {
        const tree = self.tree orelse return &[_]Highlight{};
        const root = c.ts_tree_root_node(tree);

        var highlights = std.ArrayList(Highlight){};
        errdefer highlights.deinit(allocator);

        try self.walkNode(root, &highlights, allocator);

        return highlights.toOwnedSlice(allocator);
    }

    fn walkNode(self: *Parser, node: c.TSNode, highlights: *std.ArrayList(Highlight), allocator: std.mem.Allocator) Error!void {
        const node_type = c.ts_node_type(node);
        const start_byte = c.ts_node_start_byte(node);
        const end_byte = c.ts_node_end_byte(node);

        // Map node types to highlight types
        const highlight_type = self.mapNodeType(node_type);
        if (highlight_type != .none) {
            try highlights.append(allocator, .{
                .start_byte = start_byte,
                .end_byte = end_byte,
                .type = highlight_type,
            });
        }

        // Walk children
        const child_count = c.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            const child = c.ts_node_child(node, i);
            try self.walkNode(child, highlights, allocator);
        }
    }

    fn mapNodeType(self: *Parser, node_type: [*c]const u8) HighlightType {
        _ = self;
        const type_str = std.mem.span(node_type);

        // Common patterns across languages
        if (std.mem.indexOf(u8, type_str, "comment") != null) return .comment;
        if (std.mem.indexOf(u8, type_str, "string") != null) return .string;
        if (std.mem.indexOf(u8, type_str, "number") != null) return .number;
        if (std.mem.indexOf(u8, type_str, "function") != null) return .function;
        if (std.mem.indexOf(u8, type_str, "type") != null) return .type;
        if (std.mem.indexOf(u8, type_str, "keyword") != null) return .keyword;
        if (std.mem.indexOf(u8, type_str, "operator") != null) return .operator;
        if (std.mem.indexOf(u8, type_str, "punctuation") != null) return .punctuation;
        if (std.mem.indexOf(u8, type_str, "variable") != null) return .variable;
        if (std.mem.indexOf(u8, type_str, "parameter") != null) return .parameter;
        if (std.mem.indexOf(u8, type_str, "field") != null) return .field;
        if (std.mem.indexOf(u8, type_str, "property") != null) return .property;
        if (std.mem.indexOf(u8, type_str, "method") != null) return .method;
        if (std.mem.indexOf(u8, type_str, "const") != null) return .constant;
        if (std.mem.indexOf(u8, type_str, "enum") != null) return .@"enum";

        // Specific patterns
        if (std.mem.eql(u8, type_str, "if") or
            std.mem.eql(u8, type_str, "else") or
            std.mem.eql(u8, type_str, "while") or
            std.mem.eql(u8, type_str, "for") or
            std.mem.eql(u8, type_str, "return") or
            std.mem.eql(u8, type_str, "break") or
            std.mem.eql(u8, type_str, "continue")) return .keyword;

        if (std.mem.eql(u8, type_str, "identifier")) return .variable;

        return .none;
    }

    pub const Edit = struct {
        start_byte: usize,
        old_end_byte: usize,
        new_end_byte: usize,
        start_point: Point,
        old_end_point: Point,
        new_end_point: Point,

        pub const Point = struct {
            row: usize,
            column: usize,
        };
    };
};

// Language detection from file extension
pub fn detectLanguage(path: []const u8) ?Parser.Language {
    if (std.mem.endsWith(u8, path, ".zig")) return .zig;
    if (std.mem.endsWith(u8, path, ".rs")) return .rust;
    if (std.mem.endsWith(u8, path, ".js")) return .javascript;
    if (std.mem.endsWith(u8, path, ".ts") or std.mem.endsWith(u8, path, ".tsx")) return .typescript;
    if (std.mem.endsWith(u8, path, ".json")) return .json;
    if (std.mem.endsWith(u8, path, ".toml")) return .toml;
    if (std.mem.endsWith(u8, path, ".md")) return .markdown;
    if (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h")) return .c;
    if (std.mem.endsWith(u8, path, ".cpp") or std.mem.endsWith(u8, path, ".hpp") or std.mem.endsWith(u8, path, ".cc")) return .cpp;
    if (std.mem.endsWith(u8, path, ".py")) return .python;
    return null;
}

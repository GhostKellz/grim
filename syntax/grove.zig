const std = @import("std");

// Grove zig-tree-sitter integration module
// This is the pure Zig Tree-sitter implementation
// grove package = @import("grove");

pub const GroveParser = struct {
    allocator: std.mem.Allocator,
    language: Language,
    tree: ?*Tree = null,
    source: []const u8 = "",

    pub const Language = enum {
        zig,
        rust,
        javascript,
        typescript,
        python,
        c,
        cpp,
        go,
        html,
        css,
        markdown,
        json,
        yaml,
        toml,
        unknown,

        pub fn fromExtension(ext: []const u8) Language {
            if (std.mem.eql(u8, ext, ".zig")) return .zig;
            if (std.mem.eql(u8, ext, ".rs")) return .rust;
            if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return .javascript;
            if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx")) return .typescript;
            if (std.mem.eql(u8, ext, ".py")) return .python;
            if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
            if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cxx") or
                std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".hpp")) return .cpp;
            if (std.mem.eql(u8, ext, ".go")) return .go;
            if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
            if (std.mem.eql(u8, ext, ".css") or std.mem.eql(u8, ext, ".scss")) return .css;
            if (std.mem.eql(u8, ext, ".md")) return .markdown;
            if (std.mem.eql(u8, ext, ".json")) return .json;
            if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return .yaml;
            if (std.mem.eql(u8, ext, ".toml")) return .toml;
            return .unknown;
        }

        pub fn name(self: Language) []const u8 {
            return switch (self) {
                .zig => "zig",
                .rust => "rust",
                .javascript => "javascript",
                .typescript => "typescript",
                .python => "python",
                .c => "c",
                .cpp => "cpp",
                .go => "go",
                .html => "html",
                .css => "css",
                .markdown => "markdown",
                .json => "json",
                .yaml => "yaml",
                .toml => "toml",
                .unknown => "unknown",
            };
        }
    };

    pub const HighlightType = enum {
        keyword,
        string_literal,
        number_literal,
        comment,
        function_name,
        type_name,
        variable,
        operator,
        punctuation,
        @"error",
        none,

        pub fn toCssClass(self: HighlightType) []const u8 {
            return switch (self) {
                .keyword => "grim-keyword",
                .string_literal => "grim-string",
                .number_literal => "grim-number",
                .comment => "grim-comment",
                .function_name => "grim-function",
                .type_name => "grim-type",
                .variable => "grim-variable",
                .operator => "grim-operator",
                .punctuation => "grim-punctuation",
                .@"error" => "grim-error",
                .none => "grim-text",
            };
        }
    };

    pub const Highlight = struct {
        start: usize,
        end: usize,
        type: HighlightType,

        pub fn length(self: Highlight) usize {
            return self.end - self.start;
        }
    };

    pub const Tree = opaque {};

    pub const Error = error{
        ParseError,
        LanguageNotSupported,
        InvalidSyntax,
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator, language: Language) !*GroveParser {
        const self = try allocator.create(GroveParser);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .language = language,
        };

        return self;
    }

    pub fn deinit(self: *GroveParser) void {
        if (self.tree) |tree| {
            // grove.tree_delete(tree);
            _ = tree; // Placeholder
        }
        self.allocator.destroy(self);
    }

    pub fn parse(self: *GroveParser, source: []const u8) Error!void {
        self.source = source;

        // TODO: Implement Grove parsing when dependency is available
        // self.tree = grove.parser_parse_string(parser, source.ptr, source.len);
        // if (self.tree == null) return Error.ParseError;
    }

    pub fn getHighlights(self: *GroveParser, allocator: std.mem.Allocator) Error![]Highlight {
        if (self.tree == null) return &.{};

        // TODO: Implement Grove highlighting when dependency is available
        // For now, return basic lexical highlighting as fallback
        return try self.getFallbackHighlights(allocator);
    }

    // Fallback highlighting using simple lexical analysis
    fn getFallbackHighlights(self: *GroveParser, allocator: std.mem.Allocator) Error![]Highlight {
        var highlights = std.ArrayList(Highlight).init(allocator);
        errdefer highlights.deinit();

        var i: usize = 0;
        while (i < self.source.len) {
            const char = self.source[i];

            // Skip whitespace
            if (std.ascii.isWhitespace(char)) {
                i += 1;
                continue;
            }

            // Comments
            if (self.isCommentStart(i)) {
                const end = self.findCommentEnd(i);
                try highlights.append(.{
                    .start = i,
                    .end = end,
                    .type = .comment,
                });
                i = end;
                continue;
            }

            // String literals
            if (char == '"' or char == '\'' or char == '`') {
                const end = self.findStringEnd(i, char);
                try highlights.append(.{
                    .start = i,
                    .end = end,
                    .type = .string_literal,
                });
                i = end;
                continue;
            }

            // Numbers
            if (std.ascii.isDigit(char)) {
                const end = self.findNumberEnd(i);
                try highlights.append(.{
                    .start = i,
                    .end = end,
                    .type = .number_literal,
                });
                i = end;
                continue;
            }

            // Keywords and identifiers
            if (std.ascii.isAlphabetic(char) or char == '_') {
                const end = self.findIdentifierEnd(i);
                const word = self.source[i..end];
                const highlight_type = self.classifyWord(word);

                if (highlight_type != .none) {
                    try highlights.append(.{
                        .start = i,
                        .end = end,
                        .type = highlight_type,
                    });
                }
                i = end;
                continue;
            }

            // Operators and punctuation
            if (self.isOperatorOrPunctuation(char)) {
                try highlights.append(.{
                    .start = i,
                    .end = i + 1,
                    .type = if (self.isOperator(char)) .operator else .punctuation,
                });
            }

            i += 1;
        }

        return highlights.toOwnedSlice();
    }

    fn isCommentStart(self: *GroveParser, pos: usize) bool {
        if (pos >= self.source.len) return false;

        return switch (self.language) {
            .zig, .c, .cpp, .rust, .javascript, .typescript =>
                pos + 1 < self.source.len and
                self.source[pos] == '/' and
                self.source[pos + 1] == '/',
            .python, .yaml, .toml => self.source[pos] == '#',
            .html => pos + 3 < self.source.len and
                std.mem.startsWith(u8, self.source[pos..], "<!--"),
            else => false,
        };
    }

    fn findCommentEnd(self: *GroveParser, start: usize) usize {
        return switch (self.language) {
            .html => blk: {
                var i = start + 4; // Skip "<!--"
                while (i + 2 < self.source.len) {
                    if (std.mem.startsWith(u8, self.source[i..], "-->")) {
                        break :blk i + 3;
                    }
                    i += 1;
                }
                break :blk self.source.len;
            },
            else => blk: {
                var i = start;
                while (i < self.source.len and self.source[i] != '\n') {
                    i += 1;
                }
                break :blk i;
            },
        };
    }

    fn findStringEnd(self: *GroveParser, start: usize, quote: u8) usize {
        var i = start + 1;
        while (i < self.source.len) {
            const char = self.source[i];
            if (char == quote) return i + 1;
            if (char == '\\' and i + 1 < self.source.len) {
                i += 2; // Skip escaped character
            } else {
                i += 1;
            }
        }
        return self.source.len;
    }

    fn findNumberEnd(self: *GroveParser, start: usize) usize {
        var i = start;
        var has_dot = false;

        while (i < self.source.len) {
            const char = self.source[i];
            if (std.ascii.isDigit(char)) {
                i += 1;
            } else if (char == '.' and !has_dot) {
                has_dot = true;
                i += 1;
            } else {
                break;
            }
        }
        return i;
    }

    fn findIdentifierEnd(self: *GroveParser, start: usize) usize {
        var i = start;
        while (i < self.source.len) {
            const char = self.source[i];
            if (std.ascii.isAlphanumeric(char) or char == '_') {
                i += 1;
            } else {
                break;
            }
        }
        return i;
    }

    fn classifyWord(self: *GroveParser, word: []const u8) HighlightType {
        const keywords = switch (self.language) {
            .zig => &.{ "const", "var", "fn", "pub", "if", "else", "while", "for", "switch", "try", "catch", "return", "struct", "enum", "union", "error", "comptime" },
            .rust => &.{ "fn", "let", "mut", "const", "if", "else", "while", "for", "loop", "match", "return", "struct", "enum", "impl", "trait", "pub", "use" },
            .javascript, .typescript => &.{ "function", "const", "let", "var", "if", "else", "while", "for", "return", "class", "extends", "import", "export", "async", "await" },
            .python => &.{ "def", "class", "if", "else", "elif", "while", "for", "return", "import", "from", "try", "except", "finally", "with", "async", "await" },
            .c, .cpp => &.{ "int", "char", "float", "double", "void", "if", "else", "while", "for", "return", "struct", "typedef", "const", "static", "extern" },
            .go => &.{ "func", "var", "const", "if", "else", "for", "range", "return", "struct", "interface", "map", "chan", "go", "defer", "package", "import" },
            else => &.{},
        };

        for (keywords) |keyword| {
            if (std.mem.eql(u8, word, keyword)) {
                return .keyword;
            }
        }

        return .none;
    }

    fn isOperatorOrPunctuation(self: *GroveParser, char: u8) bool {
        _ = self;
        return switch (char) {
            '+', '-', '*', '/', '%', '=', '!', '<', '>', '&', '|', '^', '~' => true,
            '(', ')', '[', ']', '{', '}', ';', ',', '.', ':', '?', '@', '#' => true,
            else => false,
        };
    }

    fn isOperator(self: *GroveParser, char: u8) bool {
        _ = self;
        return switch (char) {
            '+', '-', '*', '/', '%', '=', '!', '<', '>', '&', '|', '^', '~' => true,
            else => false,
        };
    }
};

// Detection utilities
pub fn detectLanguage(filename: []const u8) GroveParser.Language {
    const ext = std.fs.path.extension(filename);
    return GroveParser.Language.fromExtension(ext);
}

pub fn createParser(allocator: std.mem.Allocator, filename: []const u8) !*GroveParser {
    const language = detectLanguage(filename);
    return GroveParser.init(allocator, language);
}
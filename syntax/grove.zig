const std = @import("std");

// Grove zig-tree-sitter integration module
// This is the pure Zig Tree-sitter implementation
const grove = @import("grove");
// Import core Grove types
pub const Parser = grove.Parser;
pub const Tree = grove.Tree;
pub const Node = grove.Node;
pub const Point = grove.Point;
pub const Query = grove.Query;
pub const QueryCursor = grove.QueryCursor;
pub const GroveLanguage = grove.Language;
pub const BundledLanguages = grove.Languages;

const KEYWORDS = struct {
    const zig = [_][]const u8{
        "const", "var", "fn", "pub", "if", "else", "while", "for", "switch",
        "try", "catch", "return", "struct", "enum", "union", "error", "comptime",
    };
    const rust = [_][]const u8{
        "fn", "let", "mut", "const", "if", "else", "while", "for", "loop",
        "match", "return", "struct", "enum", "impl", "trait", "pub", "use",
    };
    const js_ts = [_][]const u8{
        "function", "const", "let", "var", "if", "else", "while", "for", "return",
        "class", "extends", "import", "export", "async", "await",
    };
    const python = [_][]const u8{
        "def", "class", "if", "else", "elif", "while", "for", "return", "import",
        "from", "try", "except", "finally", "with", "async", "await",
    };
    const yaml = [_][]const u8{
        "true", "false", "null", "yes", "no", "on", "off",
        "anchor", "alias", "map", "seq", "scalar",
    };
    const toml = [_][]const u8{
        "true", "false", "datetime", "table", "inline", "array",
        "integer", "float", "boolean", "string",
    };
    const c = [_][]const u8{
        "int", "char", "float", "double", "void", "if", "else", "while", "for",
        "return", "struct", "typedef", "const", "static", "extern",
    };
    const cmake = [_][]const u8{
        "function", "macro", "endfunction", "endmacro", "if", "elseif", "endif",
        "foreach", "endforeach", "while", "endwhile", "set", "set_property",
        "add_executable", "add_library", "target_link_libraries", "find_package",
        "include", "project", "cmake_minimum_required",
    };
    const go = [_][]const u8{
        "func", "var", "const", "if", "else", "for", "range", "return", "struct",
        "interface", "map", "chan", "go", "defer", "package", "import",
    };
    const none = [_][]const u8{};
};

pub const GroveParser = struct {
    allocator: std.mem.Allocator,
    lang_name: []const u8,
    language: LangType,
    parser: *Parser,
    tree: ?Tree = null,
    source: []const u8 = "",

    pub const LangType = enum {
        zig,
        rust,
        javascript,
        typescript,
        python,
        c,
        cmake,
        cpp,
        go,
        html,
        css,
        markdown,
        json,
        yaml,
        toml,
        ghostlang,
        unknown,

        pub fn fromExtension(ext: []const u8) LangType {
            if (std.mem.eql(u8, ext, ".zig")) return .zig;
            if (std.mem.eql(u8, ext, ".rs")) return .rust;
            if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return .javascript;
            if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx")) return .typescript;
            if (std.mem.eql(u8, ext, ".py")) return .python;
            if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
            if (std.mem.eql(u8, ext, ".cmake")) return .cmake;
            if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cxx") or
                std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".hpp")) return .cpp;
            if (std.mem.eql(u8, ext, ".go")) return .go;
            if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
            if (std.mem.eql(u8, ext, ".css") or std.mem.eql(u8, ext, ".scss")) return .css;
            if (std.mem.eql(u8, ext, ".md")) return .markdown;
            if (std.mem.eql(u8, ext, ".json")) return .json;
            if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return .yaml;
            if (std.mem.eql(u8, ext, ".toml")) return .toml;
            if (std.mem.eql(u8, ext, ".gza") or std.mem.eql(u8, ext, ".ghost")) return .ghostlang;
            return .unknown;
        }

        pub fn name(self: LangType) []const u8 {
            return switch (self) {
                .zig => "zig",
                .rust => "rust",
                .javascript => "javascript",
                .typescript => "typescript",
                .python => "python",
                .c => "c",
                .cmake => "cmake",
                .cpp => "cpp",
                .go => "go",
                .html => "html",
                .css => "css",
                .markdown => "markdown",
                .json => "json",
                .yaml => "yaml",
                .toml => "toml",
                .ghostlang => "ghostlang",
                .unknown => "unknown",
            };
        }

        pub fn toBundled(self: LangType) ?BundledLanguages {
            return switch (self) {
                .zig => .zig,
                .rust => .rust,
                .javascript => .javascript,
                .typescript => .typescript,
                .python => .python,
                .c => .c,
                .cmake => .cmake,
                .cpp => .c, // Map C++ to C grammar
                .markdown => .markdown,
                .json => .json,
                .yaml => .yaml,
                .toml => .toml,
                .ghostlang => .ghostlang,
                else => null, // Not in Grove's bundled languages
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

    // Grove Editor Service Types
    pub const DocumentSymbol = struct {
        name: []const u8,
        kind: SymbolKind,
        start: Position,
        end: Position,
        children: []DocumentSymbol = &.{},

        pub const SymbolKind = enum {
            function,
            variable,
            class,
            module,
            property,
            field,
            constructor,
            @"enum",
            interface,
            constant,
        };
    };

    pub const FoldingRange = struct {
        start_line: u32,
        start_character: u32,
        end_line: u32,
        end_character: u32,
        kind: FoldingKind = .region,

        pub const FoldingKind = enum {
            comment,
            imports,
            region,
        };
    };

    pub const Position = struct {
        line: u32,
        character: u32,
    };

    pub const TextObject = struct {
        start: Position,
        end: Position,
        kind: TextObjectKind,

        pub const TextObjectKind = enum {
            function_outer,
            function_inner,
            block_outer,
            block_inner,
            parameter,
            statement,
        };
    };

    pub const Error = error{
        ParseError,
        LanguageNotSupported,
        InvalidSyntax,
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator, lang_type: LangType) !*GroveParser {
        const self = try allocator.create(GroveParser);
        errdefer allocator.destroy(self);

        // Create Grove parser
        const parser_ptr = try allocator.create(Parser);
        parser_ptr.* = try Parser.init(allocator);

        // Convert to Grove's bundled language and set
        if (lang_type.toBundled()) |bundled_lang| {
            const grove_lang = GroveLanguage.fromRaw(bundled_lang.raw()) catch {
                return Error.LanguageNotSupported;
            };
            try parser_ptr.setLanguage(grove_lang);
        } else {
            return Error.LanguageNotSupported;
        }

        self.* = .{
            .allocator = allocator,
            .lang_name = lang_type.name(),
            .language = lang_type,
            .parser = parser_ptr,
        };

        return self;
    }

    pub fn deinit(self: *GroveParser) void {
        if (self.tree) |*tree| {
            tree.deinit();
        }
        self.parser.deinit();
        self.allocator.destroy(self.parser);
        self.allocator.destroy(self);
    }

    pub fn parse(self: *GroveParser, source: []const u8) !Tree {
        self.source = source;

        // Parse with Grove
        const tree = self.parser.parseUtf8(null, source) catch |err| {
            return switch (err) {
                error.ParserUnavailable => Error.ParseError,
                error.LanguageNotSet => Error.LanguageNotSupported,
                error.LanguageUnsupported => Error.LanguageNotSupported,
                error.InputTooLarge => Error.ParseError,
                error.ParseFailed => Error.ParseError,
            };
        };
        self.tree = tree;
        return tree;
    }

    pub fn getHighlights(self: *GroveParser, allocator: std.mem.Allocator) Error![]Highlight {
        if (self.tree == null) return &.{};

        // TODO: Implement Grove highlighting when dependency is available
        // For now, return basic lexical highlighting as fallback
        return try self.getFallbackHighlights(allocator);
    }

    // Fallback highlighting using simple lexical analysis
    fn getFallbackHighlights(self: *GroveParser, allocator: std.mem.Allocator) Error![]Highlight {
    var highlights = std.ArrayListUnmanaged(Highlight){};
    errdefer highlights.deinit(allocator);

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
                    try highlights.append(allocator, .{
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
                    try highlights.append(allocator, .{
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
                    try highlights.append(allocator, .{
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
                        try highlights.append(allocator, .{
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
                    try highlights.append(allocator, .{
                    .start = i,
                    .end = i + 1,
                    .type = if (self.isOperator(char)) .operator else .punctuation,
                });
            }

            i += 1;
        }

        return highlights.toOwnedSlice(allocator);
    }

    // Grove Editor Services (as per ADAPTER_GUIDE.md)
    pub fn documentSymbols(self: *GroveParser, allocator: std.mem.Allocator) Error![]DocumentSymbol {
        _ = allocator;
        _ = self;
        // TODO: Implement using Grove's Editor utilities when available
        return &.{};
    }

    pub fn foldingRanges(self: *GroveParser, allocator: std.mem.Allocator) Error![]FoldingRange {
        _ = allocator;
        _ = self;
        // TODO: Implement using Grove's Editor utilities when available
        return &.{};
    }

    pub fn textobjectAt(self: *GroveParser, position: Position) ?TextObject {
        _ = position;
        _ = self;
        // TODO: Implement using Grove's Editor utilities when available
        return null;
    }

    fn isCommentStart(self: *GroveParser, pos: usize) bool {
        if (pos >= self.source.len) return false;

        return switch (self.language) {
            .zig, .c, .cpp, .rust, .javascript, .typescript =>
                pos + 1 < self.source.len and
                self.source[pos] == '/' and
                self.source[pos + 1] == '/',
            .python, .yaml, .toml, .cmake => self.source[pos] == '#',
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
            .zig => KEYWORDS.zig[0..],
            .rust => KEYWORDS.rust[0..],
            .javascript, .typescript => KEYWORDS.js_ts[0..],
            .python => KEYWORDS.python[0..],
            .yaml => KEYWORDS.yaml[0..],
            .toml => KEYWORDS.toml[0..],
            .c, .cpp => KEYWORDS.c[0..],
            .cmake => KEYWORDS.cmake[0..],
            .go => KEYWORDS.go[0..],
            else => KEYWORDS.none[0..],
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
pub fn detectLanguage(filename: []const u8) GroveParser.LangType {
    const basename = std.fs.path.basename(filename);
    if (std.mem.eql(u8, basename, "CMakeLists.txt")) {
        return GroveParser.LangType.cmake;
    }

    const ext = std.fs.path.extension(filename);
    return GroveParser.LangType.fromExtension(ext);
}

pub fn createParser(allocator: std.mem.Allocator, filename: []const u8) !*GroveParser {
    const language = detectLanguage(filename);
    return GroveParser.init(allocator, language);
}

test "detect language identifies cmake files" {
    try std.testing.expectEqual(GroveParser.Language.cmake, detectLanguage("CMakeLists.txt"));
    try std.testing.expectEqual(GroveParser.Language.cmake, detectLanguage("build.cmake"));
}

test "detect language identifies new config grammars" {
    try std.testing.expectEqual(GroveParser.Language.toml, detectLanguage("Cargo.toml"));
    try std.testing.expectEqual(GroveParser.Language.yaml, detectLanguage("docker-compose.yaml"));
    try std.testing.expectEqual(GroveParser.Language.yaml, detectLanguage(".github/workflows/ci.yml"));
}

test "detect language maps c headers" {
    try std.testing.expectEqual(GroveParser.LangType.c, detectLanguage("main.c"));
    try std.testing.expectEqual(GroveParser.LangType.c, detectLanguage("lib/header.h"));
}

test "fallback tokenizer highlights keywords" {
    const allocator = std.testing.allocator;

    var parser = try GroveParser.init(allocator, .zig);
    defer parser.deinit();

    const source = "const x = 42;";
    _ = try parser.parse(source);

    const highlights = try parser.getFallbackHighlights(allocator);
    defer allocator.free(highlights);

    // Should find at least the keyword "const"
    var found_keyword = false;
    for (highlights) |h| {
        if (h.type == .keyword) {
            const text = source[h.start..h.end];
            if (std.mem.eql(u8, text, "const")) {
                found_keyword = true;
            }
        }
    }
    try std.testing.expect(found_keyword);
}

test "fallback tokenizer highlights strings" {
    const allocator = std.testing.allocator;

    var parser = try GroveParser.init(allocator, .zig);
    defer parser.deinit();

    const source =
        \\const msg = "hello world";
    ;
    _ = try parser.parse(source);

    const highlights = try parser.getFallbackHighlights(allocator);
    defer allocator.free(highlights);

    // Should find the string literal
    var found_string = false;
    for (highlights) |h| {
        if (h.type == .string_literal) {
            const text = source[h.start..h.end];
            if (std.mem.indexOf(u8, text, "hello") != null) {
                found_string = true;
            }
        }
    }
    try std.testing.expect(found_string);
}

test "fallback tokenizer highlights numbers" {
    const allocator = std.testing.allocator;

    var parser = try GroveParser.init(allocator, .zig);
    defer parser.deinit();

    const source = "const x = 42;";
    _ = try parser.parse(source);

    const highlights = try parser.getFallbackHighlights(allocator);
    defer allocator.free(highlights);

    // Should find the number 42
    var found_number = false;
    for (highlights) |h| {
        if (h.type == .number_literal) {
            const text = source[h.start..h.end];
            if (std.mem.eql(u8, text, "42")) {
                found_number = true;
            }
        }
    }
    try std.testing.expect(found_number);
}

test "fallback tokenizer highlights comments" {
    const allocator = std.testing.allocator;

    var parser = try GroveParser.init(allocator, .zig);
    defer parser.deinit();

    const source = "// This is a comment\nconst x = 1;";
    _ = try parser.parse(source);

    const highlights = try parser.getFallbackHighlights(allocator);
    defer allocator.free(highlights);

    // Should find the comment
    var found_comment = false;
    for (highlights) |h| {
        if (h.type == .comment) {
            const text = source[h.start..h.end];
            if (std.mem.indexOf(u8, text, "comment") != null) {
                found_comment = true;
            }
        }
    }
    try std.testing.expect(found_comment);
}

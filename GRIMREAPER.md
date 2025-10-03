# GRIMREAPER.md
## How Grim Leverages Grove for Editor Features

**Last Updated**: 2025-10-03 (v0.1.0)

---

## Overview

**Grim** is a Neovim-inspired terminal text editor built in Zig. **Grove** is its Tree-sitter powered syntax engine, providing parsing, highlighting, and LSP-like features for 14 languages out of the box.

This document explains how Grim consumes Grove as a dependency and leverages its bundled grammars, editor utilities, and performance optimizations.

---

## Package Integration

### Adding Grove to Grim

Grove is consumed as a Zig package:

```bash
# In your Grim project:
zig fetch --save https://github.com/ghostkellz/grove/archive/refs/tags/v0.1.0.tar.gz
```

**Critical Fix in v0.1.0**: Grove's `build.zig.zon` now includes `vendor/tree-sitter` and `vendor/grammars` in `.paths`, ensuring the tree-sitter runtime (`lib.c`) and all 14 prebuilt grammar parsers/scanners are packaged correctly. This allows Grim to build with `-Dghostlang=true` and other language flags without missing dependency errors.

### Build System Integration

In `build.zig`:

```zig
const grove_dep = b.dependency("grove", .{
    .target = target,
    .optimize = optimize,
});
const grove_mod = grove_dep.module("grove");

// Add to your executable
exe.root_module.addImport("grove", grove_mod);
```

---

## Language Support

Grove bundles **14 production-ready grammars**, all compiled against tree-sitter 0.25.10 (ABI 15):

| Language | Grove API | File Extensions | Use Case |
|----------|-----------|----------------|----------|
| **Bash** | `grove.Languages.bash.get()` | `.sh`, `.bash` | Shell scripts |
| **C** | `grove.Languages.c.get()` | `.c`, `.h` | C programming |
| **CMake** | `grove.Languages.cmake.get()` | `CMakeLists.txt` | Build configs |
| **Ghostlang** | `grove.Languages.ghostlang.get()` | `.ghost`, `.gza` | Ghostlang scripts |
| **JavaScript** | `grove.Languages.javascript.get()` | `.js`, `.mjs` | Web scripting |
| **JSON** | `grove.Languages.json.get()` | `.json` | Config files |
| **Markdown** | `grove.Languages.markdown.get()` | `.md` | Documentation |
| **Python** | `grove.Languages.python.get()` | `.py` | Python scripts |
| **Rust** | `grove.Languages.rust.get()` | `.rs` | Rust code |
| **TOML** | `grove.Languages.toml.get()` | `.toml` | Cargo/config files |
| **TSX** | `grove.Languages.tsx.get()` | `.tsx` | React TypeScript |
| **TypeScript** | `grove.Languages.typescript.get()` | `.ts` | TypeScript |
| **YAML** | `grove.Languages.yaml.get()` | `.yml`, `.yaml` | CI/CD configs |
| **Zig** | `grove.Languages.zig.get()` | `.zig` | Zig language |

### How Grim Uses Language Detection

```zig
const grove = @import("grove");

pub fn detectLanguage(file_path: []const u8) !grove.Language {
    if (std.mem.endsWith(u8, file_path, ".zig")) return try grove.Languages.zig.get();
    if (std.mem.endsWith(u8, file_path, ".rs")) return try grove.Languages.rust.get();
    if (std.mem.endsWith(u8, file_path, ".ts")) return try grove.Languages.typescript.get();
    if (std.mem.endsWith(u8, file_path, ".ghost")) return try grove.Languages.ghostlang.get();
    // ... etc
    return error.UnsupportedLanguage;
}
```

---

## Core Editor Features

### 1. Syntax Highlighting

Grove provides Tree-sitter queries for syntax highlighting:

```zig
const grove = @import("grove");

// Parse the buffer
var parser = try grove.Parser.init(allocator);
defer parser.deinit();

const language = try grove.Languages.typescript.get();
try parser.setLanguage(language);

var tree = try parser.parseUtf8(null, buffer_contents);
defer tree.deinit();

// Extract highlights
const highlights = try grove.Highlight.collectHighlights(
    allocator,
    tree.rootNode().?,
    buffer_contents,
    language,
);
defer allocator.free(highlights);

// Apply to Grim's rendering pipeline
for (highlights) |hl| {
    grim.applyHighlight(hl.range, hl.capture_name);
}
```

**Available Captures**: `keyword`, `function`, `variable`, `string`, `comment`, `type`, `operator`, `constant`, `property`, etc.

### 2. Document Symbols (Outline View)

Extract functions, classes, variables for a sidebar/outline:

```zig
const grove = @import("grove");

var services = grove.EditorServices.init(allocator);
defer services.deinit();

const symbols = try services.documentSymbols(
    .typescript,  // or .zig, .rust, .python, etc.
    tree.rootNode().?,
    buffer_contents,
);
defer grove.freeDocumentSymbols(allocator, symbols);

// Render in Grim's outline panel
for (symbols) |sym| {
    grim.outline.addItem(sym.name, sym.kind, sym.range);
}
```

**Symbol Kinds**: `function`, `method`, `class`, `variable`, `constant`, `property`, `module`, `namespace`.

### 3. Code Folding

Intelligent folding based on syntax structure:

```zig
const folding = try services.foldingRanges(
    .rust,
    tree.rootNode().?,
    .{ .min_line_span = 2 },  // Only fold blocks spanning 2+ lines
);
defer allocator.free(folding);

// Apply to Grim's folding system
for (folding) |range| {
    grim.folds.addFoldableRegion(
        range.start_line,
        range.end_line,
        range.kind,
    );
}
```

### 4. Incremental Edits

Grove supports incremental parsing for sub-5ms latency:

```zig
const grove = @import("grove");

// User types "hello" at line 10, column 5
var edit_builder = grove.EditBuilder.init(allocator);
defer edit_builder.deinit();

try edit_builder.insertText(tree, 10, 5, "hello");
const edit = edit_builder.build();

// Re-parse only changed regions
var new_tree = try parser.parseUtf8(tree, updated_buffer);
defer tree.deinit();  // old tree
tree = new_tree;
```

**Performance Target**: <5ms P50 latency per edit (track with `zig build bench-latency`).

### 5. Syntax Error Recovery

Extract errors for diagnostics/linting:

```zig
const errors = try grove.getSyntaxErrors(allocator, tree.rootNode().?, buffer_contents);
defer allocator.free(errors);

for (errors) |err| {
    grim.diagnostics.addError(
        err.range,
        err.message,
        .syntax_error,
    );
}
```

### 6. Multi-Language Support (Injections)

Handle embedded languages (e.g., code blocks in Markdown, scripts in HTML):

```zig
var injected = try grove.parseWithInjections(
    allocator,
    parser,
    tree,
    markdown_source,
);
defer injected.deinit();

// Render highlighted code blocks
for (injected.ranges) |range| {
    grim.renderCodeBlock(range.language, range.content);
}
```

---

## Grim Bridge Integration

Grove provides a **GrimBridge** specifically for editor integration:

```zig
const grove = @import("grove");

var bridge = grove.GrimBridge.init(allocator);
defer bridge.deinit();

// Get complete configuration for Grim
const config = try bridge.getGrimConfig();
defer allocator.free(config);

// Get language-specific queries
const ts_queries = try bridge.getLanguageQueries(.typescript);
defer allocator.free(ts_queries);

// Get theme configuration
const theme = try bridge.getThemeConfig("grim_dark");
defer if (theme) |t| allocator.free(t);

// Generate feature summary for docs/help menu
const summary = try bridge.getFeatureSummary();
defer allocator.free(summary);
```

### Theme Integration

Grove ships with 3 built-in themes:
- **default** – Grove default theme
- **grim_dark** – Dark theme optimized for Grim
- **grim_light** – Light theme optimized for Grim

Apply in Grim:

```zig
const theme = try bridge.getThemeConfig("grim_dark");
if (theme) |t| {
    grim.setTheme(t);
}
```

---

## Performance Characteristics

Grove is optimized for real-time editing:

### Parsing Throughput
- **Target**: ≥10 MB/s (vs C Tree-sitter baseline)
- **Benchmark**: `zig build bench`

### Incremental Latency
- **Target**: <5ms P50 per edit
- **Benchmark**: `zig build bench-latency`

### Memory Usage
- **Target**: <100 MB for 10k-file projects
- **Strategy**: Parser pooling (`grove.ParserPool`), arena allocators, tree cloning for undo/redo

### Grim-Specific Optimizations

```zig
// 1. Parser Pooling (reuse parsers across buffers)
var pool = try grove.ParserPool.init(allocator, 4);  // 4 parsers
defer pool.deinit();

const parser = try pool.acquire();
defer pool.release(parser);

// 2. Chunked Input (avoid buffer copies)
var tree = try parser.parseChunks(null, buffer.chunks());
defer tree.deinit();

// 3. Tree Cloning (undo/redo without re-parsing)
const snapshot = try tree.clone();
defer snapshot.deinit();
grim.undo_stack.push(snapshot);
```

---

## Query System

Grove exposes Tree-sitter queries for advanced features:

### Highlight Queries

```zig
const query_source = @embedFile("vendor/grammars/typescript/queries/highlights.scm");
var query = try grove.Query.init(allocator, language, query_source);
defer query.deinit();

var cursor = try grove.QueryCursor.init();
defer cursor.deinit();
cursor.exec(&query, tree.rootNode().?);

while (cursor.nextCapture(&query)) |hit| {
    const name = hit.capture.name;  // "keyword", "function", etc.
    const node = hit.capture.node;
    // Apply highlight
}
```

### Custom Queries

Grim can define custom queries for navigation, refactoring, etc.:

```zig
const custom_query =
    \\(function_declaration name: (identifier) @func.name)
    \\(call_expression function: (identifier) @func.call)
;

var query = try grove.Query.init(allocator, language, custom_query);
defer query.deinit();

// Find all function calls
var cursor = try grove.QueryCursor.init();
defer cursor.deinit();
cursor.exec(&query, root);

while (cursor.nextCapture(&query)) |hit| {
    if (std.mem.eql(u8, hit.capture.name, "func.call")) {
        // Jump to definition, show references, etc.
    }
}
```

---

## Language Utilities API

Grove provides per-language utilities via `EditorServices`:

```zig
const grove = @import("grove");

var services = grove.EditorServices.init(allocator);
defer services.deinit();

// Auto-detects language and initializes utilities
const symbols = try services.documentSymbols(.zig, root, source);
defer grove.freeDocumentSymbols(allocator, symbols);

const folding = try services.foldingRanges(.rust, root, .{});
defer allocator.free(folding);
```

### Supported Languages

All 14 bundled languages have utilities:
- `ghostlang`, `typescript`, `tsx`, `zig`, `json`, `rust`
- `bash`, `javascript`, `python`, `markdown`
- `cmake`, `toml`, `yaml`, `c`

---

## Advanced Features

### 1. Dynamic Grammar Loading

Load additional grammars at runtime:

```zig
var registry = grove.LanguageRegistry.init(allocator);
defer registry.deinit();

try registry.loadFromSharedLibrary("path/to/custom-grammar.so", "custom_lang");
const custom = registry.get("custom_lang");
```

### 2. Query Validation

Validate .scm files before loading:

```zig
const valid = try grove.validateQueryFile(allocator, language, "custom.scm");
if (!valid) {
    grim.showError("Invalid query file");
}
```

### 3. Error Context

Get detailed error information:

```zig
const errors = try grove.getSyntaxErrors(allocator, root, source);
for (errors) |err| {
    const context = source[err.context_start..err.context_end];
    grim.diagnostics.addError(err.range, err.message, context);
}
```

---

## Integration Checklist

When integrating Grove into Grim:

- [x] Add Grove as Zig dependency (`zig fetch --save`)
- [x] Detect file language from extension
- [x] Parse buffer with `grove.Parser`
- [x] Extract highlights with `grove.Highlight`
- [x] Extract symbols with `grove.EditorServices.documentSymbols()`
- [x] Extract folding ranges with `grove.EditorServices.foldingRanges()`
- [x] Handle incremental edits with `grove.EditBuilder`
- [x] Display syntax errors from `grove.getSyntaxErrors()`
- [x] Support theme switching via `grove.GrimBridge`
- [x] Implement parser pooling for multi-buffer performance
- [ ] Add custom queries for Grim-specific features (go-to-definition, refactoring)
- [ ] Benchmark with `zig build bench` and `zig build bench-latency`
- [ ] Profile memory usage with 1000+ file projects

---

## Example: Full Buffer Integration

```zig
const std = @import("std");
const grove = @import("grove");

pub const GrimBuffer = struct {
    allocator: std.mem.Allocator,
    parser: grove.Parser,
    tree: ?grove.Tree,
    language: grove.Language,
    services: grove.EditorServices,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !GrimBuffer {
        const language = try detectLanguage(file_path);

        var parser = try grove.Parser.init(allocator);
        errdefer parser.deinit();
        try parser.setLanguage(language);

        return .{
            .allocator = allocator,
            .parser = parser,
            .tree = null,
            .language = language,
            .services = grove.EditorServices.init(allocator),
        };
    }

    pub fn deinit(self: *GrimBuffer) void {
        if (self.tree) |*tree| tree.deinit();
        self.parser.deinit();
        self.services.deinit();
    }

    pub fn parse(self: *GrimBuffer, source: []const u8) !void {
        if (self.tree) |*old| old.deinit();
        self.tree = try self.parser.parseUtf8(null, source);
    }

    pub fn getHighlights(self: *GrimBuffer, source: []const u8) ![]grove.Highlight {
        const root = self.tree.?.rootNode() orelse return error.NoRoot;
        return grove.Highlight.collectHighlights(
            self.allocator,
            root,
            source,
            self.language,
        );
    }

    pub fn getSymbols(self: *GrimBuffer, source: []const u8) ![]grove.DocumentSymbol {
        const root = self.tree.?.rootNode() orelse return error.NoRoot;
        const lang_enum = self.languageToEnum();
        return self.services.documentSymbols(lang_enum, root, source);
    }

    pub fn getFolding(self: *GrimBuffer) ![]grove.FoldingRange {
        const root = self.tree.?.rootNode() orelse return error.NoRoot;
        const lang_enum = self.languageToEnum();
        return self.services.foldingRanges(lang_enum, root, .{});
    }

    fn languageToEnum(self: *GrimBuffer) grove.Languages.Bundled {
        // Map grove.Language to enum variant
        // Implementation depends on your language detection
        return .zig;  // placeholder
    }
};
```

---

## Performance Monitoring

Track Grove's performance in Grim:

```zig
// 1. Parse timing
const report = try parser.parseUtf8Timed(null, buffer);
defer report.tree.deinit();

grim.metrics.recordParseDuration(report.duration_ns);
grim.metrics.recordParseBytes(report.bytes);

// 2. Throughput calculation
const mb_per_sec = @as(f64, report.bytes) / @as(f64, report.duration_ns) * 1_000_000_000.0 / (1024.0 * 1024.0);
if (mb_per_sec < 10.0) {
    grim.warn("Parsing slower than 10 MB/s target");
}

// 3. Incremental latency
const start = std.time.nanoTimestamp();
// ... apply edit and re-parse ...
const latency_ms = @divTrunc(std.time.nanoTimestamp() - start, 1_000_000);
if (latency_ms > 5) {
    grim.warn("Edit latency exceeds 5ms target");
}
```

---

## Troubleshooting

### Issue: Missing `lib.c` Error

**Solution**: Ensure you're using Grove v0.1.0+, which includes `vendor/tree-sitter` in `build.zig.zon` paths.

### Issue: Slow Parsing

**Diagnosis**: Run `zig build bench` to measure throughput. Target is ≥10 MB/s.

**Solutions**:
- Use `parseChunks()` to avoid buffer copies
- Enable parser pooling for multi-buffer scenarios
- Profile with `zig build -Drelease=fast`

### Issue: High Memory Usage

**Diagnosis**: Profile with Valgrind or Heaptrack.

**Solutions**:
- Use arena allocators for short-lived trees
- Call `tree.deinit()` promptly after use
- Implement tree caching with LRU eviction

### Issue: Missing Highlights

**Diagnosis**: Check if language has `highlights.scm`:

```bash
ls vendor/grammars/<language>/queries/highlights.scm
```

**Solution**: Some grammars may need custom queries. Contribute to Grove!

---

## Contributing to Grove

Grim users can contribute back to Grove:

1. **New Grammars**: Add support for new languages
2. **Query Improvements**: Enhance highlight/symbol queries
3. **Performance**: Optimize hot paths, report benchmarks
4. **Utilities**: Extend `EditorServices` with new features (hover, completion)

See `CLAUDE.md` and `vendor/grammars/README.md` for integration guides.

---

## Version Compatibility

| Grim Version | Grove Version | Tree-sitter ABI |
|--------------|---------------|-----------------|
| 0.1.x | 0.1.0+ | 15 (tree-sitter 0.25.10) |

Always pin Grove to a specific version in `build.zig.zon` for stability.

---

## Resources

- **Grove Repository**: https://github.com/yourusername/grove
- **Tree-sitter Docs**: https://tree-sitter.github.io/tree-sitter/
- **Query Syntax**: https://tree-sitter.github.io/tree-sitter/using-parsers#pattern-matching-with-queries
- **Neovim Tree-sitter**: https://neovim.io/doc/user/treesitter.html (inspiration for Grim)

---

## Next Steps for Grim

1. **Implement Go-to-Definition**: Use `grove.findDefinition()` with symbol extraction
2. **Add Code Actions**: Leverage queries for refactoring (rename, extract function)
3. **LSP Integration**: Use Grove as fallback when LSP unavailable
4. **Multi-Cursor Support**: Apply edits in batch with `grove.EditBuilder`
5. **Tree-sitter Playground**: Debug queries interactively (like nvim-treesitter-playground)

---

**Grove is production-ready for Grim. Happy editing!** ⚡

# Grim Modules Reference for Phantom.Grim

**Quick reference for using grim modules in phantom.grim**

---

## Available Modules

Phantom.grim imports the following modules from grim:

| Module | Import Name | Purpose |
|--------|-------------|---------|
| TestHarness | `test_harness` | Plugin testing framework |
| Runtime | `grim_runtime` | Plugin execution runtime |
| Core | `grim_core` | Editor, Buffer, Rope |
| LSP | `grim_lsp` | Language server protocol client |
| Syntax | `grim_syntax` | Tree-sitter integration (grove) |
| UI-TUI | `grim_ui_tui` | SimpleTUI renderer |

---

## Usage Examples

### 1. TestHarness - Plugin Testing

```zig
const std = @import("std");
const TestHarness = @import("test_harness").TestHarness;

test "my plugin test" {
    const allocator = std.testing.allocator;

    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    // Load plugin
    try harness.loadPlugin("plugins/my-plugin/init.gza");

    // Create buffer
    _ = try harness.createBuffer("test.zig");

    // Simulate input
    try harness.sendKeys("i");
    try harness.sendKeys("hello world");
    try harness.sendKeys("\x1b"); // ESC

    // Assert results
    try harness.assertBufferContent("hello world");
    try harness.assertCursorPosition(0, 11);
}
```

**TestHarness API:**
- `init(allocator)` - Initialize test harness
- `deinit()` - Clean up
- `loadPlugin(path)` - Load Ghostlang plugin
- `createBuffer(name)` - Create new buffer
- `sendKeys(keys)` - Simulate key presses
- `executeCommand(cmd)` - Execute command
- `assertBufferContent(expected)` - Assert buffer matches
- `assertCursorPosition(line, col)` - Assert cursor position
- `assertOutput(expected)` - Assert output matches
- `getOutput()` - Get current output

---

### 2. Runtime - Plugin Execution

```zig
const Runtime = @import("grim_runtime").Runtime;

pub fn loadPlugins(allocator: std.mem.Allocator) !void {
    var runtime = try Runtime.init(allocator);
    defer runtime.deinit();

    // Execute Ghostlang code
    const result = try runtime.executeCode("print('Hello from plugin')");
    defer allocator.free(result);

    // Load plugin module
    try runtime.loadModule("plugins/file-tree/init.gza");

    // Call plugin function
    _ = try runtime.executeCode("file_tree.setup({ width = 30 })");
}
```

**Runtime API:**
- `init(allocator)` - Initialize runtime
- `deinit()` - Clean up
- `executeCode(code)` - Execute Ghostlang code
- `loadModule(path)` - Load .gza module
- `getGlobal(name)` - Get global variable
- `setGlobal(name, value)` - Set global variable

---

### 3. Core - Editor Operations

```zig
const core = @import("grim_core");
const Editor = core.Editor;
const Buffer = core.Buffer;
const Rope = core.Rope;

pub fn createEditor(allocator: std.mem.Allocator) !*Editor {
    var editor = try Editor.init(allocator);

    // Create buffer
    const buffer = try Buffer.init(allocator, "test.zig");
    try editor.addBuffer(buffer);

    // Insert text
    try editor.insertText(0, "const std = @import(\"std\");");

    return editor;
}
```

**Core API:**
- `Editor.init(allocator)` - Create editor instance
- `Buffer.init(allocator, name)` - Create buffer
- `Rope.init(allocator)` - Create rope data structure
- `Editor.insertText(pos, text)` - Insert text
- `Editor.deleteRange(start, end)` - Delete range
- `Editor.undo()` - Undo last operation
- `Editor.redo()` - Redo last undone operation

---

### 4. LSP - Language Server Integration

```zig
const lsp = @import("grim_lsp");
const Client = lsp.Client;

pub fn setupLSP(allocator: std.mem.Allocator) !*Client {
    var client = try Client.init(allocator, "zls");

    // Start LSP server
    try client.start();

    // Send initialize request
    try client.sendInitialize();

    // Open document
    try client.didOpen("test.zig", "const std = @import(\"std\");");

    // Request completion
    const completions = try client.requestCompletion("test.zig", 0, 10);
    defer allocator.free(completions);

    return client;
}
```

**LSP API:**
- `Client.init(allocator, server_name)` - Create LSP client
- `start()` - Start LSP server process
- `sendInitialize()` - Send initialize request
- `didOpen(path, content)` - Notify file opened
- `didChange(path, content)` - Notify file changed
- `requestCompletion(path, line, col)` - Request completions
- `requestHover(path, line, col)` - Request hover info
- `requestDefinition(path, line, col)` - Go to definition
- `requestDiagnostics(path)` - Get diagnostics

---

### 5. Syntax - Tree-sitter Integration

```zig
const syntax = @import("grim_syntax");
const Parser = syntax.Parser;

pub fn highlightCode(allocator: std.mem.Allocator, code: []const u8) ![]syntax.Highlight {
    var parser = try Parser.init(allocator, "zig");
    defer parser.deinit();

    // Parse code
    const tree = try parser.parse(code);
    defer tree.deinit();

    // Get highlights
    const highlights = try parser.getHighlights(tree);

    return highlights;
}
```

**Syntax API:**
- `Parser.init(allocator, language)` - Create parser for language
- `parse(code)` - Parse source code
- `getHighlights(tree)` - Get syntax highlights
- `getFolds(tree)` - Get code folding ranges
- `getIndents(tree)` - Get indentation info

---

### 6. UI-TUI - Terminal UI

```zig
const ui_tui = @import("grim_ui_tui");
const SimpleTUI = ui_tui.SimpleTUI;

pub fn createTUI(allocator: std.mem.Allocator) !*SimpleTUI {
    var tui = try SimpleTUI.init(allocator);

    // Set up rendering
    try tui.setupTerminal();

    // Render loop
    while (tui.running) {
        try tui.render();
        try tui.handleInput();
    }

    return tui;
}
```

**UI-TUI API:**
- `SimpleTUI.init(allocator)` - Create TUI instance
- `setupTerminal()` - Initialize terminal
- `render()` - Render frame
- `handleInput()` - Process input
- `drawText(x, y, text)` - Draw text at position
- `setCursorPos(x, y)` - Set cursor position

---

## Build Configuration

### In build.zig

```zig
const grim = b.dependency("grim", .{
    .target = target,
    .optimize = optimize,
    .@"export-test-harness" = true, // Enable TestHarness
    .ghostlang = true,               // Enable Ghostlang support
});

// Get modules
const test_harness_mod = grim.module("test_harness");
const runtime_mod = grim.module("runtime");
const core_mod = grim.module("core");
const lsp_mod = grim.module("lsp");
const syntax_mod = grim.module("syntax");
const ui_tui_mod = grim.module("ui_tui");

// Add to your module
const mod = b.addModule("phantom_grim", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .imports = &.{
        .{ .name = "test_harness", .module = test_harness_mod },
        .{ .name = "grim_runtime", .module = runtime_mod },
        .{ .name = "grim_core", .module = core_mod },
        .{ .name = "grim_lsp", .module = lsp_mod },
        .{ .name = "grim_syntax", .module = syntax_mod },
        .{ .name = "grim_ui_tui", .module = ui_tui_mod },
    },
});
```

### In build.zig.zon

```zig
.dependencies = .{
    .grim = .{
        .url = "https://github.com/ghostkellz/grim/archive/refs/heads/main.tar.gz",
        .hash = "grim-0.0.0-BbxsAcvPDQA2q5etvZd8olqukrq_pKJ1Rob5hZfnwR9C",
    },
},
```

---

## Common Patterns

### Pattern 1: Plugin Testing

```zig
test "plugin workflow" {
    var harness = try TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // 1. Load plugin
    try harness.loadPlugin("plugins/my-plugin/init.gza");

    // 2. Set up environment
    _ = try harness.createBuffer("test.zig");

    // 3. Execute plugin functionality
    try harness.executeCommand(":MyPluginCommand");

    // 4. Verify results
    try harness.assertOutput("Expected output");
}
```

### Pattern 2: LSP Integration

```zig
const lsp = @import("grim_lsp");

pub fn setupLanguageServer(allocator: std.mem.Allocator, language: []const u8) !*lsp.Client {
    const server_name = if (std.mem.eql(u8, language, "zig"))
        "zls"
    else if (std.mem.eql(u8, language, "rust"))
        "rust-analyzer"
    else
        return error.UnsupportedLanguage;

    var client = try lsp.Client.init(allocator, server_name);
    try client.start();
    try client.sendInitialize();

    return client;
}
```

### Pattern 3: Syntax Highlighting

```zig
const syntax = @import("grim_syntax");

pub fn getHighlights(allocator: std.mem.Allocator, language: []const u8, code: []const u8) ![]syntax.Highlight {
    var parser = try syntax.Parser.init(allocator, language);
    defer parser.deinit();

    const tree = try parser.parse(code);
    defer tree.deinit();

    return try parser.getHighlights(tree);
}
```

### Pattern 4: Editor Operations

```zig
const core = @import("grim_core");

pub fn editFile(allocator: std.mem.Allocator, path: []const u8) !void {
    var editor = try core.Editor.init(allocator);
    defer editor.deinit();

    // Open file
    const buffer = try editor.openFile(path);

    // Edit
    try editor.insertText(0, "// New comment\n");

    // Save
    try editor.saveBuffer(buffer);
}
```

---

## Integration Example

Complete example showing all modules together:

```zig
const std = @import("std");
const TestHarness = @import("test_harness").TestHarness;
const Runtime = @import("grim_runtime").Runtime;
const core = @import("grim_core");
const lsp = @import("grim_lsp");
const syntax = @import("grim_syntax");

test "full integration" {
    const allocator = std.testing.allocator;

    // 1. Set up runtime
    var runtime = try Runtime.init(allocator);
    defer runtime.deinit();

    // 2. Set up LSP
    var lsp_client = try lsp.Client.init(allocator, "zls");
    defer lsp_client.deinit();
    try lsp_client.start();

    // 3. Create editor
    var editor = try core.Editor.init(allocator);
    defer editor.deinit();

    const buffer = try editor.openFile("test.zig");

    // 4. Parse and highlight
    var parser = try syntax.Parser.init(allocator, "zig");
    defer parser.deinit();

    const tree = try parser.parse(buffer.content);
    defer tree.deinit();

    const highlights = try parser.getHighlights(tree);
    defer allocator.free(highlights);

    // 5. Get LSP completions
    try lsp_client.didOpen("test.zig", buffer.content);
    const completions = try lsp_client.requestCompletion("test.zig", 0, 0);
    defer allocator.free(completions);

    // Verify everything works
    try std.testing.expect(highlights.len > 0);
    try std.testing.expect(completions.len > 0);
}
```

---

## Troubleshooting

### Error: Module 'test_harness' not found

**Solution:** Ensure `.@"export-test-harness" = true` is set in build.zig:

```zig
const grim = b.dependency("grim", .{
    .@"export-test-harness" = true,  // ← Must be enabled
});
```

### Error: Hash mismatch

**Solution:** Regenerate the hash:

```bash
cd /data/projects/phantom.grim
zig fetch --save https://github.com/ghostkellz/grim/archive/refs/heads/main.tar.gz
```

### Error: Dependency not found

**Solution:** Run zig fetch first:

```bash
zig fetch
zig build
```

---

## See Also

- [TestHarness Usage Guide](/data/projects/grim/docs/TEST_HARNESS_USAGE.md)
- [PhantomBuffer Guide](/data/projects/grim/PHANTOMBUFFER_CHANGELOG.md)
- [LSP Features](/data/projects/grim/NEW_LSP_FEATURES_v0.3.0.md)
- [Phantom.Grim Architecture](./PHANTOM_GRIM_ARCHITECTURE.md)
- [PGRIM TODO](./PGRIM_TODO.md)

---

**Last Updated:** 2025-10-10
**Grim Version:** main branch
**Status:** Ready to use

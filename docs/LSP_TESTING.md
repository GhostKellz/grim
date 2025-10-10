# LSP Testing Guide

Complete guide for testing Language Server Protocol (LSP) integration in Grim with zls and rust-analyzer.

## LSP Servers Available

### ✅ Installed Servers

```bash
$ which zls
/home/chris/.local/share/nvim/mason/bin/zls

$ which rust-analyzer
/home/chris/.local/share/nvim/mason/bin/rust-analyzer
```

Both servers are installed and ready for testing.

---

## Testing LSP with zls (Zig Language Server)

### Quick Test

1. **Open a Zig file in Grim:**
   ```bash
   ./zig-out/bin/grim src/main.zig
   ```

2. **Verify LSP features:**
   - **Diagnostics:** Look for errors/warnings in the gutter (E/W markers)
   - **Hover:** Press `H` in normal mode over a symbol to see documentation
   - **Go to Definition:** Press `D` in normal mode over a symbol
   - **Completions:** In insert mode, type partial symbol then `Ctrl+Space`

### Test Scenarios for zls

#### 1. **Diagnostics (Error/Warning Detection)**

Create a test file `test_zls_diagnostics.zig`:
```zig
const std = @import("std");

pub fn main() !void {
    const undefined_var = undefined_symbol;  // Error: undefined symbol
    var x: u32 = "string";  // Error: type mismatch

    const unused = 42;  // Warning: unused variable
}
```

**Expected:**
- Gutter shows `E` marker on lines 4-5
- Gutter shows `W` marker on line 7
- Status line displays error/warning counts
- Cursor on error line shows diagnostic message in status bar

#### 2. **Hover Information**

Test file `test_zls_hover.zig`:
```zig
const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn main() !void {
    const result = add(5, 10);
    std.debug.print("{d}\n", .{result});
}
```

**Test:**
- Move cursor to `add` on line 8
- Press `H` (LSP hover command)
- Status bar should show function signature: `fn add(a: i32, b: i32) i32`

#### 3. **Go to Definition**

Use same file as hover test.

**Test:**
- Move cursor to `add` on line 8
- Press `D` (LSP go-to-definition command)
- Cursor should jump to line 3 (function definition)
- Status line: "Jumped to definition"

#### 4. **Auto-completion**

Test file `test_zls_completion.zig`:
```zig
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try list.app  // Trigger completion here
}
```

**Test:**
- In insert mode, type `list.app`
- Press `Ctrl+Space`
- Completion popup should show `append`, `appendSlice`, etc.
- Use arrow keys or Tab to navigate
- Press Enter to accept

**Expected Completion Items:**
- `append`
- `appendSlice`
- `appendAssumeCapacity`
- ...with documentation/details shown

---

## Testing LSP with rust-analyzer

### Quick Test

1. **Create a Rust test file:**
   ```bash
   mkdir -p /tmp/rust_test && cd /tmp/rust_test
   cargo init
   ```

2. **Open in Grim:**
   ```bash
   /data/projects/grim/zig-out/bin/grim src/main.rs
   ```

### Test Scenarios for rust-analyzer

#### 1. **Diagnostics**

Edit `src/main.rs`:
```rust
fn main() {
    let undefined = undefined_var;  // Error: not found
    let x: i32 = "string";  // Error: type mismatch

    let unused = 42;  // Warning: unused variable
    println!("Hello, world!");
}
```

**Expected:**
- Errors on lines 2-3 with `E` markers
- Warning on line 5 with `W` marker
- Diagnostic messages in status bar

#### 2. **Hover**

```rust
fn calculate_sum(a: i32, b: i32) -> i32 {
    a + b
}

fn main() {
    let result = calculate_sum(5, 10);
    println!("Sum: {}", result);
}
```

**Test:**
- Cursor on `calculate_sum` (line 6)
- Press `H`
- Status bar shows: `fn calculate_sum(a: i32, b: i32) -> i32`

#### 3. **Go to Definition**

Same file as hover.

**Test:**
- Cursor on `calculate_sum` (line 6)
- Press `D`
- Jumps to line 1 (function definition)

#### 4. **Completions**

```rust
fn main() {
    let vec = Vec::new();
    vec.pu  // Trigger completion
}
```

**Test:**
- Type `vec.pu` in insert mode
- Press `Ctrl+Space`
- Completion shows `push`, `push_str`, etc.

**Expected Items:**
- `push`
- `pop`
- ...with type information

---

## LSP Integration Architecture

### EditorLSP (`ui-tui/editor_lsp.zig`)

Main LSP client interface:

```zig
pub const EditorLSP = struct {
    allocator: std.mem.Allocator,
    lsp_client: ?*lsp.LSPClient,
    diagnostics: DiagnosticsMap,  // File -> []Diagnostic
    hover_cache: ?[]const u8,
    definition_queue: DefinitionQueue,
    completion_cache: CompletionCache,

    // Key methods
    pub fn openFile(path: []const u8) !void
    pub fn closeFile(path: []const u8) !void
    pub fn notifyBufferChange(path: []const u8) !void
    pub fn requestHover(path: []const u8, line: u32, char: u32) !void
    pub fn requestDefinition(path: []const u8, line: u32, char: u32) !void
    pub fn requestCompletion(path: []const u8, line: u32, char: u32) !void
    pub fn getDiagnostics(path: []const u8) ?[]const Diagnostic
};
```

### SimpleTUI Integration

In `simple_tui.zig`:

```zig
pub const SimpleTUI = struct {
    editor_lsp: ?*editor_lsp_mod.EditorLSP,

    // LSP feature methods
    fn requestLspHover(self: *SimpleTUI) void;
    fn requestLspDefinition(self: *SimpleTUI) void;
    fn triggerCompletionRequest(self: *SimpleTUI) void;
    fn applyPendingDefinition(self: *SimpleTUI) void;
};
```

**Key Bindings:**
- `H` - Hover (normal mode)
- `D` - Go to definition (normal mode)
- `Ctrl+Space` - Trigger completion (insert mode)
- `Ctrl+N` / `Ctrl+P` - Navigate completions
- `Tab` - Next completion
- `Enter` - Accept completion
- `Esc` - Close completion popup

---

## Debugging LSP Issues

### Enable Verbose LSP Logging

In Grim source, LSP client logs to stderr:

```bash
./zig-out/bin/grim test.zig 2>lsp_debug.log
```

Check `lsp_debug.log` for:
- LSP server initialization
- Request/response JSON messages
- Error messages

### Common Issues

#### 1. **No Diagnostics Showing**

**Check:**
- LSP server is running (`ps aux | grep zls`)
- File is saved (some servers only analyze saved files)
- File is in a valid project (has `build.zig` for Zig, `Cargo.toml` for Rust)

**Solution:**
```bash
# For Zig
touch build.zig

# For Rust
cargo init
```

#### 2. **Hover/Definition Not Working**

**Check:**
- Cursor is on a valid symbol
- Symbol is defined in current or imported file
- LSP server has indexed the file

**Test:**
```zig
// Hover should work on 'std' and 'debug'
const std = @import("std");
pub fn main() !void {
    std.debug.print("test\n", .{});
}
```

#### 3. **Completions Not Appearing**

**Check:**
- Completion trigger characters (`.`, `:`, `>` etc.)
- Cursor position (completions only work at valid completion points)
- LSP server is initialized for the file type

**Manual trigger:** Use `Ctrl+Space` to force completion request

#### 4. **Slow Performance**

**Possible causes:**
- Large project (many files)
- LSP server indexing
- Complex type analysis

**Monitor:**
```bash
top -p $(pgrep zls)  # Check zls CPU/memory usage
```

---

## Test Results Template

### zls Testing Results

**Date:** YYYY-MM-DD
**Grim Version:** [commit hash]
**zls Version:** [version]

| Feature | Status | Notes |
|---------|--------|-------|
| Diagnostics (errors) | ⬜ | |
| Diagnostics (warnings) | ⬜ | |
| Hover information | ⬜ | |
| Go to definition | ⬜ | |
| Completions | ⬜ | |
| Completion details | ⬜ | |
| Real-time updates | ⬜ | |

**Issues Found:**
-

**Performance Notes:**
-

### rust-analyzer Testing Results

**Date:** YYYY-MM-DD
**Grim Version:** [commit hash]
**rust-analyzer Version:** [version]

| Feature | Status | Notes |
|---------|--------|-------|
| Diagnostics (errors) | ⬜ | |
| Diagnostics (warnings) | ⬜ | |
| Hover information | ⬜ | |
| Go to definition | ⬜ | |
| Completions | ⬜ | |
| Completion details | ⬜ | |
| Real-time updates | ⬜ | |

**Issues Found:**
-

**Performance Notes:**
-

---

## Expected Behavior Summary

### Diagnostics

**Visual indicators:**
- `E` in gutter for errors (red)
- `W` in gutter for warnings (yellow)
- `I` in gutter for information
- `H` in gutter for hints

**Status bar:**
- Error count displayed
- Current line diagnostic message
- Example: `ERR: undefined symbol 'foo'`

### Hover

**Trigger:** `H` key in normal mode

**Display:** Status bar shows:
- Function signatures
- Type information
- Documentation snippets

**Example:** `fn add(a: i32, b: i32) -> i32`

### Go to Definition

**Trigger:** `D` key in normal mode

**Behavior:**
- Jumps to symbol definition
- Opens file if in different file
- Status message: "Jumped to definition"

### Completions

**Trigger:**
- Auto: Typing after `.` or `:`
- Manual: `Ctrl+Space`

**UI:**
- Popup with up to 4 visible items
- Shows label, detail, documentation
- Navigate with arrows, `Tab`, `Ctrl+N/P`
- Accept with `Enter`, cancel with `Esc`

---

## Next Steps

1. ✅ **Install LSP servers** (zls, rust-analyzer) - DONE
2. ⬜ **Manual testing** - Test all scenarios above
3. ⬜ **Document results** - Fill in test results templates
4. ⬜ **Report issues** - File bugs for any failures
5. ⬜ **Performance testing** - Test with large codebases

---

## References

- **Grim LSP Client:** `/data/projects/grim/lsp/`
- **EditorLSP:** `/data/projects/grim/ui-tui/editor_lsp.zig`
- **SimpleTUI:** `/data/projects/grim/ui-tui/simple_tui.zig`
- **zls Repository:** https://github.com/zigtools/zls
- **rust-analyzer:** https://rust-analyzer.github.io/

---

**Last Updated:** 2025-10-09

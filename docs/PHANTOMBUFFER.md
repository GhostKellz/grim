# PhantomBuffer Integration Guide

## Overview

PhantomBuffer is an enhanced text buffer system for grim that provides native undo/redo functionality and multi-cursor support. It's built on top of grim's rope data structure and integrates seamlessly with the SimpleTUI editor.

## Features

✅ **Implemented**:
- ✅ Manual undo/redo stack (1000 levels)
- ✅ Multi-cursor position tracking
- ✅ Rope-based text buffer
- ✅ Buffer management (PhantomBufferManager)
- ✅ Keybindings (`u` for undo, `Ctrl+R` for redo)
- ✅ File load/save integration
- ✅ Language detection
- ✅ Modified state tracking

🚧 **Planned**:
- Multi-cursor editing in visual block mode
- Cross-buffer undo/redo
- Persistent undo history

## Architecture

```
SimpleTUI
├── Editor (cursor management, rendering)
├── PhantomBufferManager (multi-buffer)
│   └── ManagedBuffer[]
│       └── PhantomBuffer (text, undo/redo, multi-cursor)
│           └── Rope (actual text storage)
```

### Data Flow

**Text Operations**:
1. User types in SimpleTUI
2. SimpleTUI calls `insertCharWithUndo()`
3. Operation routed to PhantomBuffer
4. PhantomBuffer records undo entry
5. PhantomBuffer modifies rope
6. Editor rope synced from PhantomBuffer
7. UI re-renders

**Undo/Redo**:
1. User presses `u` or `Ctrl+R`
2. PhantomBuffer pops from undo/redo stack
3. Inverse operation applied to rope
4. Entry moved to opposite stack
5. Editor rope synced
6. UI re-renders

## File Structure

```
ui-tui/
├── phantom_buffer.zig              # Core buffer with undo/redo
├── phantom_buffer_manager.zig      # Multi-buffer management
├── simple_tui.zig                  # Integration layer
├── phantom_integration_test.zig    # Comprehensive tests
└── phantom_buffer_perf_test.zig    # Performance benchmarks
```

## API Reference

### PhantomBuffer

```zig
pub const PhantomBuffer = struct {
    allocator: std.mem.Allocator,
    id: u32,
    file_path: ?[]const u8,
    language: Language,
    modified: bool,
    rope: core.Rope,
    undo_stack: std.ArrayList(UndoEntry),
    redo_stack: std.ArrayList(UndoEntry),
    cursor_positions: std.ArrayList(CursorPosition),
    config: EditorConfig,
    max_undo_levels: usize = 1000,

    // Initialization
    pub fn init(allocator: std.mem.Allocator, id: u32, options: BufferOptions) !PhantomBuffer
    pub fn deinit(self: *PhantomBuffer) void

    // File operations
    pub fn loadFile(self: *PhantomBuffer, path: []const u8) !void
    pub fn saveFile(self: *PhantomBuffer) !void

    // Text operations (with undo/redo)
    pub fn insertText(self: *PhantomBuffer, position: usize, text: []const u8) !void
    pub fn deleteRange(self: *PhantomBuffer, range: core.Range) !void
    pub fn replaceRange(self: *PhantomBuffer, range: core.Range, text: []const u8) !void

    // Undo/redo
    pub fn undo(self: *PhantomBuffer) !void // error.NothingToUndo
    pub fn redo(self: *PhantomBuffer) !void // error.NothingToRedo

    // Multi-cursor
    pub fn addCursor(self: *PhantomBuffer, position: CursorPosition) !void
    pub fn clearSecondaryCursors(self: *PhantomBuffer) void
    pub fn primaryCursor(self: *const PhantomBuffer) CursorPosition
    pub fn setPrimaryCursor(self: *PhantomBuffer, position: CursorPosition) void

    // Content access
    pub fn getContent(self: *const PhantomBuffer) ![]const u8
    pub fn lineCount(self: *const PhantomBuffer) usize
    pub fn getLine(self: *const PhantomBuffer, line_num: usize) ![]const u8
};
```

### PhantomBufferManager

```zig
pub const PhantomBufferManager = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(ManagedBuffer),
    active_buffer_id: u32,
    next_buffer_id: u32,

    // Initialization
    pub fn init(allocator: std.mem.Allocator) !PhantomBufferManager
    pub fn deinit(self: *PhantomBufferManager) void

    // Buffer access
    pub fn getActiveBuffer(self: *PhantomBufferManager) ?*ManagedBuffer
    pub fn getBuffer(self: *PhantomBufferManager, buffer_id: u32) ?*ManagedBuffer

    // Buffer creation
    pub fn createBuffer(self: *PhantomBufferManager) !u32
    pub fn openFile(self: *PhantomBufferManager, path: []const u8) !u32

    // Buffer lifecycle
    pub fn closeBuffer(self: *PhantomBufferManager, buffer_id: u32) !void
    pub fn saveActiveBuffer(self: *PhantomBufferManager) !void
    pub fn saveBufferAs(self: *PhantomBufferManager, buffer_id: u32, path: []const u8) !void

    // Navigation
    pub fn nextBuffer(self: *PhantomBufferManager) void
    pub fn previousBuffer(self: *PhantomBufferManager) void
    pub fn switchToBuffer(self: *PhantomBufferManager, buffer_id: u32) !void

    // UI integration
    pub fn getTabLine(self: *PhantomBufferManager, allocator: std.mem.Allocator) ![]TabItem
    pub fn getBufferList(self: *PhantomBufferManager, allocator: std.mem.Allocator) ![]BufferInfo

    // State queries
    pub fn getModifiedBuffers(self: *PhantomBufferManager, allocator: std.mem.Allocator) ![]u32
    pub fn hasUnsavedChanges(self: *PhantomBufferManager) bool
};
```

## SimpleTUI Integration

### Feature Flag

PhantomBuffer is controlled by a compile-time flag in `ui-tui/simple_tui.zig`:

```zig
const use_phantom_buffers = true;  // Enable/disable PhantomBuffer
```

### Text Operation Wrappers

SimpleTUI provides wrapper methods that route to PhantomBuffer when enabled:

```zig
// Insert character with undo tracking
fn insertCharWithUndo(self: *SimpleTUI, key: u21) !void

// Delete character with undo tracking
fn deleteCharWithUndo(self: *SimpleTUI) !void

// Backspace with undo tracking
fn backspaceWithUndo(self: *SimpleTUI) !void

// Insert newline with undo tracking
fn insertNewlineAfterWithUndo(self: *SimpleTUI) !void
fn insertNewlineBeforeWithUndo(self: *SimpleTUI) !void

// Sync editor rope from PhantomBuffer
fn syncEditorFromPhantomBuffer(self: *SimpleTUI) !void
```

### Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `u` | Normal | Undo last change |
| `Ctrl+R` | Normal | Redo last undone change |
| `x` | Normal | Delete character (with undo) |
| `o` | Normal | Open line below (with undo) |
| `O` | Normal | Open line above (with undo) |
| All typing | Insert | Insert text (with undo) |
| Backspace | Insert | Delete character (with undo) |

## Implementation Details

### Undo/Redo Stack

PhantomBuffer maintains two stacks:

```zig
const UndoEntry = struct {
    operation: Operation,  // .insert or .delete
    position: usize,      // Byte offset in rope
    content: []const u8,  // Text that was inserted/deleted
};

undo_stack: std.ArrayList(UndoEntry),  // Past operations
redo_stack: std.ArrayList(UndoEntry),  // Undone operations
```

**Undo Algorithm**:
1. Pop entry from undo_stack
2. Apply inverse operation:
   - Insert → Delete at same position
   - Delete → Insert original content
3. Push entry to redo_stack

**Redo Algorithm**:
1. Pop entry from redo_stack
2. Apply original operation
3. Push entry to undo_stack

**Stack Management**:
- New operations clear redo_stack
- Undo stack limited to 1000 entries (configurable)
- Oldest entries removed when limit reached

### Multi-Cursor Support

```zig
pub const CursorPosition = struct {
    line: usize,
    column: usize,
    byte_offset: usize,
    anchor: ?struct {
        line: usize,
        column: usize,
        byte_offset: usize,
    } = null,  // For selections

    pub fn hasSelection(self: *const CursorPosition) bool {
        return self.anchor != null;
    }
};

cursor_positions: std.ArrayList(CursorPosition),
```

**Primary Cursor**: `cursor_positions.items[0]`
**Secondary Cursors**: `cursor_positions.items[1..]`

### Synchronization

The Editor owns its rope for rendering, while PhantomBuffer owns the source of truth. After each PhantomBuffer operation, `syncEditorFromPhantomBuffer()` copies content:

```zig
fn syncEditorFromPhantomBuffer(self: *SimpleTUI) !void {
    // Clear editor's rope
    const old_len = self.editor.rope.len();
    if (old_len > 0) {
        try self.editor.rope.delete(0, old_len);
    }

    // Copy from PhantomBuffer
    const content = try buffer.phantom_buffer.getContent();
    defer self.allocator.free(content);

    if (content.len > 0) {
        try self.editor.rope.insert(0, content);
    }
}
```

## Performance

Performance characteristics (tested with `phantom_buffer_perf_test.zig`):

| Operation | Performance |
|-----------|-------------|
| Insert 10,000 lines | ~50ms |
| 1,000 small edits | ~20ms (~20μs/op) |
| 500 undos | ~5ms (~10μs/undo) |
| 500 redos | ~5ms (~10μs/redo) |

**Memory Usage**:
- Each undo entry stores: operation type + position + content copy
- 1000 undo entries ≈ size of original content
- Rope structure: O(log n) insertion/deletion

## Testing

### Unit Tests

All PhantomBuffer tests are in `ui-tui/phantom_buffer.zig`:
- Basic insert/delete operations
- Undo/redo cycles
- Multi-cursor management

### Integration Tests

`ui-tui/phantom_integration_test.zig` contains:
- Text editing with undo/redo
- Delete with undo
- Replace range operations
- Multi-cursor positions
- File load/save
- Buffer manager operations
- Undo stack limits
- Redo cleared on new operations

Run tests:
```bash
zig build test --summary all
```

### Performance Tests

Run performance benchmarks:
```bash
zig build-exe ui-tui/phantom_buffer_perf_test.zig --dep core -Mcore=core/mod.zig
./phantom_buffer_perf_test
```

## Migration from BufferManager

PhantomBufferManager is a drop-in replacement for BufferManager:

**Before**:
```zig
var buffer_mgr = try BufferManager.init(allocator);
const buffer = buffer_mgr.getActiveBuffer().?;
try buffer.rope.insert(0, "text");
```

**After**:
```zig
var phantom_mgr = try PhantomBufferManager.init(allocator);
const buffer = phantom_mgr.getActiveBuffer().?;
try buffer.phantom_buffer.insertText(0, "text");  // With undo!
```

## Configuration

### Editor Config

PhantomBuffer supports per-buffer editor configuration:

```zig
pub const EditorConfig = struct {
    show_line_numbers: bool = true,
    relative_line_numbers: bool = false,
    tab_size: usize = 4,
    use_spaces: bool = true,
    enable_ligatures: bool = true,
    auto_indent: bool = true,
    highlight_matching_brackets: bool = true,
    line_wrap: bool = false,
    cursor_line_highlight: bool = true,
    minimap_enabled: bool = false,
    diagnostics_enabled: bool = true,
};
```

### Language Detection

Automatic language detection from file extension:

- `.zig` → Zig
- `.rs` → Rust
- `.go` → Go
- `.js` → JavaScript
- `.ts` → TypeScript
- `.py` → Python
- `.c` → C
- `.cpp/.cc/.cxx` → C++
- `.md` → Markdown
- `.json` → JSON
- `.html` → HTML
- `.css` → CSS
- `.gza` → GhostLang

## Troubleshooting

### Undo not working

**Problem**: Pressing `u` shows "Undo not available"

**Solution**: Ensure `use_phantom_buffers = true` in `simple_tui.zig`

### Memory usage growing

**Problem**: Undo history consuming too much memory

**Solution**: Adjust `max_undo_levels`:
```zig
buffer.max_undo_levels = 500;  // Reduce from default 1000
```

### Slow performance with large files

**Problem**: Operations slow with 100k+ line files

**Solution**:
- Rope structure handles large files well
- If issues persist, disable undo for bulk operations
- Consider streaming large file loading

## Future Enhancements

### Planned Features

1. **Visual Block Multi-Cursor** (Task 3.3)
   - Wire PhantomBuffer multi-cursor to Vim visual block mode
   - Enable simultaneous editing at multiple positions

2. **Persistent Undo**
   - Save undo history to `.grim-undo` files
   - Restore undo history on file reopen

3. **Cross-Buffer Undo**
   - Global undo/redo across all buffers
   - Timeline-based undo tree

4. **Diff-Based Undo**
   - Store diffs instead of full content
   - Reduce memory usage for large deletions

5. **Undo Grouping**
   - Group related operations (e.g., word typing)
   - Single undo for logical edit unit

## References

- **Core Rope Implementation**: `core/rope.zig`
- **Editor Integration**: `ui-tui/editor.zig`
- **SimpleTUI**: `ui-tui/simple_tui.zig`
- **LSP Integration**: `ui-tui/editor_lsp.zig`

## License

PhantomBuffer is part of grim, licensed under the same terms as the main project.

---

**Status**: ✅ Fully Implemented and Tested
**Version**: 1.0.0
**Last Updated**: 2025-10-10

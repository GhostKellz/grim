# PhantomBuffer Migration Plan

## Overview

This document outlines the migration plan for switching SimpleTUI from the current `Editor` implementation to `PhantomBuffer`, which provides significant built-in capabilities that would simplify the codebase and enhance performance.

## Current Architecture

**BufferManager.Buffer** (ui-tui/buffer_manager.zig:14-68):
```zig
pub const Buffer = struct {
    id: u32,
    editor: editor_mod.Editor,  // ← Current editor
    file_path: ?[]const u8 = null,
    modified: bool = false,
    display_name: []const u8,
    last_accessed: i64,
    // ...
};
```

**SimpleTUI** interacts with BufferManager to get Buffers, then accesses the `editor` field to perform editing operations using the `Editor` API (rope-based, manual cursor management, no undo/redo).

## PhantomBuffer Advantages

### 1. Built-in Undo/Redo Stack
**Current:** Editor has no undo/redo support. Implementing it requires:
- Creating an UndoStack structure
- Recording before/after states for every edit
- Managing undo/redo traversal
- Memory management for history

**With PhantomBuffer:**
```zig
pub fn undo(self: *PhantomBuffer) !void {
    if (self.phantom_editor) |editor| {
        try editor.undo();  // ✅ Built-in!
    }
}

pub fn redo(self: *PhantomBuffer) !void {
    if (self.phantom_editor) |editor| {
        try editor.redo();  // ✅ Built-in!
    }
}
```

### 2. Native Multi-Cursor Support
**Current:** Editor has basic multi-cursor fields but incomplete implementation.

**With PhantomBuffer:**
```zig
pub fn addCursor(self: *PhantomBuffer, position: CursorPosition) !void
pub fn clearSecondaryCursors(self: *PhantomBuffer) void
pub fn primaryCursor(self: *const PhantomBuffer) CursorPosition
pub fn setPrimaryCursor(self: *PhantomBuffer, position: CursorPosition) void
```

### 3. LSP Diagnostic Markers
**Current:** Diagnostics are stored in EditorLSP, rendered separately in SimpleTUI.

**With PhantomBuffer:**
```zig
pub fn addDiagnostic(
    self: *PhantomBuffer,
    line: usize,
    column: usize,
    severity: DiagnosticSeverity,
    message: []const u8
) !void

pub fn clearDiagnostics(self: *PhantomBuffer) void
```
Phantom TextEditor handles rendering diagnostic squiggles/markers automatically.

### 4. High Performance
PhantomBuffer uses Phantom v0.5.0 TextEditor widget, which is optimized for:
- Large files (millions of lines)
- Incremental rendering
- Efficient rope operations
- GPU-accelerated text rendering (when available)

### 5. Rope Fallback
PhantomBuffer gracefully falls back to rope-based implementation when Phantom TextEditor is unavailable, ensuring compatibility.

## Migration Strategy

### Phase 1: Create PhantomBufferManager

Create a new `PhantomBufferManager` alongside `BufferManager`:

```zig
// ui-tui/phantom_buffer_manager.zig
pub const PhantomBufferManager = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(ManagedBuffer),
    active_buffer_id: u32 = 0,
    next_buffer_id: u32 = 1,

    pub const ManagedBuffer = struct {
        id: u32,
        phantom_buffer: phantom_buffer_mod.PhantomBuffer,  // ← PhantomBuffer
        display_name: []const u8,
        last_accessed: i64,

        // PhantomBuffer already tracks file_path and modified state
        pub fn filePath(self: *const ManagedBuffer) ?[]const u8 {
            return self.phantom_buffer.file_path;
        }

        pub fn isModified(self: *const ManagedBuffer) bool {
            return self.phantom_buffer.modified;
        }
    };

    // Same API as BufferManager:
    pub fn init(allocator: std.mem.Allocator) !PhantomBufferManager
    pub fn deinit(self: *PhantomBufferManager) void
    pub fn getActiveBuffer(self: *PhantomBufferManager) ?*ManagedBuffer
    pub fn createBuffer(self: *PhantomBufferManager) !u32
    pub fn openFile(self: *PhantomBufferManager, path: []const u8) !u32
    pub fn saveActiveBuffer(self: *PhantomBufferManager) !void
    pub fn closeBuffer(self: *PhantomBufferManager, buffer_id: u32) !void
    pub fn nextBuffer(self: *PhantomBufferManager) void
    pub fn previousBuffer(self: *PhantomBufferManager) void
    // ... etc
};
```

### Phase 2: Update SimpleTUI API Calls

Replace Editor-specific calls with PhantomBuffer API:

**Editor API → PhantomBuffer API mapping:**
```zig
// Insertions
editor.rope.insert(offset, text)
    → buffer.insertText(offset, text)

// Deletions
editor.rope.delete(offset, len)
    → buffer.deleteRange(.{ .start = offset, .end = offset + len })

// File operations
editor.loadFile(path)
    → buffer.loadFile(path)

editor.saveFile(path)
    → buffer.saveFile()  // PhantomBuffer tracks path internally

// Cursor (major change - Editor uses byte offsets, PhantomBuffer uses line/col)
editor.cursor.offset
    → buffer.primaryCursor().byte_offset

// NEW: Undo/Redo
// No Editor equivalent
buffer.undo()
buffer.redo()

// NEW: Multi-cursor
// No Editor equivalent
buffer.addCursor(position)
buffer.clearSecondaryCursors()
```

### Phase 3: Cursor Position Conversion

**Challenge:** Editor uses byte offsets, PhantomBuffer uses line/column positions.

**Solution:** Implement conversion helpers:
```zig
fn offsetToLineCol(rope: *core.Rope, offset: usize) struct { line: usize, col: usize } {
    const content = rope.slice(.{ .start = 0, .end = offset }) catch return .{ .line = 0, .col = 0 };
    defer rope.allocator.free(content);

    var line: usize = 0;
    var col: usize = 0;
    for (content) |ch| {
        if (ch == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
    }
    return .{ .line = line, .col = col };
}
```

Or leverage PhantomBuffer's internal tracking (preferred).

### Phase 4: Enable New Features

Once migration is complete, enable:

1. **Undo/Redo Keybindings** (Task 3.2):
   ```zig
   'u' => {  // Normal mode
       const buffer = self.phantom_buffer_manager.getActiveBuffer() orelse return;
       buffer.phantom_buffer.undo() catch |err| {
           self.setStatusMessage("Cannot undo");
       };
   },
   18 => {  // Ctrl+R
       const buffer = self.phantom_buffer_manager.getActiveBuffer() orelse return;
       buffer.phantom_buffer.redo() catch |err| {
           self.setStatusMessage("Cannot redo");
       };
   },
   ```

2. **Multi-Cursor Visual Block Mode** (Task 3.3):
   - Wire visual block mode selections to `buffer.addCursor()`
   - Enable simultaneous editing with all cursors

3. **LSP Diagnostic Markers** (automatic with PhantomBuffer):
   ```zig
   fn onDiagnosticsReceived(diagnostics: []Diagnostic) void {
       const buffer = self.phantom_buffer_manager.getActiveBuffer().?;
       buffer.phantom_buffer.clearDiagnostics();

       for (diagnostics) |diag| {
           buffer.phantom_buffer.addDiagnostic(
               diag.range.start.line,
               diag.range.start.character,
               diag.severity,
               diag.message
           ) catch continue;
       }
   }
   ```

## Benefits Summary

### Code Reduction
- **Remove:** Manual undo/redo stack implementation (~200-300 lines)
- **Remove:** Complex multi-cursor state management
- **Remove:** Manual diagnostic tracking in EditorLSP
- **Simplify:** Cursor position tracking (PhantomBuffer handles it)

### Feature Gains
- ✅ Undo/Redo with unlimited history
- ✅ Multi-cursor editing
- ✅ Visual diagnostic markers (squiggles, margin icons)
- ✅ Better performance with large files
- ✅ Code folding (Phantom TextEditor built-in)
- ✅ Minimap support (optional)

### Performance
PhantomBuffer + Phantom TextEditor provides:
- Incremental rendering (only render visible lines)
- GPU acceleration (when available)
- Optimized rope operations
- Lower memory usage for large files

## Compatibility Note

PhantomBuffer has a **rope fallback mode** (ui-tui/phantom_buffer.zig:96-100):
```zig
var phantom_editor: ?*phantom.TextEditor = null;
if (options.use_phantom) {
    phantom_editor = initPhantomEditor(allocator, options.config) catch |err| blk: {
        std.log.warn("Failed to initialize Phantom TextEditor (falling back to rope): {}", .{err});
        break :blk null;
    };
}
```

This ensures the editor works even if Phantom v0.5.0 is unavailable.

## Testing Strategy

1. **Unit Tests:** Create tests for PhantomBufferManager matching BufferManager's test coverage
2. **Integration Tests:** Test SimpleTUI with PhantomBufferManager using rope fallback
3. **Performance Tests:** Compare Editor vs PhantomBuffer on large files (1M+ lines)
4. **Feature Tests:** Verify undo/redo, multi-cursor, diagnostics work correctly

## Timeline Estimate

- Phase 1 (PhantomBufferManager): **2-3 hours**
- Phase 2 (SimpleTUI API updates): **4-6 hours**
- Phase 3 (Cursor conversion): **1-2 hours**
- Phase 4 (Enable new features): **2-3 hours**
- Testing & debugging: **3-5 hours**

**Total: ~12-19 hours** for complete migration

## Risks & Mitigation

### Risk 1: Breaking Existing Functionality
**Mitigation:** Keep BufferManager alongside PhantomBufferManager during transition. Add a `--use-phantom` flag to SimpleTUI to switch between implementations.

### Risk 2: Phantom v0.5.0 Availability
**Mitigation:** PhantomBuffer already has rope fallback. All features work in fallback mode except undo/redo (returns error).

### Risk 3: Performance Regression
**Mitigation:** Run benchmarks before and after migration. The fallback rope mode should perform similarly to current Editor.

## Next Steps

When ready to proceed with migration:

1. Create `ui-tui/phantom_buffer_manager.zig`
2. Add compile-time flag to SimpleTUI: `use_phantom_buffers: bool = false`
3. Implement PhantomBufferManager with identical API to BufferManager
4. Add tests
5. Update SimpleTUI to use PhantomBufferManager when flag enabled
6. Test thoroughly
7. Enable by default
8. Remove old BufferManager once stable

## Related Files

- `/data/projects/grim/ui-tui/phantom_buffer.zig` - PhantomBuffer implementation
- `/data/projects/grim/ui-tui/buffer_manager.zig` - Current BufferManager
- `/data/projects/grim/ui-tui/editor.zig` - Current Editor (to be replaced)
- `/data/projects/grim/ui-tui/simple_tui.zig` - Main TUI (needs API updates)

## References

- Phantom v0.5.0 TextEditor API documentation
- PhantomTUI integration examples
- grim editor architecture docs

---

**Status:** Not yet implemented
**Priority:** Medium-High (unlocks undo/redo, multi-cursor, better performance)
**Estimated Effort:** 2-3 days of focused development
**Author:** Claude Code
**Date:** 2025-10-10

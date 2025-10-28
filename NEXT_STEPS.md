# Grim - Next 10 Priority Items

**Date:** 2025-10-27
**Current Status:** Platform foundation complete, Editor polish needed
**Focus:** Make Grim production-ready for daily use

---

## 🔥 TOP 10 PRIORITIES (Ranked by Impact)

### 1. Undo/Redo Implementation ⚡ **CRITICAL**
**Status:** Not implemented
**Impact:** Can't fix mistakes - editor is unusable for real work
**Effort:** 8-10 hours

**Current State:**
- No undo/redo stack
- `u` and `Ctrl+R` keybindings don't exist

**Implementation:**
```zig
// core/undo.zig
pub const UndoStack = struct {
    snapshots: std.ArrayList(Snapshot),
    current_index: usize,

    const Snapshot = struct {
        content: []const u8,
        cursor_offset: usize,
        timestamp: i64,
    };

    pub fn recordUndo(self: *UndoStack, rope: *Rope, cursor: usize) !void;
    pub fn undo(self: *UndoStack) ?Snapshot;
    pub fn redo(self: *UndoStack) ?Snapshot;
};
```

**Files to modify:**
- `core/undo.zig` (new)
- `ui-tui/editor.zig` (integrate undo stack)
- `ui-tui/grim_editor_widget.zig` (call recordUndo on edits)
- `ui-tui/grim_app.zig` (wire up `u` and `Ctrl+R` keys)

**Acceptance Criteria:**
- [ ] `u` undoes last change
- [ ] `Ctrl+R` redoes undone change
- [ ] Undo stack limits to 1000 entries
- [ ] Cursor position restored on undo/redo

---

### 2. Search Highlighting & `n`/`N` Navigation ⚡ **HIGH**
**Status:** Search works but no visual feedback
**Impact:** Can't see matches, hard to navigate results
**Effort:** 6-8 hours

**Current State:**
- `/` and `?` search work
- No highlighting of matches
- No `n`/`N` to jump to next/previous

**Implementation:**
```zig
// ui-tui/editor.zig
pub const Editor = struct {
    search_pattern: ?[]const u8,
    search_matches: std.ArrayList(usize), // All match offsets
    current_match_index: ?usize,

    pub fn search(self: *Editor, pattern: []const u8) !void;
    pub fn highlightMatches(self: *Editor) void;
    pub fn nextMatch(self: *Editor) void;
    pub fn previousMatch(self: *Editor) void;
};
```

**Files to modify:**
- `ui-tui/editor.zig` (add search state + methods)
- `ui-tui/grim_editor_widget.zig` (render highlights)
- `ui-tui/grim_app.zig` (wire up `n` and `N` keys)

**Acceptance Criteria:**
- [ ] All matches highlighted with yellow background
- [ ] Current match has different color
- [ ] `n` jumps to next match
- [ ] `N` jumps to previous match
- [ ] Status line shows "5/23 matches"

---

### 3. File Save Confirmation & Quit Warnings ⚡ **HIGH**
**Status:** Minimal feedback
**Impact:** Don't know if save succeeded, can lose work
**Effort:** 2-3 hours

**Current State:**
- `:w` saves silently
- `:q` quits without checking unsaved changes
- No error messages

**Implementation:**
```zig
// ui-tui/grim_app.zig
fn executeCommand(self: *GrimApp, cmd: []const u8) !void {
    if (std.mem.eql(u8, cmd, "w")) {
        try self.saveCurrentBuffer();
        // Show: "test.zig" 42L, 1337B written
        const info = try std.fmt.allocPrint(
            self.allocator,
            "\"{s}\" {d}L, {d}B written",
            .{ filename, line_count, byte_count }
        );
        self.showMessage(info);
    } else if (std.mem.eql(u8, cmd, "q")) {
        if (self.hasUnsavedChanges()) {
            self.showError("No write since last change (add ! to override)");
            return error.UnsavedChanges;
        }
        self.quit();
    }
}
```

**Files to modify:**
- `ui-tui/grim_app.zig` (executeCommand)
- `ui-tui/grim_editor_widget.zig` (track modified state)

**Acceptance Criteria:**
- [ ] `:w` shows "file.txt" 42L, 1337B written
- [ ] `:q` warns if unsaved changes
- [ ] `:q!` force quits
- [ ] `:wq` saves and quits
- [ ] `:e!` reloads file (discard changes)

---

### 4. Complete Wayland Backend Integration 🎨 **MEDIUM**
**Status:** Foundation exists, needs integration
**Impact:** Native Wayland support for better performance
**Effort:** 12-16 hours

**Current State:**
- `wayland_backend.zig` has client setup
- Not integrated into main app
- DMA-BUF and fractional scaling detected but unused

**Implementation:**
```zig
// ui-tui/grim_app.zig
pub fn init(allocator: Allocator, config: Config) !*GrimApp {
    // Detect platform
    var caps = try core.PlatformCapabilities.detect(allocator);

    // Choose backend
    const backend = if (caps.has_wayland and config.prefer_wayland)
        try WaylandBackend.init(allocator)
    else
        try TerminalBackend.init(allocator);

    // Use DMA-BUF if available
    if (backend.hasDmaBuf()) {
        try backend.enableZeroCopy();
    }
}
```

**Files to modify:**
- `ui-tui/wayland_backend.zig` (complete render() method)
- `ui-tui/grim_app.zig` (integrate backend selection)
- `src/main.zig` (add --wayland flag)

**Acceptance Criteria:**
- [ ] `grim --wayland` uses Wayland backend
- [ ] DMA-BUF zero-copy rendering if available
- [ ] Fractional scaling works on HiDPI displays
- [ ] Falls back to terminal if Wayland unavailable

---

### 5. Mouse Support (Click & Scroll) 🖱️ **MEDIUM**
**Status:** Not implemented
**Impact:** Modern editor expectation, especially in tmux
**Effort:** 8-12 hours

**Current State:**
- Keyboard-only navigation
- No mouse input handling

**Implementation:**
```zig
// ui-tui/grim_app.zig
fn handleMouseEvent(self: *GrimApp, event: phantom.MouseEvent) !void {
    switch (event.type) {
        .press => {
            // Click to position cursor
            const pos = self.screenToBufferPos(event.x, event.y);
            self.editor.cursor.offset = pos;
        },
        .scroll_up => {
            try self.editor.scrollUp(3);
        },
        .scroll_down => {
            try self.editor.scrollDown(3);
        },
        .drag => {
            // Select text
            self.enterVisualMode();
            self.updateSelection(event.x, event.y);
        },
    }
}
```

**Files to modify:**
- `ui-tui/grim_app.zig` (add mouse handlers)
- `ui-tui/phantom_app.zig` (enable mouse mode)

**Acceptance Criteria:**
- [ ] Click positions cursor
- [ ] Scroll wheel scrolls viewport
- [ ] Drag selects text (enters visual mode)
- [ ] Works in tmux with mouse mode enabled

---

### 6. Update wzl Dependency (Thread-Safe Version) ⚡ **HIGH**
**Status:** Using older version
**Impact:** Missing thread safety improvements
**Effort:** 1-2 hours

**wzl Updates (from latest commit):**
- ✅ Thread safety: 3 mutexes in client.zig
- ✅ Thread safety: 3 mutexes in server.zig
- ✅ 176+ tests passing with zero memory leaks
- ✅ Lock ordering documented

**Implementation:**
```bash
cd /data/projects/grim
zig fetch --save https://github.com/ghostkellz/wzl/archive/refs/heads/main.tar.gz
zig build
```

**Files to modify:**
- `build.zig.zon` (update wzl hash)

**Acceptance Criteria:**
- [ ] wzl updated to latest commit (b7da66c)
- [ ] All tests still pass
- [ ] No regressions in Wayland backend

---

### 7. SIMD UTF-8 Validation (AVX-512) 🚀 **MEDIUM**
**Status:** Platform detection ready
**Impact:** 10-20x faster text validation
**Effort:** 10-14 hours

**Current State:**
- Platform detection identifies AVX-512 support
- No SIMD implementation yet

**Implementation:**
```zig
// core/simd.zig
pub fn validateUtf8(bytes: []const u8) bool {
    if (comptime std.Target.x86.featureSetHas(
        std.Target.current.cpu.features,
        .avx512f
    )) {
        return validateUtf8Avx512(bytes);
    }
    return validateUtf8Scalar(bytes);
}

fn validateUtf8Avx512(bytes: []const u8) bool {
    // Use AVX-512 intrinsics
    // Process 64 bytes at a time
    // Check UTF-8 continuation bytes
    // Return validation result
}
```

**Files to modify:**
- `core/simd.zig` (new)
- `core/rope.zig` (use SIMD validation)

**Acceptance Criteria:**
- [ ] 10-20 GB/s throughput on AVX-512
- [ ] Falls back to scalar on older CPUs
- [ ] All UTF-8 edge cases handled

---

### 8. Tab Bar & Buffer Switcher UI 📑 **MEDIUM**
**Status:** Tab commands work, no visual tab bar
**Impact:** Hard to track open buffers
**Effort:** 4-6 hours

**Current State:**
- `:tabnew`, `:tabn`, `:tabp` work
- No visual indication of tabs
- No tab bar at top

**Implementation:**
```zig
// ui-tui/tab_bar.zig
pub const TabBar = struct {
    tabs: std.ArrayList(Tab),
    active_index: usize,

    pub fn render(self: *TabBar, buffer: *Buffer, area: Rect) void {
        // Render tabs like: [1:main.zig] [2:test.zig*] [3:foo.zig]
        // Active tab highlighted
        // Modified indicator (*)
    }
};
```

**Files to modify:**
- `ui-tui/tab_bar.zig` (new)
- `ui-tui/grim_layout.zig` (integrate tab bar)
- `ui-tui/grim_app.zig` (update on tab changes)

**Acceptance Criteria:**
- [ ] Tab bar shows all open buffers
- [ ] Active tab highlighted
- [ ] Modified indicator shows `*`
- [ ] Click tab to switch (if mouse enabled)

---

### 9. Macro Recording (`q`/`@`) 🎬 **LOW**
**Status:** Stubbed but incomplete
**Impact:** Power user feature, not critical
**Effort:** 8-10 hours

**Current State:**
- `q` keybinding exists
- No actual recording implementation

**Implementation:**
```zig
// ui-tui/editor.zig
pub const Editor = struct {
    recording_macro: ?u8, // Register name (a-z)
    macro_buffer: std.ArrayList(Key),
    macros: std.StringHashMap([]Key),

    pub fn startRecording(self: *Editor, register: u8) !void;
    pub fn stopRecording(self: *Editor) !void;
    pub fn playMacro(self: *Editor, register: u8) !void;
};
```

**Files to modify:**
- `ui-tui/editor.zig` (macro storage)
- `ui-tui/grim_app.zig` (record keys during macro)

**Acceptance Criteria:**
- [ ] `qa` starts recording to register `a`
- [ ] `q` stops recording
- [ ] `@a` plays macro from register `a`
- [ ] `@@` repeats last macro

---

### 10. io_uring Async File I/O 🚀 **LOW**
**Status:** Platform detection ready
**Impact:** Faster large file loading
**Effort:** 10-14 hours

**Current State:**
- Platform detection confirms io_uring available
- Synchronous file I/O currently

**Implementation:**
```zig
// core/io_uring.zig
pub const IoUring = struct {
    ring: std.os.linux.IoUring,

    pub fn init(entries: u32) !IoUring;
    pub fn readFileAsync(self: *IoUring, fd: i32, buffer: []u8) !void;
    pub fn submitAndWait(self: *IoUring, min_complete: u32) !void;
};
```

**Files to modify:**
- `core/io_uring.zig` (new)
- `core/rope.zig` (use async I/O for large files)
- `ui-tui/grim_app.zig` (async file loading)

**Acceptance Criteria:**
- [ ] Large files (100MB+) load 2-5x faster
- [ ] Zero syscall overhead (batched submissions)
- [ ] Falls back to sync I/O if io_uring unavailable

---

## 📊 Priority Summary

### Must Have for BETA (Items 1-3)
1. ✅ Undo/Redo - **CRITICAL**
2. ✅ Search highlighting + n/N - **HIGH**
3. ✅ File save feedback - **HIGH**

**Total Effort:** 16-21 hours
**Impact:** Editor becomes usable for daily work

### Should Have for BETA (Items 4-6)
4. Wayland integration - **MEDIUM**
5. Mouse support - **MEDIUM**
6. Update wzl - **HIGH** (quick win!)

**Total Effort:** 21-30 hours
**Impact:** Modern editor experience

### Nice to Have (Items 7-10)
7. SIMD UTF-8 - **MEDIUM** (performance)
8. Tab bar UI - **MEDIUM** (UX)
9. Macros - **LOW** (power users)
10. io_uring - **LOW** (large files)

**Total Effort:** 32-44 hours
**Impact:** Performance and power user features

---

## 🎯 Recommended Order

### Week 1: Core Editor (Must Have)
**Days 1-2:** Implement undo/redo
**Days 3-4:** Search highlighting + n/N navigation
**Day 5:** File save confirmation + quit warnings

**Result:** Editor is usable for daily work

### Week 2: Modern Features (Should Have)
**Day 1:** Update wzl dependency (quick win!)
**Days 2-4:** Wayland backend integration
**Days 4-5:** Mouse support

**Result:** Modern, polished editor experience

### Week 3+: Performance & Polish (Nice to Have)
- SIMD UTF-8 validation
- Tab bar UI
- Macro recording
- io_uring async I/O

**Result:** Production-ready, high-performance editor

---

## ✅ Already Complete (Previous Work)

- ✅ Platform detection (Wayland, GPU, CPU features)
- ✅ tmux integration (OSC 52 clipboard)
- ✅ Wayland backend foundation
- ✅ Terminal resize handling
- ✅ Viewport scrolling
- ✅ Visual mode operations (d/y/c/>/‹)
- ✅ Vim motions (f/F/t/T, ;/,)
- ✅ LSP integration (completion, hover, diagnostics)
- ✅ Syntax highlighting
- ✅ Powerline status bar
- ✅ Command line interface

---

## 🔄 Quick Wins (< 2 hours each)

1. **Update wzl** - 1 hour
2. **Add `:wq` command** - 30 minutes
3. **Show save confirmation** - 1 hour
4. **Add `:q!` force quit** - 30 minutes
5. **Wire up existing `n`/`N` keys** - 1 hour

**Total:** 4 hours for 5 improvements!

---

**Next Action:** Start with Item #1 (Undo/Redo) - Most critical for usability!

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const runtime = @import("runtime");

/// PhantomTUI v0.5.0 Buffer Integration
/// Wraps PhantomTUI's TextEditor widget with grim's buffer management
pub const PhantomBuffer = struct {
    allocator: std.mem.Allocator,
    id: u32,
    file_path: ?[]const u8 = null,
    language: Language = .unknown,
    modified: bool = false,

    // PhantomTUI components (placeholder types for now)
    // These would be actual phantom types when phantom is available
    editor_config: EditorConfig,

    // Rope buffer (fallback when phantom TextEditor not available)
    rope: core.Rope,

    // Editor state
    cursor_positions: std.ArrayList(CursorPosition),
    selection: ?Selection = null,
    undo_stack: std.ArrayList(UndoEntry),
    redo_stack: std.ArrayList(UndoEntry),

    pub const Language = enum {
        unknown,
        zig,
        rust,
        go,
        javascript,
        typescript,
        python,
        c,
        cpp,
        markdown,
        json,
        html,
        css,
        ghostlang,
    };

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

    pub const CursorPosition = struct {
        line: usize,
        column: usize,
        byte_offset: usize,
        anchor: ?struct {
            line: usize,
            column: usize,
            byte_offset: usize,
        } = null,

        pub fn hasSelection(self: *const CursorPosition) bool {
            return self.anchor != null;
        }
    };

    pub const Selection = struct {
        start: usize,
        end: usize,
        mode: SelectionMode,

        pub const SelectionMode = enum {
            char_wise,
            line_wise,
            block_wise,
        };
    };

    pub const UndoEntry = struct {
        operation: Operation,
        timestamp: i64,

        pub const Operation = union(enum) {
            insert: struct { position: usize, text: []const u8 },
            delete: struct { position: usize, text: []const u8 },
            replace: struct { range: core.Range, old_text: []const u8, new_text: []const u8 },
        };
    };

    pub const BufferOptions = struct {
        config: EditorConfig = .{},
        initial_content: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator, id: u32, options: BufferOptions) !PhantomBuffer {
        var rope = try core.Rope.init(allocator);
        errdefer rope.deinit();

        if (options.initial_content) |content| {
            try rope.insert(0, content);
        }

        var cursor_positions = std.ArrayList(CursorPosition).init(allocator);
        errdefer cursor_positions.deinit();

        // Initialize with one cursor at (0, 0)
        try cursor_positions.append(.{ .line = 0, .column = 0, .byte_offset = 0 });

        return PhantomBuffer{
            .allocator = allocator,
            .id = id,
            .editor_config = options.config,
            .rope = rope,
            .cursor_positions = cursor_positions,
            .undo_stack = std.ArrayList(UndoEntry).init(allocator),
            .redo_stack = std.ArrayList(UndoEntry).init(allocator),
        };
    }

    pub fn deinit(self: *PhantomBuffer) void {
        self.rope.deinit();
        self.cursor_positions.deinit();

        for (self.undo_stack.items) |*entry| {
            self.freeUndoEntry(entry);
        }
        self.undo_stack.deinit();

        for (self.redo_stack.items) |*entry| {
            self.freeUndoEntry(entry);
        }
        self.redo_stack.deinit();

        if (self.file_path) |path| {
            self.allocator.free(path);
        }
    }

    /// Load file into buffer
    pub fn loadFile(self: *PhantomBuffer, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 100 * 1024 * 1024); // 100MB max
        defer self.allocator.free(content);

        // Clear existing content
        const len = self.rope.len();
        if (len > 0) {
            try self.rope.delete(0, len);
        }

        // Insert new content
        try self.rope.insert(0, content);

        // Set file path
        if (self.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.file_path = try self.allocator.dupe(u8, path);

        // Detect language
        self.language = detectLanguage(path);

        self.modified = false;
    }

    /// Save buffer to file
    pub fn saveFile(self: *PhantomBuffer) !void {
        const path = self.file_path orelse return error.NoFilePath;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const content = try self.rope.copyRangeAlloc(self.allocator, .{ .start = 0, .end = self.rope.len() });
        defer self.allocator.free(content);

        try file.writeAll(content);

        self.modified = false;
    }

    /// Insert text at position
    pub fn insertText(self: *PhantomBuffer, position: usize, text: []const u8) !void {
        // Record for undo
        try self.recordUndo(.{ .insert = .{ .position = position, .text = try self.allocator.dupe(u8, text) } });

        try self.rope.insert(position, text);
        self.modified = true;

        // Clear redo stack
        self.clearRedo();
    }

    /// Delete range
    pub fn deleteRange(self: *PhantomBuffer, range: core.Range) !void {
        const deleted_text = try self.rope.copyRangeAlloc(self.allocator, range);

        // Record for undo
        try self.recordUndo(.{ .delete = .{ .position = range.start, .text = deleted_text } });

        try self.rope.delete(range.start, range.len());
        self.modified = true;

        // Clear redo stack
        self.clearRedo();
    }

    /// Replace range with text
    pub fn replaceRange(self: *PhantomBuffer, range: core.Range, text: []const u8) !void {
        const old_text = try self.rope.copyRangeAlloc(self.allocator, range);

        // Record for undo
        try self.recordUndo(.{
            .replace = .{
                .range = range,
                .old_text = old_text,
                .new_text = try self.allocator.dupe(u8, text),
            },
        });

        try self.rope.delete(range.start, range.len());
        try self.rope.insert(range.start, text);
        self.modified = true;

        // Clear redo stack
        self.clearRedo();
    }

    /// Undo last operation
    pub fn undo(self: *PhantomBuffer) !void {
        const entry = self.undo_stack.popOrNull() orelse return error.NothingToUndo;

        switch (entry.operation) {
            .insert => |op| {
                try self.rope.delete(op.position, op.text.len);
                try self.redo_stack.append(entry);
            },
            .delete => |op| {
                try self.rope.insert(op.position, op.text);
                try self.redo_stack.append(entry);
            },
            .replace => |op| {
                try self.rope.delete(op.range.start, op.new_text.len);
                try self.rope.insert(op.range.start, op.old_text);
                try self.redo_stack.append(entry);
            },
        }
    }

    /// Redo last undone operation
    pub fn redo(self: *PhantomBuffer) !void {
        const entry = self.redo_stack.popOrNull() orelse return error.NothingToRedo;

        switch (entry.operation) {
            .insert => |op| {
                try self.rope.insert(op.position, op.text);
                try self.undo_stack.append(entry);
            },
            .delete => |op| {
                try self.rope.delete(op.position, op.text.len);
                try self.undo_stack.append(entry);
            },
            .replace => |op| {
                try self.rope.delete(op.range.start, op.old_text.len);
                try self.rope.insert(op.range.start, op.new_text);
                try self.undo_stack.append(entry);
            },
        }
    }

    /// Add a cursor
    pub fn addCursor(self: *PhantomBuffer, position: CursorPosition) !void {
        try self.cursor_positions.append(position);
    }

    /// Remove all cursors except the primary
    pub fn clearSecondaryCursors(self: *PhantomBuffer) void {
        if (self.cursor_positions.items.len > 1) {
            self.cursor_positions.shrinkRetainingCapacity(1);
        }
    }

    /// Get primary cursor
    pub fn primaryCursor(self: *const PhantomBuffer) CursorPosition {
        return self.cursor_positions.items[0];
    }

    /// Set primary cursor
    pub fn setPrimaryCursor(self: *PhantomBuffer, position: CursorPosition) void {
        self.cursor_positions.items[0] = position;
    }

    /// Get buffer content
    pub fn getContent(self: *const PhantomBuffer) ![]const u8 {
        return try self.rope.copyRangeAlloc(self.allocator, .{ .start = 0, .end = self.rope.len() });
    }

    /// Get line count
    pub fn lineCount(self: *const PhantomBuffer) usize {
        return self.rope.lineCount();
    }

    /// Get line content
    pub fn getLine(self: *const PhantomBuffer, line_num: usize) ![]const u8 {
        return try self.rope.lineSliceAlloc(self.allocator, line_num);
    }

    // Private helpers
    fn recordUndo(self: *PhantomBuffer, operation: UndoEntry.Operation) !void {
        try self.undo_stack.append(.{
            .operation = operation,
            .timestamp = std.time.milliTimestamp(),
        });
    }

    fn clearRedo(self: *PhantomBuffer) void {
        for (self.redo_stack.items) |*entry| {
            self.freeUndoEntry(entry);
        }
        self.redo_stack.clearRetainingCapacity();
    }

    fn freeUndoEntry(self: *PhantomBuffer, entry: *UndoEntry) void {
        switch (entry.operation) {
            .insert => |op| self.allocator.free(op.text),
            .delete => |op| self.allocator.free(op.text),
            .replace => |op| {
                self.allocator.free(op.old_text);
                self.allocator.free(op.new_text);
            },
        }
    }
};

/// Detect language from file extension
fn detectLanguage(path: []const u8) PhantomBuffer.Language {
    const ext = std.fs.path.extension(path);

    if (std.mem.eql(u8, ext, ".zig")) return .zig;
    if (std.mem.eql(u8, ext, ".rs")) return .rust;
    if (std.mem.eql(u8, ext, ".go")) return .go;
    if (std.mem.eql(u8, ext, ".js")) return .javascript;
    if (std.mem.eql(u8, ext, ".ts")) return .typescript;
    if (std.mem.eql(u8, ext, ".py")) return .python;
    if (std.mem.eql(u8, ext, ".c")) return .c;
    if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".cxx")) return .cpp;
    if (std.mem.eql(u8, ext, ".md")) return .markdown;
    if (std.mem.eql(u8, ext, ".json")) return .json;
    if (std.mem.eql(u8, ext, ".html")) return .html;
    if (std.mem.eql(u8, ext, ".css")) return .css;
    if (std.mem.eql(u8, ext, ".gza")) return .ghostlang;

    return .unknown;
}

test "PhantomBuffer basic operations" {
    const allocator = std.testing.allocator;

    var buffer = try PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "hello");
    try buffer.insertText(5, " world");

    const content = try buffer.getContent();
    defer allocator.free(content);

    try std.testing.expectEqualStrings("hello world", content);
}

test "PhantomBuffer undo/redo" {
    const allocator = std.testing.allocator;

    var buffer = try PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "hello");
    try buffer.undo();

    var content = try buffer.getContent();
    defer allocator.free(content);
    try std.testing.expectEqualStrings("", content);

    try buffer.redo();
    content = try buffer.getContent();
    defer allocator.free(content);
    try std.testing.expectEqualStrings("hello", content);
}

test "PhantomBuffer multi-cursor" {
    const allocator = std.testing.allocator;

    var buffer = try PhantomBuffer.init(allocator, 1, .{});
    defer buffer.deinit();

    try buffer.insertText(0, "line1\nline2\nline3");

    try buffer.addCursor(.{ .line = 1, .column = 0, .byte_offset = 6 });
    try buffer.addCursor(.{ .line = 2, .column = 0, .byte_offset = 12 });

    try std.testing.expectEqual(@as(usize, 3), buffer.cursor_positions.items.len);

    buffer.clearSecondaryCursors();
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor_positions.items.len);
}

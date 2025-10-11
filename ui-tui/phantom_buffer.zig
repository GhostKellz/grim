const std = @import("std");
const core = @import("core");

/// PhantomBuffer - Enhanced buffer with undo/redo and multi-cursor support
/// Uses rope-based implementation with manual undo/redo stack
pub const PhantomBuffer = struct {
    allocator: std.mem.Allocator,
    id: u32,
    file_path: ?[]const u8 = null,
    language: Language = .unknown,
    modified: bool = false,

    // Rope buffer
    rope: core.Rope,

    // Undo/redo stacks
    undo_stack: std.ArrayList(UndoEntry),
    redo_stack: std.ArrayList(UndoEntry),
    max_undo_levels: usize = 1000,

    // Multi-cursor support
    cursor_positions: std.ArrayList(CursorPosition),

    // Editor configuration
    config: EditorConfig,

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

    pub const BufferOptions = struct {
        config: EditorConfig = .{},
        initial_content: ?[]const u8 = null,
        use_phantom: bool = false, // Reserved for future PhantomTUI integration
    };

    const UndoEntry = struct {
        operation: Operation,
        position: usize,
        content: []const u8,

        const Operation = enum {
            insert,
            delete,
        };

        fn deinit(self: *UndoEntry, allocator: std.mem.Allocator) void {
            allocator.free(self.content);
        }
    };

    pub fn init(allocator: std.mem.Allocator, id: u32, options: BufferOptions) !PhantomBuffer {
        var rope = try core.Rope.init(allocator);
        errdefer rope.deinit();

        if (options.initial_content) |content| {
            try rope.insert(0, content);
        }

        var cursor_positions = std.ArrayList(CursorPosition){};
        errdefer cursor_positions.deinit(allocator);

        // Initialize with one cursor at (0, 0)
        try cursor_positions.append(allocator, .{ .line = 0, .column = 0, .byte_offset = 0 });

        return PhantomBuffer{
            .allocator = allocator,
            .id = id,
            .config = options.config,
            .rope = rope,
            .cursor_positions = cursor_positions,
            .undo_stack = .{},
            .redo_stack = .{},
        };
    }

    pub fn deinit(self: *PhantomBuffer) void {
        self.rope.deinit();
        self.cursor_positions.deinit(self.allocator);

        // Free undo stack
        for (self.undo_stack.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.undo_stack.deinit(self.allocator);

        // Free redo stack
        for (self.redo_stack.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.redo_stack.deinit(self.allocator);

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

        // Clear rope
        const len = self.rope.len();
        if (len > 0) {
            try self.rope.delete(0, len);
        }
        try self.rope.insert(0, content);

        // Set file path
        if (self.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.file_path = try self.allocator.dupe(u8, path);

        // Detect language
        self.language = detectLanguage(path);
        self.modified = false;

        // Clear undo/redo on file load
        self.clearUndoRedo();
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
        // Record undo entry
        try self.recordUndo(.{
            .operation = .insert,
            .position = position,
            .content = try self.allocator.dupe(u8, text),
        });

        try self.rope.insert(position, text);
        self.modified = true;

        // Clear redo stack on new operation
        self.clearRedoStack();
    }

    /// Delete range
    pub fn deleteRange(self: *PhantomBuffer, range: core.Range) !void {
        // Get content before deletion for undo
        const deleted_content = try self.rope.copyRangeAlloc(self.allocator, range);

        // Record undo entry
        try self.recordUndo(.{
            .operation = .delete,
            .position = range.start,
            .content = deleted_content,
        });

        try self.rope.delete(range.start, range.len());
        self.modified = true;

        // Clear redo stack on new operation
        self.clearRedoStack();
    }

    /// Replace range with text
    pub fn replaceRange(self: *PhantomBuffer, range: core.Range, text: []const u8) !void {
        try self.deleteRange(range);
        try self.insertText(range.start, text);
    }

    /// Undo last operation
    pub fn undo(self: *PhantomBuffer) !void {
        const entry = self.undo_stack.pop() orelse return error.NothingToUndo;

        // Perform reverse operation
        switch (entry.operation) {
            .insert => {
                // Reverse insert = delete
                try self.rope.delete(entry.position, entry.content.len);

                // Add to redo stack
                try self.redo_stack.append(self.allocator, entry);
            },
            .delete => {
                // Reverse delete = insert
                try self.rope.insert(entry.position, entry.content);

                // Add to redo stack
                try self.redo_stack.append(self.allocator, entry);
            },
        }

        self.modified = true;
    }

    /// Redo last undone operation
    pub fn redo(self: *PhantomBuffer) !void {
        const entry = self.redo_stack.pop() orelse return error.NothingToRedo;

        // Perform original operation
        switch (entry.operation) {
            .insert => {
                try self.rope.insert(entry.position, entry.content);

                // Add back to undo stack
                try self.undo_stack.append(self.allocator, entry);
            },
            .delete => {
                try self.rope.delete(entry.position, entry.content.len);

                // Add back to undo stack
                try self.undo_stack.append(self.allocator, entry);
            },
        }

        self.modified = true;
    }

    /// Add a cursor (multi-cursor support)
    pub fn addCursor(self: *PhantomBuffer, position: CursorPosition) !void {
        try self.cursor_positions.append(self.allocator, position);
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

    /// Check if using Phantom TextEditor (always false for now)
    pub fn isUsingPhantom(self: *const PhantomBuffer) bool {
        _ = self;
        return false; // TODO: Return true when phantom.TextEditor is integrated
    }

    pub const DiagnosticSeverity = enum {
        @"error",
        warning,
        info,
        hint,
    };

    // Private helpers

    fn recordUndo(self: *PhantomBuffer, entry: UndoEntry) !void {
        // Enforce max undo levels
        if (self.undo_stack.items.len >= self.max_undo_levels) {
            var old_entry = self.undo_stack.orderedRemove(0);
            old_entry.deinit(self.allocator);
        }

        try self.undo_stack.append(self.allocator, entry);
    }

    fn clearRedoStack(self: *PhantomBuffer) void {
        for (self.redo_stack.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.redo_stack.clearRetainingCapacity();
    }

    fn clearUndoRedo(self: *PhantomBuffer) void {
        for (self.undo_stack.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.undo_stack.clearRetainingCapacity();

        for (self.redo_stack.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.redo_stack.clearRetainingCapacity();
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

    // Insert text
    try buffer.insertText(0, "hello");

    {
        const content1 = try buffer.getContent();
        defer allocator.free(content1);
        try std.testing.expectEqualStrings("hello", content1);
    }

    // Undo
    try buffer.undo();

    {
        const content2 = try buffer.getContent();
        defer allocator.free(content2);
        try std.testing.expectEqualStrings("", content2);
    }

    // Redo
    try buffer.redo();

    {
        const content3 = try buffer.getContent();
        defer allocator.free(content3);
        try std.testing.expectEqualStrings("hello", content3);
    }
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

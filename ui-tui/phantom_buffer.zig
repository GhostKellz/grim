const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const runtime = @import("runtime");

/// PhantomTUI v0.5.0 Buffer Integration
/// Uses Phantom's built-in TextEditor widget for high-performance editing
pub const PhantomBuffer = struct {
    allocator: std.mem.Allocator,
    id: u32,
    file_path: ?[]const u8 = null,
    language: Language = .unknown,
    modified: bool = false,

    // Phantom v0.5.0 TextEditor widget (when available)
    // Falls back to rope-based implementation
    phantom_editor: ?*phantom.TextEditor = null,

    // Fallback rope buffer (used when phantom TextEditor not available)
    rope: core.Rope,

    // Editor configuration
    config: EditorConfig,

    // Multi-cursor support (synced with phantom or managed manually)
    cursor_positions: std.ArrayList(CursorPosition),

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
        use_phantom: bool = true, // Set to false to force rope fallback
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

        // Try to initialize Phantom TextEditor widget
        var phantom_editor: ?*phantom.TextEditor = null;
        if (options.use_phantom) {
            phantom_editor = initPhantomEditor(allocator, options.config) catch |err| blk: {
                std.log.warn("Failed to initialize Phantom TextEditor (falling back to rope): {}", .{err});
                break :blk null;
            };
        }

        return PhantomBuffer{
            .allocator = allocator,
            .id = id,
            .config = options.config,
            .phantom_editor = phantom_editor,
            .rope = rope,
            .cursor_positions = cursor_positions,
        };
    }

    fn initPhantomEditor(allocator: std.mem.Allocator, config: EditorConfig) !*phantom.TextEditor {
        // Phantom v0.5.0 TextEditor initialization
        // This provides:
        // - Built-in rope buffer
        // - Undo/redo stack
        // - Multi-cursor support
        // - Diagnostic markers
        // - Code folding
        const editor_config = phantom.TextEditor.Config{
            .show_line_numbers = config.show_line_numbers,
            .relative_line_numbers = config.relative_line_numbers,
            .tab_size = @intCast(config.tab_size),
            .use_spaces = config.use_spaces,
            .enable_ligatures = config.enable_ligatures,
            .auto_indent = config.auto_indent,
            .highlight_matching_brackets = config.highlight_matching_brackets,
            .line_wrap = config.line_wrap,
        };

        return try phantom.TextEditor.init(allocator, editor_config);
    }

    pub fn deinit(self: *PhantomBuffer) void {
        if (self.phantom_editor) |editor| {
            editor.deinit();
            self.allocator.destroy(editor);
        }

        self.rope.deinit();
        self.cursor_positions.deinit();

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

        if (self.phantom_editor) |editor| {
            // Use Phantom's loadFile if available
            try editor.loadFile(path);
        } else {
            // Fallback: Clear and insert into rope
            const len = self.rope.len();
            if (len > 0) {
                try self.rope.delete(0, len);
            }
            try self.rope.insert(0, content);
        }

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

        if (self.phantom_editor) |editor| {
            // Use Phantom's saveFile if available
            try editor.saveFile(path);
        } else {
            // Fallback: Save from rope
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();

            const content = try self.rope.copyRangeAlloc(self.allocator, .{ .start = 0, .end = self.rope.len() });
            defer self.allocator.free(content);

            try file.writeAll(content);
        }

        self.modified = false;
    }

    /// Insert text at position
    pub fn insertText(self: *PhantomBuffer, position: usize, text: []const u8) !void {
        if (self.phantom_editor) |editor| {
            // Phantom automatically handles undo/redo
            try editor.insertText(position, text);
        } else {
            // Fallback rope implementation
            try self.rope.insert(position, text);
        }
        self.modified = true;
    }

    /// Delete range
    pub fn deleteRange(self: *PhantomBuffer, range: core.Range) !void {
        if (self.phantom_editor) |editor| {
            try editor.deleteRange(range.start, range.len());
        } else {
            try self.rope.delete(range.start, range.len());
        }
        self.modified = true;
    }

    /// Replace range with text
    pub fn replaceRange(self: *PhantomBuffer, range: core.Range, text: []const u8) !void {
        if (self.phantom_editor) |editor| {
            try editor.deleteRange(range.start, range.len());
            try editor.insertText(range.start, text);
        } else {
            try self.rope.delete(range.start, range.len());
            try self.rope.insert(range.start, text);
        }
        self.modified = true;
    }

    /// Undo last operation (Phantom handles this natively!)
    pub fn undo(self: *PhantomBuffer) !void {
        if (self.phantom_editor) |editor| {
            try editor.undo();
        } else {
            return error.UndoNotAvailableInFallbackMode;
        }
    }

    /// Redo last undone operation (Phantom handles this natively!)
    pub fn redo(self: *PhantomBuffer) !void {
        if (self.phantom_editor) |editor| {
            try editor.redo();
        } else {
            return error.RedoNotAvailableInFallbackMode;
        }
    }

    /// Add a cursor (multi-cursor support)
    pub fn addCursor(self: *PhantomBuffer, position: CursorPosition) !void {
        if (self.phantom_editor) |editor| {
            try editor.addCursor(.{
                .line = position.line,
                .col = position.column,
            });
        } else {
            try self.cursor_positions.append(position);
        }
    }

    /// Remove all cursors except the primary
    pub fn clearSecondaryCursors(self: *PhantomBuffer) void {
        if (self.phantom_editor) |editor| {
            editor.clearSecondaryCursors();
        } else {
            if (self.cursor_positions.items.len > 1) {
                self.cursor_positions.shrinkRetainingCapacity(1);
            }
        }
    }

    /// Get primary cursor
    pub fn primaryCursor(self: *const PhantomBuffer) CursorPosition {
        if (self.phantom_editor) |editor| {
            const phantom_cursor = editor.getPrimaryCursor();
            return .{
                .line = phantom_cursor.line,
                .column = phantom_cursor.col,
                .byte_offset = self.lineColToOffset(phantom_cursor.line, phantom_cursor.col),
            };
        } else {
            return self.cursor_positions.items[0];
        }
    }

    /// Set primary cursor
    pub fn setPrimaryCursor(self: *PhantomBuffer, position: CursorPosition) void {
        if (self.phantom_editor) |editor| {
            editor.setPrimaryCursor(.{
                .line = position.line,
                .col = position.column,
            });
        } else {
            self.cursor_positions.items[0] = position;
        }
    }

    /// Get buffer content
    pub fn getContent(self: *const PhantomBuffer) ![]const u8 {
        if (self.phantom_editor) |editor| {
            return try editor.getContent(self.allocator);
        } else {
            return try self.rope.copyRangeAlloc(self.allocator, .{ .start = 0, .end = self.rope.len() });
        }
    }

    /// Get line count
    pub fn lineCount(self: *const PhantomBuffer) usize {
        if (self.phantom_editor) |editor| {
            return editor.lineCount();
        } else {
            return self.rope.lineCount();
        }
    }

    /// Get line content
    pub fn getLine(self: *const PhantomBuffer, line_num: usize) ![]const u8 {
        if (self.phantom_editor) |editor| {
            return try editor.getLine(self.allocator, line_num);
        } else {
            return try self.rope.lineSliceAlloc(self.allocator, line_num);
        }
    }

    /// Add LSP diagnostic marker (Phantom v0.5.0 feature!)
    pub fn addDiagnostic(self: *PhantomBuffer, line: usize, column: usize, severity: DiagnosticSeverity, message: []const u8) !void {
        if (self.phantom_editor) |editor| {
            const phantom_severity = switch (severity) {
                .@"error" => phantom.TextEditor.DiagnosticMarker.Severity.error_marker,
                .warning => phantom.TextEditor.DiagnosticMarker.Severity.warning,
                .info => phantom.TextEditor.DiagnosticMarker.Severity.info,
                .hint => phantom.TextEditor.DiagnosticMarker.Severity.hint,
            };

            try editor.addDiagnosticMarker(.{
                .line = line,
                .col = column,
                .severity = phantom_severity,
                .message = message,
            });
        }
    }

    /// Clear all diagnostic markers
    pub fn clearDiagnostics(self: *PhantomBuffer) void {
        if (self.phantom_editor) |editor| {
            editor.clearDiagnosticMarkers();
        }
    }

    pub const DiagnosticSeverity = enum {
        @"error",
        warning,
        info,
        hint,
    };

    // Private helpers
    fn lineColToOffset(self: *const PhantomBuffer, line: usize, col: usize) usize {
        _ = self;
        _ = line;
        _ = col;
        // TODO: Implement proper line/col to offset conversion
        return 0;
    }

    /// Check if using Phantom TextEditor
    pub fn isUsingPhantom(self: *const PhantomBuffer) bool {
        return self.phantom_editor != null;
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

    var buffer = try PhantomBuffer.init(allocator, 1, .{ .use_phantom = false }); // Use rope fallback for tests
    defer buffer.deinit();

    try buffer.insertText(0, "hello");
    try buffer.insertText(5, " world");

    const content = try buffer.getContent();
    defer allocator.free(content);

    try std.testing.expectEqualStrings("hello world", content);
}

test "PhantomBuffer multi-cursor" {
    const allocator = std.testing.allocator;

    var buffer = try PhantomBuffer.init(allocator, 1, .{ .use_phantom = false });
    defer buffer.deinit();

    try buffer.insertText(0, "line1\nline2\nline3");

    try buffer.addCursor(.{ .line = 1, .column = 0, .byte_offset = 6 });
    try buffer.addCursor(.{ .line = 2, .column = 0, .byte_offset = 12 });

    try std.testing.expectEqual(@as(usize, 3), buffer.cursor_positions.items.len);

    buffer.clearSecondaryCursors();
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor_positions.items.len);
}

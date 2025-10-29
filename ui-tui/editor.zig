const std = @import("std");
const core = @import("core");
const syntax = @import("syntax");

pub const Editor = struct {
    allocator: std.mem.Allocator,
    rope: core.Rope,
    mode: Mode,
    cursor: Position,
    highlighter: syntax.SyntaxHighlighter,
    current_filename: ?[]const u8,
    features: syntax.Features,
    fold_regions: []syntax.Features.FoldRegion,
    selection_start: ?usize,
    selection_end: ?usize,
    // Multi-cursor support
    cursors: std.ArrayList(Position),
    multi_cursor_mode: bool,
    selected_word: ?[]u8, // Current word for multi-cursor selection
    // Key sequence tracking
    pending_key: ?u21,
    // Rename state
    rename_buffer: ?[]u8,
    rename_active: bool,
    // Yank/paste system
    yank_buffer: ?[]u8,
    yank_linewise: bool,
    // Search state
    search_pattern: ?[]u8,
    last_search_forward: bool,
    search_matches: std.ArrayList(usize), // All match offsets
    current_match_index: ?usize, // Index into search_matches
    // Character find state (for f/F/t/T and ; commands)
    last_find_char: ?u21,
    last_find_forward: bool,
    last_find_till: bool, // true for t/T, false for f/F
    // Undo/redo system (using core.UndoStack)
    undo_stack: core.UndoStack,
    // io_uring async file I/O manager
    io_uring_manager: core.IoUringFileManager,

    pub const Mode = enum {
        normal,
        insert,
        visual,
        command,
    };

    pub const Position = struct {
        offset: usize = 0, // Byte offset in the rope
        desired_column: ?usize = null, // Virtual column for vertical movement

        pub fn moveLeft(self: *Position, rope: *core.Rope) void {
            self.desired_column = null; // Horizontal movement clears desired column
            if (self.offset == 0) return;

            // Move to previous UTF-8 character boundary
            const slice = rope.slice(.{ .start = 0, .end = self.offset }) catch return;
            var i = self.offset - 1;
            while (i > 0 and (slice[i] & 0xC0) == 0x80) : (i -= 1) {}
            self.offset = i;
        }

        pub fn moveRight(self: *Position, rope: *core.Rope) void {
            self.desired_column = null; // Horizontal movement clears desired column
            if (self.offset >= rope.len()) return;

            // Move to next UTF-8 character boundary
            const slice = rope.slice(.{ .start = self.offset, .end = rope.len() }) catch return;
            var i: usize = 1;
            while (i < slice.len and (slice[i] & 0xC0) == 0x80) : (i += 1) {}
            self.offset = @min(self.offset + i, rope.len());
        }

        pub fn moveToLineStart(self: *Position, rope: *core.Rope) void {
            self.desired_column = null; // Horizontal movement clears desired column
            if (self.offset == 0) return;

            // Find previous newline
            const slice = rope.slice(.{ .start = 0, .end = self.offset }) catch return;
            var i = self.offset;
            while (i > 0) : (i -= 1) {
                if (slice[i - 1] == '\n') break;
            }
            self.offset = i;
        }

        pub fn moveToLineEnd(self: *Position, rope: *core.Rope) void {
            self.desired_column = null; // Horizontal movement clears desired column
            const len = rope.len();
            if (self.offset >= len) return;

            // Find next newline
            const slice = rope.slice(.{ .start = self.offset, .end = len }) catch return;
            for (slice, 0..) |ch, i| {
                if (ch == '\n') {
                    self.offset += i;
                    return;
                }
            }
            self.offset = len;
        }
    };

    pub const Command = enum {
        move_left,
        move_right,
        move_up,
        move_down,
        move_word_forward,
        move_word_backward,
        move_line_start,
        move_line_end,
        move_file_start,
        move_file_end,
        enter_insert,
        enter_insert_after,
        enter_visual,
        enter_command,
        escape_to_normal,
        delete_char,
        delete_line,
        yank_line,
        paste_after,
        toggle_fold,
        fold_all,
        unfold_all,
        expand_selection,
        shrink_selection,
        update_folds,
        add_cursor_below,
        add_cursor_above,
        add_cursor_at_next_match,
        remove_last_cursor,
        toggle_multi_cursor,
        jump_to_definition,
        rename_symbol,
    };

    pub const Error = error{
        UnhandledKey,
        RopeError,
        Utf8CannotEncodeSurrogateHalf,
        CodepointTooLarge,
    } || std.mem.Allocator.Error || core.Rope.Error;

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return .{
            .allocator = allocator,
            .rope = try core.Rope.init(allocator),
            .mode = .normal,
            .cursor = .{},
            .highlighter = syntax.SyntaxHighlighter.init(allocator),
            .current_filename = null,
            .features = syntax.Features.init(allocator),
            .fold_regions = &.{},
            .selection_start = null,
            .selection_end = null,
            .cursors = .{},
            .multi_cursor_mode = false,
            .selected_word = null,
            .pending_key = null,
            .rename_buffer = null,
            .rename_active = false,
            .yank_buffer = null,
            .yank_linewise = false,
            .search_pattern = null,
            .last_search_forward = true,
            .search_matches = std.ArrayList(usize){},
            .current_match_index = null,
            .last_find_char = null,
            .last_find_forward = true,
            .last_find_till = false,
            .undo_stack = core.UndoStack.init(allocator, 1000),
            .io_uring_manager = try core.IoUringFileManager.init(allocator),
        };
    }

    pub fn deinit(self: *Editor) void {
        self.io_uring_manager.deinit();
        self.rope.deinit();
        self.highlighter.deinit();
        if (self.fold_regions.len > 0) {
            self.allocator.free(self.fold_regions);
        }
        if (self.current_filename) |filename| {
            self.allocator.free(filename);
        }
        if (self.rename_buffer) |buf| {
            self.allocator.free(buf);
        }
        if (self.yank_buffer) |buf| {
            self.allocator.free(buf);
        }
        if (self.search_pattern) |pattern| {
            self.allocator.free(pattern);
        }
        if (self.selected_word) |word| {
            self.allocator.free(word);
        }
        // Free undo stack
        self.undo_stack.deinit();
        self.cursors.deinit(self.allocator);
        self.search_matches.deinit(self.allocator);
        self.* = undefined;
    }

    /// Convert byte offset to line and column (0-indexed)
    pub fn offsetToLineCol(self: *Editor, offset: usize) !struct { line: u32, col: u32 } {
        const content = try self.rope.slice(.{ .start = 0, .end = @min(offset, self.rope.len()) });
        var line: u32 = 0;
        var col: u32 = 0;

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

    pub fn loadFile(self: *Editor, path: []const u8) !void {
        // Use io_uring if available, fallback to synchronous I/O
        const content = if (self.io_uring_manager.available)
            try self.loadFileAsync(path)
        else
            try self.loadFileSync(path);
        defer self.allocator.free(content);

        // Clear rope before loading new content
        const rope_len = self.rope.len();
        if (rope_len > 0) {
            try self.rope.delete(0, rope_len);
        }

        try self.rope.insert(0, content);

        // Update filename and initialize syntax highlighting
        if (self.current_filename) |old_filename| {
            self.allocator.free(old_filename);
        }
        self.current_filename = try self.allocator.dupe(u8, path);
        try self.highlighter.setLanguage(path);

        // Set parser for tree-sitter features and update fold regions
        if (self.highlighter.parser) |parser| {
            self.features.setParser(parser);
            try self.updateFoldRegions();
        }
    }

    /// Load file using io_uring (async, zero-copy)
    fn loadFileAsync(self: *Editor, path: []const u8) ![]u8 {
        // TODO: Implement full io_uring integration
        // For now, fallback to sync
        return self.loadFileSync(path);
    }

    /// Load file using synchronous I/O (fallback)
    fn loadFileSync(self: *Editor, path: []const u8) ![]u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Return empty buffer for new files
                return try self.allocator.alloc(u8, 0);
            }
            return err;
        };
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(content);

        const bytes_read = try file.readAll(content);
        return content[0..bytes_read];
    }

    pub fn saveFile(self: *Editor, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        try file.writeAll(content);
    }

    pub fn handleKey(self: *Editor, key: u21) Error!void {
        switch (self.mode) {
            .normal => {
                if (self.commandForNormalKey(key)) |cmd| {
                    try self.dispatch(cmd);
                } else {
                    return Error.UnhandledKey;
                }
            },
            .insert => {
                if (key == 0x1B) { // ESC
                    self.mode = .normal;
                } else {
                    try self.insertChar(key);
                }
            },
            .visual => {
                if (key == 0x1B) { // ESC
                    self.mode = .normal;
                }
                // TODO: Implement visual mode commands
            },
            .command => {
                if (key == 0x1B) { // ESC
                    self.mode = .normal;
                }
                // TODO: Implement command mode
            },
        }
    }

    pub fn dispatch(self: *Editor, command: Command) Error!void {
        switch (command) {
            .move_left => self.cursor.moveLeft(&self.rope),
            .move_right => self.cursor.moveRight(&self.rope),
            .move_up => self.moveCursorUp(),
            .move_down => self.moveCursorDown(),
            .move_word_forward => self.moveCursorWordForward(),
            .move_word_backward => self.moveCursorWordBackward(),
            .move_line_start => self.cursor.moveToLineStart(&self.rope),
            .move_line_end => self.cursor.moveToLineEnd(&self.rope),
            .move_file_start => self.cursor.offset = 0,
            .move_file_end => self.cursor.offset = self.rope.len(),
            .enter_insert => self.mode = .insert,
            .enter_insert_after => {
                self.cursor.moveRight(&self.rope);
                self.mode = .insert;
            },
            .enter_visual => self.mode = .visual,
            .enter_command => self.mode = .command,
            .escape_to_normal => self.mode = .normal,
            .delete_char => try self.deleteCharAtCursor(),
            .delete_line => try self.deleteCurrentLine(),
            .yank_line => try self.yankCurrentLine(),
            .paste_after => try self.pasteAfter(),
            .toggle_fold => try self.toggleFoldAtCursor(),
            .fold_all => self.foldAll(),
            .unfold_all => self.unfoldAll(),
            .expand_selection => try self.expandSelection(),
            .shrink_selection => try self.shrinkSelection(),
            .update_folds => try self.updateFoldRegions(),
            .add_cursor_below => try self.addCursorBelow(),
            .add_cursor_above => try self.addCursorAbove(),
            .add_cursor_at_next_match => try self.addCursorAtNextMatch(),
            .remove_last_cursor => self.removeLastCursor(),
            .toggle_multi_cursor => self.toggleMultiCursor(),
            .jump_to_definition => try self.jumpToDefinition(),
            .rename_symbol => {
                // Rename requires UI interaction - set flag for TUI to handle
                self.rename_active = true;
            },
        }
    }

    fn commandForNormalKey(self: *Editor, key: u21) ?Command {
        // Handle two-key sequences
        if (self.pending_key) |pending| {
            defer self.pending_key = null;

            // Handle 'g' sequences
            if (pending == 'g') {
                return switch (key) {
                    'g' => .move_file_start,
                    'd' => .jump_to_definition,
                    else => null,
                };
            }

            // Handle 'd' sequences (dd for delete line)
            if (pending == 'd') {
                return switch (key) {
                    'd' => .delete_line,
                    else => null,
                };
            }

            // Handle 'y' sequences (yy for yank line)
            if (pending == 'y') {
                return switch (key) {
                    'y' => .yank_line,
                    else => null,
                };
            }
        }

        // Single-key commands
        return switch (key) {
            'h' => .move_left,
            'j' => .move_down,
            'k' => .move_up,
            'l' => .move_right,
            'w' => .move_word_forward,
            'b' => .move_word_backward,
            '0' => .move_line_start,
            '$' => .move_line_end,
            'g' => blk: {
                self.pending_key = 'g';
                break :blk null;
            },
            'G' => .move_file_end,
            'i' => .enter_insert,
            'a' => .enter_insert_after,
            'v' => .enter_visual,
            ':' => .enter_command,
            'x' => .delete_char,
            'd' => blk: {
                self.pending_key = 'd';
                break :blk null;
            },
            'y' => blk: {
                self.pending_key = 'y';
                break :blk null;
            },
            'p' => .paste_after,
            'z' => .toggle_fold, // TODO: Handle za, zR, zM properly
            'Z' => .fold_all, // Fold all regions
            '=' => .expand_selection, // Expand selection (Alt+= in full implementation)
            '-' => .shrink_selection, // Shrink selection (Alt+- in full implementation)
            0x1B => .escape_to_normal,
            else => null,
        };
    }

    pub fn insertChar(self: *Editor, key: u21) !void {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(key, &buf);
        try self.rope.insert(self.cursor.offset, buf[0..len]);
        self.cursor.offset += len;
    }

    pub fn getSyntaxHighlights(self: *Editor) ![]syntax.HighlightRange {
        const highlights = try self.highlighter.highlight(&self.rope);
        defer self.allocator.free(highlights);
        return syntax.convertHighlightsToRanges(self.allocator, highlights, &self.rope);
    }

    pub fn getLanguageName(self: *const Editor) []const u8 {
        return self.highlighter.getLanguageName();
    }

    fn deleteCharAtCursor(self: *Editor) !void {
        if (self.cursor.offset >= self.rope.len()) return;

        // Find the end of the current UTF-8 character
        const slice = try self.rope.slice(.{ .start = self.cursor.offset, .end = self.rope.len() });
        var char_len: usize = 1;
        while (char_len < slice.len and (slice[char_len] & 0xC0) == 0x80) : (char_len += 1) {}

        try self.rope.delete(self.cursor.offset, char_len);
    }

    fn deleteCurrentLine(self: *Editor) !void {
        // Find line boundaries
        self.cursor.moveToLineStart(&self.rope);
        const start = self.cursor.offset;
        self.cursor.moveToLineEnd(&self.rope);
        var end = self.cursor.offset;

        // Include the newline if not at end of file
        if (end < self.rope.len()) {
            end += 1;
        }

        if (end > start) {
            try self.rope.delete(start, end - start);
            self.cursor.offset = start;
        }
    }

    pub fn moveCursorUp(self: *Editor) void {
        // Save or use desired column
        const target_col = self.cursor.desired_column orelse self.getColumnPosition();
        self.cursor.desired_column = target_col;

        // Move to previous line
        self.cursor.moveToLineStart(&self.rope);
        if (self.cursor.offset > 0) {
            self.cursor.offset -= 1; // Move past previous newline
            self.cursor.moveToLineStart(&self.rope);

            // Restore column position (using desired column)
            self.moveToColumn(target_col);
        }
    }

    pub fn moveCursorDown(self: *Editor) void {
        // Save or use desired column
        const target_col = self.cursor.desired_column orelse self.getColumnPosition();
        self.cursor.desired_column = target_col;

        // Move to next line
        self.cursor.moveToLineEnd(&self.rope);
        if (self.cursor.offset < self.rope.len()) {
            self.cursor.offset += 1; // Move past newline

            // Restore column position (using desired column)
            self.moveToColumn(target_col);
        }
    }

    fn getColumnPosition(self: *Editor) usize {
        const line_start = blk: {
            var pos = Position{ .offset = self.cursor.offset };
            pos.moveToLineStart(&self.rope);
            break :blk pos.offset;
        };

        return self.cursor.offset - line_start;
    }

    fn moveToColumn(self: *Editor, col: usize) void {
        const line_start = self.cursor.offset;
        const line_end = blk: {
            var pos = Position{ .offset = self.cursor.offset };
            pos.moveToLineEnd(&self.rope);
            break :blk pos.offset;
        };

        self.cursor.offset = @min(line_start + col, line_end);
    }

    pub fn moveCursorWordForward(self: *Editor) void {
        const len = self.rope.len();
        if (self.cursor.offset >= len) return;

        const slice = self.rope.slice(.{ .start = self.cursor.offset, .end = len }) catch return;

        var i: usize = 0;
        var in_word = false;

        // Skip current word/whitespace
        while (i < slice.len) : (i += 1) {
            const is_word_char = std.ascii.isAlphanumeric(slice[i]) or slice[i] == '_';
            if (!in_word and is_word_char) {
                in_word = true;
            } else if (in_word and !is_word_char) {
                break;
            }
        }

        // Skip whitespace to next word
        while (i < slice.len and std.ascii.isWhitespace(slice[i])) : (i += 1) {}

        self.cursor.offset = @min(self.cursor.offset + i, len);
    }

    pub fn moveCursorWordBackward(self: *Editor) void {
        if (self.cursor.offset == 0) return;

        const slice = self.rope.slice(.{ .start = 0, .end = self.cursor.offset }) catch return;

        var i = slice.len;

        // Skip whitespace
        while (i > 0 and std.ascii.isWhitespace(slice[i - 1])) : (i -= 1) {}

        // Skip word characters
        while (i > 0 and (std.ascii.isAlphanumeric(slice[i - 1]) or slice[i - 1] == '_')) : (i -= 1) {}

        self.cursor.offset = i;
    }

    // Character find motions (f/F/t/T and ;/,)
    pub fn findCharForward(self: *Editor, ch: u21) void {
        self.last_find_char = ch;
        self.last_find_forward = true;
        self.last_find_till = false;

        const slice = self.rope.slice(.{ .start = self.cursor.offset + 1, .end = self.rope.len() }) catch return;
        for (slice, 0..) |byte, i| {
            if (byte == ch) {
                self.cursor.offset += i + 1;
                return;
            }
            // Stop at newline (f only searches current line)
            if (byte == '\n') return;
        }
    }

    pub fn findCharBackward(self: *Editor, ch: u21) void {
        self.last_find_char = ch;
        self.last_find_forward = false;
        self.last_find_till = false;

        if (self.cursor.offset == 0) return;
        const slice = self.rope.slice(.{ .start = 0, .end = self.cursor.offset }) catch return;
        var i = slice.len;
        while (i > 0) {
            i -= 1;
            if (slice[i] == ch) {
                self.cursor.offset = i;
                return;
            }
            // Stop at newline (F only searches current line)
            if (slice[i] == '\n') return;
        }
    }

    pub fn tillCharForward(self: *Editor, ch: u21) void {
        self.last_find_char = ch;
        self.last_find_forward = true;
        self.last_find_till = true;

        const slice = self.rope.slice(.{ .start = self.cursor.offset + 1, .end = self.rope.len() }) catch return;
        for (slice, 0..) |byte, i| {
            if (byte == ch) {
                self.cursor.offset += i; // Stop before the character
                return;
            }
            if (byte == '\n') return;
        }
    }

    pub fn tillCharBackward(self: *Editor, ch: u21) void {
        self.last_find_char = ch;
        self.last_find_forward = false;
        self.last_find_till = true;

        if (self.cursor.offset == 0) return;
        const slice = self.rope.slice(.{ .start = 0, .end = self.cursor.offset }) catch return;
        var i = slice.len;
        while (i > 0) {
            i -= 1;
            if (slice[i] == ch) {
                self.cursor.offset = i + 1; // Stop after the character
                return;
            }
            if (slice[i] == '\n') return;
        }
    }

    pub fn repeatLastFind(self: *Editor) void {
        const ch = self.last_find_char orelse return;
        if (self.last_find_forward) {
            if (self.last_find_till) {
                self.tillCharForward(ch);
            } else {
                self.findCharForward(ch);
            }
        } else {
            if (self.last_find_till) {
                self.tillCharBackward(ch);
            } else {
                self.findCharBackward(ch);
            }
        }
    }

    pub fn repeatLastFindReverse(self: *Editor) void {
        const ch = self.last_find_char orelse return;
        // Reverse direction
        if (self.last_find_forward) {
            if (self.last_find_till) {
                self.tillCharBackward(ch);
            } else {
                self.findCharBackward(ch);
            }
        } else {
            if (self.last_find_till) {
                self.tillCharForward(ch);
            } else {
                self.findCharForward(ch);
            }
        }
    }

    // Public interface aliases for SimpleTUI
    pub fn moveCursorLeft(self: *Editor) void {
        self.cursor.moveLeft(&self.rope);
    }

    pub fn moveCursorRight(self: *Editor) void {
        self.cursor.moveRight(&self.rope);
    }

    pub fn moveCursorToLineStart(self: *Editor) void {
        self.cursor.moveToLineStart(&self.rope);
    }

    pub fn moveCursorToLineEnd(self: *Editor) void {
        self.cursor.moveToLineEnd(&self.rope);
    }

    pub fn moveCursorToEnd(self: *Editor) void {
        self.cursor.offset = self.rope.len();
    }

    pub fn moveWordForward(self: *Editor) void {
        self.moveCursorWordForward();
    }

    pub fn moveWordBackward(self: *Editor) void {
        self.moveCursorWordBackward();
    }

    pub fn deleteChar(self: *Editor) !void {
        try self.deleteCharAtCursor();
    }

    pub fn insertNewlineAfter(self: *Editor) !void {
        self.cursor.moveToLineEnd(&self.rope);
        try self.rope.insert(self.cursor.offset, "\n");
        self.cursor.offset += 1;
    }

    pub fn insertNewlineBefore(self: *Editor) !void {
        self.cursor.moveToLineStart(&self.rope);
        try self.rope.insert(self.cursor.offset, "\n");
        // Don't move cursor - we want to be on the new line above
    }

    pub fn backspace(self: *Editor) !void {
        if (self.cursor.offset == 0) return;
        self.cursor.moveLeft(&self.rope);
        try self.rope.delete(self.cursor.offset, 1);
    }

    // Folding methods
    fn updateFoldRegions(self: *Editor) !void {
        if (self.fold_regions.len > 0) {
            self.allocator.free(self.fold_regions);
        }

        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        self.fold_regions = try self.features.getFoldRegions(content);
    }

    fn getCurrentLine(self: *const Editor) usize {
        const content = self.rope.slice(.{ .start = 0, .end = self.cursor.offset }) catch return 0;
        // Note: Rope owns this memory, don't free it

        var line: usize = 0;
        for (content) |ch| {
            if (ch == '\n') line += 1;
        }
        return line;
    }

    fn toggleFoldAtCursor(self: *Editor) !void {
        const current_line = self.getCurrentLine();

        for (self.fold_regions) |*region| {
            if (region.start_line <= current_line and current_line <= region.end_line) {
                region.folded = !region.folded;
                return;
            }
        }
    }

    fn foldAll(self: *Editor) void {
        for (self.fold_regions) |*region| {
            region.folded = true;
        }
    }

    fn unfoldAll(self: *Editor) void {
        for (self.fold_regions) |*region| {
            region.folded = false;
        }
    }

    // Jump to definition using tree-sitter
    // TODO: Add LSP fallback - see ui-tui/editor_lsp.zig for LSP integration
    // Future: Try LSP first (requires async handling), fall back to tree-sitter
    fn jumpToDefinition(self: *Editor) !void {
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        if (try self.features.findDefinition(content, self.cursor.offset)) |def| {
            self.cursor.offset = def.start_byte;
        }
    }

    // Rename symbol at cursor
    // Uses tree-sitter to find all occurrences in current file
    // TODO: Add LSP support for cross-file rename
    fn renameSymbol(self: *Editor, new_name: []const u8) !void {
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        // Get the identifier at cursor
        const identifier = self.features.getIdentifierAtPosition(content, self.cursor.offset) orelse return;

        // Find all occurrences of this identifier
        var occurrences = try std.ArrayList(struct { start: usize, end: usize }).initCapacity(self.allocator, 0);
        defer occurrences.deinit(self.allocator);

        // Simple text-based search for now (tree-sitter-based would be more accurate)
        var i: usize = 0;
        while (i < content.len) {
            if (i + identifier.len <= content.len and
                std.mem.eql(u8, content[i .. i + identifier.len], identifier))
            {
                // Check word boundaries
                const is_start_boundary = i == 0 or !isIdentifierChar(content[i - 1]);
                const is_end_boundary = i + identifier.len >= content.len or !isIdentifierChar(content[i + identifier.len]);

                if (is_start_boundary and is_end_boundary) {
                    try occurrences.append(self.allocator, .{ .start = i, .end = i + identifier.len });
                }
                i += identifier.len;
            } else {
                i += 1;
            }
        }

        // Replace occurrences in reverse order to maintain offsets
        var j: usize = occurrences.items.len;
        while (j > 0) {
            j -= 1;
            const occ = occurrences.items[j];

            // Delete old name
            var k: usize = occ.start;
            while (k < occ.end) : (k += 1) {
                try self.rope.delete(occ.start);
            }

            // Insert new name
            try self.rope.insert(occ.start, new_name);
        }

        // Update cursor if needed
        if (occurrences.items.len > 0) {
            // Stay at first occurrence
            self.cursor.offset = occurrences.items[0].start;
        }
    }

    fn isIdentifierChar(ch: u8) bool {
        return (ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or
            ch == '_';
    }

    // Selection methods
    fn expandSelection(self: *Editor) !void {
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        const current_start = self.selection_start orelse self.cursor.offset;
        const current_end = self.selection_end orelse self.cursor.offset;

        if (self.features.expandSelection(content, current_start, current_end)) |range| {
            self.selection_start = range.start_byte;
            self.selection_end = range.end_byte;
            self.cursor.offset = range.end_byte;
        } else |_| {
            // No larger selection available
        }
    }

    fn shrinkSelection(self: *Editor) !void {
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        const current_start = self.selection_start orelse self.cursor.offset;
        const current_end = self.selection_end orelse self.cursor.offset;

        if (self.features.shrinkSelection(content, current_start, current_end)) |range| {
            self.selection_start = range.start_byte;
            self.selection_end = range.end_byte;
            self.cursor.offset = range.end_byte;
        } else |_| {
            // No smaller selection available
            self.selection_start = null;
            self.selection_end = null;
        }
    }

    // Accessor for fold regions (for TUI rendering)
    pub fn getFoldRegions(self: *const Editor) []const syntax.Features.FoldRegion {
        return self.fold_regions;
    }

    pub fn getSelection(self: *const Editor) ?struct { start: usize, end: usize } {
        if (self.selection_start) |start| {
            if (self.selection_end) |end| {
                return .{ .start = start, .end = end };
            }
        }
        return null;
    }

    // Search operations
    pub fn setSearchPattern(self: *Editor, pattern: []const u8) !void {
        if (self.search_pattern) |old_pattern| {
            self.allocator.free(old_pattern);
        }
        self.search_pattern = try self.allocator.dupe(u8, pattern);

        // Find all matches
        try self.findAllMatches();
    }

    /// Find all occurrences of the current search pattern
    fn findAllMatches(self: *Editor) !void {
        self.search_matches.clearRetainingCapacity();
        self.current_match_index = null;

        const pattern = self.search_pattern orelse return;
        if (pattern.len == 0) return;

        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });

        var offset: usize = 0;
        while (offset < content.len) {
            if (std.mem.indexOf(u8, content[offset..], pattern)) |rel_pos| {
                const match_pos = offset + rel_pos;
                try self.search_matches.append(self.allocator, match_pos);
                offset = match_pos + 1; // Move past this match
            } else {
                break;
            }
        }

        // Set current match index to the one at or after cursor
        if (self.search_matches.items.len > 0) {
            for (self.search_matches.items, 0..) |match_pos, i| {
                if (match_pos >= self.cursor.offset) {
                    self.current_match_index = i;
                    break;
                }
            }
            // If no match after cursor, wrap to first
            if (self.current_match_index == null) {
                self.current_match_index = 0;
            }
        }
    }

    /// Go to next search match (n command)
    pub fn nextMatch(self: *Editor) bool {
        if (self.search_matches.items.len == 0) return false;

        if (self.current_match_index) |idx| {
            // Go to next match, wrap around if at end
            const next_idx = (idx + 1) % self.search_matches.items.len;
            self.current_match_index = next_idx;
            self.cursor.offset = self.search_matches.items[next_idx];
            self.last_search_forward = true;
            return true;
        }

        return false;
    }

    /// Go to previous search match (N command)
    pub fn previousMatch(self: *Editor) bool {
        if (self.search_matches.items.len == 0) return false;

        if (self.current_match_index) |idx| {
            // Go to previous match, wrap around if at beginning
            const prev_idx = if (idx == 0)
                self.search_matches.items.len - 1
            else
                idx - 1;
            self.current_match_index = prev_idx;
            self.cursor.offset = self.search_matches.items[prev_idx];
            self.last_search_forward = false;
            return true;
        }

        return false;
    }

    pub fn searchForward(self: *Editor) !bool {
        // Use nextMatch for forward navigation
        return self.nextMatch();
    }

    pub fn searchBackward(self: *Editor) !bool {
        // Use previousMatch for backward navigation
        return self.previousMatch();
    }

    pub fn repeatLastSearch(self: *Editor) !bool {
        if (self.last_search_forward) {
            return try self.searchForward();
        } else {
            return try self.searchBackward();
        }
    }

    pub fn repeatLastSearchReverse(self: *Editor) !bool {
        if (self.last_search_forward) {
            return try self.searchBackward();
        } else {
            return try self.searchForward();
        }
    }

    // Yank/paste operations
    fn yankCurrentLine(self: *Editor) !void {
        // Find line boundaries
        self.cursor.moveToLineStart(&self.rope);
        const start = self.cursor.offset;
        self.cursor.moveToLineEnd(&self.rope);
        var end = self.cursor.offset;

        // Include the newline if not at end of file
        if (end < self.rope.len()) {
            end += 1;
        }

        if (end > start) {
            const yanked = try self.rope.slice(.{ .start = start, .end = end });

            // Free old yank buffer
            if (self.yank_buffer) |old_buf| {
                self.allocator.free(old_buf);
            }

            // Store yanked content
            self.yank_buffer = try self.allocator.dupe(u8, yanked);
            self.yank_linewise = true;
            self.cursor.offset = start;
        }
    }

    fn pasteAfter(self: *Editor) !void {
        const yanked = self.yank_buffer orelse return;

        if (self.yank_linewise) {
            // Paste on next line
            self.cursor.moveToLineEnd(&self.rope);
            const insert_pos = if (self.cursor.offset < self.rope.len())
                self.cursor.offset + 1
            else
                self.cursor.offset;

            // If at end of file and no trailing newline, add one first
            if (insert_pos == self.rope.len() and self.rope.len() > 0) {
                const last_char = (try self.rope.slice(.{ .start = self.rope.len() - 1, .end = self.rope.len() }))[0];
                if (last_char != '\n') {
                    try self.rope.insert(self.rope.len(), "\n");
                }
            }

            try self.rope.insert(insert_pos, yanked);
            self.cursor.offset = insert_pos;
        } else {
            // Character-wise paste after cursor
            self.cursor.moveRight(&self.rope);
            try self.rope.insert(self.cursor.offset, yanked);
            self.cursor.offset += yanked.len;
        }
    }

    // Bracket matching
    pub fn findMatchingBracket(self: *const Editor) ?usize {
        if (self.cursor.offset >= self.rope.len()) return null;

        const content = self.rope.slice(.{ .start = 0, .end = self.rope.len() }) catch return null;
        // Note: Rope owns this memory, don't free it

        const cursor_pos = self.cursor.offset;
        if (cursor_pos >= content.len) return null;

        const char_at_cursor = content[cursor_pos];

        // Check if cursor is on a bracket
        const bracket_pairs = [_]struct { open: u8, close: u8 }{
            .{ .open = '(', .close = ')' },
            .{ .open = '[', .close = ']' },
            .{ .open = '{', .close = '}' },
            .{ .open = '<', .close = '>' },
        };

        for (bracket_pairs) |pair| {
            if (char_at_cursor == pair.open) {
                return self.findClosingBracket(content, cursor_pos, pair.open, pair.close);
            } else if (char_at_cursor == pair.close) {
                return self.findOpeningBracket(content, cursor_pos, pair.open, pair.close);
            }
        }

        return null;
    }

    fn findClosingBracket(self: *const Editor, content: []const u8, start: usize, open: u8, close: u8) ?usize {
        _ = self;
        var depth: i32 = 1;
        var i = start + 1;

        while (i < content.len) : (i += 1) {
            if (content[i] == open) {
                depth += 1;
            } else if (content[i] == close) {
                depth -= 1;
                if (depth == 0) return i;
            }
        }

        return null;
    }

    fn findOpeningBracket(self: *const Editor, content: []const u8, start: usize, open: u8, close: u8) ?usize {
        _ = self;
        var depth: i32 = 1;
        var i: usize = start;

        while (i > 0) {
            i -= 1;
            if (content[i] == close) {
                depth += 1;
            } else if (content[i] == open) {
                depth -= 1;
                if (depth == 0) return i;
            }
        }

        return null;
    }

    // Multi-cursor operations
    fn addCursorBelow(self: *Editor) !void {
        const current_line = self.getCurrentLine();
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        // Find the start of the next line
        var line: usize = 0;
        var offset: usize = 0;
        while (offset < content.len and line <= current_line + 1) {
            if (content[offset] == '\n') {
                line += 1;
                if (line == current_line + 1) {
                    const new_pos = Position{ .offset = offset + 1 };
                    try self.cursors.append(new_pos);
                    self.multi_cursor_mode = true;
                    return;
                }
            }
            offset += 1;
        }
    }

    fn addCursorAbove(self: *Editor) !void {
        if (self.getCurrentLine() == 0) return;

        const current_line = self.getCurrentLine();
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        // Find the start of the previous line
        var line: usize = 0;
        var offset: usize = 0;
        var prev_line_start: usize = 0;

        while (offset < content.len) {
            if (content[offset] == '\n') {
                line += 1;
                if (line == current_line) {
                    const new_pos = Position{ .offset = prev_line_start };
                    try self.cursors.append(new_pos);
                    self.multi_cursor_mode = true;
                    return;
                }
                prev_line_start = offset + 1;
            }
            offset += 1;
        }
    }

    fn addCursorAtNextMatch(self: *Editor) !void {
        // Find the word at cursor and add cursor at next occurrence
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        // Note: Rope owns this memory, don't free it

        const word = self.getWordAtCursor(content) orelse return;

        // Find next occurrence after current cursor
        const search_start = self.cursor.offset + 1;
        if (std.mem.indexOf(u8, content[search_start..], word)) |rel_pos| {
            const abs_pos = search_start + rel_pos;
            const new_pos = Position{ .offset = abs_pos };
            try self.cursors.append(new_pos);
            self.multi_cursor_mode = true;
        }
    }

    fn getWordAtCursor(self: *const Editor, content: []const u8) ?[]const u8 {
        if (self.cursor.offset >= content.len) return null;

        var start = self.cursor.offset;
        var end = self.cursor.offset;

        // Find word start
        while (start > 0 and isWordChar(content[start - 1])) {
            start -= 1;
        }

        // Find word end
        while (end < content.len and isWordChar(content[end])) {
            end += 1;
        }

        if (start == end) return null;
        return content[start..end];
    }

    fn isWordChar(ch: u8) bool {
        return (ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or
            ch == '_';
    }

    fn removeLastCursor(self: *Editor) void {
        if (self.cursors.items.len > 0) {
            _ = self.cursors.pop();
            if (self.cursors.items.len == 0) {
                self.multi_cursor_mode = false;
            }
        }
    }

    fn toggleMultiCursor(self: *Editor) void {
        self.multi_cursor_mode = !self.multi_cursor_mode;
        if (!self.multi_cursor_mode) {
            self.cursors.clearRetainingCapacity();
        }
    }

    pub fn getCursors(self: *const Editor) []const Position {
        if (self.multi_cursor_mode and self.cursors.items.len > 0) {
            return self.cursors.items;
        }
        return &.{};
    }

    // === Multi-Cursor Operations ===

    /// Select next occurrence of current word (gd key binding)
    pub fn selectNextOccurrence(self: *Editor) !void {
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });

        // Get word at cursor if we don't have one already
        if (self.selected_word == null) {
            const word = self.getWordAtCursor(content) orelse return;
            self.selected_word = try self.allocator.dupe(u8, word);

            // Add cursor at current position
            try self.cursors.append(self.allocator, Position{ .offset = self.cursor.offset });
            self.multi_cursor_mode = true;
        }

        const word = self.selected_word.?;

        // Find next occurrence after the last cursor
        const last_cursor_offset = if (self.cursors.items.len > 0)
            self.cursors.items[self.cursors.items.len - 1].offset
        else
            self.cursor.offset;

        // Search from position after last cursor
        var search_start = last_cursor_offset + 1;
        while (search_start < content.len) {
            if (search_start + word.len > content.len) break;

            if (std.mem.eql(u8, content[search_start..search_start + word.len], word)) {
                // Check word boundaries
                const is_start_boundary = search_start == 0 or !isWordChar(content[search_start - 1]);
                const is_end_boundary = search_start + word.len >= content.len or
                    !isWordChar(content[search_start + word.len]);

                if (is_start_boundary and is_end_boundary) {
                    // Found next occurrence
                    try self.cursors.append(self.allocator, Position{ .offset = search_start });
                    self.cursor.offset = search_start; // Move main cursor to new location
                    return;
                }
            }
            search_start += 1;
        }

        // Wrap around to beginning
        search_start = 0;
        while (search_start < last_cursor_offset) {
            if (search_start + word.len > content.len) break;

            if (std.mem.eql(u8, content[search_start..search_start + word.len], word)) {
                // Check word boundaries
                const is_start_boundary = search_start == 0 or !isWordChar(content[search_start - 1]);
                const is_end_boundary = search_start + word.len >= content.len or
                    !isWordChar(content[search_start + word.len]);

                if (is_start_boundary and is_end_boundary) {
                    // Found occurrence (wrapped)
                    try self.cursors.append(self.allocator, Position{ .offset = search_start });
                    self.cursor.offset = search_start;
                    return;
                }
            }
            search_start += 1;
        }
    }

    /// Select all occurrences of current word (<leader>a key binding)
    pub fn selectAllOccurrences(self: *Editor) !void {
        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });

        // Get word at cursor
        const word = self.getWordAtCursor(content) orelse return;

        // Store selected word
        if (self.selected_word) |old_word| {
            self.allocator.free(old_word);
        }
        self.selected_word = try self.allocator.dupe(u8, word);

        // Clear existing cursors
        self.cursors.clearRetainingCapacity();

        // Find all occurrences
        var search_offset: usize = 0;
        while (search_offset < content.len) {
            if (search_offset + word.len > content.len) break;

            if (std.mem.eql(u8, content[search_offset..search_offset + word.len], word)) {
                // Check word boundaries
                const is_start_boundary = search_offset == 0 or !isWordChar(content[search_offset - 1]);
                const is_end_boundary = search_offset + word.len >= content.len or
                    !isWordChar(content[search_offset + word.len]);

                if (is_start_boundary and is_end_boundary) {
                    try self.cursors.append(self.allocator, Position{ .offset = search_offset });
                }
            }
            search_offset += 1;
        }

        if (self.cursors.items.len > 0) {
            self.multi_cursor_mode = true;
            // Keep main cursor at current position
        }
    }

    /// Exit multi-cursor mode
    pub fn exitMultiCursorMode(self: *Editor) void {
        self.multi_cursor_mode = false;
        self.cursors.clearRetainingCapacity();
        if (self.selected_word) |word| {
            self.allocator.free(word);
            self.selected_word = null;
        }
    }

    /// Insert character at all cursor positions
    pub fn insertCharMultiCursor(self: *Editor, c: u21) !void {
        if (!self.multi_cursor_mode or self.cursors.items.len == 0) {
            return self.insertChar(c);
        }

        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(c, &buf);
        const char_str = buf[0..len];

        // Insert at all cursors (from back to front to preserve offsets)
        var i: usize = self.cursors.items.len;
        var offset_adjustment: usize = 0;

        while (i > 0) {
            i -= 1;
            const cursor_offset = self.cursors.items[i].offset + offset_adjustment;
            try self.rope.insert(cursor_offset, char_str);
            self.cursors.items[i].offset = cursor_offset + len;
            offset_adjustment += len;
        }

        // Update main cursor
        if (self.cursors.items.len > 0) {
            self.cursor.offset = self.cursors.items[self.cursors.items.len - 1].offset;
        }
    }

    /// Delete character at all cursor positions
    pub fn deleteCharMultiCursor(self: *Editor) !void {
        if (!self.multi_cursor_mode or self.cursors.items.len == 0) {
            return self.deleteCharAtCursor();
        }

        // Sort cursors by offset (descending) to maintain offsets during deletion
        std.mem.sort(Position, self.cursors.items, {}, struct {
            fn lessThan(_: void, a: Position, b: Position) bool {
                return a.offset > b.offset;
            }
        }.lessThan);

        // Delete at all cursors (from back to front)
        for (self.cursors.items) |*cursor_pos| {
            if (cursor_pos.offset >= self.rope.len()) continue;

            const slice = try self.rope.slice(.{ .start = cursor_pos.offset, .end = self.rope.len() });
            var char_len: usize = 1;
            while (char_len < slice.len and (slice[char_len] & 0xC0) == 0x80) : (char_len += 1) {}

            try self.rope.delete(cursor_pos.offset, char_len);
        }

        // Update main cursor
        if (self.cursors.items.len > 0) {
            self.cursor.offset = self.cursors.items[self.cursors.items.len - 1].offset;
        }
    }

    /// Move all cursors left
    pub fn moveCursorsLeft(self: *Editor) void {
        for (self.cursors.items) |*cursor_pos| {
            cursor_pos.moveLeft(&self.rope);
        }
        if (self.cursors.items.len > 0) {
            self.cursor = self.cursors.items[self.cursors.items.len - 1];
        }
    }

    /// Move all cursors right
    pub fn moveCursorsRight(self: *Editor) void {
        for (self.cursors.items) |*cursor_pos| {
            cursor_pos.moveRight(&self.rope);
        }
        if (self.cursors.items.len > 0) {
            self.cursor = self.cursors.items[self.cursors.items.len - 1];
        }
    }

    // === Undo/Redo System ===

    /// Save current state to undo stack (call before making changes)
    pub fn saveUndoState(self: *Editor, description: []const u8) !void {
        try self.undo_stack.recordUndo(&self.rope, self.cursor.offset, description);
    }

    /// Undo last change
    pub fn undo(self: *Editor) !void {
        const snapshot = self.undo_stack.undo() orelse return;

        // Replace rope content
        const rope_len = self.rope.len();
        if (rope_len > 0) {
            try self.rope.delete(0, rope_len);
        }
        try self.rope.insert(0, snapshot.content);
        self.cursor.offset = snapshot.cursor_offset;
        self.cursor.desired_column = null;
    }

    /// Redo last undone change
    pub fn redo(self: *Editor) !void {
        const snapshot = self.undo_stack.redo() orelse return;

        // Replace rope content
        const rope_len = self.rope.len();
        if (rope_len > 0) {
            try self.rope.delete(0, rope_len);
        }
        try self.rope.insert(0, snapshot.content);
        self.cursor.offset = snapshot.cursor_offset;
        self.cursor.desired_column = null;
    }
};

test "editor basic operations" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Insert some text
    try editor.rope.insert(0, "Hello, world!\nThis is a test.");

    // Test movement
    try editor.handleKey('l');
    try std.testing.expectEqual(@as(usize, 1), editor.cursor.offset);

    try editor.handleKey('w');
    try std.testing.expect(editor.cursor.offset > 1);

    try editor.handleKey('0');
    try std.testing.expectEqual(@as(usize, 0), editor.cursor.offset);

    // Test mode switching
    try editor.handleKey('i');
    try std.testing.expect(editor.mode == .insert);

    try editor.handleKey('a');
    try std.testing.expect(editor.rope.len() > 30);

    try editor.handleKey(0x1B); // ESC
    try std.testing.expect(editor.mode == .normal);
}

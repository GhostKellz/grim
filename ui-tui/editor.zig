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

    pub const Mode = enum {
        normal,
        insert,
        visual,
        command,
    };

    pub const Position = struct {
        offset: usize = 0, // Byte offset in the rope

        pub fn moveLeft(self: *Position, rope: *core.Rope) void {
            if (self.offset == 0) return;

            // Move to previous UTF-8 character boundary
            const slice = rope.slice(.{ .start = 0, .end = self.offset }) catch return;
            var i = self.offset - 1;
            while (i > 0 and (slice[i] & 0xC0) == 0x80) : (i -= 1) {}
            self.offset = i;
        }

        pub fn moveRight(self: *Position, rope: *core.Rope) void {
            if (self.offset >= rope.len()) return;

            // Move to next UTF-8 character boundary
            const slice = rope.slice(.{ .start = self.offset, .end = rope.len() }) catch return;
            var i: usize = 1;
            while (i < slice.len and (slice[i] & 0xC0) == 0x80) : (i += 1) {}
            self.offset = @min(self.offset + i, rope.len());
        }

        pub fn moveToLineStart(self: *Position, rope: *core.Rope) void {
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
            .cursors = .empty,
            .multi_cursor_mode = false,
            .pending_key = null,
            .rename_buffer = null,
            .rename_active = false,
            .yank_buffer = null,
            .yank_linewise = false,
            .search_pattern = null,
            .last_search_forward = true,
        };
    }

    pub fn deinit(self: *Editor) void {
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
        self.cursors.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn loadFile(self: *Editor, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);

        _ = try file.read(content);
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
        // Save current column position
        const current_col = self.getColumnPosition();

        // Move to previous line
        self.cursor.moveToLineStart(&self.rope);
        if (self.cursor.offset > 0) {
            self.cursor.offset -= 1; // Move past previous newline
            self.cursor.moveToLineStart(&self.rope);

            // Restore column position
            self.moveToColumn(current_col);
        }
    }

    pub fn moveCursorDown(self: *Editor) void {
        // Save current column position
        const current_col = self.getColumnPosition();

        // Move to next line
        self.cursor.moveToLineEnd(&self.rope);
        if (self.cursor.offset < self.rope.len()) {
            self.cursor.offset += 1; // Move past newline

            // Restore column position
            self.moveToColumn(current_col);
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
    }

    pub fn searchForward(self: *Editor) !bool {
        const pattern = self.search_pattern orelse return false;
        if (pattern.len == 0) return false;

        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });
        const search_start = self.cursor.offset + 1;

        if (search_start >= content.len) {
            // Wrap around to beginning
            if (std.mem.indexOf(u8, content[0..], pattern)) |pos| {
                self.cursor.offset = pos;
                self.last_search_forward = true;
                return true;
            }
            return false;
        }

        // Search from current position to end
        if (std.mem.indexOf(u8, content[search_start..], pattern)) |rel_pos| {
            self.cursor.offset = search_start + rel_pos;
            self.last_search_forward = true;
            return true;
        }

        // Wrap around to beginning
        if (std.mem.indexOf(u8, content[0..self.cursor.offset], pattern)) |pos| {
            self.cursor.offset = pos;
            self.last_search_forward = true;
            return true;
        }

        return false;
    }

    pub fn searchBackward(self: *Editor) !bool {
        const pattern = self.search_pattern orelse return false;
        if (pattern.len == 0) return false;

        const content = try self.rope.slice(.{ .start = 0, .end = self.rope.len() });

        if (self.cursor.offset == 0) {
            // Wrap around to end
            if (std.mem.lastIndexOf(u8, content, pattern)) |pos| {
                self.cursor.offset = pos;
                self.last_search_forward = false;
                return true;
            }
            return false;
        }

        // Search from beginning to current position (exclusive)
        if (std.mem.lastIndexOf(u8, content[0..self.cursor.offset], pattern)) |pos| {
            self.cursor.offset = pos;
            self.last_search_forward = false;
            return true;
        }

        // Wrap around to end
        if (std.mem.lastIndexOf(u8, content[self.cursor.offset..], pattern)) |rel_pos| {
            self.cursor.offset = self.cursor.offset + rel_pos;
            self.last_search_forward = false;
            return true;
        }

        return false;
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

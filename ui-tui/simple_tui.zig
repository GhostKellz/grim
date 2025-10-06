const std = @import("std");
const syntax = @import("syntax");
const lsp = @import("lsp");
const core = @import("core");
const Editor = @import("editor.zig").Editor;
const Theme = @import("theme.zig").Theme;

pub const SimpleTUI = struct {
    allocator: std.mem.Allocator,
    editor: Editor,
    running: bool,
    stdin: std.fs.File,
    stdout: std.fs.File,
    highlight_cache: []syntax.HighlightRange,
    highlight_dirty: bool,
    highlight_error: ?[]u8,
    highlight_error_flash: bool,
    highlight_error_flash_state: bool,
    highlight_error_logged: bool,
    lsp_manager: lsp.ServerManager,
    hover_popup: ?[]const u8,
    pending_key: ?u8,
    // Git integration
    git: core.Git,
    git_blame_visible: bool,
    // Fuzzy finder
    file_picker: ?*core.FilePicker,
    // Harpoon
    harpoon: core.Harpoon,
    // Tree-sitter features
    syntax_features: syntax.Features,
    fold_regions: []syntax.FoldRegion,
    // Incremental selection
    selection_start: ?usize,
    selection_end: ?usize,
    // Theme
    theme: Theme,

    pub fn init(allocator: std.mem.Allocator) !*SimpleTUI {
        const self = try allocator.create(SimpleTUI);
        self.* = .{
            .allocator = allocator,
            .editor = try Editor.init(allocator),
            .running = true,
            .stdin = std.fs.File.stdin(),
            .stdout = std.fs.File.stdout(),
            .highlight_cache = &.{},
            .highlight_dirty = true,
            .highlight_error = null,
            .highlight_error_flash = false,
            .highlight_error_flash_state = false,
            .highlight_error_logged = false,
            .lsp_manager = lsp.ServerManager.init(allocator),
            .hover_popup = null,
            .pending_key = null,
            .git = core.Git.init(allocator),
            .git_blame_visible = false,
            .file_picker = null,
            .harpoon = core.Harpoon.init(allocator),
            .syntax_features = syntax.Features.init(allocator),
            .fold_regions = &.{},
            .selection_start = null,
            .selection_end = null,
            .theme = Theme.loadDefault(allocator) catch |err| blk: {
                std.log.warn("Failed to load theme: {}, using built-in fallback", .{err});
                break :blk Theme.ghostHackerBlue();
            },
        };
        return self;
    }

    pub fn deinit(self: *SimpleTUI) void {
        if (self.highlight_cache.len > 0) {
            self.allocator.free(self.highlight_cache);
        }
        if (self.highlight_error) |msg| {
            self.allocator.free(msg);
        }
        if (self.hover_popup) |popup| {
            self.allocator.free(popup);
        }
        if (self.file_picker) |picker| {
            picker.deinit();
            self.allocator.destroy(picker);
        }
        if (self.fold_regions.len > 0) {
            self.allocator.free(self.fold_regions);
        }
        self.git.deinit();
        self.harpoon.deinit();
        self.lsp_manager.deinit();
        self.editor.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *SimpleTUI) !void {
        try self.enableRawMode();
        defer self.disableRawMode() catch {};

        try self.clearScreen();
        try self.showCursor();

        while (self.running) {
            try self.render();
            try self.handleInput();
        }
    }

    pub fn loadFile(self: *SimpleTUI, path: []const u8) !void {
        try self.editor.loadFile(path);
        self.markHighlightsDirty();

        // Auto-spawn LSP server for this file type
        if (self.lsp_manager.autoSpawn(path) catch null) |server| {
            // Set up response callbacks for this server
            server.client.setResponseCallback(.{
                .ctx = self,
                .onHover = onLspHoverResponse,
                .onDefinition = onLspDefinitionResponse,
            });
        }

        // Detect git repository
        const dir_path = std.fs.path.dirname(path) orelse ".";
        _ = self.git.detectRepository(dir_path) catch false;
    }

    fn onLspHoverResponse(ctx: *anyopaque, response: lsp.HoverResponse) void {
        const self: *SimpleTUI = @ptrCast(@alignCast(ctx));

        // Free old popup
        if (self.hover_popup) |old| {
            self.allocator.free(old);
        }

        // Display hover content
        if (response.contents.len > 0) {
            self.hover_popup = std.fmt.allocPrint(
                self.allocator,
                "Hover: {s}",
                .{response.contents},
            ) catch |err| {
                std.log.warn("Failed to format hover popup: {}", .{err});
                self.hover_popup = null;
                return;
            };
        } else {
            self.hover_popup = std.fmt.allocPrint(
                self.allocator,
                "Hover: (no info available)",
                .{},
            ) catch null;
        }
    }

    fn onLspDefinitionResponse(ctx: *anyopaque, response: lsp.DefinitionResponse) void {
        const self: *SimpleTUI = @ptrCast(@alignCast(ctx));

        std.log.info("Definition: {s} at {d}:{d}", .{ response.uri, response.line, response.character });

        // TODO: Actually jump to the definition location
        // For now, just log it
        _ = self;
    }

    fn lspHover(self: *SimpleTUI) !void {
        const filepath = self.editor.current_filename orelse return;

        // Get or spawn LSP server for this file
        const server = (try self.lsp_manager.getOrSpawn(filepath)) orelse {
            std.log.warn("No LSP server available for {s}", .{filepath});
            return;
        };

        // Ensure callbacks are set
        server.client.setResponseCallback(.{
            .ctx = self,
            .onHover = onLspHoverResponse,
            .onDefinition = onLspDefinitionResponse,
        });

        const line = self.getCursorLine();
        const col = self.getCursorColumn();

        // Send hover request
        const uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{filepath});
        defer self.allocator.free(uri);

        const request_id = try server.client.requestHover(uri, @intCast(line), @intCast(col));

        std.log.info("LSP hover requested at {d}:{d} (request_id: {d})", .{ line, col, request_id });

        // Try to poll for response (will trigger callbacks)
        server.client.poll() catch |err| {
            std.log.warn("LSP poll failed: {}", .{err});
        };
    }

    fn lspGotoDefinition(self: *SimpleTUI) !void {
        const filepath = self.editor.current_filename orelse return;

        // Get or spawn LSP server for this file
        const server = (try self.lsp_manager.getOrSpawn(filepath)) orelse {
            std.log.warn("No LSP server available for {s}", .{filepath});
            return;
        };

        // Ensure callbacks are set
        server.client.setResponseCallback(.{
            .ctx = self,
            .onHover = onLspHoverResponse,
            .onDefinition = onLspDefinitionResponse,
        });

        const line = self.getCursorLine();
        const col = self.getCursorColumn();

        // Send definition request
        const uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{filepath});
        defer self.allocator.free(uri);

        const request_id = try server.client.requestDefinition(uri, @intCast(line), @intCast(col));

        std.log.info("LSP goto-definition requested at {d}:{d} (request_id: {d})", .{ line, col, request_id });

        // Try to poll for response (will trigger callbacks)
        server.client.poll() catch |err| {
            std.log.warn("LSP poll failed: {}", .{err});
        };
    }

    // Harpoon functions
    fn harpoonPin(self: *SimpleTUI, slot: usize) !void {
        const filepath = self.editor.current_filename orelse return;
        const line = self.getCursorLine();
        const col = self.getCursorColumn();
        try self.harpoon.pin(slot, filepath, line, col);
        std.log.info("Pinned {s} to slot {d}", .{ filepath, slot });
    }

    fn harpoonJump(self: *SimpleTUI, slot: usize) !void {
        if (self.harpoon.get(slot)) |pinned| {
            try self.loadFile(pinned.path);
            // TODO: Restore cursor position
            std.log.info("Jumped to slot {d}: {s}", .{ slot, pinned.path });
        }
    }

    // Git functions
    fn toggleGitBlame(self: *SimpleTUI) void {
        self.git_blame_visible = !self.git_blame_visible;
    }

    fn gitNextHunk(_: *SimpleTUI) void {
        // TODO: Implement hunk navigation
        std.log.info("Next git hunk", .{});
    }

    fn gitPrevHunk(_: *SimpleTUI) void {
        // TODO: Implement hunk navigation
        std.log.info("Previous git hunk", .{});
    }

    fn gitStageFile(self: *SimpleTUI) !void {
        const filepath = self.editor.current_filename orelse return;
        try self.git.stageFile(filepath);
        std.log.info("Staged: {s}", .{filepath});
    }

    fn gitUnstageFile(self: *SimpleTUI) !void {
        const filepath = self.editor.current_filename orelse return;
        try self.git.unstageFile(filepath);
        std.log.info("Unstaged: {s}", .{filepath});
    }

    fn gitDiscardChanges(self: *SimpleTUI) !void {
        const filepath = self.editor.current_filename orelse return;
        try self.git.discardChanges(filepath);
        std.log.info("Discarded changes: {s}", .{filepath});
        // Reload file
        try self.loadFile(filepath);
    }

    // Folding
    fn updateFoldRegions(self: *SimpleTUI) !void {
        if (self.fold_regions.len > 0) {
            self.allocator.free(self.fold_regions);
        }

        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        defer self.allocator.free(content);

        self.fold_regions = try self.syntax_features.getFoldRegionsSimple(content);
    }

    fn toggleFoldAtCursor(self: *SimpleTUI) !void {
        const cursor_line = self.getCursorLine();

        // Find fold region at cursor
        for (self.fold_regions) |*region| {
            if (region.start_line == cursor_line) {
                region.folded = !region.folded;
                std.log.info("Toggled fold at line {d}", .{cursor_line});
                return;
            }
        }

        std.log.info("No fold region at line {d}", .{cursor_line});
    }

    // Incremental selection
    fn expandSelection(self: *SimpleTUI) !void {
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        defer self.allocator.free(content);

        const current_start = self.selection_start orelse self.editor.cursor.offset;
        const current_end = self.selection_end orelse self.editor.cursor.offset;

        if (try self.syntax_features.expandSelection(content, current_start, current_end)) |range| {
            self.selection_start = range.start_byte;
            self.selection_end = range.end_byte;
            self.editor.mode = .visual;
            std.log.info("Expanded selection to {d}-{d}", .{ range.start_byte, range.end_byte });
        } else {
            std.log.info("Cannot expand selection further", .{});
        }
    }

    fn shrinkSelection(self: *SimpleTUI) !void {
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        defer self.allocator.free(content);

        const current_start = self.selection_start orelse self.editor.cursor.offset;
        const current_end = self.selection_end orelse self.editor.cursor.offset;

        if (try self.syntax_features.shrinkSelection(content, current_start, current_end)) |range| {
            self.selection_start = range.start_byte;
            self.selection_end = range.end_byte;
            std.log.info("Shrunk selection to {d}-{d}", .{ range.start_byte, range.end_byte });
        } else {
            // Can't shrink further, exit visual mode
            self.selection_start = null;
            self.selection_end = null;
            self.editor.mode = .normal;
            std.log.info("Exited visual mode", .{});
        }
    }

    // Fuzzy finder
    fn openFilePicker(self: *SimpleTUI) !void {
        if (self.file_picker) |picker| {
            picker.deinit();
            self.allocator.destroy(picker);
        }

        const picker = try self.allocator.create(core.FilePicker);
        picker.* = core.FilePicker.init(self.allocator);
        self.file_picker = picker;

        // Find files in current directory
        try picker.finder.findFiles(".", 5); // Max depth 5
        try picker.updateQuery(""); // Show all files initially

        std.log.info("File picker opened", .{});
        // TODO: Enter file picker mode
    }

    fn render(self: *SimpleTUI) !void {
        // Get terminal size (simplified)
        const width = 80;
        const height = 24;

        try self.clearScreen();
        try self.setCursor(1, 1);

        self.refreshHighlights();

        if (self.highlight_error_flash) {
            self.highlight_error_flash_state = !self.highlight_error_flash_state;
        } else {
            self.highlight_error_flash_state = false;
        }

        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        defer self.allocator.free(content);

        // Get git blame if visible
        const blame_info = if (self.git_blame_visible and self.editor.current_filename != null)
            self.git.getBlame(self.editor.current_filename.?) catch null
        else
            null;

        const gutter_width: usize = if (self.git_blame_visible) 20 else 6;
        const content_width: usize = if (width > gutter_width) width - gutter_width else 0;

        var line_start: usize = 0;
        var logical_line: usize = 0;

        while (logical_line < height - 2 and line_start <= content.len) {
            const remaining = content[line_start..];
            const rel_newline = std.mem.indexOfScalar(u8, remaining, '\n');
            const line_end = if (rel_newline) |rel| line_start + rel else content.len;
            const line_slice = content[line_start..line_end];

            // Git blame gutter (if enabled)
            if (self.git_blame_visible) {
                if (blame_info) |blame| {
                    if (logical_line < blame.len) {
                        const blame_line = blame[logical_line];
                        // Show first 7 chars of commit hash
                        const hash_short = if (blame_line.commit_hash.len >= 7)
                            blame_line.commit_hash[0..7]
                        else
                            blame_line.commit_hash;

                        try self.setColor(90, 0); // Dim gray
                        var blame_buf: [16]u8 = undefined;
                        const blame_str = try std.fmt.bufPrint(&blame_buf, "{s:7} ", .{hash_short});
                        try self.stdout.writeAll(blame_str);
                        try self.resetColor();
                    } else {
                        try self.stdout.writeAll("        ");
                    }
                } else {
                    try self.stdout.writeAll("        ");
                }
            }

            // Line numbers
            var line_buf: [16]u8 = undefined;
            const line_str = try std.fmt.bufPrint(&line_buf, "{d:4}", .{logical_line + 1});
            try self.stdout.writeAll(line_str);

            // Fold indicators
            const fold_indicator = self.getFoldIndicator(logical_line);
            try self.stdout.writeAll(fold_indicator);
            try self.stdout.writeAll(" ");

            if (content_width > 0) {
                try self.renderHighlightedLine(line_slice, logical_line, content_width);
            }

            try self.stdout.writeAll("\r\n");

            line_start = if (rel_newline) |_| line_end + 1 else content.len + 1;
            logical_line += 1;
        }

        while (logical_line < height - 2) : (logical_line += 1) {
            try self.stdout.writeAll("~\r\n");
        }

        // Hover popup (if active)
        if (self.hover_popup) |popup_text| {
            const popup_line = if (height > 5) height - 4 else 1;
            try self.setCursor(popup_line, 1);
            try self.setColor(44, 97); // Blue background, white text
            var popup_buf: [256]u8 = undefined;
            const popup_display = if (popup_text.len > 70) popup_text[0..70] else popup_text;
            const popup_str = try std.fmt.bufPrint(&popup_buf, " LSP: {s} ", .{popup_display});
            try self.stdout.writeAll(popup_str);
            if (popup_text.len > 70) {
                try self.stdout.writeAll("...");
            }
            try self.resetColor();
        }

        // Status line
        try self.setCursor(height, 1);
        const flash_on = self.highlight_error_flash and self.highlight_error_flash_state;
        const status_bg: u8 = if (flash_on) 41 else 47; // Red flash or default white
        const status_fg: u8 = if (flash_on) 97 else 30; // Bright white or black text
        try self.setColor(status_bg, status_fg);

        const mode_str = switch (self.editor.mode) {
            .normal => "NORMAL",
            .insert => "INSERT",
            .visual => "VISUAL",
            .command => "COMMAND",
        };

        const cursor_line = self.getCursorLine();
        const cursor_col = self.getCursorColumn();

        const language = self.editor.getLanguageName();

        // Get git info for status line
        const git_branch = if (self.git.repo_root != null)
            self.git.getCurrentBranch() catch null
        else
            null;

        const file_status = if (self.git.repo_root != null and self.editor.current_filename != null)
            self.git.getFileStatus(self.editor.current_filename.?) catch .unmodified
        else
            .unmodified;

        const status_char = switch (file_status) {
            .modified => "●",
            .added => "+",
            .deleted => "-",
            .untracked => "?",
            else => "",
        };

        var status_buf: [512]u8 = undefined;
        var status_len: usize = 0;

        // Build status line with git info
        if (git_branch) |branch| {
            const git_slice = try std.fmt.bufPrint(status_buf[status_len..], " {s} | {s}{s} | ", .{
                mode_str,
                branch,
                status_char,
            });
            status_len += git_slice.len;
        } else {
            const mode_slice = try std.fmt.bufPrint(status_buf[status_len..], " {s} | ", .{mode_str});
            status_len += mode_slice.len;
        }

        const base_slice = try std.fmt.bufPrint(status_buf[status_len..], "{d},{d} | {d} bytes | {s}", .{
            cursor_line + 1,
            cursor_col + 1,
            self.editor.rope.len(),
            language,
        });
        status_len += base_slice.len;

        // Show warning instead of error for highlight issues (less alarming)
        if (self.highlight_error) |err_msg| {
            const max_err_len: usize = 40;
            const trimmed_len = if (err_msg.len > max_err_len) max_err_len else err_msg.len;
            // Show as warning, not error
            const warn_slice = try std.fmt.bufPrint(status_buf[status_len..], " | ⚠ {s}", .{err_msg[0..trimmed_len]});
            status_len += warn_slice.len;
            if (err_msg.len > max_err_len) {
                const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "...", .{});
                status_len += ellipsis_slice.len;
            }
        }

        const status_slice = status_buf[0..status_len];

        // Pad with spaces to fill width
        const padding_len = if (status_slice.len < width) width - status_slice.len else 0;
        var final_status_buf: [512]u8 = undefined;
        @memcpy(final_status_buf[0..status_slice.len], status_slice);
        if (padding_len > 0) {
            @memset(final_status_buf[status_slice.len .. status_slice.len + padding_len], ' ');
        }
        const status = final_status_buf[0 .. status_slice.len + padding_len];

        try self.stdout.writeAll(status[0..@min(status.len, width)]);
        try self.resetColor();

        // Position cursor
        const screen_line = @min(cursor_line + 1, height - 2);
        const screen_col = cursor_col + 6; // Account for line numbers
        try self.setCursor(screen_line, screen_col);

        // Flush stdout
    }

    fn handleInput(self: *SimpleTUI) !void {
        var buf: [8]u8 = undefined;
        const n = try self.stdin.read(buf[0..1]); // Read one byte at a time
        if (n == 0) return;

        var key_bytes: [4]u8 = undefined;
        key_bytes[0] = buf[0];
        var key_len: usize = 1;

        // Handle escape sequences (simplified - no timeout)
        if (buf[0] == 27) { // ESC
            // Try to read more bytes for escape sequences
            const next_n = self.stdin.read(buf[1..2]) catch 0;
            if (next_n > 0) {
                key_bytes[1] = buf[1];
                key_len = 2;

                if (buf[1] == '[') {
                    // Arrow keys and other sequences
                    const third_n = self.stdin.read(buf[2..3]) catch 0;
                    if (third_n > 0) {
                        key_bytes[2] = buf[2];
                        key_len = 3;
                    }
                }
            }
        }

        try self.processKeyInput(key_bytes[0..key_len]);
    }

    fn processKeyInput(self: *SimpleTUI, key_bytes: []const u8) !void {
        if (key_bytes.len == 1) {
            const key = key_bytes[0];

            // Global commands (work in any mode)
            switch (key) {
                17 => { // Ctrl+Q
                    self.running = false;
                    return;
                },
                else => {},
            }

            // Mode-specific commands
            switch (self.editor.mode) {
                .normal => try self.handleNormalMode(key),
                .insert => try self.handleInsertMode(key),
                .visual => try self.handleVisualMode(key),
                .command => try self.handleCommandMode(key),
            }
        } else if (key_bytes.len == 3 and key_bytes[0] == 27 and key_bytes[1] == '[') {
            // Arrow keys
            switch (key_bytes[2]) {
                'A' => self.editor.moveCursorUp(), // Up arrow
                'B' => self.editor.moveCursorDown(), // Down arrow
                'C' => self.editor.moveCursorRight(), // Right arrow
                'D' => self.editor.moveCursorLeft(), // Left arrow
                else => {},
            }
        }
    }

    fn handleNormalMode(self: *SimpleTUI, key: u8) !void {
        // Handle pending key sequences (e.g., "gd" for goto-definition)
        if (self.pending_key) |prev_key| {
            defer self.pending_key = null;

            if (prev_key == 'g' and key == 'd') {
                // gd -> goto-definition
                try self.lspGotoDefinition();
                return;
            } else if (prev_key == 'g' and key == 'g') {
                // gg -> goto top
                self.editor.cursor.offset = 0;
                return;
            } else if (prev_key == ' ') {
                // Leader key mappings (space)
                switch (key) {
                    'f' => try self.openFilePicker(), // <leader>f -> file picker
                    'g' => self.toggleGitBlame(), // <leader>g -> toggle git blame
                    's' => try self.gitStageFile(), // <leader>s -> stage file
                    'u' => try self.gitUnstageFile(), // <leader>u -> unstage file
                    'd' => try self.gitDiscardChanges(), // <leader>d -> discard changes
                    '1' => try self.harpoonPin(0), // <leader>1 -> pin to slot 1
                    '2' => try self.harpoonPin(1),
                    '3' => try self.harpoonPin(2),
                    '4' => try self.harpoonPin(3),
                    '5' => try self.harpoonPin(4),
                    else => {},
                }
                return;
            } else if (prev_key == ']') {
                // ] prefix mappings
                if (key == 'h') {
                    self.gitNextHunk(); // ]h -> next hunk
                    return;
                }
            } else if (prev_key == '[') {
                // [ prefix mappings
                if (key == 'h') {
                    self.gitPrevHunk(); // [h -> prev hunk
                    return;
                }
            } else if (prev_key == 'z') {
                // z prefix mappings (folding)
                switch (key) {
                    'a' => try self.toggleFoldAtCursor(), // za -> toggle fold
                    'u' => try self.updateFoldRegions(), // zu -> update fold regions
                    else => {},
                }
                return;
            }
            // Fall through for other combinations
        }

        switch (key) {
            27 => {}, // ESC in normal mode - already in normal
            'h' => self.editor.moveCursorLeft(),
            'j' => self.editor.moveCursorDown(),
            'k' => self.editor.moveCursorUp(),
            'l' => self.editor.moveCursorRight(),
            'K' => try self.lspHover(), // LSP hover
            'z' => {
                // z prefix for folding
                self.pending_key = 'z';
            },
            'V' => try self.expandSelection(), // Shift+V -> expand selection
            'i' => self.editor.mode = .insert,
            'I' => {
                self.editor.moveCursorToLineStart();
                self.editor.mode = .insert;
            },
            'a' => {
                self.editor.moveCursorRight();
                self.editor.mode = .insert;
            },
            'A' => {
                self.editor.moveCursorToLineEnd();
                self.editor.mode = .insert;
            },
            'o' => {
                try self.editor.insertNewlineAfter();
                self.editor.mode = .insert;
            },
            'O' => {
                try self.editor.insertNewlineBefore();
                self.editor.mode = .insert;
            },
            'x' => try self.editor.deleteChar(),
            'w' => self.editor.moveWordForward(),
            'b' => self.editor.moveWordBackward(),
            '0' => self.editor.moveCursorToLineStart(),
            '$' => self.editor.moveCursorToLineEnd(),
            'g' => {
                // Set pending key for multi-key sequences (gg, gd)
                self.pending_key = 'g';
            },
            'G' => self.editor.moveCursorToEnd(),
            ' ' => {
                // Leader key (space)
                self.pending_key = ' ';
            },
            '[' => {
                // [ prefix for git hunk navigation
                self.pending_key = '[';
            },
            ']' => {
                // ] prefix for git hunk navigation
                self.pending_key = ']';
            },
            '1' => try self.harpoonJump(0), // Jump to harpoon slot 1
            '2' => try self.harpoonJump(1),
            '3' => try self.harpoonJump(2),
            '4' => try self.harpoonJump(3),
            '5' => try self.harpoonJump(4),
            ':' => self.editor.mode = .command,
            'v' => self.editor.mode = .visual,
            'q' => self.running = false, // Simple quit
            else => {}, // Ignore unhandled keys
        }
    }

    fn handleInsertMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.editor.mode = .normal, // ESC
            8, 127 => try self.editor.backspace(), // Backspace/Delete
            13 => try self.editor.insertChar('\n'), // Enter
            else => {
                if (key >= 32 and key < 127) { // Printable ASCII
                    try self.editor.insertChar(key);
                }
            },
        }
    }

    fn handleVisualMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => {
                // ESC -> exit visual mode
                self.selection_start = null;
                self.selection_end = null;
                self.editor.mode = .normal;
            },
            'h' => self.editor.moveCursorLeft(),
            'j' => self.editor.moveCursorDown(),
            'k' => self.editor.moveCursorUp(),
            'l' => self.editor.moveCursorRight(),
            'V' => try self.expandSelection(), // Shift+V -> expand selection
            'v' => try self.shrinkSelection(), // v -> shrink selection
            'd' => {
                // TODO: Delete selection
                self.selection_start = null;
                self.selection_end = null;
                self.editor.mode = .normal;
            },
            'y' => {
                // TODO: Yank selection
                self.selection_start = null;
                self.selection_end = null;
                self.editor.mode = .normal;
            },
            else => {},
        }
    }

    fn handleCommandMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.editor.mode = .normal, // ESC
            13 => { // Enter
                // TODO: Execute command
                self.editor.mode = .normal;
            },
            else => {
                // TODO: Build command string
            },
        }
    }

    fn enableRawMode(self: *SimpleTUI) !void {
        _ = self;
        // Platform-specific raw mode setup would go here
        // For now, just a placeholder
    }

    fn disableRawMode(self: *SimpleTUI) !void {
        _ = self;
        // Platform-specific raw mode cleanup would go here
    }

    fn clearScreen(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[2J");
    }

    fn setCursor(self: *SimpleTUI, row: usize, col: usize) !void {
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1B[{d};{d}H", .{ row, col });
        try self.stdout.writeAll(seq);
    }

    fn showCursor(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[?25h");
    }

    fn hideCursor(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[?25l");
    }

    fn setColor(self: *SimpleTUI, bg: u8, fg: u8) !void {
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1B[{d};{d}m", .{ bg, fg });
        try self.stdout.writeAll(seq);
    }

    fn resetColor(self: *SimpleTUI) !void {
        try self.stdout.writeAll("\x1B[0m");
    }

    fn getCursorLine(self: *SimpleTUI) usize {
        const content = self.editor.rope.slice(.{
            .start = 0,
            .end = self.editor.cursor.offset,
        }) catch return 0;

        var lines: usize = 0;
        for (content) |ch| {
            if (ch == '\n') lines += 1;
        }
        return lines;
    }

    fn getCursorColumn(self: *SimpleTUI) usize {
        const content = self.editor.rope.slice(.{
            .start = 0,
            .end = self.editor.cursor.offset,
        }) catch return 0;

        var col: usize = 0;
        for (content) |ch| {
            if (ch == '\n') {
                col = 0;
            } else {
                col += 1;
            }
        }
        return col;
    }

    fn markHighlightsDirty(self: *SimpleTUI) void {
        self.highlight_dirty = true;
        if (self.highlight_error) |msg| {
            self.allocator.free(msg);
            self.highlight_error = null;
        }
        self.highlight_error_flash = false;
        self.highlight_error_flash_state = false;
        self.highlight_error_logged = false;
    }

    fn refreshHighlights(self: *SimpleTUI) void {
        if (!self.highlight_dirty) return;

        // Free old cache
        if (self.highlight_cache.len > 0) {
            self.allocator.free(self.highlight_cache);
            self.highlight_cache = &.{};
        }

        // Try to get new highlights
        const new_highlights = self.editor.getSyntaxHighlights() catch |err| {
            // Store error message
            const err_msg = std.fmt.allocPrint(
                self.allocator,
                "Highlight error: {s}",
                .{@errorName(err)},
            ) catch return;

            if (self.highlight_error) |old_msg| {
                self.allocator.free(old_msg);
            }
            self.highlight_error = err_msg;
            self.highlight_error_flash = true;
            self.highlight_error_flash_state = false;
            if (!self.highlight_error_logged) {
                std.log.err("Highlight refresh failed: {s}", .{err_msg});
                self.highlight_error_logged = true;
            }
            return;
        };

        if (self.highlight_error) |old_msg| {
            self.allocator.free(old_msg);
            self.highlight_error = null;
        }
        self.highlight_error_flash = false;
        self.highlight_error_flash_state = false;
        self.highlight_error_logged = false;

        self.highlight_cache = new_highlights;
        self.highlight_dirty = false;
    }

    fn renderPlainLine(self: *SimpleTUI, line: []const u8, max_width: usize) !void {
        const display_len = @min(line.len, max_width);
        if (display_len > 0) {
            try self.stdout.writeAll(line[0..display_len]);
        }

        var remaining = max_width - display_len;
        while (remaining > 0) : (remaining -= 1) {
            try self.stdout.writeAll(" ");
        }
    }

    fn renderHighlightedLine(self: *SimpleTUI, line: []const u8, line_num: usize, max_width: usize) !void {
        if (max_width == 0) return;

        const line_len = line.len;
        if (self.highlight_cache.len == 0) {
            try self.renderPlainLine(line, max_width);
            return;
        }

        const Segment = struct {
            start: usize,
            end: usize,
            highlight_type: syntax.HighlightType,

            fn lessThan(lhs: @This(), rhs: @This()) bool {
                if (lhs.start == rhs.start) return lhs.end < rhs.end;
                return lhs.start < rhs.start;
            }
        };

        var segments = std.ArrayListUnmanaged(Segment){};
        defer segments.deinit(self.allocator);

        for (self.highlight_cache) |range| {
            if (line_num < range.start_line or line_num > range.end_line) continue;
            if (range.highlight_type == .none) continue;

            var start_col = if (range.start_line == line_num) range.start_col else 0;
            var end_col = if (range.end_line == line_num) range.end_col else line_len;

            if (start_col > line_len) start_col = line_len;
            if (end_col > line_len) end_col = line_len;
            if (end_col <= start_col) continue;

            segments.append(self.allocator, .{ .start = start_col, .end = end_col, .highlight_type = range.highlight_type }) catch |err| {
                if (err == error.OutOfMemory) {
                    std.log.warn("Highlight segment allocation failed; falling back to plain rendering", .{});
                    try self.renderPlainLine(line, max_width);
                    return;
                }
                return err;
            };
        }

        if (segments.items.len == 0) {
            try self.renderPlainLine(line, max_width);
            return;
        }

        var segs = segments.items;
        var i: usize = 0;
        while (i < segs.len) : (i += 1) {
            var j = i + 1;
            while (j < segs.len) : (j += 1) {
                if (Segment.lessThan(segs[j], segs[i])) {
                    const tmp = segs[i];
                    segs[i] = segs[j];
                    segs[j] = tmp;
                }
            }
        }

        var col: usize = 0;
        var written: usize = 0;
        var seg_idx: usize = 0;
        var color_active = false;
        var active_type: ?syntax.HighlightType = null;

        while (col < line_len and written < max_width) {
            while (seg_idx < segments.items.len and segments.items[seg_idx].end <= col) : (seg_idx += 1) {}

            var run_type: ?syntax.HighlightType = null;
            var run_end = line_len;

            if (seg_idx < segments.items.len) {
                const seg = segments.items[seg_idx];
                if (seg.start > col) {
                    run_end = seg.start;
                } else {
                    run_type = seg.highlight_type;
                    run_end = seg.end;
                }
            }

            if (run_end <= col) {
                col += 1;
                continue;
            }

            const remaining = max_width - written;
            if (run_end - col > remaining) {
                run_end = col + remaining;
            }

            if (run_type) |ht| {
                if (!color_active or active_type != ht) {
                    if (color_active) try self.resetColor();
                    var buf: [32]u8 = undefined;
                    const seq = try self.theme.getHighlightSequence(ht, &buf);
                    try self.stdout.writeAll(seq);
                    color_active = true;
                    active_type = ht;
                }
            } else if (color_active) {
                try self.resetColor();
                color_active = false;
                active_type = null;
            }

            if (run_end > col) {
                try self.stdout.writeAll(line[col..run_end]);
                written += run_end - col;
            }

            col = run_end;
        }

        if (color_active) {
            try self.resetColor();
        }

        while (written < max_width) : (written += 1) {
            try self.stdout.writeAll(" ");
        }
    }

    fn getFoldIndicator(self: *SimpleTUI, line_num: usize) []const u8 {
        // Check if this line starts a fold region
        for (self.editor.fold_regions) |region| {
            if (region.start_line == line_num) {
                return if (region.folded) "▶" else "▼";
            }
        }
        return " ";
    }
};

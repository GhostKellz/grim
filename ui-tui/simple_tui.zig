const std = @import("std");
const runtime = @import("runtime");
const syntax = @import("syntax");
const core = @import("core");
const theme_mod = @import("theme.zig");
const Editor = @import("editor.zig").Editor;
const editor_lsp_mod = @import("editor_lsp.zig");
const buffer_manager_mod = @import("buffer_manager.zig");
const phantom_buffer_manager_mod = @import("phantom_buffer_manager.zig");
const window_manager_mod = @import("window_manager.zig");
const buffer_picker_mod = @import("buffer_picker.zig");
const font_manager_mod = @import("font_manager.zig");
const file_tree_mod = @import("file_tree.zig");

/// Feature flag: Enable PhantomBuffer with undo/redo and multi-cursor support
/// Set to false to use legacy Editor-based buffers
const use_phantom_buffers = true;

pub const SimpleTUI = struct {
    allocator: std.mem.Allocator,
    editor: Editor,
    running: bool,
    stdin: std.fs.File,
    stdout: std.fs.File,
    theme_registry: theme_mod.ThemeRegistry,
    active_theme: theme_mod.Theme,
    plugin_manager: ?*runtime.PluginManager,
    editor_lsp: ?*editor_lsp_mod.EditorLSP,
    highlight_cache: []syntax.HighlightRange,
    highlight_dirty: bool,
    highlight_error: ?[]u8,
    highlight_error_flash: bool,
    highlight_error_flash_state: bool,
    highlight_error_logged: bool,
    command_buffer: std.ArrayList(u8),
    status_message: ?[]u8,
    plugin_cursor: ?*runtime.PluginAPI.EditorContext.CursorPosition,
    editor_context: ?*runtime.PluginAPI.EditorContext,
    current_buffer_id: runtime.PluginAPI.BufferId,
    next_buffer_id: runtime.PluginAPI.BufferId,
    completion_popup_active: bool,
    completion_selected_index: usize,
    completion_items: []editor_lsp_mod.Completion,
    completion_items_heap: bool,
    completion_prefix: std.ArrayList(u8),
    completion_anchor_offset: ?usize,
    completion_generation_seen: u64,
    completion_dirty: bool,
    // Signature help popup
    signature_help_active: bool,
    signature_help_last_offset: ?usize,
    // Code actions menu
    code_actions_active: bool,
    code_actions_selected: usize,
    // New integration components
    buffer_manager: ?*buffer_manager_mod.BufferManager,
    phantom_buffer_manager: ?*phantom_buffer_manager_mod.PhantomBufferManager,
    window_manager: ?*window_manager_mod.WindowManager,
    buffer_picker: ?*buffer_picker_mod.BufferPicker,
    buffer_picker_active: bool,
    window_command_pending: bool,
    // Font Manager for Nerd Font icons
    font_manager: font_manager_mod.FontManager,
    enable_nerd_fonts: bool,
    // PhantomBuffer mode flag (matches compile-time constant)
    using_phantom_buffers: bool,
    // Visual block mode
    visual_block_mode: bool,
    visual_block_start_line: usize,
    visual_block_start_column: usize,
    // Git integration
    git: core.Git,
    git_hunks: []core.Git.Hunk,
    git_status_active: bool,
    git_log_active: bool,
    git_selected_commit: usize,
    // Harpoon integration
    harpoon: core.Harpoon,
    harpoon_menu_active: bool,
    harpoon_selected_idx: usize,
    // File tree sidebar
    file_tree: ?*file_tree_mod.FileTree,
    file_tree_active: bool,
    file_tree_width: usize,
    // Vim key sequences (dd, yy, etc.)
    pending_vim_key: ?u8,
    // Leader key for custom keybindings (Space)
    leader_key_pending: bool,
    leader_key_timestamp: i64,
    leader_key_sequence: std.ArrayList(u8),
    // Terminal state
    original_termios: std.posix.termios,
    // Terminal size (dynamic)
    terminal_width: u16,
    terminal_height: u16,
    needs_resize: bool,
    // Viewport (scrolling)
    viewport_top_line: usize,
    viewport_left_col: usize,

    pub fn init(allocator: std.mem.Allocator) !*SimpleTUI {
        var command_buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer command_buffer.deinit(allocator);
        var completion_prefix = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer completion_prefix.deinit(allocator);
        const self = try allocator.create(SimpleTUI);
        self.* = .{
            .allocator = allocator,
            .editor = try Editor.init(allocator),
            .running = true,
            .stdin = std.fs.File.stdin(),
            .stdout = std.fs.File.stdout(),
            .theme_registry = theme_mod.ThemeRegistry.init(allocator),
            .active_theme = theme_mod.Theme.defaultDark(),
            .plugin_manager = null,
            .editor_lsp = null,
            .highlight_cache = &.{},
            .highlight_dirty = true,
            .highlight_error = null,
            .highlight_error_flash = false,
            .highlight_error_flash_state = false,
            .highlight_error_logged = false,
            .command_buffer = command_buffer,
            .status_message = null,
            .plugin_cursor = null,
            .editor_context = null,
            .current_buffer_id = 1,
            .next_buffer_id = 2,
            .completion_popup_active = false,
            .completion_selected_index = 0,
            .completion_items = &.{},
            .completion_items_heap = false,
            .completion_prefix = completion_prefix,
            .completion_anchor_offset = null,
            .completion_generation_seen = 0,
            .completion_dirty = false,
            .signature_help_active = false,
            .signature_help_last_offset = null,
            .code_actions_active = false,
            .code_actions_selected = 0,
            .buffer_manager = null,
            .phantom_buffer_manager = null,
            .window_manager = null,
            .buffer_picker = null,
            .buffer_picker_active = false,
            .window_command_pending = false,
            .enable_nerd_fonts = true, // Enable Nerd Fonts by default
            .font_manager = font_manager_mod.FontManager.init(allocator, true),
            .using_phantom_buffers = use_phantom_buffers,
            .visual_block_mode = false,
            .visual_block_start_line = 0,
            .visual_block_start_column = 0,
            .git = core.Git.init(allocator),
            .git_hunks = &.{},
            .git_status_active = false,
            .git_log_active = false,
            .git_selected_commit = 0,
            .harpoon = core.Harpoon.init(allocator),
            .harpoon_menu_active = false,
            .harpoon_selected_idx = 0,
            .file_tree = null,
            .file_tree_active = false,
            .file_tree_width = 30,
            .pending_vim_key = null,
            .leader_key_pending = false,
            .leader_key_timestamp = 0,
            .leader_key_sequence = .{},
            .original_termios = undefined,
            .terminal_width = 80,
            .terminal_height = 24,
            .needs_resize = false,
            .viewport_top_line = 0,
            .viewport_left_col = 0,
        };

        // Initialize PhantomBufferManager if enabled
        if (use_phantom_buffers) {
            const pbm = try allocator.create(phantom_buffer_manager_mod.PhantomBufferManager);
            pbm.* = try phantom_buffer_manager_mod.PhantomBufferManager.init(allocator);
            self.phantom_buffer_manager = pbm;
        }

        return self;
    }

    pub fn deinit(self: *SimpleTUI) void {
        // Restore terminal state
        self.disableRawMode() catch {};

        // Clean up native integrations
        self.harpoon.deinit();
        self.git.deinit();
        self.leader_key_sequence.deinit(self.allocator);

        self.clearCompletionDisplay();
        self.completion_prefix.deinit(self.allocator);
        if (self.highlight_cache.len > 0) {
            self.allocator.free(self.highlight_cache);
        }
        if (self.highlight_error) |msg| {
            self.allocator.free(msg);
        }
        if (self.status_message) |msg| {
            self.allocator.free(msg);
        }
        if (self.buffer_picker) |picker| {
            picker.deinit();
            self.allocator.destroy(picker);
        }
        if (self.window_manager) |win_mgr| {
            win_mgr.deinit();
            self.allocator.destroy(win_mgr);
        }
        if (self.buffer_manager) |buf_mgr| {
            buf_mgr.deinit();
            self.allocator.destroy(buf_mgr);
        }
        if (self.phantom_buffer_manager) |pbm| {
            pbm.deinit();
            self.allocator.destroy(pbm);
        }
        // Clean up git hunks
        for (self.git_hunks) |hunk| {
            self.allocator.free(hunk.content);
        }
        if (self.git_hunks.len > 0) {
            self.allocator.free(self.git_hunks);
        }
        // Clean up file tree
        if (self.file_tree) |tree| {
            tree.deinit();
            self.allocator.destroy(tree);
        }
        self.command_buffer.deinit(self.allocator);
        self.theme_registry.deinit();
        self.font_manager.deinit();
        self.editor.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *SimpleTUI) !void {
        try self.enableRawMode();
        defer self.disableRawMode() catch {};

        // Clear screen and position cursor at top-left
        try self.clearScreen();
        try self.setCursor(1, 1);

        // Do initial render before showing cursor
        try self.render();
        try self.showCursor();

        while (self.running) {
            // Check for terminal resize
            if (self.needs_resize) {
                try self.getTerminalSize();
                self.needs_resize = false;
            }

            try self.handleInput();
            try self.render();
        }
    }

    pub fn loadFile(self: *SimpleTUI, path: []const u8) !void {
        const reuse_buffer = blk: {
            if (self.editor.current_filename) |existing| {
                break :blk std.mem.eql(u8, existing, path);
            }
            break :blk false;
        };

        try self.editor.loadFile(path);
        self.closeCompletionPopup();
        self.markHighlightsDirty();

        // Sync to PhantomBuffer if enabled
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;

            // Clear phantom buffer
            const pb_len = buffer.phantom_buffer.rope.len();
            if (pb_len > 0) {
                try buffer.phantom_buffer.rope.delete(0, pb_len);
            }

            // Copy from editor to phantom buffer
            const editor_content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
            if (editor_content.len > 0) {
                try buffer.phantom_buffer.rope.insert(0, editor_content);
            }

            // Clear undo/redo stacks on file load
            buffer.phantom_buffer.clearUndoRedo();
        }

        const filename = self.editor.current_filename orelse path;

        if (!reuse_buffer) {
            const previous_id = self.current_buffer_id;
            const new_id = self.allocateBufferId();
            self.setActiveBufferId(new_id);
            if (previous_id != new_id) {
                self.emitBufferClosed(previous_id);
            }
            self.emitBufferCreated(new_id);
            self.emitBufferOpened(new_id, filename);
        } else {
            self.emitBufferOpened(self.current_buffer_id, filename);
        }

        if (self.editor_lsp) |lsp| {
            lsp.openFile(filename) catch |err| {
                // Only log real errors, not expected failures
                if (err != error.ServerCrashed and err != error.NotInitialized) {
                    std.log.warn("Failed to open file for LSP: {}", .{err});
                }
            };
        }

        if (self.plugin_manager) |manager| {
            manager.emitEvent(.file_opened, .{ .file_opened = path }) catch |err| {
                std.log.err("Failed to emit file_opened event: {}", .{err});
            };
        }

        // Load git hunks for the file
        self.loadGitHunks(filename) catch |err| {
            // Not being in a git repo is expected, so only log errors that aren't NotInGitRepo
            if (err != error.NotInGitRepo) {
                std.log.warn("Failed to load git hunks for '{s}': {}", .{ filename, err });
            }
        };
    }

    pub fn setTheme(self: *SimpleTUI, name: []const u8) !void {
        if (self.theme_registry.get(name)) |plugin_theme| {
            self.active_theme = plugin_theme;
            self.markHighlightsDirty();
            return;
        }

        if (std.mem.indexOf(u8, name, "::")) |sep| {
            const plugin_id = name[0..sep];
            const plugin_theme_name = name[sep + 2 ..];
            if (plugin_theme_name.len > 0) {
                if (self.theme_registry.getPluginTheme(plugin_id, plugin_theme_name)) |plugin_theme_value| {
                    self.active_theme = plugin_theme_value;
                    self.markHighlightsDirty();
                    return;
                }
            }
        }

        self.active_theme = try theme_mod.Theme.get(name);
        self.markHighlightsDirty();
    }

    fn setStatusMessage(self: *SimpleTUI, message: []const u8) void {
        if (self.status_message) |existing| {
            self.allocator.free(existing);
        }
        const duped = self.allocator.dupe(u8, message) catch |err| {
            std.log.warn("Failed to allocate status message: {}", .{err});
            self.status_message = null;
            return;
        };
        self.status_message = duped;
    }

    fn clearStatusMessage(self: *SimpleTUI) void {
        if (self.status_message) |existing| {
            self.allocator.free(existing);
            self.status_message = null;
        }
    }

    pub fn attachPluginManager(self: *SimpleTUI, manager: *runtime.PluginManager) void {
        self.plugin_manager = manager;
        manager.setThemeCallbacks(
            @as(*anyopaque, @ptrCast(&self.theme_registry)),
            theme_mod.registerThemeCallback,
            theme_mod.unregisterThemeCallback,
        );

        self.emitBufferCreated(self.current_buffer_id);
        if (self.editor.current_filename) |filename| {
            self.emitBufferOpened(self.current_buffer_id, filename);
        }
    }

    pub fn attachEditorLSP(self: *SimpleTUI, editor_lsp: *editor_lsp_mod.EditorLSP) void {
        self.editor_lsp = editor_lsp;
    }

    pub fn detachEditorLSP(self: *SimpleTUI) void {
        self.editor_lsp = null;
    }

    pub fn setEditorContext(self: *SimpleTUI, ctx: *runtime.PluginAPI.EditorContext) void {
        self.editor_context = ctx;
        ctx.active_buffer_id = self.current_buffer_id;
    }

    pub fn getActiveBufferId(self: *const SimpleTUI) runtime.PluginAPI.BufferId {
        return self.current_buffer_id;
    }

    fn setActiveBufferId(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId) void {
        self.current_buffer_id = buffer_id;
        if (self.editor_context) |ctx| {
            ctx.active_buffer_id = buffer_id;
        }
    }

    fn allocateBufferId(self: *SimpleTUI) runtime.PluginAPI.BufferId {
        const candidate = self.next_buffer_id;
        if (candidate == std.math.maxInt(runtime.PluginAPI.BufferId)) {
            std.log.err("Buffer id counter exhausted", .{});
            return candidate;
        }
        self.next_buffer_id = candidate + 1;
        return candidate;
    }

    fn emitBufferCreated(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_created, .{ .buffer_created = buffer_id }) catch |err| {
                std.log.err("Failed to emit buffer_created event: {}", .{err});
            };
        }
    }

    fn emitBufferOpened(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId, filename: []const u8) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_opened, .{ .buffer_opened = .{ .buffer_id = buffer_id, .filename = filename } }) catch |err| {
                std.log.err("Failed to emit buffer_opened event: {}", .{err});
            };
        }
    }

    fn emitBufferSaved(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId, filename: []const u8) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_saved, .{ .buffer_saved = .{ .buffer_id = buffer_id, .filename = filename } }) catch |err| {
                std.log.err("Failed to emit buffer_saved event: {}", .{err});
            };
        }
    }

    fn emitBufferClosed(self: *SimpleTUI, buffer_id: runtime.PluginAPI.BufferId) void {
        if (self.plugin_manager) |manager| {
            manager.emitEvent(.buffer_closed, .{ .buffer_closed = buffer_id }) catch |err| {
                std.log.err("Failed to emit buffer_closed event: {}", .{err});
            };
        }
    }

    pub fn closeActiveBuffer(self: *SimpleTUI) void {
        if (self.editor.current_filename) |path| {
            if (self.editor_lsp) |lsp| {
                lsp.closeFile(path) catch |err| {
                    std.log.warn("Failed to close LSP document: {}", .{err});
                };
            }
        }
        self.emitBufferClosed(self.current_buffer_id);
    }

    fn getOffsetForLine(self: *SimpleTUI, target_line: usize) usize {
        const content = self.editor.rope.slice(.{
            .start = 0,
            .end = self.editor.rope.len(),
        }) catch return 0;

        var current_line: usize = 0;
        var offset: usize = 0;

        while (offset < content.len and current_line < target_line) {
            if (content[offset] == '\n') {
                current_line += 1;
            }
            offset += 1;
        }

        return offset;
    }

    fn scrollToCursor(self: *SimpleTUI) !void {
        const cursor_line = self.getCursorLine();
        const cursor_col = self.getCursorColumn();
        const height = self.terminal_height;
        const width = self.terminal_width;

        // Vertical scrolling
        // Scroll down if cursor below viewport
        if (cursor_line >= self.viewport_top_line + height - 2) {
            self.viewport_top_line = cursor_line - height + 3;
        }

        // Scroll up if cursor above viewport
        if (cursor_line < self.viewport_top_line) {
            self.viewport_top_line = cursor_line;
        }

        // Horizontal scrolling
        const gutter_width: usize = 7; // 4 (line num) + 1 (diag) + 1 (git) + 1 (space)
        const visible_width = if (width > gutter_width) width - gutter_width else 0;

        // Scroll right if cursor beyond right edge
        if (cursor_col >= self.viewport_left_col + visible_width) {
            self.viewport_left_col = cursor_col - visible_width + 1;
        }

        // Scroll left if cursor before left edge
        if (cursor_col < self.viewport_left_col) {
            self.viewport_left_col = cursor_col;
        }
    }

    fn render(self: *SimpleTUI) !void {
        // Use dynamic terminal size
        const width = self.terminal_width;
        const height = self.terminal_height;

        std.log.info("render: Called (terminal={}x{}, highlight_dirty={})", .{ width, height, self.highlight_dirty });

        self.applyPendingDefinition();

        // Ensure cursor is in viewport
        try self.scrollToCursor();

        try self.clearScreen();
        try self.setCursor(1, 1);

        std.log.info("render: About to call refreshHighlights()", .{});
        self.refreshHighlights();
        std.log.info("render: refreshHighlights() returned", .{});
        self.updatePluginCursorFromEditor();

        if (self.highlight_error_flash) {
            self.highlight_error_flash_state = !self.highlight_error_flash_state;
        } else {
            self.highlight_error_flash_state = false;
        }

        // Note: rope.slice() returns arena-allocated memory, do NOT free
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        // Gutter width: 4 (line number) + 1 (diagnostic) + 1 (git sign) + 1 (space) = 7
        const content_width: usize = if (width > 7) width - 7 else 0;

        var diagnostics_entries: []const editor_lsp_mod.Diagnostic = &[_]editor_lsp_mod.Diagnostic{};
        if (self.editor_lsp) |lsp| {
            if (self.editor.current_filename) |filename| {
                diagnostics_entries = lsp.getDiagnostics(filename) orelse diagnostics_entries;
            }
        }

        // Start rendering from viewport top line
        const viewport_start_offset = self.getOffsetForLine(self.viewport_top_line);
        var line_start: usize = viewport_start_offset;
        var screen_line: usize = 0;

        while (screen_line < height - 2 and line_start <= content.len) {
            const actual_line_num = self.viewport_top_line + screen_line;
            const remaining = content[line_start..];
            const rel_newline = std.mem.indexOfScalar(u8, remaining, '\n');
            const line_end = if (rel_newline) |rel| line_start + rel else content.len;
            var line_slice = content[line_start..line_end];

            // Apply horizontal scrolling (but keep full line for highlighting)
            const display_slice = if (self.viewport_left_col < line_slice.len)
                line_slice[self.viewport_left_col..]
            else
                "";

            // Line numbers + diagnostic marker + git sign columns
            var line_buf: [16]u8 = undefined;
            const line_str = try std.fmt.bufPrint(&line_buf, "{d:4}", .{actual_line_num + 1});
            try self.stdout.writeAll(line_str);

            // Diagnostic marker
            const line_diag = selectLineDiagnostic(diagnostics_entries, actual_line_num);
            const diag_marker = if (line_diag) |diag| severityMarker(diag.severity) else ' ';
            var diag_marker_buf = [1]u8{diag_marker};
            try self.stdout.writeAll(diag_marker_buf[0..]);

            // Git sign
            const git_sign = self.getGitSignForLine(actual_line_num);
            var git_sign_buf = [1]u8{git_sign};
            try self.stdout.writeAll(git_sign_buf[0..]);

            try self.stdout.writeAll(" ");

            if (content_width > 0) {
                // Use display_slice for rendering (with horizontal scroll applied)
                try self.renderHighlightedLine(display_slice, actual_line_num, content_width);
            }

            try self.stdout.writeAll("\r\n");

            line_start = if (rel_newline) |_| line_end + 1 else content.len + 1;
            screen_line += 1;
        }

        // Fill remaining lines with ~
        while (screen_line < height - 2) : (screen_line += 1) {
            try self.stdout.writeAll("~\r\n");
        }

        try self.renderCompletionBar(width, height);
        try self.renderSignatureHelpPopup(width, height);
        try self.renderCodeActionsMenu(width, height);
        try self.renderBufferPicker(width, height);
        try self.renderFileTree(width, height);

        // Status line
        try self.setCursor(height, 1);
        const flash_on = self.highlight_error_flash and self.highlight_error_flash_state;
        if (flash_on) {
            try self.setColor(41, 97);
        } else blk: {
            var bg_buf: [32]u8 = undefined;
            var fg_buf: [32]u8 = undefined;
            const bg_seq = self.active_theme.status_bar_bg.toBgSequence(&bg_buf) catch |err| {
                std.log.warn("Failed to apply status bar background color: {}", .{err});
                try self.setColor(47, 30);
                break :blk;
            };
            const fg_seq = self.active_theme.status_bar_fg.toFgSequence(&fg_buf) catch |err| {
                std.log.warn("Failed to apply status bar foreground color: {}", .{err});
                try self.setColor(47, 30);
                break :blk;
            };
            try self.stdout.writeAll(bg_seq);
            try self.stdout.writeAll(fg_seq);
        }

        const mode_enum = switch (self.editor.mode) {
            .normal => font_manager_mod.FontManager.Mode.normal,
            .insert => font_manager_mod.FontManager.Mode.insert,
            .visual => font_manager_mod.FontManager.Mode.visual,
            .command => font_manager_mod.FontManager.Mode.command,
        };
        const mode_str = self.font_manager.getModeIcon(mode_enum);

        const cursor_line = self.getCursorLine();
        const cursor_col = self.getCursorColumn();
        const cursor_diag = selectLineDiagnostic(diagnostics_entries, cursor_line);

        const language = self.editor.getLanguageName();

        // Get icons
        const line_icon = self.font_manager.getLineNumberIcon();
        const col_icon = self.font_manager.getColumnIcon();

        // Get LSP status icon
        const lsp_icon = if (self.editor_lsp != null)
            self.font_manager.getLspActiveIcon()
        else
            self.font_manager.getLspInactiveIcon();

        // Get filename
        const filename = if (self.editor.current_filename) |path| blk: {
            const basename = std.fs.path.basename(path);
            break :blk basename;
        } else "[No Name]";

        // Get git branch and stats
        const git_branch = self.git.getCurrentBranch() catch null;
        var added_count: usize = 0;
        var modified_count: usize = 0;
        var removed_count: usize = 0;
        for (self.git_hunks) |hunk| {
            switch (hunk.hunk_type) {
                .added => added_count += 1,
                .modified => modified_count += 1,
                .deleted => removed_count += 1,
            }
        }

        var status_buf: [512]u8 = undefined;
        var status_len: usize = 0;

        // Mode + filename + git
        var base_slice: []const u8 = undefined;
        if (git_branch) |branch| {
            if (added_count > 0 or modified_count > 0 or removed_count > 0) {
                base_slice = try std.fmt.bufPrint(status_buf[status_len..], " {s} {s}  {s} +{d} ~{d} -{d} {s} {s}{d} {s}{d} | {d} bytes | {s}", .{
                    mode_str,
                    filename,
                    branch,
                    added_count,
                    modified_count,
                    removed_count,
                    lsp_icon,
                    line_icon,
                    cursor_line + 1,
                    col_icon,
                    cursor_col + 1,
                    self.editor.rope.len(),
                    language,
                });
            } else {
                base_slice = try std.fmt.bufPrint(status_buf[status_len..], " {s} {s}  {s} {s} {s}{d} {s}{d} | {d} bytes | {s}", .{
                    mode_str,
                    filename,
                    branch,
                    lsp_icon,
                    line_icon,
                    cursor_line + 1,
                    col_icon,
                    cursor_col + 1,
                    self.editor.rope.len(),
                    language,
                });
            }
        } else {
            base_slice = try std.fmt.bufPrint(status_buf[status_len..], " {s} {s} {s} {s}{d} {s}{d} | {d} bytes | {s}", .{
                mode_str,
                filename,
                lsp_icon,
                line_icon,
                cursor_line + 1,
                col_icon,
                cursor_col + 1,
                self.editor.rope.len(),
                language,
            });
        }
        status_len += base_slice.len;

        if (self.highlight_error) |err_msg| {
            const max_err_len: usize = 48;
            const trimmed_len = if (err_msg.len > max_err_len) max_err_len else err_msg.len;
            const warn_slice = try std.fmt.bufPrint(status_buf[status_len..], " | ! {s}", .{err_msg[0..trimmed_len]});
            status_len += warn_slice.len;
            if (err_msg.len > max_err_len) {
                const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                status_len += ellipsis_slice.len;
            }
        }

        if (self.status_message) |msg| {
            const max_msg_len: usize = 48;
            const trimmed_len = if (msg.len > max_msg_len) max_msg_len else msg.len;
            const msg_slice = try std.fmt.bufPrint(status_buf[status_len..], " | {s}", .{msg[0..trimmed_len]});
            status_len += msg_slice.len;
            if (msg.len > max_msg_len) {
                const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                status_len += ellipsis_slice.len;
            }
        }

        if (cursor_diag) |diag| {
            const diag_icon = switch (diag.severity) {
                .error_sev => self.font_manager.getErrorIcon(),
                .warning => self.font_manager.getWarningIcon(),
                .information => self.font_manager.getInfoIcon(),
                .hint => self.font_manager.getHintIcon(),
            };
            const max_diag_len: usize = 60;
            const trimmed_len = if (diag.message.len > max_diag_len) max_diag_len else diag.message.len;
            const diag_slice = try std.fmt.bufPrint(status_buf[status_len..], " | {s} {s}", .{ diag_icon, diag.message[0..trimmed_len] });
            status_len += diag_slice.len;
            if (diag.message.len > max_diag_len) {
                const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                status_len += ellipsis_slice.len;
            }
        }

        if (self.editor_lsp) |lsp| {
            if (lsp.getHoverInfo()) |hover| {
                if (hover.len > 0) {
                    const hover_icon = self.font_manager.getHoverIcon();
                    const max_hover_len: usize = 40;
                    const trimmed_len = if (hover.len > max_hover_len) max_hover_len else hover.len;
                    const hover_slice = try std.fmt.bufPrint(status_buf[status_len..], " | {s} {s}", .{ hover_icon, hover[0..trimmed_len] });
                    status_len += hover_slice.len;
                    if (hover.len > max_hover_len) {
                        const ellipsis_slice = try std.fmt.bufPrint(status_buf[status_len..], "…", .{});
                        status_len += ellipsis_slice.len;
                    }
                }
            }
        }

        var status_slice: []const u8 = status_buf[0..status_len];
        var command_line_buf: [512]u8 = undefined;
        if (self.editor.mode == .command) {
            const input = self.command_buffer.items;
            const max_input_len = if (command_line_buf.len > 4) command_line_buf.len - 4 else 0;
            const needs_ellipsis = input.len > max_input_len;
            if (needs_ellipsis) {
                status_slice = try std.fmt.bufPrint(&command_line_buf, ":{s}...", .{input[0..max_input_len]});
            } else {
                status_slice = try std.fmt.bufPrint(&command_line_buf, ":{s}", .{input});
            }
        }

        // Pad with spaces to fill width
        const padding_len = if (status_slice.len < width) width - status_slice.len else 0;
        var final_status_buf: [512]u8 = undefined;
        const max_status_len: usize = final_status_buf.len;
        const copy_len: usize = @min(status_slice.len, max_status_len);
        @memcpy(final_status_buf[0..copy_len], status_slice[0..copy_len]);
        var total_len: usize = copy_len;
        if (padding_len > 0 and total_len < max_status_len) {
            const pad_count: usize = @min(padding_len, max_status_len - total_len);
            @memset(final_status_buf[total_len .. total_len + pad_count], ' ');
            total_len += pad_count;
        }
        const status = final_status_buf[0..total_len];

        try self.stdout.writeAll(status[0..@min(status.len, width)]);
        try self.resetColor();

        // Position cursor (accounting for viewport)
        const viewport_line = if (cursor_line >= self.viewport_top_line)
            cursor_line - self.viewport_top_line
        else
            0;
        const screen_line_pos = @min(viewport_line + 1, height - 2);
        const viewport_col = if (cursor_col >= self.viewport_left_col)
            cursor_col - self.viewport_left_col
        else
            0;
        const screen_col_pos = viewport_col + 7; // Account for gutter (7 chars)
        try self.setCursor(screen_line_pos, screen_col_pos);

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
                2 => { // Ctrl+B - Toggle file tree
                    try self.toggleFileTree();
                    return;
                },
                17 => { // Ctrl+Q
                    self.running = false;
                    return;
                },
                else => {},
            }

            // Buffer picker mode takes precedence
            if (self.buffer_picker_active) {
                try self.handleBufferPickerInput(key);
                return;
            }

            // Code actions menu takes precedence
            if (self.code_actions_active) {
                try self.handleCodeActionsInput(key);
                return;
            }

            // Harpoon menu mode takes precedence
            if (self.harpoon_menu_active) {
                // TODO: Implement harpoon menu// try self.handleHarpoonMenuInput(key);
                return;
            }

            // Git status mode takes precedence
            if (self.git_status_active) {
                // TODO: Implement git status// try self.handleGitStatusInput(key);
                return;
            }

            // Leader key sequence handling (normal mode only)
            if (self.editor.mode == .normal and self.leader_key_pending) {
                // TODO: Implement leader key sequence// try self.handleLeaderKeySequence(key);
                return;
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
                'A' => { // Up arrow
                    if (self.file_tree_active) {
                        if (self.file_tree) |tree| tree.moveUp();
                    } else if (self.editor.mode == .insert and self.completion_popup_active and self.completion_items.len > 0) {
                        self.moveCompletionSelection(-1);
                    } else {
                        self.editor.moveCursorUp();
                    }
                },
                'B' => { // Down arrow
                    if (self.file_tree_active) {
                        if (self.file_tree) |tree| tree.moveDown();
                    } else if (self.editor.mode == .insert and self.completion_popup_active and self.completion_items.len > 0) {
                        self.moveCompletionSelection(1);
                    } else {
                        self.editor.moveCursorDown();
                    }
                },
                'C' => { // Right arrow
                    if (self.file_tree_active) {
                        if (self.file_tree) |tree| try tree.toggleExpanded();
                    } else {
                        self.editor.moveCursorRight();
                        if (self.editor.mode == .insert and self.completion_popup_active) {
                            self.completion_dirty = true;
                        }
                    }
                },
                'D' => { // Left arrow
                    if (self.file_tree_active) {
                        if (self.file_tree) |tree| try tree.toggleExpanded();
                    } else {
                        self.editor.moveCursorLeft();
                        if (self.editor.mode == .insert and self.completion_popup_active) {
                            self.completion_dirty = true;
                        }
                    }
                },
                else => {},
            }
        } else if (key_bytes.len == 1) {
            const key = key_bytes[0];
            // Handle Enter key in file tree
            if (self.file_tree_active and key == 13) { // Enter
                try self.openFileTreeSelection();
                return;
            }
        }
    }

    fn handleNormalMode(self: *SimpleTUI, key: u8) !void {
        // Handle two-key sequences (dd, yy, etc.)
        if (self.pending_vim_key) |pending| {
            defer self.pending_vim_key = null;

            if (pending == 'd' and key == 'd') {
                // dd - delete line
                try self.deleteLineWithUndo();
                return;
            } else if (pending == 'y' and key == 'y') {
                // yy - yank line
                try self.yankLine();
                return;
            } else if (pending == 'g' and key == 'g') {
                // gg - goto top
                self.editor.cursor.offset = 0;
                return;
            }
            // If no match, fall through to handle second key normally
        }

        switch (key) {
            ' ' => { // Space - Leader key
                self.leader_key_pending = true;
                self.leader_key_timestamp = std.time.milliTimestamp();
                self.leader_key_sequence.clearRetainingCapacity();
                self.setStatusMessage("Leader: <Space>...");
                return;
            },
            27 => {
                // ESC - clear pending key
                self.pending_vim_key = null;
            },
            1 => self.triggerCodeActions(), // Ctrl+A - code actions menu
            2 => self.activateBufferPicker(), // Ctrl+B - buffer picker
            9 => self.toggleInlayHints(), // Ctrl+I (Tab) - toggle inlay hints
            23 => { // Ctrl+W - window commands
                self.window_command_pending = true;
                self.setStatusMessage("Window command (s=split h, v=split v, c=close, h/j/k/l=navigate)");
            },
            'h' => self.editor.moveCursorLeft(),
            'j' => self.editor.moveCursorDown(),
            'k' => self.editor.moveCursorUp(),
            'l' => self.editor.moveCursorRight(),
            'i' => self.switchMode(.insert),
            'I' => {
                self.editor.moveCursorToLineStart();
                self.switchMode(.insert);
            },
            'a' => {
                self.editor.moveCursorRight();
                self.switchMode(.insert);
            },
            'A' => {
                self.editor.moveCursorToLineEnd();
                self.switchMode(.insert);
            },
            'o' => {
                try self.insertNewlineAfterWithUndo();
                self.switchMode(.insert);
            },
            'O' => {
                try self.insertNewlineBeforeWithUndo();
                self.switchMode(.insert);
            },
            'x' => try self.deleteCharWithUndo(),
            'u' => try self.performUndo(),
            18 => try self.performRedo(), // Ctrl+R
            'w' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                } else {
                    self.editor.moveWordForward();
                }
            },
            'b' => self.editor.moveWordBackward(),
            '0' => self.editor.moveCursorToLineStart(),
            '$' => self.editor.moveCursorToLineEnd(),
            'd' => {
                // Set pending key for dd sequence
                self.pending_vim_key = 'd';
            },
            'y' => {
                // Set pending key for yy sequence
                self.pending_vim_key = 'y';
            },
            'p' => {
                // Paste after cursor
                try self.pasteAfter();
            },
            'P' => {
                // Paste before cursor
                try self.pasteBefore();
            },
            'g' => {
                // Set pending key for gg sequence
                self.pending_vim_key = 'g';
            },
            'G' => self.editor.moveCursorToEnd(),
            'H' => self.requestLspHover(),
            'D' => self.requestLspDefinition(),
            's' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                    self.splitWindow(.horizontal) catch |err| {
                        std.log.warn("Failed to split window: {}", .{err});
                    };
                }
            },
            'v' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                    self.splitWindow(.vertical) catch |err| {
                        std.log.warn("Failed to split window: {}", .{err});
                    };
                } else {
                    self.switchMode(.visual);
                }
            },
            22 => { // Ctrl+V - visual block mode
                self.enterVisualBlockMode();
            },
            'c' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                    self.closeWindow() catch |err| {
                        std.log.warn("Failed to close window: {}", .{err});
                        self.setStatusMessage("Cannot close last window");
                    };
                }
            },
            ':' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                } else {
                    self.startCommandMode();
                }
            },
            '/' => {
                // Start forward search
                self.command_buffer.clearRetainingCapacity();
                self.command_buffer.append(self.allocator, '/') catch {};
                self.switchMode(.command);
            },
            '?' => {
                // Start backward search
                self.command_buffer.clearRetainingCapacity();
                self.command_buffer.append(self.allocator, '?') catch {};
                self.switchMode(.command);
            },
            'n' => {
                // Repeat last search
                const found = self.editor.repeatLastSearch() catch false;
                if (found) {
                    self.setStatusMessage("Search: next match");
                } else {
                    self.setStatusMessage("Pattern not found");
                }
            },
            'N' => {
                // Repeat last search in opposite direction
                const found = self.editor.repeatLastSearchReverse() catch false;
                if (found) {
                    self.setStatusMessage("Search: previous match");
                } else {
                    self.setStatusMessage("Pattern not found");
                }
            },
            'q' => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                } else {
                    self.running = false;
                }
            },
            else => {
                if (self.window_command_pending) {
                    self.window_command_pending = false;
                    self.clearStatusMessage();
                }
            },
        }
    }

    fn handleInsertMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => self.switchMode(.normal), // ESC
            0 => self.triggerCompletionRequest(), // Ctrl+Space
            8, 127 => { // Backspace/Delete
                try self.backspaceWithUndo();
                self.afterTextEdit();
                if (self.completion_popup_active) {
                    self.completion_dirty = true;
                }
            },
            9 => { // Tab
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    self.moveCompletionSelection(1);
                } else {
                    try self.insertCharWithUndo('\t');
                    self.afterTextEdit();
                }
            },
            13 => { // Enter
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    try self.acceptCompletionSelection();
                } else {
                    try self.insertCharWithUndo('\n');
                    self.afterTextEdit();
                    self.closeCompletionPopup();
                }
            },
            14 => { // Ctrl+N
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    self.moveCompletionSelection(1);
                }
            },
            16 => { // Ctrl+P
                if (self.completion_popup_active and self.completion_items.len > 0) {
                    self.moveCompletionSelection(-1);
                }
            },
            else => {
                if (key >= 32 and key < 127) { // Printable ASCII
                    try self.insertCharWithUndo(key);
                    self.afterTextEdit();
                    if (self.completion_popup_active) {
                        self.completion_dirty = true;
                    } else {
                        self.maybeTriggerAutoCompletion(key);
                    }
                    // Trigger signature help for '(' and ','
                    self.maybeTriggerSignatureHelp(key);
                }
            },
        }
    }

    fn handleVisualMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => { // ESC
                if (self.visual_block_mode) {
                    self.exitVisualBlockMode();
                }
                self.switchMode(.normal);
            },
            'h' => {
                self.editor.moveCursorLeft();
                self.editor.selection_end = self.editor.cursor.offset;
            },
            'j' => {
                self.editor.moveCursorDown();
                self.editor.selection_end = self.editor.cursor.offset;
            },
            'k' => {
                self.editor.moveCursorUp();
                self.editor.selection_end = self.editor.cursor.offset;
            },
            'l' => {
                self.editor.moveCursorRight();
                self.editor.selection_end = self.editor.cursor.offset;
            },
            'd' => {
                if (self.visual_block_mode) {
                    try self.deleteVisualBlock();
                } else {
                    // Delete visual selection
                    if (self.editor.selection_start) |start| {
                        if (self.editor.selection_end) |end| {
                            const delete_start = @min(start, end);
                            const delete_end = @max(start, end);
                            const deleted = try self.editor.rope.slice(.{ .start = delete_start, .end = delete_end });

                            // Store in yank buffer before deleting
                            if (self.editor.yank_buffer) |old_buf| {
                                self.allocator.free(old_buf);
                            }
                            self.editor.yank_buffer = try self.allocator.dupe(u8, deleted);
                            self.editor.yank_linewise = false;

                            // Delete the selection
                            try self.editor.rope.delete(delete_start, delete_end - delete_start);
                            self.editor.cursor.offset = delete_start;

                            self.setStatusMessage("Deleted selection");
                        }
                    }

                    // Clear selection
                    self.editor.selection_start = null;
                    self.editor.selection_end = null;
                }
                self.switchMode(.normal);
            },
            'c' => {
                // Change visual selection (delete and enter insert mode)
                if (self.visual_block_mode) {
                    try self.changeVisualBlock();
                } else {
                    if (self.editor.selection_start) |start| {
                        if (self.editor.selection_end) |end| {
                            const delete_start = @min(start, end);
                            const delete_end = @max(start, end);
                            const deleted = try self.editor.rope.slice(.{ .start = delete_start, .end = delete_end });

                            // Store in yank buffer before deleting
                            if (self.editor.yank_buffer) |old_buf| {
                                self.allocator.free(old_buf);
                            }
                            self.editor.yank_buffer = try self.allocator.dupe(u8, deleted);
                            self.editor.yank_linewise = false;

                            // Delete the selection
                            try self.editor.rope.delete(delete_start, delete_end - delete_start);
                            self.editor.cursor.offset = delete_start;
                        }
                    }

                    // Clear selection
                    self.editor.selection_start = null;
                    self.editor.selection_end = null;
                    self.switchMode(.insert);
                }
            },
            'y' => {
                // Yank visual selection
                if (self.editor.selection_start) |start| {
                    if (self.editor.selection_end) |end| {
                        const yank_start = @min(start, end);
                        const yank_end = @max(start, end);
                        const yanked = try self.editor.rope.slice(.{ .start = yank_start, .end = yank_end });

                        // Free old yank buffer
                        if (self.editor.yank_buffer) |old_buf| {
                            self.allocator.free(old_buf);
                        }

                        // Store yanked content (character-wise in visual mode)
                        self.editor.yank_buffer = try self.allocator.dupe(u8, yanked);
                        self.editor.yank_linewise = false;

                        self.setStatusMessage("Yanked selection");
                    }
                }

                if (self.visual_block_mode) {
                    self.exitVisualBlockMode();
                }

                // Clear selection
                self.editor.selection_start = null;
                self.editor.selection_end = null;
                self.switchMode(.normal);
            },
            'I' => { // Insert at start of block
                if (self.visual_block_mode) {
                    try self.insertAtVisualBlockStart();
                }
            },
            'A' => { // Append at end of block
                if (self.visual_block_mode) {
                    try self.appendAtVisualBlockEnd();
                }
            },
            else => {},
        }
    }

    fn handleCommandMode(self: *SimpleTUI, key: u8) !void {
        switch (key) {
            27 => {
                self.exitCommandMode();
                self.clearStatusMessage();
            },
            13 => try self.submitCommandLine(),
            8, 127 => {
                if (self.command_buffer.items.len > 0) {
                    _ = self.command_buffer.pop();
                }
            },
            else => {
                if (key >= 32 and key < 127) {
                    try self.command_buffer.append(self.allocator, key);
                }
            },
        }
    }

    fn modeToPluginMode(mode: Editor.Mode) runtime.PluginAPI.EditorContext.EditorMode {
        return switch (mode) {
            .normal => .normal,
            .insert => .insert,
            .visual => .visual,
            .command => .command,
        };
    }

    fn switchMode(self: *SimpleTUI, new_mode: Editor.Mode) void {
        const current = self.editor.mode;
        if (current == new_mode) return;
        self.editor.mode = new_mode;

        if (new_mode != .insert) {
            self.closeCompletionPopup();
        }

        // Initialize visual mode selection
        if (new_mode == .visual) {
            self.editor.selection_start = self.editor.cursor.offset;
            self.editor.selection_end = self.editor.cursor.offset;
        } else if (current == .visual) {
            // Clear selection when leaving visual mode
            self.editor.selection_start = null;
            self.editor.selection_end = null;
        }

        if (self.plugin_manager) |manager| {
            const event_data = runtime.PluginAPI.EventData{
                .mode_changed = .{
                    .old_mode = modeToPluginMode(current),
                    .new_mode = modeToPluginMode(new_mode),
                },
            };
            manager.emitEvent(.mode_changed, event_data) catch |err| {
                std.log.err("Failed to emit mode_changed event: {}", .{err});
            };
        }
    }

    fn startCommandMode(self: *SimpleTUI) void {
        self.command_buffer.clearRetainingCapacity();
        self.switchMode(.command);
    }

    fn exitCommandMode(self: *SimpleTUI) void {
        self.command_buffer.clearRetainingCapacity();
        self.switchMode(.normal);
    }

    fn submitCommandLine(self: *SimpleTUI) !void {
        const trimmed = std.mem.trim(u8, self.command_buffer.items, " \t");
        if (trimmed.len == 0) {
            self.exitCommandMode();
            return;
        }

        // Handle search patterns
        if (trimmed[0] == '/' or trimmed[0] == '?') {
            const is_forward = trimmed[0] == '/';
            const pattern = if (trimmed.len > 1) trimmed[1..] else "";

            if (pattern.len == 0) {
                self.setStatusMessage("No search pattern");
                self.exitCommandMode();
                return;
            }

            // Set search pattern
            try self.editor.setSearchPattern(pattern);

            // Perform first search
            const found = if (is_forward)
                try self.editor.searchForward()
            else
                try self.editor.searchBackward();

            if (found) {
                var msg_buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Search: {s}", .{pattern}) catch "Search complete";
                self.setStatusMessage(msg);
            } else {
                self.setStatusMessage("Pattern not found");
            }

            self.exitCommandMode();
            return;
        }

        var tokenizer = std.mem.tokenizeAny(u8, trimmed, " \t");
        const head = tokenizer.next() orelse {
            self.exitCommandMode();
            return;
        };

        if (std.mem.eql(u8, head, "q") or std.mem.eql(u8, head, "quit")) {
            // Check for unsaved changes
            if (self.phantom_buffer_manager) |pbm| {
                if (pbm.hasUnsavedChanges()) {
                    self.setStatusMessage("No write since last change (add ! to override)");
                    self.exitCommandMode();
                    return;
                }
            }
            self.running = false;
            self.setStatusMessage("Quit");
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "q!") or std.mem.eql(u8, head, "quit!")) {
            self.running = false;
            self.setStatusMessage("Quit (forced)");
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "wq")) {
            self.saveCurrentFile() catch |err| {
                switch (err) {
                    error.NoActiveFile => self.setStatusMessage("No file to write"),
                    else => {
                        self.setStatusMessage("Write failed");
                        std.log.err("Failed to write file: {}", .{err});
                    },
                }
                self.exitCommandMode();
                return;
            };
            self.setStatusMessage("Wrote file");
            self.running = false;
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "w") or std.mem.eql(u8, head, "write")) {
            self.saveCurrentFile() catch |err| {
                switch (err) {
                    error.NoActiveFile => self.setStatusMessage("No file to write"),
                    else => {
                        self.setStatusMessage("Write failed");
                        std.log.err("Failed to write file: {}", .{err});
                    },
                }
                self.exitCommandMode();
                return;
            };
            self.setStatusMessage("Wrote file");
            self.exitCommandMode();
            return;
        }

        // Buffer navigation commands
        if (std.mem.eql(u8, head, "e") or std.mem.eql(u8, head, "edit")) {
            const filename = tokenizer.next() orelse {
                self.setStatusMessage("E471: Argument required");
                self.exitCommandMode();
                return;
            };

            self.loadFile(filename) catch |err| {
                var msg_buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Failed to open '{s}': {}", .{ filename, err }) catch "Failed to open file";
                self.setStatusMessage(msg);
                std.log.err("Failed to open file '{s}': {}", .{ filename, err });
                self.exitCommandMode();
                return;
            };

            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Opened '{s}'", .{filename}) catch "File opened";
            self.setStatusMessage(msg);
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "bn") or std.mem.eql(u8, head, "bnext")) {
            if (self.phantom_buffer_manager) |pbm| {
                pbm.nextBuffer();
                const active = pbm.getActiveBuffer() orelse {
                    self.setStatusMessage("No active buffer");
                    self.exitCommandMode();
                    return;
                };
                var msg_buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Switched to buffer {d}: {s}", .{ active.id, active.display_name }) catch "Next buffer";
                self.setStatusMessage(msg);
            } else {
                self.setStatusMessage("Buffer manager not available");
            }
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "bp") or std.mem.eql(u8, head, "bprev") or std.mem.eql(u8, head, "bprevious")) {
            if (self.phantom_buffer_manager) |pbm| {
                pbm.previousBuffer();
                const active = pbm.getActiveBuffer() orelse {
                    self.setStatusMessage("No active buffer");
                    self.exitCommandMode();
                    return;
                };
                var msg_buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "Switched to buffer {d}: {s}", .{ active.id, active.display_name }) catch "Previous buffer";
                self.setStatusMessage(msg);
            } else {
                self.setStatusMessage("Buffer manager not available");
            }
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "bd") or std.mem.eql(u8, head, "bdelete")) {
            if (self.phantom_buffer_manager) |pbm| {
                const current_id = pbm.active_buffer_id;
                pbm.closeBuffer(current_id) catch |err| {
                    switch (err) {
                        error.CannotCloseLastBuffer => self.setStatusMessage("Cannot close last buffer"),
                        else => {
                            var msg_buf: [128]u8 = undefined;
                            const msg = std.fmt.bufPrint(&msg_buf, "Failed to close buffer: {}", .{err}) catch "Close failed";
                            self.setStatusMessage(msg);
                        },
                    }
                    self.exitCommandMode();
                    return;
                };
                self.setStatusMessage("Buffer closed");
            } else {
                self.setStatusMessage("Buffer manager not available");
            }
            self.exitCommandMode();
            return;
        }

        // Handle substitute command :%s/pattern/replacement/[flags]
        if (std.mem.eql(u8, head, "%s") or std.mem.eql(u8, head, "s")) {
            const rest = trimmed[head.len..];
            // Parse: /pattern/replacement/[flags]
            if (rest.len < 3 or rest[0] != '/') {
                self.setStatusMessage("E486: Pattern not found (usage: :%s/pattern/replacement/[flags])");
                self.exitCommandMode();
                return;
            }

            // Find second delimiter
            const second_delim_idx = std.mem.indexOfPos(u8, rest, 1, "/") orelse {
                self.setStatusMessage("E486: Pattern not found");
                self.exitCommandMode();
                return;
            };

            const pattern = rest[1..second_delim_idx];
            if (pattern.len == 0) {
                self.setStatusMessage("E486: Pattern not found");
                self.exitCommandMode();
                return;
            }

            // Find third delimiter (optional)
            const third_start = second_delim_idx + 1;
            const third_delim_idx = std.mem.indexOfPos(u8, rest, third_start, "/");

            const replacement = if (third_delim_idx) |idx|
                rest[third_start..idx]
            else if (third_start < rest.len)
                rest[third_start..]
            else
                "";

            const flags = if (third_delim_idx) |idx|
                if (idx + 1 < rest.len) rest[idx + 1 ..] else ""
            else
                "";

            // Determine if global replace (g flag)
            const global = std.mem.indexOf(u8, flags, "g") != null;

            // Perform replacement
            const count = try self.performSubstitute(pattern, replacement, global);

            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "{d} substitution{s} on {d} line{s}", .{
                count,
                if (count == 1) @as([]const u8, "") else "s",
                count,
                if (count == 1) @as([]const u8, "") else "s",
            }) catch "Substitution complete";
            self.setStatusMessage(msg);
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "commands")) {
            self.showAvailableCommands() catch |err| {
                if (err != error.PluginUnavailable) {
                    std.log.err("Failed to show command list: {}", .{err});
                    self.setStatusMessage("Unable to list commands");
                }
            };
            self.exitCommandMode();
            return;
        }

        if (std.mem.eql(u8, head, "plugins")) {
            self.showLoadedPlugins() catch |err| {
                if (err != error.PluginUnavailable) {
                    std.log.err("Failed to show plugins: {}", .{err});
                    self.setStatusMessage("Unable to list plugins");
                }
            };
            self.exitCommandMode();
            return;
        }

        var args_builder = std.ArrayList([]const u8).initCapacity(self.allocator, 0) catch |err| {
            std.log.err("Failed to allocate command arguments: {}", .{err});
            self.setStatusMessage("Unable to process command arguments");
            self.exitCommandMode();
            return;
        };
        defer args_builder.deinit(self.allocator);
        while (tokenizer.next()) |token| {
            try args_builder.append(self.allocator, token);
        }

        const args = args_builder.items;
        self.executePluginCommand(head, args) catch |err| {
            switch (err) {
                error.PluginUnavailable => {},
                else => {
                    var msg_buf: [160]u8 = undefined;
                    const msg = std.fmt.bufPrint(&msg_buf, "Command '{s}' failed", .{head}) catch "Command failed";
                    self.setStatusMessage(msg);
                    std.log.err("Plugin command '{s}' failed: {}", .{ head, err });
                },
            }
            self.exitCommandMode();
            return;
        };

        self.exitCommandMode();
    }

    fn performSubstitute(self: *SimpleTUI, pattern: []const u8, replacement: []const u8, global: bool) !usize {
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        var count: usize = 0;
        var pos: usize = 0;

        while (pos < content.len) {
            if (std.mem.indexOf(u8, content[pos..], pattern)) |rel_offset| {
                const match_start = pos + rel_offset;

                // Delete the matched pattern
                try self.editor.rope.delete(match_start, pattern.len);

                // Insert the replacement
                if (replacement.len > 0) {
                    try self.editor.rope.insert(match_start, replacement);
                }

                count += 1;

                // Update position
                if (global) {
                    // For global replace, restart search from beginning (simpler implementation)
                    pos = 0;
                    continue;
                } else {
                    // For non-global, only replace first occurrence
                    break;
                }
            } else {
                // No more matches
                break;
            }
        }

        if (count > 0) {
            self.markHighlightsDirty();
        }

        return count;
    }

    fn saveCurrentFile(self: *SimpleTUI) !void {
        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No file to write");
            return error.NoActiveFile;
        };
        try self.editor.saveFile(path);

        if (self.plugin_manager) |manager| {
            manager.emitEvent(.file_saved, .{ .file_saved = path }) catch |err| {
                std.log.err("Failed to emit file_saved event: {}", .{err});
            };
        }

        self.emitBufferSaved(self.current_buffer_id, path);

        if (self.editor_lsp) |lsp| {
            lsp.notifyFileSaved(path) catch |err| {
                std.log.warn("Failed to notify LSP about save: {}", .{err});
            };
        }
    }

    fn executePluginCommand(self: *SimpleTUI, name: []const u8, args: []const []const u8) !void {
        const manager = self.plugin_manager orelse {
            self.setStatusMessage("No plugin manager attached");
            return error.PluginUnavailable;
        };
        try manager.executeCommand(name, args);
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Executed {s}", .{name}) catch "Command executed";
        self.setStatusMessage(msg);
    }

    fn showAvailableCommands(self: *SimpleTUI) !void {
        const manager = self.plugin_manager orelse {
            self.setStatusMessage("No plugin manager attached");
            return error.PluginUnavailable;
        };

        const commands = manager.listCommands(self.allocator) catch |err| {
            std.log.err("Failed to list plugin commands: {}", .{err});
            self.setStatusMessage("Unable to list commands");
            return;
        };
        defer self.allocator.free(commands);

        if (commands.len == 0) {
            self.setStatusMessage("No plugin commands registered");
            return;
        }

        var builder = std.ArrayList(u8).initCapacity(self.allocator, 0) catch |err| {
            std.log.err("Failed to allocate command list buffer: {}", .{err});
            self.setStatusMessage("Unable to list commands");
            return;
        };
        defer builder.deinit(self.allocator);
        try builder.appendSlice(self.allocator, "Commands: ");

        const max_display: usize = 5;
        for (commands, 0..) |command, idx| {
            if (idx >= max_display) {
                try builder.appendSlice(self.allocator, "...");
                break;
            }

            if (idx > 0) {
                try builder.appendSlice(self.allocator, ", ");
            }

            try builder.appendSlice(self.allocator, command.name);
            try builder.appendSlice(self.allocator, " (");
            try builder.appendSlice(self.allocator, command.plugin_id);
            try builder.appendSlice(self.allocator, ")");
        }

        self.setStatusMessage(builder.items);
    }

    fn showLoadedPlugins(self: *SimpleTUI) !void {
        const manager = self.plugin_manager orelse {
            self.setStatusMessage("No plugin manager attached");
            return error.PluginUnavailable;
        };

        const plugins = manager.listLoadedPlugins(self.allocator) catch |err| {
            std.log.err("Failed to list plugins: {}", .{err});
            self.setStatusMessage("Unable to list plugins");
            return;
        };
        defer self.allocator.free(plugins);

        if (plugins.len == 0) {
            self.setStatusMessage("No plugins loaded");
            return;
        }

        var builder = std.ArrayList(u8).initCapacity(self.allocator, 0) catch |err| {
            std.log.err("Failed to allocate plugin list buffer: {}", .{err});
            self.setStatusMessage("Unable to list plugins");
            return;
        };
        defer builder.deinit(self.allocator);
        try builder.appendSlice(self.allocator, "Plugins: ");
        for (plugins, 0..) |plugin_id, idx| {
            if (idx > 0) try builder.appendSlice(self.allocator, ", ");
            try builder.appendSlice(self.allocator, plugin_id);
        }

        self.setStatusMessage(builder.items);
    }

    fn getTerminalSize(self: *SimpleTUI) !void {
        var winsize: std.posix.winsize = undefined;
        const result = std.posix.system.ioctl(
            self.stdout.handle,
            std.posix.T.IOCGWINSZ,
            @intFromPtr(&winsize),
        );

        if (result < 0) {
            // Fallback to default size
            self.terminal_width = 80;
            self.terminal_height = 24;
            return;
        }

        self.terminal_width = winsize.col;
        self.terminal_height = winsize.row;
    }

    fn enableRawMode(self: *SimpleTUI) !void {
        // Get initial terminal size
        try self.getTerminalSize();

        // Enter alternate screen buffer
        try self.stdout.writeAll("\x1B[?1049h");

        // Hide cursor
        try self.stdout.writeAll("\x1B[?25l");

        // Enable raw mode using termios
        const stdin_fd = std.posix.STDIN_FILENO;

        // Get current terminal settings
        self.original_termios = try std.posix.tcgetattr(stdin_fd);

        // Create modified settings for raw mode
        var raw = self.original_termios;

        // Disable canonical mode, echo, and signals
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        // Disable input processing
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        // Disable output processing
        raw.oflag.OPOST = false;

        // Set character size to 8 bits
        raw.cflag.CSIZE = .CS8;

        // Set read timeout (100ms)
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;

        // Apply settings
        try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);
    }

    fn bridgeGetCurrentBuffer(ctx: *anyopaque) runtime.PluginAPI.BufferId {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        return self.current_buffer_id;
    }

    fn bridgeGetCursorPosition(ctx: *anyopaque) runtime.PluginAPI.EditorContext.CursorPosition {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        const offset = self.editor.cursor.offset;
        const lc = self.editor.rope.lineColumnAtOffset(offset) catch {
            const fallback = runtime.PluginAPI.EditorContext.CursorPosition{ .line = 0, .column = 0, .byte_offset = offset };
            if (self.plugin_cursor) |cursor_ptr| {
                cursor_ptr.* = fallback;
            }
            return fallback;
        };
        const position = runtime.PluginAPI.EditorContext.CursorPosition{ .line = lc.line, .column = lc.column, .byte_offset = offset };
        if (self.plugin_cursor) |cursor_ptr| {
            cursor_ptr.* = position;
        }
        return position;
    }

    fn bridgeSetCursorPosition(ctx: *anyopaque, position: runtime.PluginAPI.EditorContext.CursorPosition) anyerror!void {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        const rope_len = self.editor.rope.len();
        const new_offset = if (position.byte_offset > rope_len) rope_len else position.byte_offset;
        self.editor.cursor.offset = new_offset;
        if (self.plugin_cursor) |cursor_ptr| {
            cursor_ptr.* = .{
                .line = position.line,
                .column = position.column,
                .byte_offset = new_offset,
            };
        }
    }

    fn bridgeGetSelection(ctx: *anyopaque) ?runtime.PluginAPI.EditorContext.SelectionRange {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        const start_opt = self.editor.selection_start;
        const end_opt = self.editor.selection_end;
        if (start_opt == null or end_opt == null) return null;

        const start_val = start_opt.?;
        const end_val = end_opt.?;
        const normalized_start = @min(start_val, end_val);
        const normalized_end = @max(start_val, end_val);
        return .{ .start = normalized_start, .end = normalized_end };
    }

    fn bridgeSetSelection(ctx: *anyopaque, selection: ?runtime.PluginAPI.EditorContext.SelectionRange) anyerror!void {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        if (selection) |sel| {
            const rope_len = self.editor.rope.len();
            const clamped_start = @min(sel.start, rope_len);
            const clamped_end = @min(sel.end, rope_len);
            const normalized_start = @min(clamped_start, clamped_end);
            const normalized_end = @max(clamped_start, clamped_end);
            self.editor.selection_start = normalized_start;
            self.editor.selection_end = normalized_end;
        } else {
            self.editor.selection_start = null;
            self.editor.selection_end = null;
        }
    }

    fn bridgeNotifyChange(ctx: *anyopaque, change: runtime.PluginAPI.EditorContext.BufferChange) anyerror!void {
        const self = @as(*SimpleTUI, @ptrCast(@alignCast(ctx)));
        _ = change;
        self.markHighlightsDirty();
        if (self.plugin_cursor) |cursor_ptr| {
            self.editor.cursor.offset = cursor_ptr.byte_offset;
            self.updatePluginCursorFromEditor();
        }
        if (self.editor_lsp) |lsp| {
            if (self.editor.current_filename) |path| {
                lsp.notifyBufferChange(path) catch |err| {
                    std.log.warn("Failed to send LSP change notification: {}", .{err});
                };
            }
        }
    }

    pub fn makeEditorBridge(self: *SimpleTUI) runtime.PluginAPI.EditorContext.EditorBridge {
        return .{
            .ctx = @as(*anyopaque, @ptrCast(self)),
            .getCurrentBuffer = bridgeGetCurrentBuffer,
            .getCursorPosition = bridgeGetCursorPosition,
            .setCursorPosition = bridgeSetCursorPosition,
            .getSelection = bridgeGetSelection,
            .setSelection = bridgeSetSelection,
            .notifyChange = bridgeNotifyChange,
        };
    }

    fn requestLspHover(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No active file");
            return;
        };

        const line_idx = self.getCursorLine();
        const char_idx = self.getCursorColumn();
        const line = std.math.cast(u32, line_idx) orelse std.math.maxInt(u32);
        const character = std.math.cast(u32, char_idx) orelse std.math.maxInt(u32);

        lsp.requestHover(path, line, character) catch |err| {
            std.log.warn("Failed to request hover: {}", .{err});
            self.setStatusMessage("Hover request failed");
            return;
        };

        self.setStatusMessage("Hover requested");
    }

    fn requestLspDefinition(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No active file");
            return;
        };

        const line_idx = self.getCursorLine();
        const char_idx = self.getCursorColumn();
        const line = std.math.cast(u32, line_idx) orelse std.math.maxInt(u32);
        const character = std.math.cast(u32, char_idx) orelse std.math.maxInt(u32);

        lsp.requestDefinition(path, line, character) catch |err| {
            std.log.warn("Failed to request definition: {}", .{err});
            self.setStatusMessage("Definition request failed");
            return;
        };

        self.setStatusMessage("Definition requested");
    }

    fn triggerCodeActions(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No active file");
            return;
        };

        const line_idx = self.getCursorLine();
        const line = std.math.cast(u32, line_idx) orelse std.math.maxInt(u32);

        lsp.requestCodeActions(path, line, line) catch |err| {
            std.log.warn("Failed to request code actions: {}", .{err});
            self.setStatusMessage("Code actions request failed");
            return;
        };

        self.code_actions_active = true;
        self.code_actions_selected = 0;
        self.setStatusMessage("Code actions menu (j/k to navigate, Enter to apply, ESC to cancel)");
    }

    fn toggleInlayHints(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        lsp.inlay_hints_enabled = !lsp.inlay_hints_enabled;

        if (lsp.inlay_hints_enabled) {
            self.setStatusMessage("Inlay hints enabled");
        } else {
            self.setStatusMessage("Inlay hints disabled");
        }
    }

    fn applyPendingDefinition(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse return;

        while (lsp.takeDefinitionResult()) |result| {
            const def = result;
            defer lsp.freeDefinitionResult(def);

            const path_slice: []const u8 = def.path;
            const same_file = blk: {
                if (self.editor.current_filename) |current| {
                    break :blk std.mem.eql(u8, current, path_slice);
                }
                break :blk false;
            };

            if (!same_file) {
                const load_result = self.loadFile(path_slice);
                if (load_result) |_| {
                    self.markHighlightsDirty();
                } else |err| {
                    std.log.warn("Failed to open definition target '{s}': {}", .{ path_slice, err });
                    self.setStatusMessage("Definition open failed");
                    continue;
                }
            }

            const offset = lsp.offsetFromPosition(def.line, def.character);
            self.editor.cursor.offset = if (offset <= self.editor.rope.len()) offset else self.editor.rope.len();
            self.editor.selection_start = null;
            self.editor.selection_end = null;
            self.updatePluginCursorFromEditor();

            self.setStatusMessage("Jumped to definition");
        }
    }

    fn updatePluginCursorFromEditor(self: *SimpleTUI) void {
        if (self.plugin_cursor) |cursor_ptr| {
            const offset = self.editor.cursor.offset;
            cursor_ptr.byte_offset = offset;
            const lc = self.editor.rope.lineColumnAtOffset(offset) catch {
                cursor_ptr.line = 0;
                cursor_ptr.column = 0;
                return;
            };
            cursor_ptr.line = lc.line;
            cursor_ptr.column = lc.column;
        }
    }

    fn disableRawMode(self: *SimpleTUI) !void {
        // Show cursor
        try self.stdout.writeAll("\x1B[?25h");

        // Exit alternate screen buffer
        try self.stdout.writeAll("\x1B[?1049l");

        // Restore original terminal settings
        const stdin_fd = std.posix.STDIN_FILENO;
        try std.posix.tcsetattr(stdin_fd, .FLUSH, self.original_termios);
    }

    fn clearScreen(self: *SimpleTUI) !void {
        // Clear scrollback buffer + entire screen + move cursor to home position
        // \x1B[3J clears scrollback, \x1B[2J clears screen, \x1B[H moves to home
        try self.stdout.writeAll("\x1B[3J\x1B[2J\x1B[H");
    }

    fn setCursor(self: *SimpleTUI, row: usize, col: usize) !void {
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1B[{d};{d}H", .{ row, col });
        try self.stdout.writeAll(seq);
    }

    fn clearLineAt(self: *SimpleTUI, row: usize, width: usize) !void {
        try self.setCursor(row, 1);
        var blank: [128]u8 = undefined;
        const chunk = @min(blank.len, width);
        @memset(blank[0..chunk], ' ');
        var remaining = width;
        while (remaining > 0) {
            const emit = @min(chunk, remaining);
            try self.stdout.writeAll(blank[0..emit]);
            remaining -= emit;
        }
        try self.setCursor(row, 1);
    }

    fn renderCompletionBar(self: *SimpleTUI, width: usize, height: usize) !void {
        const status_row = if (height > 0) height else 1;
        const popup_height: usize = 6; // 4 entries + header/footer
        const popup_row = if (status_row > popup_height) status_row - popup_height else 1;

        var row = popup_row;
        var lines_to_clear: usize = popup_height;
        while (lines_to_clear > 0) : (lines_to_clear -= 1) {
            try self.clearLineAt(row, width);
            row += 1;
        }

        if (!self.completion_popup_active) return;

        const lsp = self.editor_lsp orelse {
            self.closeCompletionPopup();
            return;
        };

        var needs_refresh = self.completion_dirty;
        const generation = lsp.getCompletionGeneration();
        if (generation != self.completion_generation_seen) {
            self.completion_generation_seen = generation;
            needs_refresh = true;
        }

        if (needs_refresh) {
            self.refreshCompletionPrefix() catch {
                self.closeCompletionPopup();
                return;
            };

            if (self.completion_popup_active) {
                self.refreshCompletionDisplay(lsp);
            }
        }

        const list_window = popup_height - 2;
        if (self.completion_items.len == 0) {
            try self.displayCenteredMessage(popup_row, width, "Waiting for completions…");
            return;
        }

        const visible = self.computeVisibleCompletions(list_window);
        try self.renderCompletionList(popup_row, width, visible.start, visible.count);
    }

    const VisibleWindow = struct { start: usize, count: usize };

    fn computeVisibleCompletions(self: *SimpleTUI, capacity: usize) VisibleWindow {
        if (capacity == 0 or self.completion_items.len == 0) return .{ .start = 0, .count = 0 };

        const total = self.completion_items.len;
        const selected = self.completion_selected_index;

        const half = capacity / 2;
        var start = if (selected > half) selected - half else 0;
        if (start + capacity > total) {
            if (total > capacity) {
                start = total - capacity;
            } else {
                start = 0;
            }
        }

        const remaining = total - start;
        const count = if (remaining < capacity) remaining else capacity;
        return .{ .start = start, .count = count };
    }

    fn displayCenteredMessage(self: *SimpleTUI, row_start: usize, width: usize, message: []const u8) !void {
        const centered_col = if (message.len >= width) 1 else (width - message.len) / 2 + 1;
        try self.setCursor(row_start + 1, centered_col);
        try self.stdout.writeAll(message[0..@min(message.len, width)]);
    }

    fn renderCompletionList(self: *SimpleTUI, row_start: usize, width: usize, start: usize, count: usize) !void {
        const total = self.completion_items.len;
        const selected = self.completion_selected_index;
        const header_row = row_start;
        const list_row = row_start + 1;
        const detail_row = row_start + 4;
        const footer_row = row_start + 5;

        // Header
        try self.setCursor(header_row, 1);
        var header_buf: [128]u8 = undefined;
        const header_slice = try std.fmt.bufPrint(&header_buf, "Completions {d}/{d} (prefix: {s})", .{ selected + 1, total, self.completion_prefix.items });
        try self.stdout.writeAll(header_slice[0..@min(header_slice.len, width)]);

        // Entries
        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            const absolute = start + idx;
            const comp = self.completion_items[absolute];
            const is_selected = absolute == selected;

            var line_buf: [256]u8 = undefined;
            var written: usize = 0;
            const first = try std.fmt.bufPrint(line_buf[written..], "{s}{s}", .{ if (is_selected) "→ " else "  ", comp.label });
            written += first.len;
            if (comp.detail) |detail| {
                const detail_slice = try std.fmt.bufPrint(line_buf[written..], " — {s}", .{detail});
                written += detail_slice.len;
            }

            const slice = line_buf[0..written];
            try self.setCursor(list_row + idx, 1);
            try self.stdout.writeAll(slice[0..@min(slice.len, width)]);
        }

        // Inline documentation or detail preview
        try self.renderCompletionDetails(detail_row, width);

        // Footer
        try self.setCursor(footer_row, 1);
        const footer = "Tab/Ctrl+N next • Ctrl+P prev • Enter apply • Esc cancel";
        try self.stdout.writeAll(footer[0..@min(footer.len, width)]);
    }

    fn renderCompletionDetails(self: *SimpleTUI, row: usize, width: usize) !void {
        if (self.completion_items.len == 0) return;

        const comp = self.completion_items[self.completion_selected_index];
        try self.setCursor(row, 1);

        if (comp.documentation) |doc| {
            try self.writeWrapped(doc, width, row, 2);
        } else if (comp.detail) |detail| {
            try self.stdout.writeAll(detail[0..@min(detail.len, width)]);
        } else {
            const placeholder = "(no documentation available)";
            try self.stdout.writeAll(placeholder[0..@min(placeholder.len, width)]);
        }
    }

    fn writeWrapped(self: *SimpleTUI, text: []const u8, width: usize, row_start: usize, max_lines: usize) !void {
        var remaining = text;
        var row = row_start;
        var lines_written: usize = 0;
        while (remaining.len > 0 and lines_written < max_lines) {
            const take = @min(remaining.len, width);
            try self.setCursor(row, 1);
            try self.stdout.writeAll(remaining[0..take]);
            remaining = remaining[take..];
            row += 1;
            lines_written += 1;
        }
    }

    // Signature Help Popup (ghostls v0.3.0)
    fn renderSignatureHelpPopup(self: *SimpleTUI, width: usize, height: usize) !void {
        if (!self.signature_help_active) return;

        const lsp = self.editor_lsp orelse return;
        const sig_help = lsp.signature_help orelse {
            self.signature_help_active = false;
            return;
        };

        if (sig_help.signatures.len == 0) {
            self.signature_help_active = false;
            return;
        }

        // Position: above current line, leaving space for status line
        const cursor_line = self.getCursorLine();
        const popup_height: usize = 3; // Label + signature + doc snippet
        const popup_row = if (cursor_line > popup_height + 1) cursor_line - popup_height else 2;

        // Clear popup area
        var row = popup_row;
        var lines_to_clear: usize = popup_height;
        while (lines_to_clear > 0) : (lines_to_clear -= 1) {
            try self.clearLineAt(row, width);
            row += 1;
        }

        const active_sig_idx = @min(sig_help.active_signature, sig_help.signatures.len - 1);
        const active_sig = sig_help.signatures[active_sig_idx];

        // Header line
        try self.setCursor(popup_row, 1);
        try self.setColor(40, 37); // Dark background, white text
        var header_buf: [128]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf, " Signature {d}/{d} ", .{ active_sig_idx + 1, sig_help.signatures.len });
        try self.stdout.writeAll(header[0..@min(header.len, width)]);
        try self.resetColor();

        // Signature line with parameter highlighting
        try self.setCursor(popup_row + 1, 1);
        try self.renderSignatureWithHighlight(active_sig, sig_help.active_parameter, width);

        // Documentation line
        if (active_sig.documentation) |doc| {
            try self.setCursor(popup_row + 2, 1);
            const doc_display = if (doc.len > width) doc[0..width] else doc;
            try self.stdout.writeAll(doc_display);
        }

        _ = height; // Suppress unused warning
    }

    fn renderSignatureWithHighlight(self: *SimpleTUI, sig: editor_lsp_mod.SignatureHelp.SignatureInfo, active_param: u32, width: usize) !void {
        const label = sig.label;

        // Simple rendering: show full signature
        // TODO: In future, we could parse the label to find parameter positions and highlight
        const display_len = @min(label.len, width);
        try self.stdout.writeAll(label[0..display_len]);

        // If we have parameters and can highlight, show active parameter
        if (sig.parameters.len > 0 and active_param < sig.parameters.len) {
            const param = sig.parameters[active_param];
            // For now, just append parameter hint if space allows
            if (display_len + param.label.len + 4 < width) {
                try self.stdout.writeAll("  [");
                try self.setColor(43, 30); // Yellow background
                try self.stdout.writeAll(param.label);
                try self.resetColor();
                try self.stdout.writeAll("]");
            }
        }
    }

    // Code Actions Menu (ghostls v0.3.0)
    fn renderCodeActionsMenu(self: *SimpleTUI, width: usize, height: usize) !void {
        if (!self.code_actions_active) return;

        const lsp = self.editor_lsp orelse return;
        const actions = lsp.code_actions.items;

        if (actions.len == 0) {
            self.code_actions_active = false;
            return;
        }

        // Ensure selected index is valid
        if (self.code_actions_selected >= actions.len) {
            self.code_actions_selected = 0;
        }

        const menu_height = @min(actions.len + 2, 10); // +2 for header and border
        const cursor_line = self.getCursorLine();
        const menu_row = if (cursor_line > menu_height + 1) cursor_line - menu_height else 2;

        // Header
        try self.setCursor(menu_row, 1);
        try self.setColor(44, 37); // Blue background, white text
        var header_buf: [64]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf, " Code Actions ({d}) ", .{actions.len});
        try self.stdout.writeAll(header[0..@min(header.len, width)]);
        try self.resetColor();

        // Actions list
        const visible_actions = @min(actions.len, 8);
        var row = menu_row + 1;
        for (actions[0..visible_actions], 0..) |action, i| {
            try self.setCursor(row, 1);

            if (i == self.code_actions_selected) {
                try self.setColor(47, 30); // Selected: white bg, black text
            } else {
                try self.setColor(40, 37); // Normal: dark bg, white text
            }

            // Show prefix for preferred actions
            const prefix = if (action.is_preferred) "> " else "  ";
            var action_buf: [128]u8 = undefined;
            const action_text = try std.fmt.bufPrint(&action_buf, "{s}{s}", .{ prefix, action.title });
            const display = if (action_text.len > width) action_text[0..width] else action_text;
            try self.stdout.writeAll(display);

            // Pad the rest of the line
            var pad = if (display.len < width) width - display.len else 0;
            while (pad > 0) : (pad -= 1) {
                try self.stdout.writeAll(" ");
            }

            try self.resetColor();
            row += 1;
        }

        _ = height;
    }

    fn renderBufferPicker(self: *SimpleTUI, width: usize, height: usize) !void {
        if (!self.buffer_picker_active) return;

        const picker = self.buffer_picker orelse return;
        const info = picker.getRenderInfo();

        if (info.total_count == 0) {
            self.buffer_picker_active = false;
            return;
        }

        const menu_height = @min(info.visible_items.len + 3, 12); // +3 for header, search bar, border
        const menu_row: usize = if (height > menu_height + 2) (height - menu_height) / 2 else 2;
        const menu_width = @min(width - 4, 70);

        // Header
        try self.setCursor(menu_row, 2);
        try self.setColor(44, 37); // Blue background, white text
        const picker_icon = self.font_manager.getBufferPickerIcon();
        var header_buf: [128]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf, " {s} Buffers ({d}) ", .{ picker_icon, info.total_count });
        try self.stdout.writeAll(header[0..@min(header.len, menu_width)]);
        // Pad header
        if (header.len < menu_width) {
            var pad = menu_width - header.len;
            while (pad > 0) : (pad -= 1) {
                try self.stdout.writeAll(" ");
            }
        }
        try self.resetColor();

        // Search bar
        try self.setCursor(menu_row + 1, 2);
        try self.setColor(40, 37);
        const search_icon = self.font_manager.getSearchIcon();
        var search_buf: [128]u8 = undefined;
        const search_text = try std.fmt.bufPrint(&search_buf, " {s} {s}", .{ search_icon, info.query });
        try self.stdout.writeAll(search_text[0..@min(search_text.len, menu_width)]);
        // Pad search bar
        if (search_text.len < menu_width) {
            var pad = menu_width - search_text.len;
            while (pad > 0) : (pad -= 1) {
                try self.stdout.writeAll(" ");
            }
        }
        try self.resetColor();

        // Buffer list
        var row = menu_row + 2;
        const visible_count = @min(info.visible_items.len, 8);
        for (info.visible_items[0..visible_count], 0..) |buffer_item, i| {
            const is_selected = (info.visible_start + i) == info.selected_index;

            try self.setCursor(row, 2);

            if (is_selected) {
                try self.setColor(47, 30); // Selected: white bg, black text
            } else {
                try self.setColor(40, 37); // Normal: dark bg, white text
            }

            // Get file type icon
            const file_icon = if (buffer_item.file_path) |path|
                self.font_manager.getFileIcon(path)
            else
                self.font_manager.getFileIcon("untitled");

            // Modified indicator
            const modified_icon = if (buffer_item.modified)
                self.font_manager.getModifiedIcon()
            else
                " ";

            // Format buffer line: [icon] [modified] name (lines) language
            var buffer_buf: [256]u8 = undefined;
            const buffer_text = try std.fmt.bufPrint(&buffer_buf, " {s} {s} {s} ({d} lines) {s}", .{
                file_icon,
                modified_icon,
                buffer_item.display_name,
                buffer_item.line_count,
                buffer_item.language,
            });

            const display = if (buffer_text.len > menu_width) buffer_text[0..menu_width] else buffer_text;
            try self.stdout.writeAll(display);

            // Pad the rest of the line
            if (display.len < menu_width) {
                var pad = menu_width - display.len;
                while (pad > 0) : (pad -= 1) {
                    try self.stdout.writeAll(" ");
                }
            }

            try self.resetColor();
            row += 1;
        }
    }

    fn renderFileTree(self: *SimpleTUI, width: usize, height: usize) !void {
        if (!self.file_tree_active) return;
        const tree = self.file_tree orelse return;

        const tree_width = @min(self.file_tree_width, width / 2);
        const tree_height = height - 2; // Leave room for status line

        // Render file tree on the left side
        var row: usize = 1;
        for (tree.visible_entries.items[tree.scroll_offset..], tree.scroll_offset..) |entry, idx| {
            if (row > tree_height) break;

            try self.setCursor(row, 1);
            const is_selected = idx == tree.selected_index;

            // Background color
            if (is_selected) {
                try self.setColor(47, 30); // Selected: white bg, black text
            } else {
                try self.setColor(40, 37); // Normal: dark bg, white text
            }

            // Selection indicator
            if (is_selected) {
                try self.stdout.writeAll("> ");
            } else {
                try self.stdout.writeAll("  ");
            }

            // Indentation
            var i: usize = 0;
            while (i < entry.depth) : (i += 1) {
                try self.stdout.writeAll("  ");
            }

            // Expansion indicator for directories
            if (entry.is_dir) {
                if (entry.expanded) {
                    try self.stdout.writeAll("▼ ");
                } else {
                    try self.stdout.writeAll("▶ ");
                }
            } else {
                try self.stdout.writeAll("  ");
            }

            // File/directory name (truncate if too long)
            const max_name_len = tree_width - 4 - (entry.depth * 2) - 2;
            if (entry.name.len > max_name_len) {
                try self.stdout.writeAll(entry.name[0..max_name_len]);
            } else {
                try self.stdout.writeAll(entry.name);
            }

            // Pad the rest of the line
            const used_width = 2 + (entry.depth * 2) + 2 + @min(entry.name.len, max_name_len);
            if (used_width < tree_width) {
                var pad = tree_width - used_width;
                while (pad > 0) : (pad -= 1) {
                    try self.stdout.writeAll(" ");
                }
            }

            try self.resetColor();
            row += 1;
        }

        // Fill remaining lines with background
        while (row <= tree_height) : (row += 1) {
            try self.setCursor(row, 1);
            try self.setColor(40, 37);
            var pad: usize = 0;
            while (pad < tree_width) : (pad += 1) {
                try self.stdout.writeAll(" ");
            }
            try self.resetColor();
        }

        // Draw vertical separator
        row = 1;
        while (row <= tree_height) : (row += 1) {
            try self.setCursor(row, tree_width + 1);
            try self.setColor(47, 30);
            try self.stdout.writeAll("│");
            try self.resetColor();
        }
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

    fn afterTextEdit(self: *SimpleTUI) void {
        self.markHighlightsDirty();
        self.updatePluginCursorFromEditor();
        if (self.editor_lsp) |lsp| {
            if (self.editor.current_filename) |path| {
                lsp.notifyBufferChange(path) catch |err| {
                    std.log.warn("Failed to send LSP change notification: {}", .{err});
                };
            }
        }
    }

    fn clearCompletionDisplay(self: *SimpleTUI) void {
        if (self.completion_items_heap and self.completion_items.len > 0) {
            self.allocator.free(self.completion_items);
            self.completion_items_heap = false;
        }
        self.completion_items = &.{};
        self.completion_selected_index = 0;
    }

    fn closeCompletionPopup(self: *SimpleTUI) void {
        if (!self.completion_popup_active) return;
        self.completion_popup_active = false;
        self.completion_anchor_offset = null;
        self.completion_generation_seen = 0;
        self.completion_dirty = false;
        self.clearCompletionDisplay();
        self.completion_prefix.clearRetainingCapacity();
    }

    fn isWordChar(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '_';
    }

    fn captureCompletionContext(self: *SimpleTUI) !void {
        const cursor_offset = self.editor.cursor.offset;
        const head = try self.editor.rope.slice(.{ .start = 0, .end = cursor_offset });
        // Note: rope.slice() returns arena-allocated memory, do NOT free

        var anchor = cursor_offset;
        while (anchor > 0) {
            const ch = head[anchor - 1];
            if (!isWordChar(ch)) break;
            anchor -= 1;
        }

        self.completion_anchor_offset = anchor;
        self.completion_prefix.clearRetainingCapacity();
        const prefix_slice = head[anchor..];
        if (prefix_slice.len > 0) {
            try self.completion_prefix.appendSlice(self.allocator, prefix_slice);
        }
    }

    fn refreshCompletionPrefix(self: *SimpleTUI) !void {
        const anchor = self.completion_anchor_offset orelse {
            self.closeCompletionPopup();
            return;
        };

        const cursor_offset = self.editor.cursor.offset;
        if (cursor_offset < anchor) {
            self.closeCompletionPopup();
            return;
        }

        const slice = try self.editor.rope.slice(.{ .start = anchor, .end = cursor_offset });
        defer self.allocator.free(slice);

        self.completion_prefix.clearRetainingCapacity();
        if (slice.len > 0) {
            try self.completion_prefix.appendSlice(self.allocator, slice);
        }
    }

    fn refreshCompletionDisplay(self: *SimpleTUI, lsp: *editor_lsp_mod.EditorLSP) void {
        self.clearCompletionDisplay();

        const filtered = lsp.filterCompletions(self.allocator, self.completion_prefix.items) catch |err| {
            std.log.warn("Failed to filter completions: {}", .{err});
            self.setStatusMessage("Completion update failed");
            return;
        };

        self.completion_items = filtered;
        self.completion_items_heap = true;
        if (self.completion_items.len == 0) {
            self.completion_selected_index = 0;
        } else if (self.completion_selected_index >= self.completion_items.len) {
            self.completion_selected_index = self.completion_items.len - 1;
        }
        self.completion_dirty = false;
    }

    fn triggerCompletionRequest(self: *SimpleTUI) void {
        const lsp = self.editor_lsp orelse {
            self.setStatusMessage("LSP inactive");
            return;
        };

        const path = self.editor.current_filename orelse {
            self.setStatusMessage("No active file");
            return;
        };

        self.clearCompletionDisplay();

        self.captureCompletionContext() catch |err| {
            std.log.warn("Failed to capture completion context: {}", .{err});
            self.setStatusMessage("Completion unavailable");
            return;
        };

        const line_idx = self.getCursorLine();
        const col_idx = self.getCursorColumn();
        const line = std.math.cast(u32, line_idx) orelse std.math.maxInt(u32);
        const character = std.math.cast(u32, col_idx) orelse std.math.maxInt(u32);

        lsp.requestCompletion(path, line, character) catch |err| {
            std.log.warn("Failed to request completion: {}", .{err});
            self.setStatusMessage("Completion request failed");
            self.closeCompletionPopup();
            return;
        };

        self.completion_popup_active = true;
        self.completion_selected_index = 0;
        self.completion_dirty = true;
        self.completion_generation_seen = lsp.getCompletionGeneration();
    }

    fn maybeTriggerAutoCompletion(self: *SimpleTUI, typed_char: u8) void {
        const lsp = self.editor_lsp orelse return;
        if (!lsp.shouldTriggerCompletion(typed_char)) return;
        self.triggerCompletionRequest();
    }

    fn maybeTriggerSignatureHelp(self: *SimpleTUI, typed_char: u8) void {
        // Trigger on '(' or ',' - common signature help triggers
        if (typed_char != '(' and typed_char != ',') {
            // Close signature help if typing other characters
            if (typed_char == ')') {
                self.signature_help_active = false;
            }
            return;
        }

        const lsp = self.editor_lsp orelse return;
        const current_file = lsp.current_file orelse return;

        // Calculate line and character from offset
        const cursor_offset = self.editor.cursor.offset;
        const content = self.editor.rope.slice(.{ .start = 0, .end = cursor_offset }) catch return;
        defer self.allocator.free(content);

        var line: u32 = 0;
        var character: u32 = 0;
        for (content) |ch| {
            if (ch == '\n') {
                line += 1;
                character = 0;
            } else {
                character += 1;
            }
        }

        lsp.requestSignatureHelp(current_file, line, character) catch |err| {
            std.log.warn("Failed to request signature help: {}", .{err});
            return;
        };

        self.signature_help_active = true;
        self.signature_help_last_offset = self.editor.cursor.offset;
    }

    fn moveCompletionSelection(self: *SimpleTUI, direction: i32) void {
        if (!self.completion_popup_active) return;
        if (self.completion_items.len == 0) return;

        const len = self.completion_items.len;
        if (direction > 0) {
            self.completion_selected_index = (self.completion_selected_index + 1) % len;
        } else if (direction < 0) {
            if (self.completion_selected_index == 0) {
                self.completion_selected_index = len - 1;
            } else {
                self.completion_selected_index -= 1;
            }
        }
    }

    fn acceptCompletionSelection(self: *SimpleTUI) !void {
        if (!self.completion_popup_active) return;
        if (self.completion_items.len == 0) {
            self.closeCompletionPopup();
            return;
        }

        const anchor = self.completion_anchor_offset orelse {
            self.closeCompletionPopup();
            return;
        };

        const comp = self.completion_items[self.completion_selected_index];
        try self.applyCompletion(comp, anchor);
        self.setStatusMessage("Inserted completion");
        self.closeCompletionPopup();
    }

    const SelectionRange = struct { start: usize, end: usize };

    fn applyCompletion(self: *SimpleTUI, comp: editor_lsp_mod.Completion, anchor: usize) !void {
        var selection: ?SelectionRange = null;

        if (comp.text_edit) |edit| {
            selection = try self.applyTextEditCompletion(edit, comp.insert_text_format);
        } else {
            const cursor_offset = self.editor.cursor.offset;
            if (cursor_offset < anchor) return;

            const prefix_len = cursor_offset - anchor;
            if (prefix_len > 0) {
                try self.editor.rope.delete(anchor, prefix_len);
            }

            const insert_text = comp.insert_text orelse comp.label;
            if (comp.insert_text_format == .snippet) {
                selection = try self.insertSnippetText(anchor, insert_text);
            } else {
                try self.editor.rope.insert(anchor, insert_text);
                self.editor.cursor.offset = anchor + insert_text.len;
            }
        }

        if (selection) |sel| {
            if (sel.start != sel.end) {
                self.editor.selection_start = sel.start;
                self.editor.selection_end = sel.end;
            } else {
                self.editor.selection_start = null;
                self.editor.selection_end = null;
            }
        } else {
            self.editor.selection_start = null;
            self.editor.selection_end = null;
        }

        self.updatePluginCursorFromEditor();
        self.afterTextEdit();
    }

    fn applyTextEditCompletion(
        self: *SimpleTUI,
        edit: editor_lsp_mod.Completion.TextEdit,
        format: editor_lsp_mod.Completion.InsertTextFormat,
    ) !?SelectionRange {
        if (self.editor_lsp == null) return null;

        const lsp = self.editor_lsp.?;
        const start_offset = lsp.offsetFromPosition(edit.range.start.line, edit.range.start.character);
        const end_offset = lsp.offsetFromPosition(edit.range.end.line, edit.range.end.character);

        if (end_offset > start_offset) {
            try self.editor.rope.delete(start_offset, end_offset - start_offset);
        }

        switch (format) {
            .snippet => {
                const expansion = self.expandSnippet(edit.new_text) catch |err| {
                    std.log.warn("Failed to expand snippet text edit: {}", .{err});
                    try self.editor.rope.insert(start_offset, edit.new_text);
                    self.editor.cursor.offset = start_offset + edit.new_text.len;
                    return null;
                };
                defer self.allocator.free(expansion.text);

                try self.editor.rope.insert(start_offset, expansion.text);
                self.editor.cursor.offset = start_offset + expansion.caret;

                if (expansion.selection) |sel| {
                    return .{ .start = start_offset + sel.start, .end = start_offset + sel.end };
                }
                return null;
            },
            .plain_text => {
                try self.editor.rope.insert(start_offset, edit.new_text);
                self.editor.cursor.offset = start_offset + edit.new_text.len;
                return null;
            },
        }
    }

    fn insertSnippetText(self: *SimpleTUI, anchor: usize, snippet: []const u8) !?SelectionRange {
        const expansion = self.expandSnippet(snippet) catch |err| {
            std.log.warn("Failed to expand snippet: {}", .{err});
            try self.editor.rope.insert(anchor, snippet);
            self.editor.cursor.offset = anchor + snippet.len;
            return null;
        };
        defer self.allocator.free(expansion.text);

        try self.editor.rope.insert(anchor, expansion.text);
        self.editor.cursor.offset = anchor + expansion.caret;

        if (expansion.selection) |sel| {
            return .{ .start = anchor + sel.start, .end = anchor + sel.end };
        }
        return null;
    }

    const SnippetExpansion = struct {
        text: []u8,
        caret: usize,
        selection: ?SelectionRange,
    };

    fn expandSnippet(self: *SimpleTUI, snippet: []const u8) !SnippetExpansion {
        var buffer = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        errdefer buffer.deinit(self.allocator);

        const PlaceholderInfo = struct {
            id: u32,
            offset: usize,
            length: usize,
        };

        var best_placeholder: ?PlaceholderInfo = null;
        var final_stop: ?PlaceholderInfo = null;

        var idx: usize = 0;
        while (idx < snippet.len) {
            const ch = snippet[idx];
            if (ch == '\\' and idx + 1 < snippet.len) {
                try buffer.append(self.allocator, snippet[idx + 1]);
                idx += 2;
                continue;
            }

            if (ch == '$') {
                if (idx + 1 < snippet.len and std.ascii.isDigit(snippet[idx + 1])) {
                    var j = idx + 1;
                    while (j < snippet.len and std.ascii.isDigit(snippet[j])) j += 1;
                    const id_slice = snippet[idx + 1 .. j];
                    const id = std.fmt.parseUnsigned(u32, id_slice, 10) catch {
                        try buffer.append(self.allocator, '$');
                        idx += 1;
                        continue;
                    };

                    const info = PlaceholderInfo{ .id = id, .offset = buffer.items.len, .length = 0 };
                    if (id == 0) {
                        if (final_stop == null) final_stop = info;
                    } else if (best_placeholder == null or id < best_placeholder.?.id) {
                        best_placeholder = info;
                    }
                    idx = j;
                    continue;
                } else if (idx + 1 < snippet.len and snippet[idx + 1] == '{') {
                    var j = idx + 2;
                    var depth: usize = 1;
                    while (j < snippet.len) {
                        const c = snippet[j];
                        if (c == '\\' and j + 1 < snippet.len) {
                            j += 2;
                            continue;
                        } else if (c == '{') {
                            depth += 1;
                            j += 1;
                            continue;
                        } else if (c == '}') {
                            depth -= 1;
                            if (depth == 0) break;
                            j += 1;
                            continue;
                        } else {
                            j += 1;
                        }
                    }

                    if (depth != 0 or j >= snippet.len) {
                        try buffer.append(self.allocator, '$');
                        idx += 1;
                        continue;
                    }

                    const body = snippet[idx + 2 .. j];
                    if (parseSnippetPlaceholder(body)) |placeholder| {
                        const placeholder_offset = buffer.items.len;
                        var inserted_len: usize = 0;
                        if (placeholder.default_text) |default_slice| {
                            const normalized = normalizePlaceholderDefault(default_slice);
                            inserted_len = buffer.items.len;
                            try appendSnippetPlain(&buffer, self.allocator, normalized);
                            inserted_len = buffer.items.len - placeholder_offset;
                        }

                        const info = PlaceholderInfo{
                            .id = placeholder.id,
                            .offset = placeholder_offset,
                            .length = inserted_len,
                        };

                        if (placeholder.id == 0) {
                            if (final_stop == null) final_stop = info;
                        } else if (best_placeholder == null or placeholder.id < best_placeholder.?.id) {
                            best_placeholder = info;
                        }

                        idx = j + 1;
                        continue;
                    }

                    try buffer.append(self.allocator, '$');
                    idx += 1;
                    continue;
                }
            }

            try buffer.append(self.allocator, ch);
            idx += 1;
        }

        const final_len = buffer.items.len;
        const fallback = PlaceholderInfo{ .id = 0, .offset = final_len, .length = 0 };
        const chosen = if (best_placeholder) |sel|
            sel
        else if (final_stop) |sel|
            sel
        else
            fallback;

        const text = try buffer.toOwnedSlice(self.allocator);
        const caret = chosen.offset + chosen.length;
        const selection = if (chosen.length > 0)
            SelectionRange{ .start = chosen.offset, .end = chosen.offset + chosen.length }
        else
            null;

        return SnippetExpansion{
            .text = text,
            .caret = caret,
            .selection = selection,
        };
    }

    const SnippetPlaceholder = struct {
        id: u32,
        default_text: ?[]const u8,
    };

    fn parseSnippetPlaceholder(body: []const u8) ?SnippetPlaceholder {
        if (body.len == 0) return null;
        var i: usize = 0;
        while (i < body.len and std.ascii.isDigit(body[i])) : (i += 1) {}
        if (i == 0) return null;

        const id_slice = body[0..i];
        const id = std.fmt.parseUnsigned(u32, id_slice, 10) catch return null;

        if (i >= body.len) {
            return SnippetPlaceholder{ .id = id, .default_text = null };
        }

        return SnippetPlaceholder{ .id = id, .default_text = body[i..] };
    }

    fn normalizePlaceholderDefault(default_slice: []const u8) []const u8 {
        if (default_slice.len == 0) return default_slice;

        if (default_slice[0] == ':') {
            return default_slice[1..];
        }

        if (default_slice[0] == '|' and default_slice.len > 1) {
            const rest = default_slice[1..];
            if (std.mem.indexOfScalar(u8, rest, '|')) |end_idx| {
                const choices = rest[0..end_idx];
                if (std.mem.indexOfScalar(u8, choices, ',')) |comma| {
                    return choices[0..comma];
                }
                return choices;
            }
            return rest;
        }

        return default_slice;
    }

    fn appendSnippetPlain(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
        var idx: usize = 0;
        while (idx < text.len) {
            const ch = text[idx];
            if (ch == '\\' and idx + 1 < text.len) {
                try buffer.append(allocator, text[idx + 1]);
                idx += 2;
            } else {
                try buffer.append(allocator, ch);
                idx += 1;
            }
        }
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
            // Suppress ParserNotInitialized - this is expected before file is loaded
            if (err == error.ParserNotInitialized) {
                return;
            }

            // Store error message for other errors
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

    const LineDiagnostic = struct {
        severity: editor_lsp_mod.Diagnostic.Severity,
        message: []const u8,
    };

    fn selectLineDiagnostic(diags: []const editor_lsp_mod.Diagnostic, line_usize: usize) ?LineDiagnostic {
        if (line_usize > std.math.maxInt(u32)) return null;
        const line_val: u32 = @intCast(line_usize);
        var best: ?LineDiagnostic = null;
        var best_score: u8 = 0;

        for (diags) |diag| {
            if (line_val < diag.range.start.line or line_val > diag.range.end.line) continue;
            const score = severityScore(diag.severity);
            if (score > best_score) {
                best_score = score;
                best = .{ .severity = diag.severity, .message = diag.message };
            }
        }

        return best;
    }

    fn severityScore(severity: editor_lsp_mod.Diagnostic.Severity) u8 {
        return switch (severity) {
            .error_sev => 4,
            .warning => 3,
            .information => 2,
            .hint => 1,
        };
    }

    fn severityMarker(severity: editor_lsp_mod.Diagnostic.Severity) u8 {
        return switch (severity) {
            .error_sev => 'E',
            .warning => 'W',
            .information => 'I',
            .hint => 'H',
        };
    }

    fn severityLabel(severity: editor_lsp_mod.Diagnostic.Severity) []const u8 {
        return switch (severity) {
            .error_sev => "ERR",
            .warning => "WARN",
            .information => "INFO",
            .hint => "HINT",
        };
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

    fn renderPlainLineWithHints(self: *SimpleTUI, line: []const u8, hints: []const editor_lsp_mod.InlayHint, max_width: usize) !void {
        if (hints.len == 0) {
            try self.renderPlainLine(line, max_width);
            return;
        }

        var written: usize = 0;
        var col: usize = 0;
        var hint_idx: usize = 0;

        while (col < line.len and written < max_width) {
            // Check if we should insert a hint at this position
            if (hint_idx < hints.len and hints[hint_idx].position.character == col) {
                const hint = hints[hint_idx];

                // Render hint with dim color (gray)
                try self.stdout.writeAll("\x1b[90m"); // ANSI bright black (gray)
                const hint_display_len = @min(hint.label.len, max_width - written);
                if (hint_display_len > 0) {
                    try self.stdout.writeAll(hint.label[0..hint_display_len]);
                    written += hint_display_len;
                }
                try self.resetColor();

                hint_idx += 1;
                if (written >= max_width) break;
            }

            // Write the actual character
            if (written < max_width) {
                try self.stdout.writeAll(line[col .. col + 1]);
                written += 1;
                col += 1;
            }
        }

        // Pad remaining width
        while (written < max_width) : (written += 1) {
            try self.stdout.writeAll(" ");
        }
    }

    // Helper to get inlay hints for a specific line, sorted by character position
    fn getInlayHintsForLine(self: *SimpleTUI, line_num: usize) []const editor_lsp_mod.InlayHint {
        const lsp = self.editor_lsp orelse return &[_]editor_lsp_mod.InlayHint{};
        if (!lsp.inlay_hints_enabled) return &[_]editor_lsp_mod.InlayHint{};

        var hints_for_line = std.ArrayList(editor_lsp_mod.InlayHint){};
        defer hints_for_line.deinit(self.allocator);

        for (lsp.inlay_hints.items) |hint| {
            if (hint.position.line == line_num) {
                hints_for_line.append(self.allocator, hint) catch continue;
            }
        }

        // Sort by character position
        if (hints_for_line.items.len > 0) {
            std.mem.sort(editor_lsp_mod.InlayHint, hints_for_line.items, {}, struct {
                fn lessThan(_: void, a: editor_lsp_mod.InlayHint, b: editor_lsp_mod.InlayHint) bool {
                    return a.position.character < b.position.character;
                }
            }.lessThan);
        }

        // Return owned slice (caller must free)
        return hints_for_line.toOwnedSlice(self.allocator) catch &[_]editor_lsp_mod.InlayHint{};
    }

    fn renderHighlightedLine(self: *SimpleTUI, line: []const u8, line_num: usize, max_width: usize) !void {
        if (max_width == 0) return;

        // Get inlay hints for this line
        const hints = self.getInlayHintsForLine(line_num);
        defer if (hints.len > 0) self.allocator.free(hints);

        const line_len = line.len;
        if (self.highlight_cache.len == 0) {
            try self.renderPlainLineWithHints(line, hints, max_width);
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
            try self.renderPlainLineWithHints(line, hints, max_width);
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
        var hint_idx: usize = 0;
        var color_active = false;
        var active_type: ?syntax.HighlightType = null;
        var seq_buf: [32]u8 = undefined;

        while (col < line_len and written < max_width) {
            // Check if we should insert a hint at current column position
            while (hint_idx < hints.len and hints[hint_idx].position.character == col) {
                const hint = hints[hint_idx];

                // Reset any active syntax highlighting color
                if (color_active) {
                    try self.resetColor();
                    color_active = false;
                    active_type = null;
                }

                // Render hint with dim gray color
                try self.stdout.writeAll("\x1b[90m");
                const hint_display_len = @min(hint.label.len, max_width - written);
                if (hint_display_len > 0) {
                    try self.stdout.writeAll(hint.label[0..hint_display_len]);
                    written += hint_display_len;
                }
                try self.resetColor();

                hint_idx += 1;
                if (written >= max_width) break;
            }

            if (written >= max_width) break;
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
                    const seq = self.active_theme.getHighlightSequence(ht, &seq_buf) catch |err| {
                        std.log.err("Failed to build highlight sequence: {}", .{err});
                        return err;
                    };
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

    // Buffer picker and window management functions

    fn activateBufferPicker(self: *SimpleTUI) void {
        // Initialize buffer manager if needed
        if (self.buffer_manager == null) {
            const buf_mgr = self.allocator.create(buffer_manager_mod.BufferManager) catch {
                self.setStatusMessage("Failed to create buffer manager");
                return;
            };
            buf_mgr.* = buffer_manager_mod.BufferManager.init(self.allocator) catch {
                self.allocator.destroy(buf_mgr);
                self.setStatusMessage("Failed to initialize buffer manager");
                return;
            };
            self.buffer_manager = buf_mgr;
        }

        // Initialize buffer picker if needed
        if (self.buffer_picker == null) {
            const buf_mgr = self.buffer_manager.?;
            const picker = self.allocator.create(buffer_picker_mod.BufferPicker) catch {
                self.setStatusMessage("Failed to create buffer picker");
                return;
            };
            picker.* = buffer_picker_mod.BufferPicker.init(self.allocator, buf_mgr);
            self.buffer_picker = picker;
        }

        self.buffer_picker_active = true;
        self.setStatusMessage("Buffer picker active (ESC to cancel, Enter to select)");
    }

    fn handleBufferPickerInput(self: *SimpleTUI, key: u8) !void {
        const picker = self.buffer_picker orelse return;

        switch (key) {
            27 => { // ESC
                self.buffer_picker_active = false;
                self.clearStatusMessage();
            },
            13 => { // Enter
                if (picker.getSelectedBufferId()) |selected_id| {
                    self.buffer_picker_active = false;
                    self.clearStatusMessage();
                    // Switch to selected buffer
                    if (self.buffer_manager) |buf_mgr| {
                        buf_mgr.switchToBuffer(selected_id) catch |err| {
                            std.log.warn("Failed to switch buffer: {}", .{err});
                            self.setStatusMessage("Failed to switch buffer");
                        };
                    }
                }
            },
            8, 127 => { // Backspace
                picker.backspaceQuery() catch {};
            },
            else => {
                if (key >= 32 and key < 127) { // Printable ASCII
                    picker.appendToQuery(key) catch |err| {
                        std.log.warn("Buffer picker input error: {}", .{err});
                    };
                }
            },
        }
    }

    fn handleCodeActionsInput(self: *SimpleTUI, key: u8) !void {
        const lsp = self.editor_lsp orelse return;
        const actions = lsp.code_actions.items;

        switch (key) {
            27 => { // ESC
                self.code_actions_active = false;
                self.clearStatusMessage();
            },
            13 => { // Enter - apply selected action
                if (self.code_actions_selected < actions.len) {
                    const action = actions[self.code_actions_selected];
                    self.setStatusMessage("Code action not yet implemented"); // TODO: Apply action
                    std.log.info("Selected code action: {s}", .{action.title});
                    self.code_actions_active = false;
                }
            },
            'j', 'J' => { // Move down
                if (actions.len > 0) {
                    self.code_actions_selected = (self.code_actions_selected + 1) % actions.len;
                }
            },
            'k', 'K' => { // Move up
                if (actions.len > 0) {
                    if (self.code_actions_selected == 0) {
                        self.code_actions_selected = actions.len - 1;
                    } else {
                        self.code_actions_selected -= 1;
                    }
                }
            },
            else => {},
        }
    }

    fn performUndo(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse {
                self.setStatusMessage("No active buffer");
                return;
            };

            buffer.phantom_buffer.undo() catch |err| {
                switch (err) {
                    error.NothingToUndo => {
                        self.setStatusMessage("Already at oldest change");
                        return;
                    },
                    else => return err,
                }
            };

            // Sync back to editor for rendering
            try self.syncEditorFromPhantomBuffer();
            self.setStatusMessage("Undo");
        } else {
            self.setStatusMessage("Undo not available (PhantomBuffer not enabled)");
        }
    }

    fn performRedo(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse {
                self.setStatusMessage("No active buffer");
                return;
            };

            buffer.phantom_buffer.redo() catch |err| {
                switch (err) {
                    error.NothingToRedo => {
                        self.setStatusMessage("Already at newest change");
                        return;
                    },
                    else => return err,
                }
            };

            // Sync back to editor for rendering
            try self.syncEditorFromPhantomBuffer();
            self.setStatusMessage("Redo");
        } else {
            self.setStatusMessage("Redo not available (PhantomBuffer not enabled)");
        }
    }

    // PhantomBuffer text operation wrappers
    fn insertCharWithUndo(self: *SimpleTUI, key: u21) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;

            var buf: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(key, &buf);

            // Check if multi-cursor is active
            if (buffer.phantom_buffer.cursor_positions.items.len > 1) {
                // Multi-cursor insert - insert at all cursor positions
                // Start from the end to maintain offsets
                var i = buffer.phantom_buffer.cursor_positions.items.len;
                var offset_adjustment: usize = 0;

                while (i > 0) {
                    i -= 1;
                    const cursor_pos = buffer.phantom_buffer.cursor_positions.items[i];
                    const insert_offset = cursor_pos.byte_offset + (offset_adjustment * i);

                    try buffer.phantom_buffer.insertText(insert_offset, buf[0..len]);

                    // Update cursor position
                    buffer.phantom_buffer.cursor_positions.items[i].byte_offset += len;
                    buffer.phantom_buffer.cursor_positions.items[i].column += len;
                }

                offset_adjustment = len;
            } else {
                // Single cursor insert
                const offset = self.editor.cursor.offset;
                try buffer.phantom_buffer.insertText(offset, buf[0..len]);
                self.editor.cursor.offset = offset + len;
            }

            try self.syncEditorFromPhantomBuffer();
        } else {
            try self.editor.insertChar(key);
        }
    }

    fn deleteCharWithUndo(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;
            const offset = self.editor.cursor.offset;

            if (offset >= buffer.phantom_buffer.rope.len()) return;

            // Find UTF-8 character length
            const slice = try buffer.phantom_buffer.rope.slice(.{ .start = offset, .end = buffer.phantom_buffer.rope.len() });
            var char_len: usize = 1;
            while (char_len < slice.len and (slice[char_len] & 0xC0) == 0x80) : (char_len += 1) {}

            try buffer.phantom_buffer.deleteRange(.{ .start = offset, .end = offset + char_len });
            try self.syncEditorFromPhantomBuffer();
        } else {
            try self.editor.deleteChar();
        }
    }

    fn backspaceWithUndo(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;
            const offset = self.editor.cursor.offset;

            if (offset == 0) return;

            // Move cursor left to find character boundary
            var new_offset = offset - 1;
            const slice = try buffer.phantom_buffer.rope.slice(.{ .start = 0, .end = offset });
            while (new_offset > 0 and (slice[new_offset] & 0xC0) == 0x80) : (new_offset -= 1) {}

            try buffer.phantom_buffer.deleteRange(.{ .start = new_offset, .end = offset });
            try self.syncEditorFromPhantomBuffer();
            self.editor.cursor.offset = new_offset;
        } else {
            try self.editor.backspace();
        }
    }

    fn insertNewlineAfterWithUndo(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;

            // Move to line end
            self.editor.cursor.moveToLineEnd(&self.editor.rope);
            const offset = self.editor.cursor.offset;

            try buffer.phantom_buffer.insertText(offset, "\n");
            try self.syncEditorFromPhantomBuffer();
            self.editor.cursor.offset = offset + 1;
        } else {
            try self.editor.insertNewlineAfter();
        }
    }

    fn insertNewlineBeforeWithUndo(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;

            // Move to line start
            self.editor.cursor.moveToLineStart(&self.editor.rope);
            const offset = self.editor.cursor.offset;

            try buffer.phantom_buffer.insertText(offset, "\n");
            try self.syncEditorFromPhantomBuffer();
            // Cursor stays at same offset (now on the new line)
        } else {
            try self.editor.insertNewlineBefore();
        }
    }

    fn syncEditorFromPhantomBuffer(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return;

            // Clear editor's rope
            const old_len = self.editor.rope.len();
            if (old_len > 0) {
                try self.editor.rope.delete(0, old_len);
            }

            // Copy content from PhantomBuffer
            const content = try buffer.phantom_buffer.getContent();
            defer self.allocator.free(content);

            if (content.len > 0) {
                try self.editor.rope.insert(0, content);
            }
        }
    }

    fn deleteLineWithUndo(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;

            // Find line boundaries
            self.editor.cursor.moveToLineStart(&self.editor.rope);
            const start = self.editor.cursor.offset;
            self.editor.cursor.moveToLineEnd(&self.editor.rope);
            var end = self.editor.cursor.offset;

            // Include the newline if not at end of file
            if (end < self.editor.rope.len()) {
                end += 1;
            }

            if (end > start) {
                // Store in yank buffer before deleting
                const deleted = try buffer.phantom_buffer.rope.slice(.{ .start = start, .end = end });
                if (self.editor.yank_buffer) |old_buf| {
                    self.allocator.free(old_buf);
                }
                self.editor.yank_buffer = try self.allocator.dupe(u8, deleted);
                self.editor.yank_linewise = true;

                // Delete the line
                try buffer.phantom_buffer.deleteRange(.{ .start = start, .end = end });
                try self.syncEditorFromPhantomBuffer();
                self.editor.cursor.offset = start;
            }
        } else {
            // Find line boundaries and yank
            self.editor.cursor.moveToLineStart(&self.editor.rope);
            const start = self.editor.cursor.offset;
            self.editor.cursor.moveToLineEnd(&self.editor.rope);
            var end = self.editor.cursor.offset;

            if (end < self.editor.rope.len()) {
                end += 1;
            }

            if (end > start) {
                const deleted = try self.editor.rope.slice(.{ .start = start, .end = end });
                if (self.editor.yank_buffer) |old_buf| {
                    self.allocator.free(old_buf);
                }
                self.editor.yank_buffer = try self.allocator.dupe(u8, deleted);
                self.editor.yank_linewise = true;

                try self.editor.rope.delete(start, end - start);
                self.editor.cursor.offset = start;
            }
        }
    }

    fn yankLine(self: *SimpleTUI) !void {
        // Find line boundaries
        self.editor.cursor.moveToLineStart(&self.editor.rope);
        const start = self.editor.cursor.offset;
        self.editor.cursor.moveToLineEnd(&self.editor.rope);
        var end = self.editor.cursor.offset;

        // Include the newline if not at end of file
        if (end < self.editor.rope.len()) {
            end += 1;
        }

        if (end > start) {
            const yanked = try self.editor.rope.slice(.{ .start = start, .end = end });

            // Free old yank buffer
            if (self.editor.yank_buffer) |old_buf| {
                self.allocator.free(old_buf);
            }

            // Store yanked content
            self.editor.yank_buffer = try self.allocator.dupe(u8, yanked);
            self.editor.yank_linewise = true;
            self.editor.cursor.offset = start;
            self.setStatusMessage("Yanked line");
        }
    }

    fn pasteAfter(self: *SimpleTUI) !void {
        const yanked = self.editor.yank_buffer orelse return;

        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;

            if (self.editor.yank_linewise) {
                // Paste on next line
                self.editor.cursor.moveToLineEnd(&self.editor.rope);
                const insert_pos = if (self.editor.cursor.offset < self.editor.rope.len())
                    self.editor.cursor.offset + 1
                else
                    self.editor.cursor.offset;

                // If at end of file and no trailing newline, add one first
                if (insert_pos == self.editor.rope.len() and self.editor.rope.len() > 0) {
                    const last_char = (try self.editor.rope.slice(.{ .start = self.editor.rope.len() - 1, .end = self.editor.rope.len() }))[0];
                    if (last_char != '\n') {
                        try buffer.phantom_buffer.insertText(self.editor.rope.len(), "\n");
                    }
                }

                try buffer.phantom_buffer.insertText(insert_pos, yanked);
                try self.syncEditorFromPhantomBuffer();
                self.editor.cursor.offset = insert_pos;
            } else {
                // Character-wise paste after cursor
                self.editor.cursor.moveRight(&self.editor.rope);
                const insert_pos = self.editor.cursor.offset;
                try buffer.phantom_buffer.insertText(insert_pos, yanked);
                try self.syncEditorFromPhantomBuffer();
                self.editor.cursor.offset = insert_pos + yanked.len;
            }
        } else {
            if (self.editor.yank_linewise) {
                self.editor.cursor.moveToLineEnd(&self.editor.rope);
                const insert_pos = if (self.editor.cursor.offset < self.editor.rope.len())
                    self.editor.cursor.offset + 1
                else
                    self.editor.cursor.offset;

                if (insert_pos == self.editor.rope.len() and self.editor.rope.len() > 0) {
                    const last_char = (try self.editor.rope.slice(.{ .start = self.editor.rope.len() - 1, .end = self.editor.rope.len() }))[0];
                    if (last_char != '\n') {
                        try self.editor.rope.insert(self.editor.rope.len(), "\n");
                    }
                }

                try self.editor.rope.insert(insert_pos, yanked);
                self.editor.cursor.offset = insert_pos;
            } else {
                self.editor.cursor.moveRight(&self.editor.rope);
                try self.editor.rope.insert(self.editor.cursor.offset, yanked);
                self.editor.cursor.offset += yanked.len;
            }
        }
    }

    fn pasteBefore(self: *SimpleTUI) !void {
        const yanked = self.editor.yank_buffer orelse return;

        if (self.phantom_buffer_manager) |pbm| {
            const buffer = pbm.getActiveBuffer() orelse return error.NoActiveBuffer;

            if (self.editor.yank_linewise) {
                // Paste on previous line
                self.editor.cursor.moveToLineStart(&self.editor.rope);
                const insert_pos = self.editor.cursor.offset;

                try buffer.phantom_buffer.insertText(insert_pos, yanked);
                try self.syncEditorFromPhantomBuffer();
                self.editor.cursor.offset = insert_pos;
            } else {
                // Character-wise paste before cursor
                const insert_pos = self.editor.cursor.offset;
                try buffer.phantom_buffer.insertText(insert_pos, yanked);
                try self.syncEditorFromPhantomBuffer();
                self.editor.cursor.offset = insert_pos + yanked.len;
            }
        } else {
            if (self.editor.yank_linewise) {
                self.editor.cursor.moveToLineStart(&self.editor.rope);
                const insert_pos = self.editor.cursor.offset;
                try self.editor.rope.insert(insert_pos, yanked);
                self.editor.cursor.offset = insert_pos;
            } else {
                const insert_pos = self.editor.cursor.offset;
                try self.editor.rope.insert(insert_pos, yanked);
                self.editor.cursor.offset = insert_pos + yanked.len;
            }
        }
    }

    // Visual Block Mode Functions
    fn enterVisualBlockMode(self: *SimpleTUI) void {
        self.visual_block_mode = true;
        self.switchMode(.visual);

        // Get current line and column
        const current_line = self.getCurrentLine();
        const current_column = self.getCurrentColumn();

        self.visual_block_start_line = current_line;
        self.visual_block_start_column = current_column;

        self.setStatusMessage("-- VISUAL BLOCK --");
    }

    fn exitVisualBlockMode(self: *SimpleTUI) void {
        self.visual_block_mode = false;

        // Clear PhantomBuffer secondary cursors if using PhantomBuffer
        if (self.phantom_buffer_manager) |pbm| {
            if (pbm.getActiveBuffer()) |buffer| {
                buffer.phantom_buffer.clearSecondaryCursors();
            }
        }
    }

    fn getCurrentLine(self: *SimpleTUI) usize {
        const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.cursor.offset }) catch return 0;
        var line: usize = 0;
        for (content) |ch| {
            if (ch == '\n') line += 1;
        }
        return line;
    }

    fn getCurrentColumn(self: *SimpleTUI) usize {
        const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.cursor.offset }) catch return 0;
        var col: usize = 0;
        var i = content.len;
        while (i > 0) : (i -= 1) {
            if (content[i - 1] == '\n') break;
            col += 1;
        }
        return content.len - (content.len - col);
    }

    fn getLineStartOffset(self: *SimpleTUI, line: usize) usize {
        const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() }) catch return 0;
        var current_line: usize = 0;
        for (content, 0..) |ch, i| {
            if (current_line == line) return i;
            if (ch == '\n') current_line += 1;
        }
        return content.len;
    }

    fn deleteVisualBlock(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager == null) {
            self.setStatusMessage("Visual block requires PhantomBuffer");
            return;
        }

        const pbm = self.phantom_buffer_manager.?;
        const buffer = pbm.getActiveBuffer() orelse return;

        const current_line = self.getCurrentLine();
        const current_column = self.getCurrentColumn();

        const start_line = @min(self.visual_block_start_line, current_line);
        const end_line = @max(self.visual_block_start_line, current_line);
        const start_col = @min(self.visual_block_start_column, current_column);
        const end_col = @max(self.visual_block_start_column, current_column);

        // Delete from bottom to top to maintain offsets
        var line = end_line;
        while (line >= start_line) : (line -= 1) {
            const line_start = self.getLineStartOffset(line);
            const delete_start = line_start + start_col;
            const delete_end = @min(line_start + end_col + 1, self.editor.rope.len());

            if (delete_start < delete_end) {
                try buffer.phantom_buffer.deleteRange(.{ .start = delete_start, .end = delete_end });
            }

            if (line == 0) break;
        }

        try self.syncEditorFromPhantomBuffer();
        self.exitVisualBlockMode();
        self.setStatusMessage("Deleted visual block");
    }

    fn insertAtVisualBlockStart(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager == null) {
            self.setStatusMessage("Visual block requires PhantomBuffer");
            return;
        }

        const pbm = self.phantom_buffer_manager.?;
        const buffer = pbm.getActiveBuffer() orelse return;

        const current_line = self.getCurrentLine();
        const start_line = @min(self.visual_block_start_line, current_line);
        const end_line = @max(self.visual_block_start_line, current_line);
        const insert_col = @min(self.visual_block_start_column, self.getCurrentColumn());

        // Set up multi-cursors at the start of each line in the block
        buffer.phantom_buffer.clearSecondaryCursors();

        var line = start_line;
        while (line <= end_line) : (line += 1) {
            const line_start = self.getLineStartOffset(line);
            const insert_offset = line_start + insert_col;

            if (line == start_line) {
                // Update primary cursor
                buffer.phantom_buffer.setPrimaryCursor(.{
                    .line = line,
                    .column = insert_col,
                    .byte_offset = insert_offset,
                });
            } else {
                // Add secondary cursors
                try buffer.phantom_buffer.addCursor(.{
                    .line = line,
                    .column = insert_col,
                    .byte_offset = insert_offset,
                });
            }
        }

        self.setStatusMessage("-- VISUAL BLOCK INSERT -- (multi-cursor active)");
        self.switchMode(.insert);
    }

    fn appendAtVisualBlockEnd(self: *SimpleTUI) !void {
        if (self.phantom_buffer_manager == null) {
            self.setStatusMessage("Visual block requires PhantomBuffer");
            return;
        }

        const pbm = self.phantom_buffer_manager.?;
        const buffer = pbm.getActiveBuffer() orelse return;

        const current_line = self.getCurrentLine();
        const start_line = @min(self.visual_block_start_line, current_line);
        const end_line = @max(self.visual_block_start_line, current_line);
        const append_col = @max(self.visual_block_start_column, self.getCurrentColumn()) + 1;

        // Set up multi-cursors at the end of each line in the block
        buffer.phantom_buffer.clearSecondaryCursors();

        var line = start_line;
        while (line <= end_line) : (line += 1) {
            const line_start = self.getLineStartOffset(line);
            const insert_offset = line_start + append_col;

            if (line == start_line) {
                // Update primary cursor
                buffer.phantom_buffer.setPrimaryCursor(.{
                    .line = line,
                    .column = append_col,
                    .byte_offset = insert_offset,
                });
            } else {
                // Add secondary cursors
                try buffer.phantom_buffer.addCursor(.{
                    .line = line,
                    .column = append_col,
                    .byte_offset = insert_offset,
                });
            }
        }

        self.setStatusMessage("-- VISUAL BLOCK APPEND -- (multi-cursor active)");
        self.switchMode(.insert);
    }

    fn changeVisualBlock(self: *SimpleTUI) !void {
        // Delete then enter insert mode
        try self.deleteVisualBlock();
        try self.insertAtVisualBlockStart();
    }

    fn closeWindow(self: *SimpleTUI) !void {
        if (self.window_manager) |win_mgr| {
            win_mgr.closeWindow() catch |err| {
                switch (err) {
                    error.CannotCloseLastWindow => {
                        self.setStatusMessage("Cannot close last window");
                        return;
                    },
                    else => return err,
                }
            };
            self.setStatusMessage("Window closed");
        } else {
            self.setStatusMessage("No window manager active");
        }
    }

    fn splitWindow(self: *SimpleTUI, direction: window_manager_mod.WindowManager.SplitDirection) !void {
        // Initialize buffer manager if needed
        if (self.buffer_manager == null) {
            const buf_mgr = self.allocator.create(buffer_manager_mod.BufferManager) catch {
                self.setStatusMessage("Failed to create buffer manager");
                return;
            };
            buf_mgr.* = buffer_manager_mod.BufferManager.init(self.allocator) catch {
                self.allocator.destroy(buf_mgr);
                self.setStatusMessage("Failed to initialize buffer manager");
                return;
            };
            self.buffer_manager = buf_mgr;
        }

        // Initialize window manager if needed
        if (self.window_manager == null) {
            const buf_mgr = self.buffer_manager.?;
            const win_mgr = self.allocator.create(window_manager_mod.WindowManager) catch {
                self.setStatusMessage("Failed to create window manager");
                return;
            };
            win_mgr.* = window_manager_mod.WindowManager.init(self.allocator, buf_mgr) catch {
                self.allocator.destroy(win_mgr);
                self.setStatusMessage("Failed to initialize window manager");
                return;
            };
            self.window_manager = win_mgr;
        }

        const win_mgr = self.window_manager.?;
        win_mgr.splitWindow(direction) catch |err| {
            std.log.warn("Failed to split window: {}", .{err});
            self.setStatusMessage("Failed to split window");
            return;
        };

        const dir_name = if (direction == .horizontal) "horizontal" else "vertical";
        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Split {s}", .{dir_name}) catch "Split complete";
        self.setStatusMessage(msg);
    }

    fn navigateWindow(self: *SimpleTUI, direction: window_manager_mod.WindowManager.Direction) !void {
        if (self.window_manager) |win_mgr| {
            win_mgr.navigateWindow(direction) catch |err| {
                std.log.warn("Failed to navigate window: {}", .{err});
                self.setStatusMessage("Navigation failed");
                return;
            };
            self.setStatusMessage("Window navigated");
        } else {
            self.setStatusMessage("No window manager active");
        }
    }

    fn loadGitHunks(self: *SimpleTUI, filepath: []const u8) !void {
        // Free old hunks first
        for (self.git_hunks) |hunk| {
            self.allocator.free(hunk.content);
        }
        if (self.git_hunks.len > 0) {
            self.allocator.free(self.git_hunks);
            self.git_hunks = &.{};
        }

        // Detect git repo if not already detected
        if (self.git.repo_root == null) {
            const parent_dir = std.fs.path.dirname(filepath) orelse ".";
            _ = try self.git.detectRepository(parent_dir);
        }

        // Load hunks
        self.git_hunks = try self.git.getHunks(filepath);
    }

    fn getGitSignForLine(self: *SimpleTUI, line: usize) u8 {
        // Line is 0-indexed, but git hunks use 1-indexed line numbers
        const git_line = line + 1;

        for (self.git_hunks) |hunk| {
            if (hunk.start_line <= git_line and git_line <= hunk.end_line) {
                return switch (hunk.hunk_type) {
                    .added => '+',
                    .modified => '~',
                    .deleted => '-',
                };
            }
        }

        return ' ';
    }

    /// Toggle file tree sidebar visibility
    pub fn toggleFileTree(self: *SimpleTUI) !void {
        if (self.file_tree == null) {
            // Initialize file tree with current working directory
            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            defer self.allocator.free(cwd);

            const tree = try self.allocator.create(file_tree_mod.FileTree);
            tree.* = try file_tree_mod.FileTree.init(self.allocator, cwd);
            self.file_tree = tree;

            // Load the tree
            try tree.load();
        }

        self.file_tree_active = !self.file_tree_active;
        if (self.file_tree_active) {
            self.setStatusMessage("File tree opened (Ctrl+B to close, ←→ to navigate)");
        } else {
            self.setStatusMessage("File tree closed");
        }
    }

    /// Open selected file from file tree
    fn openFileTreeSelection(self: *SimpleTUI) !void {
        const tree = self.file_tree orelse return;
        const entry = tree.getSelectedEntry() orelse return;

        if (!entry.is_dir) {
            try self.loadFile(entry.path);
            self.file_tree_active = false;
            self.switchMode(.normal);
        } else {
            try tree.toggleExpanded();
        }
    }
};

test "simple tui expand snippet captures default placeholder" {
    var tui = try SimpleTUI.init(std.testing.allocator);
    defer tui.deinit();

    const expansion = try tui.expandSnippet("${1:foo}bar");
    defer tui.allocator.free(expansion.text);

    try std.testing.expectEqualStrings("foobar", expansion.text);
    try std.testing.expectEqual(@as(usize, 3), expansion.caret);
    try std.testing.expect(expansion.selection != null);
    const sel = expansion.selection.?;
    try std.testing.expectEqual(@as(usize, 0), sel.start);
    try std.testing.expectEqual(@as(usize, 3), sel.end);
}

test "simple tui expand snippet falls back to final stop" {
    var tui = try SimpleTUI.init(std.testing.allocator);
    defer tui.deinit();

    const expansion = try tui.expandSnippet("print($0)");
    defer tui.allocator.free(expansion.text);

    try std.testing.expectEqualStrings("print()", expansion.text);
    try std.testing.expectEqual(@as(usize, 6), expansion.caret);
    try std.testing.expect(expansion.selection == null);
}

test "simple tui expand snippet handles plain tab stop" {
    var tui = try SimpleTUI.init(std.testing.allocator);
    defer tui.deinit();

    const expansion = try tui.expandSnippet("$1");
    defer tui.allocator.free(expansion.text);

    try std.testing.expectEqualStrings("", expansion.text);
    try std.testing.expectEqual(@as(usize, 0), expansion.caret);
    try std.testing.expect(expansion.selection == null);
}

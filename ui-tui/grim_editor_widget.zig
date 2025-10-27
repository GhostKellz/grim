//! GrimEditorWidget - Core text editing widget for Grim
//! Implements Phantom Widget interface for proper rendering integration

const std = @import("std");
const phantom = @import("phantom");
const syntax = @import("syntax");
const Editor = @import("editor.zig").Editor;
const editor_lsp_mod = @import("editor_lsp.zig");

const Widget = phantom.Widget;
const Buffer = phantom.Buffer;
const Cell = struct {
    char: u21 = ' ',
    style: phantom.Style = phantom.Style.default(),

    pub fn init(char: u21, cell_style: phantom.Style) @This() {
        return .{ .char = char, .style = cell_style };
    }
};

// LSP widgets
const lsp_completion_menu_mod = @import("lsp_completion_menu.zig");
const lsp_hover_widget_mod = @import("lsp_hover_widget.zig");
const lsp_diagnostics_panel_mod = @import("lsp_diagnostics_panel.zig");

pub const GrimEditorWidget = struct {
    widget: phantom.Widget,
    allocator: std.mem.Allocator,

    // Core editor
    editor: *Editor,

    // LSP integration
    lsp_client: ?*editor_lsp_mod.EditorLSP,
    lsp_completion_menu: ?*lsp_completion_menu_mod.LSPCompletionMenu,
    lsp_hover_widget: ?*lsp_hover_widget_mod.LSPHoverWidget,
    lsp_diagnostics_panel: ?*lsp_diagnostics_panel_mod.LSPDiagnosticsPanel,

    // Syntax highlighting
    highlight_cache: []syntax.HighlightRange,
    highlight_dirty: bool,

    // Viewport (scrolling)
    viewport_top_line: usize,
    viewport_left_col: usize,

    // Rendering area
    area: phantom.Rect,

    // Line numbers
    show_line_numbers: bool,
    relative_line_numbers: bool,

    // Search state
    search_pattern: ?[]const u8,
    search_matches: std.ArrayList(SearchMatch),
    current_match_index: ?usize,

    const SearchMatch = struct {
        start_offset: usize,
        end_offset: usize,
        line: usize,
        col: usize,
    };

    const vtable = phantom.Widget.WidgetVTable{
        .render = render,
        .deinit = deinit,
        .handleEvent = handleEvent,
        .resize = resize,
    };

    pub fn init(allocator: std.mem.Allocator) !*GrimEditorWidget {
        const self = try allocator.create(GrimEditorWidget);
        errdefer allocator.destroy(self);

        const editor = try allocator.create(Editor);
        errdefer allocator.destroy(editor);
        editor.* = try Editor.init(allocator);
        errdefer editor.deinit();

        const lsp_completion = try lsp_completion_menu_mod.LSPCompletionMenu.init(allocator);
        errdefer lsp_completion.deinit();

        const lsp_hover = try lsp_hover_widget_mod.LSPHoverWidget.init(allocator, 60, 15);
        errdefer lsp_hover.deinit();

        const lsp_diagnostics = try lsp_diagnostics_panel_mod.LSPDiagnosticsPanel.init(allocator, 80, 20);
        errdefer lsp_diagnostics.deinit();

        self.* = .{
            .widget = .{ .vtable = &vtable },
            .allocator = allocator,
            .editor = editor,
            .lsp_client = null,
            .lsp_completion_menu = lsp_completion,
            .lsp_hover_widget = lsp_hover,
            .lsp_diagnostics_panel = lsp_diagnostics,
            .highlight_cache = &.{},
            .highlight_dirty = true,
            .viewport_top_line = 0,
            .viewport_left_col = 0,
            .area = phantom.Rect.init(0, 0, 80, 24),
            .show_line_numbers = true,
            .relative_line_numbers = false,
            .search_pattern = null,
            .search_matches = std.ArrayList(SearchMatch){},
            .current_match_index = null,
        };

        return self;
    }

    fn deinit(widget: *phantom.Widget) void {
        const self: *GrimEditorWidget = @fieldParentPtr("widget", widget);

        if (self.lsp_diagnostics_panel) |panel| panel.deinit();
        if (self.lsp_hover_widget) |w| w.deinit();
        if (self.lsp_completion_menu) |m| m.deinit();
        if (self.lsp_client) |lsp| lsp.deinit();
        if (self.highlight_cache.len > 0) self.allocator.free(self.highlight_cache);
        if (self.search_pattern) |pattern| self.allocator.free(pattern);
        self.search_matches.deinit(self.allocator);
        self.editor.deinit();
        self.allocator.destroy(self.editor); // Free the Editor pointer itself!
        self.allocator.destroy(self);
    }

    fn render(widget: *phantom.Widget, buffer: *Buffer, area: phantom.Rect) void {
        const self: *GrimEditorWidget = @fieldParentPtr("widget", widget);
        self.area = area;

        // Update LSP widgets with latest data before rendering
        self.updateLSPWidgets();

        // Render main editor content
        self.renderEditorContent(buffer, area) catch |err| {
            std.log.err("Failed to render editor content: {}", .{err});
        };

        // Render LSP overlays (completion menu, hover widget)
        self.renderLSPOverlays(buffer, area) catch |err| {
            std.log.err("Failed to render LSP overlays: {}", .{err});
        };
    }

    fn renderEditorContent(self: *GrimEditorWidget, buffer: anytype, area: phantom.Rect) !void {
        // Ensure cursor is in viewport
        self.scrollToCursor();

        // Get editor content
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        // Calculate gutter width (line numbers + signs)
        const gutter_width: u16 = if (self.show_line_numbers) 6 else 1;
        const content_start_x = area.x + gutter_width;
        const content_width = if (area.width > gutter_width) area.width - gutter_width else 0;

        // Render lines
        var screen_line: usize = 0;
        var line_start: usize = self.getOffsetForLine(self.viewport_top_line);

        while (screen_line < area.height and line_start <= content.len) : (screen_line += 1) {
            const actual_line_num = self.viewport_top_line + screen_line;
            const screen_y = area.y + @as(u16, @intCast(screen_line));

            // Find line end
            const remaining = content[line_start..];
            const newline_pos = std.mem.indexOfScalar(u8, remaining, '\n');
            const line_end = if (newline_pos) |pos| line_start + pos else content.len;
            const line_slice = content[line_start..line_end];

            // Render gutter (line number)
            if (self.show_line_numbers) {
                var line_num_buf: [6]u8 = undefined;
                const cursor_line_col = if (self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset)) |result|
                    result
                else |_|
                    @TypeOf(try self.editor.rope.lineColumnAtOffset(0)){ .line = 0, .column = 0 };
                const cursor_line = cursor_line_col.line;
                const line_num = if (self.relative_line_numbers and actual_line_num != cursor_line) blk: {
                    const diff = if (actual_line_num > cursor_line)
                        actual_line_num - cursor_line
                    else
                        cursor_line - actual_line_num;
                    break :blk diff;
                } else actual_line_num + 1;

                const line_num_str = std.fmt.bufPrint(&line_num_buf, "{d:4} ", .{line_num}) catch "    ";

                const line_num_style = phantom.Style.default().withFg(phantom.Color.bright_black);
                buffer.writeText(area.x, screen_y, line_num_str, line_num_style);
            }

            // Apply horizontal scrolling
            const display_slice = if (self.viewport_left_col < line_slice.len)
                line_slice[self.viewport_left_col..]
            else
                "";

            // Render line content with syntax highlighting
            if (content_width > 0) {
                try self.renderHighlightedLine(buffer, content_start_x, screen_y, display_slice, actual_line_num, content_width);
            }

            // Move to next line
            line_start = if (newline_pos != null) line_end + 1 else content.len + 1;
        }

        // Fill remaining lines with tilde
        while (screen_line < area.height) : (screen_line += 1) {
            const screen_y = area.y + @as(u16, @intCast(screen_line));
            const tilde_style = phantom.Style.default().withFg(phantom.Color.blue);
            buffer.writeText(area.x, screen_y, "~", tilde_style);
        }

        // Render cursor
        try self.renderCursor(buffer, area, content_start_x);
    }

    fn renderHighlightedLine(
        _: *GrimEditorWidget,
        buffer: anytype,
        x: u16,
        y: u16,
        line: []const u8,
        line_num: usize,
        max_width: u16,
    ) !void {
        _ = line_num; // TODO: Use for syntax highlighting lookup

        // For now, render plain text
        // TODO: Implement syntax highlighting from highlight_cache
        const style = phantom.Style.default().withFg(phantom.Color.white);

        var current_x = x;
        var written: usize = 0;
        var utf8_iter = std.unicode.Utf8Iterator{ .bytes = line, .i = 0 };

        while (utf8_iter.nextCodepoint()) |codepoint| {
            if (written >= max_width) break;
            if (current_x >= buffer.size.width) break;

            const cell = Cell.init(codepoint, style);
            buffer.setCell(current_x, y, .{ .char = cell.char, .style = cell.style });
            current_x += 1;
            written += 1;
        }
    }

    fn renderCursor(self: *GrimEditorWidget, buffer: anytype, area: phantom.Rect, content_start_x: u16) !void {
        const cursor_line_col = self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return;
        const cursor_line = cursor_line_col.line;
        const cursor_col = cursor_line_col.column;

        // Check if cursor is in viewport
        if (cursor_line < self.viewport_top_line) return;
        const screen_line = cursor_line - self.viewport_top_line;
        if (screen_line >= area.height) return;

        if (cursor_col < self.viewport_left_col) return;
        const screen_col = cursor_col - self.viewport_left_col;

        const cursor_x = content_start_x + @as(u16, @intCast(screen_col));
        const cursor_y = area.y + @as(u16, @intCast(screen_line));

        if (cursor_x >= area.x + area.width) return;

        // Get character at cursor position
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        const cursor_offset = self.editor.cursor.offset;

        var cursor_char: u21 = ' ';
        if (cursor_offset < content.len) {
            var utf8_view = std.unicode.Utf8View.init(content[cursor_offset..]) catch return;
            var iter = utf8_view.iterator();
            if (iter.nextCodepoint()) |cp| {
                cursor_char = cp;
            }
        }

        // Render cursor as inverted cell
        const cursor_style = phantom.Style.default()
            .withFg(phantom.Color.black)
            .withBg(phantom.Color.white);

        const cell = Cell.init(cursor_char, cursor_style);
        buffer.setCell(cursor_x, cursor_y, .{ .char = cell.char, .style = cell.style });
    }

    fn renderLSPOverlays(self: *GrimEditorWidget, buffer: anytype, area: phantom.Rect) !void {
        // Render completion menu if visible
        if (self.lsp_completion_menu) |menu| {
            if (menu.visible) {
                // Calculate menu position near cursor
                const cursor_line_col = self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return;
                const cursor_line = cursor_line_col.line;
                const cursor_col = cursor_line_col.column;

                if (cursor_line >= self.viewport_top_line and cursor_line < self.viewport_top_line + area.height) {
                    const screen_line = cursor_line - self.viewport_top_line;
                    const screen_col = if (cursor_col >= self.viewport_left_col)
                        cursor_col - self.viewport_left_col
                    else
                        0;

                    const menu_width: u16 = 40;
                    const menu_height: u16 = 10;
                    const menu_x = area.x + @as(u16, @intCast(@min(screen_col + 1, area.width - menu_width)));
                    const menu_y = area.y + @as(u16, @intCast(@min(screen_line + 1, area.height - menu_height)));

                    const menu_area = phantom.Rect{
                        .x = menu_x,
                        .y = menu_y,
                        .width = menu_width,
                        .height = menu_height,
                    };

                    menu.render(buffer, menu_area);
                }
            }
        }

        // Render hover widget if visible
        if (self.lsp_hover_widget) |hover| {
            if (hover.visible) {
                // Position hover widget above/below cursor
                const cursor_line_col = self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return;
                const cursor_line = cursor_line_col.line;

                if (cursor_line >= self.viewport_top_line and cursor_line < self.viewport_top_line + area.height) {
                    const screen_line = cursor_line - self.viewport_top_line;

                    const hover_width: u16 = 60;
                    const hover_height: u16 = 15;
                    const hover_x = area.x + 5;
                    const hover_y = if (screen_line > 15)
                        area.y + @as(u16, @intCast(screen_line - 15))
                    else
                        area.y + @as(u16, @intCast(screen_line + 2));

                    const hover_area = phantom.Rect{
                        .x = hover_x,
                        .y = hover_y,
                        .width = hover_width,
                        .height = hover_height,
                    };

                    hover.render(buffer, hover_area);
                }
            }
        }

        // Render diagnostics panel if visible (bottom right)
        if (self.lsp_diagnostics_panel) |panel| {
            if (panel.visible) {
                const panel_width: u16 = 50;
                const panel_height: u16 = 20;
                const panel_x = if (area.width > panel_width) area.x + (area.width - panel_width) else area.x;
                const panel_y = if (area.height > panel_height) area.y + (area.height - panel_height) else area.y;

                const panel_area = phantom.Rect{
                    .x = panel_x,
                    .y = panel_y,
                    .width = panel_width,
                    .height = panel_height,
                };

                panel.border.widget.vtable.render(&panel.border.widget, buffer, panel_area);
            }
        }
    }

    fn handleEvent(widget: *phantom.Widget, event: phantom.Event) bool {
        const self: *GrimEditorWidget = @fieldParentPtr("widget", widget);
        // Let LSP widgets handle events first
        if (self.lsp_completion_menu) |menu| {
            if (menu.visible) {
                switch (event) {
                    .key => |key| {
                        if (menu.handleKeyEvent(key)) {
                            return true;
                        }
                    },
                    else => {},
                }
            }
        }

        // Let hover widget handle events
        if (self.lsp_hover_widget) |hover| {
            if (hover.visible) {
                switch (event) {
                    .key => |key| {
                        if (key == .escape) {
                            hover.hide();
                            return true;
                        }
                    },
                    else => {},
                }
            }
        }

        // Widget doesn't handle events directly - parent (GrimApp) handles them
        return false;
    }

    fn resize(widget: *phantom.Widget, new_area: phantom.Rect) void {
        const self: *GrimEditorWidget = @fieldParentPtr("widget", widget);
        self.area = new_area;
    }

    // === Public API ===

    pub fn loadFile(self: *GrimEditorWidget, filepath: []const u8) !void {
        try self.editor.loadFile(filepath);
        self.highlight_dirty = true;
        self.viewport_top_line = 0;
        self.viewport_left_col = 0;

        // Initialize LSP if needed
        // TODO: Detect language and start LSP client
    }

    pub fn saveFile(self: *GrimEditorWidget) !void {
        if (self.editor.current_filename) |filepath| {
            const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
            const file = try std.fs.cwd().createFile(filepath, .{});
            defer file.close();
            try file.writeAll(content);
        } else {
            return error.NoFilename;
        }
    }

    pub fn insertChar(self: *GrimEditorWidget, c: u21) !void {
        try self.editor.insertChar(c);
        self.highlight_dirty = true;
    }

    pub fn insertNewline(self: *GrimEditorWidget) !void {
        try self.editor.rope.insert(self.editor.cursor.offset, "\n");
        self.editor.cursor.offset += 1;
        self.highlight_dirty = true;
    }

    pub fn insertTab(self: *GrimEditorWidget) !void {
        // TODO: Respect config (tabs vs spaces)
        try self.insertChar(' ');
        try self.insertChar(' ');
        try self.insertChar(' ');
        try self.insertChar(' ');
    }

    pub fn deleteCharBackward(self: *GrimEditorWidget) !void {
        if (self.editor.cursor.offset > 0) {
            const prev_offset = self.editor.cursor.offset - 1;
            try self.editor.rope.delete(prev_offset, 1);
            self.editor.cursor.offset = prev_offset;
        }
        self.highlight_dirty = true;
    }

    pub fn deleteCharForward(self: *GrimEditorWidget) !void {
        if (self.editor.cursor.offset < self.editor.rope.len()) {
            try self.editor.rope.delete(self.editor.cursor.offset, 1);
        }
        self.highlight_dirty = true;
    }

    pub fn moveCursorLeft(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveLeft(&self.editor.rope);
    }

    pub fn moveCursorRight(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveRight(&self.editor.rope);
    }

    pub fn moveCursorUp(self: *GrimEditorWidget) !void {
        self.editor.moveCursorUp();
    }

    pub fn moveCursorDown(self: *GrimEditorWidget) !void {
        self.editor.moveCursorDown();
    }

    pub fn moveWordForward(self: *GrimEditorWidget) !void {
        self.editor.moveWordForward();
    }

    pub fn moveWordBackward(self: *GrimEditorWidget) !void {
        self.editor.moveWordBackward();
    }

    pub fn moveToLineStart(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveToLineStart(&self.editor.rope);
    }

    pub fn moveToLineEnd(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveToLineEnd(&self.editor.rope);
    }

    // Visual mode operations
    pub fn startVisualMode(self: *GrimEditorWidget) !void {
        // TODO: Implement visual mode state
        _ = self;
    }

    pub fn startVisualLineMode(self: *GrimEditorWidget) !void {
        // TODO: Implement visual line mode
        _ = self;
    }

    pub fn clearSelection(self: *GrimEditorWidget) !void {
        // TODO: Clear visual selection
        _ = self;
    }

    pub fn extendSelectionLeft(self: *GrimEditorWidget) !void {
        try self.moveCursorLeft();
    }

    pub fn extendSelectionRight(self: *GrimEditorWidget) !void {
        try self.moveCursorRight();
    }

    pub fn extendSelectionUp(self: *GrimEditorWidget) !void {
        try self.moveCursorUp();
    }

    pub fn extendSelectionDown(self: *GrimEditorWidget) !void {
        try self.moveCursorDown();
    }

    pub fn deleteSelection(self: *GrimEditorWidget) !void {
        // TODO: Delete visual selection
        _ = self;
    }

    pub fn yankSelection(self: *GrimEditorWidget) !void {
        // TODO: Yank visual selection
        _ = self;
    }

    // Update LSP widgets with latest data from LSP client
    pub fn updateLSPWidgets(self: *GrimEditorWidget) void {
        if (self.lsp_client) |lsp| {
            // Update hover widget if we have new hover info
            if (lsp.getHoverInfo()) |hover_text| {
                if (self.lsp_hover_widget) |hover| {
                    hover.setHoverContent(hover_text) catch |err| {
                        std.log.err("Failed to set hover content: {}", .{err});
                    };
                    if (!hover.visible) {
                        hover.show();
                    }
                }
            }

            // Update completion menu if we have new completions
            const completions = lsp.getCompletions();
            if (completions.len > 0) {
                if (self.lsp_completion_menu) |menu| {
                    // Convert completions to string slice
                    // TODO: This allocates, need to manage memory properly
                    var items = self.allocator.alloc([]const u8, completions.len) catch return;
                    for (completions, 0..) |completion, i| {
                        items[i] = completion.label;
                    }
                    menu.setItems(items) catch |err| {
                        self.allocator.free(items);
                        std.log.err("Failed to set completion items: {}", .{err});
                        return;
                    };
                    if (!menu.visible) {
                        menu.show();
                    }
                }
            }

            // Update diagnostics panel if we have diagnostics for the current file
            if (self.editor.current_filename) |path| {
                if (lsp.getDiagnostics(path)) |diagnostics| {
                    if (self.lsp_diagnostics_panel) |panel| {
                        panel.setDiagnostics(diagnostics) catch |err| {
                            std.log.err("Failed to set diagnostics: {}", .{err});
                        };
                    }
                }
            }
        }
    }

    // Toggle diagnostics panel visibility
    pub fn toggleDiagnostics(self: *GrimEditorWidget) void {
        if (self.lsp_diagnostics_panel) |panel| {
            panel.visible = !panel.visible;
        }
    }

    // LSP operations
    pub fn triggerHover(self: *GrimEditorWidget) !void {
        // Request hover information from LSP client
        if (self.lsp_client) |lsp| {
            if (self.editor.current_filename) |path| {
                // Get cursor position
                const cursor_line_col = try self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset);

                // Request hover from LSP server
                try lsp.requestHover(path, @intCast(cursor_line_col.line), @intCast(cursor_line_col.column));

                // Show loading spinner in hover widget
                if (self.lsp_hover_widget) |hover| {
                    const loading_msg = "Loading...";
                    try hover.setHoverContent(loading_msg);
                    hover.show();
                }

                // Note: Actual hover content will be set by LSP response handler
            }
        }
    }

    pub fn triggerCompletion(self: *GrimEditorWidget) !void {
        // Request completions from LSP client
        if (self.lsp_client) |lsp| {
            if (self.editor.current_filename) |path| {
                // Get cursor position
                const cursor_line_col = try self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset);

                // Request completions from LSP server
                try lsp.requestCompletion(path, @intCast(cursor_line_col.line), @intCast(cursor_line_col.column));

                // Show loading in completion menu
                if (self.lsp_completion_menu) |menu| {
                    const loading_items = [_][]const u8{"Loading..."};
                    try menu.setItems(&loading_items);
                    menu.show();
                }

                // Note: Actual completion items will be set by LSP response handler
            }
        }
    }

    // Scrolling
    fn scrollToCursor(self: *GrimEditorWidget) void {
        const cursor_line_col = self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return;
        const cursor_line = cursor_line_col.line;
        const cursor_col = cursor_line_col.column;
        const viewport_height = self.area.height;
        const viewport_width = if (self.area.width > 6) self.area.width - 6 else 0;

        // Vertical scrolling
        if (cursor_line < self.viewport_top_line) {
            self.viewport_top_line = cursor_line;
        } else if (cursor_line >= self.viewport_top_line + viewport_height) {
            self.viewport_top_line = cursor_line - viewport_height + 1;
        }

        // Horizontal scrolling
        if (cursor_col < self.viewport_left_col) {
            self.viewport_left_col = cursor_col;
        } else if (cursor_col >= self.viewport_left_col + viewport_width) {
            self.viewport_left_col = cursor_col - viewport_width + 1;
        }
    }

    fn getOffsetForLine(self: *GrimEditorWidget, line: usize) usize {
        // Find offset for the start of the given line
        const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() }) catch return 0;
        var current_line: usize = 0;
        var offset: usize = 0;

        while (current_line < line and offset < content.len) {
            if (content[offset] == '\n') {
                current_line += 1;
            }
            offset += 1;
        }

        return offset;
    }

    // === Search functionality ===

    pub fn search(self: *GrimEditorWidget, pattern: []const u8, forward: bool) !void {
        // Free old pattern and matches
        if (self.search_pattern) |old_pattern| {
            self.allocator.free(old_pattern);
        }
        self.search_matches.clearRetainingCapacity();

        // Store new pattern
        self.search_pattern = try self.allocator.dupe(u8, pattern);

        // Find all matches
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        var offset: usize = 0;
        while (offset + pattern.len <= content.len) {
            if (std.mem.eql(u8, content[offset .. offset + pattern.len], pattern)) {
                // Found a match, convert offset to line/col
                const line_col = self.offsetToLineCol(content, offset);
                try self.search_matches.append(self.allocator, SearchMatch{
                    .start_offset = offset,
                    .end_offset = offset + pattern.len,
                    .line = line_col.line,
                    .col = line_col.col,
                });
                offset += pattern.len;
            } else {
                offset += 1;
            }
        }

        // Jump to first match
        if (self.search_matches.items.len > 0) {
            self.current_match_index = 0;
            try self.jumpToMatch(0, forward);
        }
    }

    pub fn searchNext(self: *GrimEditorWidget) !void {
        if (self.search_matches.items.len == 0) return;

        const idx = self.current_match_index orelse 0;
        const next = (idx + 1) % self.search_matches.items.len;
        self.current_match_index = next;
        try self.jumpToMatch(next, true);
    }

    pub fn searchPrev(self: *GrimEditorWidget) !void {
        if (self.search_matches.items.len == 0) return;

        const idx = self.current_match_index orelse 0;
        const prev = if (idx == 0) self.search_matches.items.len - 1 else idx - 1;
        self.current_match_index = prev;
        try self.jumpToMatch(prev, false);
    }

    fn jumpToMatch(self: *GrimEditorWidget, index: usize, forward: bool) !void {
        _ = forward;
        if (index >= self.search_matches.items.len) return;

        const match = self.search_matches.items[index];
        // Move cursor to match location
        self.editor.cursor.offset = match.start_offset;
    }

    fn offsetToLineCol(self: *GrimEditorWidget, content: []const u8, offset: usize) struct { line: usize, col: usize } {
        _ = self;
        var line: usize = 0;
        var col: usize = 0;
        var i: usize = 0;

        while (i < offset and i < content.len) : (i += 1) {
            if (content[i] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }

        return .{ .line = line, .col = col };
    }

    pub fn clearSearch(self: *GrimEditorWidget) void {
        if (self.search_pattern) |pattern| {
            self.allocator.free(pattern);
            self.search_pattern = null;
        }
        self.search_matches.clearRetainingCapacity();
        self.current_match_index = null;
    }
};

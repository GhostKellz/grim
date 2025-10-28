//! GrimEditorWidget - Core text editing widget for Grim
//! Implements Phantom Widget interface for proper rendering integration

const std = @import("std");
const phantom = @import("phantom");
const syntax = @import("syntax");
const core = @import("core");
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

    // Dirty line tracking for rendering optimization
    dirty_lines: std.DynamicBitSet,
    full_redraw_needed: bool,

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

    // Visual mode state
    visual_mode: VisualMode,
    visual_anchor: ?usize, // Start offset of visual selection

    // Register system (for yank/paste)
    unnamed_register: ?[]const u8, // "" register
    named_registers: std.StringHashMap([]const u8), // Named registers (a-z)
    clipboard: ?*core.Clipboard, // System clipboard (+ register)

    // Macro system
    recording_macro: ?u8, // Register being recorded to (a-z)
    macro_buffer: std.ArrayList(phantom.Key), // Current recording
    macros: std.StringHashMap([]phantom.Key), // Recorded macros (a-z)

    // File state
    is_modified: bool, // Track if buffer has unsaved changes

    // Tab configuration
    tab_size: u8, // Number of spaces for a tab
    expand_tab: bool, // Convert tabs to spaces

    const SearchMatch = struct {
        start_offset: usize,
        end_offset: usize,
        line: usize,
        col: usize,
    };

    const BlockSelection = struct {
        start_line: usize,
        end_line: usize,
        start_col: usize,
        end_col: usize,
    };

    pub const VisualMode = enum {
        none,
        character, // v
        line, // V
        block, // Ctrl-V
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

        // Initialize dirty line tracking
        var dirty_lines = try std.DynamicBitSet.initEmpty(allocator, 1024); // Start with 1024 lines capacity
        errdefer dirty_lines.deinit(allocator);

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
            .dirty_lines = dirty_lines,
            .full_redraw_needed = true,
            .viewport_top_line = 0,
            .viewport_left_col = 0,
            .area = phantom.Rect.init(0, 0, 80, 24),
            .show_line_numbers = true,
            .relative_line_numbers = false,
            .search_pattern = null,
            .search_matches = std.ArrayList(SearchMatch){},
            .current_match_index = null,
            .visual_mode = .none,
            .visual_anchor = null,
            .unnamed_register = null,
            .named_registers = std.StringHashMap([]const u8).init(allocator),
            .clipboard = null,
            .recording_macro = null,
            .macro_buffer = std.ArrayList(phantom.Key){},
            .macros = std.StringHashMap([]phantom.Key).init(allocator),
            .is_modified = false,
            .tab_size = 4, // Default to 4 spaces
            .expand_tab = true, // Default to spaces, not tabs
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
        self.dirty_lines.deinit();

        // Free registers
        if (self.unnamed_register) |reg| self.allocator.free(reg);
        var reg_iter = self.named_registers.valueIterator();
        while (reg_iter.next()) |value| {
            self.allocator.free(value.*);
        }
        self.named_registers.deinit();

        // Free macros
        self.macro_buffer.deinit(self.allocator);
        var macro_iter = self.macros.valueIterator();
        while (macro_iter.next()) |value| {
            self.allocator.free(value.*);
        }
        self.macros.deinit();

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
        // Update syntax highlighting if dirty
        if (self.highlight_dirty) {
            self.updateHighlighting() catch |err| {
                std.log.warn("Failed to update syntax highlighting: {}", .{err});
            };
        }

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
        self: *GrimEditorWidget,
        buffer: anytype,
        x: u16,
        y: u16,
        line: []const u8,
        line_num: usize,
        max_width: u16,
    ) !void {
        // Default style
        const default_style = phantom.Style.default().withFg(phantom.Color.white);

        var current_x = x;
        var written: usize = 0;
        var col: usize = 0;
        var utf8_iter = std.unicode.Utf8Iterator{ .bytes = line, .i = 0 };

        while (utf8_iter.nextCodepoint()) |codepoint| {
            if (written >= max_width) break;
            if (current_x >= buffer.size.width) break;

            var cell_style = default_style;

            // Check syntax highlighting (line/col based)
            for (self.highlight_cache) |hl_range| {
                const in_range = if (line_num == hl_range.start_line and line_num == hl_range.end_line)
                    col >= hl_range.start_col and col < hl_range.end_col
                else if (line_num == hl_range.start_line)
                    col >= hl_range.start_col
                else if (line_num == hl_range.end_line)
                    col < hl_range.end_col
                else
                    line_num > hl_range.start_line and line_num < hl_range.end_line;

                if (in_range) {
                    cell_style = self.highlightStyleFromType(hl_range.highlight_type);
                    break;
                }
            }

            // Check visual selection (higher priority than syntax highlighting)
            if (self.visual_mode != .none) {
                if (self.getSelectionRange()) |range| {
                    const line_start_offset = self.getOffsetForLine(line_num);
                    const byte_offset = line_start_offset + utf8_iter.i;

                    if (byte_offset >= range.start and byte_offset < range.end) {
                        cell_style = phantom.Style.default()
                            .withFg(phantom.Color.white)
                            .withBg(phantom.Color.blue);
                    }
                }
            }

            // Check search matches (highest priority - byte offset based)
            if (self.search_pattern != null) {
                const line_start_offset = self.getOffsetForLine(line_num);
                const byte_offset = line_start_offset + utf8_iter.i;

                for (self.search_matches.items) |match| {
                    if (byte_offset >= match.start_offset and byte_offset < match.end_offset) {
                        cell_style = phantom.Style.default()
                            .withFg(phantom.Color.black)
                            .withBg(phantom.Color.yellow);
                        break;
                    }
                }
            }

            const cell = Cell.init(codepoint, cell_style);
            buffer.setCell(current_x, y, .{ .char = cell.char, .style = cell.style });
            current_x += 1;
            written += 1;
            col += 1;
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
        // Mark all as dirty on resize to force full redraw
        self.full_redraw_needed = true;
        // Re-scroll to ensure cursor stays in viewport with new dimensions
        self.scrollToCursor();
    }

    // === Public API ===

    pub fn loadFile(self: *GrimEditorWidget, filepath: []const u8) !void {
        try self.editor.loadFile(filepath);
        self.highlight_dirty = true;
        self.viewport_top_line = 0;
        self.viewport_left_col = 0;
        self.is_modified = false; // Clear modified flag on fresh load

        // Detect language and trigger syntax highlighting
        try self.activateSyntaxHighlighting(filepath);

        // Initialize LSP if needed
        self.startLSPForLanguage(filepath);
    }

    fn startLSPForLanguage(self: *GrimEditorWidget, filepath: []const u8) void {
        // Only start LSP if we have a client instance
        if (self.lsp_client) |lsp| {
            // Get absolute path for LSP
            const abs_path = std.fs.cwd().realpathAlloc(self.allocator, filepath) catch {
                // If we can't get absolute path, try with the relative path
                lsp.openFile(filepath) catch |err| {
                    std.log.warn("Failed to open file in LSP: {}", .{err});
                };
                return;
            };
            defer self.allocator.free(abs_path);

            // Open the file in LSP - this will auto-start the appropriate server
            lsp.openFile(abs_path) catch |err| {
                std.log.warn("Failed to open file in LSP: {}", .{err});
                return;
            };

            std.log.info("LSP: Opened {s} for language support", .{filepath});
        }
    }

    fn activateSyntaxHighlighting(self: *GrimEditorWidget, filepath: []const u8) !void {
        // Set the language based on file extension
        try self.editor.highlighter.setLanguage(filepath);

        // Initial highlighting
        try self.updateHighlighting();
    }

    fn updateHighlighting(self: *GrimEditorWidget) !void {
        // Get highlights from the highlighter
        const highlights = try self.editor.highlighter.highlight(&self.editor.rope);
        defer self.allocator.free(highlights);

        // Convert highlights to ranges for rendering
        const ranges = try syntax.convertHighlightsToRanges(self.allocator, highlights, &self.editor.rope);

        // Free old cache and store new ranges
        if (self.highlight_cache.len > 0) {
            self.allocator.free(self.highlight_cache);
        }
        self.highlight_cache = ranges;
        self.highlight_dirty = false;
    }

    pub fn saveFile(self: *GrimEditorWidget) !void {
        if (self.editor.current_filename) |filepath| {
            const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

            // Count lines
            var line_count: usize = 1; // Start at 1 for the first line
            for (content) |ch| {
                if (ch == '\n') line_count += 1;
            }

            const file = try std.fs.cwd().createFile(filepath, .{});
            defer file.close();
            try file.writeAll(content);
            self.is_modified = false; // Clear modified flag after successful save

            // Show save confirmation
            std.log.info("\"{s}\" {d}L, {d}B written", .{ filepath, line_count, content.len });
        } else {
            return error.NoFilename;
        }
    }

    pub fn insertChar(self: *GrimEditorWidget, c: u21) !void {
        // Save undo state for each character
        try self.editor.saveUndoState("insert character");
        const line = (self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return).line;
        try self.editor.insertChar(c);
        self.highlight_dirty = true;
        self.is_modified = true;
        self.markLineDirty(line);
    }

    pub fn insertNewline(self: *GrimEditorWidget) !void {
        try self.editor.saveUndoState("insert newline");
        const line = (self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return).line;
        try self.editor.rope.insert(self.editor.cursor.offset, "\n");
        self.editor.cursor.offset += 1;
        self.highlight_dirty = true;
        self.is_modified = true;
        // Mark current and next lines as dirty (newline affects both)
        self.markLinesDirty(line, line + 1);
    }

    pub fn insertTab(self: *GrimEditorWidget) !void {
        if (self.expand_tab) {
            // Insert spaces based on tab_size
            var i: u8 = 0;
            while (i < self.tab_size) : (i += 1) {
                try self.insertChar(' ');
            }
        } else {
            // Insert actual tab character
            try self.insertChar('\t');
        }
    }

    pub fn deleteCharBackward(self: *GrimEditorWidget) !void {
        if (self.editor.cursor.offset > 0) {
            try self.editor.saveUndoState("backspace");
            const line = (self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return).line;
            const prev_offset = self.editor.cursor.offset - 1;
            try self.editor.rope.delete(prev_offset, 1);
            self.editor.cursor.offset = prev_offset;
            self.is_modified = true;
            self.markLineDirty(line);
        }
        self.highlight_dirty = true;
    }

    pub fn deleteCharForward(self: *GrimEditorWidget) !void {
        if (self.editor.cursor.offset < self.editor.rope.len()) {
            try self.editor.saveUndoState("delete");
            const line = (self.editor.rope.lineColumnAtOffset(self.editor.cursor.offset) catch return).line;
            try self.editor.rope.delete(self.editor.cursor.offset, 1);
            self.is_modified = true;
            self.markLineDirty(line);
        }
        self.highlight_dirty = true;
    }

    pub fn moveCursorLeft(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveLeft(&self.editor.rope);
        self.scrollToCursor();
    }

    pub fn moveCursorRight(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveRight(&self.editor.rope);
        self.scrollToCursor();
    }

    pub fn moveCursorUp(self: *GrimEditorWidget) !void {
        self.editor.moveCursorUp();
        self.scrollToCursor();
    }

    pub fn moveCursorDown(self: *GrimEditorWidget) !void {
        self.editor.moveCursorDown();
        self.scrollToCursor();
    }

    pub fn moveWordForward(self: *GrimEditorWidget) !void {
        self.editor.moveWordForward();
        self.scrollToCursor();
    }

    pub fn moveWordBackward(self: *GrimEditorWidget) !void {
        self.editor.moveWordBackward();
        self.scrollToCursor();
    }

    pub fn moveToLineStart(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveToLineStart(&self.editor.rope);
        self.scrollToCursor();
    }

    pub fn moveToLineEnd(self: *GrimEditorWidget) !void {
        self.editor.cursor.moveToLineEnd(&self.editor.rope);
        self.scrollToCursor();
    }

    pub fn scrollHalfPageDown(self: *GrimEditorWidget) !void {
        const half_page = self.area.height / 2;
        var i: usize = 0;
        while (i < half_page) : (i += 1) {
            self.editor.moveCursorDown();
        }
        self.scrollToCursor();
    }

    pub fn scrollHalfPageUp(self: *GrimEditorWidget) !void {
        const half_page = self.area.height / 2;
        var i: usize = 0;
        while (i < half_page) : (i += 1) {
            self.editor.moveCursorUp();
        }
        self.scrollToCursor();
    }

    pub fn scrollFullPageDown(self: *GrimEditorWidget) !void {
        const full_page = self.area.height;
        var i: usize = 0;
        while (i < full_page) : (i += 1) {
            self.editor.moveCursorDown();
        }
        self.scrollToCursor();
    }

    pub fn scrollFullPageUp(self: *GrimEditorWidget) !void {
        const full_page = self.area.height;
        var i: usize = 0;
        while (i < full_page) : (i += 1) {
            self.editor.moveCursorUp();
        }
        self.scrollToCursor();
    }

    pub fn gotoFirstLine(self: *GrimEditorWidget) !void {
        self.editor.cursor.offset = 0;
        self.scrollToCursor();
    }

    pub fn gotoLastLine(self: *GrimEditorWidget) !void {
        self.editor.cursor.offset = self.editor.rope.len();
        self.scrollToCursor();
    }

    // Visual mode operations
    pub fn startVisualMode(self: *GrimEditorWidget) !void {
        if (self.visual_mode == .none) {
            self.visual_mode = .character;
            self.visual_anchor = self.editor.cursor.offset;
        } else {
            // Toggle off if already in visual mode
            self.visual_mode = .none;
            self.visual_anchor = null;
        }
    }

    pub fn startVisualLineMode(self: *GrimEditorWidget) !void {
        if (self.visual_mode == .none) {
            self.visual_mode = .line;
            self.visual_anchor = self.editor.cursor.offset;
        } else {
            // Toggle off if already in visual mode
            self.visual_mode = .none;
            self.visual_anchor = null;
        }
    }

    pub fn startVisualBlockMode(self: *GrimEditorWidget) !void {
        if (self.visual_mode == .none) {
            self.visual_mode = .block;
            self.visual_anchor = self.editor.cursor.offset;
        } else {
            // Toggle off if already in visual mode
            self.visual_mode = .none;
            self.visual_anchor = null;
        }
    }

    pub fn clearSelection(self: *GrimEditorWidget) !void {
        self.visual_mode = .none;
        self.visual_anchor = null;
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
        if (self.visual_mode == .none) return;

        const range = self.getSelectionRange() orelse return;
        const start = range.start;
        const end = range.end;

        if (start >= end) return;

        // Save undo state before deletion
        try self.editor.saveUndoState("delete selection");

        // Delete the selected range
        try self.editor.rope.delete(start, end - start);
        self.editor.cursor.offset = start;

        // Exit visual mode
        self.visual_mode = .none;
        self.visual_anchor = null;
        self.highlight_dirty = true;
        self.is_modified = true;
    }

    pub fn yankSelection(self: *GrimEditorWidget) !void {
        if (self.visual_mode == .none) return;

        const range = self.getSelectionRange() orelse return;
        const start = range.start;
        const end = range.end;

        if (start >= end) return;

        // Get the selected text
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        const selected_text = content[start..end];

        // Store in unnamed register
        try self.setRegister(null, selected_text);

        // Exit visual mode
        self.visual_mode = .none;
        self.visual_anchor = null;
    }

    pub fn indentSelection(self: *GrimEditorWidget) !void {
        if (self.visual_mode == .none) return;

        const range = self.getSelectionRange() orelse return;
        const start = range.start;
        const end = range.end;

        if (start >= end) return;

        // Save undo state before indenting
        try self.editor.saveUndoState("indent");

        // Get the content
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        // Find all lines in the selection
        const start_line_col = self.offsetToLineCol(content, start);
        const end_line_col = self.offsetToLineCol(content, end);

        // Indent each line in the selection (from bottom to top to maintain offsets)
        var line = end_line_col.line;
        while (true) : (line -= 1) {
            const line_start = self.getOffsetForLine(line);

            // Insert indentation (spaces or tab based on expand_tab setting)
            if (self.expand_tab) {
                // Insert spaces
                var i: u8 = 0;
                while (i < self.tab_size) : (i += 1) {
                    try self.editor.rope.insert(line_start, " ");
                }
            } else {
                // Insert tab character
                try self.editor.rope.insert(line_start, "\t");
            }

            // Mark line as dirty
            self.markLineDirty(line);

            if (line == start_line_col.line) break;
            if (line == 0) break;
        }

        // Exit visual mode
        self.visual_mode = .none;
        self.visual_anchor = null;
        self.highlight_dirty = true;
        self.is_modified = true;
    }

    pub fn dedentSelection(self: *GrimEditorWidget) !void {
        if (self.visual_mode == .none) return;

        const range = self.getSelectionRange() orelse return;
        const start = range.start;
        const end = range.end;

        if (start >= end) return;

        // Save undo state before dedenting
        try self.editor.saveUndoState("dedent");

        // Get the content
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        // Find all lines in the selection
        const start_line_col = self.offsetToLineCol(content, start);
        const end_line_col = self.offsetToLineCol(content, end);

        // Dedent each line in the selection (from bottom to top to maintain offsets)
        var line = end_line_col.line;
        while (true) : (line -= 1) {
            const line_start = self.getOffsetForLine(line);

            // Check what's at the start of the line and remove it
            const line_content = content[line_start..];
            if (line_content.len > 0) {
                if (line_content[0] == '\t') {
                    // Remove one tab
                    try self.editor.rope.delete(line_start, 1);
                    self.markLineDirty(line);
                } else if (line_content[0] == ' ') {
                    // Remove up to tab_size spaces
                    var spaces_to_remove: u8 = 0;
                    var i: usize = 0;
                    while (i < self.tab_size and i < line_content.len and line_content[i] == ' ') {
                        spaces_to_remove += 1;
                        i += 1;
                    }
                    if (spaces_to_remove > 0) {
                        try self.editor.rope.delete(line_start, spaces_to_remove);
                        self.markLineDirty(line);
                    }
                }
            }

            if (line == start_line_col.line) break;
            if (line == 0) break;
        }

        // Exit visual mode
        self.visual_mode = .none;
        self.visual_anchor = null;
        self.highlight_dirty = true;
        self.is_modified = true;
    }

    fn getSelectionRange(self: *GrimEditorWidget) ?struct { start: usize, end: usize } {
        if (self.visual_mode == .none) return null;
        const anchor = self.visual_anchor orelse return null;
        const cursor = self.editor.cursor.offset;

        if (self.visual_mode == .character) {
            const start = @min(anchor, cursor);
            const end = @max(anchor, cursor) + 1; // Include character under cursor
            return .{ .start = start, .end = end };
        } else if (self.visual_mode == .line) {
            // Get line boundaries
            const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() }) catch return null;

            // Find line start of anchor
            var anchor_line_start = anchor;
            while (anchor_line_start > 0 and content[anchor_line_start - 1] != '\n') {
                anchor_line_start -= 1;
            }

            // Find line end of cursor (include newline)
            var cursor_line_end = cursor;
            while (cursor_line_end < content.len and content[cursor_line_end] != '\n') {
                cursor_line_end += 1;
            }
            if (cursor_line_end < content.len) cursor_line_end += 1; // Include the newline

            const start = @min(anchor_line_start, anchor_line_start);
            const end = @max(cursor_line_end, cursor_line_end);
            return .{ .start = start, .end = end };
        } else if (self.visual_mode == .block) {
            // For block mode, return the full range - actual column logic handled in operations
            const start = @min(anchor, cursor);
            const end = @max(anchor, cursor) + 1;
            return .{ .start = start, .end = end };
        }

        return null;
    }

    /// Get block selection coordinates for visual block mode
    fn getBlockSelection(self: *GrimEditorWidget) ?BlockSelection {
        if (self.visual_mode != .block) return null;
        const anchor = self.visual_anchor orelse return null;
        const cursor = self.editor.cursor.offset;

        const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() }) catch return null;

        // Convert offsets to line/col
        const anchor_pos = self.offsetToLineCol(content, anchor);
        const cursor_pos = self.offsetToLineCol(content, cursor);

        return BlockSelection{
            .start_line = @min(anchor_pos.line, cursor_pos.line),
            .end_line = @max(anchor_pos.line, cursor_pos.line),
            .start_col = @min(anchor_pos.col, cursor_pos.col),
            .end_col = @max(anchor_pos.col, cursor_pos.col),
        };
    }

    /// Delete block selection (column-wise delete)
    pub fn deleteBlockSelection(self: *GrimEditorWidget) !void {
        const block = self.getBlockSelection() orelse return;
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        // Delete from bottom to top to preserve offsets
        var line = block.end_line;
        while (true) : (line -= 1) {
            const delete_start = self.lineColToOffset(content, line, block.start_col);
            const delete_end = self.lineColToOffset(content, line, block.end_col + 1);

            if (delete_start < delete_end and delete_end <= content.len) {
                try self.editor.rope.delete(delete_start, delete_end - delete_start);
            }

            if (line == block.start_line) break;
            if (line == 0) break;
        }

        self.visual_mode = .none;
        self.visual_anchor = null;
        self.highlight_dirty = true;
        self.is_modified = true;
    }

    /// Yank block selection (column-wise yank)
    pub fn yankBlockSelection(self: *GrimEditorWidget) !void {
        const block = self.getBlockSelection() orelse return;
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        // Calculate total size needed
        var total_size: usize = 0;
        var line = block.start_line;
        while (line <= block.end_line) : (line += 1) {
            const yank_start = self.lineColToOffset(content, line, block.start_col);
            const yank_end = self.lineColToOffset(content, line, block.end_col + 1);
            if (yank_start < yank_end and yank_end <= content.len) {
                total_size += yank_end - yank_start;
            }
            if (line < block.end_line) {
                total_size += 1; // newline
            }
        }

        // Allocate and build yank buffer
        const yank_buffer = try self.allocator.alloc(u8, total_size);
        defer self.allocator.free(yank_buffer);

        var offset: usize = 0;
        line = block.start_line;
        while (line <= block.end_line) : (line += 1) {
            const yank_start = self.lineColToOffset(content, line, block.start_col);
            const yank_end = self.lineColToOffset(content, line, block.end_col + 1);

            if (yank_start < yank_end and yank_end <= content.len) {
                const len = yank_end - yank_start;
                @memcpy(yank_buffer[offset..][0..len], content[yank_start..yank_end]);
                offset += len;
            }
            if (line < block.end_line) {
                yank_buffer[offset] = '\n';
                offset += 1;
            }
        }

        // Store in clipboard
        if (self.clipboard) |clip| {
            try clip.copy(yank_buffer);
        }

        self.visual_mode = .none;
        self.visual_anchor = null;
    }

    /// Convert line/column to byte offset
    fn lineColToOffset(self: *GrimEditorWidget, content: []const u8, target_line: usize, target_col: usize) usize {
        _ = self;
        var line: usize = 0;
        var col: usize = 0;
        var i: usize = 0;

        while (i < content.len) : (i += 1) {
            if (line == target_line and col == target_col) {
                return i;
            }
            if (content[i] == '\n') {
                if (line == target_line) {
                    // Reached end of target line
                    return i;
                }
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }

        return i;
    }

    /// Block insert - enter insert mode at start of block selection
    pub fn blockInsert(self: *GrimEditorWidget) !void {
        const block = self.getBlockSelection() orelse return;

        // Move cursor to start of block (top-left corner)
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        const insert_offset = self.lineColToOffset(content, block.start_line, block.start_col);
        self.editor.cursor.offset = insert_offset;

        self.visual_mode = .none;
        self.visual_anchor = null;
        // Note: Caller should switch to insert mode
    }

    /// Block append - enter insert mode at end of block selection
    pub fn blockAppend(self: *GrimEditorWidget) !void {
        const block = self.getBlockSelection() orelse return;

        // Move cursor to end of block (top-right corner + 1)
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        const append_offset = self.lineColToOffset(content, block.start_line, block.end_col + 1);
        self.editor.cursor.offset = append_offset;

        self.visual_mode = .none;
        self.visual_anchor = null;
        // Note: Caller should switch to insert mode
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
    /// Mark a single line as dirty (needs redraw)
    pub fn markLineDirty(self: *GrimEditorWidget, line: usize) void {
        // Ensure bitset has enough capacity
        if (line >= self.dirty_lines.capacity()) {
            const new_capacity = @max(line + 1, self.dirty_lines.capacity() * 2);
            self.dirty_lines.resize(new_capacity, false) catch return;
        }
        self.dirty_lines.set(line);
    }

    /// Mark a range of lines as dirty
    pub fn markLinesDirty(self: *GrimEditorWidget, start_line: usize, end_line: usize) void {
        const last_line = @min(end_line, self.editor.rope.lineCount());
        var line = start_line;
        while (line <= last_line) : (line += 1) {
            self.markLineDirty(line);
        }
    }

    /// Mark all visible lines as dirty (force full redraw)
    pub fn markAllDirty(self: *GrimEditorWidget) void {
        self.full_redraw_needed = true;
    }

    /// Clear all dirty flags after rendering
    fn clearDirtyFlags(self: *GrimEditorWidget) void {
        self.dirty_lines.setRangeValue(.{ .start = 0, .end = self.dirty_lines.capacity() }, false);
        self.full_redraw_needed = false;
    }

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
        // Use editor's nextMatch method
        if (self.editor.nextMatch()) {
            // Update widget's search match index to match editor's
            if (self.editor.current_match_index) |idx| {
                self.current_match_index = idx;
            }
        }
    }

    pub fn searchPrev(self: *GrimEditorWidget) !void {
        // Use editor's previousMatch method
        if (self.editor.previousMatch()) {
            // Update widget's search match index to match editor's
            if (self.editor.current_match_index) |idx| {
                self.current_match_index = idx;
            }
        }
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

    /// Perform search and replace operation
    /// pattern: the text to search for
    /// replacement: the text to replace with
    /// global_range: if true, replace in entire file; if false, replace only on current line
    /// global_flag: if true, replace all occurrences on each line; if false, replace only first occurrence
    /// confirm: if true, ask for confirmation (not implemented yet)
    pub fn substitute(
        self: *GrimEditorWidget,
        pattern: []const u8,
        replacement: []const u8,
        global_range: bool,
        global_flag: bool,
        confirm: bool,
    ) !void {
        _ = confirm; // TODO: Implement confirmation

        if (pattern.len == 0) return;

        // Save undo state before making changes
        try self.editor.saveUndoState("substitute");

        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        const cursor_offset = self.editor.cursor.offset;

        var replace_count: usize = 0;
        var offset_adjustment: isize = 0;

        if (global_range) {
            // Replace in entire file
            var search_offset: usize = 0;
            while (search_offset < content.len) {
                const remaining = content[search_offset..];
                if (std.mem.indexOf(u8, remaining, pattern)) |match_pos| {
                    const absolute_pos = search_offset + match_pos;
                    const adjusted_pos = @as(usize, @intCast(@as(isize, @intCast(absolute_pos)) + offset_adjustment));

                    // Delete the pattern
                    try self.editor.rope.delete(adjusted_pos, pattern.len);
                    // Insert the replacement
                    try self.editor.rope.insert(adjusted_pos, replacement);

                    // Track offset adjustment
                    offset_adjustment += @as(isize, @intCast(replacement.len)) - @as(isize, @intCast(pattern.len));
                    replace_count += 1;

                    // Move search position forward
                    if (global_flag) {
                        search_offset = absolute_pos + pattern.len;
                    } else {
                        // Skip to next line
                        const newline_pos = std.mem.indexOfScalar(u8, remaining[match_pos..], '\n');
                        search_offset = if (newline_pos) |pos|
                            absolute_pos + pos + 1
                        else
                            content.len;
                    }
                } else {
                    break;
                }
            }
        } else {
            // Replace only on current line
            const line_start = blk: {
                var pos = cursor_offset;
                while (pos > 0 and content[pos - 1] != '\n') {
                    pos -= 1;
                }
                break :blk pos;
            };

            const line_end = blk: {
                var pos = cursor_offset;
                while (pos < content.len and content[pos] != '\n') {
                    pos += 1;
                }
                break :blk pos;
            };

            const line = content[line_start..line_end];
            var search_offset: usize = 0;

            while (search_offset < line.len) {
                if (std.mem.indexOf(u8, line[search_offset..], pattern)) |match_pos| {
                    const absolute_pos = line_start + search_offset + match_pos;
                    const adjusted_pos = @as(usize, @intCast(@as(isize, @intCast(absolute_pos)) + offset_adjustment));

                    // Delete the pattern
                    try self.editor.rope.delete(adjusted_pos, pattern.len);
                    // Insert the replacement
                    try self.editor.rope.insert(adjusted_pos, replacement);

                    // Track offset adjustment
                    offset_adjustment += @as(isize, @intCast(replacement.len)) - @as(isize, @intCast(pattern.len));
                    replace_count += 1;

                    if (global_flag) {
                        search_offset = search_offset + match_pos + pattern.len;
                    } else {
                        break; // Only replace first occurrence
                    }
                } else {
                    break;
                }
            }
        }

        // Update cursor position if it was affected
        const new_cursor_offset = @as(usize, @intCast(@as(isize, @intCast(cursor_offset)) + offset_adjustment));
        self.editor.cursor.offset = @min(new_cursor_offset, self.editor.rope.len());

        self.highlight_dirty = true;
        if (replace_count > 0) {
            self.is_modified = true;
        }

        std.log.info("Replaced {d} occurrence(s)", .{replace_count});
    }

    fn highlightStyleFromType(self: *GrimEditorWidget, hl_type: syntax.HighlightType) phantom.Style {
        _ = self;
        return switch (hl_type) {
            .keyword => phantom.Style.default().withFg(phantom.Color.magenta),
            .type_name => phantom.Style.default().withFg(phantom.Color.cyan),
            .function_name => phantom.Style.default().withFg(phantom.Color.blue),
            .string_literal => phantom.Style.default().withFg(phantom.Color.green),
            .number_literal => phantom.Style.default().withFg(phantom.Color.yellow),
            .comment => phantom.Style.default().withFg(phantom.Color.bright_black),
            .operator => phantom.Style.default().withFg(phantom.Color.red),
            .punctuation => phantom.Style.default().withFg(phantom.Color.white),
            .variable => phantom.Style.default().withFg(phantom.Color.white),
            .@"error" => phantom.Style.default().withFg(phantom.Color.red),
            .none => phantom.Style.default().withFg(phantom.Color.white),
        };
    }

    // === Register and clipboard operations ===

    /// Set register content (null for unnamed register)
    pub fn setRegister(self: *GrimEditorWidget, register: ?u8, text: []const u8) !void {
        if (register) |reg| {
            // '+' register = system clipboard
            if (reg == '+') {
                try self.copyToClipboard(text);
                return;
            }

            // Named register (a-z)
            const key = [_]u8{reg};
            const owned_text = try self.allocator.dupe(u8, text);
            if (self.named_registers.get(&key)) |old_value| {
                self.allocator.free(old_value);
            }
            try self.named_registers.put(&key, owned_text);
        } else {
            // Unnamed register
            if (self.unnamed_register) |old| {
                self.allocator.free(old);
            }
            self.unnamed_register = try self.allocator.dupe(u8, text);

            // Also try to copy to system clipboard
            self.copyToClipboard(text) catch |err| {
                std.log.warn("Failed to copy to clipboard: {}", .{err});
            };
        }
    }

    /// Get register content (null for unnamed register, '+' for system clipboard)
    pub fn getRegister(self: *GrimEditorWidget, register: ?u8) ?[]const u8 {
        if (register) |reg| {
            // '+' register = system clipboard
            if (reg == '+') {
                if (self.pasteFromClipboard()) |clipboard_text| {
                    return clipboard_text;
                } else |_| {
                    std.log.warn("Failed to paste from clipboard", .{});
                    return null;
                }
            }

            const key = [_]u8{reg};
            return self.named_registers.get(&key);
        } else {
            return self.unnamed_register;
        }
    }

    /// Paste from register at cursor
    pub fn paste(self: *GrimEditorWidget, register: ?u8) !void {
        const text = self.getRegister(register) orelse return;
        try self.editor.saveUndoState("paste");
        try self.editor.rope.insert(self.editor.cursor.offset, text);
        self.editor.cursor.offset += text.len;
        self.highlight_dirty = true;
        self.is_modified = true;
    }

    /// Yank current line to register
    pub fn yankLine(self: *GrimEditorWidget, register: ?u8) !void {
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        const cursor_offset = self.editor.cursor.offset;

        // Find line start
        var line_start = cursor_offset;
        while (line_start > 0 and content[line_start - 1] != '\n') {
            line_start -= 1;
        }

        // Find line end (include newline)
        var line_end = cursor_offset;
        while (line_end < content.len and content[line_end] != '\n') {
            line_end += 1;
        }
        if (line_end < content.len) line_end += 1;

        const line_text = content[line_start..line_end];
        try self.setRegister(register, line_text);
    }

    /// Delete current line to register
    pub fn deleteLine(self: *GrimEditorWidget, register: ?u8) !void {
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        const cursor_offset = self.editor.cursor.offset;

        // Find line start
        var line_start = cursor_offset;
        while (line_start > 0 and content[line_start - 1] != '\n') {
            line_start -= 1;
        }

        // Find line end (include newline)
        var line_end = cursor_offset;
        while (line_end < content.len and content[line_end] != '\n') {
            line_end += 1;
        }
        if (line_end < content.len) line_end += 1;

        const line_text = content[line_start..line_end];
        try self.setRegister(register, line_text);

        // Save undo state before deletion
        try self.editor.saveUndoState("delete line");

        // Delete the line
        try self.editor.rope.delete(line_start, line_end - line_start);
        self.editor.cursor.offset = line_start;
        self.highlight_dirty = true;
        self.is_modified = true;
    }

    /// Copy text to system clipboard
    fn copyToClipboard(self: *GrimEditorWidget, text: []const u8) !void {
        if (self.clipboard) |clipboard| {
            try clipboard.copy(text);
        } else {
            return error.ClipboardNotAvailable;
        }
    }

    /// Get text from system clipboard
    fn pasteFromClipboard(self: *GrimEditorWidget) ![]u8 {
        if (self.clipboard) |clipboard| {
            return try clipboard.paste();
        } else {
            return error.ClipboardNotAvailable;
        }
    }

    /// Set clipboard reference (called by parent app)
    pub fn setClipboard(self: *GrimEditorWidget, clipboard: *core.Clipboard) void {
        self.clipboard = clipboard;
    }

    // === Undo/Redo operations ===

    /// Undo last change
    pub fn undo(self: *GrimEditorWidget) !void {
        try self.editor.undo();
        self.highlight_dirty = true;
    }

    /// Redo last undone change
    pub fn redo(self: *GrimEditorWidget) !void {
        try self.editor.redo();
        self.highlight_dirty = true;
    }

    /// End undo grouping (call when leaving insert mode)
    pub fn endUndoGroup(self: *GrimEditorWidget) void {
        // No-op now, undo is automatic per-operation
        _ = self;
    }

    // === Macro operations ===

    /// Start recording macro to register (a-z)
    pub fn startRecordingMacro(self: *GrimEditorWidget, register: u8) !void {
        if (self.recording_macro != null) {
            // Already recording, stop recording first
            self.stopRecordingMacro();
        }

        self.recording_macro = register;
        self.macro_buffer.clearRetainingCapacity();
    }

    /// Stop recording macro and save it
    pub fn stopRecordingMacro(self: *GrimEditorWidget) void {
        if (self.recording_macro) |register| {
            // Save macro to storage
            const key = [_]u8{register};
            const macro_keys = self.allocator.dupe(phantom.Key, self.macro_buffer.items) catch return;

            // Free old macro if exists
            if (self.macros.get(&key)) |old_macro| {
                self.allocator.free(old_macro);
            }

            self.macros.put(&key, macro_keys) catch return;
            self.recording_macro = null;
        }
    }

    /// Record a key press (if recording)
    pub fn recordKey(self: *GrimEditorWidget, key: phantom.Key) !void {
        if (self.recording_macro != null) {
            try self.macro_buffer.append(self.allocator, key);
        }
    }

    /// Replay macro from register (a-z)
    /// Returns the list of keys to replay (caller is responsible for injecting them)
    pub fn replayMacro(self: *GrimEditorWidget, register: u8) !?[]const phantom.Key {
        const key = [_]u8{register};
        const macro = self.macros.get(&key) orelse {
            std.log.warn("No macro recorded in register '{c}'", .{register});
            return null;
        };

        std.log.info("Replaying macro '{c}' ({d} keys)", .{ register, macro.len });
        return macro;
    }

    /// Check if currently recording
    pub fn isRecording(self: *GrimEditorWidget) bool {
        return self.recording_macro != null;
    }

    // === Mouse handling ===

    const MouseEvent = @typeInfo(phantom.Event).@"union".fields[1].type;

    /// Handle mouse events (click, scroll, drag)
    pub fn handleMouseEvent(self: *GrimEditorWidget, mouse: MouseEvent, area: phantom.Rect) !void {
        // Handle scroll wheel
        if (mouse.button == .wheel_up) {
            // Scroll up 3 lines
            if (self.viewport_top_line >= 3) {
                self.viewport_top_line -= 3;
            } else {
                self.viewport_top_line = 0;
            }
            return;
        } else if (mouse.button == .wheel_down) {
            // Scroll down 3 lines
            const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() }) catch return;
            var total_lines: usize = 1;
            for (content) |ch| {
                if (ch == '\n') total_lines += 1;
            }
            if (self.viewport_top_line + 3 < total_lines) {
                self.viewport_top_line += 3;
            }
            return;
        }

        // Handle left/right click
        if (mouse.pressed) {
            // Press event
            if (mouse.button == .left) {
                // Left click - position cursor
                try self.handleMouseClick(mouse.position.x, mouse.position.y, area);
            }
        }
        // TODO: Handle drag for visual selection when phantom supports it
    }

    /// Convert mouse click coordinates to buffer offset and position cursor
    fn handleMouseClick(self: *GrimEditorWidget, x: u16, y: u16, area: phantom.Rect) !void {
        // Calculate which line was clicked (accounting for viewport)
        const clicked_line = self.viewport_top_line + y;

        // Get line range
        const line_range = self.editor.rope.lineRange(clicked_line) catch return;

        // Find column position (accounting for line numbers + gutter)
        const content_start_x: usize = 6; // Line number width
        if (x < content_start_x) {
            // Clicked in gutter - go to line start
            self.editor.cursor.offset = line_range.start;
            return;
        }

        const col_clicked = if (x >= content_start_x) x - content_start_x else 0;

        // Get line content
        const line_content = self.editor.rope.slice(line_range) catch return;

        // Walk through line content to find byte offset at clicked column
        var col: usize = 0;
        var offset = line_range.start;
        var iter = (try std.unicode.Utf8View.init(line_content)).iterator();

        while (iter.nextCodepoint()) |_| {
            if (col >= col_clicked) break;
            col += 1;
            offset = line_range.start + iter.i;
        }

        self.editor.cursor.offset = offset;
        _ = area;
    }

    /// Attach LSP client to this editor widget
    pub fn attachLSP(self: *GrimEditorWidget, lsp_client: *editor_lsp_mod.EditorLSP) void {
        self.lsp_client = lsp_client;
    }

    /// Detach LSP client from this editor widget
    pub fn detachLSP(self: *GrimEditorWidget) void {
        self.lsp_client = null;
    }
};

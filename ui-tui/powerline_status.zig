//! Powerline-style status bar with segments (like powerlevel10k)

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const Editor = @import("editor.zig").Editor;
const GrimEditorWidget = @import("grim_editor_widget.zig").GrimEditorWidget;

// Powerline separator characters
const POWERLINE_RIGHT_ARROW = "";
const POWERLINE_LEFT_ARROW = "";
const POWERLINE_RIGHT_TRIANGLE = "";
const POWERLINE_LEFT_TRIANGLE = "";

// Icons (Nerd Font)
const ICON_GIT_BRANCH = "";
const ICON_LOCK = "";
const ICON_MODIFIED = "";
const ICON_READONLY = "";
const ICON_RECORDING = "";
const ICON_LSP_LOADING = "󰔟"; // LSP loading spinner icon

pub const PowerlineStatus = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    width: u16,

    pub fn init(allocator: std.mem.Allocator, width: u16) !*PowerlineStatus {
        const self = try allocator.create(PowerlineStatus);
        self.* = .{
            .allocator = allocator,
            .buffer = .{},
            .width = width,
        };
        return self;
    }

    pub fn deinit(self: *PowerlineStatus) void {
        self.buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn resize(self: *PowerlineStatus, new_width: u16) void {
        self.width = new_width;
    }

    pub fn render(self: *PowerlineStatus, buffer: anytype, area: phantom.Rect, editor_widget: *GrimEditorWidget, mode: anytype, git: *core.Git) !void {
        self.buffer.clearRetainingCapacity();

        // Segment 1: Mode (left side)
        try self.renderModeSegment(mode);

        // Segment 2: Recording indicator (if recording)
        if (editor_widget.isRecording()) {
            try self.renderRecordingSegment(editor_widget.recording_macro.?);
        }

        // Segment 3: LSP Loading indicator
        if (editor_widget.lsp_client) |lsp| {
            if (lsp.isLoading()) {
                try self.renderLSPLoadingSegment();
            }
        }

        // Segment 4: Modified indicator
        if (editor_widget.is_modified) {
            try self.renderModifiedSegment();
        }

        // Segment 5: File path
        const filename = editor_widget.editor.current_filename orelse "[No Name]";
        try self.renderFileSegment(filename);

        // Calculate right-side segments position
        const editor = editor_widget.editor;

        // Get position directly from rope without allocating full content
        const cursor_offset = editor.cursor.offset;
        const total_lines = editor.rope.lineCount();

        var line: usize = 0;
        var col: usize = 0;

        if (editor.rope.lineColumnAtOffset(cursor_offset)) |lc| {
            line = lc.line;
            col = lc.column;
        } else |_| {}

        const percent = if (total_lines > 0)
            @as(u8, @intCast(@min(100, (line * 100) / total_lines)))
        else
            0;

        const pos = .{ .line = line, .col = col, .percent = percent };

        // Render right-aligned segments
        var right_buffer = std.ArrayList(u8){};
        defer right_buffer.deinit(self.allocator);

        // Git branch (right side)
        if (git.getCurrentBranch()) |branch| {
            defer self.allocator.free(branch);
            try self.renderGitSegment(&right_buffer, branch);
        } else |_| {}

        // Position indicator
        try self.renderPositionSegment(&right_buffer, pos.line, pos.col, pos.percent);

        // Write left segments
        const left_len = self.buffer.items.len;
        try self.writeToBuffer(buffer, area, 0, self.buffer.items);

        // Write right segments
        const right_len = right_buffer.items.len;
        if (right_len < area.width) {
            const right_start = area.width - @as(u16, @intCast(right_len));
            try self.writeToBuffer(buffer, area, right_start, right_buffer.items);
        }

        // Fill middle with background
        const middle_start = @as(u16, @intCast(@min(left_len, area.width)));
        const middle_end = if (right_len < area.width) area.width - @as(u16, @intCast(right_len)) else area.width;
        if (middle_start < middle_end) {
            const fill_style = phantom.Style.default()
                .withBg(phantom.Color.black);
            var x = middle_start;
            while (x < middle_end) : (x += 1) {
                buffer.setCell(area.x + x, area.y, .{ .char = ' ', .style = fill_style });
            }
        }
    }

    fn renderModeSegment(self: *PowerlineStatus, mode: anytype) !void {
        const mode_name = @tagName(mode);
        const mode_text = if (std.mem.eql(u8, mode_name, "normal"))
            " NORMAL "
        else if (std.mem.eql(u8, mode_name, "insert"))
            " INSERT "
        else if (std.mem.eql(u8, mode_name, "visual"))
            " VISUAL "
        else if (std.mem.eql(u8, mode_name, "visual_line"))
            " V-LINE "
        else if (std.mem.eql(u8, mode_name, "visual_block"))
            " V-BLOCK "
        else if (std.mem.eql(u8, mode_name, "command"))
            " COMMAND "
        else
            " NORMAL ";

        // Mode colors (bright bg, black fg)
        const bg_color = if (std.mem.eql(u8, mode_name, "insert"))
            "\x1b[42m" // Green
        else if (std.mem.eql(u8, mode_name, "visual") or
                 std.mem.eql(u8, mode_name, "visual_line") or
                 std.mem.eql(u8, mode_name, "visual_block"))
            "\x1b[45m" // Magenta
        else if (std.mem.eql(u8, mode_name, "command"))
            "\x1b[43m" // Yellow
        else
            "\x1b[44m"; // Blue (normal)

        const text = try std.fmt.allocPrint(self.allocator, "{s}\x1b[30m{s}\x1b[0m", .{ bg_color, mode_text });
        defer self.allocator.free(text);
        try self.buffer.appendSlice(self.allocator, text);

        const arrow = try std.fmt.allocPrint(self.allocator, "{s}{s}\x1b[0m ", .{ bg_color, POWERLINE_RIGHT_ARROW });
        defer self.allocator.free(arrow);
        try self.buffer.appendSlice(self.allocator, arrow);
    }

    fn renderRecordingSegment(self: *PowerlineStatus, register: u8) !void {
        const text = try std.fmt.allocPrint(self.allocator, "\x1b[41m\x1b[30m {s} REC[{c}] \x1b[0m", .{ ICON_RECORDING, register });
        defer self.allocator.free(text);
        try self.buffer.appendSlice(self.allocator, text);

        const arrow = try std.fmt.allocPrint(self.allocator, "\x1b[41m{s}\x1b[0m ", .{POWERLINE_RIGHT_ARROW});
        defer self.allocator.free(arrow);
        try self.buffer.appendSlice(self.allocator, arrow);
    }

    fn renderLSPLoadingSegment(self: *PowerlineStatus) !void {
        const text = try std.fmt.allocPrint(self.allocator, "\x1b[46m\x1b[30m {s} LSP \x1b[0m ", .{ICON_LSP_LOADING});
        defer self.allocator.free(text);
        try self.buffer.appendSlice(self.allocator, text);
    }

    fn renderModifiedSegment(self: *PowerlineStatus) !void {
        const text = try std.fmt.allocPrint(self.allocator, "\x1b[101m\x1b[30m {s} \x1b[0m ", .{ICON_MODIFIED});
        defer self.allocator.free(text);
        try self.buffer.appendSlice(self.allocator, text);
    }

    fn renderFileSegment(self: *PowerlineStatus, filename: []const u8) !void {
        const basename = std.fs.path.basename(filename);
        const icon = self.getFileIcon(basename);
        const text = try std.fmt.allocPrint(self.allocator, "\x1b[100m\x1b[37m {s} {s} \x1b[0m", .{ icon, basename });
        defer self.allocator.free(text);
        try self.buffer.appendSlice(self.allocator, text);
    }

    fn renderGitSegment(self: *PowerlineStatus, buf: *std.ArrayList(u8), branch: []const u8) !void {
        const text = try std.fmt.allocPrint(self.allocator, "\x1b[46m\x1b[30m {s}{s} {s} \x1b[0m", .{ POWERLINE_LEFT_ARROW, ICON_GIT_BRANCH, branch });
        defer self.allocator.free(text);
        try buf.appendSlice(self.allocator, text);
    }

    fn renderPositionSegment(self: *PowerlineStatus, buf: *std.ArrayList(u8), line: usize, col: usize, percent: u8) !void {
        const pos_text = try std.fmt.allocPrint(self.allocator, "\x1b[100m\x1b[37m{s} {d}:{d} \x1b[0m", .{ POWERLINE_LEFT_ARROW, line + 1, col + 1 });
        defer self.allocator.free(pos_text);
        try buf.appendSlice(self.allocator, pos_text);

        const percent_text = try std.fmt.allocPrint(self.allocator, "\x1b[44m\x1b[30m{s} {d}% \x1b[0m", .{ POWERLINE_LEFT_ARROW, percent });
        defer self.allocator.free(percent_text);
        try buf.appendSlice(self.allocator, percent_text);
    }

    fn getFileIcon(self: *PowerlineStatus, filename: []const u8) []const u8 {
        _ = self;
        const ext = std.fs.path.extension(filename);

        if (std.mem.eql(u8, ext, ".zig")) return "";
        if (std.mem.eql(u8, ext, ".py")) return "";
        if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".ts")) return "";
        if (std.mem.eql(u8, ext, ".rs")) return "";
        if (std.mem.eql(u8, ext, ".go")) return "";
        if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return "";
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp")) return "";
        if (std.mem.eql(u8, ext, ".md")) return "";
        if (std.mem.eql(u8, ext, ".json")) return "";
        if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return "";
        if (std.mem.eql(u8, ext, ".toml")) return "";
        if (std.mem.eql(u8, ext, ".sh")) return "";

        return ""; // Default file icon
    }


    fn writeToBuffer(self: *PowerlineStatus, buffer: anytype, area: phantom.Rect, start_x: u16, text: []const u8) !void {
        _ = self;
        var x = start_x;
        var i: usize = 0;

        while (i < text.len and x < area.width) {
            if (text[i] == '\x1b') {
                // Skip ANSI escape sequences (we'll handle them differently)
                while (i < text.len and text[i] != 'm') : (i += 1) {}
                if (i < text.len) i += 1;
                continue;
            }

            // For now, just write characters without ANSI processing
            // In real impl, you'd parse ANSI and apply styles
            buffer.setCell(area.x + x, area.y, .{
                .char = text[i],
                .style = phantom.Style.default()
            });
            x += 1;
            i += 1;
        }
    }
};

const std = @import("std");
const phantom = @import("phantom");
const Editor = @import("editor.zig").Editor;
const GrimEditorWidget = @import("grim_editor_widget.zig").GrimEditorWidget;
const core = @import("core");

pub const StatusBar = struct {
    flex_row: *phantom.widgets.FlexRow,
    allocator: std.mem.Allocator,
    width: u16,

    pub fn init(allocator: std.mem.Allocator, width: u16) !*StatusBar {
        const self = try allocator.create(StatusBar);

        const flex_row = try phantom.widgets.FlexRow.init(allocator);

        // Configure layout (set directly on fields)
        flex_row.justify = .space_between;  // Space items evenly
        flex_row.alignment = .center;       // Center vertically
        flex_row.gap = 1;                   // 1 space between items

        self.* = .{
            .flex_row = flex_row,
            .allocator = allocator,
            .width = width,
        };

        return self;
    }

    pub fn deinit(self: *StatusBar) void {
        // Clean up any remaining child widgets before freeing flex_row
        for (self.flex_row.children.items) |child| {
            child.widget.vtable.deinit(child.widget);
        }
        self.flex_row.widget.vtable.deinit(&self.flex_row.widget);
        self.allocator.destroy(self);
    }

    pub fn update(self: *StatusBar, editor_widget: *GrimEditorWidget, grim_mode: anytype, git: *core.Git) !void {
        // Clean up old widgets before creating new ones
        for (self.flex_row.children.items) |child| {
            child.widget.vtable.deinit(child.widget);
        }
        self.flex_row.children.clearRetainingCapacity();

        const editor = editor_widget.editor;

        // Left section: Mode indicator (fixed width)
        const mode_text = try self.modeText(grim_mode);
        const mode_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            mode_text,
            self.modeStyle(grim_mode),
        );
        try self.flex_row.addChild(.{ .widget = &mode_widget.widget, .flex_basis =10 });

        // Recording indicator
        if (editor_widget.isRecording()) {
            const recording_register = editor_widget.recording_macro.?;
            const rec_text = try std.fmt.allocPrint(
                self.allocator,
                " REC[{c}] ",
                .{recording_register},
            );
            defer self.allocator.free(rec_text);
            const rec_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                rec_text,
                phantom.Style.default()
                    .withFg(phantom.Color.black)
                    .withBg(phantom.Color.red)
                    .withBold(),
            );
            try self.flex_row.addChild(.{ .widget = &rec_widget.widget, .flex_basis =@intCast(rec_text.len) });
        }

        // File modification indicator
        if (editor_widget.is_modified) {
            const modified_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                "[+]",
                phantom.Style.default().withFg(phantom.Color.bright_red).withBold(),
            );
            try self.flex_row.addChild(.{ .widget = &modified_widget.widget, .flex_basis =4 });
        }

        // Middle section: File path (flexible, grows to fill space)
        const file_path = editor.current_filename orelse "[No Name]";
        const file_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            file_path,
            phantom.Style.default().withFg(phantom.Color.bright_cyan),
        );
        try self.flex_row.addChild(.{ .widget = &file_widget.widget, .flex_grow = 1.0 });

        // File type indicator (if available)
        const lang_name = editor.getLanguageName();
        if (lang_name.len > 0) {
            const ft_text = try std.fmt.allocPrint(
                self.allocator,
                " {s} ",
                .{lang_name},
            );
            defer self.allocator.free(ft_text);
            const ft_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                ft_text,
                phantom.Style.default()
                    .withFg(phantom.Color.bright_white)
                    .withBg(phantom.Color.bright_black),
            );
            try self.flex_row.addChild(.{ .widget = &ft_widget.widget, .flex_basis =@intCast(ft_text.len) });
        }

        // Right section: Cursor position (fixed width)
        const cursor_line_col = editor.rope.lineColumnAtOffset(editor.cursor.offset) catch return;
        const pos_text = try std.fmt.allocPrint(
            self.allocator,
            "{}:{}",
            .{ cursor_line_col.line + 1, cursor_line_col.column + 1 },
        );
        defer self.allocator.free(pos_text);
        const pos_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            pos_text,
            phantom.Style.default().withFg(phantom.Color.bright_yellow),
        );
        try self.flex_row.addChild(.{ .widget = &pos_widget.widget, .flex_basis =12 });

        // Line count / percentage
        const total_lines = editor.rope.lineCount();
        const line_percent = if (total_lines > 0)
            (cursor_line_col.line * 100) / total_lines
        else
            0;

        const percent_text = try std.fmt.allocPrint(
            self.allocator,
            "{d}%",
            .{line_percent},
        );
        defer self.allocator.free(percent_text);
        const percent_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            percent_text,
            phantom.Style.default().withFg(phantom.Color.bright_white),
        );
        try self.flex_row.addChild(.{ .widget = &percent_widget.widget, .flex_basis =5 });

        // Git branch display
        if (git.getCurrentBranch()) |branch| {
            defer self.allocator.free(branch);
            const branch_text = try std.fmt.allocPrint(
                self.allocator,
                "  {s}",
                .{branch},
            );
            defer self.allocator.free(branch_text);
            const branch_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                branch_text,
                phantom.Style.default()
                    .withFg(phantom.Color.cyan)
                    .withBold(),
            );
            try self.flex_row.addChild(.{ .widget = &branch_widget.widget, .flex_basis =@intCast(branch_text.len) });
        } else |_| {
            // Not in a git repo or branch detection failed - silently ignore
        }
    }

    pub fn resize(self: *StatusBar, new_width: u16) void {
        self.width = new_width;
        // FlexRow doesn't have a width field - it sizes based on render area
    }

    pub fn render(self: *StatusBar, buffer: *phantom.Buffer, area: phantom.Rect) void {
        self.flex_row.widget.vtable.render(&self.flex_row.widget, buffer, area);
    }

    fn modeText(self: *StatusBar, mode: anytype) ![]const u8 {
        _ = self;
        // Handle both simple and extended mode enums
        const mode_name = @tagName(mode);
        if (std.mem.eql(u8, mode_name, "normal")) return " NORMAL ";
        if (std.mem.eql(u8, mode_name, "insert")) return " INSERT ";
        if (std.mem.eql(u8, mode_name, "visual")) return " VISUAL ";
        if (std.mem.eql(u8, mode_name, "visual_line")) return " V-LINE ";
        if (std.mem.eql(u8, mode_name, "visual_block")) return " V-BLOCK ";
        if (std.mem.eql(u8, mode_name, "command")) return " COMMAND ";
        return " NORMAL ";
    }

    fn modeStyle(self: *StatusBar, mode: anytype) phantom.Style {
        _ = self;
        const mode_name = @tagName(mode);
        if (std.mem.eql(u8, mode_name, "insert")) {
            return phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.green)
                .withBold();
        }
        if (std.mem.eql(u8, mode_name, "visual") or
            std.mem.eql(u8, mode_name, "visual_line") or
            std.mem.eql(u8, mode_name, "visual_block")) {
            return phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.magenta)
                .withBold();
        }
        if (std.mem.eql(u8, mode_name, "command")) {
            return phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.yellow)
                .withBold();
        }
        // Default: normal mode
        return phantom.Style.default()
            .withFg(phantom.Color.black)
            .withBg(phantom.Color.blue)
            .withBold();
    }
};

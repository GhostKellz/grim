const std = @import("std");
const phantom = @import("phantom");
const Editor = @import("editor.zig").Editor;
const GrimMode = @import("app.zig").Mode;

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
        self.flex_row.widget.vtable.deinit(&self.flex_row.widget);
        self.allocator.destroy(self);
    }

    pub fn update(self: *StatusBar, editor: *Editor) !void {
        // Clean up old widgets before creating new ones
        for (self.flex_row.children.items) |child| {
            child.widget.vtable.deinit(child.widget);
        }
        self.flex_row.children.clearRetainingCapacity();

        // Left section: Mode indicator (fixed width) - convert Editor.Mode to GrimMode
        const grim_mode: GrimMode = switch (editor.mode) {
            .normal => .normal,
            .insert => .insert,
            else => .normal,
        };
        const mode_text = try self.modeText(grim_mode);
        const mode_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            mode_text,
            self.modeStyle(grim_mode),
        );
        try self.flex_row.addChild(.{ .widget = &mode_widget.widget, .flex_basis =10 });

        // File modification indicator
        const modified = false; // TODO: Track modification state
        if (modified) {
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
        const percent_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            percent_text,
            phantom.Style.default().withFg(phantom.Color.bright_white),
        );
        try self.flex_row.addChild(.{ .widget = &percent_widget.widget, .flex_basis =5 });

        // LSP status is managed by GrimApp, not Editor
        // TODO: Pass LSP status from GrimApp if needed

        // Git branch info is managed by GrimApp, not Editor
        // TODO: Pass git_branch from GrimApp if needed
    }

    pub fn resize(self: *StatusBar, new_width: u16) void {
        self.width = new_width;
        // FlexRow doesn't have a width field - it sizes based on render area
    }

    pub fn render(self: *StatusBar, buffer: *phantom.Buffer, area: phantom.Rect) void {
        self.flex_row.widget.vtable.render(&self.flex_row.widget, buffer, area);
    }

    fn modeText(self: *StatusBar, mode: GrimMode) ![]const u8 {
        _ = self;
        return switch (mode) {
            .normal => " NORMAL ",
            .insert => " INSERT ",
        };
    }

    fn modeStyle(self: *StatusBar, mode: GrimMode) phantom.Style {
        _ = self;
        return switch (mode) {
            .normal => phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.blue)
                .withBold(),
            .insert => phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.green)
                .withBold(),
        };
    }
};

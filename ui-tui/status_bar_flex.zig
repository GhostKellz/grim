const std = @import("std");
const phantom = @import("phantom");
const Editor = @import("editor.zig").Editor;
const Mode = @import("app.zig").Mode;

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
        self.flex_row.clear();

        // Left section: Mode indicator (fixed width)
        const mode_text = try self.modeText(editor.mode);
        const mode_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            mode_text,
            self.modeStyle(editor.mode),
        );
        try self.flex_row.addChild(&mode_widget.widget, .{ .fixed = 10 });

        // File modification indicator
        if (editor.modified) {
            const modified_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                "[+]",
                phantom.Style.default().withFg(phantom.Color.bright_red).withBold(),
            );
            try self.flex_row.addChild(&modified_widget.widget, .{ .fixed = 4 });
        }

        // Middle section: File path (flexible, grows to fill space)
        const file_path = editor.current_file orelse "[No Name]";
        const file_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            file_path,
            phantom.Style.default().withFg(phantom.Color.bright_cyan),
        );
        try self.flex_row.addChild(&file_widget.widget, .{ .flex = 1 });

        // File type indicator (if available)
        if (editor.file_type) |ft| {
            const ft_text = try std.fmt.allocPrint(
                self.allocator,
                " {s} ",
                .{ft},
            );
            const ft_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                ft_text,
                phantom.Style.default()
                    .withFg(phantom.Color.bright_white)
                    .withBg(phantom.Color.bright_black),
            );
            try self.flex_row.addChild(&ft_widget.widget, .{ .fixed = @intCast(ft_text.len) });
        }

        // Right section: Cursor position (fixed width)
        const pos_text = try std.fmt.allocPrint(
            self.allocator,
            "{}:{}",
            .{ editor.cursor.line + 1, editor.cursor.col + 1 },
        );
        const pos_widget = try phantom.widgets.Text.initWithStyle(
            self.allocator,
            pos_text,
            phantom.Style.default().withFg(phantom.Color.bright_yellow),
        );
        try self.flex_row.addChild(&pos_widget.widget, .{ .fixed = 12 });

        // Line count / percentage
        const total_lines = editor.rope.line_count();
        const line_percent = if (total_lines > 0)
            (editor.cursor.line * 100) / total_lines
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
        try self.flex_row.addChild(&percent_widget.widget, .{ .fixed = 5 });

        // LSP status (if active)
        if (editor.lsp_client != null) {
            const lsp_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                " LSP ",
                phantom.Style.default()
                    .withFg(phantom.Color.black)
                    .withBg(phantom.Color.green)
                    .withBold(),
            );
            try self.flex_row.addChild(&lsp_widget.widget, .{ .fixed = 6 });
        }

        // Git branch (if in git repo)
        if (editor.git_branch) |branch| {
            const branch_text = try std.fmt.allocPrint(
                self.allocator,
                "  {s} ",
                .{branch},
            );
            const branch_widget = try phantom.widgets.Text.initWithStyle(
                self.allocator,
                branch_text,
                phantom.Style.default()
                    .withFg(phantom.Color.bright_magenta),
            );
            try self.flex_row.addChild(&branch_widget.widget, .{ .fixed = @intCast(branch_text.len) });
        }
    }

    pub fn resize(self: *StatusBar, new_width: u16) void {
        self.width = new_width;
        self.flex_row.width = new_width;
    }

    pub fn render(self: *StatusBar, buffer: *phantom.Buffer, area: phantom.Rect) !void {
        try self.flex_row.widget.vtable.render(&self.flex_row.widget, buffer, area);
    }

    fn modeText(self: *StatusBar, mode: Mode) ![]const u8 {
        _ = self;
        return switch (mode) {
            .normal => " NORMAL ",
            .insert => " INSERT ",
            .visual => " VISUAL ",
            .visual_line => " V-LINE ",
            .visual_block => " V-BLOCK",
            .command => " COMMAND",
            .search => " SEARCH ",
            .replace => " REPLACE",
        };
    }

    fn modeStyle(self: *StatusBar, mode: Mode) phantom.Style {
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
            .visual, .visual_line, .visual_block => phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.magenta)
                .withBold(),
            .command, .search => phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.yellow)
                .withBold(),
            .replace => phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.red)
                .withBold(),
        };
    }
};

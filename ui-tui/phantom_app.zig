const std = @import("std");
const phantom = @import("phantom");
const syntax = @import("syntax");
const Editor = @import("editor.zig").Editor;

pub const GrimApp = struct {
    allocator: std.mem.Allocator,
    app: phantom.App,
    editor: Editor,
    editor_widget: *EditorWidget,
    status_bar: *phantom.widgets.Text,
    command_line: *phantom.widgets.Input,

    const EditorWidget = struct {
        widget: phantom.Widget,
        editor: *Editor,
        viewport_offset: usize = 0,
        viewport_height: usize = 24,

        pub fn init(allocator: std.mem.Allocator, editor: *Editor) !*EditorWidget {
            var self = try allocator.create(EditorWidget);
            self.* = .{
                .widget = phantom.Widget.init(allocator, .{
                    .focusable = true,
                    .expandable = true,
                }),
                .editor = editor,
            };
            self.widget.setRenderFn(render);
            self.widget.setEventFn(handleEvent);
            self.widget.setUserData(self);
            return self;
        }

        fn render(widget: *phantom.Widget, canvas: *phantom.Canvas) !void {
            const self = @as(*EditorWidget, @ptrCast(@alignCast(widget.getUserData())));
            const bounds = widget.getBounds();

            // Clear the canvas area
            try canvas.fillRect(bounds, ' ', phantom.Style.default());

            // Get content from rope
            const content = self.editor.rope.slice(.{
                .start = 0,
                .end = self.editor.rope.len(),
            }) catch "";

            // Split into lines
            var lines = std.mem.tokenize(u8, content, "\n");
            var y: usize = 0;

            while (lines.next()) |line| : (y += 1) {
                if (y >= self.viewport_offset and y < self.viewport_offset + bounds.height) {
                    const screen_y = y - self.viewport_offset;

                    // Line numbers
                    var line_num_buf: [8]u8 = undefined;
                    const line_num_str = std.fmt.bufPrint(&line_num_buf, "{d:4} ", .{y + 1}) catch "";
                    try canvas.writeText(
                        bounds.x,
                        bounds.y + screen_y,
                        line_num_str,
                        phantom.Style.default().withFg(phantom.Color.dark_gray),
                    );

                    // Content
                    const content_x = bounds.x + 5;
                    const max_width = if (bounds.width > 5) bounds.width - 5 else 0;
                    const display_line = if (line.len > max_width) line[0..max_width] else line;

                    try canvas.writeText(
                        content_x,
                        bounds.y + screen_y,
                        display_line,
                        phantom.Style.default(),
                    );
                }
            }

            // Draw cursor
            const cursor_pos = self.getCursorPosition();
            if (cursor_pos.y >= self.viewport_offset and
                cursor_pos.y < self.viewport_offset + bounds.height)
            {
                const screen_y = cursor_pos.y - self.viewport_offset;
                const cursor_x = bounds.x + 5 + cursor_pos.x;

                try canvas.setCursorPos(cursor_x, bounds.y + screen_y);
                try canvas.showCursor();
            }
        }

        fn handleEvent(widget: *phantom.Widget, event: phantom.Event) !bool {
            const self = @as(*EditorWidget, @ptrCast(@alignCast(widget.getUserData())));

            switch (event) {
                .key => |key| {
                    switch (key) {
                        .char => |c| {
                            try self.editor.handleKey(c);
                            return true;
                        },
                        .ctrl => |c| {
                            // Handle Ctrl combinations
                            switch (c) {
                                'q' => return false, // Quit
                                's' => {
                                    // TODO: Save file
                                    return true;
                                },
                                else => {},
                            }
                        },
                        .special => |special| {
                            // Map special keys to editor commands
                            switch (special) {
                                .escape => try self.editor.handleKey(0x1B),
                                .enter => try self.editor.handleKey('\n'),
                                .backspace => {
                                    // Handle backspace in insert mode
                                    if (self.editor.mode == .insert) {
                                        if (self.editor.cursor.offset > 0) {
                                            self.editor.cursor.offset -= 1;
                                            try self.editor.rope.delete(self.editor.cursor.offset, 1);
                                        }
                                    }
                                },
                                .arrow_left => try self.editor.handleKey('h'),
                                .arrow_down => try self.editor.handleKey('j'),
                                .arrow_up => try self.editor.handleKey('k'),
                                .arrow_right => try self.editor.handleKey('l'),
                                else => {},
                            }
                            return true;
                        },
                    }
                },
                .mouse => |mouse| {
                    // Handle mouse clicks for cursor positioning
                    if (mouse.button == .left and mouse.action == .press) {
                        // TODO: Convert mouse position to cursor offset
                        return true;
                    }
                },
                .resize => {
                    // Update viewport on resize
                    const bounds = widget.getBounds();
                    self.viewport_height = bounds.height;
                    return true;
                },
                else => {},
            }

            return false;
        }

        fn getCursorPosition(self: *EditorWidget) struct { x: usize, y: usize } {
            const content = self.editor.rope.slice(.{
                .start = 0,
                .end = self.editor.cursor.offset,
            }) catch "";

            var x: usize = 0;
            var y: usize = 0;

            for (content) |ch| {
                if (ch == '\n') {
                    y += 1;
                    x = 0;
                } else {
                    x += 1;
                }
            }

            return .{ .x = x, .y = y };
        }
    };

    pub fn init(allocator: std.mem.Allocator) !*GrimApp {
        var self = try allocator.create(GrimApp);

        // Initialize editor
        self.editor = try Editor.init(allocator);

        // Initialize Phantom app
        self.app = try phantom.App.init(allocator, .{
            .title = "Grim Editor",
            .tick_rate_ms = 50,
            .mouse_enabled = true,
        });

        // Create main layout
        const layout = try phantom.layout.Vertical.init(allocator, .{
            .spacing = 0,
        });

        // Create editor widget
        self.editor_widget = try EditorWidget.init(allocator, &self.editor);

        // Create status bar
        self.status_bar = try phantom.widgets.Text.init(allocator, "");
        self.status_bar.widget.setStyle(phantom.Style.default()
            .withBg(phantom.Color.dark_gray)
            .withFg(phantom.Color.white));

        // Create command line (hidden by default)
        self.command_line = try phantom.widgets.Input.init(allocator, .{
            .prompt = ":",
            .visible = false,
        });

        // Add widgets to layout
        try layout.addWidget(&self.editor_widget.widget, .{ .flex = 1 });
        try layout.addWidget(&self.status_bar.widget, .{ .height = 1 });
        try layout.addWidget(&self.command_line.widget, .{ .height = 1 });

        // Set layout as root
        try self.app.setRootWidget(&layout.widget);

        // Set up event handler
        try self.app.event_loop.addHandler(handleAppEvent);
        self.app.event_loop.setUserData(self);

        self.allocator = allocator;
        self.* = .{
            .allocator = allocator,
            .app = self.app,
            .editor = self.editor,
            .editor_widget = self.editor_widget,
            .status_bar = self.status_bar,
            .command_line = self.command_line,
        };

        // Update initial status
        try self.updateStatusBar();

        return self;
    }

    pub fn deinit(self: *GrimApp) void {
        self.editor.deinit();
        self.app.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *GrimApp) !void {
        try self.app.run();
    }

    pub fn loadFile(self: *GrimApp, path: []const u8) !void {
        try self.editor.loadFile(path);
        try self.updateStatusBar();
    }

    fn handleAppEvent(event: phantom.Event, user_data: ?*anyopaque) !bool {
        const self = @as(*GrimApp, @ptrCast(@alignCast(user_data.?)));

        // Update status bar after each event
        defer self.updateStatusBar() catch {};

        switch (event) {
            .key => |key| {
                switch (key) {
                    .ctrl => |c| {
                        if (c == 'q') return false; // Quit app
                    },
                    else => {},
                }
            },
            else => {},
        }

        return true; // Continue running
    }

    fn updateStatusBar(self: *GrimApp) !void {
        var buf: [256]u8 = undefined;

        const mode_str = switch (self.editor.mode) {
            .normal => "NORMAL",
            .insert => "INSERT",
            .visual => "VISUAL",
            .command => "COMMAND",
        };

        const cursor_pos = self.editor_widget.getCursorPosition();

        const status = try std.fmt.bufPrint(&buf, " {s} | Line {d}, Col {d} | {d} bytes", .{
            mode_str,
            cursor_pos.y + 1,
            cursor_pos.x + 1,
            self.editor.rope.len(),
        });

        try self.status_bar.setText(status);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try GrimApp.init(allocator);
    defer app.deinit();

    // Load file if provided as argument
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        try app.loadFile(args[1]);
    }

    try app.run();
}

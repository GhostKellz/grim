const std = @import("std");
const phantom = @import("phantom");
const lsp = @import("lsp");
const editor_lsp = @import("editor_lsp.zig");


const Diagnostic = editor_lsp.Diagnostic;

pub const LSPDiagnosticsPanel = struct {
    scroll_view: *phantom.widgets.ScrollView,
    border: *phantom.widgets.Border,
    content_lines: std.ArrayListAligned([]const u8, null),
    allocator: std.mem.Allocator,
    visible: bool,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !*LSPDiagnosticsPanel {
        _ = width;
        _ = height;
        const self = try allocator.create(LSPDiagnosticsPanel);

        // Create ScrollView
        const scroll_view = try phantom.widgets.ScrollView.init(allocator);

        // Configure scrollbar style (set directly on field)
        scroll_view.scrollbar_style = phantom.Style.default().withFg(phantom.Color.bright_black);

        // Create border
        const border = try phantom.widgets.Border.init(allocator);
        border.setBorderStyle(.rounded);
        try border.setTitle(" Diagnostics ");
        border.setChild(&scroll_view.widget);
        border.border_color = phantom.Style.default().withFg(phantom.Color.bright_red);
        border.title_style = phantom.Style.default().withFg(phantom.Color.bright_yellow).withBold();

                self.* = .{
            .scroll_view = scroll_view,
            .border = border,
            .content_lines = .{
                .items = &.{},
                .capacity = 0,
            },
            .allocator = allocator,
            .visible = false,
        };

        return self;
    }

    pub fn deinit(self: *LSPDiagnosticsPanel) void {
        for (self.content_lines.items) |line| {
            self.allocator.free(line);
        }
        self.content_lines.deinit(self.allocator);
        self.border.widget.vtable.deinit(&self.border.widget);
        self.scroll_view.widget.vtable.deinit(&self.scroll_view.widget);
        self.allocator.destroy(self);
    }

    pub fn setDiagnostics(self: *LSPDiagnosticsPanel, diagnostics: []const Diagnostic) !void {
        // Clear old content
        for (self.content_lines.items) |line| {
            self.allocator.free(line);
        }
        self.content_lines.clearRetainingCapacity();

        // Group diagnostics by file
        var current_file: ?[]const u8 = null;
        var error_count: usize = 0;
        var warning_count: usize = 0;
        var info_count: usize = 0;
        var hint_count: usize = 0;

        for (diagnostics) |diag| {
            // Count by severity
            switch (diag.severity) {
                .error_sev => error_count += 1,
                .warning => warning_count += 1,
                .information => info_count += 1,
                .hint => hint_count += 1,
            }

            // File header (if changed)
            if (current_file == null or !std.mem.eql(u8, current_file.?, diag.source orelse "unknown")) {
                if (current_file != null) {
                    // Add separator
                    try self.content_lines.append(try self.allocator.dupe(u8, ""));
                }
                current_file = diag.source;
                const file_header = try std.fmt.allocPrint(
                    self.allocator,
                    "📄 {s}",
                    .{diag.source orelse "unknown"},
                );
                try self.content_lines.append(file_header);
            }

            // Diagnostic icon based on severity
            const icon = switch (diag.severity) {
                .error_sev => "󰅙",    // Error
                .warning => "",     // Warning
                .information => "", // Info
                .hint => "",        // Hint
            };

            // Format: icon line:col - message
            const diag_line = try std.fmt.allocPrint(
                self.allocator,
                "  {s} {}:{} - {s}",
                .{
                    icon,
                    diag.range.start.line + 1,
                    diag.range.start.character + 1,
                    diag.message,
                },
            );
            try self.content_lines.append(diag_line);

            // Add code if present
            if (diag.code) |code| {
                const code_line = try std.fmt.allocPrint(
                    self.allocator,
                    "    Code: {s}",
                    .{code},
                );
                try self.content_lines.append(code_line);
            }
        }

        // Update border title with counts
        const title = try std.fmt.allocPrint(
            self.allocator,
            " Diagnostics (E:{d} W:{d} I:{d} H:{d}) ",
            .{ error_count, warning_count, info_count, hint_count },
        );
        defer self.allocator.free(title);
        self.border.setTitle(title);

        // Build content for ScrollView
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        for (self.content_lines.items) |line| {
            try content.appendSlice(line);
            try content.append('\n');
        }

        try self.scroll_view.setContent(content.items);
        self.visible = diagnostics.len > 0;
    }

    pub fn scrollUp(self: *LSPDiagnosticsPanel) void {
        self.scroll_view.scrollUp();
    }

    pub fn scrollDown(self: *LSPDiagnosticsPanel) void {
        self.scroll_view.scrollDown();
    }

    pub fn scrollToTop(self: *LSPDiagnosticsPanel) void {
        self.scroll_view.scroll_offset = 0;
    }

    pub fn scrollToBottom(self: *LSPDiagnosticsPanel) void {
        if (self.content_lines.items.len > self.scroll_view.viewport_height) {
            self.scroll_view.scroll_offset = self.content_lines.items.len - self.scroll_view.viewport_height;
        }
    }

    pub fn scrollToDiagnostic(self: *LSPDiagnosticsPanel, index: usize) void {
        self.scroll_view.ensureLineVisible(index);
    }

    pub fn pageUp(self: *LSPDiagnosticsPanel) void {
        if (self.scroll_view.scroll_offset > self.scroll_view.viewport_height) {
            self.scroll_view.scroll_offset -= self.scroll_view.viewport_height;
        } else {
            self.scroll_view.scroll_offset = 0;
        }
    }

    pub fn pageDown(self: *LSPDiagnosticsPanel) void {
        const content_height = self.content_lines.items.len;
        if (self.scroll_view.scroll_offset + self.scroll_view.viewport_height < content_height) {
            self.scroll_view.scroll_offset += self.scroll_view.viewport_height;
        }
    }

    pub fn handleKeyEvent(self: *LSPDiagnosticsPanel, key: phantom.Key) bool {
        if (!self.visible) return false;

        return switch (key) {
            .up => {
                self.scrollUp();
                return true;
            },
            .down => {
                self.scrollDown();
                return true;
            },
            .char => |c| switch (c) {
                'k' => {
                    self.scrollUp();
                    return true;
                },
                'j' => {
                    self.scrollDown();
                    return true;
                },
                'g' => {
                    self.scrollToTop();
                    return true;
                },
                'G' => {
                    self.scrollToBottom();
                    return true;
                },
                else => false,
            },
            .page_up => {
                self.pageUp();
                return true;
            },
            .page_down => {
                self.pageDown();
                return true;
            },
            .home => {
                self.scrollToTop();
                return true;
            },
            .end => {
                self.scrollToBottom();
                return true;
            },
            else => false,
        };
    }

    pub fn hide(self: *LSPDiagnosticsPanel) void {
        self.visible = false;
    }

    pub fn show(self: *LSPDiagnosticsPanel) void {
        if (self.content_lines.items.len > 0) {
            self.visible = true;
        }
    }

    pub fn render(self: *LSPDiagnosticsPanel, buffer: anytype, area: phantom.Rect) void {
        if (!self.visible) return;
        self.border.widget.vtable.render(&self.border.widget, buffer, area);
    }
};

const std = @import("std");
const phantom = @import("phantom");

pub const LSPHoverWidget = struct {
    rich_text: *phantom.widgets.RichText,
    border: *phantom.widgets.Border,
    allocator: std.mem.Allocator,
    visible: bool,
    width: u16,
    height: u16,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !*LSPHoverWidget {
        const self = try allocator.create(LSPHoverWidget);

        // Create RichText widget
        const rich_text = try phantom.widgets.RichText.init(allocator);
        rich_text.word_wrap = true;  // Enable word wrapping
        rich_text.alignment = .left;

        // Create Border
        const border = try phantom.widgets.Border.init(allocator);
        border.setBorderStyle(.rounded);
        try border.setTitle(" Documentation ");
        border.setChild(&rich_text.widget);

        // Style border
        border.border_color = phantom.Style.default().withFg(phantom.Color.bright_cyan);
        border.title_style = phantom.Style.default().withFg(phantom.Color.bright_yellow).withBold();

        self.* = .{
            .rich_text = rich_text,
            .border = border,
            .allocator = allocator,
            .visible = false,
            .width = width,
            .height = height,
        };

        return self;
    }

    pub fn deinit(self: *LSPHoverWidget) void {
        self.border.widget.vtable.deinit(&self.border.widget);
        self.rich_text.widget.vtable.deinit(&self.rich_text.widget);
        self.allocator.destroy(self);
    }

    /// Set hover content from LSP hover response
    /// Supports markdown formatting from LSP
    pub fn setHoverContent(self: *LSPHoverWidget, content: []const u8) !void {
        // LSP hover responses often contain markdown
        // RichText.setMarkdown() will parse:
        // - **bold**
        // - *italic*
        // - `code`
        // - Headers (##)
        // - Lists
        try self.rich_text.setMarkdown(content);
        self.visible = content.len > 0;
    }

    /// Set hover content with custom styling
    pub fn setStyledContent(self: *LSPHoverWidget, spans: []const phantom.widgets.TextSpan) !void {
        try self.rich_text.setSpans(spans);
        self.visible = spans.len > 0;
    }

    /// Set plain text content
    pub fn setPlainText(self: *LSPHoverWidget, text: []const u8) !void {
        try self.rich_text.setText(text);
        self.visible = text.len > 0;
    }

    /// Update border title (e.g., function name, type)
    pub fn setTitle(self: *LSPHoverWidget, title: []const u8) void {
        self.border.setTitle(title);
    }

    pub fn hide(self: *LSPHoverWidget) void {
        self.visible = false;
    }

    pub fn show(self: *LSPHoverWidget) void {
        if (self.rich_text.text.items.len > 0) {
            self.visible = true;
        }
    }

    pub fn resize(self: *LSPHoverWidget, width: u16, height: u16) void {
        self.width = width;
        self.height = height;
    }

    pub fn render(self: *LSPHoverWidget, buffer: *phantom.Buffer, area: phantom.Rect) !void {
        if (!self.visible) return;

        // Render border (which contains rich_text)
        try self.border.widget.vtable.render(&self.border.widget, buffer, area);
    }
};

/// Helper to create hover widget from LSP Hover response
pub fn createFromLSPHover(
    allocator: std.mem.Allocator,
    hover_response: LSPHoverResponse,
    width: u16,
    height: u16,
) !*LSPHoverWidget {
    const widget = try LSPHoverWidget.init(allocator, width, height);

    // Parse hover content
    if (hover_response.contents) |contents| {
        switch (contents) {
            .markedString => |ms| {
                if (ms.language) |lang| {
                    // Code block
                    const code_content = try std.fmt.allocPrint(
                        allocator,
                        "```{s}\n{s}\n```",
                        .{ lang, ms.value },
                    );
                    defer allocator.free(code_content);
                    try widget.setHoverContent(code_content);
                } else {
                    try widget.setPlainText(ms.value);
                }
            },
            .markedStringArray => |arr| {
                var content = std.ArrayList(u8).init(allocator);
                defer content.deinit();

                for (arr) |ms| {
                    if (ms.language) |lang| {
                        try content.writer().print("```{s}\n{s}\n```\n\n", .{ lang, ms.value });
                    } else {
                        try content.writer().print("{s}\n\n", .{ms.value});
                    }
                }

                try widget.setHoverContent(content.items);
            },
            .markupContent => |mc| {
                if (std.mem.eql(u8, mc.kind, "markdown")) {
                    try widget.setHoverContent(mc.value);
                } else {
                    try widget.setPlainText(mc.value);
                }
            },
        }
    }

    return widget;
}

/// LSP Hover response types (simplified)
pub const LSPHoverResponse = struct {
    contents: ?HoverContents,
    range: ?struct {
        start: struct { line: u32, character: u32 },
        end: struct { line: u32, character: u32 },
    } = null,
};

pub const HoverContents = union(enum) {
    markedString: MarkedString,
    markedStringArray: []const MarkedString,
    markupContent: MarkupContent,
};

pub const MarkedString = struct {
    language: ?[]const u8 = null,
    value: []const u8,
};

pub const MarkupContent = struct {
    kind: []const u8,  // "plaintext" or "markdown"
    value: []const u8,
};

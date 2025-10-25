//! Ghost text rendering for inline AI completions
//! Renders completion suggestions in dim/gray text at cursor position

const std = @import("std");

/// Ghost text style
pub const GhostTextStyle = struct {
    foreground: u32 = 0x808080, // Gray
    italic: bool = true,
    dim: bool = true,
};

/// Ghost text instance
pub const GhostText = struct {
    text: []const u8,
    line: u32,
    column: u32,
    style: GhostTextStyle,
    visible: bool,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, text: []const u8, line: u32, column: u32) !GhostText {
        return .{
            .text = try allocator.dupe(u8, text),
            .line = line,
            .column = column,
            .style = GhostTextStyle{},
            .visible = true,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GhostText) void {
        self.allocator.free(self.text);
    }

    pub fn show(self: *GhostText) void {
        self.visible = true;
    }

    pub fn hide(self: *GhostText) void {
        self.visible = false;
    }

    pub fn setText(self: *GhostText, new_text: []const u8) !void {
        self.allocator.free(self.text);
        self.text = try self.allocator.dupe(u8, new_text);
    }
};

/// Ghost text renderer for TUI
pub const GhostTextRenderer = struct {
    allocator: std.mem.Allocator,
    current_ghost: ?GhostText,

    pub fn init(allocator: std.mem.Allocator) GhostTextRenderer {
        return .{
            .allocator = allocator,
            .current_ghost = null,
        };
    }

    pub fn deinit(self: *GhostTextRenderer) void {
        if (self.current_ghost) |*ghost| {
            ghost.deinit();
        }
    }

    /// Display ghost text at position
    pub fn showGhostText(self: *GhostTextRenderer, text: []const u8, line: u32, column: u32) !void {
        // Clear existing ghost text
        if (self.current_ghost) |*old| {
            old.deinit();
        }

        // Create new ghost text
        self.current_ghost = try GhostText.init(self.allocator, text, line, column);
    }

    /// Clear current ghost text
    pub fn clearGhostText(self: *GhostTextRenderer) void {
        if (self.current_ghost) |*ghost| {
            ghost.deinit();
            self.current_ghost = null;
        }
    }

    /// Get current ghost text for rendering
    pub fn getCurrentGhost(self: *const GhostTextRenderer) ?GhostText {
        return self.current_ghost;
    }

    /// Render ghost text to TUI buffer
    /// This is called by the TUI rendering loop
    pub fn render(self: *const GhostTextRenderer, writer: anytype, viewport_line: u32, viewport_col: u32) !void {
        if (self.current_ghost) |ghost| {
            if (!ghost.visible) return;

            // Only render if in viewport
            if (ghost.line != viewport_line or ghost.column < viewport_col) {
                return;
            }

            // Write ghost text with dim/italic style
            // Format: \x1b[2;3m{text}\x1b[0m
            // 2 = dim, 3 = italic

            const style_prefix = if (ghost.style.dim and ghost.style.italic)
                "\x1b[2;3m"
            else if (ghost.style.dim)
                "\x1b[2m"
            else if (ghost.style.italic)
                "\x1b[3m"
            else
                "";

            const style_suffix = "\x1b[0m"; // Reset

            try writer.writeAll(style_prefix);
            try writer.writeAll(ghost.text);
            try writer.writeAll(style_suffix);
        }
    }

    /// Render multi-line ghost text
    pub fn renderMultiLine(
        self: *const GhostTextRenderer,
        writer: anytype,
        start_line: u32,
        start_col: u32,
    ) !void {
        if (self.current_ghost) |ghost| {
            if (!ghost.visible) return;

            // Split text by newlines
            var lines = std.mem.split(u8, ghost.text, "\n");
            var line_idx: u32 = 0;

            while (lines.next()) |line| : (line_idx += 1) {
                const current_line = ghost.line + line_idx;

                // Only render if in viewport
                if (current_line < start_line) continue;

                // Calculate column (first line starts at ghost.column, rest at 0)
                const col = if (line_idx == 0) ghost.column else 0;
                if (col < start_col) continue;

                // Write with style
                try writer.writeAll("\x1b[2;3m"); // Dim + italic
                try writer.writeAll(line);
                try writer.writeAll("\x1b[0m"); // Reset

                if (lines.peek() != null) {
                    try writer.writeAll("\n");
                }
            }
        }
    }

    /// Check if ghost text should be shown at this position
    pub fn shouldShowAt(self: *const GhostTextRenderer, line: u32, column: u32) bool {
        if (self.current_ghost) |ghost| {
            return ghost.visible and ghost.line == line and ghost.column == column;
        }
        return false;
    }

    /// Update ghost text position (when cursor moves)
    pub fn updatePosition(self: *GhostTextRenderer, line: u32, column: u32) void {
        if (self.current_ghost) |*ghost| {
            ghost.line = line;
            ghost.column = column;
        }
    }
};

// Tests
test "ghost text creation" {
    var ghost = try GhostText.init(std.testing.allocator, "completion text", 10, 5);
    defer ghost.deinit();

    try std.testing.expectEqualStrings("completion text", ghost.text);
    try std.testing.expectEqual(@as(u32, 10), ghost.line);
    try std.testing.expectEqual(@as(u32, 5), ghost.column);
    try std.testing.expect(ghost.visible);
}

test "ghost text renderer" {
    var renderer = GhostTextRenderer.init(std.testing.allocator);
    defer renderer.deinit();

    try std.testing.expect(renderer.current_ghost == null);

    // Show ghost text
    try renderer.showGhostText("test completion", 5, 10);
    try std.testing.expect(renderer.current_ghost != null);

    // Clear ghost text
    renderer.clearGhostText();
    try std.testing.expect(renderer.current_ghost == null);
}

test "ghost text visibility" {
    var renderer = GhostTextRenderer.init(std.testing.allocator);
    defer renderer.deinit();

    try renderer.showGhostText("test", 1, 1);

    try std.testing.expect(renderer.shouldShowAt(1, 1));
    try std.testing.expect(!renderer.shouldShowAt(1, 2));
    try std.testing.expect(!renderer.shouldShowAt(2, 1));
}

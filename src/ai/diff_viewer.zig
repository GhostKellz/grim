//! Diff viewer for AI-suggested changes
//! Shows side-by-side or unified diff with accept/reject actions

const std = @import("std");

/// Diff change type
pub const ChangeType = enum {
    added,
    removed,
    modified,
    unchanged,

    pub fn toSymbol(self: ChangeType) u8 {
        return switch (self) {
            .added => '+',
            .removed => '-',
            .modified => '!',
            .unchanged => ' ',
        };
    }

    pub fn toColor(self: ChangeType) []const u8 {
        return switch (self) {
            .added => "\x1b[32m", // Green
            .removed => "\x1b[31m", // Red
            .modified => "\x1b[33m", // Yellow
            .unchanged => "\x1b[0m", // Reset
        };
    }
};

/// Single line in a diff hunk
pub const DiffLine = struct {
    change_type: ChangeType,
    old_line_no: ?u32 = null,
    new_line_no: ?u32 = null,
    content: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiffLine) void {
        self.allocator.free(self.content);
    }
};

/// A section of changes (hunk)
pub const DiffHunk = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
    lines: std.ArrayList(DiffLine),
    accepted: ?bool = null, // null = pending, true = accepted, false = rejected

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiffHunk {
        return .{
            .old_start = 0,
            .old_count = 0,
            .new_start = 0,
            .new_count = 0,
            .lines = std.ArrayList(DiffLine).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DiffHunk) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();
    }

    pub fn accept(self: *DiffHunk) void {
        self.accepted = true;
    }

    pub fn reject(self: *DiffHunk) void {
        self.accepted = false;
    }
};

/// Diff viewer state
pub const DiffViewer = struct {
    allocator: std.mem.Allocator,
    hunks: std.ArrayList(DiffHunk),
    current_hunk_idx: usize,
    file_path: []const u8,
    old_content: []const u8,
    new_content: []const u8,
    visible: bool,
    mode: DiffViewMode,

    pub const DiffViewMode = enum {
        unified, // Unified diff view
        side_by_side, // Split view
    };

    pub fn init(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        old_content: []const u8,
        new_content: []const u8,
    ) !DiffViewer {
        return .{
            .allocator = allocator,
            .hunks = std.ArrayList(DiffHunk).init(allocator),
            .current_hunk_idx = 0,
            .file_path = try allocator.dupe(u8, file_path),
            .old_content = try allocator.dupe(u8, old_content),
            .new_content = try allocator.dupe(u8, new_content),
            .visible = false,
            .mode = .unified,
        };
    }

    pub fn deinit(self: *DiffViewer) void {
        for (self.hunks.items) |*hunk| {
            hunk.deinit();
        }
        self.hunks.deinit();
        self.allocator.free(self.file_path);
        self.allocator.free(self.old_content);
        self.allocator.free(self.new_content);
    }

    /// Generate diff hunks from old and new content
    pub fn generateDiff(self: *DiffViewer) !void {
        // Clear existing hunks
        for (self.hunks.items) |*hunk| {
            hunk.deinit();
        }
        self.hunks.clearRetainingCapacity();

        // Split into lines
        var old_lines = std.mem.split(u8, self.old_content, "\n");
        var new_lines = std.mem.split(u8, self.new_content, "\n");

        var old_line_list = std.ArrayList([]const u8).init(self.allocator);
        defer old_line_list.deinit();
        var new_line_list = std.ArrayList([]const u8).init(self.allocator);
        defer new_line_list.deinit();

        while (old_lines.next()) |line| {
            try old_line_list.append(line);
        }
        while (new_lines.next()) |line| {
            try new_line_list.append(line);
        }

        // Simple line-by-line diff
        var hunk = DiffHunk.init(self.allocator);
        hunk.old_start = 1;
        hunk.new_start = 1;

        const max_lines = @max(old_line_list.items.len, new_line_list.items.len);

        for (0..max_lines) |i| {
            if (i < old_line_list.items.len and i < new_line_list.items.len) {
                const old_line = old_line_list.items[i];
                const new_line = new_line_list.items[i];

                if (std.mem.eql(u8, old_line, new_line)) {
                    // Unchanged
                    try hunk.lines.append(.{
                        .change_type = .unchanged,
                        .old_line_no = @intCast(i + 1),
                        .new_line_no = @intCast(i + 1),
                        .content = try self.allocator.dupe(u8, old_line),
                        .allocator = self.allocator,
                    });
                } else {
                    // Modified (show as removed + added)
                    try hunk.lines.append(.{
                        .change_type = .removed,
                        .old_line_no = @intCast(i + 1),
                        .content = try self.allocator.dupe(u8, old_line),
                        .allocator = self.allocator,
                    });
                    try hunk.lines.append(.{
                        .change_type = .added,
                        .new_line_no = @intCast(i + 1),
                        .content = try self.allocator.dupe(u8, new_line),
                        .allocator = self.allocator,
                    });
                }
            } else if (i < old_line_list.items.len) {
                // Line removed
                try hunk.lines.append(.{
                    .change_type = .removed,
                    .old_line_no = @intCast(i + 1),
                    .content = try self.allocator.dupe(u8, old_line_list.items[i]),
                    .allocator = self.allocator,
                });
            } else if (i < new_line_list.items.len) {
                // Line added
                try hunk.lines.append(.{
                    .change_type = .added,
                    .new_line_no = @intCast(i + 1),
                    .content = try self.allocator.dupe(u8, new_line_list.items[i]),
                    .allocator = self.allocator,
                });
            }
        }

        hunk.old_count = @intCast(old_line_list.items.len);
        hunk.new_count = @intCast(new_line_list.items.len);

        try self.hunks.append(hunk);
    }

    /// Show diff viewer
    pub fn show(self: *DiffViewer) !void {
        try self.generateDiff();
        self.visible = true;
        self.current_hunk_idx = 0;
    }

    /// Hide diff viewer
    pub fn hide(self: *DiffViewer) void {
        self.visible = false;
    }

    /// Navigate to next hunk
    pub fn nextHunk(self: *DiffViewer) void {
        if (self.current_hunk_idx < self.hunks.items.len - 1) {
            self.current_hunk_idx += 1;
        }
    }

    /// Navigate to previous hunk
    pub fn prevHunk(self: *DiffViewer) void {
        if (self.current_hunk_idx > 0) {
            self.current_hunk_idx -= 1;
        }
    }

    /// Accept current hunk
    pub fn acceptCurrentHunk(self: *DiffViewer) void {
        if (self.current_hunk_idx < self.hunks.items.len) {
            self.hunks.items[self.current_hunk_idx].accept();
        }
    }

    /// Reject current hunk
    pub fn rejectCurrentHunk(self: *DiffViewer) void {
        if (self.current_hunk_idx < self.hunks.items.len) {
            self.hunks.items[self.current_hunk_idx].reject();
        }
    }

    /// Accept all hunks
    pub fn acceptAll(self: *DiffViewer) void {
        for (self.hunks.items) |*hunk| {
            hunk.accept();
        }
    }

    /// Reject all hunks
    pub fn rejectAll(self: *DiffViewer) void {
        for (self.hunks.items) |*hunk| {
            hunk.reject();
        }
    }

    /// Apply accepted changes to buffer
    pub fn applyChanges(self: *DiffViewer) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        for (self.hunks.items) |hunk| {
            if (hunk.accepted == true) {
                // Apply new content
                for (hunk.lines.items) |line| {
                    if (line.change_type == .added or line.change_type == .unchanged) {
                        try result.appendSlice(line.content);
                        try result.append('\n');
                    }
                }
            } else {
                // Keep old content
                for (hunk.lines.items) |line| {
                    if (line.change_type == .removed or line.change_type == .unchanged) {
                        try result.appendSlice(line.content);
                        try result.append('\n');
                    }
                }
            }
        }

        return try result.toOwnedSlice();
    }

    /// Render unified diff view
    pub fn renderUnified(self: *const DiffViewer, writer: anytype, width: u32, height: u32) !void {
        if (!self.visible or self.hunks.items.len == 0) return;

        // Draw header
        try writer.writeAll("╭");
        try writer.writeByteNTimes('─', width - 2);
        try writer.writeAll("╮\n");

        const title = try std.fmt.allocPrint(
            self.allocator,
            "Diff: {s} (Hunk {d}/{d})",
            .{ self.file_path, self.current_hunk_idx + 1, self.hunks.items.len },
        );
        defer self.allocator.free(title);

        try writer.writeAll("│ ");
        try writer.writeAll(title);
        try writer.writeByteNTimes(' ', width - title.len - 4);
        try writer.writeAll("│\n");

        try writer.writeAll("├");
        try writer.writeByteNTimes('─', width - 2);
        try writer.writeAll("┤\n");

        // Render current hunk
        const hunk = self.hunks.items[self.current_hunk_idx];

        // Hunk header
        const hunk_header = try std.fmt.allocPrint(
            self.allocator,
            "@@ -{d},{d} +{d},{d} @@",
            .{ hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count },
        );
        defer self.allocator.free(hunk_header);

        try writer.writeAll("│ ");
        try writer.writeAll("\x1b[36m"); // Cyan
        try writer.writeAll(hunk_header);
        try writer.writeAll("\x1b[0m"); // Reset
        try writer.writeByteNTimes(' ', width - hunk_header.len - 4);
        try writer.writeAll("│\n");

        // Render lines (up to height limit)
        const max_lines = height - 8; // Leave space for header/footer
        const start_line = if (hunk.lines.items.len > max_lines)
            hunk.lines.items.len - max_lines
        else
            0;

        for (hunk.lines.items[start_line..]) |line| {
            try self.renderDiffLine(writer, line, width);
        }

        // Fill remaining space
        const rendered = hunk.lines.items.len - start_line;
        if (rendered < max_lines) {
            for (0..max_lines - rendered) |_| {
                try writer.writeAll("│");
                try writer.writeByteNTimes(' ', width - 2);
                try writer.writeAll("│\n");
            }
        }

        // Draw footer with status
        try writer.writeAll("├");
        try writer.writeByteNTimes('─', width - 2);
        try writer.writeAll("┤\n");

        const status = if (hunk.accepted == true)
            "✓ Accepted"
        else if (hunk.accepted == false)
            "✗ Rejected"
        else
            "? Pending";

        try writer.writeAll("│ Status: ");
        try writer.writeAll(status);
        try writer.writeByteNTimes(' ', width - status.len - 12);
        try writer.writeAll("│\n");

        try writer.writeAll("│ [a]ccept [r]eject [n]ext [p]rev [A]ccept all [R]eject all [q]uit");
        const padding = width - 68;
        if (padding > 0) {
            try writer.writeByteNTimes(' ', padding);
        }
        try writer.writeAll("│\n");

        try writer.writeAll("╰");
        try writer.writeByteNTimes('─', width - 2);
        try writer.writeAll("╯\n");
    }

    /// Render single diff line
    fn renderDiffLine(_: *const DiffViewer, writer: anytype, line: DiffLine, width: u32) !void {
        const symbol = line.change_type.toSymbol();
        const color = line.change_type.toColor();
        const reset = "\x1b[0m";

        // Format: "│ + line content    │"
        try writer.writeAll("│ ");
        try writer.writeAll(color);
        try writer.writeByte(symbol);
        try writer.writeByte(' ');

        const max_content = width - 6;
        const content = if (line.content.len > max_content)
            line.content[0..max_content]
        else
            line.content;

        try writer.writeAll(content);
        try writer.writeAll(reset);
        try writer.writeByteNTimes(' ', width - content.len - 6);
        try writer.writeAll("│\n");
    }
};

// Tests
test "diff hunk creation" {
    var hunk = DiffHunk.init(std.testing.allocator);
    defer hunk.deinit();

    try std.testing.expect(hunk.accepted == null);

    hunk.accept();
    try std.testing.expect(hunk.accepted == true);
}

test "diff viewer init" {
    const old = "line1\nline2\nline3";
    const new = "line1\nmodified\nline3";

    var viewer = try DiffViewer.init(std.testing.allocator, "test.zig", old, new);
    defer viewer.deinit();

    try std.testing.expect(!viewer.visible);
    try std.testing.expectEqual(@as(usize, 0), viewer.hunks.items.len);

    try viewer.generateDiff();
    try std.testing.expectEqual(@as(usize, 1), viewer.hunks.items.len);
}

test "diff navigation" {
    const old = "old";
    const new = "new";

    var viewer = try DiffViewer.init(std.testing.allocator, "test.zig", old, new);
    defer viewer.deinit();

    try viewer.show();
    try std.testing.expectEqual(@as(usize, 0), viewer.current_hunk_idx);

    viewer.nextHunk();
    try std.testing.expectEqual(@as(usize, 0), viewer.current_hunk_idx); // Can't go beyond last

    viewer.prevHunk();
    try std.testing.expectEqual(@as(usize, 0), viewer.current_hunk_idx); // Can't go below 0
}

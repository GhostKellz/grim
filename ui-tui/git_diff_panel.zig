//! Git diff panel

const std = @import("std");
const phantom = @import("phantom");

pub const DiffHunk = struct {
    start_line: usize,
    end_line: usize,
    diff_text: []const u8,

    pub fn deinit(self: *DiffHunk, allocator: std.mem.Allocator) void {
        allocator.free(self.diff_text);
    }
};

pub const GitDiffPanel = struct {
    allocator: std.mem.Allocator,
    hunks: std.ArrayList(DiffHunk),
    visible: bool,
    selected_hunk: usize,

    pub fn init(allocator: std.mem.Allocator) GitDiffPanel {
        return .{
            .allocator = allocator,
            .hunks = std.ArrayList(DiffHunk){},
            .visible = false,
            .selected_hunk = 0,
        };
    }

    pub fn deinit(self: *GitDiffPanel) void {
        for (self.hunks.items) |*hunk| {
            hunk.deinit(self.allocator);
        }
        self.hunks.deinit(self.allocator);
    }

    pub fn loadDiff(self: *GitDiffPanel, filepath: []const u8) !void {
        // Clear old data
        for (self.hunks.items) |*hunk| {
            hunk.deinit(self.allocator);
        }
        self.hunks.clearRetainingCapacity();

        // Run git diff
        var argv = [_][]const u8{ "git", "diff", filepath };
        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        defer _ = child.wait() catch {};

        const output = try child.stdout.?.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(output);

        // Parse hunks (simplified)
        var lines = std.mem.split(u8, output, "\n");
        var current_hunk_lines = std.ArrayList(u8){};
        defer current_hunk_lines.deinit(self.allocator);

        var in_hunk = false;
        var hunk_start: usize = 0;

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "@@")) {
                if (in_hunk) {
                    // Save previous hunk
                    const hunk = DiffHunk{
                        .start_line = hunk_start,
                        .end_line = hunk_start + 10,
                        .diff_text = try current_hunk_lines.toOwnedSlice(self.allocator),
                    };
                    try self.hunks.append(self.allocator, hunk);
                    current_hunk_lines = std.ArrayList(u8){};
                }
                in_hunk = true;
                // Parse line number
                hunk_start = 1;
            }

            if (in_hunk) {
                try current_hunk_lines.appendSlice(self.allocator, line);
                try current_hunk_lines.append(self.allocator, '\n');
            }
        }

        if (in_hunk and current_hunk_lines.items.len > 0) {
            const hunk = DiffHunk{
                .start_line = hunk_start,
                .end_line = hunk_start + 10,
                .diff_text = try current_hunk_lines.toOwnedSlice(self.allocator),
            };
            try self.hunks.append(self.allocator, hunk);
        }

        self.visible = true;
    }

    pub fn render(self: *GitDiffPanel, buffer: anytype, area: phantom.Rect) void {
        if (!self.visible) return;

        // Draw border
        const style = phantom.Style.default().withFg(phantom.Color.green);
        buffer.drawRect(area, style);
        buffer.writeText(area.x + 2, area.y, " Git Diff ", style);

        // Render hunks
        var y: u16 = area.y + 1;
        for (self.hunks.items) |*hunk| {
            if (y >= area.y + area.height - 1) break;
            var lines = std.mem.split(u8, hunk.diff_text, "\n");
            while (lines.next()) |line| {
                if (y >= area.y + area.height - 1) break;
                const line_style = if (std.mem.startsWith(u8, line, "+"))
                    phantom.Style.default().withFg(phantom.Color.green)
                else if (std.mem.startsWith(u8, line, "-"))
                    phantom.Style.default().withFg(phantom.Color.red)
                else
                    phantom.Style.default();

                const display = if (line.len > area.width - 2) line[0 .. area.width - 2] else line;
                buffer.writeText(area.x + 1, y, display, line_style);
                y += 1;
            }
        }
    }

    pub fn nextHunk(self: *GitDiffPanel) ?usize {
        if (self.hunks.items.len == 0) return null;
        self.selected_hunk = (self.selected_hunk + 1) % self.hunks.items.len;
        return self.hunks.items[self.selected_hunk].start_line;
    }

    pub fn prevHunk(self: *GitDiffPanel) ?usize {
        if (self.hunks.items.len == 0) return null;
        if (self.selected_hunk == 0) {
            self.selected_hunk = self.hunks.items.len - 1;
        } else {
            self.selected_hunk -= 1;
        }
        return self.hunks.items[self.selected_hunk].start_line;
    }
};

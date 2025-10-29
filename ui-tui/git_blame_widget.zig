//! Git blame widget - shows git blame inline

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");

pub const BlameInfo = struct {
    author: []const u8,
    timestamp: i64,
    commit_hash: []const u8,

    pub fn deinit(self: *BlameInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.author);
        allocator.free(self.commit_hash);
    }
};

pub const GitBlameWidget = struct {
    allocator: std.mem.Allocator,
    blame_lines: std.ArrayList(?BlameInfo),
    visible: bool,
    fade_timer: i64,

    pub fn init(allocator: std.mem.Allocator) GitBlameWidget {
        return .{
            .allocator = allocator,
            .blame_lines = std.ArrayList(?BlameInfo){},
            .visible = false,
            .fade_timer = 0,
        };
    }

    pub fn deinit(self: *GitBlameWidget) void {
        for (self.blame_lines.items) |*maybe_info| {
            if (maybe_info.*) |*info| {
                info.deinit(self.allocator);
            }
        }
        self.blame_lines.deinit(self.allocator);
    }

    pub fn loadBlame(self: *GitBlameWidget, filepath: []const u8) !void {
        // Clear old data
        for (self.blame_lines.items) |*maybe_info| {
            if (maybe_info.*) |*info| {
                info.deinit(self.allocator);
            }
        }
        self.blame_lines.clearRetainingCapacity();

        // Run git blame
        var argv = [_][]const u8{ "git", "blame", "--line-porcelain", filepath };
        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        defer _ = child.wait() catch {};

        const stdout = child.stdout.?.reader();
        var buf: [4096]u8 = undefined;

        var current_blame: ?BlameInfo = null;

        while (try stdout.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (std.mem.startsWith(u8, line, "author ")) {
                const author = line[7..];
                if (current_blame) |*blame| {
                    blame.author = try self.allocator.dupe(u8, author);
                }
            } else if (std.mem.startsWith(u8, line, "author-time ")) {
                const timestamp_str = line[12..];
                const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch 0;
                if (current_blame) |*blame| {
                    blame.timestamp = timestamp;
                }
            } else if (line.len >= 40 and std.mem.indexOfScalar(u8, line, ' ') == null) {
                // Commit hash line
                if (current_blame) |blame| {
                    try self.blame_lines.append(blame);
                }
                current_blame = BlameInfo{
                    .author = &.{},
                    .timestamp = 0,
                    .commit_hash = try self.allocator.dupe(u8, line[0..8]),
                };
            }
        }

        if (current_blame) |blame| {
            try self.blame_lines.append(blame);
        }

        self.visible = true;
        self.fade_timer = 3000; // 3 seconds
    }

    pub fn render(self: *GitBlameWidget, buffer: anytype, line: usize, x: u16, y: u16) void {
        if (!self.visible or self.fade_timer <= 0) return;
        if (line >= self.blame_lines.items.len) return;

        if (self.blame_lines.items[line]) |info| {
            var buf: [128]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, " \u{2022} {s} ", .{info.author}) catch return;
            const style = phantom.Style.default().withFg(phantom.Color.bright_black);
            buffer.writeText(x, y, text, style);
        }
    }

    pub fn update(self: *GitBlameWidget, delta_ms: i64) void {
        if (self.fade_timer > 0) {
            self.fade_timer -= delta_ms;
            if (self.fade_timer <= 0) {
                self.visible = false;
            }
        }
    }
};

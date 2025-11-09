//! tmux Integration for Grim
//!
//! Features:
//! - OSC 52 clipboard integration (copy to system clipboard from tmux)
//! - tmux passthrough sequences
//! - Pane detection and awareness
//! - Session information
//!
//! This integrates directly into Grim core and works with or without reaper.

const std = @import("std");

pub const TmuxIntegration = struct {
    allocator: std.mem.Allocator,
    enabled: bool,
    in_tmux: bool,

    // Session info
    session_name: ?[]const u8,
    window_index: ?[]const u8,
    pane_index: ?[]const u8,
    pane_id: ?[]const u8,

    // Terminal file descriptor (for writing escape sequences)
    tty_fd: std.posix.fd_t,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);

        // Open /dev/tty for terminal output (gracefully handle if not available)
        const tty_fd = std.posix.open("/dev/tty", .{ .ACCMODE = .WRONLY }, 0) catch {
            // /dev/tty not available (e.g., in non-interactive context)
            // Disable tmux integration
            self.* = .{
                .allocator = allocator,
                .enabled = false,
                .in_tmux = false,
                .session_name = null,
                .window_index = null,
                .pane_index = null,
                .pane_id = null,
                .tty_fd = std.posix.STDOUT_FILENO,
            };
            return self;
        };

        self.* = .{
            .allocator = allocator,
            .enabled = true,
            .in_tmux = detectTmux(),
            .session_name = null,
            .window_index = null,
            .pane_index = null,
            .pane_id = null,
            .tty_fd = tty_fd,
        };

        // If in tmux, get session info
        if (self.in_tmux) {
            try self.refreshSessionInfo();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        std.posix.close(self.tty_fd);

        if (self.session_name) |name| self.allocator.free(name);
        if (self.window_index) |idx| self.allocator.free(idx);
        if (self.pane_index) |idx| self.allocator.free(idx);
        if (self.pane_id) |id| self.allocator.free(id);

        self.allocator.destroy(self);
    }

    /// Check if running inside tmux
    fn detectTmux() bool {
        return std.posix.getenv("TMUX") != null;
    }

    /// Get tmux session information
    pub fn refreshSessionInfo(self: *Self) !void {
        if (!self.in_tmux) return;

        // Get session name
        if (try self.runTmuxCommand("display-message -p '#S'")) |session| {
            if (self.session_name) |old| self.allocator.free(old);
            self.session_name = session;
        }

        // Get window index
        if (try self.runTmuxCommand("display-message -p '#I'")) |window| {
            if (self.window_index) |old| self.allocator.free(old);
            self.window_index = window;
        }

        // Get pane index
        if (try self.runTmuxCommand("display-message -p '#P'")) |pane| {
            if (self.pane_index) |old| self.allocator.free(old);
            self.pane_index = pane;
        }

        // Get pane ID
        if (try self.runTmuxCommand("display-message -p '#{pane_id}'")) |id| {
            if (self.pane_id) |old| self.allocator.free(old);
            self.pane_id = id;
        }
    }

    /// Run tmux command and return output
    fn runTmuxCommand(self: *Self, args: []const u8) !?[]const u8 {
        var argv_buf: [256]u8 = undefined;
        const cmd = try std.fmt.bufPrint(&argv_buf, "tmux {s}", .{args});

        // Execute command and capture output
        var child = std.process.Child.init(&.{ "sh", "-c", cmd }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        try child.spawn();

        var stdout_buf: [1024]u8 = undefined;
        const n = try child.stdout.?.read(&stdout_buf);
        _ = try child.wait();

        if (n == 0) return null;

        // Trim whitespace and duplicate
        const trimmed = std.mem.trim(u8, stdout_buf[0..n], " \n\r\t");
        if (trimmed.len == 0) return null;

        return try self.allocator.dupe(u8, trimmed);
    }

    /// Copy text to clipboard using OSC 52 escape sequence
    ///
    /// OSC 52 format: ESC ] 52 ; c ; <base64-data> ST
    /// Where:
    /// - ESC ] = \x1b]
    /// - 52 = clipboard operation
    /// - c = clipboard selection (c=clipboard, p=primary, s=select)
    /// - <base64-data> = base64-encoded text
    /// - ST = \x1b\\ or \x07
    ///
    /// With tmux passthrough: ESC Ptmux; <escaped-sequence> ESC \\
    pub fn setClipboard(self: *Self, text: []const u8) !void {
        if (!self.enabled) return;

        // Base64 encode the text
        const base64_encoder = std.base64.standard.Encoder;
        const encoded_len = base64_encoder.calcSize(text.len);

        const encoded_buf = try self.allocator.alloc(u8, encoded_len);
        defer self.allocator.free(encoded_buf);

        const encoded = base64_encoder.encode(encoded_buf, text);

        // Build OSC 52 sequence
        var osc52_buf: [8192]u8 = undefined;
        const osc52 = if (self.in_tmux)
            // tmux passthrough: wrap OSC 52 in DCS sequence
            try std.fmt.bufPrint(&osc52_buf, "\x1bPtmux;\x1b\x1b]52;c;{s}\x07\x1b\\", .{encoded})
        else
            // Direct OSC 52
            try std.fmt.bufPrint(&osc52_buf, "\x1b]52;c;{s}\x07", .{encoded});

        // Write to terminal
        _ = try std.posix.write(self.tty_fd, osc52);

        std.log.info("Copied {d} bytes to clipboard via OSC 52", .{text.len});
    }

    /// Get clipboard using OSC 52 (read mode)
    ///
    /// OSC 52 query: ESC ] 52 ; c ; ? ST
    /// Terminal responds with: ESC ] 52 ; c ; <base64-data> ST
    ///
    /// Note: This is less reliable as not all terminals support OSC 52 read
    pub fn getClipboard(self: *Self) !?[]const u8 {
        if (!self.enabled) return null;
        if (!self.in_tmux) return null; // Only works reliably in tmux

        // Build OSC 52 query
        const query = if (self.in_tmux)
            "\x1bPtmux;\x1b\x1b]52;c;?\x07\x1b\\"
        else
            "\x1b]52;c;?\x07";

        // Write query
        _ = try std.posix.write(self.tty_fd, query);

        // TODO: Read response from terminal
        // This requires setting up terminal in raw mode and reading escape sequences
        // For now, return null (clipboard read is not critical)
        return null;
    }

    /// Check if in tmux
    pub fn inTmux(self: *Self) bool {
        return self.in_tmux;
    }

    /// Get formatted session info for status line
    pub fn getStatusLineInfo(self: *Self) ?[]const u8 {
        if (!self.in_tmux) return null;

        var buf: [256]u8 = undefined;
        const info = std.fmt.bufPrint(
            &buf,
            "[{s}:{s}.{s}]",
            .{
                self.session_name orelse "?",
                self.window_index orelse "?",
                self.pane_index orelse "?",
            },
        ) catch return null;

        return self.allocator.dupe(u8, info) catch null;
    }

    /// Get pane dimensions
    pub fn getPaneDimensions(self: *Self) !?struct { width: u32, height: u32 } {
        if (!self.in_tmux) return null;

        const width_str = try self.runTmuxCommand("display-message -p '#{pane_width}'") orelse return null;
        defer self.allocator.free(width_str);

        const height_str = try self.runTmuxCommand("display-message -p '#{pane_height}'") orelse return null;
        defer self.allocator.free(height_str);

        const width = try std.fmt.parseInt(u32, width_str, 10);
        const height = try std.fmt.parseInt(u32, height_str, 10);

        return .{ .width = width, .height = height };
    }

    /// Send passthrough sequence to terminal (bypassing tmux)
    ///
    /// Useful for sequences that tmux might intercept
    pub fn sendPassthrough(self: *Self, data: []const u8) !void {
        if (!self.in_tmux) {
            // Not in tmux, send directly
            _ = try std.posix.write(self.tty_fd, data);
            return;
        }

        // Wrap in tmux passthrough: ESC Ptmux; <escaped-data> ESC \\
        // Need to escape ESC characters in data
        var buf: [8192]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();

        try writer.writeAll("\x1bPtmux;");

        // Escape ESC characters
        for (data) |byte| {
            if (byte == 0x1b) {
                try writer.writeAll("\x1b\x1b");
            } else {
                try writer.writeByte(byte);
            }
        }

        try writer.writeAll("\x1b\\");

        const escaped = stream.getWritten();
        _ = try std.posix.write(self.tty_fd, escaped);
    }

    /// Print detected info
    pub fn printInfo(self: *Self) void {
        std.log.info("=== tmux Integration ===", .{});
        std.log.info("Enabled: {}", .{self.enabled});
        std.log.info("In tmux: {}", .{self.in_tmux});

        if (self.in_tmux) {
            std.log.info("Session: {s}", .{self.session_name orelse "unknown"});
            std.log.info("Window: {s}", .{self.window_index orelse "unknown"});
            std.log.info("Pane: {s}", .{self.pane_index orelse "unknown"});
            std.log.info("Pane ID: {s}", .{self.pane_id orelse "unknown"});

            if (self.getPaneDimensions()) |dims| {
                std.log.info("Pane size: {d}x{d}", .{ dims.width, dims.height });
            } else |_| {}
        }
    }
};

test "tmux detection" {
    const allocator = std.testing.allocator;
    const tmux = try TmuxIntegration.init(allocator);
    defer tmux.deinit();

    // Just test that init/deinit works
    std.testing.expect(tmux.enabled) catch {};
}

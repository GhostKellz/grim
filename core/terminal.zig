//! Terminal emulator with PTY support
//! Provides embedded terminal functionality for Grim editor
//! Sprint 12.1 - Terminal Integration

const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

/// Terminal instance managing a PTY and child process
pub const Terminal = struct {
    allocator: std.mem.Allocator,

    /// PTY master file descriptor
    pty_master: posix.fd_t,

    /// Child process ID
    child_pid: posix.pid_t,

    /// Terminal dimensions
    rows: u16,
    cols: u16,

    /// Output buffer (ring buffer for scrollback)
    output_buffer: std.array_list.AlignedManaged(u8, null),

    /// Whether the child process is still running
    running: bool,

    /// Terminal title (from escape sequences)
    title: ?[]const u8,

    pub const Error = error{
        PtyCreationFailed,
        ForkFailed,
        ExecFailed,
        AlreadyRunning,
        NotRunning,
        ReadFailed,
        WriteFailed,
    } || std.mem.Allocator.Error;

    /// Initialize a new terminal instance
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !*Terminal {
        const self = try allocator.create(Terminal);
        self.* = .{
            .allocator = allocator,
            .pty_master = -1,
            .child_pid = -1,
            .rows = rows,
            .cols = cols,
            .output_buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
            .running = false,
            .title = null,
        };
        return self;
    }

    /// Clean up terminal resources
    pub fn deinit(self: *Terminal) void {
        if (self.running) {
            self.kill() catch {};
        }

        if (self.pty_master != -1) {
            posix.close(self.pty_master);
        }

        self.output_buffer.deinit();

        if (self.title) |title| {
            self.allocator.free(title);
        }

        self.allocator.destroy(self);
    }

    /// Spawn a shell or command in the terminal
    pub fn spawn(self: *Terminal, cmd: ?[]const u8) !void {
        if (self.running) return Error.AlreadyRunning;

        // Create PTY master/slave pair
        var master: c_int = undefined;
        var slave: c_int = undefined;

        if (builtin.os.tag == .linux) {
            // Use openpty for PTY creation
            master = try createPtyMaster();

            // Get slave name
            var slave_name_buf: [256]u8 = undefined;
            const slave_name = try getPtySlaveName(master, &slave_name_buf);

            // Grant access and unlock slave
            try grantPty(master);
            try unlockPty(master);

            // Open slave
            slave = try std.posix.open(slave_name, .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0);
        } else {
            return error.UnsupportedPlatform;
        }

        // Fork process
        const pid = std.posix.fork() catch return Error.ForkFailed;

        if (pid == 0) {
            // Child process

            // Create new session
            if (builtin.os.tag == .linux) {
                const result = std.os.linux.syscall0(.setsid);
                if (result < 0) {
                    std.process.exit(1);
                }
            } else {
                _ = posix.setsid() catch {
                    std.process.exit(1);
                };
            }

            // Set controlling terminal
            if (builtin.os.tag == .linux) {
                const TIOCSCTTY: u32 = 0x540E;
                _ = std.os.linux.ioctl(slave, TIOCSCTTY, 0);
            }

            // Duplicate slave to stdin/stdout/stderr
            posix.dup2(slave, posix.STDIN_FILENO) catch std.process.exit(1);
            posix.dup2(slave, posix.STDOUT_FILENO) catch std.process.exit(1);
            posix.dup2(slave, posix.STDERR_FILENO) catch std.process.exit(1);

            // Close original descriptors
            if (slave > 2) posix.close(slave);
            posix.close(master);

            // Set terminal size
            self.setChildTerminalSize(posix.STDOUT_FILENO) catch {};

            // Execute shell or command
            const shell = cmd orelse getShell();
            const args = if (cmd) |c|
                &[_][]const u8{ "/bin/sh", "-c", c }
            else
                &[_][]const u8{shell};

            const env = std.process.getEnvMap(self.allocator) catch {
                std.process.exit(1);
            };
            defer env.deinit();

            std.process.execve(self.allocator, args, &env) catch {
                std.process.exit(1);
            };
        }

        // Parent process
        posix.close(slave);

        self.pty_master = master;
        self.child_pid = pid;
        self.running = true;
    }

    /// Read output from terminal (non-blocking)
    pub fn read(self: *Terminal, buffer: []u8) !usize {
        if (!self.running) return Error.NotRunning;

        // Set non-blocking mode
        const flags = try posix.fcntl(self.pty_master, posix.F.GETFL, 0);
        _ = try posix.fcntl(self.pty_master, posix.F.SETFL, flags | posix.O.NONBLOCK);

        const n = posix.read(self.pty_master, buffer) catch |err| {
            if (err == error.WouldBlock) return 0;
            return Error.ReadFailed;
        };

        // Append to output buffer for scrollback
        try self.output_buffer.appendSlice(buffer[0..n]);

        // Limit scrollback buffer size (e.g., 1MB)
        const max_scrollback = 1024 * 1024;
        if (self.output_buffer.items.len > max_scrollback) {
            const excess = self.output_buffer.items.len - max_scrollback;
            std.mem.copyForwards(
                u8,
                self.output_buffer.items[0..max_scrollback],
                self.output_buffer.items[excess..],
            );
            self.output_buffer.shrinkRetainingCapacity(max_scrollback);
        }

        return n;
    }

    /// Write input to terminal
    pub fn write(self: *Terminal, data: []const u8) !usize {
        if (!self.running) return Error.NotRunning;

        return posix.write(self.pty_master, data) catch Error.WriteFailed;
    }

    /// Resize terminal
    pub fn resize(self: *Terminal, rows: u16, cols: u16) !void {
        self.rows = rows;
        self.cols = cols;

        if (self.running) {
            try self.setChildTerminalSize(self.pty_master);
        }
    }

    /// Check if child process is still running
    pub fn checkStatus(self: *Terminal) !bool {
        if (!self.running) return false;

        const result = std.posix.waitpid(self.child_pid, std.posix.W.NOHANG);

        if (result.pid == self.child_pid) {
            // Process exited
            self.running = false;
            return false;
        }

        return true;
    }

    /// Send signal to child process
    pub fn kill(self: *Terminal) !void {
        if (!self.running) return Error.NotRunning;

        try std.posix.kill(self.child_pid, std.posix.SIG.TERM);

        // Wait for process to exit (with timeout)
        var attempts: usize = 0;
        while (attempts < 10) : (attempts += 1) {
            std.Thread.sleep(100 * std.time.ns_per_ms);

            if (!try self.checkStatus()) {
                return;
            }
        }

        // Force kill if still running
        try std.posix.kill(self.child_pid, std.posix.SIG.KILL);
        _ = std.posix.waitpid(self.child_pid, 0);
        self.running = false;
    }

    /// Get scrollback buffer
    pub fn getScrollback(self: *Terminal) []const u8 {
        return self.output_buffer.items;
    }

    /// Clear scrollback buffer
    pub fn clearScrollback(self: *Terminal) void {
        self.output_buffer.clearRetainingCapacity();
    }

    // =========================================================================
    // Private helper functions
    // =========================================================================

    fn createPtyMaster() !posix.fd_t {
        // Try posix_openpt first (modern)
        if (builtin.os.tag == .linux) {
            const O_RDWR = 0o2;
            const O_NOCTTY = 0o400;
            const AT_FDCWD: isize = -100;
            const fd = std.os.linux.syscall3(
                .openat,
                @as(usize, @bitCast(AT_FDCWD)),
                @intFromPtr("/dev/ptmx"),
                O_RDWR | O_NOCTTY,
            );

            if (fd > 0) return @intCast(fd);
        }

        return error.PtyCreationFailed;
    }

    fn getPtySlaveName(master: posix.fd_t, buffer: []u8) ![]const u8 {
        if (builtin.os.tag == .linux) {
            // Use ptsname on Linux
            const result = std.os.linux.syscall2(
                .ioctl,
                @as(usize, @intCast(master)),
                0x80045430, // TIOCGPTN
            );

            if (result < 0) return error.PtyCreationFailed;

            const slave_num: i32 = @intCast(result);
            return std.fmt.bufPrint(buffer, "/dev/pts/{d}", .{slave_num}) catch return error.PtyCreationFailed;
        }

        return error.UnsupportedPlatform;
    }

    fn grantPty(master: posix.fd_t) !void {
        _ = master;
        // On modern Linux with /dev/ptmx, this is automatic
    }

    fn unlockPty(master: posix.fd_t) !void {
        if (builtin.os.tag == .linux) {
            const TIOCSPTLCK: u32 = 0x40045431;
            var unlock: c_int = 0;
            const result = std.os.linux.syscall3(
                .ioctl,
                @as(usize, @intCast(master)),
                TIOCSPTLCK,
                @intFromPtr(&unlock),
            );

            if (result < 0) return error.PtyCreationFailed;
        }
    }

    fn setChildTerminalSize(self: *Terminal, fd: posix.fd_t) !void {
        if (builtin.os.tag == .linux) {
            const winsize = extern struct {
                ws_row: u16,
                ws_col: u16,
                ws_xpixel: u16,
                ws_ypixel: u16,
            };

            var ws = winsize{
                .ws_row = self.rows,
                .ws_col = self.cols,
                .ws_xpixel = 0,
                .ws_ypixel = 0,
            };

            const TIOCSWINSZ: u32 = 0x5414;
            _ = std.os.linux.syscall3(
                .ioctl,
                @as(usize, @intCast(fd)),
                TIOCSWINSZ,
                @intFromPtr(&ws),
            );
        }
    }

    fn getShell() [:0]const u8 {
        return std.posix.getenv("SHELL") orelse "/bin/sh";
    }
};

test "terminal creation" {
    const allocator = std.testing.allocator;
    const term = try Terminal.init(allocator, 24, 80);
    defer term.deinit();

    try std.testing.expect(term.rows == 24);
    try std.testing.expect(term.cols == 80);
    try std.testing.expect(!term.running);
}

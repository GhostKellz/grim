//! Cross-platform clipboard integration
//! Supports: Wayland (wl-clipboard), X11 (xclip/xsel), tmux (OSC 52)
//! Provides unified API for system clipboard access

const std = @import("std");
const tmux = @import("tmux.zig");
const platform = @import("platform.zig");

/// Clipboard provider type
pub const ClipboardProvider = enum {
    wayland_wl_copy,
    x11_xclip,
    x11_xsel,
    tmux_osc52,
    none,
};

/// Main clipboard interface
pub const Clipboard = struct {
    allocator: std.mem.Allocator,
    provider: ClipboardProvider,
    tmux_integration: ?*tmux.TmuxIntegration,

    pub fn init(allocator: std.mem.Allocator) !Clipboard {
        // Detect tmux first (highest priority for remote sessions)
        if (std.posix.getenv("TMUX")) |_| {
            const tmux_int = try tmux.TmuxIntegration.init(allocator);
            return Clipboard{
                .allocator = allocator,
                .provider = .tmux_osc52,
                .tmux_integration = tmux_int,
            };
        }

        // Detect platform capabilities
        var caps = try platform.PlatformCapabilities.detect(allocator);
        defer caps.deinit(allocator);

        // Prefer Wayland if available
        if (caps.has_wayland) {
            // Check if wl-copy/wl-paste are available
            if (try checkCommandExists("wl-copy")) {
                return Clipboard{
                    .allocator = allocator,
                    .provider = .wayland_wl_copy,
                    .tmux_integration = null,
                };
            }
        }

        // Try X11 tools
        if (caps.has_x11) {
            if (try checkCommandExists("xclip")) {
                return Clipboard{
                    .allocator = allocator,
                    .provider = .x11_xclip,
                    .tmux_integration = null,
                };
            }
            if (try checkCommandExists("xsel")) {
                return Clipboard{
                    .allocator = allocator,
                    .provider = .x11_xsel,
                    .tmux_integration = null,
                };
            }
        }

        // No clipboard available
        return Clipboard{
            .allocator = allocator,
            .provider = .none,
            .tmux_integration = null,
        };
    }

    pub fn deinit(self: *Clipboard) void {
        if (self.tmux_integration) |tmux_int| {
            tmux_int.deinit();
        }
    }

    /// Copy text to system clipboard
    pub fn copy(self: *Clipboard, text: []const u8) !void {
        switch (self.provider) {
            .wayland_wl_copy => try self.copyWayland(text),
            .x11_xclip => try self.copyXClip(text),
            .x11_xsel => try self.copyXSel(text),
            .tmux_osc52 => {
                if (self.tmux_integration) |tmux_int| {
                    try tmux_int.setClipboard(text);
                }
            },
            .none => return error.ClipboardNotAvailable,
        }
    }

    /// Paste text from system clipboard
    pub fn paste(self: *Clipboard) ![]u8 {
        switch (self.provider) {
            .wayland_wl_copy => return try self.pasteWayland(),
            .x11_xclip => return try self.pasteXClip(),
            .x11_xsel => return try self.pasteXSel(),
            .tmux_osc52 => {
                // tmux OSC 52 doesn't support paste, fallback to primary selection
                if (try checkCommandExists("wl-paste")) {
                    return try self.pasteWayland();
                }
                if (try checkCommandExists("xclip")) {
                    return try self.pasteXClip();
                }
                return error.ClipboardPasteNotSupported;
            },
            .none => return error.ClipboardNotAvailable,
        }
    }

    // === Wayland implementation ===

    fn copyWayland(self: *Clipboard, text: []const u8) !void {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "wl-copy", "--" },
            .max_output_bytes = 0,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        // Write to stdin
        var child = std.process.Child.init(&[_][]const u8{ "wl-copy", "--" }, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        if (child.stdin) |stdin| {
            try stdin.writeAll(text);
            stdin.close();
            child.stdin = null;
        }
        _ = try child.wait();
    }

    fn pasteWayland(self: *Clipboard) ![]u8 {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "wl-paste", "--no-newline" },
        });
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            return result.stdout;
        }

        self.allocator.free(result.stdout);
        return error.ClipboardPasteFailed;
    }

    // === X11 xclip implementation ===

    fn copyXClip(self: *Clipboard, text: []const u8) !void {
        var child = std.process.Child.init(&[_][]const u8{ "xclip", "-selection", "clipboard" }, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        if (child.stdin) |stdin| {
            try stdin.writeAll(text);
            stdin.close();
            child.stdin = null;
        }
        _ = try child.wait();
    }

    fn pasteXClip(self: *Clipboard) ![]u8 {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "xclip", "-selection", "clipboard", "-o" },
        });
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            return result.stdout;
        }

        self.allocator.free(result.stdout);
        return error.ClipboardPasteFailed;
    }

    // === X11 xsel implementation ===

    fn copyXSel(self: *Clipboard, text: []const u8) !void {
        var child = std.process.Child.init(&[_][]const u8{ "xsel", "--clipboard", "--input" }, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        if (child.stdin) |stdin| {
            try stdin.writeAll(text);
            stdin.close();
            child.stdin = null;
        }
        _ = try child.wait();
    }

    fn pasteXSel(self: *Clipboard) ![]u8 {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "xsel", "--clipboard", "--output" },
        });
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            return result.stdout;
        }

        self.allocator.free(result.stdout);
        return error.ClipboardPasteFailed;
    }
};

/// Check if a command exists in PATH
fn checkCommandExists(command: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "which", command },
        .max_output_bytes = 1024,
    }) catch return false;

    return result.term.Exited == 0;
}

test "clipboard initialization" {
    const allocator = std.testing.allocator;
    var clipboard = try Clipboard.init(allocator);
    defer clipboard.deinit();

    std.debug.print("Clipboard provider: {}\n", .{clipboard.provider});
}

test "clipboard copy/paste round-trip" {
    const allocator = std.testing.allocator;
    var clipboard = try Clipboard.init(allocator);
    defer clipboard.deinit();

    if (clipboard.provider == .none) {
        std.debug.print("No clipboard provider available, skipping test\n", .{});
        return error.SkipZigTest;
    }

    const test_text = "Hello from Grim clipboard test!";
    try clipboard.copy(test_text);

    // Note: clipboard operations happen synchronously via child processes
    // No sleep needed - the process.Child.wait() ensures completion

    const pasted = try clipboard.paste();
    defer allocator.free(pasted);

    try std.testing.expectEqualStrings(test_text, pasted);
}

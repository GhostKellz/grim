//! Auto-save session management
//! Automatically saves workspace state at regular intervals

const std = @import("std");
const buffer_sessions = @import("buffer_sessions.zig");
const buffer_manager = @import("buffer_manager.zig");

pub const AutoSaveSession = struct {
    sessions: *buffer_sessions.BufferSessions,
    buffer_mgr: *buffer_manager.BufferManager,
    auto_save_enabled: bool,
    auto_save_interval_ms: u64,
    last_save_time: i64,
    session_name: []const u8,
    allocator: std.mem.Allocator,

    pub const DEFAULT_AUTO_SAVE_INTERVAL_MS: u64 = 30_000; // 30 seconds
    pub const AUTO_SESSION_NAME = "auto_save";

    pub fn init(
        allocator: std.mem.Allocator,
        sessions: *buffer_sessions.BufferSessions,
        buffer_mgr: *buffer_manager.BufferManager,
    ) !*AutoSaveSession {
        const self = try allocator.create(AutoSaveSession);
        self.* = .{
            .sessions = sessions,
            .buffer_mgr = buffer_mgr,
            .auto_save_enabled = true,
            .auto_save_interval_ms = DEFAULT_AUTO_SAVE_INTERVAL_MS,
            .last_save_time = 0,
            .session_name = try allocator.dupe(u8, AUTO_SESSION_NAME),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *AutoSaveSession) void {
        self.allocator.free(self.session_name);
        self.allocator.destroy(self);
    }

    /// Enable auto-save with custom interval
    pub fn enable(self: *AutoSaveSession, interval_ms: ?u64) void {
        self.auto_save_enabled = true;
        if (interval_ms) |interval| {
            self.auto_save_interval_ms = interval;
        }
    }

    /// Disable auto-save
    pub fn disable(self: *AutoSaveSession) void {
        self.auto_save_enabled = false;
    }

    /// Check if it's time to auto-save and perform save if needed
    pub fn tick(self: *AutoSaveSession) !bool {
        if (!self.auto_save_enabled) return false;

        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_save_time;

        if (elapsed >= self.auto_save_interval_ms) {
            try self.save();
            return true;
        }

        return false;
    }

    /// Manually trigger an auto-save
    pub fn save(self: *AutoSaveSession) !void {
        try self.sessions.saveSession(self.session_name, self.buffer_mgr);
        self.last_save_time = std.time.milliTimestamp();
    }

    /// Restore from auto-saved session
    pub fn restore(self: *AutoSaveSession) !void {
        try self.sessions.loadSession(self.session_name, self.buffer_mgr);
    }

    /// Check if auto-save session exists
    pub fn hasAutoSave(self: *AutoSaveSession) bool {
        const info = self.sessions.getSessionInfo(self.session_name) catch return false;
        self.allocator.free(info.name);
        return true;
    }

    /// Delete auto-save session
    pub fn clearAutoSave(self: *AutoSaveSession) !void {
        try self.sessions.deleteSession(self.session_name);
    }

    /// Get time since last save in milliseconds
    pub fn timeSinceLastSave(self: *AutoSaveSession) i64 {
        return std.time.milliTimestamp() - self.last_save_time;
    }

    /// Set custom session name for auto-save
    pub fn setSessionName(self: *AutoSaveSession, name: []const u8) !void {
        self.allocator.free(self.session_name);
        self.session_name = try self.allocator.dupe(u8, name);
    }
};

test "AutoSaveSession init and deinit" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var sessions = try buffer_sessions.BufferSessions.init(allocator);
    defer sessions.deinit();

    const auto_save = try AutoSaveSession.init(allocator, &sessions, &buffer_mgr);
    defer auto_save.deinit();

    try std.testing.expect(auto_save.auto_save_enabled);
}

test "AutoSaveSession enable/disable" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var sessions = try buffer_sessions.BufferSessions.init(allocator);
    defer sessions.deinit();

    const auto_save = try AutoSaveSession.init(allocator, &sessions, &buffer_mgr);
    defer auto_save.deinit();

    auto_save.enable(60_000); // 1 minute
    try std.testing.expect(auto_save.auto_save_enabled);
    try std.testing.expectEqual(@as(u64, 60_000), auto_save.auto_save_interval_ms);

    auto_save.disable();
    try std.testing.expect(!auto_save.auto_save_enabled);
}

test "AutoSaveSession save and restore" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var sessions = try buffer_sessions.BufferSessions.init(allocator);
    defer sessions.deinit();

    const auto_save = try AutoSaveSession.init(allocator, &sessions, &buffer_mgr);
    defer auto_save.deinit();

    // Save
    try auto_save.save();
    try std.testing.expect(auto_save.hasAutoSave());

    // Clean up
    try auto_save.clearAutoSave();
    try std.testing.expect(!auto_save.hasAutoSave());
}

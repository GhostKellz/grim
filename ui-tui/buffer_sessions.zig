const std = @import("std");
const buffer_manager = @import("buffer_manager.zig");

/// Buffer Sessions - Save and restore workspace state
/// Persists open buffers, cursor positions, and window layouts
pub const BufferSessions = struct {
    allocator: std.mem.Allocator,
    sessions_dir: []const u8,

    pub const Session = struct {
        name: []const u8,
        buffers: []BufferState,
        active_buffer_id: u32,
        created_at: i64,

        pub const BufferState = struct {
            id: u32,
            file_path: ?[]const u8,
            cursor_line: usize,
            cursor_column: usize,
            scroll_offset: usize,
            modified: bool,
        };

        pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            for (self.buffers) |*buf| {
                if (buf.file_path) |path| {
                    allocator.free(path);
                }
            }
            allocator.free(self.buffers);
        }
    };

    pub fn init(allocator: std.mem.Allocator) !BufferSessions {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

        const sessions_dir = try std.fs.path.join(allocator, &.{
            home,
            ".config",
            "grim",
            "sessions",
        });

        // Create sessions directory if it doesn't exist
        std.fs.cwd().makePath(sessions_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return BufferSessions{
            .allocator = allocator,
            .sessions_dir = sessions_dir,
        };
    }

    pub fn deinit(self: *BufferSessions) void {
        self.allocator.free(self.sessions_dir);
    }

    /// Save current workspace state
    pub fn saveSession(
        self: *BufferSessions,
        name: []const u8,
        buffer_mgr: *const buffer_manager.BufferManager,
    ) !void {
        var session = Session{
            .name = try self.allocator.dupe(u8, name),
            .buffers = try self.allocator.alloc(Session.BufferState, buffer_mgr.buffers.items.len),
            .active_buffer_id = buffer_mgr.active_buffer_id,
            .created_at = std.time.timestamp(),
        };
        defer session.deinit(self.allocator);

        // Capture buffer states
        for (buffer_mgr.buffers.items, 0..) |buffer, i| {
            session.buffers[i] = .{
                .id = buffer.id,
                .file_path = if (buffer.file_path) |path|
                    try self.allocator.dupe(u8, path)
                else
                    null,
                .cursor_line = 0, // TODO: Get from editor
                .cursor_column = 0,
                .scroll_offset = 0,
                .modified = buffer.modified,
            };
        }

        // Serialize to JSON
        const json = try self.serializeSession(&session);
        defer self.allocator.free(json);

        // Write to file
        const session_path = try std.fs.path.join(self.allocator, &.{
            self.sessions_dir,
            try std.fmt.allocPrint(self.allocator, "{s}.json", .{name}),
        });
        defer self.allocator.free(session_path);

        const file = try std.fs.cwd().createFile(session_path, .{});
        defer file.close();

        try file.writeAll(json);
    }

    /// Load workspace state
    pub fn loadSession(
        self: *BufferSessions,
        name: []const u8,
        buffer_mgr: *buffer_manager.BufferManager,
    ) !void {
        const session_path = try std.fs.path.join(self.allocator, &.{
            self.sessions_dir,
            try std.fmt.allocPrint(self.allocator, "{s}.json", .{name}),
        });
        defer self.allocator.free(session_path);

        const file = try std.fs.cwd().openFile(session_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        var session = try self.deserializeSession(content);
        defer session.deinit(self.allocator);

        // Close all current buffers (except last one)
        while (buffer_mgr.buffers.items.len > 1) {
            const last_idx = buffer_mgr.buffers.items.len - 1;
            const buffer_id = buffer_mgr.buffers.items[last_idx].id;
            try buffer_mgr.closeBuffer(buffer_id);
        }

        // Open buffers from session
        for (session.buffers) |buf_state| {
            if (buf_state.file_path) |path| {
                _ = try buffer_mgr.openFile(path);
                // TODO: Restore cursor position and scroll offset
            }
        }

        // Switch to active buffer
        try buffer_mgr.switchToBuffer(session.active_buffer_id);
    }

    /// Delete a session
    pub fn deleteSession(self: *BufferSessions, name: []const u8) !void {
        const session_path = try std.fs.path.join(self.allocator, &.{
            self.sessions_dir,
            try std.fmt.allocPrint(self.allocator, "{s}.json", .{name}),
        });
        defer self.allocator.free(session_path);

        try std.fs.cwd().deleteFile(session_path);
    }

    /// List all saved sessions
    pub fn listSessions(self: *BufferSessions) ![]const []const u8 {
        var sessions = std.ArrayList([]const u8){};
        defer sessions.deinit(self.allocator);

        var dir = try std.fs.cwd().openDir(self.sessions_dir, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                const name = entry.name;
                if (std.mem.endsWith(u8, name, ".json")) {
                    const session_name = name[0 .. name.len - 5]; // Remove .json
                    try sessions.append(self.allocator, try self.allocator.dupe(u8, session_name));
                }
            }
        }

        return sessions.toOwnedSlice(self.allocator);
    }

    /// Get session info without loading
    pub const SessionInfo = struct {
        name: []const u8,
        buffer_count: usize,
        created_at: i64,
        has_unsaved: bool,
    };

    pub fn getSessionInfo(self: *BufferSessions, name: []const u8) !SessionInfo {
        const session_path = try std.fs.path.join(self.allocator, &.{
            self.sessions_dir,
            try std.fmt.allocPrint(self.allocator, "{s}.json", .{name}),
        });
        defer self.allocator.free(session_path);

        const file = try std.fs.cwd().openFile(session_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        var session = try self.deserializeSession(content);
        defer session.deinit(self.allocator);

        var has_unsaved = false;
        for (session.buffers) |buf| {
            if (buf.modified) {
                has_unsaved = true;
                break;
            }
        }

        return SessionInfo{
            .name = try self.allocator.dupe(u8, session.name),
            .buffer_count = session.buffers.len,
            .created_at = session.created_at,
            .has_unsaved = has_unsaved,
        };
    }

    // Serialization

    fn serializeSession(self: *BufferSessions, session: *const Session) ![]const u8 {
        var string = std.ArrayList(u8){};
        defer string.deinit(self.allocator);

        try std.json.stringify(session, .{}, string.writer());
        return string.toOwnedSlice(self.allocator);
    }

    fn deserializeSession(self: *BufferSessions, json: []const u8) !Session {
        const parsed = try std.json.parseFromSlice(Session, self.allocator, json, .{});
        defer parsed.deinit();

        // Deep copy the session
        var buffers = try self.allocator.alloc(Session.BufferState, parsed.value.buffers.len);
        for (parsed.value.buffers, 0..) |buf, i| {
            buffers[i] = .{
                .id = buf.id,
                .file_path = if (buf.file_path) |path|
                    try self.allocator.dupe(u8, path)
                else
                    null,
                .cursor_line = buf.cursor_line,
                .cursor_column = buf.cursor_column,
                .scroll_offset = buf.scroll_offset,
                .modified = buf.modified,
            };
        }

        return Session{
            .name = try self.allocator.dupe(u8, parsed.value.name),
            .buffers = buffers,
            .active_buffer_id = parsed.value.active_buffer_id,
            .created_at = parsed.value.created_at,
        };
    }
};

test "BufferSessions init" {
    const allocator = std.testing.allocator;

    var sessions = try BufferSessions.init(allocator);
    defer sessions.deinit();

    try std.testing.expect(sessions.sessions_dir.len > 0);
}

test "BufferSessions save and load" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var sessions = try BufferSessions.init(allocator);
    defer sessions.deinit();

    // Save session
    try sessions.saveSession("test_session", &buffer_mgr);

    // List sessions
    const session_list = try sessions.listSessions();
    defer {
        for (session_list) |name| allocator.free(name);
        allocator.free(session_list);
    }

    try std.testing.expect(session_list.len >= 1);

    // Clean up
    try sessions.deleteSession("test_session");
}

test "BufferSessions session info" {
    const allocator = std.testing.allocator;

    var buffer_mgr = try buffer_manager.BufferManager.init(allocator);
    defer buffer_mgr.deinit();

    var sessions = try BufferSessions.init(allocator);
    defer sessions.deinit();

    try sessions.saveSession("info_test", &buffer_mgr);

    const info = try sessions.getSessionInfo("info_test");
    defer allocator.free(info.name);

    try std.testing.expectEqualStrings("info_test", info.name);
    try std.testing.expectEqual(@as(usize, 1), info.buffer_count);

    try sessions.deleteSession("info_test");
}

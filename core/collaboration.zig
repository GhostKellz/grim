//! Collaborative Editing Infrastructure
//! Sprint 13 - Real-time Multi-User Editing
//! Foundation for WebSocket-based collaboration with Operational Transform

const std = @import("std");

/// Operation type for collaborative editing
pub const OperationType = enum {
    insert,
    delete,
    cursor_move,
    user_join,
    user_leave,
};

/// A single edit operation
pub const Operation = struct {
    op_type: OperationType,
    position: usize,
    content: ?[]const u8 = null,
    user_id: []const u8,
    version: u64,
    timestamp: i64,

    pub fn init(allocator: std.mem.Allocator, op_type: OperationType, position: usize, user_id: []const u8, version: u64) !Operation {
        return Operation{
            .op_type = op_type,
            .position = position,
            .content = null,
            .user_id = try allocator.dupe(u8, user_id),
            .version = version,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Operation, allocator: std.mem.Allocator) void {
        allocator.free(self.user_id);
        if (self.content) |content| {
            allocator.free(content);
        }
    }

    /// Set content for insert/delete operations
    pub fn setContent(self: *Operation, allocator: std.mem.Allocator, content: []const u8) !void {
        if (self.content) |old_content| {
            allocator.free(old_content);
        }
        self.content = try allocator.dupe(u8, content);
    }
};

/// User presence information
pub const UserPresence = struct {
    user_id: []const u8,
    display_name: []const u8,
    cursor_position: usize,
    selection_start: ?usize = null,
    selection_end: ?usize = null,
    buffer_path: ?[]const u8 = null,
    last_seen: i64,

    pub fn init(allocator: std.mem.Allocator, user_id: []const u8, display_name: []const u8) !UserPresence {
        return UserPresence{
            .user_id = try allocator.dupe(u8, user_id),
            .display_name = try allocator.dupe(u8, display_name),
            .cursor_position = 0,
            .last_seen = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *UserPresence, allocator: std.mem.Allocator) void {
        allocator.free(self.user_id);
        allocator.free(self.display_name);
        if (self.buffer_path) |path| {
            allocator.free(path);
        }
    }

    pub fn updateCursor(self: *UserPresence, position: usize) void {
        self.cursor_position = position;
        self.last_seen = std.time.timestamp();
    }

    pub fn updateSelection(self: *UserPresence, start: usize, end: usize) void {
        self.selection_start = start;
        self.selection_end = end;
        self.last_seen = std.time.timestamp();
    }
};

/// Collaboration session
pub const CollaborationSession = struct {
    allocator: std.mem.Allocator,
    session_id: []const u8,
    local_user_id: []const u8,
    users: std.ArrayList(UserPresence),
    operation_log: std.ArrayList(Operation),
    current_version: u64 = 0,
    connected: bool = false,

    pub const Error = error{
        NotConnected,
        InvalidOperation,
        UserNotFound,
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator, session_id: []const u8, user_id: []const u8) !*CollaborationSession {
        const self = try allocator.create(CollaborationSession);
        self.* = .{
            .allocator = allocator,
            .session_id = try allocator.dupe(u8, session_id),
            .local_user_id = try allocator.dupe(u8, user_id),
            .users = std.ArrayList(UserPresence).init(allocator),
            .operation_log = std.ArrayList(Operation).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *CollaborationSession) void {
        for (self.users.items) |*user| {
            user.deinit(self.allocator);
        }
        self.users.deinit(self.allocator);

        for (self.operation_log.items) |*op| {
            op.deinit(self.allocator);
        }
        self.operation_log.deinit(self.allocator);

        self.allocator.free(self.session_id);
        self.allocator.free(self.local_user_id);
        self.allocator.destroy(self);
    }

    /// Add a user to the session
    pub fn addUser(self: *CollaborationSession, user_id: []const u8, display_name: []const u8) !void {
        const user = try UserPresence.init(self.allocator, user_id, display_name);
        try self.users.append(self.allocator, user);
    }

    /// Remove a user from the session
    pub fn removeUser(self: *CollaborationSession, user_id: []const u8) !void {
        var i: usize = 0;
        while (i < self.users.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.users.items[i].user_id, user_id)) {
                var user = self.users.orderedRemove(i);
                user.deinit(self.allocator);
                return;
            }
        }
        return Error.UserNotFound;
    }

    /// Record an operation
    pub fn recordOperation(self: *CollaborationSession, op: Operation) !void {
        self.current_version += 1;
        try self.operation_log.append(self.allocator, op);
    }

    /// Get user by ID
    pub fn getUser(self: *CollaborationSession, user_id: []const u8) ?*UserPresence {
        for (self.users.items) |*user| {
            if (std.mem.eql(u8, user.user_id, user_id)) {
                return user;
            }
        }
        return null;
    }

    /// Connect to collaboration session
    pub fn connect(self: *CollaborationSession) !void {
        // TODO: WebSocket connection implementation
        self.connected = true;
    }

    /// Disconnect from session
    pub fn disconnect(self: *CollaborationSession) void {
        // TODO: WebSocket disconnection
        self.connected = false;
    }

    /// Send operation to other users
    pub fn broadcastOperation(self: *CollaborationSession, op: *const Operation) !void {
        if (!self.connected) return Error.NotConnected;
        // TODO: WebSocket broadcast implementation
        _ = op;
    }
};

/// Operational Transform (OT) - Basic implementation
pub const OT = struct {
    /// Transform two concurrent operations
    /// Returns transformed versions: (op1', op2')
    pub fn transform(op1: *Operation, op2: *Operation) !void {
        // Simple OT transformation rules
        if (op1.op_type == .insert and op2.op_type == .insert) {
            if (op1.position < op2.position) {
                // op1 comes before op2, adjust op2 position
                if (op1.content) |content| {
                    op2.position += content.len;
                }
            } else if (op2.position < op1.position) {
                // op2 comes before op1, adjust op1 position
                if (op2.content) |content| {
                    op1.position += content.len;
                }
            }
            // If same position, keep original order (will be resolved by timestamp)
        } else if (op1.op_type == .delete and op2.op_type == .delete) {
            // Both deletes at same position - second one is no-op
            if (op1.position == op2.position) {
                // Mark op2 as redundant (TODO: add flag)
            }
        } else if (op1.op_type == .insert and op2.op_type == .delete) {
            // Insert vs delete transformation
            if (op1.position <= op2.position) {
                if (op1.content) |content| {
                    op2.position += content.len;
                }
            }
        } else if (op1.op_type == .delete and op2.op_type == .insert) {
            // Delete vs insert transformation
            if (op2.position <= op1.position) {
                if (op2.content) |content| {
                    op1.position += content.len;
                }
            }
        }
    }
};

test "operation creation" {
    const allocator = std.testing.allocator;
    var op = try Operation.init(allocator, .insert, 10, "user1", 1);
    defer op.deinit(allocator);

    try op.setContent(allocator, "hello");
    try std.testing.expectEqualStrings("user1", op.user_id);
    try std.testing.expect(op.position == 10);
}

test "collaboration session" {
    const allocator = std.testing.allocator;
    const session = try CollaborationSession.init(allocator, "session1", "user1");
    defer session.deinit();

    try session.addUser("user2", "Bob");
    try std.testing.expect(session.users.items.len == 1);

    const user = session.getUser("user2");
    try std.testing.expect(user != null);
}

//! Collaborative Editing Infrastructure
//! Sprint 13 - Real-time Multi-User Editing
//! Foundation for WebSocket-based collaboration with Operational Transform

const std = @import("std");
const json = std.json;

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
    users: std.array_list.AlignedManaged(UserPresence, null),
    operation_log: std.array_list.AlignedManaged(Operation, null),
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
            .users = std.array_list.AlignedManaged(UserPresence, null).init(allocator),
            .operation_log = std.array_list.AlignedManaged(Operation, null).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *CollaborationSession) void {
        for (self.users.items) |*user| {
            user.deinit(self.allocator);
        }
        self.users.deinit();

        for (self.operation_log.items) |*op| {
            op.deinit(self.allocator);
        }
        self.operation_log.deinit();

        self.allocator.free(self.session_id);
        self.allocator.free(self.local_user_id);
        self.allocator.destroy(self);
    }

    /// Add a user to the session
    pub fn addUser(self: *CollaborationSession, user_id: []const u8, display_name: []const u8) !void {
        const user = try UserPresence.init(self.allocator, user_id, display_name);
        try self.users.append(user);
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
        try self.operation_log.append(op);
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

/// Message types for WebSocket communication
pub const MessageType = enum {
    operation,
    presence,
    join,
    leave,
    sync,
    ack,

    pub fn jsonStringify(self: MessageType, out: anytype) !void {
        try out.write(@tagName(self));
    }
};

/// WebSocket message wrapper
pub const Message = struct {
    msg_type: MessageType,
    operation: ?Operation = null,
    presence: ?UserPresence = null,
    session_id: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
    version: ?u64 = null,
    timestamp: i64,

    pub fn init(msg_type: MessageType) Message {
        return Message{
            .msg_type = msg_type,
            .timestamp = std.time.timestamp(),
        };
    }

    /// Serialize message to JSON
    pub fn toJson(self: *const Message, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.array_list.AlignedManaged(u8, null).init(allocator);
        errdefer buf.deinit();

        try buf.appendSlice("{\"type\":\"");
        try buf.appendSlice(@tagName(self.msg_type));
        try buf.appendSlice("\",\"timestamp\":");

        var timestamp_buf: [32]u8 = undefined;
        const timestamp_str = try std.fmt.bufPrint(&timestamp_buf, "{d}", .{self.timestamp});
        try buf.appendSlice(timestamp_str);

        if (self.session_id) |sid| {
            try buf.appendSlice(",\"session_id\":\"");
            try buf.appendSlice(sid);
            try buf.append('"');
        }

        if (self.user_id) |uid| {
            try buf.appendSlice(",\"user_id\":\"");
            try buf.appendSlice(uid);
            try buf.append('"');
        }

        if (self.version) |v| {
            try buf.appendSlice(",\"version\":");
            var version_buf: [32]u8 = undefined;
            const version_str = try std.fmt.bufPrint(&version_buf, "{d}", .{v});
            try buf.appendSlice(version_str);
        }

        if (self.operation) |op| {
            try buf.appendSlice(",\"operation\":");
            const op_json = try operationToJson(&op, allocator);
            defer allocator.free(op_json);
            try buf.appendSlice(op_json);
        }

        if (self.presence) |pres| {
            try buf.appendSlice(",\"presence\":");
            const pres_json = try presenceToJson(&pres, allocator);
            defer allocator.free(pres_json);
            try buf.appendSlice(pres_json);
        }

        try buf.append('}');
        return buf.toOwnedSlice();
    }

    /// Parse message from JSON
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !Message {
        var parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        const msg_type_str = root.get("type").?.string;
        const msg_type = std.meta.stringToEnum(MessageType, msg_type_str) orelse return error.InvalidMessageType;

        var msg = Message.init(msg_type);
        msg.timestamp = @intCast(root.get("timestamp").?.integer);

        if (root.get("session_id")) |sid| {
            msg.session_id = try allocator.dupe(u8, sid.string);
        }

        if (root.get("user_id")) |uid| {
            msg.user_id = try allocator.dupe(u8, uid.string);
        }

        if (root.get("version")) |v| {
            msg.version = @intCast(v.integer);
        }

        if (root.get("operation")) |op_obj| {
            msg.operation = try operationFromJson(allocator, op_obj);
        }

        if (root.get("presence")) |pres_obj| {
            msg.presence = try presenceFromJson(allocator, pres_obj);
        }

        return msg;
    }

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        if (self.session_id) |sid| allocator.free(sid);
        if (self.user_id) |uid| allocator.free(uid);
        if (self.operation) |*op| op.deinit(allocator);
        if (self.presence) |*pres| pres.deinit(allocator);
    }
};

fn operationToJson(op: *const Operation, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.array_list.AlignedManaged(u8, null).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("{\"type\":\"");
    try buf.appendSlice(@tagName(op.op_type));
    try buf.appendSlice("\",\"position\":");

    var pos_buf: [32]u8 = undefined;
    const pos_str = try std.fmt.bufPrint(&pos_buf, "{d}", .{op.position});
    try buf.appendSlice(pos_str);

    try buf.appendSlice(",\"user_id\":\"");
    try buf.appendSlice(op.user_id);
    try buf.appendSlice("\",\"version\":");

    var ver_buf: [32]u8 = undefined;
    const ver_str = try std.fmt.bufPrint(&ver_buf, "{d}", .{op.version});
    try buf.appendSlice(ver_str);

    if (op.content) |content| {
        try buf.appendSlice(",\"content\":\"");
        // TODO: Escape special characters
        try buf.appendSlice(content);
        try buf.append('"');
    }

    try buf.append('}');
    return buf.toOwnedSlice();
}

fn operationFromJson(allocator: std.mem.Allocator, obj: json.Value) !Operation {
    const op_obj = obj.object;

    const op_type_str = op_obj.get("type").?.string;
    const op_type = std.meta.stringToEnum(OperationType, op_type_str) orelse return error.InvalidOperationType;

    const position: usize = @intCast(op_obj.get("position").?.integer);
    const user_id = op_obj.get("user_id").?.string;
    const version: u64 = @intCast(op_obj.get("version").?.integer);

    var op = try Operation.init(allocator, op_type, position, user_id, version);

    if (op_obj.get("content")) |content| {
        try op.setContent(allocator, content.string);
    }

    return op;
}

fn presenceToJson(pres: *const UserPresence, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.array_list.AlignedManaged(u8, null).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("{\"user_id\":\"");
    try buf.appendSlice(pres.user_id);
    try buf.appendSlice("\",\"display_name\":\"");
    try buf.appendSlice(pres.display_name);
    try buf.appendSlice("\",\"cursor_position\":");

    var pos_buf: [32]u8 = undefined;
    const pos_str = try std.fmt.bufPrint(&pos_buf, "{d}", .{pres.cursor_position});
    try buf.appendSlice(pos_str);

    if (pres.selection_start) |sel_start| {
        try buf.appendSlice(",\"selection_start\":");
        const sel_str = try std.fmt.bufPrint(&pos_buf, "{d}", .{sel_start});
        try buf.appendSlice(sel_str);
    }

    if (pres.selection_end) |sel_end| {
        try buf.appendSlice(",\"selection_end\":");
        const sel_str = try std.fmt.bufPrint(&pos_buf, "{d}", .{sel_end});
        try buf.appendSlice(sel_str);
    }

    if (pres.buffer_path) |path| {
        try buf.appendSlice(",\"buffer_path\":\"");
        try buf.appendSlice(path);
        try buf.append('"');
    }

    try buf.append('}');
    return buf.toOwnedSlice();
}

fn presenceFromJson(allocator: std.mem.Allocator, obj: json.Value) !UserPresence {
    const pres_obj = obj.object;

    const user_id = pres_obj.get("user_id").?.string;
    const display_name = pres_obj.get("display_name").?.string;

    var pres = try UserPresence.init(allocator, user_id, display_name);
    pres.cursor_position = @intCast(pres_obj.get("cursor_position").?.integer);

    if (pres_obj.get("selection_start")) |sel| {
        pres.selection_start = @intCast(sel.integer);
    }

    if (pres_obj.get("selection_end")) |sel| {
        pres.selection_end = @intCast(sel.integer);
    }

    if (pres_obj.get("buffer_path")) |path| {
        pres.buffer_path = try allocator.dupe(u8, path.string);
    }

    return pres;
}

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

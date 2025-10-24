//! WebSocket Server for Collaborative Editing
//! Sprint 13 - Collaboration Server

const std = @import("std");
const net = std.net;
const websocket = @import("websocket.zig");
const collaboration = @import("collaboration.zig");

/// WebSocket server for collaboration
pub const CollaborationServer = struct {
    allocator: std.mem.Allocator,
    server: ?net.Server = null,
    sessions: std.array_list.AlignedManaged(*collaboration.CollaborationSession, null),
    clients: std.array_list.AlignedManaged(Client, null),
    running: bool = false,
    port: u16,

    const Client = struct {
        stream: net.Stream,
        user_id: ?[]const u8 = null,
        session_id: ?[]const u8 = null,
        thread: ?std.Thread = null,
    };

    pub const Error = error{
        ServerAlreadyRunning,
        ServerNotRunning,
        BindFailed,
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator, port: u16) !*CollaborationServer {
        const self = try allocator.create(CollaborationServer);
        self.* = .{
            .allocator = allocator,
            .port = port,
            .sessions = std.array_list.AlignedManaged(*collaboration.CollaborationSession, null).init(allocator),
            .clients = std.array_list.AlignedManaged(Client, null).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *CollaborationServer) void {
        if (self.running) {
            self.stop();
        }

        for (self.sessions.items) |session| {
            session.deinit();
        }
        self.sessions.deinit();

        for (self.clients.items) |client| {
            client.stream.close();
            if (client.user_id) |uid| self.allocator.free(uid);
            if (client.session_id) |sid| self.allocator.free(sid);
        }
        self.clients.deinit();

        self.allocator.destroy(self);
    }

    /// Start server
    pub fn start(self: *CollaborationServer) !void {
        if (self.running) return Error.ServerAlreadyRunning;

        const address = try net.Address.parseIp("0.0.0.0", self.port);
        self.server = try address.listen(.{
            .reuse_address = true,
        });

        self.running = true;

        std.log.info("Collaboration server listening on port {d}", .{self.port});
    }

    /// Stop server
    pub fn stop(self: *CollaborationServer) void {
        self.running = false;
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
    }

    /// Accept client connections (blocking)
    pub fn acceptConnections(self: *CollaborationServer) !void {
        const server = self.server orelse return Error.ServerNotRunning;

        while (self.running) {
            const connection = server.accept() catch |err| {
                std.log.warn("Accept failed: {}", .{err});
                continue;
            };

            // Handle in separate thread
            const thread = try std.Thread.spawn(.{}, handleClient, .{ self, connection.stream });
            _ = thread;
        }
    }

    fn handleClient(self: *CollaborationServer, stream: net.Stream) void {
        defer stream.close();

        // Read HTTP request
        var buf: [4096]u8 = undefined;
        const n = stream.read(&buf) catch return;
        const request = buf[0..n];

        // Parse WebSocket handshake
        const handshake_response = self.buildHandshakeResponse(request) catch return;

        // Send handshake
        _ = stream.write(handshake_response) catch return;

        // Now in WebSocket mode
        std.log.info("Client connected via WebSocket", .{});

        // Message loop
        while (self.running) {
            var msg_buf: [8192]u8 = undefined;
            const msg_len = self.receiveMessage(stream, &msg_buf) catch break;

            if (msg_len == 0) break;

            const message = msg_buf[0..msg_len];
            self.handleMessage(stream, message) catch |err| {
                std.log.warn("Message handling failed: {}", .{err});
            };
        }
    }

    fn buildHandshakeResponse(self: *CollaborationServer, request: []const u8) ![]const u8 {
        // Extract Sec-WebSocket-Key
        const key_start = std.mem.indexOf(u8, request, "Sec-WebSocket-Key: ") orelse return error.InvalidHandshake;
        const key_line_start = key_start + "Sec-WebSocket-Key: ".len;
        const key_line_end = std.mem.indexOfPos(u8, request, key_line_start, "\r\n") orelse return error.InvalidHandshake;
        const client_key = request[key_line_start..key_line_end];

        // Compute accept key: SHA1(key + magic_string) base64
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var key_buf: [256]u8 = undefined;
        const key_concat = try std.fmt.bufPrint(&key_buf, "{s}{s}", .{ client_key, magic });

        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(key_concat, &hash, .{});

        var accept_buf: [32]u8 = undefined;
        const accept_key = std.base64.standard.Encoder.encode(&accept_buf, &hash);

        // Build response
        var response_buf: [512]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buf,
            \\HTTP/1.1 101 Switching Protocols
            \\Upgrade: websocket
            \\Connection: Upgrade
            \\Sec-WebSocket-Accept: {s}
            \\
            \\
        , .{accept_key});

        // Allocate permanent copy
        return try self.allocator.dupe(u8, response);
    }

    fn receiveMessage(self: *CollaborationServer, stream: net.Stream, buffer: []u8) !usize {
        _ = self;

        // Read frame header
        var header: [2]u8 = undefined;
        _ = try stream.readAll(&header);

        const fin = (header[0] & 0x80) != 0;
        const opcode = header[0] & 0x0F;
        const masked = (header[1] & 0x80) != 0;
        var payload_len: u64 = header[1] & 0x7F;

        // Extended length
        if (payload_len == 126) {
            var len_buf: [2]u8 = undefined;
            _ = try stream.readAll(&len_buf);
            payload_len = std.mem.readInt(u16, &len_buf, .big);
        } else if (payload_len == 127) {
            var len_buf: [8]u8 = undefined;
            _ = try stream.readAll(&len_buf);
            payload_len = std.mem.readInt(u64, &len_buf, .big);
        }

        // Mask key
        var mask_key: [4]u8 = undefined;
        if (masked) {
            _ = try stream.readAll(&mask_key);
        }

        // Read payload
        if (payload_len > buffer.len) return error.BufferTooSmall;
        const payload = buffer[0..@intCast(payload_len)];
        _ = try stream.readAll(payload);

        // Unmask
        if (masked) {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask_key[i % 4];
            }
        }

        _ = fin;
        _ = opcode;

        return @intCast(payload_len);
    }

    fn handleMessage(self: *CollaborationServer, stream: net.Stream, message: []const u8) !void {
        // Parse JSON message
        var msg = collaboration.Message.fromJson(self.allocator, message) catch |err| {
            std.log.warn("Failed to parse message: {}", .{err});
            return;
        };
        defer msg.deinit(self.allocator);

        std.log.info("Received message type: {s}", .{@tagName(msg.msg_type)});

        switch (msg.msg_type) {
            .join => {
                // Handle user joining session
                const session_id = msg.session_id orelse return error.MissingSessionId;
                const user_id = msg.user_id orelse return error.MissingUserId;

                const session = try self.getOrCreateSession(session_id);

                // Add user to session if not already present
                if (session.getUser(user_id) == null) {
                    try session.addUser(user_id, user_id); // TODO: Use real display name
                    std.log.info("User {s} joined session {s}", .{ user_id, session_id });
                }

                // Send ack
                var ack_msg = collaboration.Message.init(.ack);
                ack_msg.session_id = try self.allocator.dupe(u8, session_id);
                ack_msg.version = session.current_version;
                defer ack_msg.deinit(self.allocator);

                const ack_json = try ack_msg.toJson(self.allocator);
                defer self.allocator.free(ack_json);

                try self.sendMessage(stream, ack_json);

                // Broadcast join to other users
                var join_broadcast = collaboration.Message.init(.join);
                join_broadcast.session_id = try self.allocator.dupe(u8, session_id);
                join_broadcast.user_id = try self.allocator.dupe(u8, user_id);
                defer join_broadcast.deinit(self.allocator);

                const join_json = try join_broadcast.toJson(self.allocator);
                defer self.allocator.free(join_json);

                try self.broadcast(session_id, join_json);
            },

            .leave => {
                // Handle user leaving session
                const session_id = msg.session_id orelse return;
                const user_id = msg.user_id orelse return;

                for (self.sessions.items) |session| {
                    if (std.mem.eql(u8, session.session_id, session_id)) {
                        session.removeUser(user_id) catch {};
                        std.log.info("User {s} left session {s}", .{ user_id, session_id });

                        // Broadcast leave to other users
                        try self.broadcast(session_id, message);
                        break;
                    }
                }
            },

            .operation => {
                // Handle operation
                const session_id = msg.session_id orelse return error.MissingSessionId;

                for (self.sessions.items) |session| {
                    if (std.mem.eql(u8, session.session_id, session_id)) {
                        if (msg.operation) |op| {
                            // Record operation in session
                            try session.recordOperation(op);

                            // Apply OT transformation if needed
                            // TODO: Transform against concurrent operations

                            // Broadcast to all other clients
                            try self.broadcast(session_id, message);

                            std.log.info("Operation broadcasted in session {s}", .{session_id});
                        }
                        break;
                    }
                }
            },

            .presence => {
                // Handle presence update
                const session_id = msg.session_id orelse return;
                const user_id = msg.user_id orelse return;

                for (self.sessions.items) |session| {
                    if (std.mem.eql(u8, session.session_id, session_id)) {
                        if (session.getUser(user_id)) |user| {
                            if (msg.presence) |pres| {
                                user.cursor_position = pres.cursor_position;
                                user.selection_start = pres.selection_start;
                                user.selection_end = pres.selection_end;
                            }

                            // Broadcast presence to other users
                            try self.broadcast(session_id, message);
                        }
                        break;
                    }
                }
            },

            .sync => {
                // Handle sync request - send current session state
                const session_id = msg.session_id orelse return;

                for (self.sessions.items) |session| {
                    if (std.mem.eql(u8, session.session_id, session_id)) {
                        // Send current version and user list
                        var sync_response = collaboration.Message.init(.sync);
                        sync_response.session_id = try self.allocator.dupe(u8, session_id);
                        sync_response.version = session.current_version;
                        defer sync_response.deinit(self.allocator);

                        const sync_json = try sync_response.toJson(self.allocator);
                        defer self.allocator.free(sync_json);

                        try self.sendMessage(stream, sync_json);
                        break;
                    }
                }
            },

            .ack => {
                // Client received our message
                std.log.debug("Received ack", .{});
            },
        }
    }

    fn sendMessage(self: *CollaborationServer, stream: net.Stream, message: []const u8) !void {
        _ = self;

        // Encode as WebSocket text frame
        var frame_buf: [8192]u8 = undefined;

        // Build frame header
        var header_len: usize = 2;
        frame_buf[0] = 0x81; // FIN + text frame

        if (message.len < 126) {
            frame_buf[1] = @intCast(message.len);
        } else if (message.len < 65536) {
            frame_buf[1] = 126;
            std.mem.writeInt(u16, frame_buf[2..4], @intCast(message.len), .big);
            header_len = 4;
        } else {
            frame_buf[1] = 127;
            std.mem.writeInt(u64, frame_buf[2..10], @intCast(message.len), .big);
            header_len = 10;
        }

        // Copy payload
        if (header_len + message.len > frame_buf.len) return error.MessageTooLarge;
        @memcpy(frame_buf[header_len .. header_len + message.len], message);

        // Send frame
        _ = try stream.write(frame_buf[0 .. header_len + message.len]);
    }

    /// Create or get session
    pub fn getOrCreateSession(self: *CollaborationServer, session_id: []const u8) !*collaboration.CollaborationSession {
        // Check existing sessions
        for (self.sessions.items) |session| {
            if (std.mem.eql(u8, session.session_id, session_id)) {
                return session;
            }
        }

        // Create new session
        const session = try collaboration.CollaborationSession.init(
            self.allocator,
            session_id,
            "server",
        );
        try self.sessions.append(session);
        return session;
    }

    /// Broadcast message to all clients in session
    pub fn broadcast(self: *CollaborationServer, session_id: []const u8, message: []const u8) !void {
        for (self.clients.items) |client| {
            if (client.session_id) |csid| {
                if (std.mem.eql(u8, csid, session_id)) {
                    self.sendMessage(client.stream, message) catch |err| {
                        std.log.warn("Failed to broadcast to client: {}", .{err});
                    };
                }
            }
        }
    }
};

test "collaboration server" {
    const allocator = std.testing.allocator;
    const server = try CollaborationServer.init(allocator, 8080);
    defer server.deinit();

    try std.testing.expect(server.port == 8080);
    try std.testing.expect(!server.running);
}

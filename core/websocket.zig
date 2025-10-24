//! Simple WebSocket Client for Collaborative Editing
//! Sprint 13 - WebSocket Layer

const std = @import("std");
const net = std.net;

/// WebSocket opcode
pub const Opcode = enum(u8) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

/// WebSocket frame header
pub const Frame = struct {
    fin: bool,
    opcode: Opcode,
    masked: bool,
    payload_len: u64,
    mask_key: ?[4]u8 = null,
    payload: []const u8,
};

/// Simple WebSocket client
pub const WebSocketClient = struct {
    allocator: std.mem.Allocator,
    stream: ?net.Stream = null,
    connected: bool = false,
    url: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,

    pub const Error = error{
        InvalidUrl,
        HandshakeFailed,
        NotConnected,
        SendFailed,
        ReceiveFailed,
    } || std.mem.Allocator.Error || net.TcpConnectToHostError;

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !*WebSocketClient {
        const self = try allocator.create(WebSocketClient);

        // Parse URL: ws://host:port/path
        const parsed = try parseUrl(allocator, url);

        self.* = .{
            .allocator = allocator,
            .url = try allocator.dupe(u8, url),
            .host = parsed.host,
            .port = parsed.port,
            .path = parsed.path,
        };

        return self;
    }

    pub fn deinit(self: *WebSocketClient) void {
        if (self.stream) |stream| {
            stream.close();
        }
        self.allocator.free(self.url);
        self.allocator.free(self.host);
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    /// Connect to WebSocket server
    pub fn connect(self: *WebSocketClient) !void {
        if (self.connected) return;

        // Connect TCP socket
        self.stream = try net.tcpConnectToHost(self.allocator, self.host, self.port);

        // Send WebSocket handshake
        try self.sendHandshake();

        // Receive and verify handshake response
        try self.receiveHandshake();

        self.connected = true;
    }

    /// Disconnect from server
    pub fn disconnect(self: *WebSocketClient) void {
        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
        self.connected = false;
    }

    /// Send text message
    pub fn sendText(self: *WebSocketClient, message: []const u8) !void {
        if (!self.connected) return Error.NotConnected;

        var frame_buf: [4096]u8 = undefined;
        const frame_data = try encodeFrame(&frame_buf, .text, message, true);

        const stream = self.stream orelse return Error.NotConnected;
        _ = stream.write(frame_data) catch return Error.SendFailed;
    }

    /// Receive message (blocking)
    pub fn receive(self: *WebSocketClient, buffer: []u8) !usize {
        if (!self.connected) return Error.NotConnected;

        const stream = self.stream orelse return Error.NotConnected;

        // Read frame header (at least 2 bytes)
        var header: [14]u8 = undefined;
        const header_len = stream.read(header[0..2]) catch return Error.ReceiveFailed;
        if (header_len < 2) return Error.ReceiveFailed;

        const fin = (header[0] & 0x80) != 0;
        const opcode: Opcode = @enumFromInt(header[0] & 0x0F);
        const masked = (header[1] & 0x80) != 0;
        var payload_len: u64 = header[1] & 0x7F;

        var header_size: usize = 2;

        // Extended payload length
        if (payload_len == 126) {
            _ = try stream.readAll(header[2..4]);
            payload_len = std.mem.readInt(u16, header[2..4], .big);
            header_size += 2;
        } else if (payload_len == 127) {
            _ = try stream.readAll(header[2..10]);
            payload_len = std.mem.readInt(u64, header[2..10], .big);
            header_size += 8;
        }

        // Masking key (servers don't mask, clients do)
        var mask_key: [4]u8 = undefined;
        if (masked) {
            _ = try stream.readAll(mask_key[0..]);
            header_size += 4;
        }

        // Read payload
        if (payload_len > buffer.len) {
            return Error.ReceiveFailed; // Buffer too small
        }

        const payload_bytes = buffer[0..@intCast(payload_len)];
        _ = try stream.readAll(payload_bytes);

        // Unmask if needed
        if (masked) {
            for (payload_bytes, 0..) |*byte, i| {
                byte.* ^= mask_key[i % 4];
            }
        }

        _ = fin;
        _ = opcode;

        return @intCast(payload_len);
    }

    // Private methods

    fn sendHandshake(self: *WebSocketClient) !void {
        const stream = self.stream orelse return Error.NotConnected;

        // Generate random WebSocket key
        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);

        var key_buf: [24]u8 = undefined;
        const key = std.base64.standard.Encoder.encode(&key_buf, &key_bytes);

        // Build handshake request
        var buf: [1024]u8 = undefined;
        const handshake = try std.fmt.bufPrint(&buf,
            \\GET {s} HTTP/1.1
            \\Host: {s}:{d}
            \\Upgrade: websocket
            \\Connection: Upgrade
            \\Sec-WebSocket-Key: {s}
            \\Sec-WebSocket-Version: 13
            \\
            \\
        , .{ self.path, self.host, self.port, key });

        _ = try stream.write(handshake);
    }

    fn receiveHandshake(self: *WebSocketClient) !void {
        const stream = self.stream orelse return Error.NotConnected;

        var buf: [2048]u8 = undefined;
        const n = try stream.read(&buf);

        const response = buf[0..n];

        // Simple validation: check for "101 Switching Protocols"
        if (std.mem.indexOf(u8, response, "101") == null) {
            return Error.HandshakeFailed;
        }
    }

    fn encodeFrame(buffer: []u8, opcode: Opcode, payload: []const u8, mask: bool) ![]const u8 {
        var offset: usize = 0;

        // FIN + opcode
        buffer[offset] = 0x80 | @intFromEnum(opcode);
        offset += 1;

        // Mask bit + payload length
        const payload_len = payload.len;
        if (payload_len < 126) {
            buffer[offset] = @intCast(if (mask) 0x80 | payload_len else payload_len);
            offset += 1;
        } else if (payload_len < 65536) {
            buffer[offset] = if (mask) 0x80 | 126 else 126;
            offset += 1;
            std.mem.writeInt(u16, buffer[offset..][0..2], @intCast(payload_len), .big);
            offset += 2;
        } else {
            buffer[offset] = if (mask) 0x80 | 127 else 127;
            offset += 1;
            std.mem.writeInt(u64, buffer[offset..][0..8], @intCast(payload_len), .big);
            offset += 8;
        }

        // Masking key (clients should mask)
        var mask_key: [4]u8 = undefined;
        if (mask) {
            std.crypto.random.bytes(&mask_key);
            @memcpy(buffer[offset..][0..4], &mask_key);
            offset += 4;
        }

        // Payload
        @memcpy(buffer[offset..][0..payload.len], payload);

        // Apply mask if needed
        if (mask) {
            for (buffer[offset..][0..payload.len], 0..) |*byte, i| {
                byte.* ^= mask_key[i % 4];
            }
        }

        offset += payload.len;
        return buffer[0..offset];
    }
};

/// Parse WebSocket URL
fn parseUrl(allocator: std.mem.Allocator, url: []const u8) !struct {
    host: []const u8,
    port: u16,
    path: []const u8,
} {
    // Remove ws:// or wss:// prefix
    const without_protocol = if (std.mem.startsWith(u8, url, "ws://"))
        url[5..]
    else if (std.mem.startsWith(u8, url, "wss://"))
        url[6..]
    else
        url;

    // Find path separator
    const path_start = std.mem.indexOf(u8, without_protocol, "/") orelse without_protocol.len;

    const host_port = without_protocol[0..path_start];
    const path = if (path_start < without_protocol.len)
        try allocator.dupe(u8, without_protocol[path_start..])
    else
        try allocator.dupe(u8, "/");

    // Split host:port
    if (std.mem.indexOf(u8, host_port, ":")) |colon_idx| {
        const host = try allocator.dupe(u8, host_port[0..colon_idx]);
        const port_str = host_port[colon_idx + 1 ..];
        const port = try std.fmt.parseInt(u16, port_str, 10);
        return .{ .host = host, .port = port, .path = path };
    } else {
        const host = try allocator.dupe(u8, host_port);
        return .{ .host = host, .port = 80, .path = path };
    }
}

test "parse url" {
    const allocator = std.testing.allocator;

    const result = try parseUrl(allocator, "ws://localhost:8080/collab");
    defer {
        allocator.free(result.host);
        allocator.free(result.path);
    }

    try std.testing.expectEqualStrings("localhost", result.host);
    try std.testing.expect(result.port == 8080);
    try std.testing.expectEqualStrings("/collab", result.path);
}

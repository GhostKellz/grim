const std = @import("std");

pub const TransportError = error{
    EndOfStream,
    ReadFailure,
    WriteFailure,
};

pub const DiagnosticsLogFn = *const fn (ctx: *anyopaque, message: []const u8) std.mem.Allocator.Error!void;

pub const DiagnosticsSink = struct {
    ctx: *anyopaque,
    logFn: DiagnosticsLogFn,
};

pub const Transport = struct {
    ctx: *anyopaque,
    readFn: *const fn (ctx: *anyopaque, buffer: []u8) TransportError!usize,
    writeFn: *const fn (ctx: *anyopaque, buffer: []const u8) TransportError!usize,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    transport: Transport,
    next_id: u32,
    pending_initialize: ?u32,
    initialized: bool,
    diagnostics_sink: ?DiagnosticsSink,

    pub const Error = TransportError || std.mem.Allocator.Error || error{
        ProtocolError,
        MissingContentLength,
        InvalidMessage,
    };

    pub fn init(allocator: std.mem.Allocator, transport: Transport) Client {
        return .{
            .allocator = allocator,
            .transport = transport,
            .next_id = 1,
            .pending_initialize = null,
            .initialized = false,
            .diagnostics_sink = null,
        };
    }

    pub fn deinit(self: *Client) void {
        self.* = undefined;
    }

    pub fn setDiagnosticsSink(self: *Client, sink: DiagnosticsSink) void {
        self.diagnostics_sink = sink;
    }

    pub fn isInitialized(self: *const Client) bool {
        return self.initialized;
    }

    pub fn sendInitialize(self: *Client, root_uri: []const u8) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "initialize",
            params: Params,

            const Params = struct {
                processId: ?u32 = null,
                rootUri: []const u8,
                capabilities: struct {} = .{},
            };
        };

        const request = Request{
            .id = id,
            .params = .{ .rootUri = root_uri },
        };

        const body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(body);

        try self.writeMessage(body);

        self.pending_initialize = id;
        return id;
    }

    pub fn poll(self: *Client) Error!void {
        const payload = try self.readMessage();
        defer self.allocator.free(payload);
        try self.handlePayload(payload);
    }

    fn writeMessage(self: *Client, body: []const u8) Error!void {
        const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{body.len});
        defer self.allocator.free(header);

        try self.writeAll(header);
        try self.writeAll(body);
    }

    fn writeAll(self: *Client, data: []const u8) Error!void {
        var offset: usize = 0;
        while (offset < data.len) {
            const written = try self.transport.writeFn(self.transport.ctx, data[offset..]);
            if (written == 0) return TransportError.WriteFailure;
            offset += written;
        }
    }

    fn readMessage(self: *Client) Error![]u8 {
        var line_buffer = std.ArrayList(u8).init(self.allocator);
        defer line_buffer.deinit();

        var content_length: ?usize = null;

        while (true) {
            try self.readLine(&line_buffer);
            if (line_buffer.items.len == 0) break;

            const line = line_buffer.items;
            const colon_index = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trimRight(u8, line[0..colon_index], " ");
            const value_slice = std.mem.trimLeft(u8, line[colon_index + 1 ..], " ");

            if (std.ascii.eqlIgnoreCase(key, "content-length")) {
                const parsed = std.fmt.parseInt(usize, value_slice, 10) catch {
                    return error.ProtocolError;
                };
                content_length = parsed;
            }
        }

        const length = content_length orelse return error.MissingContentLength;
        const body = try self.allocator.alloc(u8, length);
        errdefer self.allocator.free(body);
        try self.readExact(body);
        return body;
    }

    fn readLine(self: *Client, buffer: *std.ArrayList(u8)) Error!void {
        buffer.clearRetainingCapacity();
        while (true) {
            var byte: [1]u8 = undefined;
            const n = try self.transport.readFn(self.transport.ctx, byte[0..]);
            if (n == 0) return TransportError.EndOfStream;
            const b = byte[0];
            if (b == '\n') break;
            try buffer.append(b);
        }
        if (buffer.items.len > 0 and buffer.items[buffer.items.len - 1] == '\r') {
            buffer.items.len -= 1;
        }
    }

    fn readExact(self: *Client, dest: []u8) Error!void {
        var offset: usize = 0;
        while (offset < dest.len) {
            const read = try self.transport.readFn(self.transport.ctx, dest[offset..]);
            if (read == 0) return TransportError.EndOfStream;
            offset += read;
        }
    }

    fn handlePayload(self: *Client, payload: []const u8) Error!void {
        var parser = std.json.Parser.init(self.allocator, .{});
        defer parser.deinit();
        var tree = try parser.parse(payload);
        defer tree.deinit();

        const root = tree.root orelse return error.InvalidMessage;
        if (root.* != .object) return error.InvalidMessage;

        const object = root.object;

        if (object.get("id")) |id_node| {
            if (id_node.* == .integer) {
                if (self.pending_initialize) |expected| {
                    if (id_node.integer == expected) {
                        self.pending_initialize = null;
                        self.initialized = true;
                    }
                }
            }
        }

        if (object.get("method")) |method_node| {
            if (method_node.* == .string) {
                if (std.mem.eql(u8, method_node.string, "textDocument/publishDiagnostics")) {
                    if (object.get("params")) |params_node| {
                        if (params_node.* == .object) {
                            try self.logDiagnostics(params_node.object);
                        }
                    }
                }
            }
        }
    }

    fn logDiagnostics(self: *Client, params: std.json.ObjectMap) Error!void {
        if (self.diagnostics_sink == null) return;
        var uri_slice: []const u8 = "<unknown>";
        var count: usize = 0;

        if (params.get("uri")) |uri_node| {
            if (uri_node.* == .string) {
                uri_slice = uri_node.string;
            }
        }

        if (params.get("diagnostics")) |diag_node| {
            if (diag_node.* == .array) {
                count = diag_node.array.items.len;
            }
        }

        const message = try std.fmt.allocPrint(self.allocator, "{s}: {d} diagnostic(s)", .{ uri_slice, count });
        defer self.allocator.free(message);

        const sink = self.diagnostics_sink.?;
        try sink.logFn(sink.ctx, message);
    }
};

test "initialize request framing" {
    const allocator = std.testing.allocator;
    var transport = MockTransport.init(allocator);
    defer transport.deinit();

    var client = Client.init(allocator, transport.transport());

    _ = try client.sendInitialize("file:///tmp/project");

    const written = transport.writtenBytes();
    try std.testing.expect(std.mem.startsWith(u8, written, "Content-Length:"));
    try std.testing.expect(std.mem.indexOf(u8, written, "\r\n\r\n") != null);
    const payload = written[(std.mem.indexOf(u8, written, "\r\n\r\n").? + 4)..];
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"initialize\"") != null);
}

test "diagnostics notification triggers sink" {
    const allocator = std.testing.allocator;
    var transport = MockTransport.init(allocator);
    defer transport.deinit();

    const message = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///test.zig\",\"diagnostics\":[{\"message\":\"oops\"}]}}";
    const frame = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n\r\n{s}", .{ message.len, message });
    defer allocator.free(frame);
    transport.queueIncoming(frame);

    var client = Client.init(allocator, transport.transport());

    var sink = CaptureSink.init(allocator);
    defer sink.deinit();
    client.setDiagnosticsSink(sink.sink());

    try client.poll();
    try std.testing.expect(std.mem.indexOf(u8, sink.last_message.?, "test.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.last_message.?, "1 diagnostic") != null);
}

const MockTransport = struct {
    allocator: std.mem.Allocator,
    written: std.ArrayList(u8),
    incoming: std.ArrayList(u8),
    read_cursor: usize,

    fn init(allocator: std.mem.Allocator) MockTransport {
        return .{
            .allocator = allocator,
            .written = std.ArrayList(u8).init(allocator),
            .incoming = std.ArrayList(u8).init(allocator),
            .read_cursor = 0,
        };
    }

    fn deinit(self: *MockTransport) void {
        self.written.deinit();
        self.incoming.deinit();
        self.* = undefined;
    }

    fn transport(self: *MockTransport) Transport {
        return .{
            .ctx = self,
            .readFn = read,
            .writeFn = write,
        };
    }

    fn writtenBytes(self: *MockTransport) []const u8 {
        return self.written.items;
    }

    fn queueIncoming(self: *MockTransport, data: []const u8) void {
        self.incoming.appendSlice(data) catch unreachable;
    }

    fn read(ctx: *anyopaque, buffer: []u8) TransportError!usize {
        const self = fromCtx(ctx);
        const remaining = self.incoming.items.len - self.read_cursor;
        if (remaining == 0) return TransportError.EndOfStream;
        const to_copy = @min(buffer.len, remaining);
        std.mem.copy(u8, buffer[0..to_copy], self.incoming.items[self.read_cursor .. self.read_cursor + to_copy]);
        self.read_cursor += to_copy;
        return to_copy;
    }

    fn write(ctx: *anyopaque, buffer: []const u8) TransportError!usize {
        const self = fromCtx(ctx);
        self.written.appendSlice(buffer) catch return TransportError.WriteFailure;
        return buffer.len;
    }

    fn fromCtx(ctx: *anyopaque) *MockTransport {
        return @ptrCast(@alignCast(ctx));
    }
};

const CaptureSink = struct {
    allocator: std.mem.Allocator,
    last_message: ?[]const u8,

    fn init(allocator: std.mem.Allocator) CaptureSink {
        return .{ .allocator = allocator, .last_message = null };
    }

    fn deinit(self: *CaptureSink) void {
        if (self.last_message) |msg| self.allocator.free(msg);
        self.* = undefined;
    }

    fn sink(self: *CaptureSink) DiagnosticsSink {
        return .{
            .ctx = self,
            .logFn = log,
        };
    }

    fn log(ctx: *anyopaque, message: []const u8) !void {
        const self = fromCtx(ctx);
        if (self.last_message) |old| self.allocator.free(old);
        self.last_message = try self.allocator.dupe(u8, message);
    }

    fn fromCtx(ctx: *anyopaque) *CaptureSink {
        return @ptrCast(@alignCast(ctx));
    }
};

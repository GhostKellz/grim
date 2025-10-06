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

pub const HoverResponse = struct {
    request_id: u32,
    contents: []const u8, // Markdown content
};

pub const DefinitionResponse = struct {
    request_id: u32,
    uri: []const u8,
    line: u32,
    character: u32,
};

pub const ResponseCallback = struct {
    ctx: *anyopaque,
    onHover: ?*const fn (ctx: *anyopaque, response: HoverResponse) void,
    onDefinition: ?*const fn (ctx: *anyopaque, response: DefinitionResponse) void,
};

pub const PendingRequest = struct {
    id: u32,
    kind: RequestKind,

    pub const RequestKind = enum {
        hover,
        definition,
        completion,
    };
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
    response_callback: ?ResponseCallback,
    pending_requests: std.ArrayList(PendingRequest),

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
            .response_callback = null,
            .pending_requests = .empty,
        };
    }

    pub fn deinit(self: *Client) void {
        self.pending_requests.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn setDiagnosticsSink(self: *Client, sink: DiagnosticsSink) void {
        self.diagnostics_sink = sink;
    }

    pub fn setResponseCallback(self: *Client, callback: ResponseCallback) void {
        self.response_callback = callback;
    }

    pub fn isInitialized(self: *const Client) bool {
        return self.initialized;
    }

    fn jsonStringify(self: *Client, value: anytype) Error![]u8 {
        return std.json.Stringify.valueAlloc(self.allocator, value, .{}) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
        };
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

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        self.pending_initialize = id;
        return id;
    }

    pub fn sendDidOpen(self: *Client, uri: []const u8, language_id: []const u8, text: []const u8) Error!void {
        const Notification = struct {
            jsonrpc: []const u8 = "2.0",
            method: []const u8 = "textDocument/didOpen",
            params: Params,

            const Params = struct {
                textDocument: TextDocument,

                const TextDocument = struct {
                    uri: []const u8,
                    languageId: []const u8,
                    version: u32 = 1,
                    text: []const u8,
                };
            };
        };

        const notification = Notification{
            .params = .{
                .textDocument = .{
                    .uri = uri,
                    .languageId = language_id,
                    .text = text,
                },
            },
        };

        const body = try self.jsonStringify(notification);
        defer self.allocator.free(body);

        try self.writeMessage(body);
    }

    pub fn sendDidChange(self: *Client, uri: []const u8, version: u32, text: []const u8) Error!void {
        const Notification = struct {
            jsonrpc: []const u8 = "2.0",
            method: []const u8 = "textDocument/didChange",
            params: Params,

            const Params = struct {
                textDocument: struct {
                    uri: []const u8,
                    version: u32,
                },
                contentChanges: []const ContentChange,

                const ContentChange = struct {
                    text: []const u8,
                };
            };
        };

        const changes = [_]Notification.Params.ContentChange{.{ .text = text }};

        const notification = Notification{
            .params = .{
                .textDocument = .{
                    .uri = uri,
                    .version = version,
                },
                .contentChanges = &changes,
            },
        };

        const body = try self.jsonStringify(notification);
        defer self.allocator.free(body);

        try self.writeMessage(body);
    }

    pub fn sendDidSave(self: *Client, uri: []const u8, text: ?[]const u8) Error!void {
        const Notification = struct {
            jsonrpc: []const u8 = "2.0",
            method: []const u8 = "textDocument/didSave",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                text: ?[]const u8 = null,
            };
        };

        const notification = Notification{
            .params = .{
                .textDocument = .{ .uri = uri },
                .text = text,
            },
        };

        const body = try self.jsonStringify(notification);
        defer self.allocator.free(body);

        try self.writeMessage(body);
    }

    pub fn requestCompletion(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/completion",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                position: struct { line: u32, character: u32 },
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
                .position = .{ .line = line, .character = character },
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        return id;
    }

    pub fn requestHover(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/hover",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                position: struct { line: u32, character: u32 },
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
                .position = .{ .line = line, .character = character },
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        // Track pending request for response handling
        try self.pending_requests.append(self.allocator, .{
            .id = id,
            .kind = .hover,
        });

        return id;
    }

    pub fn requestDefinition(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/definition",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                position: struct { line: u32, character: u32 },
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
                .position = .{ .line = line, .character = character },
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        // Track pending request for response handling
        try self.pending_requests.append(self.allocator, .{
            .id = id,
            .kind = .definition,
        });

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
        var line_buffer: std.ArrayList(u8) = .empty;
        defer line_buffer.deinit(self.allocator);

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
            try buffer.append(self.allocator, b);
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
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, payload, .{}) catch {
            return error.InvalidMessage;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidMessage;

        const object = root.object;

        // Handle responses (have "id" field)
        if (object.get("id")) |id_node| {
            if (id_node == .integer) {
                const response_id: u32 = @intCast(id_node.integer);

                // Check for initialize response
                if (self.pending_initialize) |expected| {
                    if (response_id == expected) {
                        self.pending_initialize = null;
                        self.initialized = true;
                        return;
                    }
                }

                // Check for hover/definition/completion responses
                if (object.get("result")) |result_node| {
                    try self.handleResponse(response_id, result_node);
                }
            }
        }

        if (object.get("method")) |method_node| {
            if (method_node == .string) {
                if (std.mem.eql(u8, method_node.string, "textDocument/publishDiagnostics")) {
                    if (object.get("params")) |params_node| {
                        if (params_node == .object) {
                            try self.logDiagnostics(params_node.object);
                        }
                    }
                }
            }
        }
    }

    fn handleResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        // Find the pending request
        var request_kind: ?PendingRequest.RequestKind = null;
        for (self.pending_requests.items, 0..) |req, i| {
            if (req.id == id) {
                request_kind = req.kind;
                _ = self.pending_requests.swapRemove(i);
                break;
            }
        }

        if (request_kind == null) return; // Unknown request

        switch (request_kind.?) {
            .hover => try self.handleHoverResponse(id, result),
            .definition => try self.handleDefinitionResponse(id, result),
            .completion => {}, // TODO
        }
    }

    fn handleHoverResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        const callback = self.response_callback orelse return;
        if (callback.onHover == null) return;

        // Parse hover response
        // LSP hover result: { contents: string | MarkupContent }
        var contents: []const u8 = "";

        if (result == .object) {
            if (result.object.get("contents")) |contents_node| {
                if (contents_node == .string) {
                    contents = contents_node.string;
                } else if (contents_node == .object) {
                    // MarkupContent: { kind: "markdown"|"plaintext", value: string }
                    if (contents_node.object.get("value")) |value_node| {
                        if (value_node == .string) {
                            contents = value_node.string;
                        }
                    }
                }
            }
        } else if (result == .string) {
            contents = result.string;
        }

        const response = HoverResponse{
            .request_id = id,
            .contents = contents,
        };

        callback.onHover.?(callback.ctx, response);
    }

    fn handleDefinitionResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        const callback = self.response_callback orelse return;
        if (callback.onDefinition == null) return;

        // Parse definition response
        // LSP definition result: Location | Location[] | null
        if (result == .array and result.array.items.len > 0) {
            const location = result.array.items[0];
            if (location == .object) {
                var uri: []const u8 = "";
                var line: u32 = 0;
                var character: u32 = 0;

                if (location.object.get("uri")) |uri_node| {
                    if (uri_node == .string) uri = uri_node.string;
                }
                if (location.object.get("range")) |range_node| {
                    if (range_node == .object) {
                        if (range_node.object.get("start")) |start_node| {
                            if (start_node == .object) {
                                if (start_node.object.get("line")) |line_node| {
                                    if (line_node == .integer) line = @intCast(line_node.integer);
                                }
                                if (start_node.object.get("character")) |char_node| {
                                    if (char_node == .integer) character = @intCast(char_node.integer);
                                }
                            }
                        }
                    }
                }

                const response = DefinitionResponse{
                    .request_id = id,
                    .uri = uri,
                    .line = line,
                    .character = character,
                };

                callback.onDefinition.?(callback.ctx, response);
            }
        }
    }

    fn logDiagnostics(self: *Client, params: std.json.ObjectMap) Error!void {
        if (self.diagnostics_sink == null) return;
        var uri_slice: []const u8 = "<unknown>";
        var count: usize = 0;

        if (params.get("uri")) |uri_node| {
            if (uri_node == .string) {
                uri_slice = uri_node.string;
            }
        }

        if (params.get("diagnostics")) |diag_node| {
            if (diag_node == .array) {
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

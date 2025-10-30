const std = @import("std");

pub const TransportError = error{
    EndOfStream,
    ReadFailure,
    WriteFailure,
};

pub const DiagnosticsHandlerFn = *const fn (ctx: *anyopaque, params: std.json.Value) std.mem.Allocator.Error!void;

pub const DiagnosticsSink = struct {
    ctx: *anyopaque,
    handleFn: DiagnosticsHandlerFn,
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

pub const CompletionResponse = struct {
    request_id: u32,
    result: std.json.Value,
};

pub const SignatureHelpResponse = struct {
    request_id: u32,
    result: std.json.Value,
};

pub const InlayHintsResponse = struct {
    request_id: u32,
    result: std.json.Value,
};

pub const SelectionRangeResponse = struct {
    request_id: u32,
    result: std.json.Value,
};

pub const CodeActionsResponse = struct {
    request_id: u32,
    result: std.json.Value,
};

/// Semantic token types (LSP 3.17 standard + GhostLS extensions)
pub const SemanticTokenType = enum(u32) {
    namespace = 0,
    type = 1,
    class = 2,
    @"enum" = 3,
    interface = 4,
    @"struct" = 5,
    typeParameter = 6,
    parameter = 7,
    variable = 8,
    property = 9,
    enumMember = 10,
    event = 11,
    function = 12,
    method = 13,
    macro = 14,
    keyword = 15,
    modifier = 16,
    comment = 17,
    string = 18,
    number = 19,
    regexp = 20,
    operator = 21,
};

/// Semantic token modifiers (bit flags)
pub const SemanticTokenModifier = enum(u32) {
    declaration = 1 << 0, // 0x001
    definition = 1 << 1, // 0x002
    readonly = 1 << 2, // 0x004
    static = 1 << 3, // 0x008
    deprecated = 1 << 4, // 0x010
    abstract = 1 << 5, // 0x020
    async = 1 << 6, // 0x040
    modification = 1 << 7, // 0x080
    documentation = 1 << 8, // 0x100
    defaultLibrary = 1 << 9, // 0x200
};

/// Document highlight kind
pub const DocumentHighlightKind = enum(u32) {
    Text = 1,
    Read = 2,
    Write = 3,
};

/// Folding range kind
pub const FoldingRangeKind = enum {
    comment,
    imports,
    region,
};

pub const ResponseCallback = struct {
    ctx: *anyopaque,
    onHover: ?*const fn (ctx: *anyopaque, response: HoverResponse) void,
    onDefinition: ?*const fn (ctx: *anyopaque, response: DefinitionResponse) void,
    onCompletion: ?*const fn (ctx: *anyopaque, response: CompletionResponse) void,
    onSignatureHelp: ?*const fn (ctx: *anyopaque, response: SignatureHelpResponse) void,
    onInlayHints: ?*const fn (ctx: *anyopaque, response: InlayHintsResponse) void,
    onSelectionRange: ?*const fn (ctx: *anyopaque, response: SelectionRangeResponse) void,
    onCodeActions: ?*const fn (ctx: *anyopaque, response: CodeActionsResponse) void,
};

pub const PendingRequest = struct {
    id: u32,
    kind: RequestKind,

    pub const RequestKind = enum {
        hover,
        definition,
        completion,
        signature_help,
        inlay_hints,
        document_highlight,
        folding_range,
        prepare_rename,
        rename,
        semantic_tokens,
        selection_range,
        code_actions,
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
    initialized: std.atomic.Value(bool),
    diagnostics_sink: ?DiagnosticsSink,
    response_callback: ?ResponseCallback,
    pending_requests: std.ArrayList(PendingRequest),
    pending_mutex: std.Thread.Mutex,
    reader_thread: ?std.Thread,
    running: std.atomic.Value(bool),

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
            .initialized = std.atomic.Value(bool).init(false),
            .diagnostics_sink = null,
            .response_callback = null,
            .pending_requests = .empty,
            .pending_mutex = .{},
            .reader_thread = null,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Client) void {
        self.stopReaderLoop();
        self.pending_mutex.lock();
        self.pending_mutex.unlock();
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
        return self.initialized.load(.acquire);
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

        self.pending_mutex.lock();
        defer self.pending_mutex.unlock();
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

        // Track pending request for response handling
        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .completion,
            });
        }

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
        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .hover,
            });
        }

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
        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .definition,
            });
        }

        return id;
    }

    pub fn requestSignatureHelp(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/signatureHelp",
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
        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .signature_help,
            });
        }

        return id;
    }

    pub fn requestInlayHints(self: *Client, uri: []const u8, start_line: u32, end_line: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/inlayHint",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                range: struct {
                    start: struct { line: u32, character: u32 },
                    end: struct { line: u32, character: u32 },
                },
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
                .range = .{
                    .start = .{ .line = start_line, .character = 0 },
                    .end = .{ .line = end_line, .character = 0 },
                },
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .inlay_hints,
            });
        }

        return id;
    }

    pub fn requestSelectionRange(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/selectionRange",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                positions: []const struct { line: u32, character: u32 },
            };
        };

        const positions = [_]struct { line: u32, character: u32 }{
            .{ .line = line, .character = character },
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
                .positions = &positions,
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .selection_range,
            });
        }

        return id;
    }

    pub fn requestCodeActions(self: *Client, uri: []const u8, start_line: u32, start_char: u32, end_line: u32, end_char: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/codeAction",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                range: struct {
                    start: struct { line: u32, character: u32 },
                    end: struct { line: u32, character: u32 },
                },
                context: struct {
                    diagnostics: []const u8 = &[_]u8{},
                },
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
                .range = .{
                    .start = .{ .line = start_line, .character = start_char },
                    .end = .{ .line = end_line, .character = end_char },
                },
                .context = .{},
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .code_actions,
            });
        }

        return id;
    }

    /// Request document highlights for a symbol at the given position
    pub fn requestDocumentHighlight(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/documentHighlight",
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

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .document_highlight,
            });
        }

        return id;
    }

    /// Request folding ranges for a document
    pub fn requestFoldingRange(self: *Client, uri: []const u8) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/foldingRange",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .folding_range,
            });
        }

        return id;
    }

    /// Prepare rename - validates that rename is possible at the given position
    pub fn requestPrepareRename(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/prepareRename",
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

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .prepare_rename,
            });
        }

        return id;
    }

    /// Rename - renames symbol at position across all open documents
    pub fn requestRename(self: *Client, uri: []const u8, line: u32, character: u32, new_name: []const u8) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/rename",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
                position: struct { line: u32, character: u32 },
                newName: []const u8,
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
                .position = .{ .line = line, .character = character },
                .newName = new_name,
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .rename,
            });
        }

        return id;
    }

    /// Request semantic tokens for full document
    pub fn requestSemanticTokensFull(self: *Client, uri: []const u8) Error!u32 {
        const id = self.next_id;
        self.next_id += 1;

        const Request = struct {
            jsonrpc: []const u8 = "2.0",
            id: u32,
            method: []const u8 = "textDocument/semanticTokens/full",
            params: Params,

            const Params = struct {
                textDocument: struct { uri: []const u8 },
            };
        };

        const request = Request{
            .id = id,
            .params = .{
                .textDocument = .{ .uri = uri },
            },
        };

        const body = try self.jsonStringify(request);
        defer self.allocator.free(body);

        try self.writeMessage(body);

        {
            self.pending_mutex.lock();
            defer self.pending_mutex.unlock();
            try self.pending_requests.append(self.allocator, .{
                .id = id,
                .kind = .semantic_tokens,
            });
        }

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
                if (self.tryCompleteInitialize(response_id)) {
                    return;
                }

                // Check for hover/definition/completion responses
                if (object.get("result")) |result_node| {
                    if (self.takePendingRequest(response_id)) |kind| {
                        try self.dispatchResponse(response_id, kind, result_node);
                    }
                }
            }
        }

        if (object.get("method")) |method_node| {
            if (method_node == .string) {
                if (std.mem.eql(u8, method_node.string, "textDocument/publishDiagnostics")) {
                    if (object.get("params")) |params_node| {
                        try self.handleDiagnostics(params_node);
                    }
                }
            }
        }
    }

    fn dispatchResponse(self: *Client, id: u32, kind: PendingRequest.RequestKind, result: std.json.Value) Error!void {
        switch (kind) {
            .hover => try self.handleHoverResponse(id, result),
            .definition => try self.handleDefinitionResponse(id, result),
            .completion => try self.handleCompletionResponse(id, result),
            .signature_help => try self.handleSignatureHelpResponse(id, result),
            .inlay_hints => try self.handleInlayHintsResponse(id, result),
            .selection_range => try self.handleSelectionRangeResponse(id, result),
            .code_actions => try self.handleCodeActionsResponse(id, result),
            .document_highlight => try self.handleDocumentHighlightResponse(id, result),
            .folding_range => try self.handleFoldingRangeResponse(id, result),
            .prepare_rename => try self.handlePrepareRenameResponse(id, result),
            .rename => try self.handleRenameResponse(id, result),
            .semantic_tokens => try self.handleSemanticTokensResponse(id, result),
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

    fn handleCompletionResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        const callback = self.response_callback orelse return;
        if (callback.onCompletion == null) return;

        const response = CompletionResponse{
            .request_id = id,
            .result = result,
        };

        callback.onCompletion.?(callback.ctx, response);
    }

    fn handleSignatureHelpResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        const callback = self.response_callback orelse return;
        if (callback.onSignatureHelp == null) return;

        const response = SignatureHelpResponse{
            .request_id = id,
            .result = result,
        };

        callback.onSignatureHelp.?(callback.ctx, response);
    }

    fn handleInlayHintsResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        const callback = self.response_callback orelse return;
        if (callback.onInlayHints == null) return;

        const response = InlayHintsResponse{
            .request_id = id,
            .result = result,
        };

        callback.onInlayHints.?(callback.ctx, response);
    }

    fn handleSelectionRangeResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        const callback = self.response_callback orelse return;
        if (callback.onSelectionRange == null) return;

        const response = SelectionRangeResponse{
            .request_id = id,
            .result = result,
        };

        callback.onSelectionRange.?(callback.ctx, response);
    }

    fn handleCodeActionsResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        const callback = self.response_callback orelse return;
        if (callback.onCodeActions == null) return;

        const response = CodeActionsResponse{
            .request_id = id,
            .result = result,
        };

        callback.onCodeActions.?(callback.ctx, response);
    }

    fn handleDocumentHighlightResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        _ = self;
        _ = id;
        _ = result;
        // TODO: Add callback support for document highlights
        // Response format: DocumentHighlight[] | null
        // DocumentHighlight = { range: Range, kind?: DocumentHighlightKind }
        // DocumentHighlightKind = 1 (Text) | 2 (Read) | 3 (Write)
    }

    fn handleFoldingRangeResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        _ = self;
        _ = id;
        _ = result;
        // TODO: Add callback support for folding ranges
        // Response format: FoldingRange[] | null
        // FoldingRange = { startLine: u32, endLine: u32, kind?: string }
    }

    fn handlePrepareRenameResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        _ = self;
        _ = id;
        _ = result;
        // TODO: Add callback support for prepare rename
        // Response format: Range | { range: Range, placeholder: string } | null
    }

    fn handleRenameResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        _ = self;
        _ = id;
        _ = result;
        // TODO: Add callback support for rename
        // Response format: WorkspaceEdit | null
        // WorkspaceEdit = { changes?: { [uri: string]: TextEdit[] } }
    }

    fn handleSemanticTokensResponse(self: *Client, id: u32, result: std.json.Value) Error!void {
        _ = self;
        _ = id;
        _ = result;
        // TODO: Add callback support for semantic tokens
        // Response format: { data: u32[] } (encoded tokens)
        // Format: [deltaLine, deltaStart, length, tokenType, tokenModifiers]
    }

    fn handleDiagnostics(self: *Client, params: std.json.Value) Error!void {
        const sink = self.diagnostics_sink orelse return;
        try sink.handleFn(sink.ctx, params);
    }

    fn tryCompleteInitialize(self: *Client, response_id: u32) bool {
        self.pending_mutex.lock();
        defer self.pending_mutex.unlock();
        if (self.pending_initialize) |expected| {
            if (response_id == expected) {
                self.pending_initialize = null;
                self.initialized.store(true, .release);
                return true;
            }
        }
        return false;
    }

    fn takePendingRequest(self: *Client, id: u32) ?PendingRequest.RequestKind {
        self.pending_mutex.lock();
        defer self.pending_mutex.unlock();
        for (self.pending_requests.items, 0..) |req, i| {
            if (req.id == id) {
                const kind = req.kind;
                _ = self.pending_requests.swapRemove(i);
                return kind;
            }
        }
        return null;
    }

    pub fn startReaderLoop(self: *Client) !void {
        if (self.reader_thread != null) return;
        self.running.store(true, .release);
        self.reader_thread = try std.Thread.spawn(.{}, readerLoop, .{self});
    }

    pub fn stopReaderLoop(self: *Client) void {
        self.running.store(false, .release);
        if (self.reader_thread) |thread| {
            thread.join();
            self.reader_thread = null;
        }
    }

    fn readerLoop(self: *Client) void {
        while (self.running.load(.acquire)) {
            self.poll() catch |err| {
                if (err == error.EndOfStream) {
                    break;
                }
                std.log.debug("LSP client reader error: {}", .{err});
            };
        }
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
    try std.testing.expect(sink.last_uri != null);
    try std.testing.expectEqualStrings("file:///test.zig", sink.last_uri.?);
    try std.testing.expectEqual(@as(usize, 1), sink.last_count);
}

const MockTransport = struct {
    allocator: std.mem.Allocator,
    written: std.ArrayList(u8),
    incoming: std.ArrayList(u8),
    read_cursor: usize,

    fn init(allocator: std.mem.Allocator) MockTransport {
        return .{
            .allocator = allocator,
            .written = std.ArrayList(u8){},
            .incoming = std.ArrayList(u8){},
            .read_cursor = 0,
        };
    }

    fn deinit(self: *MockTransport) void {
        self.written.deinit(self.allocator);
        self.incoming.deinit(self.allocator);
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
        self.incoming.appendSlice(self.allocator, data) catch unreachable;
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
        self.written.appendSlice(self.allocator, buffer) catch return TransportError.WriteFailure;
        return buffer.len;
    }

    fn fromCtx(ctx: *anyopaque) *MockTransport {
        return @ptrCast(@alignCast(ctx));
    }
};

const CaptureSink = struct {
    allocator: std.mem.Allocator,
    last_uri: ?[]u8,
    last_count: usize,

    fn init(allocator: std.mem.Allocator) CaptureSink {
        return .{ .allocator = allocator, .last_uri = null, .last_count = 0 };
    }

    fn deinit(self: *CaptureSink) void {
        if (self.last_uri) |uri| self.allocator.free(uri);
        self.* = undefined;
    }

    fn sink(self: *CaptureSink) DiagnosticsSink {
        return .{
            .ctx = self,
            .handleFn = log,
        };
    }

    fn log(ctx: *anyopaque, params: std.json.Value) !void {
        const self = fromCtx(ctx);

        if (self.last_uri) |uri| {
            self.allocator.free(uri);
            self.last_uri = null;
        }
        self.last_count = 0;

        if (params != .object) return;
        const object = params.object;

        var uri_slice: []const u8 = "<unknown>";
        if (object.get("uri")) |uri_node| {
            if (uri_node == .string) {
                uri_slice = uri_node.string;
            }
        }

        if (object.get("diagnostics")) |diag_node| {
            if (diag_node == .array) {
                self.last_count = diag_node.array.items.len;
            }
        }

        self.last_uri = try self.allocator.dupe(u8, uri_slice);
    }

    fn fromCtx(ctx: *anyopaque) *CaptureSink {
        return @ptrCast(@alignCast(ctx));
    }
};

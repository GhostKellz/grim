//! core/lsp_manager.zig
//! Grim LSP integration with process-backed transports, async response handling,
//! and diagnostics caching.

const std = @import("std");
const grim = @import("grim");

const lsp_module = if (@hasDecl(grim, "lsp"))
    grim.lsp
else
    @compileError("grim.lsp module not available. Ensure build.zig imports grim_lsp.");

const Client = lsp_module.Client;
const Transport = lsp_module.client.Transport;
const TransportError = lsp_module.client.TransportError;
const log = std.log.scoped(.lsp_manager);

const response_timeout_ns: u64 = 3 * std.time.ns_per_s;
const response_poll_ns: u64 = 5 * std.time.ns_per_ms;

pub const LSPManager = struct {
    allocator: std.mem.Allocator,
    servers: std.StringHashMap(*ServerEntry),
    language_servers: std.StringHashMap(*ServerEntry),
    documents: std.StringHashMap(DocumentRecord),
    response_buffer: std.ArrayList(u8),

    const DocumentRecord = struct {
        path: []const u8,
        language: []const u8,
        uri: []const u8,
        server: *ServerEntry,
        client: *Client,
        version: u32,
    };

    const ServerEntry = struct {
        allocator: std.mem.Allocator,
        manager: *LSPManager,
        name: []u8,
        command: []const []const u8,
        process: std.process.Child,
        client: Client,
        responses: std.AutoHashMap(u32, []u8),
        diagnostics: std.StringHashMap([]u8),
        mutex: std.Thread.Mutex,

        fn init(manager: *LSPManager, server_name: []const u8) !*ServerEntry {
            const allocator = manager.allocator;

            var entry = try allocator.create(ServerEntry);
            errdefer allocator.destroy(entry);

            entry.* = .{
                .allocator = allocator,
                .manager = manager,
                .name = try allocator.dupe(u8, server_name),
                .command = undefined,
                .process = undefined,
                .client = undefined,
                .responses = std.AutoHashMap(u32, []u8).init(allocator),
                .diagnostics = std.StringHashMap([]u8).init(allocator),
                .mutex = .{},
            };
            errdefer allocator.free(entry.name);
            errdefer entry.responses.deinit();
            errdefer entry.diagnostics.deinit();

            const command_storage = try allocator.alloc([]const u8, 1);
            errdefer allocator.free(command_storage);
            const command_mut = @constCast(command_storage);
            command_mut[0] = entry.name;
            entry.command = command_storage;

            entry.process = std.process.Child.init(entry.command, allocator);
            entry.process.stdin_behavior = .Pipe;
            entry.process.stdout_behavior = .Pipe;
            entry.process.stderr_behavior = .Inherit;

            entry.process.spawn() catch |err| {
                return err;
            };
            errdefer {
                if (entry.process.stdin) |stdin_file| stdin_file.close();
                if (entry.process.stdout) |stdout_file| stdout_file.close();
                if (entry.process.stderr) |stderr_file| stderr_file.close();
                _ = entry.process.kill() catch {};
                _ = entry.process.wait() catch {};
            }

            if (entry.process.stdin == null or entry.process.stdout == null) {
                return error.TransportUnavailable;
            }

            const transport = Transport{
                .ctx = entry,
                .readFn = ServerEntry.transportRead,
                .writeFn = ServerEntry.transportWrite,
            };

            entry.client = Client.init(allocator, transport);
            errdefer entry.client.deinit();

            entry.installCallbacks();

            const root_path = try manager.currentWorkspacePath();
            defer allocator.free(root_path);

            const root_uri = try encodeFileUri(allocator, root_path);
            defer allocator.free(root_uri);

            _ = try entry.client.sendInitialize(root_uri);
            try entry.client.startReaderLoop();
            try entry.waitUntilInitialized();

            return entry;
        }

        fn deinit(self: *ServerEntry) void {
            self.client.deinit();

            if (self.process.stdin) |stdin_file| stdin_file.close();
            if (self.process.stdout) |stdout_file| stdout_file.close();
            if (self.process.stderr) |stderr_file| stderr_file.close();

            _ = self.process.kill() catch {};
            _ = self.process.wait() catch {};

            var resp_it = self.responses.iterator();
            while (resp_it.next()) |entry| {
                self.allocator.free(entry.value_ptr.*);
            }
            self.responses.deinit();

            var diag_it = self.diagnostics.iterator();
            while (diag_it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.diagnostics.deinit();

            self.allocator.free(self.command);
            self.allocator.free(self.name);
        }

        fn installCallbacks(self: *ServerEntry) void {
            self.client.setResponseCallback(.{
                .ctx = self,
                .onHover = handleHover,
                .onDefinition = handleDefinition,
                .onCompletion = handleCompletion,
                .onSignatureHelp = null,
                .onInlayHints = null,
                .onSelectionRange = null,
                .onCodeActions = null,
            });
            self.client.setDiagnosticsSink(.{
                .ctx = self,
                .handleFn = handleDiagnostics,
            });
        }

        fn waitUntilInitialized(self: *ServerEntry) !void {
            const deadline = std.time.nanoTimestamp() + response_timeout_ns;
            while (!self.client.isInitialized()) {
                if (std.time.nanoTimestamp() >= deadline) {
                    return error.InitializationTimeout;
                }
                std.Thread.sleep(response_poll_ns);
            }
        }

        fn storeResponse(self: *ServerEntry, request_id: u32, payload: []u8) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const gop = try self.responses.getOrPut(request_id);
            if (gop.found_existing) {
                self.allocator.free(gop.value_ptr.*);
            }
            gop.value_ptr.* = payload;
        }

        fn fetchResponse(self: *ServerEntry, request_id: u32) ?[]u8 {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.responses.fetchRemove(request_id)) |kv| {
                return kv.value;
            }
            return null;
        }

        fn storeDiagnostics(self: *ServerEntry, path: []u8, payload: []u8) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const gop = try self.diagnostics.getOrPut(path);
            if (gop.found_existing) {
                self.allocator.free(path);
                self.allocator.free(gop.value_ptr.*);
            } else {
                gop.key_ptr.* = path;
            }
            gop.value_ptr.* = payload;
        }

        fn getDiagnostics(self: *ServerEntry, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.diagnostics.get(path)) |data| {
                return try allocator.dupe(u8, data);
            }
            return try allocator.dupe(u8, "[]");
        }

        fn clearDiagnostics(self: *ServerEntry, path: []const u8) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.diagnostics.fetchRemove(path)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value);
            }
        }

        fn fromCtx(ctx: *anyopaque) *ServerEntry {
            const raw: *ServerEntry = @ptrFromInt(@intFromPtr(ctx));
            return @alignCast(raw);
        }

        fn transportRead(ctx: *anyopaque, buffer: []u8) TransportError!usize {
            const self = fromCtx(ctx);
            const stdout_file = self.process.stdout orelse return TransportError.ReadFailure;
            return stdout_file.read(buffer) catch return TransportError.ReadFailure;
        }

        fn transportWrite(ctx: *anyopaque, buffer: []const u8) TransportError!usize {
            const self = fromCtx(ctx);
            const stdin_file = self.process.stdin orelse return TransportError.WriteFailure;
            return stdin_file.write(buffer) catch return TransportError.WriteFailure;
        }

        fn handleHover(ctx: *anyopaque, response: lsp_module.HoverResponse) void {
            const self = fromCtx(ctx);
            const data = self.allocator.dupe(u8, response.contents) catch {
                log.warn("hover allocation failed for {s}", .{self.name});
                return;
            };
            self.storeResponse(response.request_id, data) catch |err| {
                log.warn("hover store failed for {s}: {any}", .{ self.name, err });
                self.allocator.free(data);
            };
        }

        fn handleDefinition(ctx: *anyopaque, response: lsp_module.DefinitionResponse) void {
            const self = fromCtx(ctx);
            const payload = stringifyAlloc(self.allocator, .{
                .uri = response.uri,
                .line = response.line,
                .character = response.character,
            }) catch {
                log.warn("definition encode failed for {s}", .{self.name});
                return;
            };
            self.storeResponse(response.request_id, payload) catch |err| {
                log.warn("definition store failed for {s}: {any}", .{ self.name, err });
                self.allocator.free(payload);
            };
        }

        fn handleCompletion(ctx: *anyopaque, response: lsp_module.CompletionResponse) void {
            const self = fromCtx(ctx);
            const payload = stringifyAlloc(self.allocator, response.result) catch {
                log.warn("completion encode failed for {s}", .{self.name});
                return;
            };
            self.storeResponse(response.request_id, payload) catch |err| {
                log.warn("completion store failed for {s}: {any}", .{ self.name, err });
                self.allocator.free(payload);
            };
        }

        fn diagnosticsUri(params: std.json.Value) ?[]const u8 {
            if (params != .object) return null;
            if (params.object.get("uri")) |node| {
                if (node == .string) return node.string;
            }
            return null;
        }

        fn handleDiagnostics(ctx: *anyopaque, params: std.json.Value) std.mem.Allocator.Error!void {
            const self = fromCtx(ctx);
            const uri = diagnosticsUri(params) orelse return;

            const path = decodeFileUri(self.allocator, uri) catch |err| {
                log.warn("diagnostics decode failed for {s}: {any}", .{ self.name, err });
                return;
            };
            errdefer self.allocator.free(path);

            const payload = stringifyAlloc(self.allocator, params) catch {
                return;
            };
            errdefer self.allocator.free(payload);

            self.storeDiagnostics(path, payload) catch |err| {
                log.warn("diagnostics store failed for {s}: {any}", .{ self.name, err });
                self.allocator.free(path);
                self.allocator.free(payload);
            };
        }

        fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
            var alloc_writer: std.Io.Writer.Allocating = .init(allocator);
            errdefer alloc_writer.deinit();

            var stream = std.json.Stringify{ .writer = &alloc_writer.writer, .options = .{} };
            stream.write(value) catch {
                return error.JsonStringifyFailed;
            };

            const payload = try alloc_writer.toOwnedSlice();
            alloc_writer.deinit();
            return payload;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !*LSPManager {
        const manager = try allocator.create(LSPManager);
        errdefer allocator.destroy(manager);

        manager.* = .{
            .allocator = allocator,
            .servers = std.StringHashMap(*ServerEntry).init(allocator),
            .language_servers = std.StringHashMap(*ServerEntry).init(allocator),
            .documents = std.StringHashMap(DocumentRecord).init(allocator),
            .response_buffer = std.ArrayList(u8).empty,
        };

        return manager;
    }

    pub fn deinit(self: *LSPManager) void {
        var doc_it = self.documents.iterator();
        while (doc_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.language);
            self.allocator.free(entry.value_ptr.uri);
        }
        self.documents.deinit();

        var lang_it = self.language_servers.iterator();
        while (lang_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.language_servers.deinit();

        var server_it = self.servers.iterator();
        while (server_it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.servers.deinit();

        self.response_buffer.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    pub fn ensureLanguage(self: *LSPManager, language: []const u8, server_name: []const u8) !*Client {
        const server = try self.ensureServer(server_name);

        const lang_gop = try self.language_servers.getOrPut(language);
        if (!lang_gop.found_existing) {
            lang_gop.key_ptr.* = try self.allocator.dupe(u8, language);
        }
        lang_gop.value_ptr.* = server;

        return &server.client;
    }

    pub fn didOpen(self: *LSPManager, language: []const u8, path: []const u8, content: []const u8) !void {
        const server = try self.serverForLanguage(language);

        const path_storage = try self.canonicalizePath(path);
        var path_owned = true;
        errdefer if (path_owned) self.allocator.free(path_storage);

        const uri = try encodeFileUri(self.allocator, path_storage);
        var uri_owned = true;
        errdefer if (uri_owned) self.allocator.free(uri);

        const language_copy = try self.allocator.dupe(u8, language);
        var language_owned = true;
        errdefer if (language_owned) self.allocator.free(language_copy);

        try server.client.sendDidOpen(uri, language, content);

        const doc_gop = try self.documents.getOrPut(path_storage);
        if (!doc_gop.found_existing) {
            doc_gop.key_ptr.* = path_storage;
            path_owned = false;
        } else {
            self.allocator.free(path_storage);
            path_owned = false;
            self.allocator.free(doc_gop.value_ptr.language);
            self.allocator.free(doc_gop.value_ptr.uri);
        }

        doc_gop.value_ptr.* = .{
            .path = doc_gop.key_ptr.*,
            .language = language_copy,
            .uri = uri,
            .server = server,
            .client = &server.client,
            .version = 1,
        };
        language_owned = false;
        uri_owned = false;
    }

    pub fn didChange(self: *LSPManager, path: []const u8, content: []const u8) !void {
        const record = try self.documentForPath(path);
        record.version += 1;
        try record.client.sendDidChange(record.uri, record.version, content);
    }

    pub fn didClose(self: *LSPManager, path: []const u8) !void {
        const canonical = try self.canonicalizePath(path);
        defer self.allocator.free(canonical);

        const entry = self.documents.getEntry(canonical) orelse return error.UnknownDocument;
        entry.value_ptr.server.clearDiagnostics(entry.value_ptr.path);

        self.allocator.free(entry.value_ptr.language);
        self.allocator.free(entry.value_ptr.uri);
        self.allocator.free(entry.key_ptr.*);
        self.documents.removeByPtr(entry.key_ptr);
    }

    pub fn requestCompletion(self: *LSPManager, path: []const u8, line: u32, character: u32) ![]u8 {
        const record = try self.documentForPath(path);
        const request_id = try record.client.requestCompletion(record.uri, line, character);
        return try awaitResponse(record.server, request_id, "completion");
    }

    pub fn requestHover(self: *LSPManager, path: []const u8, line: u32, character: u32) ![]u8 {
        const record = try self.documentForPath(path);
        const request_id = try record.client.requestHover(record.uri, line, character);
        return try awaitResponse(record.server, request_id, "hover");
    }

    pub fn requestDefinition(self: *LSPManager, path: []const u8, line: u32, character: u32) ![]u8 {
        const record = try self.documentForPath(path);
        const request_id = try record.client.requestDefinition(record.uri, line, character);
        return try awaitResponse(record.server, request_id, "definition");
    }

    pub fn requestDiagnostics(self: *LSPManager, path: []const u8) ![]u8 {
        const record = try self.documentForPath(path);
        return try record.server.getDiagnostics(self.allocator, record.path);
    }

    pub fn writeResponse(self: *LSPManager, bytes: []const u8) ![*]const u8 {
        self.response_buffer.clearRetainingCapacity();
        try self.response_buffer.appendSlice(self.allocator, bytes);
        try self.response_buffer.append(self.allocator, 0);
        return self.response_buffer.items.ptr;
    }

    fn ensureServer(self: *LSPManager, server_name: []const u8) !*ServerEntry {
        if (self.servers.get(server_name)) |existing| {
            return existing;
        }

        const server = try ServerEntry.init(self, server_name);
        errdefer {
            server.deinit();
            self.allocator.destroy(server);
        }

        const gop = try self.servers.getOrPut(server_name);
        if (gop.found_existing) {
            server.deinit();
            self.allocator.destroy(server);
            return gop.value_ptr.*;
        }

        gop.key_ptr.* = server.name;
        gop.value_ptr.* = server;
        return server;
    }

    fn serverForLanguage(self: *LSPManager, language: []const u8) !*ServerEntry {
        return self.language_servers.get(language) orelse return error.UnknownLanguage;
    }

    fn documentForPath(self: *LSPManager, path: []const u8) !*DocumentRecord {
        const canonical = try self.canonicalizePath(path);
        defer self.allocator.free(canonical);
        const entry = self.documents.getEntry(canonical) orelse return error.UnknownDocument;
        return entry.value_ptr;
    }

    fn canonicalizePath(self: *LSPManager, path: []const u8) ![]u8 {
        if (std.mem.startsWith(u8, path, "file://")) {
            return try decodeFileUri(self.allocator, path);
        }

        if (std.fs.path.isAbsolute(path)) {
            return try self.allocator.dupe(u8, path);
        }

        const cwd = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd);
        return try std.fs.path.join(self.allocator, &.{ cwd, path });
    }

    fn currentWorkspacePath(self: *LSPManager) ![]u8 {
        return std.process.getCwdAlloc(self.allocator);
    }
};

fn awaitResponse(server: *LSPManager.ServerEntry, request_id: u32, context: []const u8) ![]u8 {
    const deadline = std.time.nanoTimestamp() + response_timeout_ns;
    while (true) {
        if (server.fetchResponse(request_id)) |payload| {
            return payload;
        }

        if (std.time.nanoTimestamp() >= deadline) {
            log.warn("LSP {s} response timed out for {s}", .{ context, server.name });
            return error.ResponseTimeout;
        }

        std.Thread.sleep(response_poll_ns);
    }
}

fn isUriSafeByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or switch (byte) {
        '-', '_', '.', '~', '/', ':' => true,
        else => false,
    };
}

fn appendPercentEncoded(builder: *std.ArrayList(u8), allocator: std.mem.Allocator, byte: u8) !void {
    const hex = "0123456789ABCDEF";
    const buf = [_]u8{ '%', hex[byte >> 4], hex[byte & 0xF] };
    try builder.appendSlice(allocator, buf[0..]);
}

fn encodeFileUri(allocator: std.mem.Allocator, absolute_path: []const u8) ![]u8 {
    var builder: std.ArrayList(u8) = .empty;
    defer builder.deinit(allocator);

    try builder.appendSlice(allocator, "file://");
    for (absolute_path) |byte| {
        if (isUriSafeByte(byte)) {
            try builder.append(allocator, byte);
        } else {
            try appendPercentEncoded(&builder, allocator, byte);
        }
    }

    return try builder.toOwnedSlice(allocator);
}

fn hexNibble(ch: u8) ?u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'A'...'F' => ch - 'A' + 10,
        'a'...'f' => ch - 'a' + 10,
        else => null,
    };
}

fn percentDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var builder: std.ArrayList(u8) = .empty;
    errdefer builder.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            if (hexNibble(input[i + 1])) |hi| {
                if (hexNibble(input[i + 2])) |lo| {
                    const value: u8 = (hi << 4) | lo;
                    try builder.append(allocator, value);
                    i += 3;
                    continue;
                }
            }
        }

        try builder.append(allocator, input[i]);
        i += 1;
    }

    return try builder.toOwnedSlice(allocator);
}

fn decodeFileUri(allocator: std.mem.Allocator, uri: []const u8) ![]u8 {
    const prefix = "file://";
    if (!std.mem.startsWith(u8, uri, prefix)) {
        return try allocator.dupe(u8, uri);
    }
    const path_part = uri[prefix.len..];
    return try percentDecode(allocator, path_part);
}

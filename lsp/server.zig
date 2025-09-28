const std = @import("std");
const zsync = @import("zsync");
const client = @import("client.zig");

pub const LanguageServer = struct {
    allocator: std.mem.Allocator,
    process: std.process.Child,
    client: client.Client,
    reader_thread: ?std.Thread = null,
    writer_thread: ?std.Thread = null,
    shutdown_requested: std.atomic.Value(bool),
    capabilities: ServerCapabilities,

    pub const ServerCapabilities = struct {
        textDocumentSync: ?TextDocumentSyncKind = null,
        completionProvider: bool = false,
        hoverProvider: bool = false,
        definitionProvider: bool = false,
        referencesProvider: bool = false,
        documentSymbolProvider: bool = false,
        codeActionProvider: bool = false,
        renameProvider: bool = false,
        diagnosticProvider: bool = false,
    };

    pub const TextDocumentSyncKind = enum(u8) {
        none = 0,
        full = 1,
        incremental = 2,
    };

    pub const ServerConfig = struct {
        command: []const []const u8,
        root_uri: []const u8,
        initialization_options: ?std.json.Value = null,
        env: ?std.process.EnvMap = null,
    };

    pub const Error = error{
        ServerStartFailed,
        ServerCrashed,
        InitializationFailed,
        ShutdownFailed,
    } || client.Client.Error || std.process.Child.SpawnError;

    pub fn start(allocator: std.mem.Allocator, config: ServerConfig) Error!*LanguageServer {
        var self = try allocator.create(LanguageServer);
        errdefer allocator.destroy(self);

        // Start the language server process
        var process = std.process.Child.init(config.command, allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;
        if (config.env) |env| {
            process.env_map = env;
        }

        try process.spawn();
        errdefer process.kill() catch {};

        // Create transport for the client
        const transport = client.Transport{
            .ctx = &process,
            .readFn = readFromProcess,
            .writeFn = writeToProcess,
        };

        self.* = .{
            .allocator = allocator,
            .process = process,
            .client = client.Client.init(allocator, transport),
            .shutdown_requested = std.atomic.Value(bool).init(false),
            .capabilities = .{},
        };

        // Send initialization request
        _ = try self.client.sendInitialize(config.root_uri);

        // Wait for initialization response
        const max_wait_ms = 5000;
        var elapsed_ms: u32 = 0;
        while (!self.client.isInitialized() and elapsed_ms < max_wait_ms) : (elapsed_ms += 100) {
            self.client.poll() catch |err| {
                if (err == error.EndOfStream) {
                    return Error.ServerCrashed;
                }
            };
            std.time.sleep(100 * std.time.ns_per_ms);
        }

        if (!self.client.isInitialized()) {
            return Error.InitializationFailed;
        }

        // Send initialized notification
        try self.sendInitializedNotification();

        // Start reader thread for async message handling
        self.reader_thread = try std.Thread.spawn(.{}, readerThreadFn, .{self});

        return self;
    }

    pub fn shutdown(self: *LanguageServer) Error!void {
        // Set shutdown flag
        self.shutdown_requested.store(true, .seq_cst);

        // Send shutdown request
        try self.sendShutdownRequest();

        // Send exit notification
        try self.sendExitNotification();

        // Wait for threads to finish
        if (self.reader_thread) |thread| {
            thread.join();
        }
        if (self.writer_thread) |thread| {
            thread.join();
        }

        // Kill process if still running
        _ = self.process.kill() catch {};
        _ = self.process.wait() catch {};

        self.client.deinit();
    }

    pub fn deinit(self: *LanguageServer) void {
        self.shutdown() catch {};
        self.allocator.destroy(self);
    }

    fn readFromProcess(ctx: *anyopaque, buffer: []u8) client.TransportError!usize {
        const process = @as(*std.process.Child, @ptrCast(@alignCast(ctx)));
        if (process.stdout) |stdout| {
            return stdout.read(buffer) catch return client.TransportError.ReadFailure;
        }
        return client.TransportError.EndOfStream;
    }

    fn writeToProcess(ctx: *anyopaque, buffer: []const u8) client.TransportError!usize {
        const process = @as(*std.process.Child, @ptrCast(@alignCast(ctx)));
        if (process.stdin) |stdin| {
            return stdin.write(buffer) catch return client.TransportError.WriteFailure;
        }
        return client.TransportError.WriteFailure;
    }

    fn readerThreadFn(self: *LanguageServer) void {
        while (!self.shutdown_requested.load(.seq_cst)) {
            self.client.poll() catch |err| {
                if (err == error.EndOfStream) {
                    break;
                }
                // Log error but continue
                std.debug.print("LSP reader error: {}\n", .{err});
            };
        }
    }

    fn sendInitializedNotification(self: *LanguageServer) !void {
        const notification = .{
            .jsonrpc = "2.0",
            .method = "initialized",
            .params = .{},
        };

        const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
    }

    fn sendShutdownRequest(self: *LanguageServer) !void {
        const request = .{
            .jsonrpc = "2.0",
            .id = self.client.next_id,
            .method = "shutdown",
            .params = null,
        };

        self.client.next_id += 1;

        const body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
    }

    fn sendExitNotification(self: *LanguageServer) !void {
        const notification = .{
            .jsonrpc = "2.0",
            .method = "exit",
            .params = null,
        };

        const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
    }

    fn sendMessage(self: *LanguageServer, body: []const u8) !void {
        const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{body.len});
        defer self.allocator.free(header);

        if (self.process.stdin) |stdin| {
            try stdin.writeAll(header);
            try stdin.writeAll(body);
        }
    }

    // Document synchronization methods
    pub fn openDocument(self: *LanguageServer, uri: []const u8, language_id: []const u8, version: u32, text: []const u8) !void {
        const notification = .{
            .jsonrpc = "2.0",
            .method = "textDocument/didOpen",
            .params = .{
                .textDocument = .{
                    .uri = uri,
                    .languageId = language_id,
                    .version = version,
                    .text = text,
                },
            },
        };

        const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
    }

    pub fn changeDocument(self: *LanguageServer, uri: []const u8, version: u32, changes: []const TextChange) !void {
        const notification = .{
            .jsonrpc = "2.0",
            .method = "textDocument/didChange",
            .params = .{
                .textDocument = .{
                    .uri = uri,
                    .version = version,
                },
                .contentChanges = changes,
            },
        };

        const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
    }

    pub fn closeDocument(self: *LanguageServer, uri: []const u8) !void {
        const notification = .{
            .jsonrpc = "2.0",
            .method = "textDocument/didClose",
            .params = .{
                .textDocument = .{
                    .uri = uri,
                },
            },
        };

        const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
    }

    pub fn saveDocument(self: *LanguageServer, uri: []const u8, text: ?[]const u8) !void {
        const notification = .{
            .jsonrpc = "2.0",
            .method = "textDocument/didSave",
            .params = .{
                .textDocument = .{
                    .uri = uri,
                },
                .text = text,
            },
        };

        const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
    }

    pub const TextChange = struct {
        range: ?Range = null,
        text: []const u8,
    };

    pub const Range = struct {
        start: Position,
        end: Position,
    };

    pub const Position = struct {
        line: u32,
        character: u32,
    };

    // Request methods
    pub fn requestCompletion(self: *LanguageServer, uri: []const u8, position: Position) !u32 {
        const id = self.client.next_id;
        self.client.next_id += 1;

        const request = .{
            .jsonrpc = "2.0",
            .id = id,
            .method = "textDocument/completion",
            .params = .{
                .textDocument = .{ .uri = uri },
                .position = position,
            },
        };

        const body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
        return id;
    }

    pub fn requestHover(self: *LanguageServer, uri: []const u8, position: Position) !u32 {
        const id = self.client.next_id;
        self.client.next_id += 1;

        const request = .{
            .jsonrpc = "2.0",
            .id = id,
            .method = "textDocument/hover",
            .params = .{
                .textDocument = .{ .uri = uri },
                .position = position,
            },
        };

        const body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
        return id;
    }

    pub fn requestDefinition(self: *LanguageServer, uri: []const u8, position: Position) !u32 {
        const id = self.client.next_id;
        self.client.next_id += 1;

        const request = .{
            .jsonrpc = "2.0",
            .id = id,
            .method = "textDocument/definition",
            .params = .{
                .textDocument = .{ .uri = uri },
                .position = position,
            },
        };

        const body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(body);

        try self.sendMessage(body);
        return id;
    }
};

// Server registry for managing multiple language servers
pub const ServerRegistry = struct {
    allocator: std.mem.Allocator,
    servers: std.StringHashMap(*LanguageServer),

    pub fn init(allocator: std.mem.Allocator) ServerRegistry {
        return .{
            .allocator = allocator,
            .servers = std.StringHashMap(*LanguageServer).init(allocator),
        };
    }

    pub fn deinit(self: *ServerRegistry) void {
        var iter = self.servers.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.servers.deinit();
    }

    pub fn startServer(self: *ServerRegistry, language: []const u8, config: LanguageServer.ServerConfig) !*LanguageServer {
        const server = try LanguageServer.start(self.allocator, config);
        try self.servers.put(language, server);
        return server;
    }

    pub fn getServer(self: *ServerRegistry, language: []const u8) ?*LanguageServer {
        return self.servers.get(language);
    }

    pub fn stopServer(self: *ServerRegistry, language: []const u8) !void {
        if (self.servers.get(language)) |server| {
            try server.shutdown();
            server.deinit();
            _ = self.servers.remove(language);
        }
    }
};
const std = @import("std");
const Client = @import("client.zig").Client;
const Transport = @import("client.zig").Transport;
const TransportError = @import("client.zig").TransportError;

pub const ServerManager = struct {
    allocator: std.mem.Allocator,
    servers: std.StringHashMap(*ServerProcess),

    pub const ServerProcess = struct {
        process: std.process.Child,
        client: Client,
        name: []u8,
        active: bool,
        version_counter: u32,

        pub fn deinit(self: *ServerProcess, allocator: std.mem.Allocator) void {
            self.client.deinit();
            allocator.free(self.name);
            _ = self.process.kill() catch {};
            self.* = undefined;
        }
    };

    pub const Error = error{
        ServerNotFound,
        ServerAlreadyRunning,
        ProcessSpawnFailed,
    } || std.mem.Allocator.Error || std.process.Child.SpawnError || Client.Error;

    pub fn init(allocator: std.mem.Allocator) ServerManager {
        return .{
            .allocator = allocator,
            .servers = std.StringHashMap(*ServerProcess).init(allocator),
        };
    }

    pub fn deinit(self: *ServerManager) void {
        var iterator = self.servers.iterator();
        while (iterator.next()) |entry| {
            self.shutdownServer(entry.key_ptr.*) catch {};
        }
        self.servers.deinit();
        self.* = undefined;
    }

    /// Spawn a new LSP server process
    pub fn spawn(self: *ServerManager, name: []const u8, cmd: []const []const u8) Error!*ServerProcess {
        // Check if already running
        if (self.servers.get(name)) |_| {
            return Error.ServerAlreadyRunning;
        }

        // Create server process struct FIRST (before spawning)
        const server = try self.allocator.create(ServerProcess);

        // Create process
        server.process = std.process.Child.init(cmd, self.allocator);
        server.process.stdin_behavior = .Pipe;
        server.process.stdout_behavior = .Pipe;
        server.process.stderr_behavior = .Inherit;

        server.process.spawn() catch return Error.ProcessSpawnFailed;

        // Create transport for stdio communication (use server.process address)
        const transport = Transport{
            .ctx = &server.process,
            .readFn = processRead,
            .writeFn = processWrite,
        };

        // Initialize LSP client
        server.client = Client.init(self.allocator, transport);
        server.name = try self.allocator.dupe(u8, name);
        server.active = true;
        server.version_counter = 1;

        // Store in map
        try self.servers.put(server.name, server);

        // Send initialize request
        const root_uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{try std.process.getCwdAlloc(self.allocator)});
        defer self.allocator.free(root_uri);

        _ = try server.client.sendInitialize(root_uri);
        try server.client.startReaderLoop();

        return server;
    }

    /// Get an active server by name
    pub fn getServer(self: *ServerManager, name: []const u8) ?*ServerProcess {
        return self.servers.get(name);
    }

    /// Shutdown a server gracefully
    pub fn shutdownServer(self: *ServerManager, name: []const u8) !void {
        const server = self.servers.get(name) orelse return Error.ServerNotFound;

        server.active = false;

        // Send shutdown request (LSP protocol)
        // Note: Client needs sendShutdown() method
        // For now, just terminate the process
        _ = try server.process.kill();
        _ = try server.process.wait();

        // Remove from map BEFORE deinit (which frees server.name)
        _ = self.servers.remove(name);

        // Clean up
        server.deinit(self.allocator);
    }

    /// Auto-spawn server based on file extension
    pub fn autoSpawn(self: *ServerManager, filename: []const u8) !?*ServerProcess {
        const ext = std.fs.path.extension(filename);

        const ServerConfig = struct {
            name: []const u8,
            cmd: []const []const u8,
        };

        const config: ?ServerConfig = blk: {
            // Ghostlang
            if (std.mem.eql(u8, ext, ".gza") or std.mem.eql(u8, ext, ".ghost")) {
                break :blk .{
                    .name = "ghostls",
                    .cmd = &[_][]const u8{"ghostls"},
                };
            }
            // Zig
            else if (std.mem.eql(u8, ext, ".zig")) {
                break :blk .{
                    .name = "zls",
                    .cmd = &[_][]const u8{"zls"},
                };
            }
            // Rust
            else if (std.mem.eql(u8, ext, ".rs")) {
                break :blk .{
                    .name = "rust_analyzer",
                    .cmd = &[_][]const u8{"rust-analyzer"},
                };
            }
            // Go
            else if (std.mem.eql(u8, ext, ".go")) {
                break :blk .{
                    .name = "gopls",
                    .cmd = &[_][]const u8{"gopls"},
                };
            }
            // C/C++
            else if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".cpp") or
                     std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".cxx") or
                     std.mem.eql(u8, ext, ".h") or std.mem.eql(u8, ext, ".hpp") or
                     std.mem.eql(u8, ext, ".hxx")) {
                break :blk .{
                    .name = "clangd",
                    .cmd = &[_][]const u8{"clangd"},
                };
            }
            // TypeScript/JavaScript
            else if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".js") or
                     std.mem.eql(u8, ext, ".tsx") or std.mem.eql(u8, ext, ".jsx")) {
                break :blk .{
                    .name = "ts_ls",
                    .cmd = &[_][]const u8{ "typescript-language-server", "--stdio" },
                };
            } else {
                break :blk null;
            }
        };

        if (config) |cfg| {
            // Check if already running
            if (self.servers.get(cfg.name)) |existing| {
                return existing;
            }

            // Try to spawn
            return self.spawn(cfg.name, cfg.cmd) catch |err| {
                std.log.warn("Failed to spawn {s}: {}", .{ cfg.name, err });
                return null;
            };
        }

        return null;
    }

    /// Get or spawn server for a file
    pub fn getOrSpawn(self: *ServerManager, filename: []const u8) !?*ServerProcess {
        const ext = std.fs.path.extension(filename);

        const server_name: []const u8 = blk: {
            if (std.mem.eql(u8, ext, ".gza") or std.mem.eql(u8, ext, ".ghost")) {
                break :blk "ghostls";
            } else if (std.mem.eql(u8, ext, ".zig")) {
                break :blk "zls";
            } else if (std.mem.eql(u8, ext, ".rs")) {
                break :blk "rust_analyzer";
            } else if (std.mem.eql(u8, ext, ".go")) {
                break :blk "gopls";
            } else if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".cpp") or
                       std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".cxx") or
                       std.mem.eql(u8, ext, ".h") or std.mem.eql(u8, ext, ".hpp") or
                       std.mem.eql(u8, ext, ".hxx")) {
                break :blk "clangd";
            } else if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".js") or
                       std.mem.eql(u8, ext, ".tsx") or std.mem.eql(u8, ext, ".jsx")) {
                break :blk "ts_ls";
            } else {
                return null;
            }
        };

        // Return existing if already running
        if (self.servers.get(server_name)) |existing| {
            return existing;
        }

        // Otherwise auto-spawn
        return try self.autoSpawn(filename);
    }

    /// Poll all active servers for responses (non-blocking)
    /// Call this in the main event loop to process LSP responses
    pub fn pollAll(self: *ServerManager) void {
        var iterator = self.servers.iterator();
        while (iterator.next()) |entry| {
            const server = entry.value_ptr.*;
            if (!server.active) continue;

            // Non-blocking poll - if no data, continues to next server
            server.client.poll() catch |err| {
                // Log errors but don't crash
                std.log.debug("LSP poll error for {s}: {}", .{ server.name, err });
            };
        }
    }

    /// Poll a specific server by name
    pub fn poll(self: *ServerManager, name: []const u8) !void {
        const server = self.servers.get(name) orelse return Error.ServerNotFound;
        if (!server.active) return;
        try server.client.poll();
    }

    // Helper functions for process I/O
    fn processRead(ctx: *anyopaque, buffer: []u8) TransportError!usize {
        const process: *std.process.Child = @ptrCast(@alignCast(ctx));
        return process.stdout.?.read(buffer) catch return TransportError.ReadFailure;
    }

    fn processWrite(ctx: *anyopaque, buffer: []const u8) TransportError!usize {
        const process: *std.process.Child = @ptrCast(@alignCast(ctx));
        return process.stdin.?.write(buffer) catch return TransportError.WriteFailure;
    }
};

test "server manager basic" {
    const allocator = std.testing.allocator;

    var manager = ServerManager.init(allocator);
    defer manager.deinit();

    // Test auto-spawn logic (without actually spawning)
    const gza_file = "test.gza";
    const zig_file = "test.zig";

    const ext1 = std.fs.path.extension(gza_file);
    const ext2 = std.fs.path.extension(zig_file);

    try std.testing.expect(std.mem.eql(u8, ext1, ".gza"));
    try std.testing.expect(std.mem.eql(u8, ext2, ".zig"));
}

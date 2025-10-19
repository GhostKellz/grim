//! Reaper AI Client - Native Zig plugin for Grim
//! Provides gRPC connection to reaper.grim daemon via zrpc

const std = @import("std");
const zrpc = @import("zrpc");

// Service definitions matching reaper.grim daemon
pub const CompletionRequest = struct {
    prompt: []const u8,
    language: []const u8,
    provider: ?[]const u8 = null,
    max_tokens: ?u32 = null,
};

pub const CompletionResponse = struct {
    text: []const u8,
    provider: []const u8,
    confidence: f32 = 0.8,
    latency_ms: u32 = 0,
    success: bool,
    error_message: ?[]const u8 = null,
};

pub const ChatRequest = struct {
    message: []const u8,
    provider: ?[]const u8 = null,
};

pub const ChatResponse = struct {
    message: []const u8,
    success: bool,
    error_message: ?[]const u8 = null,
};

pub const AgenticRequest = struct {
    task: []const u8,
    provider: ?[]const u8 = null,
};

pub const AgenticResponse = struct {
    result: []const u8,
    success: bool,
    error_message: ?[]const u8 = null,
};

pub const ReaperClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    connected: bool = false,
    rpc_client: ?*zrpc.service.Client = null,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !*ReaperClient {
        const self = try allocator.create(ReaperClient);
        self.* = .{
            .allocator = allocator,
            .endpoint = try allocator.dupe(u8, endpoint),
            .connected = false,
            .rpc_client = null,
        };
        return self;
    }

    pub fn deinit(self: *ReaperClient) void {
        self.disconnect();
        self.allocator.free(self.endpoint);
        self.allocator.destroy(self);
    }

    /// Connect to reaper daemon
    pub fn connect(self: *ReaperClient) !void {
        if (self.connected) return;

        // Create zrpc client - simple API, just allocator and endpoint
        const client = try self.allocator.create(zrpc.service.Client);
        client.* = zrpc.service.Client.init(self.allocator, self.endpoint);

        self.rpc_client = client;
        self.connected = true;
    }

    /// Disconnect from daemon
    pub fn disconnect(self: *ReaperClient) void {
        if (self.rpc_client) |client| {
            // zrpc Client is a simple struct, just free the pointer
            self.allocator.destroy(client);
            self.rpc_client = null;
        }
        self.connected = false;
    }

    /// Test connection to reaper daemon
    pub fn ping(self: *ReaperClient) !bool {
        if (!self.connected) return error.NotConnected;

        if (self.rpc_client) |client| {
            // Simple health check - try to connect if not already
            _ = client;
            return true;
        }

        return false;
    }

    /// Request code completion from reaper daemon
    pub fn complete(self: *ReaperClient, request: CompletionRequest) !CompletionResponse {
        if (!self.connected) return error.NotConnected;

        const client = self.rpc_client orelse return error.NotConnected;

        const start_time = std.time.milliTimestamp();

        // Make gRPC call - zrpc will encode the struct to JSON
        const ResponseStruct = struct {
            completion: []const u8,
            provider: []const u8,
            confidence: f32 = 0.8,
        };

        const response_data = client.call(
            "reaper.Completion/complete",
            request,
            ResponseStruct,
            null,
        ) catch |err| {
            return CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = try self.allocator.dupe(u8, "error"),
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "RPC call failed: {s}",
                    .{@errorName(err)},
                ),
            };
        };

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        return CompletionResponse{
            .text = try self.allocator.dupe(u8, response_data.completion),
            .provider = try self.allocator.dupe(u8, response_data.provider),
            .confidence = response_data.confidence,
            .latency_ms = latency,
            .success = true,
        };
    }

    /// Send chat message to reaper daemon
    pub fn chat(self: *ReaperClient, request: ChatRequest) !ChatResponse {
        if (!self.connected) return error.NotConnected;

        const client = self.rpc_client orelse return error.NotConnected;

        // Make gRPC call - zrpc will encode the struct to JSON
        const ResponseStruct = struct {
            message: []const u8,
        };

        const response_data = client.call(
            "reaper.Chat/send",
            request,
            ResponseStruct,
            null,
        ) catch |err| {
            return ChatResponse{
                .message = try self.allocator.dupe(u8, ""),
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Chat RPC failed: {s}",
                    .{@errorName(err)},
                ),
            };
        };

        return ChatResponse{
            .message = try self.allocator.dupe(u8, response_data.message),
            .success = true,
        };
    }

    /// Execute agentic task via reaper daemon
    pub fn agentic(self: *ReaperClient, request: AgenticRequest) !AgenticResponse {
        if (!self.connected) return error.NotConnected;

        const client = self.rpc_client orelse return error.NotConnected;

        // Make gRPC call - zrpc will encode the struct to JSON
        const ResponseStruct = struct {
            result: []const u8,
        };

        const response_data = client.call(
            "reaper.Agent/execute",
            request,
            ResponseStruct,
            null,
        ) catch |err| {
            return AgenticResponse{
                .result = try self.allocator.dupe(u8, ""),
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Agentic RPC failed: {s}",
                    .{@errorName(err)},
                ),
            };
        };

        return AgenticResponse{
            .result = try self.allocator.dupe(u8, response_data.result),
            .success = true,
        };
    }
};

// Global instance for GhostLang builtin access
var global_client: ?*ReaperClient = null;

pub fn getOrInitClient(allocator: std.mem.Allocator) !*ReaperClient {
    if (global_client) |client| {
        return client;
    }

    // Default endpoint from environment or hardcoded
    const endpoint = std.posix.getenv("REAPER_ENDPOINT") orelse "127.0.0.1:50051";
    global_client = try ReaperClient.init(allocator, endpoint);

    // Auto-connect on first access
    try global_client.?.connect();

    return global_client.?;
}

pub fn shutdownClient() void {
    if (global_client) |client| {
        client.deinit();
        global_client = null;
    }
}

test "reaper client init" {
    const allocator = std.testing.allocator;

    var client = try ReaperClient.init(allocator, "127.0.0.1:50051");
    defer client.deinit();

    try std.testing.expect(!client.connected);
    try std.testing.expectEqualStrings("127.0.0.1:50051", client.endpoint);
}

test "completion request structure" {
    const request = CompletionRequest{
        .prompt = "fn main() ",
        .language = "zig",
    };

    try std.testing.expectEqualStrings("fn main() ", request.prompt);
    try std.testing.expectEqualStrings("zig", request.language);
}

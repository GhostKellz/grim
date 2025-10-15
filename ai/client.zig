// ai/client.zig
// HTTP client for Omen AI gateway using zhttp
// Connects to OpenAI-compatible API for AI completions

const std = @import("std");
const zhttp = @import("zhttp");
const core = @import("core");
const mod = @import("mod.zig");

const CompletionRequest = mod.CompletionRequest;
const CompletionResponse = mod.CompletionResponse;

pub const ClientError = error{
    ConnectionFailed,
    RequestFailed,
    InvalidResponse,
    JsonParseError,
    StreamError,
    OutOfMemory,
};

pub const ClientConfig = struct {
    base_url: []const u8 = "http://localhost:8080",
    api_key: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
    max_retries: u32 = 3,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    config: ClientConfig,
    http_client: *zhttp.Client,

    pub fn init(allocator: std.mem.Allocator, config: ClientConfig) !Client {
        // Initialize zhttp client with config
        const http_client = try allocator.create(zhttp.Client);
        http_client.* = try zhttp.Client.init(allocator, .{
            .timeout_ms = config.timeout_ms,
        });

        return Client{
            .allocator = allocator,
            .config = config,
            .http_client = http_client,
        };
    }

    pub fn deinit(self: *Client) void {
        self.http_client.deinit();
        self.allocator.destroy(self.http_client);
    }

    /// Send a non-streaming completion request
    pub fn complete(
        self: *Client,
        request: CompletionRequest,
    ) !CompletionResponse {
        // Ensure streaming is disabled
        var req = request;
        req.stream = false;

        // Build the request URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1/chat/completions",
            .{self.config.base_url},
        );
        defer self.allocator.free(url);

        // Serialize request to JSON
        const json_body = try self.serializeRequest(req);
        defer self.allocator.free(json_body);

        // Build headers
        var headers = std.ArrayList(zhttp.Header).init(self.allocator);
        defer headers.deinit();

        try headers.append(.{
            .name = "Content-Type",
            .value = "application/json",
        });

        if (self.config.api_key) |key| {
            const auth_header = try std.fmt.allocPrint(
                self.allocator,
                "Bearer {s}",
                .{key},
            );
            defer self.allocator.free(auth_header);

            try headers.append(.{
                .name = "Authorization",
                .value = auth_header,
            });
        }

        // Make the HTTP request
        const response = self.http_client.request(.{
            .method = .POST,
            .url = url,
            .headers = headers.items,
            .body = json_body,
        }) catch |err| {
            std.log.err("HTTP request failed: {}", .{err});
            return ClientError.RequestFailed;
        };
        defer response.deinit();

        // Check response status
        if (response.status_code != 200) {
            std.log.err("Omen API returned status {}", .{response.status_code});
            return ClientError.InvalidResponse;
        }

        // Parse JSON response
        const completion = try self.parseResponse(response.body);
        return completion;
    }

    /// Send a streaming completion request (SSE)
    pub fn streamComplete(
        self: *Client,
        request: CompletionRequest,
        callback: *const fn (chunk: []const u8, user_data: ?*anyopaque) anyerror!void,
        user_data: ?*anyopaque,
    ) !void {
        // Ensure streaming is enabled
        var req = request;
        req.stream = true;

        // Build the request URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1/chat/completions",
            .{self.config.base_url},
        );
        defer self.allocator.free(url);

        // Serialize request to JSON
        const json_body = try self.serializeRequest(req);
        defer self.allocator.free(json_body);

        // Build headers
        var headers = std.ArrayList(zhttp.Header).init(self.allocator);
        defer headers.deinit();

        try headers.append(.{
            .name = "Content-Type",
            .value = "application/json",
        });
        try headers.append(.{
            .name = "Accept",
            .value = "text/event-stream",
        });

        if (self.config.api_key) |key| {
            const auth_header = try std.fmt.allocPrint(
                self.allocator,
                "Bearer {s}",
                .{key},
            );
            defer self.allocator.free(auth_header);

            try headers.append(.{
                .name = "Authorization",
                .value = auth_header,
            });
        }

        // Make streaming HTTP request
        const response = self.http_client.requestStream(.{
            .method = .POST,
            .url = url,
            .headers = headers.items,
            .body = json_body,
        }) catch |err| {
            std.log.err("HTTP streaming request failed: {}", .{err});
            return ClientError.RequestFailed;
        };
        defer response.deinit();

        // Check response status
        if (response.status_code != 200) {
            std.log.err("Omen API returned status {}", .{response.status_code});
            return ClientError.StreamError;
        }

        // Process SSE stream
        try self.processSSEStream(response, callback, user_data);
    }

    /// Serialize CompletionRequest to JSON
    fn serializeRequest(self: *Client, request: CompletionRequest) ![]u8 {
        var json_string = std.ArrayList(u8).init(self.allocator);
        defer json_string.deinit();

        try std.json.stringify(request, .{}, json_string.writer());
        return try json_string.toOwnedSlice();
    }

    /// Parse CompletionResponse from JSON
    fn parseResponse(self: *Client, json_body: []const u8) !CompletionResponse {
        const parsed = std.json.parseFromSlice(
            CompletionResponse,
            self.allocator,
            json_body,
            .{},
        ) catch |err| {
            std.log.err("Failed to parse JSON response: {}", .{err});
            return ClientError.JsonParseError;
        };
        defer parsed.deinit();

        // Deep copy the response (parsed.value is arena-allocated)
        return try self.copyResponse(parsed.value);
    }

    /// Deep copy CompletionResponse to allocator-owned memory
    fn copyResponse(self: *Client, response: CompletionResponse) !CompletionResponse {
        // Copy strings and nested structures
        const id = try self.allocator.dupe(u8, response.id);
        const object = try self.allocator.dupe(u8, response.object);
        const model = try self.allocator.dupe(u8, response.model);

        // Copy choices array
        const choices = try self.allocator.alloc(CompletionResponse.Choice, response.choices.len);
        for (response.choices, 0..) |choice, i| {
            choices[i] = try self.copyChoice(choice);
        }

        // Copy usage if present
        const usage = if (response.usage) |u| CompletionResponse.Usage{
            .prompt_tokens = u.prompt_tokens,
            .completion_tokens = u.completion_tokens,
            .total_tokens = u.total_tokens,
        } else null;

        return CompletionResponse{
            .id = id,
            .object = object,
            .created = response.created,
            .model = model,
            .choices = choices,
            .usage = usage,
        };
    }

    fn copyChoice(self: *Client, choice: CompletionResponse.Choice) !CompletionResponse.Choice {
        const role = try self.allocator.dupe(u8, choice.message.role);
        const content = if (choice.message.content) |c|
            try self.allocator.dupe(u8, c)
        else
            null;

        const finish_reason = if (choice.finish_reason) |fr|
            try self.allocator.dupe(u8, fr)
        else
            null;

        // TODO: Copy tool_calls if present

        return CompletionResponse.Choice{
            .index = choice.index,
            .message = .{
                .role = role,
                .content = content,
                .tool_calls = null, // TODO: Implement tool call copying
            },
            .finish_reason = finish_reason,
        };
    }

    /// Process Server-Sent Events (SSE) stream
    fn processSSEStream(
        self: *Client,
        response: anytype,
        callback: *const fn (chunk: []const u8, user_data: ?*anyopaque) anyerror!void,
        user_data: ?*anyopaque,
    ) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // Read stream in chunks
        while (true) {
            const chunk = response.readChunk() catch |err| {
                if (err == error.EndOfStream) break;
                std.log.err("Stream read error: {}", .{err});
                return ClientError.StreamError;
            };

            try buffer.appendSlice(chunk);

            // Process complete SSE events
            while (std.mem.indexOf(u8, buffer.items, "\n\n")) |pos| {
                const event_data = buffer.items[0..pos];

                // Parse SSE event
                if (std.mem.startsWith(u8, event_data, "data: ")) {
                    const json_data = event_data[6..]; // Skip "data: " prefix

                    // Check for [DONE] marker
                    if (std.mem.eql(u8, json_data, "[DONE]")) {
                        break;
                    }

                    // Invoke callback with chunk
                    try callback(json_data, user_data);
                }

                // Remove processed event from buffer
                std.mem.copyForwards(u8, buffer.items, buffer.items[pos + 2 ..]);
                buffer.shrinkRetainingCapacity(buffer.items.len - pos - 2);
            }
        }
    }

    /// Health check - verify Omen is reachable
    pub fn healthCheck(self: *Client) !bool {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/health",
            .{self.config.base_url},
        );
        defer self.allocator.free(url);

        const response = self.http_client.request(.{
            .method = .GET,
            .url = url,
            .headers = &.{},
            .body = "",
        }) catch {
            return false;
        };
        defer response.deinit();

        return response.status_code == 200;
    }
};

test "Client init/deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var client = try Client.init(allocator, .{});
    defer client.deinit();

    try testing.expect(client.config.timeout_ms == 30000);
}

test "serializeRequest" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var client = try Client.init(allocator, .{});
    defer client.deinit();

    const request = CompletionRequest{
        .model = "claude-3-5-sonnet",
        .messages = &[_]CompletionRequest.Message{
            .{ .role = "user", .content = "Hello!" },
        },
        .stream = false,
    };

    const json = try client.serializeRequest(request);
    defer allocator.free(json);

    try testing.expect(json.len > 0);
    try testing.expect(std.mem.indexOf(u8, json, "Hello!") != null);
}

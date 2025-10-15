// ai/streaming.zig
// Server-Sent Events (SSE) streaming support for AI completions
// Handles parsing and accumulating streaming responses from Omen

const std = @import("std");
const mod = @import("mod.zig");

pub const StreamChunk = struct {
    id: ?[]const u8 = null,
    object: []const u8,
    created: i64,
    model: []const u8,
    choices: []StreamChoice,

    pub const StreamChoice = struct {
        index: usize,
        delta: Delta,
        finish_reason: ?[]const u8 = null,

        pub const Delta = struct {
            role: ?[]const u8 = null,
            content: ?[]const u8 = null,
        };
    };
};

pub const StreamError = error{
    InvalidEvent,
    MalformedJson,
    UnexpectedEnd,
};

/// Accumulates streaming chunks into a complete response
pub const StreamAccumulator = struct {
    allocator: std.mem.Allocator,
    content: std.ArrayList(u8),
    role: ?[]const u8,
    model: ?[]const u8,
    finish_reason: ?[]const u8,
    chunk_count: usize,

    pub fn init(allocator: std.mem.Allocator) StreamAccumulator {
        return StreamAccumulator{
            .allocator = allocator,
            .content = std.ArrayList(u8).init(allocator),
            .role = null,
            .model = null,
            .finish_reason = null,
            .chunk_count = 0,
        };
    }

    pub fn deinit(self: *StreamAccumulator) void {
        self.content.deinit();
        if (self.role) |r| self.allocator.free(r);
        if (self.model) |m| self.allocator.free(m);
        if (self.finish_reason) |fr| self.allocator.free(fr);
    }

    /// Process a single SSE chunk
    pub fn processChunk(self: *StreamAccumulator, json_data: []const u8) !void {
        // Parse the stream chunk
        const parsed = std.json.parseFromSlice(
            StreamChunk,
            self.allocator,
            json_data,
            .{},
        ) catch |err| {
            std.log.err("Failed to parse stream chunk: {}", .{err});
            return StreamError.MalformedJson;
        };
        defer parsed.deinit();

        const chunk = parsed.value;
        self.chunk_count += 1;

        // Store model if first chunk
        if (self.model == null and chunk.model.len > 0) {
            self.model = try self.allocator.dupe(u8, chunk.model);
        }

        // Process each choice (usually just one)
        for (chunk.choices) |choice| {
            // Store role if present
            if (choice.delta.role) |role| {
                if (self.role == null) {
                    self.role = try self.allocator.dupe(u8, role);
                }
            }

            // Append content delta
            if (choice.delta.content) |content| {
                try self.content.appendSlice(content);
            }

            // Store finish reason
            if (choice.finish_reason) |reason| {
                if (self.finish_reason == null) {
                    self.finish_reason = try self.allocator.dupe(u8, reason);
                }
            }
        }
    }

    /// Convert accumulated data to CompletionResponse
    pub fn toResponse(self: *StreamAccumulator) !mod.CompletionResponse {
        const content = try self.content.toOwnedSlice();
        const role = self.role orelse try self.allocator.dupe(u8, "assistant");
        const model = self.model orelse try self.allocator.dupe(u8, "unknown");

        // Create a single choice
        const choices = try self.allocator.alloc(mod.CompletionResponse.Choice, 1);
        choices[0] = .{
            .index = 0,
            .message = .{
                .role = role,
                .content = content,
                .tool_calls = null,
            },
            .finish_reason = if (self.finish_reason) |fr|
                try self.allocator.dupe(u8, fr)
            else
                null,
        };

        return mod.CompletionResponse{
            .id = try self.allocator.dupe(u8, "stream-response"),
            .object = try self.allocator.dupe(u8, "chat.completion"),
            .created = std.time.timestamp(),
            .model = model,
            .choices = choices,
            .usage = null,
        };
    }
};

/// Parse a single SSE event line
pub fn parseSSEEvent(line: []const u8) ?struct {
    field: []const u8,
    value: []const u8,
} {
    // SSE format: "field: value"
    const colon_pos = std.mem.indexOf(u8, line, ": ") orelse return null;

    return .{
        .field = line[0..colon_pos],
        .value = line[colon_pos + 2 ..],
    };
}

/// Check if SSE stream is done
pub fn isStreamDone(data: []const u8) bool {
    return std.mem.eql(u8, data, "[DONE]");
}

test "StreamAccumulator basic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var acc = StreamAccumulator.init(allocator);
    defer acc.deinit();

    // Simulate first chunk with role
    const chunk1 =
        \\{
        \\  "object": "chat.completion.chunk",
        \\  "created": 1234567890,
        \\  "model": "claude-3-5-sonnet",
        \\  "choices": [{
        \\    "index": 0,
        \\    "delta": {
        \\      "role": "assistant",
        \\      "content": "Hello"
        \\    }
        \\  }]
        \\}
    ;

    try acc.processChunk(chunk1);
    try testing.expect(acc.chunk_count == 1);
    try testing.expectEqualStrings("Hello", acc.content.items);
    try testing.expectEqualStrings("assistant", acc.role.?);

    // Simulate second chunk with more content
    const chunk2 =
        \\{
        \\  "object": "chat.completion.chunk",
        \\  "created": 1234567890,
        \\  "model": "claude-3-5-sonnet",
        \\  "choices": [{
        \\    "index": 0,
        \\    "delta": {
        \\      "content": " there!"
        \\    }
        \\  }]
        \\}
    ;

    try acc.processChunk(chunk2);
    try testing.expect(acc.chunk_count == 2);
    try testing.expectEqualStrings("Hello there!", acc.content.items);
}

test "parseSSEEvent" {
    const testing = std.testing;

    const event = parseSSEEvent("data: {\"hello\": \"world\"}").?;
    try testing.expectEqualStrings("data", event.field);
    try testing.expectEqualStrings("{\"hello\": \"world\"}", event.value);

    const no_event = parseSSEEvent("invalid line");
    try testing.expect(no_event == null);
}

test "isStreamDone" {
    const testing = std.testing;

    try testing.expect(isStreamDone("[DONE]"));
    try testing.expect(!isStreamDone("[NOTDONE]"));
    try testing.expect(!isStreamDone("data: hello"));
}

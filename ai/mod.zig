// ai/mod.zig
// AI integration module for Grim - connects to Omen gateway for AI capabilities
// Provides OpenAI-compatible API client with streaming support

pub const Client = @import("client.zig").Client;
pub const Context = @import("context.zig").Context;
pub const Streaming = @import("streaming.zig");

pub const CompletionRequest = struct {
    model: []const u8 = "auto", // Omen's smart routing
    messages: []Message,
    stream: bool = false,
    temperature: ?f32 = null,
    max_tokens: ?usize = null,
    stop: ?[]const []const u8 = null,
    tools: ?[]Tool = null,

    pub const Message = struct {
        role: []const u8, // "system", "user", "assistant"
        content: []const u8,
    };

    pub const Tool = struct {
        type: []const u8 = "function",
        function: Function,

        pub const Function = struct {
            name: []const u8,
            description: []const u8,
            parameters: std.json.Value,
        };
    };
};

pub const CompletionResponse = struct {
    id: []const u8,
    object: []const u8,
    created: i64,
    model: []const u8,
    choices: []Choice,
    usage: ?Usage = null,

    pub const Choice = struct {
        index: usize,
        message: Message,
        finish_reason: ?[]const u8 = null,

        pub const Message = struct {
            role: []const u8,
            content: ?[]const u8 = null,
            tool_calls: ?[]ToolCall = null,

            pub const ToolCall = struct {
                id: []const u8,
                type: []const u8,
                function: FunctionCall,

                pub const FunctionCall = struct {
                    name: []const u8,
                    arguments: []const u8,
                };
            };
        };
    };

    pub const Usage = struct {
        prompt_tokens: usize,
        completion_tokens: usize,
        total_tokens: usize,
    };
};

const std = @import("std");

test "AI module compiles" {
    const testing = std.testing;
    _ = testing;
}

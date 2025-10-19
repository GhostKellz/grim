//! Test the Reaper AI client integration
const std = @import("std");
const reaper = @import("ai").reaper_client;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔌 Testing Reaper AI Client Integration\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Step 1: Initialize client
    std.debug.print("1. Initializing client...\n", .{});
    var client = try reaper.ReaperClient.init(allocator, "127.0.0.1:50051");
    defer client.deinit();
    std.debug.print("   ✓ Client initialized\n\n", .{});

    // Step 2: Connect to daemon
    std.debug.print("2. Connecting to daemon...\n", .{});
    try client.connect();
    std.debug.print("   ✓ Connected to 127.0.0.1:50051\n\n", .{});

    // Step 3: Ping test
    std.debug.print("3. Testing connection (ping)...\n", .{});
    const is_alive = try client.ping();
    std.debug.print("   ✓ Ping successful: {}\n\n", .{is_alive});

    // Step 4: Test completion
    std.debug.print("4. Testing code completion...\n", .{});
    const completion_request = reaper.CompletionRequest{
        .prompt = "fn main() ",
        .language = "zig",
        .provider = null,
        .max_tokens = 100,
    };

    {
        const completion_response = try client.complete(completion_request);
        defer allocator.free(completion_response.text);
        defer allocator.free(completion_response.provider);
        defer if (completion_response.error_message) |err_msg| allocator.free(err_msg);

        if (completion_response.success) {
            std.debug.print("   ✓ Completion received from {s}\n", .{completion_response.provider});
            std.debug.print("   📝 Text: {s}\n", .{completion_response.text});
            std.debug.print("   ⏱️  Latency: {}ms\n", .{completion_response.latency_ms});
            std.debug.print("   🎯 Confidence: {d:.2}\n\n", .{completion_response.confidence});
        } else {
            std.debug.print("   ✗ Completion failed: {s}\n\n", .{completion_response.error_message orelse "unknown error"});
        }
    }

    // Step 5: Test chat
    std.debug.print("5. Testing chat...\n", .{});
    const chat_request = reaper.ChatRequest{
        .message = "Hello, can you help me write Zig code?",
        .provider = null,
    };

    {
        const chat_response = try client.chat(chat_request);
        defer allocator.free(chat_response.message);
        defer if (chat_response.error_message) |err_msg| allocator.free(err_msg);

        if (chat_response.success) {
            std.debug.print("   ✓ Chat response received\n", .{});
            std.debug.print("   💬 Message: {s}\n\n", .{chat_response.message});
        } else {
            std.debug.print("   ✗ Chat failed: {s}\n\n", .{chat_response.error_message orelse "unknown error"});
        }
    }

    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("✅ All tests completed!\n", .{});
}

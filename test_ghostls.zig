const std = @import("std");
const lsp = @import("lsp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing Ghostls integration...\n", .{});

    // Create server manager
    var manager = lsp.ServerManager.init(allocator);
    defer manager.deinit();

    // Spawn ghostls (now installed system-wide)
    const server = try manager.spawn("ghostls", &[_][]const u8{"ghostls"});

    std.debug.print("✅ Ghostls spawned successfully!\n", .{});
    std.debug.print("✅ Server active: {}\n", .{server.active});

    // Wait for initialize response
    std.debug.print("⏳ Waiting for initialize response...\n", .{});
    var retries: u32 = 0;
    while (!server.client.isInitialized() and retries < 10) : (retries += 1) {
        server.client.poll() catch |err| {
            std.debug.print("  Poll attempt {d}: {}\n", .{ retries + 1, err });
        };
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    std.debug.print("✅ Client initialized: {}\n", .{server.client.isInitialized()});

    if (!server.client.isInitialized()) {
        std.debug.print("❌ Failed to initialize LSP client\n", .{});
        return;
    }

    // Send a hover request
    const request_id = try server.client.requestHover(
        "file:///data/projects/grim/test.gza",
        1,
        10,
    );

    std.debug.print("✅ Hover request sent (id: {d})\n", .{request_id});

    // Try to poll for response
    server.client.poll() catch |err| {
        std.debug.print("⚠ Poll error (expected): {}\n", .{err});
    };

    std.debug.print("\n✅ LSP integration test complete!\n", .{});
}

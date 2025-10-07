const std = @import("std");
const host_mod = @import("host");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Testing Existing example.gza ===\n\n", .{});

    // Initialize Host
    var ghostlang_host = try host_mod.Host.init(allocator);
    defer ghostlang_host.deinit();
    std.debug.print("✓ Host initialized\n", .{});

    // Read example.gza
    const script_content = try std.fs.cwd().readFileAlloc(
        "example.gza",
        allocator,
        .limited(10 * 1024 * 1024),
    );
    defer allocator.free(script_content);

    std.debug.print("✓ Read example.gza ({d} bytes)\n", .{script_content.len});
    std.debug.print("\nContent:\n{s}\n\n", .{script_content});

    // Try to compile it
    std.debug.print("Attempting to compile...\n", .{});
    const compiled = ghostlang_host.compilePluginScript(script_content) catch |err| {
        std.debug.print("✗ Compilation failed: {}\n", .{err});
        return err;
    };
    defer compiled.deinit();

    std.debug.print("✓ Compilation successful!\n", .{});
}

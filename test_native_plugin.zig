const std = @import("std");
const runtime = @import("runtime");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Native Plugin Loading Test ===\n\n", .{});

    // Initialize native plugin loader
    var loader = runtime.NativePluginLoader.init(allocator);

    const plugin_path = "plugins/examples/native-hello/libnative-hello.so";
    std.debug.print("Loading native plugin: {s}\n\n", .{plugin_path});

    // Load the plugin
    var plugin = try loader.load(plugin_path);
    defer plugin.deinit();

    // Print plugin info
    std.debug.print("✓ Plugin loaded successfully!\n", .{});
    std.debug.print("  Name: {s}\n", .{plugin.info.name});
    std.debug.print("  Version: {s}\n", .{plugin.info.version});
    std.debug.print("  Author: {s}\n", .{plugin.info.author});
    std.debug.print("  API Version: {d}\n\n", .{plugin.info.api_version});

    // Call setup
    std.debug.print("Calling plugin setup()...\n", .{});
    plugin.setup();
    std.debug.print("\n", .{});

    // Call teardown
    std.debug.print("Calling plugin teardown()...\n", .{});
    plugin.teardown();
    std.debug.print("\n", .{});

    std.debug.print("✓ Test completed successfully!\n", .{});
}

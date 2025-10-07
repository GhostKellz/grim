const std = @import("std");

const NativePluginInfo = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    api_version: u32,
};

pub fn main() !void {
    std.debug.print("=== Simple Native Plugin Test ===\n\n", .{});

    var lib = try std.DynLib.open("plugins/examples/native-hello/libnative-hello.so");
    defer lib.close();
    std.debug.print("✓ Library opened\n", .{});

    // Get info function
    const info_fn = lib.lookup(
        *const fn () callconv(.c) NativePluginInfo,
        "grim_plugin_info",
    ) orelse {
        std.debug.print("✗ Could not find grim_plugin_info\n", .{});
        return error.MissingPluginInfo;
    };
    std.debug.print("✓ Found grim_plugin_info\n", .{});

    // Call it
    const info = info_fn();
    std.debug.print("✓ Called grim_plugin_info\n", .{});

    // Print info - use mem.span to safely convert [*:0]const u8 to []const u8
    std.debug.print("  Name: {s}\n", .{std.mem.span(info.name)});
    std.debug.print("  Version: {s}\n", .{std.mem.span(info.version)});
    std.debug.print("  Author: {s}\n", .{std.mem.span(info.author)});
    std.debug.print("  API Version: {d}\n\n", .{info.api_version});

    // Get and call init
    const init_fn = lib.lookup(
        *const fn () callconv(.c) bool,
        "grim_plugin_init",
    ) orelse return error.MissingPluginInit;
    std.debug.print("✓ Found grim_plugin_init\n", .{});

    const init_ok = init_fn();
    std.debug.print("✓ Init returned: {}\n\n", .{init_ok});

    // Get and call setup
    const setup_fn = lib.lookup(
        *const fn () callconv(.c) void,
        "grim_plugin_setup",
    );
    if (setup_fn) |setup| {
        std.debug.print("✓ Found grim_plugin_setup, calling...\n", .{});
        setup();
    }

    std.debug.print("\n✓ Test completed!\n", .{});
}

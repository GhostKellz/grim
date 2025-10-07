const std = @import("std");
const runtime = @import("runtime");
const host_mod = @import("host");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Ghostlang Plugin Loading Test ===\n\n", .{});

    // Initialize Ghostlang Host
    var ghostlang_host = try host_mod.Host.init(allocator);
    defer ghostlang_host.deinit();
    std.debug.print("✓ Ghostlang Host initialized\n\n", .{});

    // Initialize plugin discovery
    var discovery = runtime.PluginDiscovery.init(allocator);
    defer discovery.deinit();

    // Add the examples directory
    try discovery.addSearchPath("plugins/examples");
    std.debug.print("✓ Added search path: plugins/examples\n", .{});

    // Discover all plugins
    var discovered = try discovery.discoverAll();
    defer {
        for (discovered.items) |*plugin| {
            plugin.deinit();
        }
        discovered.deinit(allocator);
    }
    std.debug.print("✓ Discovered {} plugin(s)\n\n", .{discovered.items.len});

    // Print discovered plugins
    for (discovered.items, 0..) |plugin, i| {
        std.debug.print("  [{d}] {s} v{s}\n", .{ i + 1, plugin.name, plugin.manifest.version });
        std.debug.print("      Main: {s}\n", .{plugin.manifest.main});
        std.debug.print("      Path: {s}\n", .{plugin.path});
    }
    std.debug.print("\n", .{});

    // Find hello-world plugin
    var hello_world_idx: ?usize = null;
    for (discovered.items, 0..) |plugin, i| {
        if (std.mem.eql(u8, plugin.name, "hello-world")) {
            hello_world_idx = i;
            break;
        }
    }

    if (hello_world_idx == null) {
        std.debug.print("✗ hello-world plugin not found\n", .{});
        return error.PluginNotFound;
    }

    std.debug.print("✓ Found hello-world plugin\n\n", .{});

    // Load the hello-world plugin
    var plugin_loader = runtime.PluginLoader.init(allocator);
    const hello_plugin = &discovered.items[hello_world_idx.?];

    std.debug.print("Loading hello-world plugin...\n", .{});
    var loaded = try plugin_loader.load(hello_plugin, &ghostlang_host);
    defer loaded.deinit();

    std.debug.print("✓ Plugin loaded successfully\n", .{});
    std.debug.print("  Type: {s}\n\n", .{@tagName(loaded.plugin_type)});

    // Create simple ActionCallbacks for testing
    const TestContext = struct {
        allocator: std.mem.Allocator,
        commands: std.ArrayList([]const u8),
        keymaps: std.ArrayList([]const u8),

        fn showMessage(_: *anyopaque, msg: []const u8) !void {
            std.debug.print("  [CALLBACK] show_message: {s}\n", .{msg});
        }

        fn registerCommand(ctx_ptr: *anyopaque, action: *const host_mod.Host.CommandAction) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
            const name = try self.allocator.dupe(u8, action.name);
            try self.commands.append(self.allocator, name);
            std.debug.print("  [CALLBACK] register_command: {s} -> {s}\n", .{ action.name, action.handler });
        }

        fn registerKeymap(ctx_ptr: *anyopaque, action: *const host_mod.Host.KeymapAction) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
            const keys = try self.allocator.dupe(u8, action.keys);
            try self.keymaps.append(self.allocator, keys);
            std.debug.print("  [CALLBACK] register_keymap: {s} -> {s}\n", .{ action.keys, action.handler });
        }
    };

    var test_ctx = TestContext{
        .allocator = allocator,
        .commands = .{},
        .keymaps = .{},
    };
    defer {
        for (test_ctx.commands.items) |cmd| allocator.free(cmd);
        test_ctx.commands.deinit(allocator);
        for (test_ctx.keymaps.items) |km| allocator.free(km);
        test_ctx.keymaps.deinit(allocator);
    }

    const callbacks = host_mod.Host.ActionCallbacks{
        .ctx = &test_ctx,
        .show_message = TestContext.showMessage,
        .register_command = TestContext.registerCommand,
        .register_keymap = TestContext.registerKeymap,
    };

    // Call setup() on the plugin
    std.debug.print("Calling plugin setup()...\n", .{});
    try plugin_loader.callSetup(&loaded, callbacks);
    std.debug.print("\n✓ Plugin setup() completed\n\n", .{});

    // Verify callbacks were invoked
    std.debug.print("Registered commands: {d}\n", .{test_ctx.commands.items.len});
    for (test_ctx.commands.items) |cmd| {
        std.debug.print("  - {s}\n", .{cmd});
    }

    std.debug.print("\nRegistered keymaps: {d}\n", .{test_ctx.keymaps.items.len});
    for (test_ctx.keymaps.items) |km| {
        std.debug.print("  - {s}\n", .{km});
    }

    std.debug.print("\n✓ All tests passed!\n", .{});
}

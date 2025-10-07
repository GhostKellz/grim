const std = @import("std");
const ghostlang = @import("ghostlang");

fn testBuiltin(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Direct Ghostlang API Test ===\n\n", .{});

    // Test with minimal config (like their examples)
    std.debug.print("--- Test A: Minimal Config (like their examples) ---\n", .{});
    {
        const config = ghostlang.EngineConfig{
            .allocator = allocator,
        };
        var engine = try ghostlang.ScriptEngine.create(config);
        defer engine.deinit();
        std.debug.print("✓ Engine created\n", .{});

        var script = engine.loadScript("local x = 42") catch |err| {
            std.debug.print("ERROR: {}\n", .{err});
            return err;
        };
        defer script.deinit();
        _ = try script.run();
        std.debug.print("✓ Script ran successfully!\n\n", .{});
    }

    // Test with Host-like config (sandbox settings) + heap allocation
    std.debug.print("--- Test B: Host Config (heap-allocated like Host) ---\n", .{});
    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 50 * 1024 * 1024, // 50MB like Host
        .execution_timeout_ms = 5000,
        .allow_io = true,
        .allow_syscalls = false,
    };

    // Allocate on heap like Host does
    const engine_ptr = try allocator.create(ghostlang.ScriptEngine);
    errdefer allocator.destroy(engine_ptr);
    engine_ptr.* = try ghostlang.ScriptEngine.create(config);
    defer {
        engine_ptr.deinit();
        allocator.destroy(engine_ptr);
    }
    const engine = engine_ptr;

    std.debug.print("✓ Engine created with sandbox config\n", .{});

    // Register builtins like Host does
    try engine.registerFunction("showMessage", testBuiltin);
    try engine.registerFunction("show_message", testBuiltin);
    try engine.registerFunction("registerCommand", testBuiltin);
    try engine.registerFunction("register_command", testBuiltin);
    std.debug.print("✓ Registered builtins\n\n", .{});

    // Test 1: Minimal script (heap-allocated like Host does)
    std.debug.print("Test 1: local x = 42 (heap-allocated script)\n", .{});
    {
        const script_ptr = try allocator.create(ghostlang.Script);
        errdefer allocator.destroy(script_ptr);

        script_ptr.* = engine.loadScript("local x = 42") catch |err| {
            allocator.destroy(script_ptr);
            std.debug.print("ERROR: {}\n", .{err});
            return err;
        };
        defer {
            script_ptr.deinit();
            allocator.destroy(script_ptr);
        }

        _ = try script_ptr.run();
        std.debug.print("✓ Success!\n\n", .{});
    }

    // Test 2: With function
    std.debug.print("Test 2: function with local variable\n", .{});
    const test2 =
        \\local message = "Plugin loaded"
        \\
        \\function setup()
        \\    print(message)
        \\end
    ;
    {
        var script = engine.loadScript(test2) catch |err| {
            std.debug.print("ERROR: {}\n", .{err});
            return err;
        };
        defer script.deinit();
        _ = try script.run();
        std.debug.print("✓ Success!\n\n", .{});
    }

    std.debug.print("✓ All tests passed!\n", .{});
}

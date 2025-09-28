const std = @import("std");
const grim = @import("grim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize Simple TUI app
    const SimpleTUI = @import("ui_tui").simple_tui.SimpleTUI;
    var app = try SimpleTUI.init(allocator);
    defer app.deinit();

    // Load file if provided
    if (args.len > 1) {
        app.loadFile(args[1]) catch |err| {
            std.debug.print("Failed to load file {s}: {}\n", .{ args[1], err });
            // Continue with empty buffer
        };
    } else {
        // Load a sample file for testing
        try app.editor.rope.insert(0,
            \\fn main() !void {
            \\    const std = @import("std");
            \\    std.debug.print("Hello, Grim!\n", .{});
            \\
            \\    // This is a comment
            \\    const x: u32 = 42;
            \\    var y = x * 2;
            \\
            \\    if (y > 80) {
            \\        std.debug.print("y is large: {}\n", .{y});
            \\    }
            \\}
        );
    }

    std.debug.print("Starting Grim editor... Press Ctrl+Q to quit.\n", .{});
    std.Thread.sleep(2 * std.time.ns_per_s); // Give user time to read

    // Run the TUI
    app.run() catch |err| {
        std.debug.print("TUI error: {}\n", .{err});
        return;
    };

    std.debug.print("Grim editor closed.\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

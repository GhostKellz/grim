const std = @import("std");
const grim = @import("grim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize Grim app
    var app = try grim.ui.tui.App.init(allocator);
    defer app.deinit();

    // Load file if provided
    if (args.len > 1) {
        // Load file content using more recent API  
        const file = std.fs.cwd().openFile(args[1], .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("File not found: {s}\n", .{args[1]});
                return;
            },
            else => return err,
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        const file_content = try allocator.alloc(u8, file_size);
        defer allocator.free(file_content);
        
        _ = try file.readAll(file_content);
        
        if (file_content.len > 0) {
            try app.buffer.insert(0, file_content);
        }
    } else {
        // Load a sample file for testing
        try app.buffer.insert(0,
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

    std.debug.print("Starting Grim editor... Press q to quit.\n", .{});

    // Run the TUI
    try app.run();

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

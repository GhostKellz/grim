const std = @import("std");
const syntax = @import("syntax");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a simple Zig code snippet
    const code =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const x: u32 = 42;
        \\    std.debug.print("Hello: {}\n", .{x});
        \\}
    ;

    std.debug.print("Testing Grove syntax highlighting...\n", .{});
    std.debug.print("Code to highlight ({} bytes):\n{s}\n\n", .{ code.len, code });

    // Create parser for Zig
    var parser = try syntax.createParser(allocator, "test.zig");
    defer parser.deinit();

    std.debug.print("Parser created for language: {s}\n", .{parser.language.name()});

    // Parse the code
    try parser.parse(code);
    std.debug.print("Code parsed successfully\n", .{});

    // Get highlights
    const highlights = try parser.getHighlights(allocator);
    defer allocator.free(highlights);

    std.debug.print("Got {} highlights:\n", .{highlights.len});
    for (highlights, 0..) |hl, i| {
        const highlight_text = code[hl.start..hl.end];
        std.debug.print("  [{d}] {s:12} @ {d:4}-{d:4}: '{s}'\n", .{
            i,
            @tagName(hl.type),
            hl.start,
            hl.end,
            highlight_text,
        });
    }
}

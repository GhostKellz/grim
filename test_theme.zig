// Test file for theme rendering
// Comments should be hacker blue (#57c7ff)

const std = @import("std");

/// Doc comment test
pub fn testThemeColors() !void {
    // String literals should be green
    const message = "Hello, Ghost Hacker Blue!";

    // Numbers should be yellow/orange
    const number: u32 = 42;
    const float: f64 = 3.14159;

    // Keywords should be cyan
    if (number > 40) {
        const result = number * 2;
        try std.debug.print("{s}: {}\n", .{ message, result });
    }

    // Function names should be mint green (#8aff80)
    const value = calculateValue(number);

    // Types should be blue
    var list = std.ArrayList(u8).init(std.heap.page_allocator);
    defer list.deinit();
}

// Function definition - name should be mint green
fn calculateValue(input: u32) u32 {
    return input * 2;
}

// Test operators
const x = 10 + 20 - 5 * 2 / 3;
const y = x > 10 and x < 100;

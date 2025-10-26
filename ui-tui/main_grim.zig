//! Grim Editor - Main entry point
//! Neovim alternative in Zig powered by Phantom TUI

const std = @import("std");
const grim_app = @import("grim_app.zig");

pub fn main() !void {
    // Set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    var args = std.process.argsAlloc(allocator) catch |err| {
        std.log.err("Failed to parse arguments: {}", .{err});
        return err;
    };
    defer std.process.argsFree(allocator, args);

    // Determine initial file to open
    var initial_file: ?[]const u8 = null;
    if (args.len > 1) {
        initial_file = args[1];
    }

    // Create Grim app config
    const config = grim_app.GrimConfig{
        .initial_file = initial_file,
        .tick_rate_ms = 16, // 60 FPS
        .mouse_enabled = true,
    };

    // Initialize and run Grim
    var app = try grim_app.GrimApp.init(allocator, config);
    defer app.deinit();

    std.log.info("🚀 Grim Editor starting...", .{});

    try app.run();

    std.log.info("👋 Grim Editor stopped", .{});
}

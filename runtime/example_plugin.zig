const std = @import("std");
const runtime = @import("mod.zig");

// Example plugin: Auto-formatter
// This demonstrates how to create plugins for Grim editor

const AutoFormatterPlugin = struct {
    const Self = @This();

    pub fn createPlugin(allocator: std.mem.Allocator) !*runtime.Plugin {
        const plugin = try allocator.create(runtime.Plugin);
        plugin.* = runtime.Plugin{
            .id = "auto-formatter",
            .name = "Auto Formatter",
            .version = "1.0.0",
            .author = "Grim Team",
            .description = "Automatic code formatting plugin",
            .context = undefined, // Will be set by plugin system
            .init_fn = initPlugin,
            .deinit_fn = deinitPlugin,
            .activate_fn = activatePlugin,
            .deactivate_fn = deactivatePlugin,
        };
        return plugin;
    }

    fn initPlugin(ctx: *runtime.PluginContext) !void {
        try ctx.api.registerCommand(.{
            .name = "format",
            .description = "Format current buffer",
            .handler = formatCommand,
            .plugin_id = ctx.plugin_id,
        });

        try ctx.api.registerCommand(.{
            .name = "toggle-format-on-save",
            .description = "Toggle automatic formatting on save",
            .handler = toggleFormatOnSaveCommand,
            .plugin_id = ctx.plugin_id,
        });

        try ctx.api.registerEventHandler(.{
            .event_type = .buffer_saved,
            .handler = onBufferSaved,
            .plugin_id = ctx.plugin_id,
        });

        try ctx.api.registerKeystrokeHandler(.{
            .key_combination = "<leader>f",
            .mode = .normal,
            .handler = formatKeystroke,
            .description = "Format current buffer",
            .plugin_id = ctx.plugin_id,
        });

        try ctx.showMessage("Auto-formatter plugin initialized");
    }

    fn deinitPlugin(ctx: *runtime.PluginContext) !void {
        try ctx.showMessage("Auto-formatter plugin deinitialized");
    }

    fn activatePlugin(ctx: *runtime.PluginContext) !void {
        try ctx.showMessage("Auto-formatter plugin activated");
    }

    fn deactivatePlugin(ctx: *runtime.PluginContext) !void {
        try ctx.showMessage("Auto-formatter plugin deactivated");
    }

    fn formatCommand(ctx: *runtime.PluginContext, args: []const []const u8) !void {
        _ = args;
        try formatCurrentBuffer(ctx);
    }

    fn toggleFormatOnSaveCommand(ctx: *runtime.PluginContext, args: []const []const u8) !void {
        _ = args;
        // Toggle format-on-save setting
        try ctx.showMessage("Format-on-save toggled");
    }

    fn onBufferSaved(ctx: *runtime.PluginContext, data: runtime.EventData) !void {
        switch (data) {
            .buffer_saved => |save_data| {
                try ctx.showMessage(try std.fmt.allocPrint(ctx.scratch_allocator, "Buffer saved: {s}", .{save_data.filename}));
                // Auto-format if enabled
                try formatCurrentBuffer(ctx);
            },
            else => {},
        }
    }

    fn formatKeystroke(ctx: *runtime.PluginContext) !bool {
        try formatCurrentBuffer(ctx);
        return true; // Key was handled
    }

    fn formatCurrentBuffer(ctx: *runtime.PluginContext) !void {
        const buffer_id = try ctx.getCurrentBuffer();
        const content = try ctx.getBufferContent(buffer_id);
        defer ctx.scratch_allocator.free(content);

        // Simple formatting example: remove trailing whitespace and ensure newline at EOF
        var formatted_content = std.ArrayList(u8).init(ctx.scratch_allocator);
        defer formatted_content.deinit();

        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            // Remove trailing whitespace
            const trimmed_line = std.mem.trimRight(u8, line, " \t");
            try formatted_content.appendSlice(trimmed_line);
            try formatted_content.append('\n');
        }

        // Ensure content ends with newline
        if (formatted_content.items.len > 0 and formatted_content.items[formatted_content.items.len - 1] != '\n') {
            try formatted_content.append('\n');
        }

        // Update buffer content
        try ctx.setBufferContent(buffer_id, formatted_content.items);
        try ctx.showMessage("Buffer formatted successfully");
    }
};

// Factory function for creating the plugin
pub fn createAutoFormatterPlugin(allocator: std.mem.Allocator) !*runtime.Plugin {
    return AutoFormatterPlugin.createPlugin(allocator);
}

// Example usage and testing
pub fn exampleUsage() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a mock editor context
    var rope = @import("core").Rope.init(allocator) catch unreachable;
    defer rope.deinit();

    var cursor_pos = runtime.PluginAPI.EditorContext.CursorPosition{ .line = 0, .column = 0, .byte_offset = 0 };
    var mode = runtime.PluginAPI.EditorContext.EditorMode.normal;
    var highlighter = @import("syntax").SyntaxHighlighter.init(allocator);
    defer highlighter.deinit();

    var editor_context = runtime.PluginAPI.EditorContext{
        .rope = &rope,
        .cursor_position = &cursor_pos,
        .current_mode = &mode,
        .highlighter = &highlighter,
    };

    // Create plugin API
    var plugin_api = runtime.PluginAPI.init(allocator, &editor_context);
    defer plugin_api.deinit();

    // Create and load plugin
    const plugin = try createAutoFormatterPlugin(allocator);
    defer allocator.destroy(plugin);

    try plugin_api.loadPlugin(plugin);

    // Test command execution
    try plugin_api.executeCommand("format", "auto-formatter", &.{});

    // Test event emission
    try plugin_api.emitEvent(.buffer_saved, .{ .buffer_saved = .{ .buffer_id = 1, .filename = "test.zig" } });

    // Test keystroke handling
    const handled = try plugin_api.handleKeystroke("<leader>f", .normal);
    std.log.info("Keystroke handled: {}", .{handled});

    // List all commands
    const commands = try plugin_api.listCommands();
    defer allocator.free(commands);

    std.log.info("Available commands:");
    for (commands) |command| {
        std.log.info("  {s}: {s}", .{ command.name, command.description });
    }
}

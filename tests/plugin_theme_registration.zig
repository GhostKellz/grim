const std = @import("std");
const runtime = @import("runtime");
const core = @import("core");
const syntax = @import("syntax");

const TestRegistry = struct {
    allocator: std.mem.Allocator,
    registered: bool = false,
    unregistered: bool = false,
    plugin_id: ?[]u8 = null,
    theme_name: ?[]u8 = null,
    colors_json: ?[]u8 = null,

    fn init(allocator: std.mem.Allocator) TestRegistry {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *TestRegistry) void {
        if (self.plugin_id) |ptr| self.allocator.free(ptr);
        if (self.theme_name) |ptr| self.allocator.free(ptr);
        if (self.colors_json) |ptr| self.allocator.free(ptr);
    }

    fn registerTheme(ctx: *anyopaque, plugin_id: []const u8, theme_name: []const u8, colors_json: []const u8) anyerror!void {
        const self = @as(*TestRegistry, @ptrCast(@alignCast(ctx)));
        if (self.plugin_id) |ptr| self.allocator.free(ptr);
        if (self.theme_name) |ptr| self.allocator.free(ptr);
        if (self.colors_json) |ptr| self.allocator.free(ptr);

        self.plugin_id = try self.allocator.dupe(u8, plugin_id);
        self.theme_name = try self.allocator.dupe(u8, theme_name);
        self.colors_json = try self.allocator.dupe(u8, colors_json);
        self.registered = true;
    }

    fn unregisterTheme(ctx: *anyopaque, plugin_id: []const u8, theme_name: []const u8) anyerror!void {
        const self = @as(*TestRegistry, @ptrCast(@alignCast(ctx)));
        _ = plugin_id;
        _ = theme_name;
        self.unregistered = true;
    }
};

test "plugin manager registers and unregisters plugin themes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rope = try core.Rope.init(allocator);
    defer rope.deinit();

    var cursor = runtime.PluginAPI.EditorContext.CursorPosition{
        .line = 0,
        .column = 0,
        .byte_offset = 0,
    };
    var mode = runtime.PluginAPI.EditorContext.EditorMode.normal;
    var highlighter = syntax.SyntaxHighlighter.init(allocator);
    defer highlighter.deinit();

    var editor_context = runtime.PluginAPI.EditorContext{
        .rope = &rope,
        .cursor_position = &cursor,
        .current_mode = &mode,
        .highlighter = &highlighter,
    };

    var plugin_api = runtime.PluginAPI.init(allocator, &editor_context);
    defer plugin_api.deinit();

    var manager = try runtime.PluginManager.init(allocator, &plugin_api, &.{});
    defer manager.deinit();

    var registry = TestRegistry.init(allocator);
    defer registry.deinit();

    manager.setThemeCallbacks(
        @as(*anyopaque, @ptrCast(&registry)),
        TestRegistry.registerTheme,
        TestRegistry.unregisterTheme,
    );

    const script_source = "function setup()\n"
        ++ "    register_theme(\"plugin-theme\", '{\"syntax\": {\"keyword\": \"#00ff00\"}, \"ui\": {\"background\": \"#000000\", \"foreground\": \"#00ff00\"}}')\n"
        ++ "    return true\n"
        ++ "end\n";

    const manifest = runtime.PluginManager.PluginManifest{
        .id = try allocator.dupe(u8, "test-plugin"),
        .name = try allocator.dupe(u8, "Test Plugin"),
        .version = try allocator.dupe(u8, "0.1.0"),
        .author = try allocator.dupe(u8, "Test Author"),
        .description = try allocator.dupe(u8, "Plugin for testing themes"),
        .entry_point = try allocator.dupe(u8, "main.gza"),
        .dependencies = &.{},
        .permissions = .{},
    };
    defer {
        allocator.free(manifest.id);
        allocator.free(manifest.name);
        allocator.free(manifest.version);
        allocator.free(manifest.author);
        allocator.free(manifest.description);
        allocator.free(manifest.entry_point);
    }

    var plugin_info = runtime.PluginManager.PluginInfo{
        .manifest = manifest,
        .plugin_path = try allocator.dupe(u8, "tests/plugins/test-plugin"),
        .script_content = try allocator.dupe(u8, script_source),
        .loaded = false,
        .state = null,
    };
    defer {
        allocator.free(plugin_info.plugin_path);
        allocator.free(plugin_info.script_content);
    }

    try manager.loadPlugin(&plugin_info);

    try std.testing.expect(plugin_info.loaded);

    try std.testing.expect(registry.registered);
    try std.testing.expect(registry.plugin_id != null);
    try std.testing.expect(std.mem.eql(u8, registry.plugin_id.?, "test-plugin"));
    try std.testing.expect(registry.theme_name != null);
    try std.testing.expect(std.mem.eql(u8, registry.theme_name.?, "plugin-theme"));
    try std.testing.expect(registry.colors_json != null);
    try std.testing.expect(std.mem.indexOf(u8, registry.colors_json.?, "\"background\": \"#000000\"") != null);

    try manager.unloadPlugin(manifest.id);

    try std.testing.expect(registry.unregistered);
}

const std = @import("std");

/// Native plugin interface (C ABI)
/// This defines the interface that pure Zig plugins must implement

/// Plugin metadata structure
pub const NativePluginInfo = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    api_version: u32,  // Grim plugin API version
};

/// Required exports for native plugins:
///
/// Export these functions with C calling convention:
///
/// pub export fn grim_plugin_info() callconv(.C) NativePluginInfo { ... }
/// pub export fn grim_plugin_init() callconv(.C) bool { ... }
/// pub export fn grim_plugin_setup() callconv(.C) void { ... }
/// pub export fn grim_plugin_teardown() callconv(.C) void { ... }

/// Current plugin API version
pub const GRIM_PLUGIN_API_VERSION: u32 = 1;

/// Native plugin loader
pub const NativePluginLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NativePluginLoader {
        return .{ .allocator = allocator };
    }

    /// Load native plugin from .so/.dll file
    pub fn load(self: *NativePluginLoader, path: []const u8) !NativePlugin {
        std.log.info("Loading native plugin: {s}", .{path});

        var library = try std.DynLib.open(path);
        errdefer library.close();

        // Lookup required symbols
        const info_fn = library.lookup(
            *const fn () callconv(.c) NativePluginInfo,
            "grim_plugin_info",
        ) orelse return error.MissingPluginInfo;

        const init_fn = library.lookup(
            *const fn () callconv(.c) bool,
            "grim_plugin_init",
        ) orelse return error.MissingPluginInit;

        const setup_fn = library.lookup(
            *const fn () callconv(.c) void,
            "grim_plugin_setup",
        );

        const teardown_fn = library.lookup(
            *const fn () callconv(.c) void,
            "grim_plugin_teardown",
        );

        // Get plugin info
        const info = info_fn();

        // Validate API version
        if (info.api_version != GRIM_PLUGIN_API_VERSION) {
            std.log.err("Plugin API version mismatch: plugin={d}, grim={d}", .{
                info.api_version,
                GRIM_PLUGIN_API_VERSION,
            });
            return error.APIVersionMismatch;
        }

        // Initialize plugin
        const init_success = init_fn();
        if (!init_success) {
            std.log.err("Plugin initialization failed: {s}", .{info.name});
            return error.PluginInitFailed;
        }

        std.log.info("Native plugin loaded: {s} v{s}", .{ info.name, info.version });

        return NativePlugin{
            .library = library,
            .info = info,
            .setup_fn = setup_fn,
            .teardown_fn = teardown_fn,
            .allocator = self.allocator,
        };
    }
};

/// Loaded native plugin
pub const NativePlugin = struct {
    library: std.DynLib,
    info: NativePluginInfo,
    setup_fn: ?*const fn () callconv(.c) void,
    teardown_fn: ?*const fn () callconv(.c) void,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *NativePlugin) void {
        self.library.close();
    }

    pub fn setup(self: *NativePlugin) void {
        if (self.setup_fn) |setup_fn| {
            std.log.debug("Calling native plugin setup: {s}", .{self.info.name});
            setup_fn();
        }
    }

    pub fn teardown(self: *NativePlugin) void {
        if (self.teardown_fn) |teardown_fn| {
            std.log.debug("Calling native plugin teardown: {s}", .{self.info.name});
            teardown_fn();
        }
    }
};

// Example native plugin (for reference)
//
// Create a file: plugins/my-plugin/native.zig
//
// ```zig
// const std = @import("std");
// const grim = @import("native_plugin");
//
// pub export fn grim_plugin_info() callconv(.C) grim.NativePluginInfo {
//     return .{
//         .name = "my-plugin",
//         .version = "1.0.0",
//         .author = "me",
//         .api_version = grim.GRIM_PLUGIN_API_VERSION,
//     };
// }
//
// pub export fn grim_plugin_init() callconv(.C) bool {
//     // Initialize plugin
//     return true;
// }
//
// pub export fn grim_plugin_setup() callconv(.C) void {
//     // Called when plugin loads
//     std.debug.print("Native plugin setup!\n", .{});
// }
//
// pub export fn grim_plugin_teardown() callconv(.C) void {
//     // Called when plugin unloads
//     std.debug.print("Native plugin teardown!\n", .{});
// }
// ```
//
// Build: zig build-lib -dynamic -O ReleaseFast native.zig
// Output: libnative.so (Linux) or native.dll (Windows)

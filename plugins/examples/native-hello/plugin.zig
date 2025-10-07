const std = @import("std");

// Import the native plugin interface
// Note: In a real plugin, you'd import this from grim's runtime module
// For this example, we'll define the necessary types inline

const NativePluginInfo = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    api_version: u32,
};

const GRIM_PLUGIN_API_VERSION: u32 = 1;

// Plugin metadata
pub export fn grim_plugin_info() callconv(.c) NativePluginInfo {
    return .{
        .name = "native-hello",
        .version = "1.0.0",
        .author = "Grim Team",
        .api_version = GRIM_PLUGIN_API_VERSION,
    };
}

// Plugin initialization
pub export fn grim_plugin_init() callconv(.c) bool {
    // Successfully initialized
    return true;
}

// Plugin setup (called after init)
pub export fn grim_plugin_setup() callconv(.c) void {
    // Setup complete - in a real plugin, this would initialize state,
    // register callbacks, set up resources, etc.
}

// Plugin teardown (called before unload)
pub export fn grim_plugin_teardown() callconv(.c) void {
    // Cleanup - in a real plugin, this would free resources,
    // unregister callbacks, etc.
}

// Example: Custom function that could be called via FFI
pub export fn native_hello_greet(name: [*:0]const u8) callconv(.c) void {
    _ = name;
    // In a real plugin, this might call back into grim's API
}

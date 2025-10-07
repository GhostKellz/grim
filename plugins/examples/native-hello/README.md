# Native Zig Plugin Example

This directory contains a complete example of a **native Zig plugin** for Grim - a plugin that compiles to a shared library (.so/.dll) and loads via C ABI instead of running in the Ghostlang interpreter.

## Overview

Native plugins offer:
- **Maximum Performance**: Direct compiled code, no interpretation overhead
- **Access to System APIs**: Full Zig standard library and C interop
- **Type Safety**: Compile-time guarantees from Zig's type system
- **Smaller Distribution**: No need to bundle interpreter runtime

Trade-offs:
- Must be compiled for each target platform
- More complex to develop than Ghostlang plugins
- Cannot hot-reload like scripted plugins

## File Structure

```
native-hello/
├── plugin.zig         # Native plugin source code
├── plugin.toml        # Plugin manifest
├── libnative-hello.so # Compiled shared library (Linux)
└── README.md          # This file
```

## Required Exports

Every native plugin MUST export these 4 functions with C calling convention:

### 1. `grim_plugin_info()` - Plugin Metadata
```zig
pub export fn grim_plugin_info() callconv(.c) NativePluginInfo {
    return .{
        .name = "native-hello",
        .version = "1.0.0",
        .author = "Your Name",
        .api_version = GRIM_PLUGIN_API_VERSION,  // Always use this constant
    };
}
```

### 2. `grim_plugin_init()` - Initialization
```zig
pub export fn grim_plugin_init() callconv(.c) bool {
    // Called once when plugin is loaded
    // Return true on success, false on failure
    return true;
}
```

### 3. `grim_plugin_setup()` - Setup (Optional)
```zig
pub export fn grim_plugin_setup() callconv(.c) void {
    // Called after successful init
    // Register callbacks, allocate resources, etc.
}
```

### 4. `grim_plugin_teardown()` - Cleanup (Optional)
```zig
pub export fn grim_plugin_teardown() callconv(.c) void {
    // Called before plugin unloads
    // Free resources, unregister callbacks, etc.
}
```

## Building

### For Linux
```bash
zig build-lib -dynamic -O ReleaseFast plugin.zig -femit-bin=libnative-hello.so
```

### For Windows
```bash
zig build-lib -dynamic -O ReleaseFast plugin.zig -femit-bin=native-hello.dll -target x86_64-windows
```

### For macOS
```bash
zig build-lib -dynamic -O ReleaseFast plugin.zig -femit-bin=libnative-hello.dylib -target x86_64-macos
```

## Plugin Manifest

The `plugin.toml` tells Grim how to load the plugin:

```toml
[plugin]
name = "native-hello"
version = "1.0.0"
type = "native"  # IMPORTANT: Must be "native"
main = "libnative-hello.so"  # Platform-specific binary name

[native]
linux = "libnative-hello.so"
windows = "native-hello.dll"
macos = "libnative-hello.dylib"
```

## Important Constraints

### ⚠️ DO NOT use `std.debug.print` in plugins!
When code runs in a dynamically loaded library, `std.debug.print` can segfault because it tries to access stderr which may not be initialized properly. Instead:

- Return status codes via function return values
- Use callback functions provided by Grim's API
- Log via Grim's logging infrastructure (once implemented)

### ⚠️ Memory Management
- Allocations in the plugin must be freed in the plugin
- Do not pass ownership of plugin-allocated memory to Grim
- Use arena allocators for lifecycle-bound resources

### ⚠️ ABI Stability
- Always use `callconv(.c)` for exported functions
- Use `extern struct` for types crossing the FFI boundary
- Match the `GRIM_PLUGIN_API_VERSION` exactly

## Testing

From the grim project root:

```bash
# Run the simple test
zig build-exe test_native_simple.zig && ./test_native_simple

# Or use the full test
zig build && ./zig-out/bin/test_native_plugin
```

Expected output:
```
=== Simple Native Plugin Test ===

✓ Library opened
✓ Found grim_plugin_info
✓ Called grim_plugin_info
  Name: native-hello
  Version: 1.0.0
  Author: Grim Team
  API Version: 1

✓ Found grim_plugin_init
✓ Init returned: true

✓ Found grim_plugin_setup, calling...

✓ Test completed!
```

## Integration with Grim

Native plugins are loaded by `runtime.NativePluginLoader`:

```zig
const runtime = @import("runtime");

var loader = runtime.NativePluginLoader.init(allocator);
var plugin = try loader.load("plugins/native-hello/libnative-hello.so");
defer plugin.deinit();

// Plugin is now loaded and initialized
plugin.setup();  // Call setup if needed
// ... use plugin ...
plugin.teardown();  // Call teardown before deinit
```

## Advanced: Hybrid Plugins

You can create **hybrid plugins** that combine:
- Ghostlang scripts for high-level logic and hot-reload
- Native Zig code for performance-critical operations

See `runtime/plugin_loader.zig` for the hybrid plugin infrastructure.

## Next Steps

1. Add custom exported functions for your plugin's functionality
2. Create a Zig build.zig to automate compilation
3. Add cross-platform conditional compilation
4. Implement proper error handling and logging
5. Create unit tests for your plugin

## API Reference

See:
- `runtime/native_plugin.zig` - Native plugin loading infrastructure
- `runtime/plugin_api.zig` - Plugin API definitions (when implemented)
- `runtime/plugin_loader.zig` - Unified plugin loading system

## License

MIT License - See main Grim repository for details.

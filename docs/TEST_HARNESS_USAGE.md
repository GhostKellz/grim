# Using Grim's TestHarness in External Projects

This guide shows how to use grim's `TestHarness` module in external projects like phantom.grim.

## Overview

Grim's TestHarness provides a comprehensive testing framework for Zig plugins and runtime integration. Instead of copying files, you can fetch it directly via `zig fetch` and use it as a dependency.

## Setup for phantom.grim

### 1. Add grim as a dependency

In your `build.zig.zon`:

```zig
.{
    .name = "phantom.grim",
    .version = "0.1.0",
    .dependencies = .{
        // Add grim with test harness export enabled
        .grim = .{
            .url = "https://github.com/yourusername/grim/archive/<commit-hash>.tar.gz",
            .hash = "<hash-will-be-generated>",
        },
    },
}
```

### 2. Fetch and save the dependency

```bash
cd /data/projects/phantom.grim
zig fetch --save https://github.com/yourusername/grim/archive/main.tar.gz
```

This will:
- Download grim
- Generate the hash
- Update `build.zig.zon`

### 3. Use TestHarness in build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get grim dependency with test harness enabled
    const grim = b.dependency("grim", .{
        .target = target,
        .optimize = optimize,
        .@"export-test-harness" = true, // Enable test harness export
    });

    // Access the test_harness module
    const test_harness_mod = grim.module("test_harness");

    // Your module that needs TestHarness
    const your_mod = b.createModule(.{
        .root_source_file = b.path("src/your_module.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "test_harness", .module = test_harness_mod },
        },
    });

    // Use in tests
    const tests = b.addTest(.{
        .root_module = your_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
```

### 4. Use TestHarness in your code

```zig
const std = @import("std");
const TestHarness = @import("test_harness").TestHarness;

test "my plugin test" {
    const allocator = std.testing.allocator;

    // Create test harness
    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    // Load plugin
    try harness.loadPlugin("path/to/plugin.gza");

    // Execute tests
    harness.executeCommand("test_hello");

    // Verify results
    const output = harness.getOutput();
    try std.testing.expectEqualStrings("Hello from plugin!", output);
}
```

## Available Build Options

When using grim as a dependency, you can enable:

```zig
const grim = b.dependency("grim", .{
    .target = target,
    .optimize = optimize,
    .@"export-test-harness" = true,  // Export TestHarness module
    .ghostlang = true,                // Enable Ghostlang support
});
```

## Accessing Grim Modules

With test harness enabled, you can access:

```zig
// Test harness for plugin testing
const test_harness = grim.module("test_harness");

// Other grim modules (optional)
const grim_runtime = grim.module("runtime"); // If you need runtime
const grim_core = grim.module("core");       // If you need core
```

## Example: phantom.grim Integration

Complete `build.zig` example for phantom.grim:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get grim with test harness
    const grim = b.dependency("grim", .{
        .target = target,
        .optimize = optimize,
        .@"export-test-harness" = true,
    });

    // Your phantom.grim module
    const phantom_grim_mod = b.createModule(.{
        .root_source_file = b.path("src/phantom_grim.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "test_harness", .module = grim.module("test_harness") },
        },
    });

    // Tests
    const tests = b.addTest(.{
        .root_module = phantom_grim_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run phantom.grim tests");
    test_step.dependOn(&run_tests.step);

    // Optional: Executable
    const exe = b.addExecutable(.{
        .name = "phantom-grim",
        .root_module = phantom_grim_mod,
    });

    b.installArtifact(exe);
}
```

## Local Development (Using File Path)

During development, you can use a local path instead of fetching:

```zig
// In build.zig.zon
.dependencies = .{
    .grim = .{
        .path = "../grim", // Local path to grim
    },
},
```

This is useful when developing both projects simultaneously.

## Testing the Setup

1. **Verify the dependency**:
   ```bash
   zig build --help
   ```
   Should show grim's build options.

2. **Build tests**:
   ```bash
   zig build test
   ```

3. **Check module access**:
   ```zig
   const TestHarness = @import("test_harness").TestHarness;
   // Should compile without errors
   ```

## TestHarness API Reference

### Initialization

```zig
pub fn init(allocator: std.mem.Allocator) !*TestHarness
pub fn deinit(self: *TestHarness) void
```

### Plugin Management

```zig
pub fn loadPlugin(self: *TestHarness, path: []const u8) !void
pub fn unloadPlugin(self: *TestHarness) void
pub fn reloadPlugin(self: *TestHarness) !void
```

### Execution

```zig
pub fn executeCommand(self: *TestHarness, command: []const u8) !void
pub fn executeFunction(self: *TestHarness, func_name: []const u8) !void
```

### Assertions

```zig
pub fn expectOutput(self: *TestHarness, expected: []const u8) !void
pub fn expectError(self: *TestHarness, expected_error: anyerror) !void
pub fn getOutput(self: *const TestHarness) []const u8
```

### State Management

```zig
pub fn reset(self: *TestHarness) void
pub fn captureOutput(self: *TestHarness, enable: bool) void
```

## Migration from Copied Files

If you were previously copying `test_harness.zig`:

**Before**:
```
phantom.grim/
├── vendor/
│   └── test_harness.zig  ← Copied from grim
└── src/
    └── tests.zig
```

**After**:
```
phantom.grim/
├── build.zig      ← Add grim dependency
├── build.zig.zon  ← Add grim to dependencies
└── src/
    └── tests.zig  ← Import from "test_harness"
```

Simply:
1. Delete `vendor/test_harness.zig`
2. Add grim to `build.zig.zon`
3. Update `build.zig` as shown above
4. Change imports: `@import("../vendor/test_harness.zig")` → `@import("test_harness")`

## Troubleshooting

### Error: Module 'test_harness' not found

**Solution**: Ensure `.@"export-test-harness" = true` is set in build.zig:
```zig
const grim = b.dependency("grim", .{
    .@"export-test-harness" = true,  // ← Don't forget this!
});
```

### Error: Hash mismatch

**Solution**: Delete the old hash and let Zig regenerate it:
```bash
zig fetch --save https://github.com/yourusername/grim/archive/main.tar.gz
```

### Error: Dependency not found

**Solution**: Run `zig fetch` first:
```bash
zig fetch
zig build
```

## Benefits Over Copying Files

✅ **Always up-to-date**: Fetch latest grim changes with `zig fetch`
✅ **No duplication**: Single source of truth
✅ **Dependency management**: Zig handles versioning
✅ **Cleaner repo**: No vendored copies
✅ **Easy updates**: `zig fetch --save <new-url>`

## Example: Full phantom.grim Test Suite

```zig
const std = @import("std");
const TestHarness = @import("test_harness").TestHarness;

test "phantom.grim: basic plugin loading" {
    const allocator = std.testing.allocator;

    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    try harness.loadPlugin("plugins/hello.gza");
    try harness.executeFunction("greet");
    try harness.expectOutput("Hello, world!");
}

test "phantom.grim: error handling" {
    const allocator = std.testing.allocator;

    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    try harness.loadPlugin("plugins/test.gza");
    try harness.expectError(error.InvalidArgument);
}

test "phantom.grim: plugin hot reload" {
    const allocator = std.testing.allocator;

    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    try harness.loadPlugin("plugins/counter.gza");
    try harness.executeCommand("increment");
    try harness.expectOutput("Count: 1");

    // Reload plugin
    try harness.reloadPlugin();
    try harness.executeCommand("get_count");
    try harness.expectOutput("Count: 0"); // State reset
}
```

## Publishing Your Package

Once set up, phantom.grim can be published and others can fetch it the same way:

```zig
// In someone else's project
const phantom_grim = b.dependency("phantom_grim", .{
    .target = target,
    .optimize = optimize,
});
```

Chain of dependencies:
```
User Project
    └── phantom.grim
            └── grim (with test_harness)
```

---

**Questions?** Check the [grim repository](https://github.com/yourusername/grim) or open an issue.

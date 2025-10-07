# Ghostlang Integration Issues - Help Needed! 🙏

## TL;DR
We've integrated Ghostlang into Grim's plugin system, but even minimal `.gza` scripts fail to parse with `error.ParseError` in `parsePrimary`. Need help understanding what we're doing wrong!

---

## What We're Building

**Grim Plugin System** with three-tier architecture:
1. **Ghostlang plugins** (.gza scripts) - for extensibility and hot-reload
2. **Native Zig plugins** (.so/.dll) - for performance (this works! ✅)
3. **TOML manifests** - for plugin metadata

### Current Status
- ✅ Plugin discovery and manifest parsing works
- ✅ Native (.so) plugin loading works perfectly
- ❌ Ghostlang (.gza) compilation fails on even trivial scripts

---

## The Problem

### Minimal Reproduction

**Script:** `plugins/examples/hello-world/init.gza`
```ghostlang
// Minimal test
const message = "Plugin loaded"

fn setup() {
    print(message)
}
```

**Error:**
```
info: Loading plugin: hello-world v1.0.0
debug: Compiling hello-world...
error: InvalidScript
/home/chris/.cache/zig/p/ghostlang-0.1.0-_SzSPTmiBQDNBVoKrlD3968nr64-NeIhF0MdXxAWMHNr/src/root.zig:6779:9: 0x127e8cd in parsePrimary (root.zig)
        return error.ParseError;
        ^
```

**Full trace:** [shows it fails in `parsePrimary` → `parseFactor` → `parseUnary` → etc.]

### Our Setup

**Ghostlang Version:** `0.1.0-_SzSPTmiBQDNBVoKrlD3968nr64-NeIhF0MdXxAWMHNr` (from zig package manager)

**How we're calling it:** `host/ghostlang.zig:529-560`
```zig
pub fn compilePluginScript(self: *Host, script_source: []const u8) Error!CompiledPlugin {
    const engine = try self.ensureEngine();
    self.pending_error = null;

    var actions: std.ArrayList(Action) = .{};
    var actions_valid = true;
    errdefer if (actions_valid) actions.deinit(self.allocator);

    const script_ptr = self.allocator.create(ghostlang.Script) catch |err| {
        return self.mapAllocatorError(err);
    };
    errdefer self.allocator.destroy(script_ptr);

    // Try to load the script
    script_ptr.* = engine.loadScript(script_source) catch |err| {
        self.allocator.destroy(script_ptr);
        return self.mapExecutionError(err);  // <-- Fails here
    };

    // ... rest of setup
}
```

**ensureEngine setup:** `host/ghostlang.zig:582-607`
```zig
fn ensureEngine(self: *Host) !*ghostlang.Engine {
    if (self.engine) |engine| {
        return engine;
    }

    const engine_ptr = try self.allocator.create(ghostlang.Engine);
    errdefer self.allocator.destroy(engine_ptr);

    const memory_limit = self.config.memory_limit_mb * 1024 * 1024;
    engine_ptr.* = try ghostlang.Engine.init(
        self.allocator,
        .{
            .memory_limit = memory_limit,
            .execution_timeout = self.config.execution_timeout_ms,
        },
    );

    self.engine = engine_ptr;
    return engine_ptr;
}
```

---

## What We've Tried

### Attempt 1: Original plugin syntax
```ghostlang
export fn setup() {
    grim.command("Hello", hello_command)
}
```
**Result:** ParseError

### Attempt 2: Changed to `fn` instead of `export fn`
```ghostlang
fn setup() {
    register_command("Hello", "hello_command", "Say hello")
}
```
**Result:** ParseError

### Attempt 3: Ultra-minimal (just shown above)
```ghostlang
const message = "Plugin loaded"

fn setup() {
    print(message)
}
```
**Result:** Still ParseError! 😢

---

## Questions for Ghostlang Devs

1. **Is our syntax correct?** We based it on these examples we found:
   - `syntax/tree-sitter-ghostlang/tmp/function.gza`
   - `example.gza`
   - `test.gza`

2. **Do we need to configure the parser differently for plugin scripts?**
   - Is there a "module mode" vs "script mode"?
   - Should we pre-register globals before parsing?

3. **Are we using the right Engine initialization?**
   ```zig
   ghostlang.Engine.init(allocator, .{
       .memory_limit = 64 * 1024 * 1024,
       .execution_timeout = 5000,
   })
   ```

4. **Does `loadScript()` expect something specific in the script?**
   - Does it need a `main()` function?
   - Should we call something else for plugin-style code?

5. **Could you provide a minimal working example of:**
   - Creating an Engine
   - Loading a script with function definitions
   - Calling those functions from Zig

---

## Our Environment

- **Zig Version:** 0.16.0-dev
- **Platform:** Linux 6.16.9 (x86_64)
- **Ghostlang:** From Zig package manager (`build.zig.zon`)

**Dependency declaration:**
```zig
.ghostlang = .{
    .url = "https://github.com/ghostlang/ghostlang/archive/<hash>.tar.gz",
    .hash = "...",
},
```

---

## What Works (for context)

Just to show our integration isn't completely broken:

### ✅ Plugin Discovery
```
✓ Added search path: plugins/examples
info: Discovered plugin: hello-world v1.0.0 at plugins/examples/hello-world
info: Discovered plugin: status-line v1.0.0 at plugins/examples/status-line
✓ Discovered 3 plugin(s)
```

### ✅ Native Plugin Loading
```
=== Simple Native Plugin Test ===
✓ Library opened
✓ Found grim_plugin_info
✓ Called grim_plugin_info
  Name: native-hello
  Version: 1.0.0
✓ Plugin setup complete!
```

### ✅ File Loading
The script file loads correctly:
```zig
const script_content = try std.fs.cwd().readFileAlloc(
    script_path,
    self.allocator,
    .limited(10 * 1024 * 1024),
);
// script_content has the right contents, we verified this
```

---

## How You Can Help

1. **Point us to working examples** of Ghostlang engine usage
2. **Suggest what we're doing wrong** in our parser setup
3. **Provide a minimal Zig test** that loads and executes a Ghostlang script
4. **Tell us if there's a version mismatch** or known issue

We're happy to:
- Test patches
- Provide more debugging output
- Try different approaches
- Contribute fixes back if we find the issue

---

## Test Files

**Full test program:** `test_ghostlang_plugin.zig`
**Integration code:** `host/ghostlang.zig` (lines 529-607)
**Plugin loader:** `runtime/plugin_loader.zig` (lines 111-147)

**To reproduce:**
```bash
git clone <our-repo>
cd grim
zig build
./zig-out/bin/test_ghostlang_plugin
```

---

## Thank You! 🙏

We're really excited about using Ghostlang for our plugin system - the combination of:
- Safe sandboxing
- Hot-reload capability
- Familiar syntax
- Zig integration

...is exactly what we need! Any help debugging this would be hugely appreciated.

---

**Contact:**
- GitHub Issues: [link]
- Discord: [if applicable]
- Email: [if you want]

**Our Repository:** `grim` - Modal text editor with Ghostlang plugins

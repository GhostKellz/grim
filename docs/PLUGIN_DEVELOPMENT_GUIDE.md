# Grim Plugin Development Guide
**Complete guide to writing plugins for the Grim editor**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Plugin Types](#plugin-types)
3. [Quick Start](#quick-start)
4. [Plugin Architecture](#plugin-architecture)
5. [Ghostlang API Reference](#ghostlang-api-reference)
6. [Native Plugin Development](#native-plugin-development)
7. [Security & Sandboxing](#security--sandboxing)
8. [Testing](#testing)
9. [Distribution](#distribution)
10. [Examples](#examples)

---

## Introduction

Grim plugins extend the editor with new functionality using **Ghostlang** (`.gza` scripts) or **native Zig** code. Plugins can:

- Add commands (`:MyCommand`)
- Register keybindings (`<leader>ff`)
- Handle events (file open, buffer change)
- Integrate with external tools (AI, LSP, Git)
- Customize UI (themes, statusline, file tree)

### Why Grim Plugins?

**Better than Vim/Neovim:**
- **Performance:** Native Zig backend, 10x faster than VimL
- **Modern:** Real async/await via zsync, not callbacks
- **Safe:** Sandboxed tiers prevent malicious plugins
- **Smart updates:** Binary cache + git hybrid (no rebuild every update)
- **Hot reload:** Edit plugin, save, changes apply instantly

**Better than VSCode:**
- **No Electron:** Native code, 45ms startup vs 2s
- **True extensibility:** Full editor API access
- **Local-first:** Works offline, no telemetry

---

## Plugin Types

### Tier 1: Ghostlang Scripts (.gza)

**Best for:** 95% of plugins (UI, commands, keybindings)

```lua
-- plugins/my-plugin/init.gza
local grim = require("grim")

function setup()
    grim.register_command("Hello", function()
        grim.print("Hello from my plugin!")
    end)
end

return { setup = setup }
```

**Characteristics:**
- Interpreted (no compilation)
- Hot reload support
- Cross-platform automatically
- ~10x slower than native (but still fast enough)

### Tier 2: Auto-Optimized Plugins

**Grim automatically compiles hot functions to Zig!**

```toml
# plugin.toml
[optimize]
hot_functions = ["fuzzy_search"]  # Grim compiles these
compile_on_install = true
```

**Characteristics:**
- Write .gza, Grim makes it fast
- No manual work
- Near-native performance for hot paths

### Tier 3: Native Zig Plugins (.zig)

**Best for:** Performance-critical code (fuzzy matching, parsing, GPU)

```zig
// native.zig
pub export fn fast_search(query: [*:0]const u8) callconv(.C) Results {
    // Hand-tuned native code
    // 100x faster than interpreted
}
```

**Characteristics:**
- Maximum performance
- Full Zig power
- Requires compilation
- Platform-specific builds

---

## Quick Start

### 1. Create Plugin Directory

```bash
mkdir -p ~/.config/grim/plugins/my-plugin
cd ~/.config/grim/plugins/my-plugin
```

### 2. Create Manifest

```toml
# plugin.toml
[plugin]
name = "my-plugin"
version = "1.0.0"
author = "Your Name"
description = "My first Grim plugin"
main = "init.gza"
license = "MIT"

[config]
enable_on_startup = true
```

### 3. Write Plugin

```lua
-- init.gza
local grim = require("grim")

local function my_command()
    local line = grim.buffer.get_current_line()
    grim.print("Current line: " .. line)
end

function setup()
    grim.register_command("MyCommand", my_command, "Print current line")
    grim.register_keymap("n", "<leader>mp", my_command, "My Plugin: show line")
end

return { setup = setup }
```

### 4. Load Plugin

```bash
# Restart Grim or run
:PluginReload my-plugin
```

### 5. Test It

```
:MyCommand
# or press <leader>mp
```

**That's it!** You've created a Grim plugin.

---

## Plugin Architecture

### Plugin Lifecycle

```
1. Discovery
   ↓
   Grim scans plugin directories
   Finds plugin.toml manifests

2. Loading
   ↓
   Parse manifest
   Check dependencies
   Load .gza script into Ghostlang VM

3. Setup
   ↓
   Call plugin.setup()
   Register commands/keymaps/events

4. Runtime
   ↓
   User triggers command
   Ghostlang calls your function
   Function accesses Grim API

5. Reload (Hot Reload)
   ↓
   Plugin file changes
   Grim reloads script
   Re-run setup()

6. Unload
   ↓
   Remove commands/keymaps
   Call plugin.teardown() if exists
   Free resources
```

### Directory Structure

```
~/.config/grim/plugins/
├── my-plugin/
│   ├── plugin.toml          # Manifest (required)
│   ├── init.gza             # Entry point (required)
│   ├── native.zig           # Optional: Native code
│   ├── README.md            # Documentation
│   └── examples/            # Usage examples
│
├── .cache/                  # Auto-generated
│   └── my-plugin/
│       └── optimized.so     # JIT compiled code
│
└── plugins.lock             # Resolved versions (like Cargo.lock)
```

### Plugin Directories (Search Order)

1. `./plugins/` (project-local)
2. `$XDG_DATA_HOME/grim/plugins/`
3. `~/.local/share/grim/plugins/`
4. `~/.config/grim/plugins/`
5. `/usr/share/grim/plugins/`
6. `/usr/local/share/grim/plugins/`

---

## Ghostlang API Reference

### Buffer Operations

```lua
-- Get/set buffer content
local text = grim.buffer.get_all()
grim.buffer.set_all("new content")

-- Get/set lines
local line = grim.buffer.get_line(10)
grim.buffer.set_line(10, "new line")
local lines = grim.buffer.get_lines(1, 100)

-- Insert/delete
grim.buffer.insert(100, "text to insert")
grim.buffer.delete(100, 120)  -- delete chars 100-120

-- Buffer info
local len = grim.buffer.length()
local line_count = grim.buffer.line_count()
```

### Cursor & Selection

```lua
-- Cursor position
local pos = grim.cursor.get_position()  -- { line, col, byte_offset }
grim.cursor.set_position(10, 5)

-- Movement
grim.cursor.move_to_line_start()
grim.cursor.move_to_line_end()
grim.cursor.move_to_buffer_start()
grim.cursor.move_to_buffer_end()

-- Selection
local selection = grim.selection.get()  -- { start, end }
grim.selection.set(100, 200)
grim.selection.clear()
local text = grim.selection.get_text()
```

### Commands

```lua
-- Register command
grim.register_command("MyCommand", function()
    grim.print("Command executed!")
end, "Optional description")

-- Execute command
grim.command("OtherCommand")

-- Command with arguments
grim.register_command("Greet", function(args)
    grim.print("Hello, " .. args[1])
end)
```

### Keymaps

```lua
-- Register keymap
-- grim.register_keymap(mode, keys, handler, description)

grim.register_keymap("n", "<leader>ff", function()
    -- Your code here
end, "Fuzzy find files")

-- Modes: "n" (normal), "i" (insert), "v" (visual)

-- Multiple keys
grim.register_keymap("n", "gcc", comment_line)
grim.register_keymap("v", "gc", comment_selection)
```

### Events

```lua
-- Register event handler
grim.register_event("BufEnter", function(buf_id)
    grim.print("Entered buffer: " .. buf_id)
end)

-- Available events:
-- - BufEnter, BufLeave
-- - BufWritePre, BufWritePost
-- - InsertEnter, InsertLeave
-- - CursorMoved
-- - FileOpen
```

### UI

```lua
-- Print to statusline/message area
grim.print("Hello!")
grim.error("Something went wrong!")
grim.warn("Warning message")
grim.info("Info message")

-- Input from user
local input = grim.ui.input("Enter text: ")
local choice = grim.ui.confirm("Are you sure?")  -- true/false

-- Menus
grim.ui.menu({
    { label = "Option 1", action = function() end },
    { label = "Option 2", action = function() end },
})
```

### File System

```lua
-- File operations
local content = grim.fs.read_file("/path/to/file")
grim.fs.write_file("/path/to/file", "content")
local exists = grim.fs.exists("/path")
local is_dir = grim.fs.is_directory("/path")

-- List directory
local entries = grim.fs.list_directory("/path")
for _, entry in ipairs(entries) do
    print(entry.name, entry.is_dir)
end

-- Path operations
local abs = grim.fs.absolute_path("relative/path")
local joined = grim.fs.join_path("dir", "file.txt")
```

### Shell Integration

```lua
-- Execute shell command
local result = grim.shell.exec("git status")
print(result.stdout)
print(result.stderr)
print(result.exit_code)

-- With options
local result = grim.shell.exec("ls", {
    cwd = "/tmp",
    timeout = 5000,  -- milliseconds
})

-- Async execution
grim.shell.exec_async("long-running-command", function(result)
    grim.print("Done: " .. result.stdout)
end)
```

### External Tools

```lua
-- Fuzzy finder
grim.fuzzy.find_files("/path", 3)  -- depth 3
local results = grim.fuzzy.search("query")
for _, result in ipairs(results) do
    print(result.path, result.score)
end

-- Git
grim.git.status()
grim.git.diff()
grim.git.add("file.txt")
grim.git.commit("message")

-- LSP
grim.lsp.definition()
grim.lsp.hover()
grim.lsp.references()
grim.lsp.rename("new_name")
```

### AI Integration (via Thanos)

```lua
-- AI completion
local completion = grim.ai.complete({
    prompt = "Write a function to reverse a string",
    language = "zig",
    provider = "auto",  -- or "claude", "gpt4", "ollama"
})
grim.buffer.insert_at_cursor(completion)

-- Ask AI
local answer = grim.ai.ask("How do I reverse a string in Zig?")
grim.print(answer)

-- Switch provider
grim.ai.set_provider("ollama")  -- Use local Ollama
```

### Theme API

```lua
-- Register theme
grim.theme.register("my-theme", {
    background = "#1a1a1a",
    foreground = "#e0e0e0",
    cursor = "#00ff00",
    -- ... more colors
})

-- Set theme
grim.theme.set("my-theme")

-- Get current theme colors
local colors = grim.theme.get_colors()
```

### Settings

```lua
-- Get/set settings
local tab_size = grim.settings.get("tab_size")
grim.settings.set("tab_size", 4)

-- Observe setting changes
grim.settings.observe("tab_size", function(old_val, new_val)
    grim.print("Tab size changed from " .. old_val .. " to " .. new_val)
end)
```

### HTTP Client

```lua
-- Make HTTP requests
local response = grim.http.get("https://api.example.com/data")
print(response.status)
print(response.body)

local response = grim.http.post("https://api.example.com/data", {
    headers = { ["Content-Type"] = "application/json" },
    body = '{"key":"value"}'
})
```

### Timers & Async

```lua
-- Delay execution
grim.timer.after(1000, function()  -- 1000ms = 1s
    grim.print("Delayed message!")
end)

-- Repeat
local timer_id = grim.timer.every(5000, function()
    grim.print("Every 5 seconds")
end)

-- Cancel timer
grim.timer.cancel(timer_id)

-- Async operations
grim.async(function()
    local result1 = await(grim.shell.exec_async("command1"))
    local result2 = await(grim.shell.exec_async("command2"))
    grim.print("Both done!")
end)
```

### Native FFI

```lua
-- Call native function from plugin
-- (Only works if plugin has native.zig)
local result = grim.call_native("fast_search", "query string")
```

---

## Native Plugin Development

### When to Use Native Plugins

**Use Ghostlang (.gza) if:**
- UI logic
- Command registration
- File operations
- Most plugins (95%)

**Use Native Zig if:**
- CPU-intensive algorithms (fuzzy matching, parsing)
- GPU operations
- Low-level system integration
- Need <1ms latency

### Native Plugin Structure

```
my-native-plugin/
├── plugin.toml
├── init.gza              # Ghostlang wrapper
├── src/
│   └── native.zig        # Native implementation
└── build.zig             # Zig build script
```

### Example: Native Function

```zig
// src/native.zig
const std = @import("std");

// Export C-ABI function for Ghostlang FFI
pub export fn fast_fibonacci(n: u32) callconv(.C) u64 {
    if (n <= 1) return n;

    var a: u64 = 0;
    var b: u64 = 1;
    var i: u32 = 2;

    while (i <= n) : (i += 1) {
        const tmp = a + b;
        a = b;
        b = tmp;
    }

    return b;
}

// Plugin info (required)
pub export fn grim_plugin_info() callconv(.C) *const NativePluginInfo {
    const info = NativePluginInfo{
        .name = "my-native-plugin",
        .version = "1.0.0",
        .author = "Your Name",
        .api_version = 1,
    };
    return &info;
}

const NativePluginInfo = extern struct {
    name: [*:0]const u8,
    version: [*:0]const u8,
    author: [*:0]const u8,
    api_version: u32,
};
```

### Ghostlang Wrapper

```lua
-- init.gza
local grim = require("grim")

-- Load native library
local native = grim.load_native("libmyplugin.so")

function setup()
    grim.register_command("Fibonacci", function(args)
        local n = tonumber(args[1]) or 10
        -- Call native function
        local result = native.fast_fibonacci(n)
        grim.print("Fibonacci(" .. n .. ") = " .. result)
    end, "Calculate Fibonacci number (native)")
end

return { setup = setup }
```

### Build Script

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build shared library
    const lib = b.addSharedLibrary(.{
        .name = "myplugin",
        .root_source_file = b.path("src/native.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);
}
```

### Build & Install

```bash
# Build native library
zig build -Doptimize=ReleaseFast

# Install to plugin directory
cp zig-out/lib/libmyplugin.so ~/.config/grim/plugins/my-native-plugin/
```

---

## Security & Sandboxing

### Security Tiers

Grim plugins run in three security tiers:

#### Tier 1: Trusted (Default)
- Full editor API access
- File system read/write anywhere
- Network access
- Shell execution

**Use for:** Your own plugins, official plugins

#### Tier 2: Restricted
- Editor API access (buffer, cursor, commands)
- File system: Read-only, limited to project directory
- No network access
- No shell execution

**Use for:** Community plugins you trust

#### Tier 3: Sandboxed
- Read-only editor state
- No file system access
- No network access
- No shell execution

**Use for:** Untrusted plugins, plugins from unknown sources

### Setting Security Tier

```toml
# plugin.toml
[security]
tier = 2  # 1 (trusted), 2 (restricted), 3 (sandboxed)
```

### Permission Model

```toml
# plugin.toml
[permissions]
filesystem = "read"      # "none", "read", "write"
network = false
shell = false
api_access = ["buffer", "cursor"]  # Whitelist API modules
```

### Best Practices

1. **Principle of Least Privilege**
   - Request minimum permissions needed
   - Document why each permission is required

2. **Input Validation**
   ```lua
   function my_command(args)
       -- Validate input
       if not args[1] or args[1] == "" then
           grim.error("Missing argument")
           return
       end

       -- Sanitize paths
       local path = grim.fs.sanitize_path(args[1])
       -- ... use path
   end
   ```

3. **Error Handling**
   ```lua
   function risky_operation()
       local success, err = pcall(function()
           -- Your code
       end)

       if not success then
           grim.error("Operation failed: " .. err)
       end
   end
   ```

4. **Secrets Management**
   ```lua
   -- DON'T hardcode secrets
   -- local api_key = "sk-1234567890"  -- BAD!

   -- DO use environment variables or config files
   local api_key = os.getenv("MY_API_KEY") or
                   grim.settings.get("my_plugin.api_key")
   ```

---

## Testing

### Unit Tests

```lua
-- tests/test_my_plugin.gza
local my_plugin = require("my_plugin")

function test_fibonacci()
    assert(my_plugin.fibonacci(0) == 0, "fib(0) should be 0")
    assert(my_plugin.fibonacci(1) == 1, "fib(1) should be 1")
    assert(my_plugin.fibonacci(10) == 55, "fib(10) should be 55")
end

-- Run tests
grim.test.run(test_fibonacci)
```

### Integration Tests

```bash
# tests/integration_test.sh
#!/bin/bash

# Start Grim with plugin
grim --plugin my-plugin &
GRIM_PID=$!

# Give it time to start
sleep 2

# Send command via RPC
echo ':MyCommand' | grim-client --pid $GRIM_PID

# Check output
# ...

# Cleanup
kill $GRIM_PID
```

### Manual Testing

```bash
# Load plugin in development mode
grim --dev-plugin ~/.config/grim/plugins/my-plugin

# Enable debug logging
export GRIM_LOG=debug
grim
```

---

## Distribution

### Publishing to Plugin Registry

```bash
# Package plugin
grim-pkg build .

# This creates: dist/my-plugin-1.0.0.tar.gz

# Publish (future feature)
grim-pkg publish dist/my-plugin-1.0.0.tar.gz
```

### Plugin Registry Structure

```
https://plugins.grim.dev/
├── my-plugin/
│   ├── 1.0.0/
│   │   ├── linux-x86_64/
│   │   │   └── my-plugin-1.0.0.tar.gz
│   │   ├── macos-aarch64/
│   │   │   └── my-plugin-1.0.0.tar.gz
│   │   └── windows-x86_64/
│   │       └── my-plugin-1.0.0.tar.gz
│   └── manifest.json
```

### Installation

```bash
# Install from registry
grim plugin install my-plugin

# Install from git
grim plugin install github:user/my-plugin

# Install from local path
grim plugin install ~/Projects/my-plugin
```

### Update Strategy

```toml
# plugin.toml
[update]
strategy = "smart"  # binary cache + git fallback
git_url = "https://github.com/user/my-plugin"
prefer_binary = true

[update.cache]
url = "https://plugins.grim.dev/{name}/{version}/{platform}"
```

---

## Examples

### Example 1: Simple Command Plugin

```lua
-- plugins/hello-world/init.gza
local grim = require("grim")

function setup()
    grim.register_command("HelloWorld", function()
        grim.print("Hello from plugin!")
    end, "Print hello message")
end

return { setup = setup }
```

### Example 2: Git Integration

```lua
-- plugins/git-signs/init.gza
local grim = require("grim")

local function show_git_status()
    local result = grim.shell.exec("git status --short")
    if result.exit_code == 0 then
        grim.ui.menu_from_lines(result.stdout, function(selected)
            grim.print("Selected: " .. selected)
        end)
    else
        grim.error("Not a git repository")
    end
end

function setup()
    grim.register_command("GitStatus", show_git_status)
    grim.register_keymap("n", "<leader>gs", show_git_status)

    -- Update git signs on buffer change
    grim.register_event("BufWritePost", function()
        -- Update git diff indicators
    end)
end

return { setup = setup }
```

### Example 3: Fuzzy Finder

```lua
-- plugins/fuzzy-finder/init.gza
local grim = require("grim")

local function fuzzy_find_files()
    local cwd = grim.fs.cwd()
    local files = grim.fuzzy.find_files(cwd, 5)  -- depth 5

    grim.ui.fuzzy_menu(files, function(selected)
        grim.command("edit " .. selected)
    end)
end

function setup()
    grim.register_command("FuzzyFiles", fuzzy_find_files)
    grim.register_keymap("n", "<leader>ff", fuzzy_find_files)
end

return { setup = setup }
```

### Example 4: AI Completion

```lua
-- plugins/ai-complete/init.gza
local grim = require("grim")

local function ai_complete_at_cursor()
    -- Get context
    local line = grim.cursor.get_position().line
    local context_lines = grim.buffer.get_lines(math.max(1, line - 10), line)
    local context = table.concat(context_lines, "\n")

    -- Get file type
    local file_type = grim.buffer.get_filetype()

    -- Request completion
    grim.print("Requesting AI completion...")

    grim.async(function()
        local completion = await(grim.ai.complete({
            prompt = context,
            language = file_type,
            max_tokens = 100,
        }))

        grim.buffer.insert_at_cursor(completion)
        grim.print("Completion inserted!")
    end)
end

function setup()
    grim.register_command("AIComplete", ai_complete_at_cursor)
    grim.register_keymap("n", "<leader>ac", ai_complete_at_cursor)
end

return { setup = setup }
```

### Example 5: Status Line Plugin

```lua
-- plugins/statusline/init.gza
local grim = require("grim")

local function render_statusline()
    -- Get info
    local mode = grim.editor.get_mode()
    local file = grim.buffer.get_filename() or "[No Name]"
    local pos = grim.cursor.get_position()
    local line_count = grim.buffer.line_count()
    local modified = grim.buffer.is_modified() and "[+]" or ""

    -- Git branch
    local git_branch = ""
    local result = grim.shell.exec("git rev-parse --abbrev-ref HEAD")
    if result.exit_code == 0 then
        git_branch = " (" .. result.stdout:gsub("\n", "") .. ")"
    end

    -- Build statusline
    return string.format(
        " %s | %s%s%s | %d:%d | %d%%",
        mode,
        file,
        modified,
        git_branch,
        pos.line,
        pos.col,
        math.floor(pos.line / line_count * 100)
    )
end

function setup()
    -- Update statusline on events
    grim.register_event("CursorMoved", function()
        grim.statusline.set(render_statusline())
    end)

    grim.register_event("BufEnter", function()
        grim.statusline.set(render_statusline())
    end)

    grim.register_event("ModeChanged", function()
        grim.statusline.set(render_statusline())
    end)
end

return { setup = setup }
```

---

## Advanced Topics

### Plugin Dependencies

```toml
# plugin.toml
[dependencies]
requires = ["fuzzy-finder", "git-signs"]  # Must be installed
optional = ["lsp-support"]                # Enhances if present
conflicts = ["old-fuzzy-finder"]          # Cannot coexist
```

```lua
-- init.gza
local grim = require("grim")

function setup()
    -- Check if optional dependency is available
    if grim.plugin.is_loaded("lsp-support") then
        -- Use LSP features
    end
end
```

### Plugin Configuration

```toml
# plugin.toml
[config]
default_provider = "ollama"
max_tokens = 100
```

```lua
-- init.gza
function setup(opts)
    local provider = opts.default_provider or "ollama"
    local max_tokens = opts.max_tokens or 100
    -- Use config
end
```

User config:
```lua
-- ~/.config/grim/init.lua
require("my-plugin").setup({
    default_provider = "claude",
    max_tokens = 200,
})
```

### Hot Reload Development

```bash
# Watch plugin files
grim --dev-plugin ~/.config/grim/plugins/my-plugin

# Changes automatically reload!
```

In plugin:
```lua
-- init.gza
local state = {}

function setup()
    -- This runs on every reload
    -- Don't lose state!
end

function teardown()
    -- Optional: cleanup before reload
    return state  -- State preserved across reloads
end
```

### Performance Optimization

**Profile your plugin:**
```lua
local start = grim.timer.now()
-- Your code here
local elapsed = grim.timer.now() - start
grim.print("Took " .. elapsed .. "ms")
```

**Mark hot functions for JIT compilation:**
```toml
# plugin.toml
[optimize]
hot_functions = ["fuzzy_search", "parse_large_file"]
compile_on_install = true
profile_runtime = true  # Auto-detect hot paths
```

---

## Troubleshooting

### Plugin Not Loading

```bash
# Check plugin manager log
:PluginLog

# Reload specific plugin
:PluginReload my-plugin

# Check plugin manifest
grim-pkg info ~/.config/grim/plugins/my-plugin
```

### Debugging

```lua
-- Add debug prints
function setup()
    grim.print("DEBUG: setup() called")
    -- ...
end

-- Check Grim logs
-- ~/.local/share/grim/logs/plugin_manager.log
```

### Common Errors

**Error: "Plugin 'foo' not found"**
- Check plugin directory structure
- Ensure `plugin.toml` exists
- Verify plugin name matches directory name

**Error: "Function 'bar' not exported"**
- Check FFI exports in native.zig
- Ensure `callconv(.C)` is set
- Verify function signature matches Ghostlang call

**Error: "Permission denied"**
- Check security tier in plugin.toml
- Request appropriate permissions
- User may need to approve plugin

---

## Resources

- **API Reference:** See `PLUGIN_API.md`
- **Manifest Reference:** See `PLUGIN_MANIFEST.md`
- **Example Plugins:** See `/plugins/examples/`
- **Community Plugins:** https://plugins.grim.dev
- **Discord:** https://discord.gg/grim-editor

---

## Contributing

Have a great plugin? Share it!

1. Polish your plugin (docs, tests, examples)
2. Publish to GitHub
3. Submit to plugin registry
4. Share on Discord

**Happy plugin development!** 🚀

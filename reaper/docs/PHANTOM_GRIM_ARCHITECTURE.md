# Phantom.Grim Architecture: The Lazy.vim of Phantom

**Version:** 1.0
**Date:** 2025-10-10
**Status:** Architectural Blueprint

---

## Executive Summary

Phantom.grim is a **lazy.vim-style configuration framework** for the Grim editor, providing:

- 🚀 **Zero-config experience** - Works out of the box with sensible defaults
- ⚡ **Blazing performance** - Core written in Zig, plugins in Ghostlang
- 🔌 **Plugin ecosystem** - Modular, lazy-loaded, dependency-resolved
- 🛠️ **IDE features** - LSP, Tree-sitter, Git, Fuzzy finding, Diagnostics
- 🎨 **Theming system** - Hot-reloadable, declarative themes

This document outlines the complete architecture for making phantom.grim the definitive plugin management framework for Grim, mirroring the success of lazy.nvim for Neovim.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Components](#core-components)
3. [Plugin System](#plugin-system)
4. [Grim Runtime Integration](#grim-runtime-integration)
5. [Dependency Resolution](#dependency-resolution)
6. [Lazy Loading Strategy](#lazy-loading-strategy)
7. [Configuration API](#configuration-api)
8. [TestHarness Integration](#testharness-integration)
9. [Theme System](#theme-system)
10. [Plugin Development Workflow](#plugin-development-workflow)
11. [Implementation Roadmap](#implementation-roadmap)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Phantom.Grim                           │
│             "The Lazy.vim of Phantom"                       │
├─────────────────────────────────────────────────────────────┤
│  Configuration Layer (Ghostlang .gza)                       │
│  ├─ init.gza (user entry point)                            │
│  ├─ lazy_config.gza (plugin specs)                         │
│  ├─ keymaps.gza (user keybindings)                         │
│  └─ autocmds.gza (user autocmds)                           │
├─────────────────────────────────────────────────────────────┤
│  Plugin Management Layer (Zig)                              │
│  ├─ PluginRegistry (dependency resolution)                 │
│  ├─ PluginLoader (lazy loading engine)                     │
│  ├─ LazyLoader (event-based triggers)                      │
│  └─ PackageRegistry (binary .gza fetching)                 │
├─────────────────────────────────────────────────────────────┤
│  Grim Runtime Integration (Zig)                             │
│  ├─ TestHarness (from grim)                                │
│  ├─ Runtime (from grim)                                    │
│  ├─ Core (editor, buffer, rope from grim)                  │
│  ├─ LSP (from grim)                                        │
│  ├─ Syntax (grove tree-sitter from grim)                   │
│  └─ UI-TUI (SimpleTUI from grim)                           │
├─────────────────────────────────────────────────────────────┤
│  Core Services (Zig)                                        │
│  ├─ ConfigManager (TOML/GZA parsing)                       │
│  ├─ SyntaxHighlighter (tree-sitter integration)            │
│  ├─ GhostlangRuntime (plugin execution)                    │
│  ├─ ThemeManager (hot-reloadable themes)                   │
│  └─ MotionEngine (enhanced vim motions)                    │
├─────────────────────────────────────────────────────────────┤
│  Grim Editor Core (External Dependency)                     │
│  └─ github.com/ghostkellz/grim                             │
└─────────────────────────────────────────────────────────────┘
```

### Lazy.vim Comparison

| Feature | Lazy.nvim | Phantom.grim | Status |
|---------|-----------|--------------|--------|
| Plugin management | ✅ | ✅ | Complete |
| Lazy loading | ✅ | 🚧 | In progress |
| Dependency resolution | ✅ | 🚧 | Planned |
| Lock file | ✅ | ⬜ | Future |
| Plugin specs (declarative) | ✅ | ✅ | Complete |
| Hot reload | ✅ | ✅ | Complete |
| Plugin profiling | ✅ | ⬜ | Future |
| Health checks | ✅ | 🚧 | In progress |
| Plugin UI | ✅ | ⬜ | Planned |
| Git integration | ✅ | ⬜ | Planned |
| Auto-update | ✅ | ⬜ | Future |

**Legend:**
- ✅ Complete
- 🚧 In progress
- ⬜ Planned

---

## Core Components

### 1. PluginRegistry (Zig)

**Purpose:** Central registry for all plugins, handles dependency resolution.

**File:** `src/core/plugin_registry.zig`

```zig
pub const PluginRegistry = struct {
    allocator: std.mem.Allocator,
    plugins: std.StringHashMap(*PluginSpec),
    load_order: std.ArrayList([]const u8),

    pub const PluginSpec = struct {
        name: []const u8,
        version: []const u8,
        url: ?[]const u8, // GitHub URL or local path
        enabled: bool,
        lazy: bool,
        dependencies: [][]const u8,
        load_after: [][]const u8,
        priority: u32, // Higher = loads first

        // Lazy loading triggers
        event: ?[]const u8,        // "BufRead", "VimEnter"
        ft: ?[][]const u8,         // ["zig", "rust"]
        cmd: ?[][]const u8,        // ["Telescope"]
        keys: ?[][]const u8,       // ["<leader>f"]

        // Build options
        build: ?[]const u8,        // Build command
        config: ?[]const u8,       // Config function name
    };

    pub fn init(allocator: std.mem.Allocator) PluginRegistry {
        return .{
            .allocator = allocator,
            .plugins = std.StringHashMap(*PluginSpec).init(allocator),
            .load_order = std.ArrayList([]const u8).init(allocator),
        };
    }

    /// Register a plugin with the registry
    pub fn register(self: *PluginRegistry, spec: PluginSpec) !void {
        const name_copy = try self.allocator.dupe(u8, spec.name);
        const spec_ptr = try self.allocator.create(PluginSpec);
        spec_ptr.* = spec;
        try self.plugins.put(name_copy, spec_ptr);
    }

    /// Resolve dependency order using topological sort
    pub fn resolveDependencies(self: *PluginRegistry) !void {
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();

        var stack = std.ArrayList([]const u8).init(self.allocator);
        defer stack.deinit();

        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            if (!visited.contains(entry.key_ptr.*)) {
                try self.dfsTopologicalSort(entry.key_ptr.*, &visited, &stack);
            }
        }

        // Reverse to get correct load order
        self.load_order.clearRetainingCapacity();
        var i = stack.items.len;
        while (i > 0) {
            i -= 1;
            try self.load_order.append(stack.items[i]);
        }
    }

    fn dfsTopologicalSort(
        self: *PluginRegistry,
        name: []const u8,
        visited: *std.StringHashMap(bool),
        stack: *std.ArrayList([]const u8),
    ) !void {
        try visited.put(name, true);

        const spec = self.plugins.get(name) orelse return;

        // Visit dependencies first
        for (spec.dependencies) |dep| {
            if (!visited.contains(dep)) {
                try self.dfsTopologicalSort(dep, visited, stack);
            }
        }

        // Visit load_after dependencies
        for (spec.load_after) |dep| {
            if (!visited.contains(dep)) {
                try self.dfsTopologicalSort(dep, visited, stack);
            }
        }

        try stack.append(name);
    }

    pub fn deinit(self: *PluginRegistry) void {
        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.plugins.deinit();
        self.load_order.deinit();
    }
};
```

**Key Features:**
- Topological sort for dependency resolution
- Priority-based loading
- Lazy loading metadata storage
- Lock-free concurrent access (future)

---

### 2. LazyLoader (Zig)

**Purpose:** Event-driven plugin loading engine.

**File:** `src/core/lazy_loader.zig`

```zig
pub const LazyLoader = struct {
    allocator: std.mem.Allocator,
    registry: *PluginRegistry,
    runtime: *GhostlangRuntime,
    event_handlers: std.StringHashMap(std.ArrayList([]const u8)),
    loaded_plugins: std.StringHashMap(bool),

    pub const Event = enum {
        VimEnter,
        BufRead,
        BufNewFile,
        BufWritePost,
        InsertEnter,
        CursorHold,
        FileType,
        Command,
        Keymap,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        registry: *PluginRegistry,
        runtime: *GhostlangRuntime,
    ) LazyLoader {
        return .{
            .allocator = allocator,
            .registry = registry,
            .runtime = runtime,
            .event_handlers = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .loaded_plugins = std.StringHashMap(bool).init(allocator),
        };
    }

    /// Register lazy-loading triggers
    pub fn registerLazyTriggers(self: *LazyLoader) !void {
        var it = self.registry.plugins.iterator();
        while (it.next()) |entry| {
            const spec = entry.value_ptr.*;
            if (!spec.lazy) continue;

            // Register event triggers
            if (spec.event) |event| {
                var handlers = self.event_handlers.get(event) orelse blk: {
                    var list = std.ArrayList([]const u8).init(self.allocator);
                    try self.event_handlers.put(event, list);
                    break :blk self.event_handlers.getPtr(event).?;
                };
                try handlers.append(spec.name);
            }

            // Register filetype triggers
            if (spec.ft) |filetypes| {
                for (filetypes) |ft| {
                    const event_name = try std.fmt.allocPrint(
                        self.allocator,
                        "FileType:{s}",
                        .{ft},
                    );
                    defer self.allocator.free(event_name);

                    var handlers = self.event_handlers.get(event_name) orelse blk: {
                        var list = std.ArrayList([]const u8).init(self.allocator);
                        try self.event_handlers.put(event_name, list);
                        break :blk self.event_handlers.getPtr(event_name).?;
                    };
                    try handlers.append(spec.name);
                }
            }
        }
    }

    /// Trigger event and load associated plugins
    pub fn triggerEvent(self: *LazyLoader, event: Event) !void {
        const event_name = @tagName(event);

        const handlers = self.event_handlers.get(event_name) orelse return;

        for (handlers.items) |plugin_name| {
            if (self.loaded_plugins.contains(plugin_name)) continue;

            try self.loadPlugin(plugin_name);
        }
    }

    /// Load a single plugin
    pub fn loadPlugin(self: *LazyLoader, name: []const u8) !void {
        const spec = self.registry.plugins.get(name) orelse return error.PluginNotFound;

        if (self.loaded_plugins.contains(name)) return;

        zlog.info("Loading plugin: {s}", .{name});

        // Load dependencies first
        for (spec.dependencies) |dep| {
            if (!self.loaded_plugins.contains(dep)) {
                try self.loadPlugin(dep);
            }
        }

        // Execute plugin's init.gza
        const module_path = try std.fmt.allocPrint(
            self.allocator,
            "plugins.{s}",
            .{name},
        );
        defer self.allocator.free(module_path);

        const require_snippet = try std.fmt.allocPrint(
            self.allocator,
            "require(\"{s}\")",
            .{module_path},
        );
        defer self.allocator.free(require_snippet);

        _ = try self.runtime.executeCode(require_snippet);

        // Run config function if specified
        if (spec.config) |config_fn| {
            const config_snippet = try std.fmt.allocPrint(
                self.allocator,
                "{s}()",
                .{config_fn},
            );
            defer self.allocator.free(config_snippet);

            _ = try self.runtime.executeCode(config_snippet);
        }

        try self.loaded_plugins.put(name, true);

        zlog.info("Plugin loaded: {s}", .{name});
    }

    pub fn deinit(self: *LazyLoader) void {
        var it = self.event_handlers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.event_handlers.deinit();
        self.loaded_plugins.deinit();
    }
};
```

**Key Features:**
- Event-based plugin loading (VimEnter, BufRead, FileType, etc.)
- Command-based loading (load on first command invocation)
- Keymap-based loading (load on first key press)
- Dependency-aware loading order

---

## Grim Runtime Integration

### Required Grim Modules

Phantom.grim depends on these grim modules:

```zig
// In build.zig
const grim = b.dependency("grim", .{
    .target = target,
    .optimize = optimize,
    .@"export-test-harness" = true,  // Enable TestHarness export
    .ghostlang = true,                // Enable Ghostlang support
});

// Available modules from grim:
const test_harness_mod = grim.module("test_harness");  // Testing framework
const runtime_mod = grim.module("runtime");            // Plugin runtime
const core_mod = grim.module("core");                  // Editor core
const lsp_mod = grim.module("lsp");                    // LSP client
const syntax_mod = grim.module("syntax");              // Tree-sitter (grove)
const ui_tui_mod = grim.module("ui_tui");              // SimpleTUI
```

### Module Usage

**1. TestHarness** - For plugin testing:

```zig
// tests/plugin_test.zig
const TestHarness = @import("test_harness").TestHarness;

test "fuzzy finder plugin" {
    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    try harness.loadPlugin("plugins/core/fuzzy-finder.gza");
    try harness.executeCommand("fuzzy_find_files");
    try harness.assertOutput("init.gza");
}
```

**2. Runtime** - For plugin execution:

```zig
const Runtime = @import("runtime").Runtime;

var runtime = try Runtime.init(allocator);
defer runtime.deinit();

try runtime.loadPlugin("plugins/core/file-tree.gza");
```

**3. Core** - For editor operations:

```zig
const core = @import("core");

const editor = try core.Editor.init(allocator);
const buffer = try core.Buffer.init(allocator, "test.zig");
```

**4. LSP** - For language server integration:

```zig
const lsp = @import("lsp");

var client = try lsp.Client.init(allocator, "zls");
try client.start();
try client.sendInitialize();
```

**5. Syntax** - For tree-sitter parsing:

```zig
const syntax = @import("syntax");

var parser = try syntax.Parser.init(allocator, "zig");
const tree = try parser.parse(source_code);
```

---

## Plugin System

### Plugin Specification Format

**Ghostlang DSL (init.gza):**

```ghostlang
-- init.gza: User's entry point
local phantom = require("phantom")

phantom.setup({
  -- Core plugins (always loaded)
  { "file-tree",
    config = function()
      require("phantom.plugins.file-tree").setup({
        width = 30,
        icons = true,
        git_status = true,
      })
    end,
  },

  -- Lazy-loaded plugins
  { "fuzzy-finder",
    lazy = true,
    keys = {
      { "<leader>f", ":FuzzyFiles<CR>", desc = "Find files" },
      { "<leader>g", ":LiveGrep<CR>", desc = "Grep" },
    },
    config = function()
      require("phantom.plugins.fuzzy-finder").setup({
        max_results = 100,
      })
    end,
  },

  { "lsp-config",
    lazy = true,
    ft = { "zig", "rust", "ghostlang" },
    dependencies = { "cmp-lsp" },
    config = function()
      local lsp = require("phantom.lsp")
      lsp.setup({
        servers = { "zls", "rust_analyzer", "ghostls" },
      })
    end,
  },

  { "treesitter",
    lazy = true,
    event = "BufRead",
    build = ":TSUpdate",
    config = function()
      require("phantom.treesitter").setup({
        ensure_installed = { "zig", "rust", "ghostlang", "lua" },
        highlight = { enable = true },
        indent = { enable = true },
      })
    end,
  },

  { "comment",
    lazy = true,
    keys = { "gc", "gcc" },
    config = function()
      require("phantom.plugins.comment").setup()
    end,
  },
})

-- Set theme
phantom.theme = "tokyonight"

-- User keymaps
phantom.keymap("n", "<leader>e", ":FileTree<CR>", { desc = "Toggle file tree" })
phantom.keymap("n", "<leader>b", ":BufferPicker<CR>", { desc = "Buffer picker" })
```

---

## Dependency Resolution

### Dependency Graph Example

```
┌──────────────┐
│  lsp-config  │
└──────┬───────┘
       │ depends on
       ├─────────────┐
       ▼             ▼
┌──────────┐   ┌──────────┐
│ cmp-lsp  │   │ nvim-cmp │
└──────────┘   └─────┬────┘
                     │ depends on
                     ▼
                ┌──────────┐
                │  luasnip │
                └──────────┘
```

**Load Order (Topological Sort):**
1. luasnip
2. nvim-cmp
3. cmp-lsp
4. lsp-config

### Circular Dependency Detection

```zig
pub fn detectCycles(self: *PluginRegistry) !void {
    var stack = std.ArrayList([]const u8).init(self.allocator);
    defer stack.deinit();

    var visiting = std.StringHashMap(bool).init(self.allocator);
    defer visiting.deinit();

    var visited = std.StringHashMap(bool).init(self.allocator);
    defer visited.deinit();

    var it = self.plugins.iterator();
    while (it.next()) |entry| {
        if (!visited.contains(entry.key_ptr.*)) {
            try self.detectCyclesRecursive(
                entry.key_ptr.*,
                &visiting,
                &visited,
                &stack,
            );
        }
    }
}

fn detectCyclesRecursive(
    self: *PluginRegistry,
    name: []const u8,
    visiting: *std.StringHashMap(bool),
    visited: *std.StringHashMap(bool),
    stack: *std.ArrayList([]const u8),
) !void {
    try stack.append(name);
    try visiting.put(name, true);

    const spec = self.plugins.get(name) orelse return;

    for (spec.dependencies) |dep| {
        if (visiting.contains(dep)) {
            // Cycle detected!
            zlog.err("Circular dependency detected:", .{});
            for (stack.items) |item| {
                zlog.err("  {s}", .{item});
            }
            return error.CircularDependency;
        }

        if (!visited.contains(dep)) {
            try self.detectCyclesRecursive(dep, visiting, visited, stack);
        }
    }

    _ = visiting.remove(name);
    try visited.put(name, true);
    _ = stack.pop();
}
```

---

## Lazy Loading Strategy

### Trigger Types

**1. Event-based:**
```ghostlang
{ "git-signs",
  lazy = true,
  event = "BufRead",  -- Load on buffer read
}
```

**2. Filetype-based:**
```ghostlang
{ "lsp-zig",
  lazy = true,
  ft = { "zig" },  -- Load only for .zig files
}
```

**3. Command-based:**
```ghostlang
{ "telescope",
  lazy = true,
  cmd = { "Telescope" },  -- Load on :Telescope command
}
```

**4. Keymap-based:**
```ghostlang
{ "comment",
  lazy = true,
  keys = {
    { "gc", mode = "n" },
    { "gcc", mode = "n" },
  },
}
```

### Loading Timeline

```
Time: 0ms
├─ Load core plugins (file-tree, statusline)
├─ Register lazy triggers
└─ Render UI

Time: 100ms (User opens test.zig)
├─ Trigger: FileType:zig
├─ Load: lsp-config
├─ Load: treesitter
└─ Start zls

Time: 500ms (User presses <leader>f)
├─ Trigger: Keymap:<leader>f
├─ Load: fuzzy-finder
└─ Show fuzzy picker UI
```

---

## Configuration API

### Phantom.grim Global API

**Exposed to Ghostlang:**

```ghostlang
-- phantom.setup()
phantom.setup({
  plugins = { ... },
  options = { ... },
  theme = "tokyonight",
})

-- phantom.keymap()
phantom.keymap(mode, lhs, rhs, opts)

-- phantom.autocmd()
phantom.autocmd(event, callback)

-- phantom.command()
phantom.command(name, callback, opts)

-- phantom.theme
phantom.theme = "catppuccin"
phantom.theme.reload()
phantom.theme.browse()

-- phantom.plugin
phantom.plugin.install("file-tree")
phantom.plugin.update("fuzzy-finder")
phantom.plugin.clean()
phantom.plugin.list()
phantom.plugin.info("lsp-config")
```

---

## TestHarness Integration

### Plugin Testing Workflow

**1. Write plugin:**

```ghostlang
-- plugins/autopair/init.gza
local autopair = {}

function autopair.setup(opts)
  -- Plugin implementation
end

function autopair.on_insert(char)
  local pairs = {
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",
  }

  if pairs[char] then
    insert_text(pairs[char])
    move_cursor_left(1)
  end
end

return autopair
```

**2. Write test:**

```zig
// tests/autopair_test.zig
const TestHarness = @import("test_harness").TestHarness;

test "autopair: insert closing paren" {
    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    // Load plugin
    try harness.loadPlugin("plugins/autopair/init.gza");

    // Create buffer
    _ = try harness.createBuffer("test.zig");

    // Type opening paren
    try harness.sendKeys("i");
    try harness.sendKeys("(");

    // Verify closing paren inserted
    try harness.assertBufferContent("()");
    try harness.assertCursorPosition(0, 1);
}
```

**3. Run tests:**

```bash
zig build test
```

### TestHarness API

**Available from grim:**

```zig
pub const TestHarness = struct {
    pub fn init(allocator: std.mem.Allocator) !*TestHarness;
    pub fn deinit(self: *TestHarness) void;

    // Plugin operations
    pub fn loadPlugin(self: *TestHarness, path: []const u8) !void;
    pub fn unloadPlugin(self: *TestHarness) void;

    // Buffer operations
    pub fn createBuffer(self: *TestHarness, name: []const u8) !u32;
    pub fn getBufferContent(self: *TestHarness) ![]const u8;
    pub fn setBufferContent(self: *TestHarness, content: []const u8) !void;

    // Input simulation
    pub fn sendKeys(self: *TestHarness, keys: []const u8) !void;
    pub fn executeCommand(self: *TestHarness, cmd: []const u8) !void;

    // Assertions
    pub fn assertBufferContent(self: *TestHarness, expected: []const u8) !void;
    pub fn assertCursorPosition(self: *TestHarness, line: usize, col: usize) !void;
    pub fn assertOutput(self: *TestHarness, expected: []const u8) !void;
    pub fn assertError(self: *TestHarness, expected_error: anyerror) !void;
};
```

---

## Theme System

### Theme Architecture

**File:** `src/core/theme_manager.zig`

```zig
pub const ThemeManager = struct {
    allocator: std.mem.Allocator,
    themes: std.StringHashMap(Theme),
    active_theme: ?[]const u8,

    pub const Theme = struct {
        name: []const u8,
        colors: ColorPalette,
        highlights: std.StringHashMap(HighlightGroup),
    };

    pub const ColorPalette = struct {
        bg: []const u8,
        fg: []const u8,
        red: []const u8,
        green: []const u8,
        yellow: []const u8,
        blue: []const u8,
        magenta: []const u8,
        cyan: []const u8,
    };

    pub fn loadTheme(self: *ThemeManager, name: []const u8) !void {
        const theme_path = try std.fmt.allocPrint(
            self.allocator,
            "themes/{s}.toml",
            .{name},
        );
        defer self.allocator.free(theme_path);

        const theme = try self.parseThemeFile(theme_path);
        try self.themes.put(name, theme);
        self.active_theme = name;

        try self.applyTheme(theme);
    }

    pub fn applyTheme(self: *ThemeManager, theme: Theme) !void {
        // Apply colors to UI components
        // Trigger hot reload
    }
};
```

---

## Plugin Development Workflow

### 1. Create Plugin

```bash
mkdir -p plugins/my-plugin
cd plugins/my-plugin
touch init.gza
touch plugin.toml
```

### 2. Define Manifest

**plugin.toml:**

```toml
[plugin]
name = "my-plugin"
version = "0.1.0"
description = "My awesome plugin"
author = "ghostkellz"

[dependencies]
requires = ["cmp-lsp", "nvim-cmp"]

[config]
lazy = true
event = "BufRead"
```

### 3. Implement Plugin

**init.gza:**

```ghostlang
local plugin = {}

function plugin.setup(opts)
  opts = opts or {}

  -- Initialize plugin
  print("my-plugin loaded!")

  -- Register commands
  grim.command("MyCommand", function()
    print("My command executed!")
  end)

  -- Register keymaps
  grim.keymap("n", "<leader>m", ":MyCommand<CR>", { desc = "My command" })
end

return plugin
```

### 4. Write Tests

**tests/my_plugin_test.zig:**

```zig
const TestHarness = @import("test_harness").TestHarness;

test "my-plugin basic functionality" {
    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    try harness.loadPlugin("plugins/my-plugin/init.gza");
    try harness.executeCommand(":MyCommand");
    try harness.assertOutput("My command executed!");
}
```

### 5. Test Plugin

```bash
zig build test
```

### 6. Publish Plugin

```bash
# Tag release
git tag v0.1.0
git push origin v0.1.0

# Publish to phantom.grim registry
grim-pkg publish plugins/my-plugin
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

**Goals:**
- ✅ Set up grim dependency with GitHub fetch
- ✅ Import TestHarness, Runtime, Core modules
- ⬜ Create PluginRegistry with dependency resolution
- ⬜ Create LazyLoader with event system

**Deliverables:**
- `build.zig` updated to fetch grim from GitHub
- `src/core/plugin_registry.zig` complete
- `src/core/lazy_loader.zig` complete
- Basic tests passing

### Phase 2: Plugin System (Week 3-4)

**Goals:**
- ⬜ Implement plugin loading from .gza files
- ⬜ Create PluginLoader with lazy triggers
- ⬜ Implement dependency resolution
- ⬜ Create plugin manifest parser (TOML)

**Deliverables:**
- Plugins can be loaded on-demand
- Dependencies resolved automatically
- Circular dependency detection
- Lazy loading working for events, filetypes, commands, keys

### Phase 3: Configuration API (Week 5-6)

**Goals:**
- ⬜ Create Ghostlang API for phantom.setup()
- ⬜ Implement keymap, autocmd, command registration
- ⬜ Create plugin specification DSL
- ⬜ Write user-facing init.gza examples

**Deliverables:**
- `init.gza` entry point working
- Plugin specs declarative and user-friendly
- All lazy loading triggers functional
- Theme system integrated

### Phase 4: Core Plugins (Week 7-8)

**Goals:**
- ⬜ Port file-tree plugin
- ⬜ Port fuzzy-finder plugin
- ⬜ Port LSP config plugin
- ⬜ Port treesitter plugin
- ⬜ Port statusline plugin

**Deliverables:**
- 5 core plugins working
- All using lazy loading
- All tested with TestHarness
- Documentation complete

### Phase 5: Testing & Polish (Week 9-10)

**Goals:**
- ⬜ Write comprehensive tests for all components
- ⬜ Performance benchmarking
- ⬜ Plugin profiling UI
- ⬜ Health check system

**Deliverables:**
- 90%+ test coverage
- Performance baseline established
- `:PhantomHealth` command working
- `:PhantomPlugins` UI complete

### Phase 6: Documentation (Week 11-12)

**Goals:**
- ⬜ Complete user guide
- ⬜ Complete plugin development guide
- ⬜ API reference documentation
- ⬜ Migration guide from Neovim

**Deliverables:**
- `docs/USER_GUIDE.md`
- `docs/PLUGIN_DEV_GUIDE.md`
- `docs/API_REFERENCE.md`
- `docs/MIGRATION_FROM_NEOVIM.md`

---

## Success Criteria

### Functional Requirements

- ✅ Plugin management (install, update, remove)
- ⬜ Lazy loading (events, filetypes, commands, keys)
- ⬜ Dependency resolution (topological sort)
- ⬜ Lock file (reproducible builds)
- ⬜ Plugin profiling (startup time tracking)
- ⬜ Health checks (plugin status, LSP, diagnostics)
- ⬜ Hot reload (themes, configs, plugins)

### Performance Requirements

- Startup time < 50ms (with lazy loading)
- Plugin load time < 10ms per plugin
- Dependency resolution < 5ms
- Zero blocking on UI thread

### User Experience

- Zero-config defaults (works out of the box)
- Declarative plugin specs (lazy.nvim-style)
- Comprehensive error messages
- Plugin UI for management
- Fuzzy search for commands/plugins

---

## Comparison: Lazy.vim vs Phantom.grim

| Aspect | Lazy.nvim | Phantom.grim |
|--------|-----------|--------------|
| Language | Lua | Zig + Ghostlang |
| Performance | ~50ms startup | Target: <30ms |
| Plugin format | Git repos | Compiled .gza binaries |
| Dependency resolution | Graph | Topological sort |
| Lock file | ✅ | Planned |
| Hot reload | ✅ | ✅ |
| Profiling | ✅ | Planned |
| Health checks | ✅ | In progress |
| UI | TUI | Phantom TUI (GPU) |
| Testing | Manual | TestHarness (automated) |

---

## Resources

- **Grim Repository:** https://github.com/ghostkellz/grim
- **Lazy.nvim:** https://github.com/folke/lazy.nvim
- **TestHarness Usage:** `/data/projects/grim/docs/TEST_HARNESS_USAGE.md`
- **PhantomBuffer Guide:** `/data/projects/grim/PHANTOMBUFFER_CHANGELOG.md`
- **LSP Features:** `/data/projects/grim/NEW_LSP_FEATURES_v0.3.0.md`

---

## Appendix A: Plugin Ecosystem Vision

### Core Plugins (Bundled)

1. **file-tree** - File explorer with git status
2. **fuzzy-finder** - FZF-style file/buffer picker
3. **statusline** - Git-aware statusline
4. **treesitter** - Syntax highlighting via grove
5. **lsp-config** - Auto-configuration for LSP servers

### Editor Plugins (Optional)

6. **comment** - Toggle comments (gc, gcc)
7. **autopair** - Auto-close brackets/quotes
8. **surround** - Surround text objects
9. **indent-guides** - Visual indent markers
10. **colorizer** - Preview hex colors

### Language Support (Optional)

11. **zig** - Zig language support (zls)
12. **rust** - Rust language support (rust-analyzer)
13. **ghostlang** - Ghostlang support (ghostls)
14. **typescript** - TypeScript support
15. **python** - Python support

### Git Integration (Optional)

16. **git-signs** - Inline git diff markers
17. **git-blame** - Git blame annotations
18. **zap-ai** - AI-powered git commit messages

---

**Last Updated:** 2025-10-10
**Version:** 1.0
**Status:** Blueprint Complete - Ready for Implementation


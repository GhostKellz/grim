# Phantom.grim Lazy Guide

**A batteries-included configuration framework for Grim editor**
*Inspired by LazyVim • Built with Zig + Ghostlang*

---

## What is Phantom.grim?

Phantom.grim is a **kickstart/LazyVim-style configuration framework** for the Grim text editor. It provides:

- 🚀 **Zero-config setup** - Works out of the box
- ⚡ **Blazing performance** - Core written in Zig
- 🎨 **Declarative config** - Written in Ghostlang (.gza)
- 🔌 **Plugin ecosystem** - Modular, extensible architecture
- 🛠️ **IDE features** - LSP, Tree-sitter, Git, Fuzzy finding

---

## Architecture Overview

### Hybrid Language Approach

```
┌─────────────────────────────────────────────────┐
│                 Phantom.grim                    │
├─────────────────────────────────────────────────┤
│  Configuration Layer (Ghostlang .gza)           │
│  ├─ init.gza                                    │
│  ├─ plugins/*.gza                               │
│  └─ themes/*.gza                                │
├─────────────────────────────────────────────────┤
│  Runtime Layer (Zig + Ghostlang Bridge)         │
│  ├─ Plugin loader                               │
│  ├─ Component registry                          │
│  └─ LSP auto-config                             │
├─────────────────────────────────────────────────┤
│  Core Layer (Zig)                               │
│  ├─ Grim editor engine                          │
│  ├─ Grove (Tree-sitter wrapper)                 │
│  ├─ Phantom TUI framework                       │
│  └─ Native performance systems                  │
└─────────────────────────────────────────────────┘
```

### Why This Hybrid?

**Zig for Core:**
- Native performance
- Memory safety
- Direct system access
- Plugin loader with binary fetching
- Dependency resolution (graph solver)

**Ghostlang for Config:**
- Declarative syntax
- Easy to read/write
- Dynamic plugin loading
- User customization
- Compiled .gza binaries

---

## Directory Structure

```
phantom.grim/
├── init.gza                    # Main entry point
├── build.zig                   # Zig build system
├── build.zig.zon              # Dependencies
│
├── plugins/                    # Plugin ecosystem
│   ├── core/                   # Essential plugins
│   │   ├── file-tree.gza
│   │   ├── fuzzy-finder.gza
│   │   ├── statusline.gza
│   │   ├── treesitter.gza
│   │   └── zap-ai.gza
│   ├── editor/                 # Editor enhancements
│   ├── ui/                     # UI components
│   └── lang/                   # Language support
│
├── themes/                     # Color schemes
│   ├── tokyonight.gza
│   ├── catppuccin.gza
│   └── gruvbox.gza
│
├── runtime/                    # Runtime configs
│   ├── options.gza
│   ├── keymaps.gza
│   └── autocmds.gza
│
└── src/                        # Zig source code
    ├── plugin_loader.zig       # Plugin management
    ├── registry.zig            # Component registry
    ├── lsp_config.zig          # Auto LSP setup
    └── motions.zig             # Enhanced motions
```

---

## Core Components

### 1. File Tree (`plugins/core/file-tree.gza`)

**Current Status:** ⚠️ Placeholder implementation

```ghostlang
plugin = {
  name = "file-tree",
  state = {
    initialized = false,
    options = {}
  },

  setup = function(opts)
    if plugin.state.initialized then return end
    plugin.state.options = opts or {}
    plugin.state.initialized = true
    log("file-tree initialized")
  end,

  toggle = function()
    log("file-tree toggle (TODO: implement UI)")
  end,

  open = function(path)
    log("file-tree open: " .. path)
  end
}

return plugin
```

**TODO:**
- [ ] Implement TUI rendering
- [ ] Add keymaps (o/enter to open, a/c/d for add/copy/delete)
- [ ] Directory expansion/collapse
- [ ] Git status indicators
- [ ] Icon support

### 2. Fuzzy Finder (`plugins/core/fuzzy-finder.gza`)

**Current Status:** ⚠️ Needs implementation

**Design:**
```ghostlang
plugin = {
  name = "fuzzy-finder",

  setup = function(opts)
    -- Integrate with core/fuzzy.zig
    -- FZF-style algorithm
    -- Scoring: consecutive, word boundary, camelCase
  end,

  find_files = function()
    -- Telescope-style file picker
    -- <leader>f keybinding
  end,

  live_grep = function()
    -- Ripgrep integration
    -- <leader>g keybinding
  end,

  buffers = function()
    -- Open buffer list
    -- <leader>b keybinding
  end
}
```

**Integration Point:**
- Leverage `/data/projects/grim/core/fuzzy.zig`
- Bridge Zig FuzzyFinder to Ghostlang API

### 3. Statusline (`plugins/core/statusline.gza`)

**Current Status:** ⚠️ Needs implementation

**Design:**
```ghostlang
plugin = {
  name = "statusline",

  components = {
    mode = function() return mode() end,
    git_branch = function() return git.branch() end,
    git_status = function() return git.status() end,
    filename = function() return buffer.name() end,
    position = function() return cursor.position() end,
    filetype = function() return buffer.filetype() end,
    encoding = function() return buffer.encoding() end,
  },

  render = function()
    -- Format: " MODE | branch● | file.zig | 10,5 | utf-8 | zig"
  end
}
```

**Integration Point:**
- Use `/data/projects/grim/core/git.zig`
- Display git branch, file status (●/+/-/?)

### 4. Tree-sitter (`plugins/core/treesitter.gza`)

**Current Status:** ⚠️ Needs implementation

**Design:**
```ghostlang
plugin = {
  name = "treesitter",

  languages = {
    "ghostlang", "zig", "rust", "typescript",
    "python", "go", "c", "cpp", "lua"
  },

  features = {
    highlight = true,
    indent = true,
    fold = true,
    incremental_selection = true
  },

  setup = function(opts)
    -- Integrate with syntax/grove.zig
    -- Auto-install grammars
  end
}
```

**Integration Point:**
- Use `/data/projects/grim/syntax/grove.zig`
- Grove v0.1.0 integration
- 14 grammars available

---

## Component Management (New Approach)

### Current Grim Components (In This Repo)

The main `grim` repository has these **Zig-native** components:

```
/data/projects/grim/
├── core/
│   ├── editor.zig          # Rope-based editor
│   ├── buffer.zig          # Text buffers
│   ├── git.zig            # Git integration ✅
│   ├── fuzzy.zig          # Fuzzy finder ✅
│   ├── harpoon.zig        # File pinning ✅
│   └── lsp.zig            # LSP client ✅
├── syntax/
│   ├── grove.zig          # Tree-sitter wrapper ✅
│   ├── highlighter.zig    # Syntax highlighting ✅
│   └── features.zig       # Folding/selection ✅
└── ui-tui/
    └── simple_tui.zig     # TUI renderer ✅
```

### Phantom.grim Component Strategy

**Option 1: Direct Zig Binding (Recommended)**

Instead of reimplementing in Ghostlang, **expose Zig APIs**:

```zig
// src/ghostlang_bridge.zig
pub const GhostlangAPI = struct {
    pub fn fuzzy_find_files(path: []const u8) ![]const u8 {
        var finder = core.FuzzyFinder.init(allocator);
        defer finder.deinit();
        try finder.findFiles(path, 10);
        // Return results to Ghostlang
    }

    pub fn git_get_branch() ![]const u8 {
        var git = core.Git.init(allocator);
        defer git.deinit();
        return try git.getCurrentBranch();
    }

    pub fn lsp_goto_definition(file: []const u8, line: usize, col: usize) !void {
        // Call Ghostls LSP
    }
};
```

Then in Ghostlang:

```ghostlang
-- plugins/core/fuzzy-finder.gza
plugin = {
  find_files = function()
    local results = grim.fuzzy_find_files(".")
    -- Display in TUI
  end
}
```

**Option 2: Ghostlang Wrappers (Current Approach)**

Ghostlang plugins call Zig components via FFI:

```ghostlang
-- Direct Zig function calls
local git_branch = grim.core.git.get_branch()
local fuzzy_results = grim.core.fuzzy.filter("init")
```

**Recommendation:** Go with **Option 1** - expose a clean API boundary. Keeps Ghostlang configs simple and leverages existing Zig performance.

---

## Plugin System Design

### Registry-Based Loading

```zig
// src/registry.zig
pub const PluginRegistry = struct {
    plugins: std.StringHashMap(*Plugin),

    pub const Plugin = struct {
        name: []const u8,
        version: []const u8,
        path: []const u8,
        enabled: bool,
        dependencies: [][]const u8,
    };

    pub fn register(self: *PluginRegistry, name: []const u8) !void {
        // Fetch compiled .gza binary
        // Resolve dependencies
        // Load into runtime
    }

    pub fn load(self: *PluginRegistry, name: []const u8) !void {
        // Execute plugin's setup() function
    }
};
```

### Plugin Lifecycle

1. **Discovery** - Scan `plugins/` directories
2. **Resolution** - Resolve dependencies (graph solver in Zig)
3. **Fetching** - Download compiled .gza binaries (not git clone!)
4. **Loading** - Execute in Ghostlang runtime
5. **Setup** - Call `plugin.setup(opts)`

### Lazy Loading

```ghostlang
-- init.gza
phantom.lazy = {
  -- Load on event
  { "file-tree", event = "VimEnter" },
  { "lsp", ft = {"zig", "ghostlang", "rust"} },
  { "git-signs", event = "BufRead" },

  -- Load on command
  { "telescope", cmd = "Telescope" },

  -- Load on keymap
  { "comment", keys = {"gc", "gcc"} }
}
```

---

## Configuration Examples

### Basic `init.gza`

```ghostlang
-- Load core modules
require("phantom.core")

-- Set options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

-- Setup plugins
require("phantom.plugins").setup({
  -- Core plugins (always loaded)
  core = {
    "file-tree",
    "fuzzy-finder",
    "statusline",
    "treesitter"
  },

  -- Optional plugins (lazy loaded)
  editor = {
    "comment",
    "autopairs",
    "surround"
  },

  ui = {
    "indent-guides",
    "colorizer"
  },

  lang = {
    lsp = {
      servers = {"ghostls", "zls", "rust-analyzer"}
    },
    dap = {
      adapters = {"lldb", "codelldb"}
    }
  }
})

-- Set theme
phantom.theme = "tokyonight"

-- Custom keymaps
map("n", "<leader>f", ":FuzzyFiles<CR>", { desc = "Find files" })
map("n", "<leader>g", ":LiveGrep<CR>", { desc = "Grep" })
map("n", "<leader>e", ":FileTree<CR>", { desc = "File explorer" })
```

### Advanced Plugin Config

```ghostlang
-- plugins/editor/comment.gza
plugin = {
  name = "comment",

  setup = function(opts)
    opts = opts or {}

    -- Line comment
    map("n", "gcc", function()
      toggle_line_comment()
    end)

    -- Block comment
    map("v", "gc", function()
      toggle_block_comment()
    end)

    -- Configure comment strings per filetype
    comment_strings = {
      zig = "//",
      ghostlang = "//",
      lua = "--",
      python = "#"
    }
  end
}

return plugin
```

### Theme System

```ghostlang
-- themes/tokyonight.gza
theme = {
  name = "tokyonight",
  variant = "night",

  colors = {
    bg = "#1a1b26",
    fg = "#c0caf5",
    blue = "#7aa2f7",
    cyan = "#7dcfff",
    green = "#9ece6a",
    red = "#f7768e",
    yellow = "#e0af68"
  },

  highlights = {
    Normal = { fg = "fg", bg = "bg" },
    Comment = { fg = "#565f89", italic = true },
    Keyword = { fg = "blue", bold = true },
    String = { fg = "green" },
    Function = { fg = "cyan" }
  }
}

return theme
```

---

## Implementation Roadmap

### Phase 1: Foundation (Current)
- [x] Grim core engine (Zig)
- [x] Grove Tree-sitter integration
- [x] LSP client (Ghostls v0.1.0)
- [x] Git integration
- [x] Fuzzy finder
- [x] Harpoon-style navigation

### Phase 2: Phantom.grim Bootstrap
- [x] Ghostlang runtime loader
- [x] Plugin registry system
- [x] Component bridge (Zig ↔ Ghostlang)
- [x] `init.gza` entry point
- [x] Basic plugin lifecycle

### Phase 3: Core Plugins
- [ ] `file-tree.gza` - Full implementation
- [ ] `fuzzy-finder.gza` - Bridge to fuzzy.zig
- [ ] `statusline.gza` - Integrate git.zig
- [ ] `treesitter.gza` - Bridge to grove.zig

### Phase 4: Plugin Ecosystem
- [ ] LSP auto-config
- [ ] DAP debugging support
- [ ] Git signs (inline diff markers)
- [ ] Comment.nvim port
- [ ] Surround.nvim port
- [ ] Autopairs

### Phase 5: Advanced Features
- [ ] Multi-cursor editing
- [ ] Macro recording
- [ ] Session management
- [ ] Project management
- [ ] Terminal integration

### Phase 6: AI Integration
- [ ] Zap integration (github.com/ghostkellz/zap)
- [ ] AI-powered git commits
- [ ] Code generation
- [ ] Inline suggestions

---

## Key Design Decisions

### 1. Why .gza Binary Format?

**Problem:** Traditional plugin managers clone entire git repos (slow, bloated)

**Solution:** Compile Ghostlang to .gza binaries
- Faster downloads (single binary vs git clone)
- Versioned releases (semantic versioning)
- Dependency resolution at binary level
- Smaller disk footprint

### 2. Why Zig for Core?

**Advantages:**
- Native performance (no runtime overhead)
- Memory safety (no GC pauses)
- Cross-compilation (single binary for all platforms)
- Explicit control (perfect for editor core)

**Ghostlang for Config:**
- Dynamic loading
- User-friendly syntax
- Hot reloading
- Easy customization

### 3. Component Bridge Architecture

**Strategy:** Expose minimal, clean API surface

```zig
// Zig side (src/api.zig)
pub export fn grim_fuzzy_find(path: [*:0]const u8) [*:0]const u8 {
    // Call core/fuzzy.zig
    // Return JSON string
}

// Ghostlang side (auto-generated bindings)
function grim.fuzzy_find(path)
  return json.decode(ffi.grim_fuzzy_find(path))
end
```

**Benefits:**
- Type safety at boundary
- Performance (no marshaling overhead for common ops)
- Flexibility (Ghostlang can abstract)

---

## Next Steps

### For Phantom.grim Project

1. **Implement Ghostlang Runtime**
   - `.gza` file loader
   - Sandboxed execution
   - API bindings generator

2. **Create Plugin Registry**
   - Centralized package index
   - Dependency graph solver
   - Binary distribution

3. **Build Core Plugins**
   - Port file-tree to use grim TUI
   - Bridge fuzzy-finder to fuzzy.zig
   - Implement statusline with git.zig

4. **Document Everything**
   - Plugin API reference
   - Migration guide (from Neovim)
   - Contribution guidelines

### For Main Grim Project

1. **Expose C API** (for FFI)
   ```zig
   // grim/src/c_api.zig
   pub export fn grim_init() *Editor { ... }
   pub export fn grim_fuzzy_find(...) { ... }
   pub export fn grim_git_blame(...) { ... }
   ```

2. **Modularize Components**
   - Each core/* module as standalone lib
   - Clean public API
   - Documentation comments

3. **Testing Infrastructure**
   - Unit tests for each module
   - Integration tests
   - Performance benchmarks

---

## Resources

- **Grim Repo:** github.com/ghostkellz/grim
- **Phantom.grim Repo:** github.com/ghostkellz/phantom.grim
- **Ghostlang:** [Language specification]
- **Grove:** Tree-sitter wrapper for Zig
- **Zap:** AI git integration (github.com/ghostkellz/zap)

---

## FAQ

**Q: Why not just use Neovim/LazyVim?**
A: Performance. Native Zig core is significantly faster than Lua/VimScript. Plus, Ghostlang is designed specifically for this use case.

**Q: Can I use Neovim plugins?**
A: Not directly, but many can be ported. We're building compatible APIs where possible.

**Q: How do I contribute?**
A: See CONTRIBUTING.md. Core (Zig) and plugins (Ghostlang) have different workflows.

**Q: When will this be production-ready?**
A: Targeting v1.0 in Q2 2025. Alpha releases coming soon.

**Q: What about Vim keybindings?**
A: Full Vim modal editing is core. Grim motions extend Vim with modern features.

---

**Built with Zig**

# Phantom.grim Architecture Guide

**Building the Next-Generation LazyVim Alternative in Zig + Ghostlang**

---

## 🎯 Vision

**Phantom.grim** is to **Grim** what **LazyVim** is to **Neovim** — but faster, simpler, and more intuitive. Built from the ground up in **Zig** (core) and **Ghostlang** (configuration), Phantom eliminates the complexity of traditional plugin managers while providing a batteries-included IDE experience.

### Core Philosophy

```
┌─────────────────────────────────────────────────────────────┐
│  "Reap your codebase with Grim motions"                    │
│  - Modern Vim motions with Zig performance                  │
│  - Zero-friction plugin management                          │
│  - Auto-updates without git cloning                         │
│  - Educational by design (grim-tutor)                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 📂 Directory Structure

```
phantom.grim/
├── init.gza                      # Entry point (bootstraps everything)
├── cktech/                       # Reference: GhostKellz's workflow
│   └── nvim/                     # Learn from this structure
├── core/                         # Zig-powered core (native speed)
│   ├── plugin_loader.zig         # No git clone - direct fetch
│   ├── auto_update.zig           # Background plugin updates
│   ├── package_registry.zig      # Central plugin registry
│   └── motion_engine.zig         # Grim motions (enhanced Vim)
├── runtime/                      # Ghostlang runtime
│   ├── defaults/
│   │   ├── options.gza           # Sensible defaults
│   │   ├── keymaps.gza           # GhostKellz-inspired bindings
│   │   ├── autocmds.gza          # Auto-commands
│   │   └── grim-tutor/           # Interactive tutorial
│   │       ├── basics.gza        # Lesson 1: Grim motions
│   │       ├── editing.gza       # Lesson 2: Text manipulation
│   │       ├── navigation.gza    # Lesson 3: Advanced navigation
│   │       └── plugins.gza       # Lesson 4: Using plugins
│   └── lib/
│       ├── utils.gza             # Helper functions
│       ├── ui.gza                # UI components
│       └── lsp.gza               # LSP utilities
├── plugins/
│   ├── core/                     # Essential (always loaded)
│   │   ├── file-tree.gza
│   │   ├── fuzzy-finder.gza
│   │   ├── statusline.gza
│   │   └── treesitter.gza
│   ├── editor/                   # Editor enhancements
│   │   ├── autopairs.gza
│   │   ├── comment.gza
│   │   ├── surround.gza
│   │   └── which-key.gza
│   ├── lsp/                      # LSP support
│   │   ├── config.gza            # Auto-setup (ghostls, zls, rust-analyzer)
│   │   ├── completion.gza
│   │   └── diagnostics.gza
│   ├── git/                      # Git integration
│   │   ├── signs.gza
│   │   ├── blame.gza
│   │   └── lazygit.gza
│   ├── ai/                       # AI tools
│   │   └── zeke.gza              # Zeke AI assistant
│   └── extras/                   # Optional plugins
│       ├── dashboard.gza
│       ├── dap.gza               # Debugging
│       └── multicursor.gza
├── themes/
│   ├── gruvbox.gza
│   ├── tokyonight.gza            # Default (GhostKellz style)
│   └── catppuccin.gza
├── lua/                          # User customizations
│   └── user/
│       ├── config.gza            # Override defaults
│       └── plugins.gza           # Add custom plugins
└── docs/
    ├── grim-tutor-guide.md       # Tutorial documentation
    ├── plugin-dev.md             # Create plugins in .gza
    └── migration.md              # From Neovim/LazyVim
```

---

## 🚀 Innovation: Phantom Package Manager

### The Problem with Lazy.nvim

```lua
-- LazyVim approach (requires git cloning)
{
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function() require("telescope").setup() end
}
```

**Issues:**
- ❌ Git clones entire repos (~50MB per plugin)
- ❌ Manual `:Lazy sync` required
- ❌ Dependency hell (version conflicts)
- ❌ Slow startup (lazy-loading hacks needed)

### Phantom's Solution: **Registry-Based + Zig Native**

```ghostlang
-- Phantom.grim approach (no git cloning!)
plugin.install("telescope", {
    auto_update = true,           -- Background updates
    version = "latest",            -- Or pin: "1.2.3"
    lazy_load = { events = "BufEnter" }  -- Native lazy loading
})
```

**How It Works:**

1. **Central Registry** (`registry.phantom.grim`)
   - JSON manifest of all plugins
   - Pre-compiled `.gza` binaries
   - Checksums for verification
   - Dependency resolution

2. **Zig-Powered Fetcher**
   ```zig
   // core/plugin_loader.zig
   pub fn fetchPlugin(name: []const u8, version: []const u8) !void {
       const url = try std.fmt.allocPrint(
           allocator,
           "https://registry.phantom.grim/{s}/{s}.tar.gz",
           .{name, version}
       );

       // Direct download (no git)
       const response = try http.fetch(url);

       // Extract to ~/.config/grim/plugins/{name}/
       try extractPlugin(response.body, name);

       // Compile .gza to bytecode
       try compilePlugin(name);
   }
   ```

3. **Auto-Update Daemon**
   ```zig
   // core/auto_update.zig
   pub fn startUpdateDaemon() !void {
       while (true) {
           std.time.sleep(6 * std.time.ns_per_hour);  // Every 6 hours

           for (installed_plugins) |plugin| {
               if (plugin.auto_update and hasNewVersion(plugin)) {
                   try updatePlugin(plugin.name);
                   notifyUser("Updated: {s}", .{plugin.name});
               }
           }
       }
   }
   ```

4. **Dependency Resolution** (Zig graph solver)
   ```zig
   pub fn resolveConflicts(plugins: []Plugin) ![]Plugin {
       // Use topological sort for dependencies
       // Detect circular deps
       // Auto-downgrade/upgrade to compatible versions
       return sorted_plugins;
   }
   ```

---

## 🎓 Grim-Tutor: Learn by Doing

### Interactive Tutorial System

```ghostlang
-- runtime/defaults/grim-tutor/basics.gza

tutor.lesson("Grim Motions: The Reaper's Way", {
    steps = {
        {
            title = "Navigation with hjkl",
            instructions = [[
                Use h, j, k, l to move around.

                     k (up)
                h (left)  l (right)
                   j (down)

                Navigate to the X below:
            ]],
            content = [[
                Start here



                        X  <- Move here!
            ]],
            validate = function(cursor)
                return cursor.line == 5 and cursor.col == 8
            end,
            hint = "Remember: h=left, j=down, k=up, l=right"
        },

        {
            title = "Word Motions (Reaping Words)",
            instructions = [[
                w - next word start
                e - next word end
                b - previous word

                Move to each word marked with X:
            ]],
            content = [[
                The X quick X brown X fox X
            ]],
            validate = function(visited)
                return #visited == 4
            end
        },

        {
            title = "Grim Motion: Harvest Lines",
            instructions = [[
                NEW in Grim: 'H' (Harvest)

                H - Select entire function/block
                HH - Select paragraph
                3H - Select 3 lines

                Try: HH to select this paragraph
            ]],
            -- ... progressive lessons
        }
    }
})
```

### Launch Tutor

```bash
# From command line
grim --tutor

# Or within Grim
:GrimTutor
```

**Features:**
- ✅ Progress tracking (resume where you left off)
- ✅ Achievements/badges
- ✅ Practice mode (timed challenges)
- ✅ Custom lessons (create .gza tutorials)

---

## ⚡ Grim Motions: Enhanced Vim

### Core Vim Motions (Preserved)

All standard Vim motions work identically:
- `h/j/k/l` - Navigation
- `w/b/e` - Word motions
- `gg/G` - Top/bottom
- `f/t/F/T` - Find character
- `%` - Match brackets
- `*/#` - Search word under cursor

### Grim Extensions (New!)

| Motion | Mnemonic | Description |
|--------|----------|-------------|
| `H` | **Harvest** | Select logical block (function, class, etc.) |
| `HH` | **Harvest Line** | Select entire paragraph |
| `<n>H` | **Harvest N** | Select N logical units |
| `<leader>rp` | **Reap** | Cut and store in special register |
| `<leader>rw` | **Reap Word** | Smart word selection (camelCase aware) |
| `<leader>rf` | **Reap Function** | Extract entire function |
| `gs` | **Ghost Select** | Multi-cursor selection |
| `gS` | **Ghost Spawn** | Add cursor at each match |

### Implementation

```zig
// core/motion_engine.zig

pub const GrimMotion = struct {
    pub fn harvest(context: *EditorContext) !void {
        // Use Grove tree-sitter to find logical block
        const node = try context.syntax.nodeAt(context.cursor);
        const block = try findParentBlock(node);

        // Select entire block
        try context.selection.set(block.start, block.end);
    }

    pub fn reapWord(context: *EditorContext) !void {
        // Smart word boundaries (camelCase, snake_case aware)
        const word = try identifySmartWord(context.cursor);

        // Cut and store
        try context.registers.store("reap", word.text);
        try context.buffer.delete(word.range);
    }
};
```

---

## 🔌 Plugin Development in .gza

### Example: Custom File Tree

```ghostlang
-- lua/user/plugins/my-tree.gza

local Plugin = require("phantom.plugin")

return Plugin.define({
    name = "my-file-tree",
    version = "1.0.0",

    -- Dependencies (auto-resolved)
    dependencies = {
        "phantom/ui",
        "phantom/fs"
    },

    -- Lazy load
    events = { "BufEnter" },

    -- Configuration
    config = function()
        local tree = {
            width = 30,
            position = "left",
            icons = true,
            git_status = true
        }

        -- Register commands
        command("MyTree", function()
            tree.toggle()
        end)

        -- Keybindings
        keymap("n", "<leader>e", ":MyTree<CR>", { desc = "Toggle tree" })

        -- Event handlers
        on("file_opened", function(file)
            tree.reveal(file)
        end)
    end,

    -- Plugin code
    init = function()
        local fs = require("phantom.fs")
        local ui = require("phantom.ui")

        function tree.toggle()
            if tree.visible then
                ui.close_sidebar()
            else
                local files = fs.readdir(fs.cwd())
                ui.show_sidebar(tree.render(files))
            end
            tree.visible = not tree.visible
        end

        function tree.render(files)
            local lines = {}
            for _, file in ipairs(files) do
                local icon = file.is_dir and "📁" or "📄"
                table.insert(lines, icon .. " " .. file.name)
            end
            return lines
        end
    end
})
```

### Publish to Registry

```bash
# Build plugin
grim-pkg build my-tree.gza

# Publish (creates tarball + manifest)
grim-pkg publish --name my-file-tree --version 1.0.0

# Users install with:
# plugin.install("my-file-tree")
```

---

## 🎨 Default Configuration (GhostKellz Style)

### Keybindings (Based on cktech/)

```ghostlang
-- runtime/defaults/keymaps.gza

local map = keymap

-- Leader
vim.g.leader = " "

-- === File Operations ===
map("n", "<leader>w", ":write<CR>", { desc = "Save file" })
map("n", "<leader>q", ":quit<CR>", { desc = "Quit" })
map("n", "<leader>e", ":TreeToggle<CR>", { desc = "File tree" })

-- === Fuzzy Finding (Telescope-inspired) ===
map("n", "<leader>ff", ":FindFiles<CR>", { desc = "Find files" })
map("n", "<leader>fg", ":FindGrep<CR>", { desc = "Live grep" })
map("n", "<leader>fb", ":FindBuffers<CR>", { desc = "Buffers" })
map("n", "<leader>fr", ":FindRecent<CR>", { desc = "Recent files" })

-- === LSP (GhostKellz bindings) ===
map("n", "K", ":LspHover<CR>", { desc = "Hover docs" })
map("n", "gd", ":LspDefinition<CR>", { desc = "Go to definition" })
map("n", "gr", ":LspReferences<CR>", { desc = "Find references" })
map("n", "<leader>rn", ":LspRename<CR>", { desc = "Rename symbol" })
map("n", "<leader>ca", ":LspCodeAction<CR>", { desc = "Code actions" })
map("n", "<leader>cf", ":LspFormat<CR>", { desc = "Format" })

-- === Git (Lazygit style) ===
map("n", "<leader>gg", ":LazyGit<CR>", { desc = "Lazygit" })
map("n", "<leader>gb", ":GitBlame<CR>", { desc = "Git blame" })
map("n", "<leader>gd", ":GitDiff<CR>", { desc = "Git diff" })

-- === AI Assistant (Zeke) ===
map("n", "<leader>aa", ":ZekeToggle<CR>", { desc = "Toggle Zeke" })
map("n", "<leader>ac", ":ZekeChat<CR>", { desc = "Zeke chat" })
map({ "n", "v" }, "<leader>ax", ":ZekeExplain<CR>", { desc = "Explain code" })

-- === Window Navigation (tmux-like) ===
map("n", "<C-h>", ":WinLeft<CR>", { desc = "Window left" })
map("n", "<C-j>", ":WinDown<CR>", { desc = "Window down" })
map("n", "<C-k>", ":WinUp<CR>", { desc = "Window up" })
map("n", "<C-l>", ":WinRight<CR>", { desc = "Window right" })

-- === Grim Motions ===
map("n", "H", "<cmd>lua require('grim.motions').harvest()<CR>", { desc = "Harvest block" })
map("n", "<leader>rp", "<cmd>lua require('grim.motions').reap()<CR>", { desc = "Reap" })
map("n", "gs", "<cmd>lua require('grim.multicursor').spawn()<CR>", { desc = "Ghost select" })

-- === Arrow Keys Fallback (GhostKellz style - beginner friendly) ===
map("n", "<Up>", "k", { desc = "Up (use k)" })
map("n", "<Down>", "j", { desc = "Down (use j)" })
map("n", "<Left>", "h", { desc = "Left (use h)" })
map("n", "<Right>", "l", { desc = "Right (use l)" })

-- Show hint on arrow usage (educate users)
on_key("<Up>", function()
    notify("💀 Use 'k' instead of arrow keys! (Grim Tutor: :GrimTutor)", "info")
end)
```

### Visual Theme (TokyoNight + Minty Accent)

```ghostlang
-- themes/tokyonight.gza

theme.setup({
    name = "tokyonight-phantom",
    base = "tokyonight-night",

    -- GhostKellz minty statusline
    highlights = {
        StatusLine = { fg = "#1a1b26", bg = "#88aff0", bold = true },
        StatusLineNC = { fg = "#1a1b26", bg = "#7aa2f7" },

        -- Phantom accents
        Function = { fg = "#88aff0", bold = true },  -- Mint functions
        Keyword = { fg = "#9a0ade", bold = true },   -- Purple keywords
        String = { fg = "#66d9ef" },                 -- Teal strings
        Comment = { fg = "#7aa2f7", italic = true }, -- Blue comments

        -- Grim-specific
        GrimMotion = { fg = "#7fffd4", bold = true }, -- Aqua for Grim motions
        GrimHarvest = { bg = "#003344", fg = "#7fffd4" },
    }
})
```

---

## 🔄 Auto-Update System

### Background Updates (Non-Blocking)

```zig
// core/auto_update.zig

pub const UpdateManager = struct {
    pub fn init() !UpdateManager {
        return .{
            .check_interval = 6 * std.time.ns_per_hour,
            .last_check = std.time.timestamp(),
        };
    }

    pub fn startDaemon(self: *UpdateManager) !void {
        const thread = try std.Thread.spawn(.{}, updateLoop, .{self});
        thread.detach();
    }

    fn updateLoop(self: *UpdateManager) !void {
        while (true) {
            defer std.time.sleep(self.check_interval);

            // Check registry for updates
            const updates = try fetchAvailableUpdates();

            if (updates.len > 0) {
                // Notify user (non-intrusive)
                try notifyUpdates(updates);

                // Auto-update if configured
                for (updates) |update| {
                    if (update.plugin.auto_update) {
                        try installUpdate(update);
                    }
                }
            }
        }
    }
};
```

### User Control

```ghostlang
-- User can configure update behavior

phantom.updates = {
    auto = true,                    -- Auto-update plugins
    check_interval = "daily",       -- Or "hourly", "weekly"
    notify = "all",                 -- Or "security-only", "none"

    -- Exclude plugins from auto-update
    exclude = { "my-custom-plugin" },

    -- Update commands
    commands = {
        ":PhantomUpdate",           -- Update all
        ":PhantomUpdate zeke",      -- Update specific plugin
        ":PhantomUpdateCheck",      -- Check without installing
    }
}
```

---

## 🎯 LSP Auto-Configuration

### Zero-Config LSP (Inspired by cktech/)

```ghostlang
-- plugins/lsp/config.gza

local lsp = require("phantom.lsp")

-- Auto-detect and configure LSP servers
lsp.auto_setup({
    -- Ghostlang (always enabled)
    ghostls = {
        cmd = { "ghostls", "--stdio" },
        filetypes = { "ghostlang", "gza", "ghost" },
        root_patterns = { ".git", "grim.toml" },
    },

    -- Zig (auto-enabled if zls found)
    zls = {
        cmd = { "zls" },
        filetypes = { "zig" },
        settings = {
            enable_build_on_save = true,
            enable_autofix = true,
        }
    },

    -- Rust (auto-enabled if rust-analyzer found)
    rust_analyzer = {
        cmd = { "rust-analyzer" },
        filetypes = { "rust" },
        settings = {
            ["rust-analyzer"] = {
                cargo = { allFeatures = true },
                checkOnSave = { command = "clippy" },
            }
        }
    },

    -- More servers (auto-detected)
    ts_ls = "auto",       -- TypeScript
    pyright = "auto",     -- Python
    gopls = "auto",       -- Go
    clangd = "auto",      -- C/C++
})

-- Auto-format on save (GhostKellz style)
on("buffer_save", function(bufnr)
    if lsp.has_formatter(bufnr) then
        lsp.format(bufnr)
    end
end)
```

---

## 📊 Comparison: LazyVim vs Phantom.grim

| Feature | LazyVim | Phantom.grim |
|---------|---------|--------------|
| **Plugin Manager** | lazy.nvim (Lua) | Native Zig |
| **Installation** | Git clone each plugin | Registry fetch (no git) |
| **Updates** | Manual `:Lazy sync` | Auto-update daemon |
| **Startup Time** | ~50-100ms | **~10-20ms** (Zig) |
| **Config Language** | Lua | **Ghostlang** (.gza) |
| **LSP Setup** | nvim-lspconfig | **Auto-detect** |
| **Tutorial** | :Tutor (Vim) | **:GrimTutor** (interactive) |
| **Dependency Resolution** | Manual | **Automatic** (Zig solver) |
| **Plugin Format** | Git repos | **Compiled .gza** binaries |
| **Maintenance** | User manages | **Auto-managed** |
| **Learning Curve** | Steep | **Gradual** (grim-tutor) |

---

## 🚢 Migration from LazyVim/Neovim

### Automatic Converter

```bash
# Convert LazyVim config to Phantom.grim
grim-convert ~/.config/nvim/

# Output: ~/.config/grim/
```

**Converter handles:**
- ✅ Translates Lua → Ghostlang
- ✅ Maps lazy.nvim plugins → Phantom registry
- ✅ Preserves keybindings
- ✅ Adapts LSP configs

### Manual Migration

```ghostlang
-- Before (LazyVim):
-- ~/.config/nvim/lua/plugins/telescope.lua
return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("telescope").setup({})
  end
}

-- After (Phantom.grim):
-- ~/.config/grim/lua/user/plugins.gza
plugin.install("telescope", {
    auto_update = true,
    config = function()
        local telescope = require("phantom.telescope")
        telescope.setup({})
    end
})
```

---

## 🛠️ Development Workflow

### Creating Phantom.grim from Scratch

1. **Bootstrap Core** (Zig)
   ```bash
   cd grim/
   zig build phantom-init
   ```

2. **Implement Plugin Loader**
   - Registry client
   - Download + extract
   - Dependency resolver
   - Auto-updater

3. **Port Essential Plugins** (.gza)
   - File tree (neo-tree → phantom-tree.gza)
   - Fuzzy finder (telescope → phantom-finder.gza)
   - LSP config
   - Git integration

4. **Create Grim-Tutor**
   - Interactive lessons
   - Progress tracking
   - Achievements

5. **Setup Registry**
   - Host at `registry.phantom.grim`
   - Plugin manifests (JSON)
   - CI/CD for plugin builds

---

## 📖 Documentation Structure

```
docs/
├── phantom-architecture.md       # This file
├── grim-tutor-guide.md           # Tutorial system
├── plugin-development.md         # Create .gza plugins
├── registry-protocol.md          # How registry works
├── migration-guide.md            # From Neovim/LazyVim
└── api/
    ├── motion-api.md             # Grim motion API
    ├── lsp-api.md                # LSP utilities
    └── ui-api.md                 # UI framework
```

---

## 🎉 Conclusion

**Phantom.grim** represents the evolution of editor configuration:

1. **Faster** - Zig-native plugin system (10x faster than Lua)
2. **Simpler** - No git cloning, auto-updates, zero config LSP
3. **Smarter** - Registry-based packages, dependency resolution
4. **Educational** - grim-tutor teaches Grim motions interactively
5. **Modern** - Ghostlang (.gza) brings type safety + performance

**Next Steps:**
1. Implement core plugin loader (Zig)
2. Build registry infrastructure
3. Port top 20 LazyVim plugins to .gza
4. Create grim-tutor lessons
5. Beta test with community

---

**Built with 👻 by the Ghost Ecosystem**

*"Reap your codebase, one motion at a time"*

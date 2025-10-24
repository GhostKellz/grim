# UI Plugins

Visual interface enhancements for Phantom.grim (5 plugins - 1298 lines).

---

## which-key.gza (364 lines)

**Keybinding discovery popup** - Shows available keybindings as you type.

### Features

- 🔑 **Auto-discovery** - Popup appears after leader key
- 📋 **Grouped bindings** - Organized by category
- ⚡ **Instant** - No delay, shows immediately
- 🎨 **Customizable** - Add your own groups/icons

### Default Groups

| Prefix | Name | Icon | Description |
|--------|------|------|-------------|
| `<leader>f` | Find/Files | 🔍 | Fuzzy finder commands |
| `<leader>g` | Git | 🔀 | Git operations |
| `<leader>b` | Buffers | 📄 | Buffer management |
| `<leader>l` | LSP | 🔧 | Language server |
| `<leader>t` | Terminal/Tmux | 💻 | Terminal & tmux |
| `<leader>d` | Diagnostics | 🩺 | Errors & warnings |
| `<leader>s` | Search | 🔎 | Search operations |
| `<leader>w` | Window | 🪟 | Window splits |

### Usage

```ghostlang
-- Auto-triggered by pressing leader key
<Space>  " → which-key popup appears

-- Navigate with arrow keys or type next key
<Space>f → Shows: ff (files), fg (grep), fb (buffers)...
```

### API

#### Register Custom Keymap

```ghostlang
local which_key = require("which-key")

-- Register single keymap
which_key.register("n", "<leader>xx", ":TodoList<CR>", {
    desc = "Show TODOs"
})

-- Register with custom group
which_key.add_group("<leader>x", {
    name = "Custom",
    icon = "🎯"
})
```

#### Register Bulk Keymaps

```ghostlang
which_key.register_bulk({
    ["<leader>ga"] = { ":GitAdd<CR>", "Stage file" },
    ["<leader>gc"] = { ":GitCommit<CR>", "Commit" },
    ["<leader>gp"] = { ":GitPush<CR>", "Push" },
})
```

### Configuration

```ghostlang
require("which-key").setup({
    delay = 0,              -- No delay
    show_popup = true,      -- Auto-show popup
    icons = true,           -- Show icons
    width = 60,             -- Popup width
    height = 20,            -- Max height
})
```

### Why It's Critical

**LazyVim's success factor:** Which-key makes vim keybindings discoverable!

- ✅ New users learn bindings naturally
- ✅ No need to memorize everything
- ✅ Reduces documentation burden
- ✅ Encourages keyboard-driven workflow

---

## dashboard.gza (233 lines)

**Welcome screen** - Startup greeter with recent files and quick actions.

### Features

- 🎨 **Phantom ASCII art** - Custom header
- 📁 **Recent files** - Quick access to last 10 files
- ⚡ **Quick actions** - One-key commands
- ℹ️ **Session info** - Git branch, tmux status, version

### Screenshot (Text Representation)

```
   ____  __                 __
  / __ \/ /_  ____ _____  / /_____  ____ ___
 / /_/ / __ \/ __ `/ __ \/ __/ __ \/ __ `__ \
/ ____/ / / / /_/ / / / / /_/ /_/ / / / / / /
/_/   /_/ /_/\__,_/_/ /_/\__/\____/_/ /_/ /_/

      🔮 The LazyVim of Grim 🔮


  📁 Recent Files

    1. ~/projects/phantom.grim/init.gza
    2. ~/projects/grim/core/editor.zig
    3. ~/.config/grim/config.gza

  ⚡ Quick Actions

    f  Find files
    g  Live grep
    r  Recent files
    e  File tree
    n  New file
    q  Quit

  ℹ️  Session Info

    Branch: main
    Tmux: session1:0.1
    Phantom.grim v0.1.0-alpha

  Press any key to continue...
```

### Quick Actions

| Key | Action | Description |
|-----|--------|-------------|
| `f` | Find files | Opens fuzzy finder |
| `g` | Live grep | Search in files |
| `r` | Recent files | Browse history |
| `e` | File tree | Open sidebar |
| `n` | New file | Create buffer |
| `1-9` | Open file | Open recent file by number |
| `q` | Quit | Exit Grim |

### API

#### Show Dashboard

```ghostlang
local dashboard = require("dashboard")

-- Show dashboard
dashboard.show()

-- Hide dashboard
dashboard.hide()
```

#### Custom Header

```ghostlang
dashboard.setup({
    header = {
        "  ██████  ██████  ██ ███    ███ ",
        " ██       ██   ██ ██ ████  ████ ",
        " ██   ███ ██████  ██ ██ ████ ██ ",
        " ██    ██ ██   ██ ██ ██  ██  ██ ",
        "  ██████  ██   ██ ██ ██      ██ ",
    },
    max_recent = 10,
    show_on_startup = true,
})
```

### Configuration

```ghostlang
require("dashboard").setup({
    max_recent = 10,        -- Number of recent files
    show_on_startup = true, -- Auto-show on empty session
})
```

---

## bufferline.gza (374 lines)

**Visual buffer tabs** - Tab-like buffer display at top of window.

### Features

- 📑 **Tab display** - Visual tabs for open buffers
- 🎨 **Icons** - Per-filetype icons (👻 .gza, ⚡ .zig, etc.)
- 🔴 **Modified indicators** - Shows unsaved changes (●)
- ✕ **Close buttons** - Click to close buffer
- 🎯 **Pick mode** - Jump to buffer with letter
- ↔️ **Sorting** - By name, directory, extension, tabs

### Visual Example

```
【 👻 init.gza 】  🐍 main.py ●   ⚡ editor.zig   📝 README.md
```

### Keybindings

| Key | Action | Description |
|-----|--------|-------------|
| `<S-h>` | Previous buffer | Move left |
| `<S-l>` | Next buffer | Move right |
| `<leader>bd` | Close buffer | Close current |
| `<leader>bo` | Close others | Keep only current |
| `<leader>bl` | Close left | Close all to left |
| `<leader>br` | Close right | Close all to right |
| `<leader>bp` | Pick buffer | Letter picker mode |
| `<leader>1-9` | Go to buffer | Jump to buffer N |

### API

#### Navigation

```ghostlang
local bufferline = require("bufferline")

-- Navigate
bufferline.next()    -- Next buffer
bufferline.prev()    -- Previous buffer
bufferline.goto(3)   -- Go to buffer 3

-- Close
bufferline.close()        -- Close current
bufferline.close(2)       -- Close buffer 2
bufferline.close_others() -- Keep only current
bufferline.close_left()   -- Close all left
bufferline.close_right()  -- Close all right

-- Sort
bufferline.sort("name")      -- By name
bufferline.sort("directory") -- By directory
bufferline.sort("extension") -- By extension

-- Move
bufferline.move_left()   -- Swap with left
bufferline.move_right()  -- Swap with right

-- Pick
bufferline.pick()  -- Enter pick mode
```

### Configuration

```ghostlang
require("bufferline").setup({
    sort_by = "id",            -- id, name, directory, extension
    show_close_icon = true,    -- Global close button
    show_buffer_close_icons = true,
    show_modified_icon = true,
    show_buffer_icons = true,  -- Filetype icons
    separator_style = "slant", -- slant, padded, thick, thin
    max_name_length = 18,
    tab_size = 18,
})
```

### Separator Styles

| Style | Left | Right | Visual |
|-------|------|-------|--------|
| slant |  |  | Angled |
| padded | ▎ | (space) | Vertical line |
| thick | ▌ | ▐ | Thick bars |
| thin | │ | │ | Thin lines |

---

## indent-guides.gza (327 lines)

**Indent visualization** - Vertical lines showing indentation levels.

### Features

- │ **Visual guides** - Show indent levels
- ┃ **Current scope** - Highlight active block
- 🎯 **Auto-detect** - Smart indent size detection
- 🎨 **Customizable** - Change characters and colors
- 🚫 **Filetype exclusions** - Disable for dashboard, help, etc.

### Visual Example

```ghostlang
function example()
│   if condition then
│   │   for i = 1, 10 do
│   │   ┃   print(i)  ← Current scope highlighted
│   │   end
│   end
end
```

### Scope Highlighting

The plugin highlights the **current indentation block** you're in:

```
function outer()
│   -- Not in this scope
│
┃   if true then          ← Cursor here
┃       local x = 10
┃       print(x)
┃   end                   ← Current scope ends here
│
│   -- Not in this scope
end
```

### API

#### Toggle

```ghostlang
local indent_guides = require("indent-guides")

-- Toggle on/off
indent_guides.toggle()

-- Toggle scope highlighting
indent_guides.toggle_scope()
```

#### Customize Characters

```ghostlang
-- Set guide character
indent_guides.set_char("│")      -- Default
indent_guides.set_char("┆")      -- Dotted
indent_guides.set_char("┊")      -- Light
indent_guides.set_char("▏")      -- Thin

-- Set context character (highlighted)
indent_guides.set_context_char("┃")  -- Thick
indent_guides.set_context_char("▎")  -- Medium
```

#### Filetype Exclusions

```ghostlang
-- Exclude filetypes
indent_guides.exclude_filetype("dashboard")
indent_guides.exclude_filetype("help")

-- Re-include
indent_guides.include_filetype("dashboard")
```

### Configuration

```ghostlang
require("indent-guides").setup({
    enabled = true,
    char = "│",                    -- Guide character
    highlight_current_context = true,
    current_context_char = "┃",   -- Context character
    show_first_indent_level = true,
    indent_levels = 30,            -- Max depth
    exclude_filetypes = {
        "dashboard",
        "help",
        "terminal",
    },
    scope_enabled = true,          -- Highlight active scope
})
```

### Indent Detection

The plugin **auto-detects** indent size from:
1. Buffer settings (if set explicitly)
2. First non-empty line indentation
3. Most common indentation in file
4. Default to 4 spaces

---

## Common Patterns

### Disable UI Plugin

```ghostlang
-- In your config
phantom.plugins.disable({
    "dashboard",        -- No startup screen
    "which-key",        -- No keybinding hints
    "bufferline",       -- No buffer tabs
    "indent-guides",    -- No indent lines
})
```

### Customize All UI Plugins

```ghostlang
-- which-key
require("which-key").setup({
    delay = 500,        -- 500ms delay instead of instant
})

-- dashboard
require("dashboard").setup({
    show_on_startup = false,  -- Don't show on launch
})

-- bufferline
require("bufferline").setup({
    separator_style = "thick",  -- Change style
})

-- indent-guides
require("indent-guides").setup({
    char = "┊",         -- Light character
})
```

---

## Comparison with Neovim Equivalents

| Phantom.grim | Neovim Plugin | Notes |
|--------------|---------------|-------|
| which-key.gza | which-key.nvim | Same UX, Ghostlang impl |
| dashboard.gza | alpha-nvim / dashboard-nvim | Similar features |
| bufferline.gza | barbar.nvim / bufferline.nvim | Tab-like display |
| indent-guides.gza | indent-blankline.nvim | Scope highlighting |

---

## Performance Notes

### Lazy Loading (Optional)

UI plugins can be **lazy-loaded** for faster startup:

```ghostlang
phantom.plugins.lazy({
    which_key = {
        event = "VimEnter",  -- Load after UI ready
    },
    dashboard = {
        event = "VimEnter",
    },
})
```

But **not recommended** - they're already fast:
- which-key: ~5ms startup
- dashboard: ~3ms
- bufferline: ~8ms
- indent-guides: ~4ms

**Total: ~20ms** - negligible overhead.

---

## Troubleshooting

### which-key not showing

Check:
```ghostlang
:lua print(require("which-key").state.initialized)  -- Should be true
```

### dashboard not appearing

```ghostlang
-- Manually show
:lua require("dashboard").show()

-- Check config
:lua print(require("dashboard").state.show_on_startup)
```

### bufferline empty

Bufferline needs multiple buffers:
```
:edit file1.txt
:edit file2.txt  -- Now bufferline appears
```

### indent-guides not visible

```ghostlang
-- Check if enabled
:lua print(require("indent-guides").state.enabled)  -- true?

-- Check filetype exclusions
:lua vim.inspect(require("indent-guides").state.exclude_filetypes)

-- Try toggling
:lua require("indent-guides").toggle()
```

---

**Last Updated:** 2025-10-12
**Status:** Sprint 4 Complete ✅

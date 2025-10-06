# Phantom.grim Theme System Integration

**For the phantom.grim project** - LazyVim-style configuration layer for Grim

This document explains how phantom.grim can leverage Grim's theme system to provide a rich, customizable theming experience similar to LazyVim's colorscheme management.

---

## Overview

Grim provides a dual-format theme system:
- **TOML themes**: Static, simple theme files (like LazyVim's colorscheme configs)
- **GZA themes** (future): Programmable themes using Ghostlang (like LazyVim's dynamic themes)

The default theme is **ghost-hacker-blue** - a Tokyo Night Moon variant with cyan/teal/mint hacker aesthetic.

---

## Theme Architecture

### Theme File Structure

```toml
[theme]
name = "My Theme"
author = "your-name"
variant = "dark"  # or "light"
base = ""         # Optional: inherit from another theme

[palette]
# Define your colors here
bg = "#222436"
fg = "#c8d3f5"
mint = "#8aff80"
blue_hacker = "#57c7ff"
# ... more colors

[syntax]
# Map syntax tokens to colors
function = "mint"           # Reference palette color
comment = "blue_hacker"     # Or use direct hex
keyword = "#89ddff"         # Both work!
# ... more mappings

[ui]
# Map UI elements to colors
cursor = "mint"
background = "bg"
foreground = "fg"
# ... more mappings

[git]
# Git integration colors
added = "green"
modified = "blue"
# ...

[diagnostic]
# LSP diagnostic colors
error = "red"
warning = "yellow"
# ...
```

---

## Theme Locations

Grim searches for themes in these locations (in order):

1. **Project directory**: `./themes/your-theme.toml`
2. **User config**: `~/.config/grim/themes/your-theme.toml` (phantom.grim's domain!)
3. **System-wide**: `/usr/share/grim/themes/your-theme.toml`
4. **Local install**: `/usr/local/share/grim/themes/your-theme.toml`

> **Phantom.grim should manage themes in `~/.config/grim/themes/`** similar to how LazyVim manages colorschemes.

---

## Phantom.grim Integration Guide

### 1. Theme Management (LazyVim-style)

Phantom.grim can provide a theme management system similar to LazyVim's `:Telescope colorscheme`:

```ghostlang
-- ~/.config/grim/init.gza

-- Theme configuration
theme({
  -- Default theme
  default = "ghost-hacker-blue",

  -- Available themes (like LazyVim's colorscheme list)
  themes = {
    "ghost-hacker-blue",
    "tokyonight-moon",
    "tokyonight-storm",
    "tokyonight-night",
    "custom/my-theme",
  },

  -- Auto-download community themes (future feature)
  ensure_installed = {
    "catppuccin",
    "gruvbox",
    "nord",
  },
})

-- Or simple string config
theme("ghost-hacker-blue")
```

### 2. Runtime Theme Switching

Phantom.grim can implement theme switching commands:

```ghostlang
-- Commands to add
:GrimTheme ghost-hacker-blue  -- Switch theme
:GrimThemeEdit                -- Edit current theme
:GrimThemeBrowser             -- Browse available themes (fuzzy picker)
:GrimThemeInstall catppuccin  -- Install community theme
```

### 3. Theme Customization API

Phantom.grim should expose a theme customization API:

```ghostlang
-- ~/.config/grim/init.gza

theme({
  default = "ghost-hacker-blue",

  -- Override specific colors (like LazyVim's highlight overrides)
  overrides = {
    palette = {
      mint = "#7fffd4",  -- Change mint to aquamarine
    },
    syntax = {
      function = "#00ff00",  -- Make functions bright green
    },
    ui = {
      cursor_line = "#1a1b26",  -- Darker cursor line
    },
  },
})
```

### 4. Theme Hooks (LazyVim-style)

Allow users to run code when themes load:

```ghostlang
theme({
  default = "ghost-hacker-blue",

  on_load = fn(theme_name) {
    if theme_name == "ghost-hacker-blue" {
      print("🎨 Hacker mode activated!")
    }
  },

  on_before_load = fn(theme_name) {
    -- Clear custom highlights before loading
  },
})
```

---

## Built-in Themes

### ghost-hacker-blue (Default)

Tokyo Night Moon base with custom hacker colors:

**Signature Colors**:
- **Mint Green** (#8aff80): Functions, primary text
- **Hacker Blue** (#57c7ff): Comments, borders
- **Aquamarine** (#7fffd4): Cursor line
- **Icy Aqua** (#a0ffe8): Selections

**Perfect for**: Midnight coding sessions, hacker aesthetics, cyan/teal lovers

### tokyonight-moon

Official Tokyo Night Moon theme without modifications.

**Perfect for**: Pure Tokyo Night experience, consistency with other editors

---

## Creating Custom Themes

### Option 1: Copy Template

```bash
# From Grim repo
cp themes/custom/template.toml ~/.config/grim/themes/my-theme.toml

# Edit the file
$EDITOR ~/.config/grim/themes/my-theme.toml
```

### Option 2: Inherit from Existing Theme

```toml
[theme]
name = "My Custom Ghost Blue"
author = "your-name"
variant = "dark"
base = "ghost-hacker-blue"  # Inherit all colors

# Override specific colors
[palette]
mint = "#00ff00"  # Make mint brighter

[syntax]
function = "mint"  # Will use your custom mint
```

### Option 3: Programmatic Theme (GZA - Future)

```ghostlang
-- ~/.config/grim/themes/dynamic-theme.gza

theme_fn("Dynamic Theme", fn() {
  const time = get_time()
  const hour = time.hour

  -- Change theme based on time of day
  if hour >= 6 and hour < 18 {
    return load_theme("tokyonight-day")
  } else {
    return load_theme("ghost-hacker-blue")
  }
})
```

---

## Phantom.grim Theme Commands

### Essential Commands (to implement)

```ghostlang
-- Theme module
local theme = require("phantom.theme")

-- Switch theme
theme.set("ghost-hacker-blue")

-- Get current theme
local current = theme.current()

-- List available themes
local themes = theme.list()

-- Reload current theme
theme.reload()

-- Install community theme
theme.install("catppuccin")

-- Create new theme from template
theme.create("my-new-theme")
```

### Fuzzy Theme Picker (Harpoon-style)

```ghostlang
-- Use Grim's fuzzy picker for themes
fuzzy_picker({
  title = "Select Theme",
  items = theme.list(),
  on_select = fn(selected) {
    theme.set(selected)
  },
})
```

---

## Theme FFI Bridge (Future Feature)

When implemented, Ghostlang plugins can query current theme:

```ghostlang
-- Access theme colors from plugins
const current_theme = grim.theme.current()

-- Get specific colors
const fg_color = current_theme.foreground
const cursor_color = current_theme.cursor

-- Use in plugin UI
const popup = create_popup({
  border_color = current_theme.ui.border,
  bg_color = current_theme.ui.background,
})
```

### FFI Functions (Planned)

```c
// C exports for Ghostlang
const char* grim_theme_get_name(void);
const char* grim_theme_get_color(const char* color_name);
bool grim_theme_reload(void);
bool grim_theme_set(const char* theme_name);
```

---

## Community Theme Repository (Future)

Similar to LazyVim's plugin ecosystem:

```ghostlang
-- ~/.config/grim/init.gza

theme({
  default = "ghost-hacker-blue",

  -- Auto-install community themes
  community = {
    { "catppuccin/grim", branch = "main" },
    { "folke/tokyonight-grim", lazy = false },
    { "nordtheme/grim", priority = 1000 },
  },
})
```

---

## Color Palette Reference

### Ghost Hacker Blue Colors

```toml
# Tokyo Night Moon base
bg = "#222436"           # Background
bg_dark = "#1e2030"      # Darker background
fg = "#c8d3f5"           # Foreground

# Hacker colors (custom)
mint = "#8aff80"         # Primary mint
mint_vivid = "#66ffc2"   # Darker mint
minty = "#7fffd4"        # Aquamarine
aqua_ice = "#a0ffe8"     # Icy aqua
blue_hacker = "#57c7ff"  # Hacker blue
blue_moon = "#c0caf5"    # Moon blue

# Tokyo Night colors
blue = "#82aaff"
cyan = "#86e1fc"
green = "#c3e88d"
yellow = "#ffc777"
orange = "#ff966c"
red = "#ff757f"
purple = "#c099ff"
magenta = "#fca7ea"
```

### Syntax Token Mappings

```toml
[syntax]
keyword = "cyan"          # if, for, while, etc.
control = "purple"        # break, continue
type = "blue"             # int, string, etc.
operator = "cyan"         # +, -, =
boolean = "orange"        # true, false

function = "mint"         # 🔥 Signature mint green!
method = "mint"
variable = "fg"
parameter = "yellow"

string = "green"
number = "orange"
comment = "blue_hacker"   # 🔥 Signature hacker blue!

error_token = "red"
warning_token = "yellow"
```

---

## Migration from NeoVim Themes

If you have a NeoVim theme you love:

### Step 1: Extract Colors

```lua
-- From your NeoVim colorscheme.lua
local colors = {
  bg = "#1a1b26",
  fg = "#c0caf5",
  -- ... more colors
}

local highlights = {
  Function = { fg = colors.green },
  Comment = { fg = colors.blue },
  -- ... more highlights
}
```

### Step 2: Convert to Grim TOML

```toml
[palette]
bg = "#1a1b26"
fg = "#c0caf5"
green = "#9ece6a"
blue = "#7aa2f7"

[syntax]
function = "green"
comment = "blue"
```

### Step 3: Test in Grim

```bash
# Copy to Grim themes directory
cp my-theme.toml ~/.config/grim/themes/

# Load in Grim (via phantom.grim)
grim --theme my-theme
```

---

## Best Practices

### For Phantom.grim Developers

1. **Theme Discovery**: Scan `~/.config/grim/themes/` for available themes
2. **Fuzzy Picker**: Integrate theme selection into fuzzy picker
3. **Hot Reload**: Implement `:GrimThemeReload` for instant preview
4. **Validation**: Validate theme files before loading
5. **Fallback**: Always fallback to ghost-hacker-blue if theme fails

### For Theme Authors

1. **Complete Palettes**: Define all required colors
2. **Contrast**: Ensure readability (especially comments!)
3. **Consistency**: Keep related colors harmonious
4. **Testing**: Test with multiple languages
5. **Documentation**: Add usage notes in theme file

### For Users

1. **Experiment**: Try different themes for different contexts
2. **Customize**: Don't be afraid to override colors
3. **Share**: Submit your themes to the community
4. **Backup**: Keep your custom themes in version control

---

## Examples

### Example 1: Time-based Theme Switching

```ghostlang
-- ~/.config/grim/init.gza

local function get_theme_for_time() {
  const hour = os.date("*t").hour

  if hour >= 6 and hour < 9 {
    return "tokyonight-day"    -- Morning: light theme
  } else if hour >= 9 and hour < 18 {
    return "ghost-hacker-blue"  -- Day: default theme
  } else {
    return "tokyonight-night"   -- Night: darker theme
  }
}

theme(get_theme_for_time())

-- Auto-refresh every hour
timer.every("1h", fn() {
  theme.set(get_theme_for_time())
})
```

### Example 2: Project-specific Themes

```ghostlang
-- ~/.config/grim/init.gza

-- Auto-detect project and set theme
autocmd("DirChanged", fn(dir) {
  if dir:match("work/projects") {
    theme.set("gruvbox")  -- Work projects: professional
  } else if dir:match("personal") {
    theme.set("ghost-hacker-blue")  -- Personal: hacker mode
  }
})
```

### Example 3: Minimal Custom Theme

```toml
# ~/.config/grim/themes/minimal.toml

[theme]
name = "Minimal"
variant = "dark"
base = "ghost-hacker-blue"

# Only override what you need
[palette]
bg = "#000000"  # Pure black background

[syntax]
function = "#00ff00"  # Matrix green functions
```

---

## Roadmap

### Phase 1: Current ✅
- [x] TOML theme parser
- [x] ghost-hacker-blue default theme
- [x] Built-in theme fallback
- [x] Template for custom themes

### Phase 2: Phantom.grim Integration 🚧
- [ ] Theme management commands
- [ ] Fuzzy theme picker
- [ ] Runtime theme switching
- [ ] Theme validation

### Phase 3: Advanced Features 📋
- [ ] GZA programmable themes
- [ ] Theme FFI bridge for plugins
- [ ] Hot reload support
- [ ] Theme inheritance

### Phase 4: Community 🌍
- [ ] Community theme repository
- [ ] Theme package manager
- [ ] Theme showcase website
- [ ] Auto-install popular themes

---

## Contributing Themes

Want to contribute a theme to Grim?

1. Create your theme: `themes/custom/my-theme.toml`
2. Test thoroughly with multiple languages
3. Add screenshot to `docs/themes/`
4. Submit PR to [grim repository]
5. Add to phantom.grim community list

---

## Resources

- **Theme Template**: `themes/custom/template.toml`
- **Built-in Themes**: `themes/`
- **Ghost Hacker Blue**: `themes/ghost-hacker-blue.toml`
- **Tokyo Night Moon**: `themes/tokyonight-moon.toml`
- **Theme Loader**: `ui-tui/theme.zig`
- **Color Reference**: Tokyo Night official colors + custom hacker palette

---

## Support

Questions about theming?

- Check the template: `themes/custom/template.toml`
- Read the theme files: `themes/*.toml`
- Open an issue on GitHub
- Ask in phantom.grim discussions

---

**Happy theming! 🎨**

May your colors be vibrant and your contrast be readable.

*- The Grim Team*

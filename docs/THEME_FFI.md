# Theme FFI Bridge Documentation

**C API for Ghostlang plugin theme integration**

This document describes the C-callable FFI functions that allow Ghostlang plugins to interact with Grim's theme system.

---

## Overview

The Theme FFI Bridge exposes Grim's theme system to Ghostlang plugins via C-compatible functions. This enables:

- **Runtime theme loading**: Load themes from .gza or .toml files
- **Theme queries**: Get current theme colors and metadata
- **Dynamic theming**: Plugins can adapt their UI to match the editor theme
- **Hot reload**: Reload themes without restarting Grim

All functions are exported from `src/ghostlang_bridge.zig` with C calling convention.

---

## API Functions

### Theme Loading

#### `grim_theme_load_default`

Load the default theme (ghost-hacker-blue).

```c
bool grim_theme_load_default(GhostlangBridge* bridge);
```

**Parameters**:
- `bridge`: Pointer to the GhostlangBridge instance

**Returns**:
- `true` if theme loaded successfully
- `false` on error

**Example (Ghostlang)**:
```ghostlang
const success = grim.theme.load_default()
if success {
    print("Ghost Hacker Blue theme loaded!")
}
```

---

#### `grim_theme_load`

Load a theme by name from standard theme directories.

```c
bool grim_theme_load(GhostlangBridge* bridge, const char* theme_name);
```

**Parameters**:
- `bridge`: Pointer to the GhostlangBridge instance
- `theme_name`: Null-terminated theme name (without .toml extension)

**Returns**:
- `true` if theme loaded successfully
- `false` if theme not found or failed to load

**Search Paths** (in order):
1. `themes/{name}.toml`
2. `/usr/share/grim/themes/{name}.toml`
3. `/usr/local/share/grim/themes/{name}.toml`

**Example (Ghostlang)**:
```ghostlang
// Load Tokyo Night Moon
const success = grim.theme.load("tokyonight-moon")
if !success {
    print("Failed to load theme, falling back to default")
    grim.theme.load_default()
}
```

---

### Theme Queries

#### `grim_theme_get_name`

Get the name of the currently loaded theme.

```c
const char* grim_theme_get_name(GhostlangBridge* bridge);
```

**Parameters**:
- `bridge`: Pointer to the GhostlangBridge instance

**Returns**:
- Null-terminated string with theme name
- "default" if no theme is loaded

**Example (Ghostlang)**:
```ghostlang
const current = grim.theme.get_name()
print("Current theme: " + current)
```

---

#### `grim_theme_get_color`

Get a theme color as a hex string.

```c
const char* grim_theme_get_color(GhostlangBridge* bridge, const char* color_name);
```

**Parameters**:
- `bridge`: Pointer to the GhostlangBridge instance
- `color_name`: Color identifier (see Available Colors below)

**Returns**:
- Hex color string in format `#RRGGBB`
- `#c8d3f5` (default foreground) on error

**Available Colors**:
- **UI Colors**: `foreground`, `background`, `cursor`, `selection`, `line_number`, `status_bar_bg`, `status_bar_fg`
- **Syntax Colors**: `keyword`, `string`, `number`, `comment`, `function`, `type`, `variable`, `operator`

**Example (Ghostlang)**:
```ghostlang
// Get function color (mint green in ghost-hacker-blue)
const func_color = grim.theme.get_color("function")
print("Function color: " + func_color)  // Output: #8aff80

// Use in plugin UI
const popup = create_popup({
    border_color: grim.theme.get_color("selection"),
    text_color: grim.theme.get_color("foreground"),
})
```

---

#### `grim_theme_get_info`

Get complete theme information as JSON.

```c
const char* grim_theme_get_info(GhostlangBridge* bridge);
```

**Parameters**:
- `bridge`: Pointer to the GhostlangBridge instance

**Returns**:
- JSON string with theme metadata
- `{"loaded":false}` if no theme is loaded

**JSON Structure**:
```json
{
  "loaded": true,
  "name": "ghost-hacker-blue",
  "foreground": "#8aff80",
  "background": "#222436"
}
```

**Example (Ghostlang)**:
```ghostlang
const info = grim.theme.get_info()
const data = json.parse(info)

if data.loaded {
    print("Theme: " + data.name)
    print("FG: " + data.foreground)
    print("BG: " + data.background)
}
```

---

#### `grim_theme_is_loaded`

Check if a theme is currently loaded.

```c
bool grim_theme_is_loaded(GhostlangBridge* bridge);
```

**Parameters**:
- `bridge`: Pointer to the GhostlangBridge instance

**Returns**:
- `true` if a theme is loaded
- `false` otherwise

**Example (Ghostlang)**:
```ghostlang
if !grim.theme.is_loaded() {
    grim.theme.load_default()
}
```

---

### Theme Management

#### `grim_theme_reload`

Reload the current theme from disk.

```c
bool grim_theme_reload(GhostlangBridge* bridge);
```

**Parameters**:
- `bridge`: Pointer to the GhostlangBridge instance

**Returns**:
- `true` if reload succeeded
- `false` on error

**Use Case**: Hot-reloading themes during development

**Example (Ghostlang)**:
```ghostlang
// Watch theme file for changes
watch_file("themes/my-theme.toml", fn() {
    grim.theme.reload()
    print("Theme reloaded!")
})
```

---

## Complete Examples

### Example 1: Theme-aware Plugin UI

```ghostlang
-- ~/.config/grim/plugins/fuzzy-finder.gza

fn create_themed_picker() {
    // Get colors from current theme
    const bg = grim.theme.get_color("background")
    const fg = grim.theme.get_color("foreground")
    const border = grim.theme.get_color("selection")
    const match = grim.theme.get_color("function")  // Mint green in ghost-hacker-blue

    // Create picker with theme colors
    return FuzzyPicker({
        title: "Files",
        background: bg,
        foreground: fg,
        border_color: border,
        match_highlight: match,
        items: find_files("."),
    })
}

-- Plugin adapts to any theme user loads
const picker = create_themed_picker()
picker.show()
```

---

### Example 2: Dynamic Theme Switching

```ghostlang
-- ~/.config/grim/init.gza

-- Theme switcher command
command("ThemeSwitch", fn() {
    const themes = ["ghost-hacker-blue", "tokyonight-moon", "tokyonight-storm"]

    fuzzy_pick(themes, fn(selected) {
        if grim.theme.load(selected) {
            print("✓ Switched to " + selected)
        } else {
            print("✗ Failed to load " + selected)
        }
    })
})

-- Keybinding
keymap("n", "<leader>tc", ":ThemeSwitch<CR>", { desc = "Switch theme" })
```

---

### Example 3: Time-based Theme Auto-switch

```ghostlang
-- ~/.config/grim/init.gza

fn update_theme_for_time() {
    const hour = os.date("*t").hour

    if hour >= 6 and hour < 18 {
        grim.theme.load("tokyonight-day")
    } else {
        grim.theme.load("ghost-hacker-blue")  // Night mode
    }
}

-- Load appropriate theme on startup
update_theme_for_time()

-- Check every hour
timer.every("1h", update_theme_for_time)
```

---

### Example 4: Theme Inspector Plugin

```ghostlang
-- ~/.config/grim/plugins/theme-inspector.gza

command("ThemeInspect", fn() {
    const info = json.parse(grim.theme.get_info())

    if !info.loaded {
        print("No theme loaded!")
        return
    }

    print("Theme: " + info.name)
    print("─" ** 40)

    const colors = [
        "foreground", "background", "cursor", "selection",
        "keyword", "string", "number", "comment",
        "function", "type", "variable", "operator"
    ]

    for color in colors {
        const hex = grim.theme.get_color(color)
        print(color.pad_right(15) + " : " + hex)
    }
})
```

---

### Example 5: Hot Reload During Development

```ghostlang
-- ~/.config/grim/init.gza (dev mode)

if is_dev_mode() {
    -- Watch custom theme for changes
    watch_file("themes/my-custom-theme.toml", fn() {
        print("Theme file changed, reloading...")
        if grim.theme.reload() {
            print("✓ Theme reloaded successfully")
        } else {
            print("✗ Failed to reload theme")
        }
    })
}
```

---

## Color Name Reference

### UI Colors

| Name | Description | Ghost Hacker Blue |
|------|-------------|-------------------|
| `foreground` | Main text color | #8aff80 (mint) |
| `background` | Editor background | #222436 |
| `cursor` | Cursor color | #8aff80 (mint) |
| `selection` | Selection background | #a0ffe8 (aqua ice) |
| `line_number` | Line number color | #636da6 |
| `status_bar_bg` | Status bar background | #1e2030 |
| `status_bar_fg` | Status bar foreground | #c0caf5 (blue moon) |

### Syntax Colors

| Name | Description | Ghost Hacker Blue |
|------|-------------|-------------------|
| `keyword` | Keywords (if, for, etc.) | #89ddff (cyan) |
| `string` | String literals | #c3e88d (green) |
| `number` | Number literals | #ffc777 (yellow) |
| `comment` | Comments | #57c7ff (hacker blue) |
| `function` | Function names | #8aff80 (mint) |
| `type` | Type names | #65bcff (blue1) |
| `variable` | Variables | #c8d3f5 (fg) |
| `operator` | Operators (+, -, etc.) | #c0caf5 (blue moon) |

---

## Memory Management

### Returned Strings

All functions that return `const char*` return **heap-allocated**, **null-terminated** strings. The caller is responsible for freeing these strings.

**In Zig**:
```zig
const name = grim_theme_get_name(bridge);
defer bridge.allocator.free(std.mem.span(name));
```

**In Ghostlang** (automatic):
Ghostlang's runtime handles memory management automatically. No manual cleanup needed.

### Bridge Lifecycle

The GhostlangBridge automatically cleans up theme resources in `deinit()`. Plugins don't need to manually free theme data.

---

## Error Handling

### Boolean Functions

Functions returning `bool` use the following convention:
- `true` = Success
- `false` = Failure

### String Functions

Functions returning `const char*` use the following convention:
- Valid pointer = Success
- Empty string `""` or default value = Partial failure (graceful fallback)
- Never returns `NULL` - always safe to use

### Example Error Handling

```ghostlang
// Safe - always returns a valid string
const color = grim.theme.get_color("function")
use_color(color)  // No null check needed

// Boolean - check for success
if !grim.theme.load("my-theme") {
    print("Failed to load, using default")
    grim.theme.load_default()
}
```

---

## Integration with Phantom.grim

Phantom.grim can provide high-level wrappers around these FFI functions:

```ghostlang
-- phantom.grim/lua/phantom/theme.lua (conceptual)

local M = {}

function M.current()
    return ffi.call("grim_theme_get_name")
end

function M.load(name)
    return ffi.call("grim_theme_load", name)
end

function M.color(name)
    return ffi.call("grim_theme_get_color", name)
end

function M.info()
    local json = ffi.call("grim_theme_get_info")
    return vim.json.decode(json)
end

function M.reload()
    return ffi.call("grim_theme_reload")
end

return M
```

**Usage in phantom.grim**:
```lua
local theme = require("phantom.theme")

-- Get current theme
print("Theme: " .. theme.current())

-- Get colors
local mint = theme.color("function")
local bg = theme.color("background")

-- Switch theme
theme.load("tokyonight-moon")
```

---

## Performance Notes

### Color Queries

`grim_theme_get_color()` allocates a new string on each call. For frequently-accessed colors in tight loops, consider caching:

```ghostlang
// Bad - allocates on every iteration
for item in items {
    render(item, grim.theme.get_color("function"))
}

// Good - cache the color
const func_color = grim.theme.get_color("function")
for item in items {
    render(item, func_color)
}
```

### Theme Switching

Theme switching (`grim_theme_load`) is relatively expensive as it:
1. Reads and parses TOML file
2. Resolves color references
3. Rebuilds theme structure

Avoid switching themes in tight loops or frequently-called functions.

---

## Future Enhancements

### Planned Features

- **Theme events**: Callbacks when theme changes
- **Partial theme overrides**: Modify specific colors without full reload
- **Theme validation**: Check if theme file is valid before loading
- **Built-in theme list**: Query available themes
- **Theme metadata**: Get theme author, variant, description

### Example (Future API)

```ghostlang
// Subscribe to theme changes
grim.theme.on_change(fn(theme_name) {
    print("Theme changed to: " + theme_name)
    update_plugin_ui()
})

// Override specific colors
grim.theme.override({
    function: "#00ff00",
    comment: "#0000ff",
})

// List available themes
const themes = grim.theme.list()
```

---

## Troubleshooting

### Theme Not Loading

**Problem**: `grim_theme_load()` returns `false`

**Solutions**:
1. Check file exists: `ls themes/your-theme.toml`
2. Verify TOML syntax: Use a TOML validator
3. Check file permissions: Ensure readable
4. Try absolute path for debugging

### Wrong Colors

**Problem**: Colors don't match theme file

**Solutions**:
1. Reload theme: `grim.theme.reload()`
2. Check color name spelling
3. Verify color is defined in theme file
4. Try `grim.theme.get_info()` to debug

### Memory Issues

**Problem**: Leaked memory or crashes

**Solutions**:
1. Ensure proper string cleanup (Zig only)
2. Don't cache pointers across theme switches
3. Update to latest Grim version
4. Report bug with reproduction steps

---

## Resources

- **Theme Files**: `themes/*.toml`
- **Template**: `themes/custom/template.toml`
- **FFI Source**: `src/ghostlang_bridge.zig`
- **Theme Loader**: `ui-tui/theme.zig`
- **Phantom.grim Guide**: `PHANTOM_GRIM_THEME.md`

---

## Contributing

Want to enhance the Theme FFI?

**Ideas for contributions**:
- Add more color query functions
- Implement theme change callbacks
- Add theme validation API
- Create Ghostlang wrapper library
- Write more example plugins

**Pull requests welcome!** 🎨

---

**Built with ❤️ for the Grim editor**

*Making themes accessible to plugins, one FFI call at a time.*

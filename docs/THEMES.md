# Theme System

Grim features a dynamic, extensible theme system for customizing syntax highlighting and UI colors.

## Overview

The theme system (`ui-tui/theme.zig`) provides:
- RGB color definitions
- Automatic RGB → ANSI 256-color conversion
- Per-token-type color lookup
- Multiple built-in themes
- Foundation for user-defined themes

## Built-in Themes

### Dark Theme (Default)

The default dark theme matches Grim's current color scheme:

```zig
const theme = Theme.defaultDark();
```

**Syntax colors:**
- Keywords: Pink/Magenta (`#FF0087`)
- Strings: Green (`#87D75F`)
- Numbers: Orange (`#FF8700`)
- Comments: Gray (`#878787`)
- Functions: Cyan (`#5FD7FF`)
- Types: Purple (`#AF5FD7`)
- Variables: Light gray (`#D7D7D7`)
- Operators: Brown (`#D7875F`)
- Errors: White on dark red background

### Light Theme

Alternative light theme for bright environments:

```zig
const theme = Theme.defaultLight();
```

**Syntax colors:**
- Keywords: Dark magenta
- Strings: Dark green
- Numbers: Dark orange
- Comments: Gray
- Functions: Dark blue
- Types: Purple
- Variables: Dark gray
- Operators: Brown
- Errors: Dark red on light pink background

## Color System

### RGB Colors

Colors are defined as RGB values:

```zig
const my_color = Color{ .r = 255, .g = 128, .b = 64 };
```

### ANSI 256-Color Conversion

Colors are automatically converted to ANSI 256-color codes for terminal display:

```zig
const code = my_color.toAnsi256();  // Returns u8 (0-255)
```

The conversion uses a 6×6×6 color cube (colors 16-231):
- R/G/B values mapped to 0-5 range
- Formula: `16 + (36*r) + (6*g) + b`

### ANSI Escape Sequences

Get ANSI sequences for terminal output:

```zig
var buf: [32]u8 = undefined;

// Foreground color
const fg = try my_color.toFgSequence(&buf);
// Result: "\x1B[38;5;{code}m"

// Background color
const bg = try my_color.toBgSequence(&buf);
// Result: "\x1B[48;5;{code}m"
```

## Theme Structure

A theme defines colors for both syntax highlighting and UI elements:

```zig
pub const Theme = struct {
    // Syntax highlighting
    keyword: Color,
    string_literal: Color,
    number_literal: Color,
    comment: Color,
    function_name: Color,
    type_name: Color,
    variable: Color,
    operator: Color,
    punctuation: Color,
    error_bg: Color,
    error_fg: Color,

    // UI colors
    background: Color,
    foreground: Color,
    cursor: Color,
    selection: Color,
    line_number: Color,
    status_bar_bg: Color,
    status_bar_fg: Color,
};
```

## Using Themes

### In SimpleTUI

Themes are integrated into the TUI rendering:

```zig
pub const SimpleTUI = struct {
    theme: Theme,
    // ... other fields
};

// Initialize with default dark theme
self.theme = Theme.defaultDark();

// Use in rendering
var buf: [32]u8 = undefined;
const seq = try self.theme.getHighlightSequence(.keyword, &buf);
try self.stdout.writeAll(seq);
```

### Highlight Sequence Lookup

Get ANSI sequence for a specific highlight type:

```zig
const HighlightType = syntax.HighlightType;

var buf: [32]u8 = undefined;

// Get color for keywords
const keyword_seq = try theme.getHighlightSequence(.keyword, &buf);

// Get color for strings
const string_seq = try theme.getHighlightSequence(.string_literal, &buf);

// Errors get both fg and bg colors
const error_seq = try theme.getHighlightSequence(.@"error", &buf);
```

## Creating Custom Themes

### Define a new theme

```zig
pub fn myCustomTheme() Theme {
    return .{
        // Syntax colors
        .keyword = .{ .r = 200, .g = 100, .b = 255 },  // Purple
        .string_literal = .{ .r = 100, .g = 200, .b = 100 },  // Green
        .number_literal = .{ .r = 255, .g = 150, .b = 50 },  // Orange
        .comment = .{ .r = 120, .g = 120, .b = 120 },  // Gray
        .function_name = .{ .r = 100, .g = 150, .b = 255 },  // Blue
        .type_name = .{ .r = 200, .g = 100, .b = 200 },  // Magenta
        .variable = .{ .r = 220, .g = 220, .b = 220 },  // Light gray
        .operator = .{ .r = 200, .g = 150, .b = 100 },  // Brown
        .punctuation = .{ .r = 150, .g = 150, .b = 150 },  // Mid gray
        .error_bg = .{ .r = 150, .g = 0, .b = 0 },  // Dark red
        .error_fg = .{ .r = 255, .g = 255, .b = 255 },  // White

        // UI colors
        .background = .{ .r = 20, .g = 20, .b = 20 },
        .foreground = .{ .r = 220, .g = 220, .b = 220 },
        .cursor = .{ .r = 255, .g = 255, .b = 0 },  // Yellow cursor
        .selection = .{ .r = 50, .g = 50, .b = 80 },  // Subtle blue
        .line_number = .{ .r = 100, .g = 100, .b = 100 },
        .status_bar_bg = .{ .r = 40, .g = 40, .b = 60 },
        .status_bar_fg = .{ .r = 200, .g = 200, .b = 255 },
    };
}
```

### Apply at runtime

```zig
// In SimpleTUI init or command
self.theme = myCustomTheme();
```

## Configuration File Support

Theme loading from config files is planned:

```zig
// Future API
const theme = try Theme.loadFromFile(allocator, "~/.config/grim/theme.toml");
```

### Example TOML format (planned)

```toml
[syntax]
keyword = "#FF0087"
string_literal = "#87D75F"
number_literal = "#FF8700"
comment = "#878787"
function_name = "#5FD7FF"
type_name = "#AF5FD7"
variable = "#D7D7D7"
operator = "#D7875F"
punctuation = "#8787AF"

[syntax.error]
background = "#5F0000"
foreground = "#FFFFFF"

[ui]
background = "#000000"
foreground = "#D7D7D7"
cursor = "#FFFFFF"
selection = "#3C3C3C"
line_number = "#646464"

[ui.status_bar]
background = "#282828"
foreground = "#C8C8C8"
```

## Popular Theme Examples

### Dracula

```zig
pub fn dracula() Theme {
    return .{
        .keyword = .{ .r = 255, .g = 121, .b = 198 },  // Pink
        .string_literal = .{ .r = 241, .g = 250, .b = 140 },  // Yellow
        .number_literal = .{ .r = 189, .g = 147, .b = 249 },  // Purple
        .comment = .{ .r = 98, .g = 114, .b = 164 },  // Blue gray
        .function_name = .{ .r = 80, .g = 250, .b = 123 },  // Green
        .type_name = .{ .r = 139, .g = 233, .b = 253 },  // Cyan
        // ... etc
    };
}
```

### Solarized Dark

```zig
pub fn solarizedDark() Theme {
    return .{
        .background = .{ .r = 0, .g = 43, .b = 54 },  // Base03
        .foreground = .{ .r = 131, .g = 148, .b = 150 },  // Base0
        .keyword = .{ .r = 38, .g = 139, .b = 210 },  // Blue
        .string_literal = .{ .r = 42, .g = 161, .b = 152 },  // Cyan
        .number_literal = .{ .r = 211, .g = 54, .b = 130 },  // Magenta
        // ... etc
    };
}
```

## Performance

- **Color lookup**: O(1) - Direct field access
- **RGB → ANSI conversion**: ~5 arithmetic operations
- **Escape sequence generation**: ~10 bytes, stack-allocated
- **No heap allocations** for theme usage

## Future Features

- [ ] TOML config file parsing
- [ ] Runtime theme switching command
- [ ] Theme preview/selection UI
- [ ] Theme validation and error reporting
- [ ] Theme inheritance/extension
- [ ] Per-filetype theme overrides
- [ ] True color (24-bit RGB) support for modern terminals

---

*Generated with [Claude Code](https://claude.ai/code)*

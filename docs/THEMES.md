# Grim Themes

Grim includes a comprehensive collection of modern, professionally-designed themes for an exceptional coding experience.

## Available Themes

### Ghost Hacker Blue (Default)
**Color Scheme:** `ghost_hacker_blue`

The signature Grim theme featuring deep blue tones inspired by Tokyo Night.

- **Background:** Deep midnight blue (#1a1b26)
- **Keywords:** Electric blue (#7aa2f7)
- **Strings:** Mint green (#9ece6a)
- **Comments:** Subtle grey (#565f89)
- **Functions:** Sky blue (#7dcfff)
- **Numbers:** Orange (#ff9e64)

Perfect for: Late-night coding sessions, reduced eye strain

### Tokyo Night Moon
**Color Scheme:** `tokyonight_moon`

A deeper, purple-tinted variant of Tokyo Night.

- **Background:** Deep purple-blue (#222436)
- **Keywords:** Purple (#bb9af7)
- **Strings:** Green (#9ece6a)
- **Comments:** Grey-blue (#636da6)
- **Functions:** Cyan (#7dcfff)
- **Numbers:** Peach (#ff9e64)

Perfect for: Night owls, purple enthusiasts

### Tokyo Night Storm
**Color Scheme:** `tokyonight_storm`

A balanced storm-grey variant of Tokyo Night.

- **Background:** Storm grey (#24283b)
- **Keywords:** Blue (#7aa2f7)
- **Strings:** Green (#9ece6a)
- **Comments:** Grey (#565f89)
- **Functions:** Cyan (#7dcfff)
- **Numbers:** Orange (#ff9e64)

Perfect for: Professional environments, balanced contrast

### Nord
**Color Scheme:** `nord`

Arctic-inspired palette with cool blues and muted accents.

- **Background:** Polar night (#2e3440)
- **Keywords:** Frost blue (#81a1c1)
- **Strings:** Aurora green (#a3be8c)
- **Comments:** Snow storm grey (#616e88)
- **Functions:** Frost cyan (#88c0d0)
- **Numbers:** Aurora orange (#d08770)

Perfect for: Minimalists, Scandinavian design lovers

### Gruvbox Dark
**Color Scheme:** `gruvbox_dark`

Retro groove with warm, earthy tones.

- **Background:** Dark brown (#282828)
- **Keywords:** Red (#fb4934)
- **Strings:** Green (#b8bb26)
- **Comments:** Grey (#928374)
- **Functions:** Blue (#83a598)
- **Numbers:** Purple (#d3869b)

Perfect for: Vintage aesthetics, warm color preference

### Gruvbox Light
**Color Scheme:** `gruvbox_light`

Light variant of Gruvbox with paper-like background.

- **Background:** Cream (#fbf1c7)
- **Keywords:** Red (#cc241d)
- **Strings:** Green (#98971a)
- **Comments:** Grey (#7c6f64)
- **Functions:** Blue (#458588)
- **Numbers:** Purple (#b16286)

Perfect for: Daytime coding, light theme preference

### Catppuccin Mocha
**Color Scheme:** `catppuccin_mocha`

Soothing pastel dark theme with warm undertones.

- **Background:** Base (#1e1e2e)
- **Keywords:** Lavender (#b4befe)
- **Strings:** Green (#a6e3a1)
- **Comments:** Overlay grey (#6c7086)
- **Functions:** Sky (#89dceb)
- **Numbers:** Peach (#fab387)

Perfect for: Soft aesthetics, pastel lovers

### Catppuccin Latte
**Color Scheme:** `catppuccin_latte`

Light variant of Catppuccin with latte-inspired tones.

- **Background:** Base (#eff1f5)
- **Keywords:** Lavender (#7287fd)
- **Strings:** Green (#40a02b)
- **Comments:** Overlay grey (#9ca0b0)
- **Functions:** Sky (#179299)
- **Numbers:** Peach (#fe640b)

Perfect for: Light theme with personality, cafe vibes

### Dracula
**Color Scheme:** `dracula`

Popular dark theme with vibrant purples and pinks.

- **Background:** Dark (#282a36)
- **Keywords:** Pink (#ff79c6)
- **Strings:** Yellow (#f1fa8c)
- **Comments:** Grey (#6272a4)
- **Functions:** Cyan (#8be9fd)
- **Numbers:** Orange (#ffb86c)

Perfect for: High contrast, vibrant colors, vampires 🧛

### One Dark
**Color Scheme:** `one_dark`

The classic Atom One Dark theme.

- **Background:** Dark grey (#282c34)
- **Keywords:** Purple (#c678dd)
- **Strings:** Green (#98c379)
- **Comments:** Grey (#5c6370)
- **Functions:** Blue (#61afef)
- **Numbers:** Orange (#d19a66)

Perfect for: Atom/VSCode refugees, balanced contrast

### Solarized Dark
**Color Scheme:** `solarized_dark`

Precision colors for machines and people.

- **Background:** Base (#002b36)
- **Keywords:** Blue (#268bd2)
- **Strings:** Cyan (#2aa198)
- **Comments:** Grey (#586e75)
- **Functions:** Blue (#268bd2)
- **Numbers:** Violet (#6c71c4)

Perfect for: Scientific accuracy, reduced eye strain

### Solarized Light
**Color Scheme:** `solarized_light`

Light variant of the precision Solarized palette.

- **Background:** Base (#fdf6e3)
- **Keywords:** Blue (#268bd2)
- **Strings:** Cyan (#2aa198)
- **Comments:** Grey (#93a1a1)
- **Functions:** Blue (#268bd2)
- **Numbers:** Violet (#6c71c4)

Perfect for: Bright environments, scientific precision

## Configuration

### Setting a Theme

Edit `~/.config/grim/config.grim`:

```
# Theme Configuration
theme = tokyonight-moon
color_scheme = tokyonight_moon
```

### Available Options

```
color_scheme = ghost_hacker_blue
color_scheme = tokyonight_moon
color_scheme = tokyonight_storm
color_scheme = nord
color_scheme = gruvbox_dark
color_scheme = gruvbox_light
color_scheme = catppuccin_mocha
color_scheme = catppuccin_latte
color_scheme = dracula
color_scheme = one_dark
color_scheme = solarized_dark
color_scheme = solarized_light
```

## Theme Features

All themes include professionally-tuned colors for:

### Syntax Highlighting
- Keywords (const, fn, if, for, etc.)
- String literals
- Number literals
- Comments
- Function names
- Type names
- Variables
- Operators
- Punctuation

### UI Elements
- Background
- Foreground text
- Cursor
- Selection highlight
- Line numbers
- Status bar
- Error backgrounds and foreground
- LSP diagnostics

### LSP Integration
- Error diagnostics (red)
- Warning diagnostics (yellow/orange)
- Info diagnostics (blue)
- Hint diagnostics (grey/subtle)

## Theme Customization

Themes are defined in `/ui-tui/theme.zig`. Each theme is a pure Zig function returning a `Theme` struct with RGB colors.

### Example Theme Structure

```zig
fn myCustomTheme() Theme {
    return .{
        .keyword = Color.fromHex("7aa2f7") catch unreachable,
        .string_literal = Color.fromHex("9ece6a") catch unreachable,
        .background = Color.fromHex("1a1b26") catch unreachable,
        // ... more colors
    };
}
```

## Best Practices

### Choosing a Theme

1. **Environment**: Bright office → Light theme (Gruvbox Light, Catppuccin Latte, Solarized Light)
2. **Time of Day**: Night coding → Dark theme with blue light reduction
3. **Contrast**: Eye strain → Solarized, Nord
4. **Aesthetics**: Modern → Tokyo Night, Catppuccin
5. **Retro**: Vintage feel → Gruvbox
6. **Vibrant**: High energy → Dracula

### Font Pairing

Themes work best with Nerd Fonts:

```
font_family = JetBrainsMono Nerd Font
nerd_fonts_enabled = true
```

See [NERD_FONTS.md](NERD_FONTS.md) for details.

## Performance

All themes use RGB colors with zero overhead:
- Colors are compile-time constants
- No runtime color parsing
- Instant theme switching
- Memory efficient

## Screenshots

### Dark Themes
- **Ghost Hacker Blue**: Deep blue, low eye strain
- **Tokyo Night Moon**: Purple-tinted, elegant
- **Tokyo Night Storm**: Balanced grey-blue
- **Nord**: Arctic frost, minimalist
- **Gruvbox Dark**: Warm retro groove
- **Catppuccin Mocha**: Soft pastel dark
- **Dracula**: Vibrant purple-pink
- **One Dark**: Classic dark grey
- **Solarized Dark**: Scientific precision

### Light Themes
- **Gruvbox Light**: Warm paper tones
- **Catppuccin Latte**: Soft pastel light
- **Solarized Light**: Precision cream

## Contributing Themes

To add a new theme:

1. Add enum variant to `ColorScheme` in `/ui-tui/config.zig`
2. Implement theme function in `/ui-tui/theme.zig`
3. Add to `Theme.get()` switch statement
4. Update `parseColorScheme()` in config.zig
5. Document here with color palette
6. Submit PR with screenshots

## Theme Philosophy

Grim themes follow these principles:

1. **Accessibility**: Sufficient contrast for readability
2. **Consistency**: Semantic color usage across elements
3. **Professional**: Suitable for production environments
4. **Eye Comfort**: Reduced blue light for dark themes
5. **Personality**: Each theme has unique character
6. **Performance**: Zero runtime overhead

## Resources

- Theme source: `/ui-tui/theme.zig`
- Config handling: `/ui-tui/config.zig`
- Color utilities: RGB hex parsing, color blending
- LSP integration: Diagnostic color mapping

## Example Configurations

### Ghost Hacker Setup
```
theme = ghost-hacker-blue
color_scheme = ghost_hacker_blue
font_family = FiraCode Nerd Font
font_size = 13
nerd_fonts_enabled = true
```

### Tokyo Night Developer
```
theme = tokyonight-moon
color_scheme = tokyonight_moon
font_family = JetBrainsMono Nerd Font
font_size = 14
nerd_fonts_enabled = true
show_statusline = true
```

### Nord Minimalist
```
theme = nord
color_scheme = nord
font_family = Hack Nerd Font
font_size = 12
nerd_fonts_enabled = true
show_gutter_signs = true
```

### Gruvbox Retro
```
theme = gruvbox
color_scheme = gruvbox_dark
font_family = Inconsolata Nerd Font
font_size = 14
nerd_fonts_enabled = true
```

---

**Enjoy coding with beautiful themes! 🎨**

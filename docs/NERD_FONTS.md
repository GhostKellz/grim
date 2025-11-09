# Nerd Fonts Support in Grim

Grim has comprehensive Nerd Fonts support, providing beautiful icons for files, UI elements, LSP features, and more.

## What are Nerd Fonts?

Nerd Fonts are patched fonts that include thousands of glyphs (icons) from popular icon collections like Font Awesome, Material Design Icons, Devicons, and more. They're essential for a modern IDE experience with rich visual indicators.

## Recommended Nerd Fonts

The following Nerd Fonts are recommended for the best Grim experience:

### Top Picks

1. **JetBrains Mono Nerd Font** (Default)
   - Font family: `JetBrainsMono Nerd Font`
   - Excellent readability
   - Designed for developers
   - Supports ligatures

2. **Fira Code Nerd Font**
   - Font family: `FiraCode Nerd Font`
   - Popular coding font
   - Excellent ligature support
   - Clean and modern

3. **Hack Nerd Font**
   - Font family: `Hack Nerd Font`
   - Designed for source code
   - High legibility
   - Compact spacing

### Other Popular Options

4. **Meslo Nerd Font**
   - Font family: `MesloLGS Nerd Font`
   - Derivative of Menlo
   - Great for terminals

5. **Inconsolata Nerd Font**
   - Font family: `Inconsolata Nerd Font`
   - Classic monospace
   - Clean and simple

6. **Ubuntu Mono Nerd Font**
   - Font family: `UbuntuMono Nerd Font`
   - Modern Ubuntu font
   - Good readability

## Configuration

### Enabling Nerd Fonts

Add to your `~/.config/grim/config.grim`:

```
# Font Configuration
font_family = JetBrainsMono Nerd Font
font_size = 14
nerd_fonts_enabled = true
```

### Available Font Families

Check which Nerd Fonts are installed on your system:

```bash
fc-list : family | grep "Nerd Font"
```

### Font Settings

- **font_family**: The font name (e.g., "JetBrainsMono Nerd Font")
- **font_size**: Font size in points (default: 14)
- **nerd_fonts_enabled**: Enable/disable Nerd Font icons (default: true)

## Icon Support

When Nerd Fonts are enabled, Grim displays beautiful icons for:

### File Types

- Programming languages (Zig, Rust, Go, JavaScript, Python, etc.)
- Web technologies (HTML, CSS, TypeScript, Vue, React)
- Data formats (JSON, YAML, TOML, XML, CSV)
- Documentation (Markdown, PDF, TXT)
- Build files (Makefile, Dockerfile, Shell scripts)
- Archives (ZIP, TAR, GZ)
- Images (PNG, JPG, SVG, GIF)
- **Ghostlang (.gza)** - Custom ghost icon 👻

### LSP Features

- Completion items (functions, methods, variables, classes, etc.)
- Diagnostics (errors, warnings, info, hints)
- Code actions
- Signature help
- Hover information
- Inlay hints

### UI Elements

- Modified buffer indicator
- LSP active/inactive status
- Mode indicators (Normal, Insert, Visual, Command)
- Git branch
- Line/column numbers
- Search
- Buffer picker
- Fuzzy finder

## ASCII Fallback

When `nerd_fonts_enabled = false`, Grim automatically falls back to ASCII characters:

- File icons: `[Z]`, `[R]`, `[J]`, etc.
- Modified: `*`
- Mode: `NORMAL`, `INSERT`, `VISUAL`, `COMMAND`
- LSP: `[LSP]`, `[-]`, `[~]`
- Diagnostics: `E`, `W`, `I`, `H`

## Installing Nerd Fonts

### Arch Linux / Manjaro

```bash
yay -S nerd-fonts-jetbrains-mono
yay -S nerd-fonts-fira-code
yay -S nerd-fonts-hack
```

### Ubuntu / Debian

Download from [Nerd Fonts Releases](https://github.com/ryanoasis/nerd-fonts/releases):

```bash
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip
unzip JetBrainsMono.zip
fc-cache -fv
```

### Manual Installation

1. Download from: https://www.nerdfonts.com/font-downloads
2. Extract to `~/.local/share/fonts/`
3. Run `fc-cache -fv`

## Theme Integration

Nerd Fonts work seamlessly with all Grim themes:

- Ghost Hacker Blue
- Tokyo Night (Moon, Storm)
- Nord
- Gruvbox (Dark, Light)
- Catppuccin (Mocha, Latte)
- Dracula
- One Dark
- Solarized (Dark, Light)

## Troubleshooting

### Icons not showing

1. Verify Nerd Fonts are installed:
   ```bash
   fc-list | grep "Nerd Font"
   ```

2. Check config:
   ```
   nerd_fonts_enabled = true
   font_family = JetBrainsMono Nerd Font
   ```

3. Verify terminal supports UTF-8:
   ```bash
   echo $LANG
   # Should show: en_US.UTF-8 or similar
   ```

### Wrong icons / Boxes appearing

- Ensure you're using the "Nerd Font" variant, not the base font
- Example: Use "JetBrainsMono Nerd Font" not "JetBrains Mono"
- The Nerd Font variant includes the icon glyphs

### Terminal compatibility

- **Supported**: Alacritty, Kitty, WezTerm, iTerm2, Terminator
- **Limited**: gnome-terminal, konsole (may need configuration)
- **Not supported**: Basic xterm

## Resources

- [Nerd Fonts Homepage](https://www.nerdfonts.com/)
- [Nerd Fonts Cheat Sheet](https://www.nerdfonts.com/cheat-sheet)
- [Nerd Fonts GitHub](https://github.com/ryanoasis/nerd-fonts)
- [Font Manager Source](/ui-tui/font_manager.zig)

## Example Configuration

```
# Grim Configuration with Nerd Fonts
# ~/.config/grim/config.grim

# UI Settings
theme = tokyonight-moon
color_scheme = tokyonight_moon
font_size = 14
font_family = JetBrainsMono Nerd Font
nerd_fonts_enabled = true

# Editor Settings
tab_width = 4
use_spaces = true
show_line_numbers = true
cursor_line_highlight = true

# LSP Settings
lsp_enabled = true
lsp_diagnostics_enabled = true
lsp_hover_enabled = true
lsp_completion_enabled = true
```

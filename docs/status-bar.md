# Status Bar

Grim features a Powerline-style status bar that displays editor state, file information, git status, and LSP diagnostics.

## Overview

The status bar is always visible at the bottom of the editor and consists of two sections:

- **Left Section**: Mode, indicators, file path
- **Right Section**: LSP diagnostics, git branch, cursor position, file percentage

## Status Bar Segments

### Mode Indicator

Shows the current editor mode with color coding:

| Mode | Color | Display |
|------|-------|---------|
| Normal | Blue | ` NORMAL ` |
| Insert | Green | ` INSERT ` |
| Visual | Magenta | ` VISUAL ` |
| Visual Line | Magenta | ` V-LINE ` |
| Visual Block | Magenta | ` V-BLOCK ` |
| Command | Yellow | ` COMMAND ` |

### Recording Indicator

When recording a macro, displays:

```
 REC[a]   # Recording to register 'a'
```

Background: Red (high visibility)

### LSP Loading Indicator

Shows when LSP server is processing:

```
󰔟 LSP
```

Background: Cyan

### LSP Diagnostics

Displays error and warning counts from LSP:

```
 2  # 2 errors (red background, white text)
 5  # 5 warnings (yellow background, black text)
```

**Features**:
- Only shows if errors or warnings exist
- Errors take priority (red) over warnings (yellow)
- Real-time updates as code changes
- Clicking opens diagnostics panel (future feature)

### Modified Indicator

Shows when current file has unsaved changes:

```
  # File modified (red background)
```

### File Path

Displays the current file name (or `[No Name]` for new buffers):

```
 main.zig      # Zig file with icon
 config.json  # JSON file with icon
```

File type icons are automatically detected based on extension.

### Git Branch

Shows current git branch (if in a git repository):

```
 main     # On 'main' branch
 feature  # On 'feature' branch
```

Background: Transparent  
Foreground: Cyan (bold)

### Cursor Position

Displays line:column position:

```
142:23  # Line 142, Column 23
```

Foreground: Bright yellow

### File Percentage

Shows relative position in file:

```
45%   # 45% through the file
0%    # At top of file
100%  # At bottom of file
```

## Configuration

The status bar appearance can be customized in `config.json`:

```json
{
  "ui": {
    "status_bar": {
      "enabled": true,
      "style": "powerline",  // or "simple"
      "show_git": true,
      "show_diagnostics": true,
      "show_position": true,
      "show_percentage": true,
      "separator": ""
    }
  }
}
```

## Implementation

### Location

- **Module**: `ui-tui/powerline_status.zig`
- **Integration**: `ui-tui/grim_app.zig`

### Key Structures

```zig
pub const PowerlineStatus = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    width: u16,
    
    pub fn init(allocator: std.mem.Allocator, width: u16) !*PowerlineStatus
    pub fn render(buffer, area, editor_widget, mode, git) !void
    pub fn resize(new_width: u16) void
};
```

### Rendering Segments

Each segment is rendered with:

```zig
fn renderDiagnosticsSegment(errors: usize, warnings: usize) !void {
    if (errors > 0) {
        // Red background for errors
        const text = try std.fmt.allocPrint(
            allocator,
            "\x1b[41m\x1b[97m  {d} \x1b[0m ",
            .{errors}
        );
        try buffer.appendSlice(text);
    }
    // ...
}
```

### ANSI Escape Codes

The status bar uses ANSI escape sequences for colors:

| Code | Effect |
|------|--------|
| `\x1b[41m` | Red background |
| `\x1b[42m` | Green background |
| `\x1b[43m` | Yellow background |
| `\x1b[44m` | Blue background |
| `\x1b[30m` | Black foreground |
| `\x1b[97m` | Bright white foreground |
| `\x1b[0m` | Reset all attributes |

## Icons

The status bar uses Nerd Font icons:

| Icon | Unicode | Usage |
|------|---------|-------|
|  | U+E0A0 | Git branch |
|  | U+F023 | Lock/readonly |
|  | U+F111 | Modified indicator |
|  | U+F069 | Recording macro |
| 󰔟 | U+F051F | LSP loading |
|  | U+F06A | Error |
|  | U+F071 | Warning |

## Troubleshooting

### Icons Not Displaying

**Issue**: Seeing squares or question marks instead of icons

**Solution**: Install a Nerd Font and configure your terminal:

```bash
# Install Nerd Font (example for Arch Linux)
yay -S ttf-jetbrains-mono-nerd

# Configure terminal to use the font
# For Alacritty: edit ~/.config/alacritty/alacritty.yml
font:
  normal:
    family: "JetBrainsMono Nerd Font"
```

### Colors Not Showing

**Issue**: Status bar is monochrome

**Solution**: Ensure your terminal supports 256 colors:

```bash
echo $TERM  # Should be 'xterm-256color' or 'screen-256color'

# Set in shell rc file:
export TERM=xterm-256color
```

### Git Branch Not Showing

**Issue**: Git branch not displayed even in git repository

**Solution**: 
1. Ensure you're in a git repository: `git status`
2. Check that you're on a branch (not detached HEAD)
3. Verify git is in PATH: `which git`

### LSP Diagnostics Not Updating

**Issue**: Error/warning counts are stale

**Solution**:
1. Check LSP server is running (LSP loading indicator)
2. Save the file to trigger re-validation
3. Restart LSP: `:LspRestart`

## Performance

The status bar is optimized for performance:

- **Incremental Updates**: Only segments that change are re-rendered
- **String Pooling**: ANSI codes are reused
- **No Allocations**: Uses a pre-allocated buffer (cleared each frame)
- **Lazy Evaluation**: Git branch is cached until directory changes

## Examples

### Normal Mode (No Issues)

```
 NORMAL   main.zig   main 142:23 45%
```

### Insert Mode (With Errors)

```
 INSERT   main.zig  2   main 142:23 45%
```

### Visual Mode (Recording + Modified)

```
 VISUAL   REC[q]   server.rs   feature 89:10 30%
```

### LSP Loading

```
 NORMAL  󰔟 LSP  config.json 1:1 0%
```

## See Also

- [LSP Diagnostics](lsp-diagnostics.md)
- [Git Integration](git-integration.md)
- [Theming](theming.md)

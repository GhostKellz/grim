# Split Windows

Grim supports Vim-style window splits for viewing and editing multiple buffers simultaneously.

## Overview

Split windows allow you to:

- View multiple files side-by-side
- Compare code across files
- Reference documentation while coding
- Edit related files together

## Basic Commands

### Creating Splits

| Command | Keybinding | Description |
|---------|------------|-------------|
| `:vsplit` | `<C-w>v` | Split window vertically (left/right) |
| `:hsplit` | `<C-w>s` | Split window horizontally (top/bottom) |
| `:split [file]` | - | Split and open file |
| `:vsplit [file]` | - | Vertical split and open file |

### Navigating Between Windows

| Keybinding | Command | Description |
|------------|---------|-------------|
| `<C-w>h` | `:wincmd h` | Move to window on the left |
| `<C-w>j` | `:wincmd j` | Move to window below |
| `<C-w>k` | `:wincmd k` | Move to window above |
| `<C-w>l` | `:wincmd l` | Move to window on the right |
| `<C-w>w` | `:wincmd w` | Cycle to next window |
| `<C-w>p` | `:wincmd p` | Go to previous window |

### Resizing Windows

| Keybinding | Command | Description |
|------------|---------|-------------|
| `<C-w>=` | `:wincmd =` | Equalize all window sizes |
| `<C-w>_` | `:wincmd _` | Maximize current window height |
| `<C-w>|` | `:wincmd |` | Maximize current window width |
| `<C-w>+` | `:resize +5` | Increase height by 5 lines |
| `<C-w>-` | `:resize -5` | Decrease height by 5 lines |
| `<C-w>>` | `:vertical resize +5` | Increase width |
| `<C-w><` | `:vertical resize -5` | Decrease width |

### Closing Windows

| Keybinding | Command | Description |
|------------|---------|-------------|
| `<C-w>c` | `:close` | Close current window |
| `<C-w>o` | `:only` | Close all windows except current |
| `:q` | - | Close current window (if not last) |
| `:qa` | - | Close all windows and quit |

## Configuration

### Window Appearance

In `config.json`:

```json
{
  "window": {
    "split_border_style": "rounded",    // "single", "double", "rounded", "thick"
    "split_border_color": "bright_blue",
    "active_border_color": "bright_cyan",
    "inactive_border_color": "bright_black",
    "show_border": true,
    "min_width": 20,
    "min_height": 5
  }
}
```

### Border Styles

| Style | Example |
|-------|---------|
| `single` | `┌───┐` `│   │` `└───┘` |
| `double` | `╔═══╗` `║   ║` `╚═══╝` |
| `rounded` | `╭───╮` `│   │` `╰───╯` |
| `thick` | `┏━━━┓` `┃   ┃` `┗━━━┛` |

### Custom Keybindings

```json
{
  "keybindings": {
    "custom": {
      "<C-w>v": ":vsplit",
      "<C-w>s": ":hsplit",
      "<C-w>h": ":wincmd h",
      "<C-w>j": ":wincmd j",
      "<C-w>k": ":wincmd k",
      "<C-w>l": ":wincmd l",
      "<C-w>c": ":close",
      "<C-w>=": ":wincmd =",
      "<C-w>_": ":wincmd _"
    }
  }
}
```

## Usage Examples

### Side-by-Side Editing

```vim
:vsplit src/parser.zig    " Open parser in vertical split
" Edit both files simultaneously
" <C-w>l to switch to right window
" <C-w>h to switch back to left window
```

### Comparing Files

```vim
:vsplit old_version.zig   " Open old version on right
:diffthis                 " Enable diff mode (future feature)
<C-w>h                    " Go to left window
:diffthis                 " Enable diff mode
```

### Reference + Coding

```vim
:split docs/api.md        " Open docs above
<C-w>_                    " Minimize docs window
<C-w>j                    " Back to code
" Docs visible for reference, maximized space for coding
```

### Multi-File Editing

```vim
:vsplit src/main.zig
:split src/config.zig
<C-w>=                    " Equalize all windows
" Now have 3 files visible in 2x2 grid
```

## Implementation

### Window Manager

Location: `ui-tui/window_manager.zig`

```zig
pub const WindowManager = struct {
    root_window: ?*Window,
    active_window_id: u32,
    buffer_manager: *BufferManager,
    
    pub fn init(allocator, buffer_mgr) !WindowManager
    pub fn splitWindow(direction: SplitDirection) !void
    pub fn closeWindow() !void
    pub fn navigateWindow(direction: Direction) !void
    pub fn resize(width: u16, height: u16) void
    pub fn equalizeWindows() void
    pub fn maximizeWindow() !void
    pub fn switchWindowBuffer(buffer_id: u32) !void
};
```

### Window Structure

Windows are organized in a binary tree:

```zig
pub const Window = struct {
    id: u32,
    buffer_id: u32,
    layout: WindowLayout,
    parent: ?*Window,
    children: ?struct {
        left: *Window,
        right: *Window,
        direction: SplitDirection,  // horizontal or vertical
    },
};
```

### Split Direction

```zig
pub const SplitDirection = enum {
    horizontal,  // Left/right split (|)
    vertical,    // Top/bottom split (─)
};
```

### Window Layout

```zig
pub const WindowLayout = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};
```

## Advanced Features

### Directional Navigation Algorithm

Grim uses a distance-based algorithm for `<C-w>hjkl` navigation:

1. Calculate center point of current window
2. Find all windows in the specified direction
3. Calculate Euclidean distance to each window
4. Switch to the closest window

```zig
pub fn navigateWindow(self: *WindowManager, direction: Direction) !void {
    const current = try self.getActiveWindow();
    const leaves = try self.getLeafWindows();
    
    var best_window: ?*Window = null;
    var best_distance: f32 = std.math.floatMax(f32);
    
    const current_center_x = @as(f32, @floatFromInt(current.layout.x + current.layout.width / 2));
    const current_center_y = @as(f32, @floatFromInt(current.layout.y + current.layout.height / 2));
    
    for (leaves) |window| {
        const center_x = @as(f32, @floatFromInt(window.layout.x + window.layout.width / 2));
        const center_y = @as(f32, @floatFromInt(window.layout.y + window.layout.height / 2));
        
        const dx = center_x - current_center_x;
        const dy = center_y - current_center_y;
        
        const is_correct_direction = switch (direction) {
            .left => dx < -5.0,
            .right => dx > 5.0,
            .up => dy < -5.0,
            .down => dy > 5.0,
        };
        
        if (!is_correct_direction) continue;
        
        const distance = @sqrt(dx * dx + dy * dy);
        if (distance < best_distance) {
            best_distance = distance;
            best_window = window;
        }
    }
    
    if (best_window) |window| {
        self.active_window_id = window.id;
    }
}
```

### Window Resizing

Window sizes are recalculated recursively when terminal is resized:

```zig
fn recalculateLayouts(window: *Window) void {
    if (window.children) |children| {
        const layout = window.layout;
        
        switch (children.direction) {
            .horizontal => {
                // Split left/right
                const mid_x = layout.x + layout.width / 2;
                children.left.layout = .{
                    .x = layout.x,
                    .y = layout.y,
                    .width = layout.width / 2,
                    .height = layout.height,
                };
                children.right.layout = .{
                    .x = mid_x,
                    .y = layout.y,
                    .width = layout.width - layout.width / 2,
                    .height = layout.height,
                };
            },
            .vertical => {
                // Split top/bottom
                const mid_y = layout.y + layout.height / 2;
                children.left.layout = .{
                    .x = layout.x,
                    .y = layout.y,
                    .width = layout.width,
                    .height = layout.height / 2,
                };
                children.right.layout = .{
                    .x = layout.x,
                    .y = mid_y,
                    .width = layout.width,
                    .height = layout.height - layout.height / 2,
                };
            },
        }
        
        recalculateLayouts(children.left);
        recalculateLayouts(children.right);
    }
}
```

## Troubleshooting

### Split Not Creating

**Issue**: `:vsplit` does nothing

**Solutions**:
1. Ensure terminal size is large enough (minimum 40 columns for vsplit)
2. Check keybinding is not overridden
3. Verify no errors in command line

### Cannot Navigate to Window

**Issue**: `<C-w>h` not moving to left window

**Solutions**:
1. Ensure window exists in that direction
2. Check terminal is capturing Ctrl+W (some terminals use it)
3. Try command mode: `:wincmd h`

### Window Borders Not Showing

**Issue**: No visual separation between windows

**Solutions**:
1. Enable borders in config: `"show_border": true`
2. Use a Nerd Font for border characters
3. Check terminal supports Unicode box-drawing characters

### Uneven Window Sizes After Resize

**Issue**: Windows not evenly distributed after terminal resize

**Solution**: Use `<C-w>=` to equalize all windows

## Workflow Examples

### Development Workflow

```vim
" Open main code file
:e src/main.zig

" Split for tests
:vsplit tests/main_test.zig

" Split for docs
:split docs/api.md

" Now have 3 windows: docs (top), main (bottom-left), tests (bottom-right)
<C-w>=                    " Equalize sizes
```

### Debugging Workflow

```vim
" Source code
:e src/server.zig

" Logs in horizontal split
:split /tmp/server.log

" Tail the logs
:terminal tail -f /tmp/server.log

" Code on top, logs updating below
```

## Best Practices

1. **Limit Split Depth**: 2-3 levels max for readability
2. **Use Equalize**: Run `<C-w>=` after creating multiple splits
3. **Close Unused Windows**: Don't let windows accumulate, close with `<C-w>c`
4. **Learn Navigation**: Master `<C-w>hjkl` for efficient navigation
5. **Save Layouts**: Use session management to preserve complex layouts

## See Also

- [Session Management](session-management.md)
- [Keybindings](keybindings.md)
- [Configuration](configuration.md)
- [Buffer Management](buffers.md)

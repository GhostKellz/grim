# LSP Completion

Grim provides intelligent code completion powered by Language Server Protocol (LSP).

## Features

### Completion Menu

The completion menu displays context-aware suggestions as you type, with:

- **Fuzzy Filtering**: Quickly find completions by typing any substring
- **Kind Icons**: Visual indicators for different completion types (functions, variables, classes, etc.)
- **Documentation Preview**: View detailed information about each suggestion
- **Keyboard Navigation**: Navigate completions with arrow keys or Vim motions

### Completion Types

Each completion item is marked with an icon indicating its type:

| Icon | Type | Description |
|------|------|-------------|
| 󰊕 | Function/Method | Callable functions and class methods |
|  | Constructor | Class constructors |
| 󰜢 | Field/Property | Object fields and properties |
| 󰀫 | Variable | Local and global variables |
| 󰠱 | Class | Class definitions |
|  | Interface | Interface definitions |
| 󰌋 | Keyword | Language keywords |
|  | Snippet | Code templates |
|  | Enum | Enumeration values |
| 󰏿 | Constant | Constant values |

## Usage

### Triggering Completions

Completions can be triggered:

1. **Automatically**: While typing (if enabled in config)
2. **Manually**: Press `Ctrl+N` (insert mode)
3. **After Trigger Characters**: Typing `.`, `::`, `->` etc.

### Navigating Completions

| Key | Action |
|-----|--------|
| `Ctrl+N` | Trigger/Select next completion |
| `Ctrl+P` | Select previous completion |
| `↓`/`j` | Move down in list |
| `↑`/`k` | Move up in list |
| `Enter` | Accept selected completion |
| `Esc` | Close completion menu |

### Configuration

In your `config.json`:

```json
{
  "lsp": {
    "enabled": true,
    "completion": {
      "auto_trigger": true,
      "trigger_characters": [".", "::", "->", "("],
      "max_items": 20,
      "show_documentation": true
    }
  }
}
```

## Implementation Details

### Completion Menu Widget

Location: `ui-tui/completion_menu.zig`

The completion menu is implemented as a reusable widget with:

```zig
pub const CompletionMenu = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(CompletionItem),
    filtered_indices: std.ArrayList(usize),
    selected_index: usize,
    filter_query: std.ArrayList(u8),
    visible: bool,
    max_visible_items: usize,
    scroll_offset: usize,
    
    pub fn init(allocator: std.mem.Allocator) !*CompletionMenu
    pub fn show(self: *CompletionMenu, items: []const CompletionItem) !void
    pub fn hide(self: *CompletionMenu) void
    pub fn setFilter(self: *CompletionMenu, query: []const u8) !void
    pub fn selectNext(self: *CompletionMenu) void
    pub fn selectPrev(self: *CompletionMenu) void
    pub fn getSelected(self: *CompletionMenu) ?CompletionItem
};
```

### Fuzzy Matching Algorithm

The completion menu uses a simple but effective fuzzy matching algorithm:

1. Convert both query and text to lowercase
2. Find each query character in order within the text
3. Return match if all query characters are found sequentially

This allows queries like "tf" to match "testFunction".

### LSP Integration

Completions are requested from the LSP server using:

```zig
// Request completions at cursor position
try lsp_client.requestCompletion(file_uri, line, column);

// Handle completion response
pub fn handleCompletionResponse(items: []const LSPCompletionItem) void {
    const grim_items = try convertToCompletionItems(items);
    try completion_menu.show(grim_items);
}
```

## Examples

### Basic Usage

```zig
// Type 'std.' and press Ctrl+N
std.|  // Cursor here
    // Completion menu appears with:
    //   󰀫 debug
    //   󰀫 mem
    //   󰀫 fs
    //   󰠱 ArrayList
    //   ...
```

### Fuzzy Search

```zig
// Type 'alint' to quickly find ArrayList.init
std.ArrayList.|
    // Filter: "alint"
    // Shows: ArrayList.init()
```

## Troubleshooting

### Completions Not Appearing

1. **Check LSP Status**: Ensure LSP server is running (look for LSP indicator in status bar)
2. **Verify Config**: Check that `lsp.enabled = true` in config
3. **Server Logs**: Check `~/.local/state/grim/lsp.log` for errors

### Slow Completions

1. **Reduce max_items**: Lower `lsp.completion.max_items` in config
2. **Disable Auto-trigger**: Set `lsp.completion.auto_trigger = false`
3. **Server Performance**: Some LSP servers (like rust-analyzer) may be slow on large projects

### Missing Icons

Ensure you're using a Nerd Font in your terminal. Recommended fonts:

- JetBrains Mono Nerd Font
- Fira Code Nerd Font
- Hack Nerd Font

## See Also

- [LSP Configuration](lsp-configuration.md)
- [Keybindings Reference](keybindings.md)
- [Status Bar](status-bar.md)

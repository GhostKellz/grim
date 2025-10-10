# LSP Integration Testing Guide

## Overview

GRIM has full LSP integration with diagnostics, hover, completion, and go-to-definition support. This guide covers testing with zls (Zig) and rust-analyzer (Rust).

## Available LSP Servers

✅ **zls**: `/home/chris/.local/share/nvim/mason/bin/zls`
✅ **rust-analyzer**: `/home/chris/.local/share/nvim/mason/bin/rust-analyzer`

## Testing with zls (Zig Language Server)

### 1. Basic Setup

```bash
cd /data/projects/grim
# Open any Zig file in grim
./zig-out/bin/grim src/main.zig
```

### 2. Features to Test

**Diagnostics** (Errors/Warnings)
- Create a syntax error: `const x = ;`
- Should see `E` marker in gutter
- Status line should show error count and message

**Hover Information** (Press 'H' in normal mode)
- Position cursor over a standard library function
- Press `H` to request hover info
- Check status line for hover text

**Go-to-Definition** (Press 'D' in normal mode)
- Position cursor over a function call
- Press `D` to jump to definition
- Should navigate to the definition location

**Completion** (Ctrl+Space in insert mode)
- Type `std.` in insert mode
- Press Ctrl+Space (or wait for auto-trigger on '.')
- Completion popup should appear with std library members
- Use Tab/Ctrl+N to navigate, Enter to accept

### 3. Expected Behavior

```
Status Line Format:
MODE | line,col | bytes | language | error_count | warning_count | diagnostics
```

Example with error:
```
NORMAL | 42,10 | 1234 bytes | zig | ERR: expected expression, found ';'
```

## Testing with rust-analyzer

### 1. Create Test Rust File

```bash
mkdir -p /tmp/rust-test && cd /tmp/rust-test
cat > Cargo.toml <<EOF
[package]
name = "test"
version = "0.1.0"
edition = "2021"
EOF

cat > src/main.rs <<EOF
fn main() {
    let x = ;  // Error for testing
    println!("Hello, world!");

    // Test completion
    let s = String::
}
EOF

# Open in grim
/data/projects/grim/zig-out/bin/grim src/main.rs
```

### 2. Features to Test

Same as zls:
- Diagnostics on line 2 (syntax error)
- Hover on `println!` macro
- Go-to-definition on `String`
- Completion after `String::`

## LSP Integration Architecture

### Files
- `lsp/lsp_client.zig` - JSON-RPC LSP client
- `ui-tui/editor_lsp.zig` - Editor-LSP bridge
- `ui-tui/simple_tui.zig` - UI integration
- `ui-tui/lsp_highlights.zig` - Visual diagnostics (new)

### Key Bindings
- `H` - Request hover (normal mode)
- `D` - Go to definition (normal mode)
- `Ctrl+Space` - Trigger completion (insert mode)
- `Ctrl+N` / `Ctrl+P` - Navigate completions
- `Tab` - Next completion
- `Enter` - Accept completion
- `Esc` - Cancel completion

### Status Line Integration

The status line shows:
1. Current mode (NORMAL/INSERT/VISUAL/COMMAND)
2. Cursor position (line, column)
3. Buffer size in bytes
4. Language name
5. Diagnostic counts (errors, warnings)
6. Current line diagnostic message
7. Hover information (when available)

## Diagnostics Visualization

### Gutter Markers
- `E` - Error
- `W` - Warning
- `I` - Information
- `H` - Hint

### Highlight Groups (via HighlightThemeAPI)
- `lsp_error` - Red underline
- `lsp_warning` - Yellow underline
- `lsp_information` - Blue underline
- `lsp_hint` - Gray underline

## Completion Features

### Supported Formats
- **Plain text** - Simple string insertion
- **Snippets** - LSP snippet syntax with placeholders
  - `$1`, `$2`, `$0` - Tab stops
  - `${1:default}` - Placeholders with defaults
  - Selection after insertion

### Completion Popup
```
Completions 3/15 (prefix: Str)
→ String               — std.string.String
  StringHashMap        — hash map with string keys
  StringBuilder        — string builder

(documentation preview)

Tab/Ctrl+N next • Ctrl+P prev • Enter apply • Esc cancel
```

## Advanced Testing

### Multi-Buffer LSP
1. Open multiple Zig files
2. Each buffer should have independent LSP state
3. Diagnostics should update per-buffer

### Hot Reload
1. Make changes to a file
2. LSP should re-analyze automatically
3. Diagnostics should update in real-time

### Performance
- Completion should appear within 200ms
- Hover should respond within 100ms
- Go-to-definition should be instant

## Troubleshooting

### LSP Not Working
```bash
# Check LSP server availability
which zls
which rust-analyzer

# Check LSP logs (if logging is enabled)
tail -f ~/.cache/grim/lsp.log
```

### Common Issues

**No completions appearing**
- Check if LSP server is running for that file type
- Verify completion trigger characters (`.`, `::`, etc.)

**Diagnostics not showing**
- Ensure file is saved (LSP typically works on disk state)
- Check if file is in a valid project (Cargo.toml for Rust, etc.)

**Hover not working**
- Position cursor exactly on the symbol
- Some symbols may not have hover information

## Integration Status

✅ **Implemented**
- JSON-RPC LSP client
- Diagnostics with gutter markers
- Hover information
- Go-to-definition
- Completion with fuzzy filtering
- Snippet expansion (basic)
- Status line integration

🚧 **Planned**
- Semantic highlighting (via LSP)
- Code actions
- Signature help
- Document symbols
- Workspace symbols
- Refactoring support

## Testing Checklist

- [ ] zls diagnostics appear correctly
- [ ] zls hover shows type information
- [ ] zls completion works with std library
- [ ] zls go-to-definition navigates correctly
- [ ] rust-analyzer diagnostics appear correctly
- [ ] rust-analyzer hover shows documentation
- [ ] rust-analyzer completion works with std types
- [ ] rust-analyzer go-to-definition works
- [ ] Completion popup renders properly
- [ ] Snippet placeholders work
- [ ] Multi-buffer LSP state is independent
- [ ] Status line shows diagnostic counts
- [ ] Gutter markers appear for errors/warnings

## Performance Benchmarks

Target latencies:
- **Completion request**: <200ms
- **Hover request**: <100ms
- **Go-to-definition**: <50ms
- **Diagnostic update**: <500ms

Actual measurements will vary based on project size and LSP server.

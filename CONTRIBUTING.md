# Contributing to Grim

Thank you for your interest in contributing to Grim! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Architecture Overview](#architecture-overview)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)
- [Documentation](#documentation)

---

## Development Setup

### Prerequisites

- **Zig 0.16.0-dev** or later
- Git
- Basic understanding of:
  - Modal editing (Vim concepts)
  - Tree-sitter (syntax parsing)
  - Language Server Protocol (LSP)

### Building from Source

```bash
# Clone the repository
git clone https://github.com/ghostkellz/grim.git
cd grim

# Fetch dependencies
zig build --fetch

# Build with Ghostlang support (recommended for development)
zig build -Dghostlang=true

# Run tests
zig build test

# Run the editor
zig build run -Dghostlang=true
```

### Project Structure

```
grim/
├── core/           # Core data structures (Rope, Config, Git, etc.)
├── lsp/            # Language Server Protocol client
├── runtime/        # Plugin runtime and APIs
├── syntax/         # Tree-sitter integration
├── ui-tui/         # Terminal UI implementation
├── host/           # Ghostlang host integration
├── src/            # Main entry point
├── tests/          # Integration and unit tests
└── tools/          # Development tools (gpkg, etc.)
```

---

## Code Style

### Zig Style Guidelines

Follow the official [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide):

- **4-space indentation** (no tabs)
- **snake_case** for functions and variables
- **PascalCase** for types
- **SCREAMING_SNAKE_CASE** for constants
- Keep lines under **100 characters** when possible

### Code Formatting

```bash
# Format all Zig files
zig fmt .
```

### Naming Conventions

```zig
// Types
pub const BufferManager = struct { ... };
pub const EditorMode = enum { normal, insert, visual, command };

// Functions
pub fn loadFile(path: []const u8) !void { ... }
pub fn saveBuffer(buffer: *Buffer) !void { ... }

// Variables
var cursor_position: usize = 0;
const max_buffer_size: usize = 100 * 1024 * 1024;

// Constants
const DEFAULT_TAB_WIDTH: u8 = 4;
const LSP_TIMEOUT_MS: u64 = 5000;
```

### Documentation Comments

Use `///` for public APIs:

```zig
/// Load a file into the buffer
/// Handles UTF-8 encoding and normalizes line endings
///
/// Arguments:
///   path: Absolute or relative file path
///
/// Returns:
///   Error if file cannot be read or is too large
pub fn loadFile(self: *Editor, path: []const u8) !void {
    // Implementation
}
```

### Error Handling

- Use `error_handler` module for user-facing errors
- Provide context in error messages
- Use `try` for propagating errors
- Use `catch` with specific error handling when needed

```zig
const core = @import("core");

// Good: Descriptive error handling
const content = self.loadFileSync(path) catch |err| {
    core.ErrorHandler.logError(err, .{
        .operation = "Load file",
        .file_path = path,
    });
    return err;
};

// Bad: Silent failure
const content = self.loadFileSync(path) catch return;
```

---

## Architecture Overview

### Core Components

#### 1. **Rope Data Structure** (`core/rope.zig`)
- Efficient text buffer for large files
- Supports insertions, deletions, and slicing
- O(log n) operations

#### 2. **Modal Engine** (`ui-tui/editor.zig`)
- Vim-style modal editing (normal, insert, visual, command)
- Keybinding system with operators and motions
- Multi-cursor support

#### 3. **LSP Client** (`lsp/client.zig`)
- JSON-RPC 2.0 protocol implementation
- Async request/response handling
- Diagnostics, hover, completion, goto-definition

#### 4. **Plugin System** (`runtime/mod.zig`)
- Ghostlang-powered plugins
- Hot reload support
- Dependency resolution
- Sandboxed execution

#### 5. **Tree-sitter Integration** (`syntax/treesitter.zig`)
- Incremental parsing
- Syntax highlighting
- Code navigation

### Data Flow

```
User Input → TUI (simple_tui.zig)
    ↓
Editor (editor.zig) → Rope (rope.zig)
    ↓
LSP Client (lsp/client.zig) ← Language Server
    ↓
Rendering → Phantom TUI Framework
```

### Key Design Principles

1. **Performance First**: Use efficient data structures (Rope, SIMD)
2. **Modularity**: Each component should be independently testable
3. **Error Resilience**: Graceful degradation when servers crash
4. **Extensibility**: Plugin system for custom functionality

---

## Pull Request Process

### Before Submitting

1. **Run tests**: `zig build test`
2. **Format code**: `zig fmt .`
3. **Build successfully**: `zig build`
4. **Test manually**: Run the editor and verify changes
5. **Update documentation**: If adding features, update README.md

### PR Guidelines

- **One feature per PR**: Keep changes focused
- **Descriptive titles**: Use conventional commits format
  - `feat: Add LSP completion menu`
  - `fix: Resolve rope boundary bug`
  - `docs: Update CONTRIBUTING.md`
  - `refactor: Simplify buffer management`
- **Clear description**: Explain what, why, and how
- **Include tests**: Add tests for new functionality
- **Reference issues**: Link to related issues

### Conventional Commit Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`

Example:
```
feat(lsp): Add completion menu with documentation

- Implement floating window for completions
- Show documentation preview
- Support fuzzy filtering
- Add keybindings (Ctrl+Space to trigger)

Closes #42
```

### Code Review

- Address all comments
- Rebase on main before merging
- Squash commits if requested
- Be responsive to feedback

---

## Testing

### Unit Tests

```zig
test "Rope insert at beginning" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "Hello");
    try std.testing.expectEqualStrings("Hello", rope.slice(.{ .start = 0, .end = 5 }));
}
```

### Integration Tests

Located in `tests/` directory:

```bash
# Run all tests
zig build test

# Run specific test
zig test tests/benchmark.zig
```

### Manual Testing Checklist

- [ ] Editor opens without crashing
- [ ] Can open, edit, and save files
- [ ] Vim motions work correctly
- [ ] LSP features function (if applicable)
- [ ] No memory leaks (use Valgrind)
- [ ] Performance is acceptable

---

## Documentation

### Where to Document

- **Code comments**: Implementation details
- **Doc comments** (`///`): Public API
- **README.md**: User-facing features
- **CONTRIBUTING.md**: Developer guidelines
- **KEYBINDINGS.md**: Keybinding reference

### Documentation Standards

- Keep examples simple and focused
- Include expected output
- Mention edge cases
- Update when code changes

---

## Common Tasks

### Adding a New Vim Motion

1. Update `ui-tui/vim_commands.zig` with new motion enum
2. Implement motion logic in `ui-tui/editor.zig`
3. Add keybinding in `handleNormalMode()`
4. Update `KEYBINDINGS.md`
5. Add tests

### Adding LSP Feature

1. Define request/response types in `lsp/client.zig`
2. Implement send/receive logic
3. Add UI rendering in `ui-tui/editor.zig`
4. Handle errors gracefully
5. Test with multiple language servers

### Creating a Plugin API

1. Define API in `runtime/` directory
2. Expose to Ghostlang in `host/ghostlang.zig`
3. Document in plugin documentation
4. Create example plugin
5. Add tests

---

## Getting Help

- **Discord**: [Join our community](https://discord.gg/grim) _(placeholder)_
- **GitHub Issues**: Report bugs or request features
- **Discussions**: Ask questions or share ideas

---

## License

By contributing to Grim, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to Grim! 🎉

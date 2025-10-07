# Ghostlang Plugin Syntax Guide for Grim

## ✅ ISSUE RESOLVED - Use `var` Not `const`!

**TL;DR:** Your plugin scripts are using `const` which is NOT supported. Use `var` instead for variables, and `function` for functions.

---

## The Problem

You're using unsupported syntax:
```ghostlang
// ❌ WRONG - const is NOT a keyword in Ghostlang
const message = "Plugin loaded"

fn setup() {  // ❌ WRONG - fn is NOT a keyword
    print(message)
}
```

Ghostlang supports **`var`** for variables and **`function`** for functions:
```ghostlang
-- ✅ CORRECT - Use var for variables
var message = "Plugin loaded"

function setup()  -- ✅ CORRECT - Use function keyword
    print(message)
end
```

**OR** use Lua-style `local`:
```ghostlang
-- ✅ ALSO CORRECT - Lua-compatible
local message = "Plugin loaded"

function setup()
    print(message)
end
```

---

## Supported Keywords

Ghostlang supports **TWO variable declaration keywords**:

| Keyword | Usage | Scope |
|---------|-------|-------|
| `var` | `var x = 10` | Global or scoped depending on context |
| `local` | `local x = 10` | Local scope (Lua-compatible) |

**NOT SUPPORTED:**
- ❌ `const` - Not a keyword
- ❌ `let` - Not a keyword
- ❌ `fn` - Not a keyword (use `function`)
- ❌ `export` - Not a keyword

---

## Correct Plugin Template

Here's what your `init.gza` should look like:

### Option 1: Using `var` (C-style)
```ghostlang
-- Plugin metadata
var plugin = {
    name = "hello-world",
    version = "1.0.0",
    description = "Example plugin"
}

-- Plugin state
var enabled = true

-- Your plugin functions
function setup()
    print("Plugin loaded: " .. plugin.name)
    return true
end

function teardown()
    print("Plugin unloaded")
    return true
end

-- Export plugin interface
return {
    setup = setup,
    teardown = teardown
}
```

### Option 2: Using `local` (Lua-style)
```ghostlang
-- Plugin metadata
local plugin = {
    name = "hello-world",
    version = "1.0.0",
    description = "Example plugin"
}

-- Plugin state
local enabled = true

-- Your plugin functions
function setup()
    print("Plugin loaded: " .. plugin.name)
    return true
end

function teardown()
    print("Plugin unloaded")
    return true
end

-- Export plugin interface
return {
    setup = setup,
    teardown = teardown
}
```

Both styles work! Use whichever you prefer.

---

## Key Syntax Rules

### Variables
```ghostlang
-- C-style variable declaration (recommended for Grim)
var name = "Ghost"
var count = 42
var enabled = true

-- Lua-style local variable (also supported)
local name = "Ghost"
local count = 42
local enabled = true

-- Global variable (no keyword - avoid in plugins)
global_var = "visible everywhere"
```

### Functions
```ghostlang
-- ✅ CORRECT - Use 'function' keyword
function greet(name)
    print("Hello, " .. name)
end

-- ✅ CORRECT - Anonymous function
var callback = function(x)
    return x * 2
end

-- ❌ WRONG - 'fn' is not supported
fn greet(name) {  -- This will fail!
    print("Hello, " .. name)
}
```

### Function Bodies
```ghostlang
-- Style 1: Lua-style with 'end' (recommended)
function setup()
    print("Hello")
end

-- Style 2: C-style with braces (also works for control flow)
function setup() {
    print("Hello")
}  -- Still need to close with matching brace
```

### Conditionals
```ghostlang
-- Style 1: Lua style (recommended)
if score >= 90 then
    print("Grade: A")
elseif score >= 80 then
    print("Grade: B")
else
    print("Grade: C")
end

-- Style 2: C-like style (also works)
if (score >= 90) {
    print("Grade: A")
} elseif (score >= 80) {
    print("Grade: B")
} else {
    print("Grade: C")
}
```

### Loops
```ghostlang
-- While loop
var i = 0
while i < 10 do
    print(i)
    i = i + 1
end

-- For loop (numeric)
for i = 1, 10 do
    print(i)
end

-- For loop (iterator)
for key, value in pairs(table) do
    print(key, value)
end
```

### Tables (Objects/Arrays)
```ghostlang
-- Array-like table
var items = [1, 2, 3, 4, 5]
print(items[1])  -- Access first element (1-indexed!)

-- Object-like table
var config = {
    width = 80,
    height = 24,
    title = "Grim Editor"
}
print(config.width)
print(config["title"])
```

### Comments
```ghostlang
-- ✅ CORRECT - Use double dash for comments
-- This is a comment

// ❌ WRONG - C-style comments not supported
// This will cause syntax errors
```

---

## Your Engine Setup (This Part is Correct!)

Your Zig integration code looks good:

```zig
// ✅ This is correct
const engine_ptr = try self.allocator.create(ghostlang.Engine);
engine_ptr.* = try ghostlang.Engine.init(
    self.allocator,
    .{
        .memory_limit = memory_limit,
        .execution_timeout = self.config.execution_timeout_ms,
    },
);

// ✅ Loading scripts is correct
script_ptr.* = engine.loadScript(script_source) catch |err| {
    // Handle error
};
```

The issue was **only** in your `.gza` script syntax, not your Zig code.

---

## Migration Checklist

To fix your existing plugins:

- [ ] Replace all `const` with `var` (or `local`)
- [ ] Replace all `fn` with `function`
- [ ] Change `// comments` to `-- comments`
- [ ] Ensure function bodies use `end` (or properly matched `{}`)
- [ ] Ensure functions use `return` explicitly if needed
- [ ] Test with: `ghostlang plugins/examples/hello-world/init.gza`

---

## Quick Test

Create a simple test file:

```ghostlang
-- test.gza
var message = "Hello from Ghostlang!"

function test()
    print(message)
    return true
end

test()
```

Run it:
```bash
./zig-out/bin/ghostlang test.gza
```

If this works, your syntax is correct!

---

## Working Examples from Ghostlang Repo

Check these files in the Ghostlang repository for complete examples:

### 1. **C-Style Syntax Tests** (`tests/c_style_syntax_test.zig`)
Shows correct usage of:
- `var` keyword for variables
- `function` keyword for functions
- C-style operators (`&&`, `||`, `!`, `!=`)
- Mixed Lua/C-style syntax

### 2. **Plugin System Example** (`examples/plugin_system.gza`)
Complete auto-formatter plugin showing:
- Plugin metadata structure
- State management (using `local`)
- Event handlers
- Command registration
- Proper `init()` and `deinit()` functions

### 3. **Grim Configuration** (`examples/grim_config.gza`)
Shows editor configuration with:
- Key bindings (using `local`)
- Plugin configuration
- Buffer manipulation hooks
- Custom commands

### 4. **Basic Examples**
- `docs/examples/basic/hello-world.gza` - Uses `local` for variables
- `docs/examples/basic/control-flow.gza` - Shows both `{}` and `end` styles
- `test_conditionals.gza` - Shows C-style with `{}`

---

## Why This Happens

From the parser source (`src/root.zig:5523-5611`):

**Supported Keywords:**
- ✅ `local` - Local variable declaration (Lua-compatible)
- ✅ `var` - Variable declaration (C-style)
- ✅ `function` - Function declaration
- ✅ `if`, `while`, `for`, `return`

**NOT Supported:**
- ❌ `const` - Not recognized by parser
- ❌ `let` - Not recognized by parser
- ❌ `fn` - Not recognized by parser
- ❌ `export` - Not recognized by parser

When the parser encounters `const`, it tries to parse it as a variable name, which fails in `parsePrimary()` because it's not valid in that context. Result: `error.ParseError` at line 6779.

---

## Parser Keyword Recognition

The parser in `src/root.zig` recognizes these statement-level keywords (line 5529-5556):

```zig
if (std.mem.eql(u8, ident, "function")) {
    // Function declaration
} else if (std.mem.eql(u8, ident, "return")) {
    // Return statement
} else if (std.mem.eql(u8, ident, "local")) {
    // Local declaration (Lua-style)
} else if (std.mem.eql(u8, ident, "var")) {
    // Variable declaration (C-style)
} else if (std.mem.eql(u8, ident, "break")) {
    // Break statement
} else if (std.mem.eql(u8, ident, "continue")) {
    // Continue statement
} else if (std.mem.eql(u8, ident, "if")) {
    // If statement
} else if (std.mem.eql(u8, ident, "while")) {
    // While loop
} else if (std.mem.eql(u8, ident, "for")) {
    // For loop
} else if (std.mem.eql(u8, ident, "repeat")) {
    // Repeat-until loop
}
```

Notice: `const` and `fn` are **NOT** in this list!

---

## Summary

**What was wrong:** Using `const` (not supported) instead of `var` (supported)
**What you need:** Use `var` or `local` for variables, `function` for functions
**Your Zig code:** ✅ Perfect, no changes needed
**Next steps:** Update your `.gza` files with correct syntax

### Before (WRONG):
```ghostlang
const message = "Plugin loaded"  // ❌ const not supported

fn setup() {  // ❌ fn not supported
    print(message)
}
```

### After (CORRECT):
```ghostlang
var message = "Plugin loaded"  // ✅ var is supported

function setup()  // ✅ function is supported
    print(message)
end
```

Good luck with Grim! 🎉

---

**Ghostlang Repository:** https://github.com/ghostlang/ghostlang
**Documentation:** See `docs/` directory in the repo
**Examples:** See `examples/` directory for working code
**C-Style Tests:** See `tests/c_style_syntax_test.zig` for `var` keyword examples

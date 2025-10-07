# Ghostlang Syntax Fixes Applied

## Summary

Fixed all `.gza` files in the Grim repository to use correct Ghostlang syntax. The main issues were using unsupported keywords `const` and `fn` instead of the supported `local`/`var` and `function`.

## Root Cause

Ghostlang is a **Lua-compatible** scripting language, NOT JavaScript/Rust-compatible. The parser only recognizes these keywords:

### Supported Keywords
- ✅ `local` - Local variable declaration (Lua-style)
- ✅ `var` - Variable declaration (C-style, but Lua-compatible)
- ✅ `function` - Function declaration
- ✅ `if`, `while`, `for`, `return`, `break`, `continue`, `repeat`

### NOT Supported
- ❌ `const` - Not a keyword in Ghostlang
- ❌ `let` - Not a keyword
- ❌ `fn` - Not a keyword (use `function`)
- ❌ `export` - Not a keyword

## Files Fixed

### 1. `/data/projects/grim/example.gza`
**Before:**
```ghostlang
// Ghostlang example for testing LSP
const greeting = "Hello from Ghostlang!"
const version = "0.1.0"

fn greet(name: string) -> string {
    return greeting + " " + name
}
```

**After:**
```ghostlang
-- Ghostlang example for testing LSP
local greeting = "Hello from Ghostlang!"
local version = "0.1.0"

function greet(name)
    return greeting .. " " .. name
end
```

**Changes:**
- `const` → `local`
- `fn` → `function`
- `//` → `--` (comments)
- `+` → `..` (string concatenation)
- Removed type annotations (not supported)
- `{ }` → `end`

---

### 2. `/data/projects/grim/test.gza`
**Before:**
```ghostlang
// Simple Ghostlang test file
const message = "Hello from Ghostlang!"

fn main() {
    print(message)
}
```

**After:**
```ghostlang
-- Simple Ghostlang test file
local message = "Hello from Ghostlang!"

function main()
    print(message)
end
```

**Changes:**
- `const` → `local`
- `fn` → `function`
- `//` → `--`
- `{ }` → `end`

---

### 3. `/data/projects/grim/plugins/examples/status-line/init.gza`
**Before:**
```ghostlang
// Status Line Plugin
export fn setup() {
    print("Status Line plugin loaded!")
}

fn get_mode_component() {
    const mode = grim.mode.current()
}
```

**After:**
```ghostlang
-- Status Line Plugin
function setup()
    print("Status Line plugin loaded!")
end

function get_mode_component()
    local mode = grim.mode.current()
end
```

**Changes:**
- `export fn` → `function` (no export keyword)
- `const` → `local`
- `fn` → `function`
- `//` → `--`
- `{ }` → `end`
- `!=` → `~=` (not equal operator)
- Ternary operators converted to `and`/`or` expressions

---

### 4. `/data/projects/grim/examples/plugins/ai_commit.gza`
**Before:**
```ghostlang
// AI-powered Git Commit Plugin
if (!grim_zap_init()) {
    print("Warning")
}

function aiCommit() {
    const diff = grim_git_diff_staged();
    if (diff == "") {
        return;
    }
}
```

**After:**
```ghostlang
-- AI-powered Git Commit Plugin
if not grim_zap_init() then
    print("Warning")
end

function aiCommit()
    local diff = grim_git_diff_staged()
    if diff == "" then
        return
    end
end
```

**Changes:**
- `const` → `local`
- `!` → `not`
- `( )` around conditions removed (optional in Ghostlang)
- `{ }` → `then...end`
- `;` removed (optional)
- `//` → `--`

---

### 5. `/data/projects/grim/examples/host/config/keybindings.gza`
**Before:**
```ghostlang
// Grim editor keybinding configuration
var editorBindings = {
    // File operations
    "file": {
        "new": "Ctrl+N",
    }
}

for (var category in editorBindings) {
    var bindings = editorBindings[category];
}
```

**After:**
```ghostlang
-- Grim editor keybinding configuration
var editorBindings = {
    -- File operations
    file = {
        new = "Ctrl+N",
    }
}

for category, bindings in pairs(editorBindings) do
    -- ...
end
```

**Changes:**
- `//` → `--`
- `"key":` → `key =` (table syntax)
- `for...in` → `for...in pairs()...do...end` (Lua iterator style)
- `{ }` → `do...end`

---

### 6. `/data/projects/grim/examples/host/config/init.gza`
**Before:**
```ghostlang
// Grim editor initialization script
function setupEditor() {
    var config = createConfig();
    config.lineNumbers = true;
    return config;
}
```

**After:**
```ghostlang
-- Grim editor initialization script
function setupEditor()
    var config = createConfig()
    config.lineNumbers = true
    return config
end
```

**Changes:**
- `//` → `--`
- `{ }` → `end`
- `;` removed

---

## Already Correct

### `/data/projects/grim/plugins/examples/hello-world/init.gza`
✅ This file was already using correct syntax! No changes needed.

```ghostlang
-- Hello World Plugin
function setup()
    register_command("hello", "hello_handler", "Say hello")
    show_message("Hello World plugin loaded!")
    return true
end
```

---

### `/data/projects/grim/test_minimal.gza`
✅ This file was already using correct syntax! No changes needed.

---

## Syntax Cheat Sheet for Grim Developers

### Variables
```ghostlang
-- Local variables (preferred)
local name = "Ghost"
local count = 42

-- Variables (C-style, also works)
var name = "Ghost"
var count = 42

-- ❌ DON'T USE
const name = "Ghost"  -- NOT SUPPORTED
let count = 42        -- NOT SUPPORTED
```

### Functions
```ghostlang
-- ✅ Correct
function greet(name)
    print("Hello, " .. name)
end

-- ✅ Also correct
var greet = function(name)
    print("Hello, " .. name)
end

-- ❌ DON'T USE
fn greet(name) {      -- NOT SUPPORTED
    print("Hello, " + name)
}
```

### Comments
```ghostlang
-- ✅ Correct single-line comment
--[[ ✅ Correct multi-line comment
  Multiple lines here
]]

-- ❌ DON'T USE
// Wrong comment style
/* Wrong comment style */
```

### Conditionals
```ghostlang
-- ✅ Lua-style (preferred)
if score >= 90 then
    print("A")
elseif score >= 80 then
    print("B")
else
    print("C")
end

-- ✅ C-style (also works)
if (score >= 90) {
    print("A")
} elseif (score >= 80) {
    print("B")
} else {
    print("C")
}
```

### Loops
```ghostlang
-- ✅ While loop
while i < 10 do
    print(i)
    i = i + 1
end

-- ✅ For loop (numeric)
for i = 1, 10 do
    print(i)
end

-- ✅ For loop (iterator)
for key, value in pairs(table) do
    print(key, value)
end
```

### Tables
```ghostlang
-- ✅ Object-like table
var config = {
    width = 80,
    height = 24,
    theme = "dark"
}

-- ✅ Array-like table
var items = [1, 2, 3, 4, 5]

-- ❌ DON'T USE
var config = {
    "width": 80,        -- Wrong: uses "key": syntax
    "height": 24
}
```

### Operators
```ghostlang
-- String concatenation
local msg = "Hello" .. " " .. "World"  -- ✅ Use ..
local msg = "Hello" + " " + "World"    -- ❌ NOT SUPPORTED

-- Not equal
if x ~= y then  -- ✅ Use ~=
if x != y then  -- ❌ NOT SUPPORTED

-- Logical operators
if x and y then     -- ✅ Use and
if x && y then      -- ✅ Also works!

if x or y then      -- ✅ Use or
if x || y then      -- ✅ Also works!

if not x then       -- ✅ Use not
if !x then          -- ❌ NOT SUPPORTED in all contexts
```

---

## Testing Your Fixes

After making syntax changes, test with:

```bash
cd /data/projects/grim
zig build
./zig-out/bin/test_ghostlang_plugin
```

Or test individual files:
```bash
/data/projects/ghostlang/zig-out/bin/ghostlang your-file.gza
```

---

## Quick Reference

| Feature | ❌ Wrong (JS/Rust) | ✅ Right (Lua) |
|---------|-------------------|----------------|
| Variables | `const x = 5` | `local x = 5` or `var x = 5` |
| Functions | `fn foo() { }` | `function foo() end` |
| Comments | `// comment` | `-- comment` |
| String concat | `"a" + "b"` | `"a" .. "b"` |
| Not equal | `x != y` | `x ~= y` |
| Logical NOT | `!x` (inconsistent) | `not x` |
| Conditionals | `if (x) { }` | `if x then end` or `if (x) { }` |
| Loops | `for (x in y)` | `for x in pairs(y) do end` |

---

## For More Information

See the updated `GRIM_MAINTAINER.md` in the ghostlang repository:
`/data/projects/ghostlang/GRIM_MAINTAINER.md`

This document has complete examples and explains why these syntax rules exist.

---

**Status:** ✅ All syntax errors fixed! Your plugins should now load correctly.

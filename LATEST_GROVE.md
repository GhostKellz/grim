# Grove Updates for Grim Integration

**Date:** 2025-10-03
**Target Branch:** `feature/ghostlang-gza-adapter` (preparing for merge to `main`)

## Summary of Grove Changes

Grove has undergone significant expansion and is now ready for Grim's `feature/ghostlang-gza-adapter` branch to integrate. This document outlines what has changed and what Grim needs to update.

---

## 🎯 What's New in Grove

### 1. Grammar Expansion: 10 → 14 Languages

Grove now ships with **14 production-ready grammars** (up from 10):

**Previously Available (10):**
- JSON, Zig, Rust, Ghostlang, TypeScript, TSX, Bash, JavaScript, Python, Markdown

**Newly Added (4):**
- **CMake** – Build system configuration
- **TOML** – Cargo.toml, pyproject.toml, configs
- **YAML** – CI/CD, Kubernetes, Docker Compose
- **C** – C programming language

All grammars are compiled against **tree-sitter 0.25.10 (ABI 15)**.

### 2. Tree-sitter Runtime Upgrade

- **Old Version:** Pre-0.25.x (ABI 14)
- **New Version:** tree-sitter 0.25.10 (ABI 15)
- **Impact:** Better performance, modern features, ecosystem alignment

### 3. Editor Utilities for New Languages

All 4 new languages include full editor support:
- Document symbols extraction
- Folding ranges
- Tree-sitter query integration

---

## 🔧 What Grim Needs to Update

### 1. Update Grove Dependency

If Grim uses Grove as a dependency (submodule, path dependency, or package):

```bash
# If Grove is a git submodule
cd path/to/grim
git submodule update --remote vendor/grove  # or wherever Grove lives

# If Grove is a Zig package dependency
# Update build.zig.zon or equivalent to point to latest Grove commit
```

### 2. Language Registration Updates

Grim's language registry may need to register the 4 new languages:

**In your Grim language setup code:**

```zig
// Add these to your language registration
try registry.register("cmake", grove.Languages.cmake);
try registry.register("toml", grove.Languages.toml);
try registry.register("yaml", grove.Languages.yaml);
try registry.register("c", grove.Languages.c);
```

### 3. File Extension Mapping

Update Grim's file extension → language mapping:

```zig
// Example additions to your extension map
.put(".cmake", .cmake);
.put("CMakeLists.txt", .cmake);
.put(".toml", .toml);
.put(".yaml", .yaml);
.put(".yml", .yaml);
.put(".c", .c);
.put(".h", .c);
```

### 4. Syntax Highlighting Configuration

If Grim has custom highlight themes, you may want to verify:
- CMake function/macro highlighting
- TOML table/key highlighting
- YAML mapping highlighting
- C struct/function highlighting

Grove's default queries should work out-of-the-box, but custom themes may need tuning.

### 5. Testing Checklist

Before merging `feature/ghostlang-gza-adapter`:

- [ ] Grove builds successfully with Grim
- [ ] All 14 grammars parse correctly
- [ ] Ghostlang `.gza` and `.ghost` files still work
- [ ] TypeScript highlighting still works
- [ ] New grammars (CMake, TOML, YAML, C) parse sample files
- [ ] Editor features work: symbols, folding, navigation
- [ ] No performance regressions (<5 ms incremental latency goal)

---

## 📋 Verification Steps

### Step 1: Build Grim with Latest Grove

```bash
cd /path/to/grim
zig build
```

**Expected:** Clean build with no errors.

### Step 2: Parse Test Files

Create test files for each new grammar:

**test.cmake:**
```cmake
function(my_function ARG1)
  message(STATUS "Hello ${ARG1}")
endfunction()
```

**test.toml:**
```toml
[package]
name = "example"
version = "0.1.0"
```

**test.yaml:**
```yaml
services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
```

**test.c:**
```c
#include <stdio.h>

int main() {
    printf("Hello, World!\n");
    return 0;
}
```

Open these files in Grim and verify:
- Syntax highlighting works
- Document symbols appear (functions, tables, structs)
- Folding works (collapse function bodies, YAML blocks, etc.)

### Step 3: Benchmark Performance

Run Grim's incremental edit benchmarks with the new grammars to ensure you meet the <5 ms P50 goal.

```bash
# Example from Grove
zig build bench-latency
```

---

## 🚀 Optional Enhancements

While not required, consider these improvements:

### 1. Language-Specific Features

- **CMake:** Auto-completion for common functions (find_package, add_executable)
- **TOML:** Validate Cargo.toml schema
- **YAML:** Schema validation for docker-compose.yml, .github/workflows/*.yml
- **C:** Integration with `clangd` LSP for full language server features

### 2. Grammar Query Customization

If you want custom highlighting for specific use cases, you can override Grove's default queries:

```zig
// Example: Custom CMake query for better macro highlighting
const custom_cmake_query = try grove.Query.init(
    allocator,
    cmake_lang,
    \\(macro_def (macro_command (argument) @macro.name)) @macro.definition
);
```

---

## 📊 Current Grove Status

- ✅ **14 grammars** fully integrated
- ✅ **tree-sitter 0.25.10** (ABI 15) across all grammars
- ✅ **All tests passing** (`zig build test`)
- ✅ **Editor utilities** complete for all languages
- ✅ **Documentation** updated

---

## 🔗 Relevant Grove Files

Key files Grim may interact with:

| File | Purpose |
|------|---------|
| `src/languages.zig` | Language registry with all 14 grammars |
| `src/editor/all_languages.zig` | Unified editor utilities interface |
| `src/editor/{cmake,toml,yaml,c}_lang.zig` | New language-specific utilities |
| `vendor/grammars/{cmake,toml,yaml,c}/` | Grammar source files |
| `build.zig` | Build configuration (updated with new grammars) |

---

## ❓ Questions or Issues?

If you encounter any issues integrating the latest Grove:

1. Check that all Grove tests pass: `zig build test`
2. Verify tree-sitter version compatibility (0.25.10)
3. Ensure Grim's Zig version matches Grove's requirement (0.16.0-dev)

---

## 🎉 Benefits of This Update

After updating to the latest Grove, Grim will gain:

- **Broader Language Support:** 14 languages covering most development workflows
- **Better Config File Editing:** TOML, YAML, CMake all fully supported
- **C Language Support:** Essential for systems programming and understanding vendor code
- **Future-Proof Runtime:** tree-sitter 0.25.10 aligns with ecosystem standards
- **Improved Performance:** ABI 15 includes optimizations over ABI 14

---

## 🏁 Ready to Merge?

Once you've verified:
- ✅ All 14 grammars work in Grim
- ✅ Ghostlang `.gza` adapter still functions
- ✅ No performance regressions
- ✅ Tests pass

Your `feature/ghostlang-gza-adapter` branch is ready to merge to `main`!

---

**Grove Version:** Latest (2025-10-03)
**Grammars:** 14
**Tree-sitter:** 0.25.10 (ABI 15)
**Zig:** 0.16.0-dev

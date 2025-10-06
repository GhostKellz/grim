# Visual Theme Testing Guide

Quick guide to verify theme colors are rendering correctly.

## Test Commands

```bash
# Build first
zig build

# Test 1: Default theme (ghost-hacker-blue)
./zig-out/bin/grim test_theme.zig

# Test 2: Tokyo Night Moon
./zig-out/bin/grim --theme tokyonight-moon test_theme.zig

# Test 3: Invalid theme (should fallback to default)
./zig-out/bin/grim --theme nonexistent test_theme.zig
```

## Expected Colors (Ghost Hacker Blue)

When you open `test_theme.zig`, verify these colors:

### Comments
- **Regular comments** (`//`): **Hacker Blue** (#57c7ff) - bright cyan
- Should be clearly visible and easy to read

### Functions
- **Function names** (`testThemeColors`, `calculateValue`): **Mint Green** (#8aff80)
- This is your signature color - should pop!

### Keywords
- **Keywords** (`const`, `fn`, `pub`, `if`, `return`): **Cyan** (#89ddff)
- Bright and prominent

### Strings
- **String literals** (`"Hello, Ghost Hacker Blue!"`): **Green** (#c3e88d)
- Tokyo Night green

### Numbers
- **Numbers** (`42`, `3.14159`): **Yellow/Orange** (#ffc777)
- Warm tone, stands out

### Types
- **Types** (`u32`, `f64`, `std.ArrayList`): **Blue** (#65bcff)
- Distinct from keywords

### Operators
- **Operators** (`+`, `-`, `*`, `/`, `>`): **Blue Moon** (#c0caf5)
- Subtle but clear

## Visual Checklist

Open the editor and verify:

- [ ] **Foreground text**: Default text is readable
- [ ] **Mint functions**: Function names are bright mint green
- [ ] **Hacker blue comments**: Comments are cyan/blue and pleasant
- [ ] **Cursor line**: Background has aquamarine tint (#7fffd4)
- [ ] **Selection**: Selected text has icy aqua background (#a0ffe8)
- [ ] **Status bar**: Bottom bar is visible with moon blue text
- [ ] **Line numbers**: Subtle comment color on left side

## Test Different Themes

### Tokyo Night Moon
```bash
./zig-out/bin/grim --theme tokyonight-moon test_theme.zig
```

**Differences from ghost-hacker-blue:**
- Functions: Standard blue instead of mint
- Comments: Standard comment color instead of hacker blue
- Overall: Pure Tokyo Night aesthetic

### Theme Not Found
```bash
./zig-out/bin/grim --theme nonexistent test_theme.zig
```

**Expected behavior:**
- Warning message in terminal: "Theme 'nonexistent' not found"
- Falls back to ghost-hacker-blue
- Editor still works perfectly

## Quick Screenshot Test

If you want to capture screenshots for documentation:

```bash
# Ghost Hacker Blue (default)
./zig-out/bin/grim test_theme.zig
# Take screenshot

# Tokyo Night Moon
./zig-out/bin/grim --theme tokyonight-moon test_theme.zig
# Take screenshot
```

## Troubleshooting

### Colors look wrong?

1. **Check terminal support**: Ensure your terminal supports 256 colors
   ```bash
   echo $TERM  # Should be xterm-256color or similar
   ```

2. **Check theme file**: Verify theme exists
   ```bash
   ls themes/ghost-hacker-blue.toml
   ls themes/tokyonight-moon.toml
   ```

3. **Check logs**: Run with log output
   ```bash
   RUST_LOG=info ./zig-out/bin/grim test_theme.zig
   ```

### Theme not loading?

1. **Check working directory**: Theme paths are relative
   ```bash
   pwd  # Should be in /data/projects/grim
   ```

2. **Use absolute path**: If relative doesn't work
   ```bash
   ./zig-out/bin/grim --theme /data/projects/grim/themes/tokyonight-moon
   ```

3. **Check file permissions**:
   ```bash
   ls -la themes/*.toml
   ```

## Success Criteria

Theme system is working if:

✅ Default theme loads automatically
✅ `--theme` flag changes colors
✅ Function names are mint green (ghost-hacker-blue)
✅ Comments are hacker blue (ghost-hacker-blue)
✅ Invalid theme falls back gracefully
✅ No crashes or errors

## Next Steps

After visual verification:

1. **Create more themes**: Tokyo Night variants (storm, night, day)
2. **Add theme hot-reload**: Watch theme files for changes
3. **Theme picker UI**: Fuzzy finder for themes
4. **User config**: `~/.config/grim/theme.toml` for default

---

**Happy theme testing!** 🎨

If colors look good, the theme system is production-ready!

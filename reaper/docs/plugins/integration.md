# Integration Plugins

Third-party tool integrations (1 plugin - 329 lines).

---

## tmux.gza (329 lines)

**Seamless tmux integration** - vim-tmux-navigator-style pane navigation + tmux features.

### Why Tmux Integration Matters

Most developers use **tmux + editor** workflow:
```
┌────────────────────────────────────┐
│ Tmux Session                       │
├────────────┬───────────────────────┤
│            │                       │
│   Grim     │   Shell / Tests       │
│   Editor   │   Logs / Servers      │
│            │                       │
└────────────┴───────────────────────┘
```

**Without integration:**
- `Ctrl+h/j/k/l` only works in editor
- Need `Ctrl+b` prefix for tmux
- Context switching = friction

**With tmux.gza:**
- `Ctrl+h/j/k/l` works **everywhere**
- No prefix needed
- Seamless navigation across editor + shell

---

## Features

### 1. 🔀 Seamless Pane Navigation

Navigate between Grim splits and tmux panes **with the same keys:**

```
┌─────────────────────────────────────┐
│                                     │
│  Ctrl+h ←   Grim    → Ctrl+l       │
│              ↓ Ctrl+j               │
├─────────────────────────────────────┤
│              ↑ Ctrl+k               │
│         Tmux Pane                   │
└─────────────────────────────────────┘
```

**Behavior:**
- If at **edge of Grim** → Navigate to tmux pane
- If **inside Grim** → Navigate between Grim splits
- No prefix, no friction

### 2. 📡 Auto-Detection

Automatically detects if you're in tmux:
```ghostlang
-- Checks $TMUX environment variable
-- Disables tmux features if not in tmux
-- Zero overhead when not in tmux session
```

### 3. 📊 Statusline Integration

Shows tmux status in your statusline:
```
[main] ~/projects/grim/  [session1:0.1] 󰊢 2:45 PM
                         └─────┬──────┘
                           tmux status
```

### 4. 🎛️ Tmux Control

Control tmux from within Grim:

| Command | Action |
|---------|--------|
| `:TmuxSplit` | Split pane |
| `:TmuxKill` | Kill pane |
| `:TmuxZoom` | Toggle zoom |
| `:TmuxSend` | Send keys to pane |
| `:TmuxCommand` | Send command (with Enter) |
| `:TmuxCopyMode` | Enter copy mode |
| `:TmuxPaste` | Paste from tmux buffer |

### 5. 📝 Send Selection to Pane

**REPL workflow:**

```ghostlang
-- 1. Write code in Grim
function fibonacci(n)
    if n <= 1 then return n end
    return fibonacci(n-1) + fibonacci(n-2)
end

-- 2. Select in visual mode (V)
-- 3. Run: :TmuxSend
-- 4. Code executes in adjacent tmux pane (REPL/shell)
```

---

## Setup

### Prerequisites

**tmux.conf** must have these bindings:

```bash
# ~/.tmux.conf
# Smart pane switching with awareness of Vim splits
is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"

bind-key -n C-h if-shell "$is_vim" "send-keys C-h"  "select-pane -L"
bind-key -n C-j if-shell "$is_vim" "send-keys C-j"  "select-pane -D"
bind-key -n C-k if-shell "$is_vim" "send-keys C-k"  "select-pane -U"
bind-key -n C-l if-shell "$is_vim" "send-keys C-l"  "select-pane -R"
```

**Why needed:** Tmux must know when to pass through `Ctrl+hjkl` to Grim.

### Grim Keybindings

Add to your config:

```ghostlang
local tmux = require("tmux")

-- Seamless navigation (Ctrl+hjkl)
vim.keymap.set("n", "<C-h>", tmux.navigate_left,  { silent = true })
vim.keymap.set("n", "<C-j>", tmux.navigate_down,  { silent = true })
vim.keymap.set("n", "<C-k>", tmux.navigate_up,    { silent = true })
vim.keymap.set("n", "<C-l>", tmux.navigate_right, { silent = true })

-- Send keys (visual mode)
vim.keymap.set("v", "<leader>ts", ":TmuxSend<CR>", { desc = "Send to tmux" })
```

---

## API Reference

### Auto-Detection

```ghostlang
local tmux = require("tmux")

-- Check if in tmux
if tmux.in_tmux() then
    print("Running in tmux session")
end

-- Get tmux info
local info = tmux.get_info()
-- Returns:
-- {
--   session = "session1",
--   window = 0,
--   pane = 1,
--   pane_count = 2,
-- }
```

### Navigation

```ghostlang
-- Navigate to panes
tmux.navigate_left()
tmux.navigate_right()
tmux.navigate_up()
tmux.navigate_down()

-- Navigate to specific pane
tmux.select_pane(1)  -- Select pane 1
```

### Pane Management

```ghostlang
-- Split panes
tmux.split_horizontal()  -- Split horizontally
tmux.split_vertical()    -- Split vertically

-- Kill panes
tmux.kill_pane()         -- Kill current pane
tmux.kill_pane(2)        -- Kill pane 2

-- Zoom
tmux.toggle_zoom()       -- Toggle zoom current pane
```

### Send Keys/Commands

```ghostlang
-- Send raw keys
tmux.send_keys("echo hello", false)  -- Don't add Enter

-- Send command (with Enter)
tmux.send_command("ls -la")  -- Executes immediately

-- Send to specific pane
tmux.send_to_pane(2, "echo 'hello from pane 2'")
```

### Send Selection (REPL Workflow)

```ghostlang
-- In visual mode
tmux.send_selection()  -- Send selected text to adjacent pane

-- Send paragraph under cursor
tmux.send_paragraph()  -- Sends current paragraph

-- Send line
tmux.send_line()  -- Sends current line
```

### Copy Mode

```ghostlang
-- Enter copy mode
tmux.enter_copy_mode()

-- Paste from tmux buffer
tmux.paste()

-- Get tmux buffer contents
local buffer = tmux.get_buffer()
print(buffer)
```

### Statusline Integration

```ghostlang
-- Get statusline info
local info = tmux.get_statusline_info()
-- Returns:
-- {
--   format = "session1:0.1",     -- Display format
--   session = "session1",
--   window_index = 0,
--   pane_index = 1,
--   active = true,
-- }

-- Use in statusline.gza
function build_statusline()
    local tmux_info = require("tmux").get_statusline_info()
    if tmux_info then
        return " [" .. tmux_info.format .. "] "
    end
    return ""
end
```

---

## Configuration

```ghostlang
require("tmux").setup({
    -- No options needed - auto-detects everything!
    -- But you can customize:
    statusline_format = "{session}:{window}.{pane}",  -- Custom format
})
```

---

## Workflows

### 1. REPL Development (Python/Ghostlang/Ruby)

**Setup:**
```bash
# In tmux
Ctrl+b %  # Split pane vertically
# Left: Grim editor
# Right: Python REPL
```

**Workflow:**
```ghostlang
-- 1. Write code in Grim
def factorial(n):
    return 1 if n <= 1 else n * factorial(n-1)

-- 2. Select function (V in visual mode)
-- 3. :TmuxSend
-- 4. Function runs in Python REPL
-- 5. Test: factorial(5)  → 120
```

### 2. TDD Workflow (Zig/Rust/Go)

**Setup:**
```bash
Ctrl+b "  # Split horizontally
# Top: Grim editor
# Bottom: Test runner (zig test --watch)
```

**Workflow:**
```ghostlang
-- 1. Edit test file
-- 2. Save (:w)
-- 3. Tests auto-run in bottom pane
-- 4. Navigate with Ctrl+j to see results
-- 5. Ctrl+k back to editor
```

### 3. Server Development

**Setup:**
```bash
# Quadrant layout
Ctrl+b %  # Vertical split
Ctrl+b "  # Top-left: horizontal split
Ctrl+b "  # Top-right: horizontal split

# Result:
┌──────────┬──────────┐
│  Grim    │  Logs    │
│  Editor  │          │
├──────────┼──────────┤
│  Shell   │  Server  │
│          │  Running │
└──────────┴──────────┘
```

**Workflow:**
- Edit code in Grim
- Ctrl+l → Check logs
- Ctrl+j → Run shell commands
- Ctrl+l → Check server output
- Ctrl+k → Back to logs
- Ctrl+h → Back to editor

### 4. Git Workflow

```ghostlang
-- Send git commands to shell pane
:TmuxCommand git status
:TmuxCommand git diff
:TmuxCommand git add .
:TmuxCommand git commit -m "feat: add feature"

-- Or navigate there with Ctrl+j
```

---

## Comparison with Alternatives

| Feature | **tmux.gza** | vim-tmux-navigator | tmux.nvim |
|---------|--------------|--------------------|--------------|
| Seamless nav | ✅ Ctrl+hjkl | ✅ Same | ✅ Same |
| Send keys | ✅ Yes | ❌ No | ✅ Yes |
| Statusline | ✅ Yes | ❌ No | ⚠️ Basic |
| Auto-detect | ✅ Yes | ✅ Yes | ✅ Yes |
| Pane control | ✅ Yes | ❌ No | ✅ Yes |
| Ghostlang | ✅ Native | ❌ Vimscript | ❌ Lua |

---

## Troubleshooting

### Navigation not working

**Check tmux.conf:**
```bash
# Verify bindings exist
tmux list-keys | grep -E "C-(h|j|k|l)"

# Reload config
tmux source-file ~/.tmux.conf
```

**Check Grim keybindings:**
```ghostlang
:lua print(vim.inspect(vim.api.nvim_get_keymap('n')))
-- Look for <C-h>, <C-j>, <C-k>, <C-l>
```

### "Not in tmux session"

```ghostlang
-- Check detection
:lua print(require("tmux").in_tmux())  -- false?

-- Check $TMUX variable
:!echo $TMUX  -- Should print tmux socket path
```

If empty, you're **not in tmux**. Start tmux first:
```bash
tmux new -s work
```

### Send keys not working

**Check pane count:**
```ghostlang
:lua print(require("tmux").get_info().pane_count)
-- Must be > 1 to send to adjacent pane
```

**Try explicit pane:**
```ghostlang
:lua require("tmux").send_to_pane(1, "echo test")
```

### Statusline not showing tmux info

```ghostlang
-- Check if enabled
:lua vim.inspect(require("tmux").get_statusline_info())

-- Rebuild statusline
:lua require("statusline").update()
```

---

## Advanced Usage

### Custom Tmux Commands

```ghostlang
-- Run any tmux command
local tmux = require("tmux")

-- Rename window
tmux.run_command("rename-window 'coding'")

-- Create new window
tmux.run_command("new-window -n 'tests'")

-- Swap panes
tmux.run_command("swap-pane -D")
```

### Integration with Other Plugins

#### With terminal.gza

```ghostlang
-- Open Grim's terminal in tmux pane
local tmux = require("tmux")
local term = require("terminal")

-- Split tmux pane, open Grim terminal there
if tmux.in_tmux() then
    tmux.split_horizontal()
    -- Grim terminal now controls that pane
end
```

#### With git-signs.gza

```ghostlang
-- Send git commands from git-signs to tmux
local git_signs = require("git-signs")
local tmux = require("tmux")

-- Stage hunk, show diff in tmux
git_signs.stage_hunk()
if tmux.in_tmux() then
    tmux.send_command("git diff --staged")
end
```

---

## Future Enhancements

### Planned Features (v0.2.0)

- [ ] **Tmux session management**
  - Create/attach/detach from Grim
  - Session picker UI
- [ ] **Pane layouts**
  - Predefined layouts (dev, test, debug)
  - Save/restore layouts
- [ ] **Copy mode integration**
  - Yank from tmux buffer to Grim register
  - Visual selection in tmux
- [ ] **Window management**
  - Create/rename/kill windows from Grim
  - Window picker UI

---

**Last Updated:** 2025-10-12
**Status:** Sprint 4 Complete ✅
**Related:** vim-tmux-navigator, tmux.nvim

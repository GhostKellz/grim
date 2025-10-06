# Grim Editor - Immediate Next Steps

**Current Status:** ✅ Builds successfully, runs but needs core features completed
**Goal:** Get to usable v0.1 MVP while Phantom.grim is being built
**Strategy:** Fix critical path issues, integrate Ghostls, stabilize core

---

## 🎯 PRIORITY 1: Fix Critical Issues (This Week)

### 1. Fix Syntax Highlighting Error ⚠️ BLOCKING
**Issue:** `ParserNotInitialized` error on startup

**Location:** `syntax/grove.zig` or `ui-tui/simple_tui.zig`

**Fix:**
```zig
// In syntax/grove.zig - ensure parser initializes
pub fn createParser(allocator: Allocator, language: Language) !*GroveParser {
    const parser = try allocator.create(GroveParser);
    parser.* = .{
        .allocator = allocator,
        .language = language,
        .tree = null,  // ← This is fine
        .source = "",
    };

    // ADD: Actually initialize tree-sitter parser
    // This is missing!
    try parser.initializeTreeSitter();  // ← Need to implement

    return parser;
}
```

**Action:**
- [ ] Check if Grove tree-sitter is actually being initialized
- [ ] Add fallback: if parser fails, use simple keyword highlighter
- [ ] Test with actual .zig/.gza files

---

### 2. Complete LSP Client Methods 🔧

**What's Done:** ✅
- `lsp/client.zig` has initialize + diagnostics
- Message framing works
- JSON-RPC parsing works

**What's Missing:** ❌
```zig
// Need to add these methods to lsp/client.zig:

pub fn sendDidOpen(self: *Client, uri: []const u8, languageId: []const u8, text: []const u8) Error!void {
    // Notify server file opened
}

pub fn sendDidChange(self: *Client, uri: []const u8, version: u32, changes: []const TextEdit) Error!void {
    // Send incremental edits
}

pub fn requestCompletion(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
    // Request code completion
}

pub fn requestHover(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
    // Request hover info
}

pub fn requestDefinition(self: *Client, uri: []const u8, line: u32, character: u32) Error!u32 {
    // Goto definition
}
```

**Reference:** Already documented in `archive/ghostls/integrations/grim/README.md`

**Action:**
- [ ] Copy method implementations from ghostls integration guide
- [ ] Wire to editor commands (`:LspHover`, `:LspGotoDefinition`)
- [ ] Test with ghostls server

---

### 3. LSP Server Manager (NEW FILE NEEDED) 🆕

**Create:** `lsp/server_manager.zig`

**Purpose:** Spawn and manage LSP servers (ghostls, zls, rust-analyzer)

```zig
// lsp/server_manager.zig
const std = @import("std");
const Client = @import("client.zig").Client;

pub const ServerManager = struct {
    allocator: std.mem.Allocator,
    servers: std.StringHashMap(*ServerProcess),

    pub const ServerProcess = struct {
        process: std.process.Child,
        client: Client,
        name: []const u8,
        active: bool,
    };

    pub fn spawn(self: *ServerManager, name: []const u8, cmd: []const []const u8) !*ServerProcess {
        var process = std.process.Child.init(cmd, self.allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Inherit;

        try process.spawn();

        // Create transport for stdio
        const transport = createStdioTransport(&process);
        const client = Client.init(self.allocator, transport);

        const server = try self.allocator.create(ServerProcess);
        server.* = .{
            .process = process,
            .client = client,
            .name = try self.allocator.dupe(u8, name),
            .active = true,
        };

        try self.servers.put(name, server);

        // Send initialize request
        _ = try server.client.sendInitialize("file:///current/workspace");

        return server;
    }

    pub fn shutdown(self: *ServerManager, name: []const u8) !void {
        if (self.servers.get(name)) |server| {
            try server.client.sendShutdown();
            _ = try server.process.wait();
            server.active = false;
        }
    }
};
```

**Action:**
- [ ] Create `lsp/server_manager.zig`
- [ ] Wire to editor startup
- [ ] Auto-spawn ghostls for .gza files
- [ ] Auto-spawn zls for .zig files

---

## 🚀 PRIORITY 2: Ghostls Integration (Next 3 Days)

### Step 1: Test Ghostls Locally

```bash
# Build ghostls (from archive/ghostls or fetch latest)
cd archive/ghostls
zig build -Drelease-safe

# Test it works
./zig-out/bin/ghostls --version

# Test LSP protocol
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ./zig-out/bin/ghostls
```

### Step 2: Integrate into Grim

**Config file:** `~/.config/grim/init.gza` (create if missing)

```ghostlang
-- Auto-load Ghostls for .gza files
local lsp = require("grim.lsp")

lsp.setup("ghostls", {
    cmd = { "ghostls", "--stdio" },  -- Or full path
    filetypes = { "ghostlang", "gza", "ghost" },
    root_patterns = { ".git", "grim.toml" },
})
```

**Action:**
- [ ] Ensure ghostls binary is in PATH
- [ ] Test spawning from Grim
- [ ] Open a .gza file, verify LSP activates
- [ ] Test hover (`:LspHover` on a function)

### Step 3: Wire LSP UI Features

**Commands to implement:**
```zig
// In ui-tui/editor.zig or new file ui-tui/lsp_commands.zig

pub fn lspHover(editor: *Editor) !void {
    const pos = editor.getCursorPosition();
    const uri = try editor.getCurrentFileURI();

    const request_id = try editor.lsp_client.requestHover(uri, pos.line, pos.character);

    // Store callback for when response comes
    try editor.lsp_pending.put(request_id, .{ .action = .show_hover });
}

pub fn lspGotoDefinition(editor: *Editor) !void {
    // Similar pattern
}

pub fn lspCompletion(editor: *Editor) !void {
    // Trigger on Ctrl-Space or after typing '.'
}
```

**Action:**
- [ ] Wire `:LspHover` command
- [ ] Wire `gd` (goto definition) keybind
- [ ] Wire `K` (hover docs) keybind
- [ ] Display diagnostics in status line

---

## 🔧 PRIORITY 3: Core Editor Polish (Ongoing)

### Fix Syntax Highlighting Fallback

**If Grove fails, use simple regex highlighter:**

```zig
// syntax/simple_highlighter.zig
pub const SimpleHighlighter = struct {
    pub fn highlight(text: []const u8, language: Language) ![]HighlightRange {
        // Use basic regex patterns for keywords
        const keywords = switch (language) {
            .zig => &[_][]const u8{"const", "var", "fn", "pub", "if", "else", "return"},
            .ghostlang => &[_][]const u8{"function", "local", "if", "end", "return"},
            else => &[_][]const u8{},
        };

        // Scan and mark keywords
        // Better than crashing!
        return highlights;
    }
};
```

### Improve Error Handling

```zig
// ui-tui/simple_tui.zig - Fix highlight refresh
fn refreshHighlights(self: *SimpleTUI) void {
    // OLD (crashes on error):
    // const highlights = try syntax.highlight(...);

    // NEW (graceful fallback):
    const highlights = syntax.highlight(self.content, self.language) catch |err| {
        if (!self.highlight_error_logged) {
            std.log.warn("Syntax highlighting failed: {}", .{err});
            self.highlight_error_logged = true;
        }
        return;  // Just don't highlight, don't crash!
    };

    self.highlight_cache = highlights;
}
```

**Action:**
- [ ] Add try/catch to all syntax operations
- [ ] Show warnings in status line, not errors
- [ ] Gracefully degrade to no highlighting

---

## 📋 Quick Wins (Can Do Now)

### 1. Add More Vim Motions
Current motions in `ui-tui/vim_commands.zig` are basic. Add:

```zig
// Word motions
pub fn wordForward(editor: *Editor) !void { ... }  // w
pub fn wordBackward(editor: *Editor) !void { ... } // b
pub fn wordEnd(editor: *Editor) !void { ... }      // e

// Line motions
pub fn lineStart(editor: *Editor) !void { ... }    // 0
pub fn lineEnd(editor: *Editor) !void { ... }      // $
pub fn firstNonBlank(editor: *Editor) !void { ... } // ^

// File motions
pub fn fileTop(editor: *Editor) !void { ... }      // gg
pub fn fileBottom(editor: *Editor) !void { ... }   // G
```

### 2. Better Status Line
Show more info:

```zig
// Current: "NORMAL | 1,1 | 0 bytes | unknown"
// Better:  "NORMAL | file.zig | 1:1 | 42 lines | zig | [LSP] zls ✓"

fn renderStatusLine(self: *SimpleTUI) []const u8 {
    return std.fmt.bufPrint(
        &status_buf,
        "{s} | {s} | {d}:{d} | {d} lines | {s} | {s}",
        .{
            mode_str,
            filename,
            cursor_line,
            cursor_col,
            total_lines,
            language,
            lsp_status,
        }
    );
}
```

### 3. File Operations
Currently loads args[1], add:

```zig
// Commands:
:e <file>    - Open file
:w           - Save current
:wq          - Save and quit
:q!          - Quit without saving
```

---

## 🧪 Testing Strategy

### Manual Tests (Do These First)

```bash
# 1. Basic editing
grim test.zig
# Type some text, move around, save, quit

# 2. Syntax highlighting
grim src/main.zig
# Should see keywords colored (if fixed)

# 3. LSP with ghostls
grim init.gza
# Hover over a function, should see docs

# 4. Multiple files
grim file1.zig file2.zig
# Switch buffers
```

### Automated Tests (Add Later)

```zig
// test/editor_test.zig
test "basic cursor movement" {
    var editor = try Editor.init(testing.allocator);
    defer editor.deinit();

    try editor.rope.insert(0, "hello\nworld");

    try editor.moveCursorDown();
    try testing.expectEqual(@as(usize, 1), editor.cursor_line);
}
```

---

## 📅 This Week's Plan

### Monday-Tuesday: Fix Critical Issues
- [x] Assess current state (DONE)
- [ ] Fix syntax highlighting crash
- [ ] Add LSP client methods
- [ ] Create server_manager.zig

### Wednesday-Thursday: Ghostls Integration
- [ ] Test ghostls standalone
- [ ] Wire spawn/lifecycle
- [ ] Test hover + goto-def
- [ ] Display diagnostics

### Friday: Polish & Test
- [ ] Add more Vim motions
- [ ] Better error handling
- [ ] Status line improvements
- [ ] Manual testing suite

---

## 🎯 Success Criteria for v0.1

**Grim is usable when:**

1. ✅ Opens and edits files without crashing
2. ✅ Basic Vim motions work (hjkl, w/b, gg/G, i/a/o)
3. ✅ Saves files correctly
4. ✅ Syntax highlighting works (even if basic)
5. ✅ LSP hover shows docs
6. ✅ LSP goto-definition jumps correctly
7. ✅ Can edit .gza config files
8. ✅ Runs on Linux

**Then we can:**
- Release v0.1-alpha
- Get early adopters
- Iterate on feedback
- Build Phantom.grim on top

---

## 💡 Meanwhile: Phantom.grim Development

**You focus on Phantom.grim, parallel track:**

1. **Create repo structure**
   ```bash
   mkdir -p phantom.grim/{core,runtime,plugins,themes}
   ```

2. **Start with plugin loader** (Zig)
   - Registry client
   - Download mechanism
   - Dependency resolver

3. **Port essential plugins** (.gza)
   - File tree
   - Fuzzy finder
   - Git signs

4. **Build grim-tutor**
   - Lesson system
   - Progress tracking

**I'll focus on Grim core**, you build Phantom.grim. When Grim v0.1 is solid, we merge Phantom.grim as the default distro!

---

## 🔥 Key Insight

**Grim doesn't need to be perfect for v0.1.**

It needs to be:
- ✅ Stable (doesn't crash)
- ✅ Fast (startup <100ms)
- ✅ Usable (basic editing + LSP)
- ✅ Extensible (loads .gza configs)

**Everything else comes in v0.2+:**
- Fuzzy finder
- Git integration
- DAP debugging
- Multi-cursor
- Advanced motions

**Ship fast, iterate on feedback!** 🚀

---

**Next Action:** Fix syntax highlighting crash in `syntax/grove.zig` or add fallback highlighter.

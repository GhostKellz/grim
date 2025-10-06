# Grim Integration TODO
**Integrating zap into Grim text editor**

**Status:** Grim already has placeholder `core/zap.zig` and `ghostlang_bridge.zig` FFI infrastructure!
Just needs to wire up the real zap dependency.

---

## Phase 1: Core Zap Integration (Priority: CRITICAL) ⚡

### 1.1 Add Zap Dependency ✅ READY
**File:** `/data/projects/grim/build.zig.zon`

```zig
.dependencies = .{
    // ... existing deps (zsync, phantom, gcode, flare, grove, ghostlang)
    .zap = .{
        .url = "https://github.com/ghostkellz/zap/archive/refs/heads/main.tar.gz",
        // Run: zig fetch --save https://github.com/ghostkellz/zap/archive/refs/heads/main.tar.gz
    },
},
```

**File:** `/data/projects/grim/build.zig`

Find the section where `core_mod` is defined (around line 53), update imports:
```zig
const core_mod = b.createModule(.{
    .root_source_file = b.path("core/mod.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "gcode", .module = gcode.module("gcode") },
        .{ .name = "zap", .module = b.dependency("zap", .{}).module("zap") },  // ADD THIS
    },
});
```

---

### 1.2 Replace Placeholder Zap with Real Implementation ✅ READY
**File:** `/data/projects/grim/core/zap.zig`

The existing file has stubs. Replace it with:

```zig
const std = @import("std");
const zap_lib = @import("zap"); // Import real zap library

/// Re-export zap's ZapContext for Grim's use
pub const ZapContext = zap_lib.ZapContext;
pub const OllamaConfig = zap_lib.ollama.OllamaConfig;

/// Grim-specific wrapper around zap
pub const ZapIntegration = struct {
    zap_ctx: ZapContext,
    allocator: std.mem.Allocator,
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) !ZapIntegration {
        return ZapIntegration{
            .allocator = allocator,
            .zap_ctx = try ZapContext.init(allocator),
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: OllamaConfig) !ZapIntegration {
        return ZapIntegration{
            .allocator = allocator,
            .zap_ctx = try ZapContext.initWithConfig(allocator, config),
        };
    }

    pub fn deinit(self: *ZapIntegration) void {
        self.zap_ctx.deinit();
    }

    pub fn generateCommitMessage(self: *ZapIntegration, diff: []const u8) ![]const u8 {
        return try self.zap_ctx.generateCommit(diff);
    }

    pub fn explainChanges(self: *ZapIntegration, commit_range: []const u8) ![]const u8 {
        return try self.zap_ctx.explainChanges(commit_range);
    }

    pub fn suggestMergeResolution(self: *ZapIntegration, conflict: []const u8) ![]const u8 {
        return try self.zap_ctx.suggestMergeResolution(conflict);
    }

    pub fn isAvailable(self: *ZapIntegration) bool {
        return self.zap_ctx.isAvailable() catch false;
    }
};
```

---

### 1.3 Add Zap FFI to Ghostlang Bridge ✅ READY
**File:** `/data/projects/grim/src/ghostlang_bridge.zig`

Add zap fields to the bridge struct (around line 12):

```zig
pub const GhostlangBridge = struct {
    allocator: std.mem.Allocator,
    fuzzy: ?*core.FuzzyFinder,
    git: ?*core.Git,
    harpoon: ?*core.Harpoon,
    features: ?*syntax.Features,
    zap: ?*core.ZapIntegration,  // ADD THIS

    pub fn init(allocator: std.mem.Allocator) GhostlangBridge {
        return .{
            .allocator = allocator,
            .fuzzy = null,
            .git = null,
            .harpoon = null,
            .features = null,
            .zap = null,  // ADD THIS
        };
    }

    pub fn deinit(self: *GhostlangBridge) void {
        // ... existing cleanup
        if (self.zap) |z| {
            z.deinit();
            self.allocator.destroy(z);
        }
    }
```

Add zap FFI exports (append to end of file):

```zig
    // ========================================================================
    // ZAP AI API
    // ========================================================================

    /// Initialize zap AI integration
    pub export fn grim_zap_init(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.zap != null) return true;

        const zap = bridge.allocator.create(core.ZapIntegration) catch return false;
        zap.* = core.ZapIntegration.init(bridge.allocator) catch {
            bridge.allocator.destroy(zap);
            return false;
        };
        bridge.zap = zap;
        return true;
    }

    /// Check if Ollama is available
    pub export fn grim_zap_available(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.zap == null) return false;
        return bridge.zap.?.isAvailable();
    }

    /// Generate commit message from diff
    pub export fn grim_zap_commit(
        bridge: *GhostlangBridge,
        diff: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const diff_slice = std.mem.span(diff);
        const message = bridge.zap.?.generateCommitMessage(diff_slice) catch return "";

        // Add null terminator
        const result = bridge.allocator.allocSentinel(u8, message.len, 0) catch {
            bridge.allocator.free(message);
            return "";
        };
        @memcpy(result, message);
        bridge.allocator.free(message);

        return result.ptr;
    }

    /// Explain commit range
    pub export fn grim_zap_explain(
        bridge: *GhostlangBridge,
        range: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const range_slice = std.mem.span(range);
        const explanation = bridge.zap.?.explainChanges(range_slice) catch return "";

        const result = bridge.allocator.allocSentinel(u8, explanation.len, 0) catch {
            bridge.allocator.free(explanation);
            return "";
        };
        @memcpy(result, explanation);
        bridge.allocator.free(explanation);

        return result.ptr;
    }

    /// Suggest merge resolution
    pub export fn grim_zap_merge(
        bridge: *GhostlangBridge,
        conflict: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const conflict_slice = std.mem.span(conflict);
        const suggestion = bridge.zap.?.suggestMergeResolution(conflict_slice) catch return "";

        const result = bridge.allocator.allocSentinel(u8, suggestion.len, 0) catch {
            bridge.allocator.free(suggestion);
            return "";
        };
        @memcpy(result, suggestion);
        bridge.allocator.free(suggestion);

        return result.ptr;
    }
};
```

---

## Phase 2: Git Commands Integration (Priority: HIGH) 🔥

### 2.1 Wire Zap into Git Module
**File:** `/data/projects/grim/core/git.zig`

Grim already has Git integration. Add zap hooks:

```zig
// Near top of file, import zap
const zap_mod = @import("zap.zig");

// Inside Git struct, add zap field
pub const Git = struct {
    allocator: std.mem.Allocator,
    // ... existing fields
    zap: ?*zap_mod.ZapIntegration = null,

    // Add method to enable AI
    pub fn enableAI(self: *Git, config: zap_mod.OllamaConfig) !void {
        if (self.zap != null) return;

        const zap_int = try self.allocator.create(zap_mod.ZapIntegration);
        zap_int.* = try zap_mod.ZapIntegration.initWithConfig(self.allocator, config);
        self.zap = zap_int;
    }

    // Add AI-enhanced commit
    pub fn generateCommitMessage(self: *Git) ![]const u8 {
        if (self.zap == null) return error.ZapNotEnabled;

        // Get staged diff
        const diff = try self.getStagedDiff();
        defer self.allocator.free(diff);

        return try self.zap.?.generateCommitMessage(diff);
    }
};
```

---

### 2.2 Add Commands (if Grim has command system)
**Location:** TBD based on Grim's command architecture

```zig
// Example command registration
pub fn registerZapCommands(registry: *CommandRegistry) !void {
    try registry.register("zap-commit", zapCommitCommand);
    try registry.register("zap-explain", zapExplainCommand);
    try registry.register("zap-merge", zapMergeCommand);
}

fn zapCommitCommand(editor: *Editor) !void {
    // Get git context
    // Call zap generate
    // Display in commit buffer
}
```

---

## Phase 3: Configuration (Priority: MEDIUM) ⚡

### 3.1 Add Zap Config to Grim
**File:** `/data/projects/grim/host/mod.zig` or config module

```zig
pub const Config = struct {
    // ... existing fields

    // Zap/AI configuration
    ai_enabled: bool = true,
    ai_ollama_host: []const u8 = "http://localhost:11434",
    ai_ollama_model: []const u8 = "deepseek-coder:33b",
    ai_auto_commit: bool = false,
};
```

---

### 3.2 Load .zap.toml from Project Root
**File:** Same config module

```zig
pub fn loadZapConfig(allocator: std.mem.Allocator, project_root: []const u8) !?zap.OllamaConfig {
    const zap_path = try std.fs.path.join(allocator, &[_][]const u8{
        project_root,
        ".zap.toml",
    });
    defer allocator.free(zap_path);

    // Try to read .zap.toml
    const file = std.fs.cwd().openFile(zap_path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close();

    // Parse with flare (Grim already has flare as dependency)
    const flare = @import("flare");
    var config = try flare.Config.init(allocator);
    defer config.deinit();

    try config.loadFromFile(zap_path);

    return zap.OllamaConfig{
        .host = try config.getString("ollama.host", "http://localhost:11434"),
        .model = try config.getString("ollama.model", "deepseek-coder:33b"),
        .timeout_ms = @intCast(try config.getInt("ollama.timeout_ms", 30000)),
    };
}
```

---

## Phase 4: UI Integration (Priority: MEDIUM) 🎨

### 4.1 Add Keybindings
**Location:** Grim's keymap system

```zig
// Default keybindings for zap
{ .mode = .normal, .key = "<leader>gc", .command = "zap-commit" },
{ .mode = .normal, .key = "<leader>ge", .command = "zap-explain" },
{ .mode = .normal, .key = "<leader>gm", .command = "zap-merge" },
{ .mode = .normal, .key = "<leader>gz", .command = "zap-toggle" },
```

---

### 4.2 Status Line Indicator
**File:** `/data/projects/grim/ui-tui/statusline.zig` (if exists)

```zig
fn renderStatusLine(editor: *Editor, buf: *Buffer) !void {
    // ... existing status line

    // Show ⚡ if zap is enabled and available
    if (editor.git) |git| {
        if (git.zap) |zap| {
            if (zap.isAvailable()) {
                try buf.append("⚡ AI");
            }
        }
    }
}
```

---

### 4.3 Floating Window for Results
**File:** `/data/projects/grim/ui-tui/` (floating window module)

Grim uses phantom TUI. Add floating window for zap results:

```zig
pub fn showZapResult(editor: *Editor, title: []const u8, content: []const u8) !void {
    // Create phantom floating window
    var float = try phantom.FloatingWindow.init(.{
        .width = 80,
        .height = 20,
        .title = title,
        .border = true,
    });

    try float.setContent(content);
    try editor.renderWindow(float);
}
```

---

## Phase 5: Testing (Priority: HIGH) 🧪

### 5.1 Integration Tests
**New File:** `/data/projects/grim/tests/zap_integration_test.zig`

```zig
const std = @import("std");
const testing = std.testing;
const core = @import("core");

test "zap integration initializes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var zap = try core.ZapIntegration.init(allocator);
    defer zap.deinit();

    try testing.expect(zap.enabled);
}

test "zap generates commit message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var zap = try core.ZapIntegration.init(allocator);
    defer zap.deinit();

    const diff = "diff --git a/test.zig b/test.zig\n+fn test() void {}";

    // This will fail if Ollama not running, which is OK for CI
    const message = zap.generateCommitMessage(diff) catch |err| {
        if (err == error.OllamaNotAvailable) return;
        return err;
    };
    defer allocator.free(message);

    try testing.expect(message.len > 0);
}
```

---

## Phase 6: Documentation (Priority: MEDIUM) 📚

### 6.1 Update Grim README
**File:** `/data/projects/grim/README.md`

Add section after "Features":

```markdown
## AI-Powered Git Workflow ⚡

Grim includes built-in AI assistance via [zap](https://github.com/ghostkellz/zap):

- **Smart commits**: Generate conventional commit messages from diffs
- **Explain changes**: Understand what code changes do in plain English
- **Merge assistance**: Get suggestions for resolving conflicts

### Quick Start

1. **Install Ollama** (local AI inference)
   \`\`\`bash
   curl -fsSL https://ollama.com/install.sh | sh
   ollama pull deepseek-coder:33b
   \`\`\`

2. **Use in Grim**
   - `:GrimCommit` - Generate AI commit message
   - `:GrimExplain HEAD~3..HEAD` - Explain commits
   - `<leader>gc` - Smart commit (default keymap)

3. **Configure** (optional)
   Create `.zap.toml` in project root:
   \`\`\`toml
   [ollama]
   host = "http://localhost:11434"
   model = "deepseek-coder:33b"
   \`\`\`

### Disable AI Features
\`\`\`bash
# Launch with AI disabled
grim --no-ai

# Or set in config
ai_enabled = false
\`\`\`
```

---

### 6.2 Add AI Features Guide
**New File:** `/data/projects/grim/docs/AI_FEATURES.md`

```markdown
# AI Features in Grim

## Overview
Grim includes zap AI integration for intelligent git workflows.

## Features
- Commit message generation
- Code change explanations
- Merge conflict resolution

## Configuration
...
```

---

## Architecture Summary

```
┌──────────────────────────────────────────────┐
│                   Grim                       │
├──────────────────────────────────────────────┤
│  UI Layer (ui-tui/)                          │
│  ├─ Editor                                   │
│  ├─ Commands                                 │
│  └─ Status line                              │
├──────────────────────────────────────────────┤
│  Core Layer (core/)                          │
│  ├─ Git ────────> Zap Integration            │
│  ├─ Fuzzy                                    │
│  ├─ Harpoon                                  │
│  └─ Rope buffer                              │
├──────────────────────────────────────────────┤
│  Ghostlang Bridge (src/ghostlang_bridge.zig) │
│  ├─ Git FFI                                  │
│  ├─ Zap FFI  ⚡ NEW                          │
│  ├─ Fuzzy FFI                                │
│  └─ Syntax FFI                               │
├──────────────────────────────────────────────┤
│  Dependencies                                │
│  ├─ zap (AI git features) ⚡ NEW             │
│  ├─ grove (tree-sitter)                      │
│  ├─ phantom (TUI)                            │
│  ├─ flare (config)                           │
│  └─ ghostlang (scripting)                    │
└──────────────────────────────────────────────┘
```

---

## Integration Points

1. **Core → Zap**: `core/zap.zig` wraps zap library
2. **Git → Zap**: `core/git.zig` calls zap for AI features
3. **Bridge → Zap**: `src/ghostlang_bridge.zig` exposes C FFI
4. **UI → Zap**: Commands trigger zap operations
5. **Config → Zap**: Load `.zap.toml` via flare

---

## Timeline Estimate

| Phase | Description | Estimate |
|-------|-------------|----------|
| 1 | Core integration (deps + wiring) | 4-6 hours |
| 2 | Git commands | 3-4 hours |
| 3 | Configuration | 2-3 hours |
| 4 | UI (keymaps, statusline, floats) | 3-4 hours |
| 5 | Testing | 3-4 hours |
| 6 | Documentation | 2-3 hours |
| **Total** | **Full integration** | **17-24 hours** |

---

## Success Criteria ✅

**Core Integration Complete When:**
- ✅ `zig build` succeeds with zap dependency
- ✅ Zap FFI exposed via ghostlang_bridge
- ✅ Git module can call zap functions
- ✅ No compilation errors

**Feature Complete When:**
- ✅ `:GrimCommit` generates AI messages
- ✅ `:GrimExplain` works for commit ranges
- ✅ Status line shows ⚡ when AI available
- ✅ `.zap.toml` config is respected
- ✅ Works with/without Ollama running

---

## Next Steps (Priority Order)

1. **NOW**: Add zap to `build.zig.zon` and fetch dependency
2. **Then**: Update `core/zap.zig` with real implementation
3. **Then**: Add zap FFI to `ghostlang_bridge.zig`
4. **Then**: Wire zap into `core/git.zig`
5. **Then**: Add commands and keybindings
6. **Then**: Test and document

---

## Notes

- **No conflicts**: Zap doesn't interfere with existing git functionality
- **Graceful degradation**: Falls back if Ollama unavailable
- **Optional**: Can be completely disabled via config
- **Privacy**: All AI inference is local (Ollama)
- **Performance**: FFI calls are fast, AI generation is async-friendly

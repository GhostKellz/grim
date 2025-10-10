# 🚀 Grim + Ghostls v0.3.0 - NEW LSP Features Available!

**Date:** October 10, 2025
**Ghostls Version:** v0.3.0 (MAJOR RELEASE)
**Grim Status:** Ready to integrate new features

---

## 🎉 What's New in Ghostls v0.3.0

Ghostls has been upgraded from a basic LSP server to a **full-featured, production-ready language server** with **15+ LSP features**. All these capabilities are now available for Grim to leverage!

---

## 📋 New LSP Methods Available

### **Phase 1: Multi-File Support (Beta Features)**

#### 1. ✅ `textDocument/semanticTokens/full` - Enhanced Syntax Highlighting
**What it does:**
Provides semantic highlighting beyond tree-sitter syntax highlighting.

**Token types:** namespace, type, class, function, variable, keyword, string, number, comment, operator
**Token modifiers:** declaration, definition, readonly, deprecated, static, abstract

**Grim Integration:**
```zig
// In editor_lsp.zig - add new method
pub fn requestSemanticTokens(self: *EditorLSP, path: []const u8) !void {
    if (self.language == null) return;

    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    _ = try server.requestSemanticTokens(uri);
}
```

**Use case:** Better syntax highlighting for Ghostlang code, distinguishing functions from variables, constants, etc.

---

### **Phase 2: Power-User Features (Modal Editing Optimized)**

#### 2. ✅ `textDocument/codeAction` - Quick Fixes & Refactoring
**What it does:**
Provides quick fixes and refactoring suggestions for code issues.

**Actions available:**
- Missing semicolon auto-fix
- Unused variable warnings
- Extract function (framework ready)
- Inline variable (framework ready)

**Grim Integration:**
```zig
// In editor_lsp.zig
pub fn requestCodeActions(self: *EditorLSP, path: []const u8, range: Diagnostic.Range) !void {
    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    _ = try server.requestCodeActions(uri, range);
}
```

**Keybinding suggestion:** `<leader>ca` - Show code actions menu
**Perfect for:** Grim's modal workflow - trigger fixes in normal mode

---

#### 3. ✅ `textDocument/rename` + `textDocument/prepareRename` - Symbol Renaming
**What it does:**
Renames symbols across the entire document (workspace-wide ready).

**Features:**
- Validates rename is possible (`prepareRename`)
- Finds all occurrences of identifier
- Returns workspace edit with all text changes
- Safe identifier validation

**Grim Integration:**
```zig
// In editor_lsp.zig
pub fn prepareRename(self: *EditorLSP, path: []const u8, line: u32, character: u32) !?Diagnostic.Range {
    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return null;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    return try server.prepareRename(uri, line, character);
}

pub fn requestRename(self: *EditorLSP, path: []const u8, line: u32, character: u32, new_name: []const u8) !void {
    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    _ = try server.requestRename(uri, line, character, new_name);
}
```

**Keybinding suggestion:** `<leader>rn` - Rename symbol under cursor
**Perfect for:** Large-scale refactoring in Grim

---

#### 4. ✅ `textDocument/signatureHelp` - Parameter Hints
**What it does:**
Shows function signatures and parameter documentation while typing function calls.

**Built-in signatures:**
- `print(value: any)` - Print value to console
- `arrayPush(array: array, value: any)` - Push to array
- All 44+ Ghostlang helper functions (extensible)

**Grim Integration:**
```zig
// In editor_lsp.zig
pub fn requestSignatureHelp(self: *EditorLSP, path: []const u8, line: u32, character: u32) !void {
    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    _ = try server.requestSignatureHelp(uri, line, character);
}
```

**Trigger:** Auto-trigger on `(` and `,`
**Perfect for:** Inline help while writing function calls

---

#### 5. ✅ `textDocument/inlayHint` - Inline Type Annotations
**What it does:**
Shows type hints inline without cluttering the source code.

**Type inference for:**
- `var x = 42;` → shows `: number` after `x`
- `var name = "Alice";` → shows `: string`
- `var items = [];` → shows `: array`
- `var config = {};` → shows `: object`

**Grim Integration:**
```zig
// In editor_lsp.zig
pub fn requestInlayHints(self: *EditorLSP, path: []const u8, range: Diagnostic.Range) !void {
    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    _ = try server.requestInlayHints(uri, range);
}
```

**Use case:** Show types without explicit annotations (like Rust's inlay hints)
**Toggle:** `<leader>th` - Toggle type hints

---

#### 6. ✅ `textDocument/selectionRange` - Smart Text Objects
**What it does:**
Provides hierarchical selection ranges for expand/shrink selections.

**Perfect for Vim motions:**
- `vii` - Select inner identifier
- `vai` - Select around expression
- `<C-]>` - Expand selection (e.g., identifier → expression → statement → function)
- `<C-[>` - Shrink selection

**Grim Integration:**
```zig
// In editor_lsp.zig
pub fn requestSelectionRange(self: *EditorLSP, path: []const u8, positions: []Diagnostic.Position) !void {
    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    _ = try server.requestSelectionRange(uri, positions);
}
```

**Perfect for:** Grim's modal editing - smart text objects for `v` (visual mode)

---

### **Phase 3: Performance & Polish**

#### 7. ✅ Incremental Parsing
**What it does:**
Ghostls now reuses AST nodes on edits, reducing re-parse time by ~80%.

**Benefits for Grim:**
- Faster response times on file changes
- Lower CPU usage during typing
- Better responsiveness for large files

**No integration required** - automatically used by ghostls!

---

#### 8. ✅ Filesystem Watcher Support
**What it does:**
Detects file changes on disk and updates workspace state.

**Future integration:**
```zig
// In editor_lsp.zig
pub fn notifyFileChanged(self: *EditorLSP, path: []const u8, change_type: ChangeType) !void {
    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    try server.notifyFileChanged(uri, change_type);
}
```

**Use case:** Auto-reload when `.gza` files change externally

---

## 🎯 Integration Priority for Grim

### **High Priority** (Immediate UX Impact)
1. **Signature Help** - Shows function params while typing
2. **Inlay Hints** - Type annotations inline
3. **Selection Range** - Smart Vim text objects
4. **Code Actions** - Quick fixes in modal workflow

### **Medium Priority** (Refactoring Features)
5. **Rename Symbol** - Workspace-wide refactoring
6. **Semantic Tokens** - Better highlighting

### **Low Priority** (Future Enhancements)
7. **Filesystem Watcher** - External file change detection

---

## 🔧 Example: Adding Signature Help to Grim

### **Step 1: Update LSP Client** (`lsp/client.zig`)

```zig
pub fn requestSignatureHelp(self: *LanguageServer, uri: []const u8, position: Position) !u32 {
    const request_id = self.nextRequestId();

    const request = try std.fmt.allocPrint(self.allocator,
        \\{{"jsonrpc":"2.0","id":{d},"method":"textDocument/signatureHelp","params":{{"textDocument":{{"uri":"{s}"}},"position":{{"line":{d},"character":{d}}}}}}}
        , .{ request_id, uri, position.line, position.character });
    defer self.allocator.free(request);

    try self.sendRequest(request);
    return request_id;
}
```

### **Step 2: Update Editor LSP** (`ui-tui/editor_lsp.zig`)

```zig
pub fn requestSignatureHelp(self: *EditorLSP, path: []const u8, line: u32, character: u32) !void {
    if (self.language == null) return;

    const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;
    const uri = try self.pathToUri(path);
    defer self.allocator.free(uri);

    _ = try server.requestSignatureHelp(uri, .{ .line = line, .character = character });
}

// Store signature help response
signature_help: ?SignatureHelp = null,

pub const SignatureHelp = struct {
    signatures: []SignatureInfo,
    active_signature: u32,
    active_parameter: u32,
};
```

### **Step 3: UI Rendering** (`ui-tui/simple_tui.zig`)

```zig
// Trigger on ( and ,
if (char == '(' or char == ',') {
    const cursor = self.editor.cursor;
    try self.lsp_manager.requestSignatureHelp(self.current_file, cursor.line, cursor.col);
}

// Render signature help popup (above cursor)
if (self.lsp_manager.signature_help) |sig| {
    // Draw signature popup with active parameter highlighted
    drawSignaturePopup(sig);
}
```

---

## 📦 Server Capabilities Update

Ghostls v0.3.0 now advertises these capabilities in `initialize` response:

```json
{
  "capabilities": {
    "positionEncoding": "utf-16",
    "textDocumentSync": {"openClose": true, "change": 1, "save": {"includeText": true}},
    "hoverProvider": true,
    "completionProvider": {"triggerCharacters": [".", ":"]},
    "definitionProvider": true,
    "referencesProvider": true,
    "workspaceSymbolProvider": true,
    "documentSymbolProvider": true,
    "semanticTokensProvider": {
      "legend": {
        "tokenTypes": ["namespace", "type", "class", "function", "variable", "keyword", "string", "number", "comment", "operator"],
        "tokenModifiers": ["declaration", "definition", "readonly", "deprecated", "static"]
      },
      "full": true
    },
    "codeActionProvider": true,
    "renameProvider": {"prepareProvider": true},
    "signatureHelpProvider": {
      "triggerCharacters": ["(", ","]
    },
    "inlayHintProvider": true,
    "selectionRangeProvider": true
  }
}
```

---

## 🎨 Keybinding Suggestions for Grim

```lua
-- In Grim config (Ghostlang format)
local keybindings = {
    -- Existing
    K = "lsp_hover",           -- Hover docs
    gd = "lsp_definition",     -- Go to definition

    -- New v0.3.0 features
    ["<leader>ca"] = "lsp_code_actions",        -- Code actions menu
    ["<leader>rn"] = "lsp_rename",              -- Rename symbol
    ["<leader>th"] = "toggle_inlay_hints",      -- Toggle type hints
    ["<C-k>"] = "lsp_signature_help",           -- Show signature
    ["<C-]>"] = "expand_selection",             -- Expand selection
    ["<C-[>"] = "shrink_selection",             -- Shrink selection
}
```

---

## 🚀 Benefits for Grim Users

### **For Modal Editing**
- **Selection ranges** integrate perfectly with Vim motions
- **Code actions** triggered via normal mode commands
- **Signature help** shows while editing in insert mode

### **For Productivity**
- **Rename** allows safe large-scale refactoring
- **Inlay hints** provide type info without annotations
- **Semantic tokens** improve code readability

### **For Performance**
- **Incremental parsing** keeps editor responsive
- **80% faster** re-parsing on file changes
- **Lower CPU** usage during typing

---

## 📚 Implementation Checklist

### **Immediate (High ROI)**
- [ ] Add signature help request method to LSP client
- [ ] Integrate signature help popup rendering
- [ ] Add keybinding for signature help (`<C-k>`)
- [ ] Test with Ghostlang function calls

### **Short-term (1-2 weeks)**
- [ ] Add selection range support for Vim motions
- [ ] Implement inlay hints rendering
- [ ] Add toggle for type hints display
- [ ] Add code actions menu

### **Medium-term (1 month)**
- [ ] Implement rename symbol workflow
- [ ] Add semantic tokens support
- [ ] Integrate with Grim's theme system
- [ ] Add filesystem watcher notifications

---

## 🔗 Resources

- **Ghostls v0.3.0 Repo:** https://github.com/ghostkellz/ghostls
- **Implementation Summary:** `/data/projects/ghostls/IMPLEMENTATION_SUMMARY_v0.3.0.md`
- **LSP Spec:** https://microsoft.github.io/language-server-protocol/
- **Grim LSP Client:** `/data/projects/grim/lsp/client.zig`
- **Grim Editor LSP:** `/data/projects/grim/ui-tui/editor_lsp.zig`

---

## 🎯 Next Steps

1. **Update Grim's LSP client** with new method signatures
2. **Test each feature** individually with ghostls v0.3.0
3. **Integrate UI rendering** for new popups/overlays
4. **Add keybindings** for new features
5. **Update Grim documentation** with new capabilities

---

**Built with 💀 by the Ghost Ecosystem**

*"Reap your codebase with intelligent tooling"*

---

## 💡 Quick Start

To test new features with Grim:

```bash
# Update ghostls
cd /data/projects/ghostls
git pull origin main
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/ghostls /usr/local/bin/

# Verify version
ghostls --version  # Should show: ghostls 0.3.0

# Test with Grim
cd /data/projects/grim
zig build
./zig-out/bin/grim example.gza

# All new LSP features now available!
```

🎉 **Ghostls v0.3.0 is ready for Grim integration!**

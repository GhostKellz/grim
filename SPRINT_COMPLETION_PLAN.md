# Grim - Sprint 12-14 Completion Plan

**Date:** October 24, 2025
**Goal:** Complete Sprints 12-14 in parallel (6-8 weeks)
**Status:** Ready to execute

---

## Infrastructure Analysis

### ✅ What's Already Implemented

**Sprint 12 - Terminal (70% complete):**
- ✅ `core/terminal.zig` - Complete PTY implementation (362 lines)
- ✅ `core/ansi.zig` - ANSI parser and screen buffer (17K)
- ✅ Process spawning (fork/exec/setsid)
- ✅ Non-blocking I/O
- ✅ Scrollback buffer

**Sprint 13 - Collaboration (40% complete):**
- ✅ `core/collaboration.zig` - OT algorithm (16K)
- ✅ `core/websocket.zig` - WebSocket client (9K)
- ✅ `core/websocket_server.zig` - WebSocket server (15K)
- ✅ User presence system
- ✅ Operation recording

**Sprint 14 - AI/Thanos (30% complete):**
- ✅ `src/ai/inline_completion.zig` - Complete inline engine (302 lines)
- ✅ `src/ai/ghost_text.zig` - Ghost text rendering (215 lines)
- ✅ `src/ai/chat_window.zig` - Chat UI (13K)
- ✅ `src/ai/context_manager.zig` - Context gathering (9.4K)
- ✅ `src/ai/cost_tracker.zig` - Cost tracking (11K)
- ✅ `src/ai/provider_switcher.zig` - Provider UI (11K)
- ✅ `src/ai/diff_viewer.zig` - Diff visualization (14K)
- ✅ Thanos integration via `/data/projects/thanos.grim`

**LSP (60% complete):**
- ✅ `lsp/client.zig` - Full LSP client
- ✅ `lsp/server_manager.zig` - Server lifecycle
- ✅ Async message polling
- ✅ JSON-RPC framing

---

## 🚀 Sprint 12: Terminal Integration (2-3 weeks)

### Phase 1: Async I/O Integration (Week 1)

**File:** `core/terminal.zig` - Add async polling

```zig
// Add to Terminal struct:
pub const Terminal = struct {
    // ... existing fields

    poll_fd: ?posix.pollfd = null,
    async_callback: ?*const fn(*Terminal, []const u8) void = null,

    /// Set up for async I/O polling
    pub fn setupAsyncIO(self: *Terminal, callback: *const fn(*Terminal, []const u8) void) !void {
        self.async_callback = callback;
        self.poll_fd = posix.pollfd{
            .fd = self.pty_master,
            .events = posix.POLL.IN | posix.POLL.HUP,
            .revents = 0,
        };
    }

    /// Poll for new data (call from main event loop)
    pub fn poll(self: *Terminal, timeout_ms: i32) !bool {
        if (self.poll_fd) |*pfd| {
            const n = try posix.poll(@ptrCast([*]posix.pollfd, pfd), 1, timeout_ms);

            if (n > 0 and (pfd.revents & posix.POLL.IN) != 0) {
                var buf: [4096]u8 = undefined;
                const bytes_read = try self.read(&buf);

                if (bytes_read > 0 and self.async_callback != null) {
                    self.async_callback.?(self, buf[0..bytes_read]);
                    return true;
                }
            }

            // Check if process exited
            if (pfd.revents & posix.POLL.HUP) {
                self.running = false;
                return false;
            }
        }

        return false;
    }
};
```

**Integration Point:** `ui-tui/simple_tui.zig` main event loop

```zig
// In SimpleTUI.run() or main loop:
pub fn pollTerminals(self: *SimpleTUI) !void {
    if (self.buffer_manager) |bm| {
        for (bm.buffers.items) |*buffer| {
            if (buffer.buffer_type == .terminal and buffer.terminal != null) {
                if (try buffer.terminal.?.poll(0)) {  // Non-blocking poll
                    self.needs_redraw = true;
                }
            }
        }
    }
}
```

**Tasks:**
1. Add `setupAsyncIO()` method - **2 hours**
2. Add `poll()` method - **3 hours**
3. Integrate into SimpleTUI event loop - **4 hours**
4. Test with `:term` command - **2 hours**
5. Handle process exit gracefully - **2 hours**

**Total:** 13 hours (2 days)

---

### Phase 2: Terminal Rendering Integration (Week 2)

**File:** `ui-tui/simple_tui.zig` - Render terminal screen buffer

The ANSI parser (`core/ansi.zig`) already exists and provides `ScreenBuffer`. We need to integrate it into rendering.

```zig
// In SimpleTUI rendering code:
fn renderBuffer(self: *SimpleTUI, writer: anytype) !void {
    const buffer = self.getCurrentBuffer() orelse return;

    if (buffer.buffer_type == .terminal and buffer.terminal != null) {
        // Render terminal screen buffer instead of text editor
        try self.renderTerminalBuffer(writer, buffer.terminal.?);
    } else {
        // Normal text editor rendering
        try self.renderTextBuffer(writer, &buffer.editor);
    }
}

fn renderTerminalBuffer(self: *SimpleTUI, writer: anytype, terminal: *Terminal) !void {
    if (terminal.screen) |screen| {
        for (screen.cells, 0..) |row, y| {
            for (row, 0..) |cell, x| {
                // Set position
                try writer.print("\x1b[{};{}H", .{y + 1, x + 1});

                // Set colors and attributes
                if (cell.fg != 0) {
                    try writer.print("\x1b[38;2;{};{};{}m", .{
                        (cell.fg >> 16) & 0xFF,
                        (cell.fg >> 8) & 0xFF,
                        cell.fg & 0xFF,
                    });
                }
                if (cell.bg != 0) {
                    try writer.print("\x1b[48;2;{};{};{}m", .{
                        (cell.bg >> 16) & 0xFF,
                        (cell.bg >> 8) & 0xFF,
                        cell.bg & 0xFF,
                    });
                }
                if (cell.bold) try writer.writeAll("\x1b[1m");
                if (cell.italic) try writer.writeAll("\x1b[3m");

                // Write character
                try writer.writeByte(cell.char);

                // Reset attributes
                try writer.writeAll("\x1b[0m");
            }
        }
    }
}
```

**Tasks:**
1. Wire `ansi.ScreenBuffer` to terminal rendering - **8 hours**
2. Handle color codes (16/256/truecolor) - **6 hours**
3. Render cursor in terminal buffer - **4 hours**
4. Test with various commands (`ls`, `vim`, `htop`) - **6 hours**
5. Fix rendering artifacts - **6 hours**

**Total:** 30 hours (4-5 days)

---

### Phase 3: Input Handling (Week 3)

**File:** `ui-tui/simple_tui.zig` - Terminal mode

```zig
// Add mode to SimpleTUI:
pub const Mode = enum {
    normal,
    insert,
    visual,
    command,
    terminal,  // NEW
};

// In handleInput():
fn handleInput(self: *SimpleTUI, key: Key) !void {
    const buffer = self.getCurrentBuffer() orelse return;

    // Switch to terminal mode when in terminal buffer
    if (buffer.buffer_type == .terminal and self.mode != .terminal) {
        self.mode = .terminal;
    }

    switch (self.mode) {
        .terminal => try self.handleTerminalInput(key),
        .normal => try self.handleNormalMode(key),
        // ... other modes
    }
}

fn handleTerminalInput(self: *SimpleTUI, key: Key) !void {
    const buffer = self.getCurrentBuffer() orelse return;
    if (buffer.terminal) |terminal| {
        // Check for exit sequence (Ctrl-\ Ctrl-N like Neovim)
        if (key.ctrl and key.char == '\\') {
            self.terminal_escape_pending = true;
            return;
        }

        if (self.terminal_escape_pending and key.ctrl and key.char == 'n') {
            // Exit terminal mode
            self.mode = .normal;
            self.terminal_escape_pending = false;
            return;
        }

        self.terminal_escape_pending = false;

        // Forward key to PTY
        var buf: [16]u8 = undefined;
        const bytes = try keyToTerminalBytes(key, &buf);
        _ = try terminal.write(bytes);
    }
}

fn keyToTerminalBytes(key: Key, buf: []u8) ![]const u8 {
    // Convert key press to terminal escape sequences
    if (key.ctrl) {
        // Ctrl+A = 0x01, Ctrl+B = 0x02, etc.
        if (key.char >= 'a' and key.char <= 'z') {
            buf[0] = key.char - 'a' + 1;
            return buf[0..1];
        }
    }

    // Special keys
    switch (key.special) {
        .up => return "\x1b[A",
        .down => return "\x1b[B",
        .right => return "\x1b[C",
        .left => return "\x1b[D",
        .home => return "\x1b[H",
        .end => return "\x1b[F",
        .page_up => return "\x1b[5~",
        .page_down => return "\x1b[6~",
        .backspace => return "\x7f",
        .delete => return "\x1b[3~",
        .enter => return "\r",
        .tab => return "\t",
        .escape => return "\x1b",
        else => {},
    }

    // Normal character
    if (key.char != 0) {
        buf[0] = key.char;
        return buf[0..1];
    }

    return "";
}
```

**Tasks:**
1. Add terminal mode to SimpleTUI - **4 hours**
2. Implement key-to-escape-sequence conversion - **6 hours**
3. Forward keys to PTY - **3 hours**
4. Implement exit sequence (Ctrl-\ Ctrl-N) - **3 hours**
5. Test interactive programs (vim, nano, htop) - **6 hours**

**Total:** 22 hours (3 days)

---

### Sprint 12 Summary
- **Week 1:** Async I/O (2 days)
- **Week 2:** Terminal rendering (5 days)
- **Week 3:** Input handling (3 days)
- **Total:** 2-3 weeks, **65 hours**
- **Deliverable:** ✅ Fully functional embedded terminal

---

## 🚀 Sprint 13: Collaboration (3-4 weeks)

### Phase 1: WebSocket Layer Polish (Week 1-2)

**Status:** `core/websocket.zig` and `core/websocket_server.zig` already exist (24K total)

**Tasks:**
1. Test WebSocket handshake - **4 hours**
2. Fix any connection issues - **8 hours**
3. Add reconnection logic - **6 hours**
4. Implement heartbeat/ping-pong - **4 hours**
5. Test with multiple clients - **6 hours**

**Total:** 28 hours (4 days)

---

### Phase 2: Protocol Implementation (Week 2)

**File:** `core/collaboration.zig` - Add JSON serialization

```zig
pub const Protocol = struct {
    pub const Message = struct {
        type: MessageType,
        user_id: []const u8,
        session_id: []const u8,
        data: MessageData,
    };

    pub const MessageType = enum {
        operation,
        cursor,
        presence,
        sync_request,
        sync_response,
        user_join,
        user_leave,
    };

    pub const MessageData = union(MessageType) {
        operation: Operation,
        cursor: CursorUpdate,
        presence: PresenceUpdate,
        sync_request: SyncRequest,
        sync_response: SyncResponse,
        user_join: UserInfo,
        user_leave: UserInfo,
    };

    pub fn serialize(allocator: std.mem.Allocator, msg: Message) ![]const u8 {
        return std.json.stringifyAlloc(allocator, msg, .{});
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !Message {
        const parsed = try std.json.parseFromSlice(Message, allocator, data, .{});
        defer parsed.deinit();
        return parsed.value;
    }
};
```

**Tasks:**
1. Implement JSON serialization - **8 hours**
2. Add message routing - **6 hours**
3. Broadcast operations to all clients - **6 hours**
4. Handle sync requests - **8 hours**

**Total:** 28 hours (4 days)

---

### Phase 3: UI Integration (Week 3)

**File:** `ui-tui/simple_tui.zig` - Add presence indicators

```zig
// Render remote cursors
fn renderRemoteCursors(self: *SimpleTUI, writer: anytype) !void {
    if (self.collaboration_session) |session| {
        for (session.users.items) |user| {
            if (std.mem.eql(u8, user.user_id, session.local_user_id)) {
                continue;  // Skip local user
            }

            // Calculate screen position
            const screen_pos = self.bufferPosToScreen(user.cursor_position);

            // Render cursor with user color
            try writer.print("\x1b[{};{}H", .{screen_pos.line, screen_pos.col});
            try writer.print("\x1b[48;2;{};{};{}m", .{
                user.color.r, user.color.g, user.color.b
            });
            try writer.writeAll(" ");  // Colored block
            try writer.writeAll("\x1b[0m");

            // Show user name above cursor
            try writer.print("\x1b[{};{}H", .{screen_pos.line - 1, screen_pos.col});
            try writer.print("\x1b[38;2;{};{};{}m", .{
                user.color.r, user.color.g, user.color.b
            });
            try writer.writeAll(user.display_name);
            try writer.writeAll("\x1b[0m");
        }
    }
}

// Update status line with collaboration info
fn renderStatusLine(self: *SimpleTUI, writer: anytype) !void {
    // ... existing status line

    // Add collaboration indicator
    if (self.collaboration_session) |session| {
        try writer.print(" | Collab: {} users", .{session.users.items.len});
    }
}
```

**Tasks:**
1. Render remote cursors - **12 hours**
2. Render user presence indicators - **8 hours**
3. Add user list panel (`:collab users`) - **8 hours**
4. Status line integration - **4 hours**
5. Test with 2-3 clients - **8 hours**

**Total:** 40 hours (5 days)

---

### Phase 4: Commands (Week 4)

**File:** `ui-tui/simple_tui.zig` - Add commands

```zig
// In command handler:
fn executeCommand(self: *SimpleTUI, cmd: []const u8) !void {
    if (std.mem.startsWith(u8, cmd, "collab start")) {
        const port = parsePort(cmd) orelse 8080;
        try self.startCollabServer(port);
    } else if (std.mem.startsWith(u8, cmd, "collab join")) {
        const url = parseUrl(cmd) orelse return error.InvalidUrl;
        try self.joinCollabSession(url);
    } else if (std.mem.eql(u8, cmd, "collab users")) {
        try self.showCollabUsers();
    } else if (std.mem.eql(u8, cmd, "collab stop")) {
        try self.stopCollab();
    }
    // ... other commands
}

fn startCollabServer(self: *SimpleTUI, port: u16) !void {
    const session = try CollaborationSession.init(
        self.allocator,
        "session-" ++ generateId(),
        "local-user"
    );

    try session.startServer(port);
    self.collaboration_session = session;

    try self.setStatusMessage(
        try std.fmt.allocPrint(self.allocator, "Collaboration server started on port {}", .{port})
    );
}

fn joinCollabSession(self: *SimpleTUI, url: []const u8) !void {
    const session = try CollaborationSession.init(
        self.allocator,
        "session-from-url",
        "local-user"
    );

    try session.connect(url);
    self.collaboration_session = session;

    try self.setStatusMessage("Joined collaboration session");
}
```

**Tasks:**
1. Implement `:collab start` - **6 hours**
2. Implement `:collab join` - **6 hours**
3. Implement `:collab users` - **4 hours**
4. Implement `:collab stop` - **3 hours**
5. Test full workflow - **8 hours**

**Total:** 27 hours (3-4 days)

---

### Sprint 13 Summary
- **Week 1-2:** WebSocket polish + protocol (8 days)
- **Week 3:** UI integration (5 days)
- **Week 4:** Commands (4 days)
- **Total:** 3-4 weeks, **123 hours**
- **Deliverable:** ✅ Real-time collaborative editing

---

## 🚀 Sprint 14: AI/Thanos Integration (3-4 weeks)

### Phase 1: Wire Thanos to Inline Completions (Week 1)

**Status:** `src/ai/inline_completion.zig` is complete but needs Thanos FFI wiring

**File:** `/data/projects/thanos.grim/native/bridge.zig` - Add inline completion function

```zig
// Add to existing FFI exports:
export fn thanos_grim_get_inline_completion_debounced(
    prefix: [*:0]const u8,
    suffix: [*:0]const u8,
    language: [*:0]const u8,
    debounce_ms: c_int,
    max_tokens: c_int,
) callconv(.C) [*:0]const u8 {
    const prefix_slice = std.mem.span(prefix);
    const suffix_slice = std.mem.span(suffix);
    const language_slice = std.mem.span(language);

    // Build context for AI
    var context = std.ArrayList(u8).init(global_allocator);
    defer context.deinit();

    context.appendSlice("// Language: ") catch return "";
    context.appendSlice(language_slice) catch return "";
    context.appendSlice("\n") catch return "";
    context.appendSlice(prefix_slice) catch return "";
    context.appendSlice("<cursor>") catch return "";
    context.appendSlice(suffix_slice) catch return "";

    // Request completion from Thanos
    const request = thanos.types.CompletionRequest{
        .prompt = context.items,
        .provider = global_provider,  // Use configured provider
        .max_tokens = @intCast(max_tokens),
        .temperature = 0.2,  // Low temperature for code completion
        .stop_sequences = &[_][]const u8{"\n\n", "//", "/*"},  // Stop at logical boundaries
        .system_prompt = "Complete the code at <cursor>. Only return the completion, no explanations.",
    };

    const response = global_thanos.complete(request) catch return "";

    if (!response.success) return "";

    // Cache result (global or thread-local)
    cached_completion = global_allocator.dupe(u8, response.text) catch return "";

    return cached_completion.ptr;
}
```

**File:** `src/ghostlang_bridge.zig` - Export FFI function to Grim

```zig
// Add extern declaration:
extern fn thanos_grim_get_inline_completion_debounced(
    prefix: [*:0]const u8,
    suffix: [*:0]const u8,
    language: [*:0]const u8,
    debounce_ms: c_int,
    max_tokens: c_int,
) callconv(.C) [*:0]const u8;

// Wire to inline completion engine in init:
pub fn initAI(allocator: std.mem.Allocator) !*InlineCompletionEngine {
    var engine = try allocator.create(InlineCompletionEngine);
    engine.* = InlineCompletionEngine.init(allocator, 300);  // 300ms debounce

    // Set FFI function
    engine.setCompletionFunction(thanos_grim_get_inline_completion_debounced);

    return engine;
}
```

**Tasks:**
1. Add inline completion FFI to thanos.grim - **8 hours**
2. Wire FFI to Grim's inline engine - **6 hours**
3. Test completion requests - **6 hours**
4. Tune debounce/temperature parameters - **4 hours**

**Total:** 24 hours (3 days)

---

### Phase 2: Ghost Text Rendering (Week 1-2)

**Status:** `src/ai/ghost_text.zig` is complete, needs TUI integration

**File:** `ui-tui/simple_tui.zig` - Integrate ghost text

```zig
pub const SimpleTUI = struct {
    // ... existing fields

    ghost_text_renderer: ?*GhostTextRenderer = null,
    inline_completion_engine: ?*InlineCompletionEngine = null,

    pub fn init(...) !SimpleTUI {
        // ... existing init

        const ghost_renderer = try GhostTextRenderer.init(allocator);
        const completion_engine = try initAI(allocator);

        return SimpleTUI{
            // ... existing fields
            .ghost_text_renderer = ghost_renderer,
            .inline_completion_engine = completion_engine,
        };
    }

    // In render loop, after rendering buffer content:
    fn render(self: *SimpleTUI, writer: anytype) !void {
        // ... render buffer content

        // Render ghost text on top
        if (self.ghost_text_renderer) |renderer| {
            try renderer.render(writer, self.cursor.line, self.cursor.col);
        }
    }

    // On text input in insert mode:
    fn handleInsertMode(self: *SimpleTUI, key: Key) !void {
        // ... existing insert handling

        // Request completion after text changes
        if (self.inline_completion_engine) |engine| {
            const context = try self.getCompletionContext();

            if (try engine.requestCompletion(context)) |completion| {
                // Show ghost text
                if (self.ghost_text_renderer) |renderer| {
                    try renderer.showGhostText(
                        completion.text,
                        self.cursor.line,
                        self.cursor.col
                    );
                }
                completion.deinit();
            } else {
                // Clear ghost text if no completion
                if (self.ghost_text_renderer) |renderer| {
                    renderer.clearGhostText();
                }
            }
        }
    }

    // Accept completion with Tab:
    fn handleInsertMode(self: *SimpleTUI, key: Key) !void {
        if (key.special == .tab) {
            if (self.ghost_text_renderer) |renderer| {
                if (renderer.getCurrentGhost()) |ghost| {
                    // Insert ghost text at cursor
                    try self.insertTextAtCursor(ghost.text);

                    // Accept completion (clear cache)
                    if (self.inline_completion_engine) |engine| {
                        engine.acceptCompletion();
                    }

                    // Clear ghost text
                    renderer.clearGhostText();
                    return;
                }
            }
        }

        // ... rest of insert mode handling
    }

    fn getCompletionContext(self: *SimpleTUI) !CompletionContext {
        const buffer = self.getCurrentBuffer() orelse return error.NoBuffer;
        const cursor_pos = self.cursor;

        // Get text before cursor (prefix)
        const prefix = try buffer.editor.rope.getSlice(0, cursor_pos.offset);

        // Get text after cursor (suffix) - next 500 chars or to end
        const suffix_end = @min(cursor_pos.offset + 500, buffer.editor.rope.len());
        const suffix = try buffer.editor.rope.getSlice(cursor_pos.offset, suffix_end);

        return CompletionContext{
            .prefix = prefix,
            .suffix = suffix,
            .file_path = buffer.file_path orelse "untitled",
            .language = detectLanguage(buffer.file_path),
            .line = cursor_pos.line,
            .column = cursor_pos.col,
        };
    }
};
```

**Tasks:**
1. Integrate GhostTextRenderer into SimpleTUI - **8 hours**
2. Wire inline completion engine - **6 hours**
3. Add Tab-to-accept logic - **4 hours**
4. Handle ghost text cancellation (Esc, cursor move) - **6 hours**
5. Test with various code scenarios - **12 hours**

**Total:** 36 hours (5 days)

---

### Phase 3: Streaming Responses (Week 2)

**File:** `/data/projects/thanos.grim/src/chat.zig` - Add streaming support

```zig
pub const ChatSession = struct {
    // ... existing fields

    streaming: bool = false,
    stream_callback: ?*const fn([]const u8) void = null,

    /// Send message with streaming response
    pub fn sendMessageStreaming(
        self: *ChatSession,
        user_message: []const u8,
        callback: *const fn([]const u8) void
    ) !void {
        // ... build context as before

        // Enable streaming
        const request = thanos.types.CompletionRequest{
            .prompt = context.items,
            .provider = self.current_provider,
            .max_tokens = 4096,
            .temperature = 0.7,
            .stream = true,  // Enable streaming
            .system_prompt = "You are a helpful AI coding assistant.",
        };

        // Call streaming API
        try self.thanos_instance.completeStreaming(request, callback);
    }
};
```

**File:** `/data/projects/thanos/src/core.zig` - Implement SSE parsing

```zig
pub fn completeStreaming(
    self: *Thanos,
    request: types.CompletionRequest,
    callback: *const fn([]const u8) void
) !void {
    // ... build HTTP request with stream=true

    // Read SSE stream
    var buffer: [4096]u8 = undefined;
    while (true) {
        const line = try response.reader().readUntilDelimiterOrEof(&buffer, '\n');
        if (line == null) break;

        // Parse SSE: "data: {...}"
        if (std.mem.startsWith(u8, line.?, "data: ")) {
            const data = line.?[6..];

            // Check for done marker
            if (std.mem.eql(u8, data, "[DONE]")) break;

            // Parse JSON chunk
            const parsed = try std.json.parseFromSlice(
                StreamChunk,
                self.allocator,
                data,
                .{}
            );
            defer parsed.deinit();

            // Extract text delta
            const delta = parsed.value.choices[0].delta.content;

            // Call callback with chunk
            callback(delta);
        }
    }
}
```

**Tasks:**
1. Implement SSE parsing in Thanos - **12 hours**
2. Add streaming support to all providers - **16 hours**
3. Wire streaming to chat window - **8 hours**
4. Token-by-token rendering in TUI - **12 hours**
5. Handle stream cancellation - **6 hours**

**Total:** 54 hours (7 days)

---

### Phase 4: Context & Polish (Week 3-4)

**File:** `src/ai/context_manager.zig` - Already exists (9.4K), needs wiring

```zig
// Wire context manager to inline completions:
fn getCompletionContext(self: *SimpleTUI) !CompletionContext {
    // ... get basic context

    // Enhance with multi-file context
    if (self.context_manager) |cm| {
        const enhanced_prefix = try cm.gatherContext(prefix, buffer.file_path);
        return CompletionContext{
            .prefix = enhanced_prefix,  // Now includes LSP symbols, imports, etc.
            // ... rest
        };
    }

    return basic_context;
}
```

**Tasks:**
1. Wire context manager to inline completions - **12 hours**
2. Implement LSP symbols gathering - **12 hours**
3. Add git diff context - **8 hours**
4. Test with provider switcher UI - **8 hours**
5. Polish cost tracker integration - **8 hours**

**Total:** 48 hours (6 days)

---

### Sprint 14 Summary
- **Week 1:** Inline completions (8 days)
- **Week 2:** Streaming (7 days)
- **Week 3-4:** Context & polish (6 days)
- **Total:** 3-4 weeks, **162 hours**
- **Deliverable:** ✅ Production-ready AI inline completions

---

## 📊 Combined Timeline

### Parallel Execution (Recommended)

**Week 1-2:**
- Terminal async I/O (**Sprint 12**)
- WebSocket polish (**Sprint 13**)
- Inline completion FFI (**Sprint 14**)

**Week 3-4:**
- Terminal rendering (**Sprint 12**)
- Collaboration protocol (**Sprint 13**)
- Ghost text integration (**Sprint 14**)

**Week 5-6:**
- Terminal input (**Sprint 12**)
- Collaboration UI (**Sprint 13**)
- Streaming responses (**Sprint 14**)

**Week 7-8:**
- Polish & testing (all sprints)
- Integration testing
- Bug fixes

**Total:** 6-8 weeks for all three sprints

---

## 🎯 Success Metrics

### Sprint 12 Complete
- ✅ `:term` opens fully functional terminal
- ✅ Can run vim, htop, bash in embedded terminal
- ✅ Async I/O with <16ms latency
- ✅ Colors and cursor rendering work
- ✅ Ctrl-\ Ctrl-N exits terminal mode

### Sprint 13 Complete
- ✅ `:collab start` starts server
- ✅ `:collab join` connects to session
- ✅ See remote cursors in real-time
- ✅ Concurrent editing with OT conflict resolution
- ✅ 3+ users can collaborate smoothly

### Sprint 14 Complete
- ✅ Ghost text appears as you type
- ✅ Tab accepts completion
- ✅ <300ms completion latency
- ✅ Streaming responses in chat window
- ✅ Multi-file context awareness
- ✅ Cost tracking works

---

## 🚀 Quick Start

### This Week (Week 1):

**Monday-Tuesday:** Terminal async I/O
```bash
cd /data/projects/grim
# Edit core/terminal.zig - add poll() method
# Edit ui-tui/simple_tui.zig - call poll() in event loop
zig build && ./zig-out/bin/grim
# Test: :term
```

**Wednesday:** WebSocket testing
```bash
# Test websocket connection
# Fix any handshake issues
```

**Thursday-Friday:** Inline completion FFI
```bash
cd /data/projects/thanos.grim
# Add thanos_grim_get_inline_completion_debounced()
zig build
cd /data/projects/grim
# Wire FFI function
zig build && ./zig-out/bin/grim
# Test completions
```

---

## 📝 Notes

**All infrastructure is in place!** The hard work of designing and scaffolding is done. Now it's "just" wiring everything together and testing.

**Estimated Total:** 350 hours = 6-8 weeks with focused work

**Parallel work possible:** Different sprints touch different files, minimal conflicts

**Deliverables:** Three major features complete, massive competitive advantage

---

*Ready to execute!* 🚀

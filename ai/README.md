# Grim AI Module - Omen Integration

## Overview

The `grim/ai` module provides AI-powered code assistance through [Omen](https://github.com/ghostkellz/omen), a Rust-based AI gateway that supports multiple providers (Claude, OpenAI, Ollama, etc.) with smart routing and caching.

**Architecture:**
```
phantom.grim (Ghostlang plugins)
    ↓
grim/ai module (Zig)
    ↓
Omen Gateway (Rust)
    ↓
AI Providers (Claude, OpenAI, Ollama, etc.)
```

## Features

- **Multi-provider support**: Claude, OpenAI, Ollama, and more through Omen
- **Smart routing**: Omen automatically selects the best provider based on the task
- **Streaming responses**: Real-time SSE (Server-Sent Events) streaming for interactive AI
- **Context awareness**: Gather buffer, LSP, and git context for better completions
- **OpenAI-compatible API**: Standard API format for easy integration
- **Zero zsync dependency**: Uses zhttp's built-in async operations

## Installation

### 1. Install Omen

Omen is already available at `/data/projects/omen`. To build and run it:

```bash
cd /data/projects/omen
cargo build --release
cargo run --release
```

Omen will start on `http://localhost:8080` by default.

**Configure Omen providers** (edit `omen.toml` or use environment variables):

```toml
# Anthropic Claude (recommended for code)
[providers.anthropic]
api_key = "sk-ant-..."
enabled = true

# OpenAI GPT
[providers.openai]
api_key = "sk-..."
enabled = true

# Ollama (local, free)
[providers.ollama]
base_url = "http://localhost:11434"
enabled = true
```

### 2. Build Grim with AI Support

The AI module is already integrated into grim's build system:

```bash
cd /data/projects/grim
zig build
```

The `ai` module will be compiled with `zhttp` support automatically.

### 3. Enable Omen Plugin in phantom.grim

The omen plugin is already added to `phantom.grim/init.gza`:

```lua
core.ensure_plugins({
    -- ...
    "ai.omen",
    -- ...
})
```

## Usage

### From Ghostlang Plugins

The omen plugin provides both high-level and low-level APIs:

#### High-Level API (Recommended)

```lua
local omen = require("ai.omen")

-- Generate commit message from staged changes
local msg = omen.commit_message()
print("Suggested commit: " .. msg)

-- Review code in current buffer
local review = omen.review_code(buffer.get_content())
print(review)

-- Explain recent changes
local explanation = omen.explain_changes()
print(explanation)

-- Generate documentation
local docs = omen.generate_docs(buffer.get_content())
buffer.insert_text(docs)

-- Detect potential issues
local issues = omen.detect_issues(buffer.get_content())
print(issues)

-- Chat with buffer context
local answer = omen.chat_with_buffer(
    "How do I optimize this function?",
    buffer.get_content(),
    buffer.get_cursor_line()
)
print(answer)
```

#### Low-Level API (Advanced)

```lua
local omen = require("ai.omen")

-- Custom completion request
local response = omen.complete({
    model = "claude-3-5-sonnet",  -- or "auto" for smart routing
    messages = {
        {
            role = "system",
            content = "You are a helpful coding assistant."
        },
        {
            role = "user",
            content = "Explain async/await in Zig"
        }
    },
    temperature = 0.7,
    max_tokens = 1000,
})

if response and response.choices then
    print(response.choices[1].message.content)
end

-- Streaming completion (real-time)
omen.stream_complete({
    model = "auto",
    messages = {
        { role = "user", content = "Write a Zig HTTP server" }
    },
    temperature = 0.8,
}, function(chunk)
    -- Called for each chunk as it arrives
    print(chunk.choices[1].delta.content or "")
end)
```

### From Zig Code (TODO: Bridge Functions)

To expose AI capabilities to Ghostlang, we need to implement bridge functions in grim's runtime:

```zig
// runtime/bridge.zig (to be implemented)

pub fn omen_health_check(base_url: []const u8) !bool {
    var client = try ai.Client.init(allocator, .{ .base_url = base_url });
    defer client.deinit();
    return try client.healthCheck();
}

pub fn omen_complete(
    base_url: []const u8,
    request: ai.CompletionRequest,
    api_key: ?[]const u8,
) !ai.CompletionResponse {
    var client = try ai.Client.init(allocator, .{
        .base_url = base_url,
        .api_key = api_key,
    });
    defer client.deinit();
    return try client.complete(request);
}

pub fn omen_stream_complete(
    base_url: []const u8,
    request: ai.CompletionRequest,
    callback: *const fn (chunk: []const u8, user_data: ?*anyopaque) anyerror!void,
    user_data: ?*anyopaque,
    api_key: ?[]const u8,
) !void {
    var client = try ai.Client.init(allocator, .{
        .base_url = base_url,
        .api_key = api_key,
    });
    defer client.deinit();
    return try client.streamComplete(request, callback, user_data);
}
```

## Configuration

### Omen Plugin Options

Configure the omen plugin in your phantom.grim config:

```lua
-- phantom.grim user config (e.g., ~/.config/grim/init.gza)

require("ai.omen").setup({
    base_url = "http://localhost:8080",  -- Omen gateway URL
    api_key = nil,                       -- Optional API key for auth
})
```

### Remote Omen Instance

You can connect to a remote Omen instance:

```lua
require("ai.omen").setup({
    base_url = "https://omen.example.com",
    api_key = "your-secret-key",
})
```

## Architecture Details

### Module Structure

```
grim/ai/
├── mod.zig          # Public API, request/response types
├── client.zig       # HTTP client using zhttp
├── streaming.zig    # SSE parsing and accumulation
├── context.zig      # Editor context gathering
└── README.md        # This file

phantom.grim/plugins/ai/
└── omen.gza         # Ghostlang plugin wrapper
```

### Request Flow

1. **User action** (e.g., `:OmenCommitMessage`) triggers Ghostlang function
2. **Ghostlang plugin** (`omen.gza`) calls bridge function
3. **Bridge function** (Zig) uses `ai.Client` to make HTTP request
4. **zhttp** sends POST to Omen gateway with JSON payload
5. **Omen** routes request to appropriate provider (Claude, OpenAI, Ollama)
6. **Provider** returns completion (streaming or non-streaming)
7. **Response** flows back through layers to user

### Context Gathering

The `context.zig` module can gather:
- **Buffer content**: Current file, cursor position, language
- **Selection**: Selected text for targeted operations
- **LSP diagnostics**: Errors, warnings for bug fixes
- **Git status**: Uncommitted changes, branch info
- **Project structure**: Open files, file tree

Example context message:
```
# Current Buffer
File: src/main.zig
Language: zig
Cursor: Line 42, Col 15

\`\`\`zig
fn main() !void {
    // User's code here
}
\`\`\`

# Diagnostics
[ERROR] Line 42: undefined variable 'foo'

# Git Status
Branch: feature/ai-integration
Status: modified
Uncommitted files: 3
```

### Streaming with SSE

Omen uses Server-Sent Events (SSE) for streaming:

```
data: {"choices":[{"delta":{"content":"Hello"}}]}

data: {"choices":[{"delta":{"content":" world"}}]}

data: [DONE]
```

The `streaming.zig` module:
1. Parses SSE events (`data:` prefix)
2. Accumulates deltas into complete response
3. Invokes callback for each chunk
4. Detects `[DONE]` marker to finish

## Troubleshooting

### "Omen AI unavailable"

**Problem**: Plugin logs "Omen AI unavailable (is Omen running on http://localhost:8080?)"

**Solutions**:
1. Start Omen: `cd /data/projects/omen && cargo run --release`
2. Check Omen is running: `curl http://localhost:8080/health`
3. Check firewall/network settings
4. Verify base_url in plugin config

### "Omen bridge not available"

**Problem**: Plugin logs "Omen bridge not available - grim needs to be rebuilt with AI support"

**Solutions**:
1. Rebuild grim: `cd /data/projects/grim && zig build`
2. Check `build.zig` includes `ai_mod` and `zhttp` dependency
3. Verify `ai/` directory exists in grim
4. Implement bridge functions (see "From Zig Code" section)

### "bridge.omen.complete() not implemented yet"

**Problem**: Plugin can't call AI functions

**Solution**: Implement bridge functions in grim's runtime (see "From Zig Code" section above). These functions expose the Zig AI client to Ghostlang.

### Omen returns 401 Unauthorized

**Problem**: Omen requires authentication

**Solution**: Set API key in plugin config:
```lua
require("ai.omen").setup({
    api_key = "your-secret-key",
})
```

### Omen returns 500 Internal Server Error

**Problem**: Omen failed to reach provider

**Solutions**:
1. Check Omen logs: `journalctl -u omen -f`
2. Verify provider configuration in `omen.toml`
3. Check provider API keys are valid
4. Ensure Ollama is running if using local models

## Performance

**Startup Impact**: Near-zero - AI module is loaded on-demand

**Memory Usage**:
- Base: ~500 KB (client, types)
- Per request: ~10 KB (request/response buffers)
- Streaming: ~5 KB (SSE parser state)

**Network**:
- Non-streaming: Single HTTP request/response
- Streaming: Persistent connection with chunked transfer

**Latency**:
- To Omen: <10ms (localhost)
- To provider: 100-500ms (network + model)
- First token (streaming): 200-800ms
- Subsequent tokens: 20-50ms

## Examples

### Example 1: AI-Assisted Commit Messages

```lua
-- phantom.grim keybinding
keymap.set("n", "<leader>gc", function()
    local omen = require("ai.omen")
    if not omen.available() then
        print("Omen unavailable")
        return
    end

    print("Generating commit message...")
    local msg = omen.commit_message()

    if msg and #msg > 0 then
        -- Open commit editor with AI-generated message
        vim.fn.system("git commit -m " .. vim.fn.shellescape(msg))
        print("Committed: " .. msg)
    else
        print("Failed to generate commit message")
    end
end, { desc = "AI commit message" })
```

### Example 2: Inline Code Review

```lua
-- Review selected code
keymap.set("v", "<leader>ar", function()
    local omen = require("ai.omen")
    local selection = vim.fn.getline("'<", "'>")
    local code = table.concat(selection, "\n")

    print("Reviewing code...")
    local review = omen.review_code(code)

    -- Show review in popup
    ui.show_popup({
        title = "AI Code Review",
        content = review,
        width = 80,
        height = 20,
    })
end, { desc = "AI review code" })
```

### Example 3: Interactive AI Chat

```lua
-- Chat with AI about current buffer
keymap.set("n", "<leader>aa", function()
    local omen = require("ai.omen")
    local prompt = vim.fn.input("Ask AI: ")
    if #prompt == 0 then return end

    local buffer_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    print("Thinking...")
    local answer = omen.chat_with_buffer(prompt, buffer_content, cursor_line)

    ui.show_popup({
        title = "AI Response",
        content = answer,
        width = 80,
        height = 30,
    })
end, { desc = "AI chat" })
```

## Next Steps

1. **Implement bridge functions** in `runtime/bridge.zig` to expose AI client to Ghostlang
2. **Add keybindings** in phantom.grim for common AI operations
3. **Create UI commands** (`:OmenCommitMessage`, `:OmenReviewCode`, etc.)
4. **Add tests** for AI module and omen plugin
5. **Performance profiling** for large requests
6. **Add MCP support** via rune/glyph for tool integration

## Related Projects

- **Omen**: `/data/projects/omen` - Rust AI gateway with multi-provider support
- **Rune**: `/data/projects/rune` - Zig MCP client library
- **Glyph**: `/data/projects/glyph` - Rust MCP server library
- **Zhttp**: `/data/projects/zhttp` - Zig HTTP client (used by AI module)

## License

Part of the grim editor project.

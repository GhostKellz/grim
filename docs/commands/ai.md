# AI Commands Reference

AI-powered commands via the **thanos.grim** plugin.

## Overview

Grim integrates with multiple AI providers through the Thanos gateway:
- **GitHub Copilot** - Code completion (if subscribed)
- **Anthropic Claude** - Best for complex reasoning
- **OpenAI GPT-4** - General-purpose AI
- **xAI Grok** - Fast, conversational
- **Ollama** - Local, privacy-focused (FREE)

## Configuration

### API Keys

Configure API keys in `~/.config/grim/ai.toml`:

```toml
[providers.anthropic]
enabled = true
api_key = "sk-ant-..."  # Or use env: ${ANTHROPIC_API_KEY}
model = "claude-sonnet-4-20250514"

[providers.openai]
enabled = true
api_key = "sk-..."  # Or use env: ${OPENAI_API_KEY}
model = "gpt-4"

[providers.xai]
enabled = true
api_key = "xai-..."  # Or use env: ${XAI_API_KEY}
model = "grok-beta"

[providers.github_copilot]
enabled = true
# Uses GitHub auth - run: gh auth login

[providers.ollama]
enabled = true
endpoint = "http://localhost:11434"
model = "codellama:latest"
```

### Environment Variables

You can also use environment variables:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export XAI_API_KEY="xai-..."
```

## Commands

### `:ThanosComplete`

AI-powered code completion at cursor position.

**Keybind:** `<leader>ak` or `Ctrl-Space` (context-aware)

**Usage:**
```vim
:ThanosComplete
```

**Example:**
```zig
fn fibonacci(n: usize) usize {
    // Place cursor here and run :ThanosComplete
    <cursor>
}
```

**Behavior:**
- Uses context from current buffer
- Respects language syntax
- Inline ghost text preview
- Accepts with `Tab`, rejects with `Esc`

---

### `:ThanosChat`

Open interactive AI chat window.

**Keybind:** `<leader>ac`

**Usage:**
```vim
:ThanosChat
```

**Chat Window Controls:**
- `<Enter>` - Send message
- `q` - Close chat
- `i` - Insert mode (type message)
- `<Esc>` - Normal mode

**Example Session:**
```
# Thanos AI Chat

Provider: claude

Type your message...

**You:** How do I implement a linked list in Zig?

**Claude:** Here's a basic linked list implementation:

```zig
const Node = struct {
    data: i32,
    next: ?*Node,
};
```

**You:** Can you add a push method?
```

---

### `:ThanosAsk <message>`

Ask AI a quick question (inline response).

**Usage:**
```vim
:ThanosAsk How do I read a file in Zig?
:ThanosAsk What does this error mean: use of undeclared identifier
```

**Example:**
```vim
:ThanosAsk Explain the difference between allocator.alloc and allocator.create
```

**Response shown in popup window.**

---

### `:ThanosSwitch <provider>`

Switch active AI provider.

**Keybind:** `<leader>ap`

**Usage:**
```vim
:ThanosSwitch ollama
:ThanosSwitch claude
:ThanosSwitch gpt4
:ThanosSwitch copilot
:ThanosSwitch grok
```

**Valid Providers:**
- `ollama` - Local Ollama instance (FREE)
- `claude` / `anthropic` - Anthropic Claude
- `gpt4` / `openai` - OpenAI GPT-4
- `copilot` / `github_copilot` - GitHub Copilot
- `grok` / `xai` - xAI Grok

**Example:**
```vim
" Switch to local Ollama for fast, free completions
:ThanosSwitch ollama

" Switch to Claude for complex reasoning
:ThanosSwitch claude

" Use Copilot subscription for GPT-4 access
:ThanosSwitch copilot
```

**Status line updates** to show current provider: `AI: ollama`

---

### `:ThanosProviders`

List all available AI providers and their health status.

**Usage:**
```vim
:ThanosProviders
```

**Example Output:**
```
# Available AI Providers

✅ ollama (available) - 21 models, 4ms latency
❌ anthropic (unavailable) - API key not configured
❌ openai (unavailable) - API key not configured
✅ copilot (available) - GitHub authenticated
❌ xai (unavailable) - API key not configured
```

---

### `:ThanosStats`

Show AI usage statistics.

**Keybind:** `<leader>as`

**Usage:**
```vim
:ThanosStats
```

**Example Output:**
```
# Thanos Statistics

**Current Provider:** ollama

Providers: 2 available
Total Requests: 47
Avg Latency: 127ms
Cache Hit Rate: 34%
Total Cost: $0.00 (local Ollama)
```

---

### `:ThanosExplain`

Explain selected code or current buffer.

**Keybind:** `<leader>ae`

**Usage:**
```vim
" Visual mode: Select code, then
:ThanosExplain

" Or in normal mode (explains whole buffer)
:ThanosExplain
```

**Example:**
```zig
// Select this code and run :ThanosExplain
const allocator = std.heap.page_allocator;
const list = try allocator.alloc(u8, 100);
defer allocator.free(list);
```

**AI Response:**
```
This code allocates 100 bytes of memory using a page allocator,
stores the slice in `list`, and ensures the memory is freed when
the scope ends using `defer`.
```

---

### `:ThanosReview`

Review current buffer for bugs, security issues, and code quality.

**Keybind:** `<leader>ar`

**Usage:**
```vim
:ThanosReview
```

**Reviews:**
- Potential bugs
- Security vulnerabilities
- Performance issues
- Code style
- Best practices

**Example Output:**
```
# Code Review

**Issues Found:**

1. **Memory Leak** (line 23)
   Missing `defer allocator.free(buffer)`

2. **Unsafe Cast** (line 45)
   Using @ptrCast without alignment check

3. **Error Handling** (line 67)
   `catch unreachable` - consider proper error handling

**Suggestions:**
- Add bounds checking for array access (line 34)
- Consider using ArrayList instead of manual allocation
```

---

### `:ThanosCommit`

Generate AI commit message from staged changes.

**Usage:**
```vim
:ThanosCommit
```

**Workflow:**
1. Stage changes: `git add .`
2. Run `:ThanosCommit`
3. Review AI-generated message
4. Commit opens with message pre-filled

**Example Generated Message:**
```
feat: add AI code completion with multi-provider support

- Integrate thanos.grim plugin
- Add Ollama, Claude, GPT-4 providers
- Implement code completion and chat UI
- Add keybindings for AI commands

Uses Omen gateway for cost-optimized routing.
```

---

## Keybindings Summary

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>ac` | ThanosChat | Open AI chat |
| `<leader>ak` | ThanosComplete | AI complete code |
| `<leader>ap` | ThanosSwitch | Switch provider |
| `<leader>as` | ThanosStats | Show statistics |
| `<leader>ae` | ThanosExplain | Explain code |
| `<leader>ar` | ThanosReview | Review code |

**Leader key:** `Space`

---

## Provider Selection Strategy

### When to Use Each Provider

**Ollama (Local):**
- ✅ Fast completions (<500ms)
- ✅ Free, unlimited usage
- ✅ Privacy (no data leaves machine)
- ❌ Less powerful for complex reasoning

**GitHub Copilot:**
- ✅ Best for code completion
- ✅ GPT-4/Codex access if subscribed
- ✅ Trained on GitHub code
- ❌ Requires subscription

**Anthropic Claude:**
- ✅ Best reasoning and code understanding
- ✅ Long context (200K tokens)
- ✅ Excellent at refactoring
- ❌ Costs $0.003/1K tokens (input)

**OpenAI GPT-4:**
- ✅ General-purpose AI
- ✅ Good for explanations
- ❌ Costs $0.03/1K tokens (input)

**xAI Grok:**
- ✅ Fast, conversational
- ✅ Real-time information
- ❌ Costs $0.015/1K tokens

### Recommended Workflow

1. **Default:** Ollama (fast, free)
2. **Complex tasks:** Switch to Claude
3. **Explanations:** GPT-4 or Copilot
4. **Code completion:** Copilot or Ollama

---

## Cost Optimization

### Omen Gateway

Thanos routes requests through Omen for:
- **Caching** - Identical requests cached (30min TTL)
- **Fallback** - Auto-switch if provider fails
- **Rate limiting** - Prevent API overuse
- **Cost tracking** - Monitor spending

### Configuration

`~/.config/grim/ai.toml`:

```toml
[routing]
strategy = "cost-optimized"  # or "latency-optimized", "quality-optimized"
fallback_chain = ["ollama", "copilot", "anthropic"]
enable_caching = true
cache_ttl_minutes = 30
```

---

## Troubleshooting

### Provider Unavailable

**Issue:** `:ThanosProviders` shows provider as unavailable

**Solutions:**
1. Check API key in `~/.config/grim/ai.toml`
2. Verify environment variables: `echo $ANTHROPIC_API_KEY`
3. Test Omen health: `curl http://localhost:8080/health`
4. Check Ollama: `curl http://localhost:11434/api/tags`

### Slow Completions

**Issue:** AI completions take >5 seconds

**Solutions:**
1. Switch to Ollama for faster local inference
2. Reduce `max_tokens` in config
3. Check network latency to API providers
4. Enable caching in Omen config

### GitHub Copilot Not Working

**Issue:** Copilot provider unavailable

**Solutions:**
1. Authenticate with GitHub: `gh auth login`
2. Check Copilot subscription: https://github.com/settings/copilot
3. Verify thanos.grim has Copilot support compiled in

---

## See Also

- [Configuration Guide](../configuration.md)
- [Plugin Development](../PLUGIN_DEVELOPMENT_GUIDE.md)
- [Thanos Gateway](https://github.com/ghostkellz/thanos)
- [Omen Router](https://github.com/ghostkellz/omen)

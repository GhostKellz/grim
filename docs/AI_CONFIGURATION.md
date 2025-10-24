# AI Configuration System

Flexible multi-provider AI configuration for Grim editor.

## Overview

Grim supports multiple AI providers with flexible API key management:
- **Direct API Keys** - Use your own Anthropic, OpenAI, xAI keys
- **GitHub Copilot** - Leverage your Copilot subscription
- **Omen Gateway** - Cost-optimized routing through local Omen instance
- **Ollama** - Free, local inference

## Configuration File

Location: `~/.config/grim/ai.toml`

```toml
[general]
debug = false
preferred_provider = "ollama"  # Default provider
routing_mode = "manual"  # or "auto", "cost-optimized"

# Anthropic Claude
[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"  # Or direct: "sk-ant-..."

# Available models
models = [
    "claude-sonnet-4.5-20250514",  # Latest Sonnet 4.5
    "claude-sonnet-4-20250514",    # Sonnet 4
    "claude-opus-4-20250514",      # Opus 4 (most powerful)
    "claude-haiku-4.5-20250514",   # Haiku 4.5 (fastest)
]
default_model = "claude-sonnet-4.5-20250514"

# Pricing (per 1M tokens)
pricing = { input = 3.00, output = 15.00 }

# OpenAI GPT
[providers.openai]
enabled = true
api_key = "${OPENAI_API_KEY}"

models = [
    "gpt-5",                    # GPT-5 (if available)
    "gpt-4-turbo",              # GPT-4 Turbo
    "gpt-4",                    # GPT-4
    "codex",                    # Codex (code-specific)
    "gpt-4-vision",             # Multimodal
]
default_model = "gpt-5"

pricing = { input = 30.00, output = 60.00 }

# xAI Grok
[providers.xai]
enabled = true
api_key = "${XAI_API_KEY}"

models = [
    "grok-code",                # Code-specific Grok
    "grok-beta",                # General Grok
    "grok-vision",              # Multimodal
]
default_model = "grok-code"

pricing = { input = 15.00, output = 30.00 }

# GitHub Copilot
[providers.github_copilot]
enabled = true
# Uses GitHub CLI authentication (gh auth login)
# Requires active Copilot subscription

models = [
    "copilot-gpt4",             # GPT-4 via Copilot
    "copilot-codex",            # Codex via Copilot
]
default_model = "copilot-gpt4"

# Free via subscription
pricing = { input = 0.00, output = 0.00 }

# Ollama (Local)
[providers.ollama]
enabled = true
endpoint = "http://localhost:11434"

models = [
    "codellama:latest",
    "deepseek-coder:latest",
    "starcoder:latest",
    "mistral:latest",
]
default_model = "codellama:latest"

# Free (local inference)
pricing = { input = 0.00, output = 0.00 }

# Omen Gateway (Routing)
[providers.omen]
enabled = true
endpoint = "http://localhost:8080"
routing_strategy = "cost-optimized"  # or "latency-optimized", "quality-optimized"

# Omen routes to these providers
preferred_providers = ["ollama", "copilot", "anthropic", "openai", "xai"]

# Fallback chain
fallback_chain = ["ollama", "copilot", "anthropic"]

# Request settings
[completion]
max_tokens = 150                    # Code completion
temperature = 0.2                   # Deterministic for code
show_inline = true                  # Ghost text preview
trigger_on_keystroke = false        # Manual trigger (Ctrl+Space)

[chat]
max_tokens = 500
temperature = 0.7
context_lines_before = 50
context_lines_after = 10
include_diagnostics = true          # Include LSP errors

# Caching
[cache]
enabled = true
ttl_minutes = 30
max_size_mb = 100

# Cost tracking
[budget]
enabled = true
daily_limit_usd = 10.00
monthly_limit_usd = 100.00
alert_threshold = 0.8               # Alert at 80% of limit

# Routing rules
[routing]
# Use Ollama for simple completions
simple_completion_provider = "ollama"

# Use Claude for complex reasoning
complex_reasoning_provider = "anthropic"
complex_reasoning_model = "claude-opus-4-20250514"

# Use Copilot/Codex for code generation
code_generation_provider = "github_copilot"

# Use Grok for real-time info
realtime_provider = "xai"
```

## Environment Variables

Instead of hardcoding API keys, use environment variables:

**`.bashrc` / `.zshrc`:**
```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
export OPENAI_API_KEY="sk-..."
export XAI_API_KEY="xai-..."
```

**`.env` (for Omen Docker container):**
```bash
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
XAI_API_KEY=xai-...
```

## Model Selection

### Anthropic Claude Models

| Model | Use Case | Context | Cost (per 1M tokens) |
|-------|----------|---------|----------------------|
| **Claude Opus 4** | Complex reasoning, refactoring | 200K | $15 / $75 |
| **Claude Sonnet 4.5** | Balanced (best default) | 200K | $3 / $15 |
| **Claude Sonnet 4** | Balanced (cheaper) | 200K | $3 / $15 |
| **Claude Haiku 4.5** | Fast, simple tasks | 200K | $0.25 / $1.25 |

**When to use:**
- **Opus 4:** Architecture design, complex refactoring, code review
- **Sonnet 4.5:** General code completion, explanations (best default)
- **Haiku 4.5:** Fast completions, simple questions

---

### OpenAI GPT Models

| Model | Use Case | Context | Cost (per 1M tokens) |
|-------|----------|---------|----------------------|
| **GPT-5** | Next-gen AI (if available) | TBD | TBD |
| **GPT-4 Turbo** | Fast, cost-effective GPT-4 | 128K | $10 / $30 |
| **GPT-4** | General-purpose AI | 8K | $30 / $60 |
| **Codex** | Code-specific model | 8K | $0 (via Copilot) |

**When to use:**
- **GPT-5:** Cutting-edge capabilities
- **GPT-4 Turbo:** Balanced performance and cost
- **Codex:** Code completion (via Copilot subscription)

---

### xAI Grok Models

| Model | Use Case | Context | Cost (per 1M tokens) |
|-------|----------|---------|----------------------|
| **Grok Code** | Code-specific | TBD | $15 / $30 |
| **Grok Beta** | General AI | TBD | $15 / $30 |

**When to use:**
- **Grok Code:** Code generation, debugging
- **Grok Beta:** General questions, explanations

---

### GitHub Copilot

| Model | Use Case | Cost |
|-------|----------|------|
| **Copilot GPT-4** | GPT-4 via subscription | FREE* |
| **Copilot Codex** | Code completion | FREE* |

\* Requires GitHub Copilot subscription ($10/month individual, $19/month business)

**When to use:**
- If you have Copilot subscription, use it for FREE GPT-4/Codex access
- Best for code completion
- Trained on GitHub code

---

### Ollama (Local)

| Model | Use Case | Size | Cost |
|-------|----------|------|------|
| **CodeLlama** | Code completion | 7B-34B | FREE |
| **DeepSeek Coder** | Code generation | 6.7B-33B | FREE |
| **StarCoder** | Code completion | 15B | FREE |

**When to use:**
- **Always try first** (free, fast, private)
- Fallback to cloud for complex tasks
- No internet required

---

## Provider Switching

### Manual Switching

```vim
:ThanosSwitch ollama            " Fast, free
:ThanosSwitch copilot           " Copilot subscription
:ThanosSwitch anthropic         " Claude Sonnet 4.5
:ThanosSwitch openai            " GPT-4/5
:ThanosSwitch xai               " Grok
```

### Auto-Routing (via Omen)

Set `routing_mode = "auto"` in `ai.toml`:

```toml
[general]
routing_mode = "auto"

[routing]
# Simple completions → Ollama (free)
simple_completion_provider = "ollama"

# Complex reasoning → Claude Opus 4
complex_reasoning_provider = "anthropic"
complex_reasoning_model = "claude-opus-4-20250514"

# Code generation → Copilot (free via subscription)
code_generation_provider = "github_copilot"
```

**Omen decides based on:**
- Prompt complexity
- Token count
- Available budget
- Provider health

---

## Cost Optimization Strategies

### 1. **Ollama-First**

Use Ollama for everything, fallback to cloud only when needed.

```toml
[general]
preferred_provider = "ollama"

[routing]
fallback_chain = ["ollama", "copilot", "anthropic"]
```

**Savings:** 90%+ (most tasks work fine with local models)

---

### 2. **Copilot-First (if subscribed)**

Use Copilot for code tasks (free via subscription), Claude for reasoning.

```toml
[routing]
code_generation_provider = "github_copilot"
complex_reasoning_provider = "anthropic"
complex_reasoning_model = "claude-sonnet-4.5-20250514"  # Cheaper than Opus
```

**Savings:** 50-70% (Copilot subscription pays for itself)

---

### 3. **Budget Limits**

Set daily/monthly spending limits:

```toml
[budget]
enabled = true
daily_limit_usd = 5.00
monthly_limit_usd = 50.00
alert_threshold = 0.8  # Alert at 80%
```

**Behavior:**
- Tracks API costs in real-time
- Switches to free providers when limit reached
- Alerts before hitting limit

---

### 4. **Caching**

Enable aggressive caching:

```toml
[cache]
enabled = true
ttl_minutes = 60        # Cache for 1 hour
max_size_mb = 500       # Large cache
```

**Savings:** 30-50% (repeated requests cached)

---

## Setup Guide

### Step 1: Install Omen (Optional but Recommended)

```bash
cd /data/projects/omen
docker-compose up -d
```

**Verify:**
```bash
curl http://localhost:8080/health
```

---

### Step 2: Configure API Keys

Create `~/.config/grim/ai.toml`:

```toml
[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"

[providers.openai]
enabled = true
api_key = "${OPENAI_API_KEY}"

[providers.xai]
enabled = true
api_key = "${XAI_API_KEY}"

[providers.github_copilot]
enabled = true  # Requires: gh auth login
```

**Set environment variables:**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export XAI_API_KEY="xai-..."
```

---

### Step 3: Authenticate GitHub Copilot

```bash
gh auth login
```

**Verify:**
```bash
gh copilot status
```

---

### Step 4: Test Providers

```vim
:ThanosProviders
```

**Expected Output:**
```
✅ ollama (available) - 21 models
✅ copilot (available) - GitHub authenticated
✅ anthropic (available) - API key configured
✅ openai (available) - API key configured
✅ xai (available) - API key configured
```

---

### Step 5: Test Completion

```vim
:ThanosSwitch ollama
:ThanosComplete
```

**Try different providers:**
```vim
:ThanosSwitch anthropic
:ThanosAsk Explain this code
```

---

## Workflow Examples

### Example 1: Cost-Conscious Developer

**Goal:** Minimize costs, use free providers first

**Config:**
```toml
[general]
preferred_provider = "ollama"
routing_mode = "manual"

[budget]
daily_limit_usd = 1.00
```

**Workflow:**
1. Use Ollama for everything
2. Switch to Copilot if subscribed
3. Use Claude only for complex refactoring

---

### Example 2: Copilot Subscriber

**Goal:** Maximize Copilot subscription value

**Config:**
```toml
[general]
preferred_provider = "github_copilot"

[routing]
code_generation_provider = "github_copilot"
complex_reasoning_provider = "anthropic"
complex_reasoning_model = "claude-sonnet-4.5-20250514"
```

**Workflow:**
1. Use Copilot GPT-4/Codex for code (FREE)
2. Use Claude Sonnet 4.5 for complex reasoning (cheap)
3. Ollama as fallback

**Cost:** ~$10-20/month (mostly Copilot subscription)

---

### Example 3: Professional Developer

**Goal:** Best quality, willing to pay

**Config:**
```toml
[general]
preferred_provider = "anthropic"
routing_mode = "auto"

[providers.anthropic]
default_model = "claude-opus-4-20250514"  # Most powerful

[budget]
monthly_limit_usd = 200.00
```

**Workflow:**
1. Use Claude Opus 4 for everything
2. GPT-5 for second opinions
3. Omen handles routing

**Cost:** $100-200/month (heavy usage)

---

## Troubleshooting

### Provider Unavailable

**Check API key:**
```bash
echo $ANTHROPIC_API_KEY
```

**Test API:**
```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4.5-20250514","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'
```

---

### Cost Tracking Not Working

**Check Omen health:**
```bash
curl http://localhost:8080/health
```

**View Omen logs:**
```bash
docker logs omen
```

---

### Copilot Not Working

**Authenticate:**
```bash
gh auth login
gh copilot status
```

**Check subscription:**
https://github.com/settings/copilot

---

## See Also

- [AI Commands](commands/ai.md)
- [Thanos Gateway](https://github.com/ghostkellz/thanos)
- [Omen Router](https://github.com/ghostkellz/omen)
- [Anthropic API](https://docs.anthropic.com/)
- [OpenAI API](https://platform.openai.com/docs/)
- [GitHub Copilot](https://github.com/features/copilot)

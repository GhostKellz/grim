# Zap AI Integration

Grim now includes **Zap** - AI-powered git and coding features using local Ollama models.

## Features

### Git Operations
- **AI Commit Messages** - Generate conventional commit messages from diffs
- **Change Explanations** - Understand what changed between commits
- **Merge Conflict Resolution** - AI-suggested conflict resolutions

### Code Quality
- **Code Review** - AI-powered code review with actionable feedback
- **Issue Detection** - Find potential bugs, security issues, performance problems
- **Documentation Generation** - Auto-generate doc comments
- **Name Suggestions** - Better variable/function names following conventions

## Setup

### 1. Install Ollama

```bash
# Install Ollama
curl https://ollama.ai/install.sh | sh

# Pull a coding model
ollama pull deepseek-coder:33b
# or
ollama pull codellama:34b
```

### 2. Start Ollama

```bash
ollama serve
```

Ollama runs on `http://localhost:11434` by default.

### 3. Use in Grim

#### From Ghostlang Plugins (`.gza`)

```javascript
// Initialize Zap
if (!grim_zap_init()) {
    print("Zap not available");
    exit(1);
}

// Check availability
if (grim_zap_available()) {
    // Generate commit message
    const diff = grim_git_diff_staged();
    const message = grim_zap_commit_message(diff);
    print(message);
}
```

#### Available FFI Functions

```javascript
// Core
grim_zap_init()                        // Initialize Zap
grim_zap_available()                   // Check if Ollama is running

// Git Features
grim_zap_commit_message(diff)          // Generate commit message
grim_zap_explain_changes(changes)      // Explain what changed
grim_zap_resolve_conflict(conflict)    // Suggest conflict resolution

// Code Quality
grim_zap_review_code(code)             // AI code review
grim_zap_generate_docs(code)           // Generate documentation
grim_zap_suggest_names(code)           // Suggest better names
grim_zap_detect_issues(code)           // Find potential issues
```

## Example Plugin

See `examples/plugins/ai_commit.gza` for a complete example:

```bash
# Load the plugin
./grim --plugin examples/plugins/ai_commit.gza

# Use commands
:AICommit   # Generate commit message
:AIExplain  # Explain recent changes
:AIReview   # Review current file
```

## Configuration

Default Ollama config:
- Host: `http://localhost:11434`
- Model: `deepseek-coder:33b`
- Timeout: 30 seconds

To customize, create a config in your `.gza` init file:

```javascript
const config = {
    host: "http://localhost:11434",
    model: "codellama:34b",
    timeout_ms: 60000
};

grim_zap_init_with_config(config);
```

## Performance Tips

1. **Use smaller models for speed**: `deepseek-coder:6.7b` vs `deepseek-coder:33b`
2. **GPU acceleration**: Ollama uses GPU if available
3. **Stream responses**: Enable streaming for long responses (coming soon)

## Troubleshooting

### "Zap AI not available"
- Ensure Ollama is installed: `ollama --version`
- Check if Ollama is running: `curl http://localhost:11434`
- Verify model is pulled: `ollama list`

### Slow responses
- Use a smaller model
- Check GPU usage: `nvidia-smi` (if using NVIDIA)
- Reduce max tokens in prompts

### Connection errors
- Firewall blocking port 11434
- Ollama running on different port (update config)
- Network proxy issues

## Future Enhancements

- [ ] Streaming responses
- [ ] Custom model configuration per feature
- [ ] Multi-model support (OpenAI, Anthropic, etc.)
- [ ] Caching for repeated queries
- [ ] Fine-tuned models for specific languages

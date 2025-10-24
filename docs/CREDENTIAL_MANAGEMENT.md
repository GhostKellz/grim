# Credential Management System

Built-in API key and authentication management for Grim.

## Overview

Grim provides first-class credential management so AI features work **out of the box**:
- Secure storage (system keyring)
- OAuth flows (GitHub Copilot)
- Auto-detection (Ollama)
- First-run setup wizard
- Cross-plugin sharing

## Architecture

```
┌─────────────────────────────────────────┐
│ Grim Core (credential manager)          │
│  - :ApiKey command                      │
│  - :GithubLogin OAuth                   │
│  - :GrimSetup wizard                    │
│  - Keyring integration                  │
└──────────────┬──────────────────────────┘
               │
               ├──────────┬──────────┬────────────┐
               ▼          ▼          ▼            ▼
         thanos.grim   future.ai   other      LSP with
           plugin      plugins     plugins   cloud features
```

**Key Principle:** Grim owns credentials, plugins consume them.

## User Experience

### First Launch

```
$ grim

┌──────────────────────────────────────────────────┐
│ Welcome to Grim!                                 │
│                                                  │
│ Let's set up AI assistance. (Skip with Ctrl+C)  │
│                                                  │
│ [1/5] Detecting Ollama...                       │
│   ✅ Ollama found at localhost:11434            │
│   ✅ 21 models available (codellama, etc.)      │
│                                                  │
│ [2/5] GitHub Copilot                            │
│   Do you have a GitHub Copilot subscription?    │
│   > [Y]es  [N]o  [S]kip                         │
│                                                  │
│   (Opens browser for OAuth...)                  │
│   ✅ GitHub authenticated                       │
│   ✅ Copilot access granted                     │
│                                                  │
│ [3/5] Anthropic Claude API                      │
│   Enter API key (or press Enter to skip):       │
│   > sk-ant-api03-****************************** │
│   ✅ API key validated                          │
│                                                  │
│ [4/5] OpenAI API                                │
│   Enter API key (or press Enter to skip):       │
│   > sk-************************************************│
│   ✅ API key validated                          │
│                                                  │
│ [5/5] xAI Grok API                              │
│   Enter API key (or press Enter to skip):       │
│   > [SKIP]                                      │
│                                                  │
│ Setup complete! 🎉                              │
│                                                  │
│ Available providers:                            │
│  ✅ Ollama (local, free)                        │
│  ✅ GitHub Copilot (subscription)               │
│  ✅ Anthropic Claude                            │
│  ✅ OpenAI GPT                                  │
│                                                  │
│ Try: :ThanosComplete                            │
└──────────────────────────────────────────────────┘
```

**After setup:**
- Credentials stored in system keyring
- AI commands work immediately
- No manual config files needed

---

## Commands

### `:GrimSetup`

Run first-time setup wizard.

**Usage:**
```vim
:GrimSetup
```

**Workflow:**
1. Detect Ollama
2. GitHub OAuth
3. Anthropic API key
4. OpenAI API key
5. xAI API key
6. Save to keyring
7. Test all providers

---

### `:ApiKey <provider> [key]`

Set or view API keys.

**Usage:**
```vim
:ApiKey anthropic sk-ant-...     " Set Anthropic key
:ApiKey openai sk-...            " Set OpenAI key
:ApiKey xai xai-...              " Set xAI key
:ApiKey list                     " List configured providers
:ApiKey anthropic                " View Anthropic key (masked)
:ApiKey delete openai            " Delete OpenAI key
```

**Examples:**
```vim
" Set API keys
:ApiKey anthropic sk-ant-api03-xxxxx
✅ Anthropic API key saved securely

" View configured providers
:ApiKey list
✅ anthropic (configured)
✅ openai (configured)
❌ xai (not configured)

" View specific key (masked)
:ApiKey anthropic
Anthropic API Key: sk-ant-api03-***************************
```

**Security:**
- Keys never stored in plaintext
- Saved to system keyring
- Masked in UI

---

### `:GithubLogin`

Authenticate with GitHub for Copilot access.

**Usage:**
```vim
:GithubLogin
```

**OAuth Flow:**
1. Opens browser to GitHub OAuth page
2. User authorizes Grim
3. Callback captures token
4. Token saved to keyring
5. Test Copilot API

**Example:**
```vim
:GithubLogin

┌──────────────────────────────────────┐
│ GitHub Authentication                │
│                                      │
│ Opening browser...                   │
│ Please authorize Grim.               │
│                                      │
│ Waiting for callback...              │
│ (Press Ctrl+C to cancel)             │
└──────────────────────────────────────┘

✅ GitHub authenticated
✅ Copilot access verified
```

**Alternative (if gh CLI installed):**
```vim
:GithubLogin --use-gh-cli

✅ Using existing gh CLI authentication
✅ Copilot access verified
```

---

### `:OllamaDetect`

Auto-detect local Ollama installation.

**Usage:**
```vim
:OllamaDetect
```

**Detection:**
1. Check `localhost:11434`
2. Check `OLLAMA_HOST` env var
3. List available models
4. Save endpoint

**Example Output:**
```
Detecting Ollama...

✅ Ollama found at localhost:11434
✅ 21 models available:
   - codellama:latest
   - deepseek-coder:latest
   - mistral:latest
   - starcoder:latest
   - ... (17 more)

Ollama configured successfully.
```

---

### `:ApiKeyExport`

Export API keys to `.env` file (for Omen Docker).

**Usage:**
```vim
:ApiKeyExport
:ApiKeyExport ~/.config/omen/.env
```

**Generated `.env`:**
```bash
# Generated by Grim - DO NOT COMMIT
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
XAI_API_KEY=xai-...
```

**Use case:** Running Omen in Docker needs env vars.

---

## Implementation

### Core Module: `core/credentials.zig`

```zig
const std = @import("std");

pub const CredentialManager = struct {
    allocator: std.mem.Allocator,
    keyring: Keyring,

    /// Supported providers
    pub const Provider = enum {
        anthropic,
        openai,
        xai,
        github_copilot,
        ollama,
    };

    pub fn init(allocator: std.mem.Allocator) !*CredentialManager {
        const self = try allocator.create(CredentialManager);
        self.* = .{
            .allocator = allocator,
            .keyring = try Keyring.init(allocator),
        };
        return self;
    }

    /// Set API key for provider
    pub fn setApiKey(
        self: *CredentialManager,
        provider: Provider,
        key: []const u8,
    ) !void {
        const key_name = try std.fmt.allocPrint(
            self.allocator,
            "grim.api.{s}",
            .{@tagName(provider)},
        );
        defer self.allocator.free(key_name);

        try self.keyring.set(key_name, key);
    }

    /// Get API key for provider
    pub fn getApiKey(
        self: *CredentialManager,
        provider: Provider,
    ) !?[]const u8 {
        const key_name = try std.fmt.allocPrint(
            self.allocator,
            "grim.api.{s}",
            .{@tagName(provider)},
        );
        defer self.allocator.free(key_name);

        return self.keyring.get(key_name);
    }

    /// Delete API key
    pub fn deleteApiKey(
        self: *CredentialManager,
        provider: Provider,
    ) !void {
        const key_name = try std.fmt.allocPrint(
            self.allocator,
            "grim.api.{s}",
            .{@tagName(provider)},
        );
        defer self.allocator.free(key_name);

        try self.keyring.delete(key_name);
    }

    /// List configured providers
    pub fn listProviders(self: *CredentialManager) ![]Provider {
        var list = std.ArrayList(Provider).init(self.allocator);

        inline for (@typeInfo(Provider).Enum.fields) |field| {
            const provider = @field(Provider, field.name);
            if (try self.getApiKey(provider)) |_| {
                try list.append(provider);
            }
        }

        return list.toOwnedSlice();
    }

    /// Validate API key by testing API
    pub fn validateApiKey(
        self: *CredentialManager,
        provider: Provider,
    ) !bool {
        const key = try self.getApiKey(provider) orelse return false;

        return switch (provider) {
            .anthropic => try self.testAnthropicApi(key),
            .openai => try self.testOpenAiApi(key),
            .xai => try self.testXaiApi(key),
            .github_copilot => try self.testCopilotApi(key),
            .ollama => true, // Local, no validation needed
        };
    }

    fn testAnthropicApi(self: *CredentialManager, key: []const u8) !bool {
        // Simple test: GET /v1/models
        _ = self;
        _ = key;
        // TODO: Implement HTTP request
        return true;
    }

    // ... similar for other providers
};

/// System keyring abstraction
pub const Keyring = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Keyring {
        return .{ .allocator = allocator };
    }

    pub fn set(self: *Keyring, key: []const u8, value: []const u8) !void {
        // Platform-specific implementation
        if (@import("builtin").os.tag == .macos) {
            try self.setMacOSKeychain(key, value);
        } else if (@import("builtin").os.tag == .linux) {
            try self.setLinuxSecretService(key, value);
        } else if (@import("builtin").os.tag == .windows) {
            try self.setWindowsCredentialManager(key, value);
        } else {
            // Fallback: encrypted file
            try self.setEncryptedFile(key, value);
        }
    }

    pub fn get(self: *Keyring, key: []const u8) !?[]const u8 {
        // Platform-specific implementation
        if (@import("builtin").os.tag == .macos) {
            return try self.getMacOSKeychain(key);
        } else if (@import("builtin").os.tag == .linux) {
            return try self.getLinuxSecretService(key);
        } else if (@import("builtin").os.tag == .windows) {
            return try self.getWindowsCredentialManager(key);
        } else {
            return try self.getEncryptedFile(key);
        }
    }

    pub fn delete(self: *Keyring, key: []const u8) !void {
        // Platform-specific implementation
        _ = self;
        _ = key;
    }

    // Platform implementations
    fn setMacOSKeychain(self: *Keyring, key: []const u8, value: []const u8) !void {
        // security add-generic-password -a grim -s <key> -w <value>
        _ = self;
        _ = key;
        _ = value;
    }

    fn getLinuxSecretService(self: *Keyring, key: []const u8) !?[]const u8 {
        // Use libsecret D-Bus API
        _ = self;
        _ = key;
        return null;
    }

    // ... other platform implementations
};
```

---

### SimpleTUI Integration

Add to `ui-tui/simple_tui.zig`:

```zig
// Field
credential_manager: ?*core.CredentialManager,

// Init
self.credential_manager = try core.CredentialManager.init(allocator);

// Command handler
if (std.mem.eql(u8, head, "ApiKey")) {
    const provider_str = tokenizer.next() orelse {
        self.setStatusMessage("Usage: :ApiKey <provider> [key]");
        return;
    };

    if (std.mem.eql(u8, provider_str, "list")) {
        const providers = try self.credential_manager.?.listProviders();
        defer self.allocator.free(providers);

        // Show popup with provider list
        var buf: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        for (providers) |provider| {
            try stream.writer().print("✅ {s}\n", .{@tagName(provider)});
        }
        // Show in popup
        return;
    }

    const provider = std.meta.stringToEnum(
        core.CredentialManager.Provider,
        provider_str,
    ) orelse {
        self.setStatusMessage("Unknown provider: {s}", .{provider_str});
        return;
    };

    const key = tokenizer.rest();
    if (key.len == 0) {
        // View key (masked)
        if (try self.credential_manager.?.getApiKey(provider)) |api_key| {
            defer self.allocator.free(api_key);
            const masked = try self.maskApiKey(api_key);
            defer self.allocator.free(masked);
            self.setStatusMessage("{s} key: {s}", .{provider_str, masked});
        } else {
            self.setStatusMessage("{s} key not configured", .{provider_str});
        }
    } else {
        // Set key
        try self.credential_manager.?.setApiKey(provider, key);

        // Validate
        const valid = try self.credential_manager.?.validateApiKey(provider);
        if (valid) {
            self.setStatusMessage("✅ {s} API key saved", .{provider_str});
        } else {
            self.setStatusMessage("⚠️  {s} API key saved but validation failed", .{provider_str});
        }
    }
}
```

---

### GitHub OAuth Flow

```zig
pub fn githubOAuthFlow(self: *CredentialManager) ![]const u8 {
    // 1. Generate device code
    const device_code_url = "https://github.com/login/device/code";
    const client_id = "grim-editor-copilot";  // Register with GitHub

    var http_client = std.http.Client{ .allocator = self.allocator };
    defer http_client.deinit();

    var request_body = try std.fmt.allocPrint(
        self.allocator,
        "client_id={s}&scope=copilot",
        .{client_id},
    );
    defer self.allocator.free(request_body);

    var req = try http_client.request(.POST, device_code_url, .{});
    defer req.deinit();

    try req.headers.append("Content-Type", "application/x-www-form-urlencoded");
    try req.send(request_body);
    try req.wait();

    // Parse response
    const response = try req.reader().readAllAlloc(self.allocator, 4096);
    defer self.allocator.free(response);

    // Extract user_code and verification_uri
    const user_code = try self.extractJsonField(response, "user_code");
    const verification_uri = try self.extractJsonField(response, "verification_uri");
    const device_code = try self.extractJsonField(response, "device_code");

    // 2. Open browser
    try self.openBrowser(verification_uri);

    // 3. Show code to user
    std.debug.print("\n", .{});
    std.debug.print("GitHub Login\n", .{});
    std.debug.print("============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("1. Opening browser to: {s}\n", .{verification_uri});
    std.debug.print("2. Enter code: {s}\n", .{user_code});
    std.debug.print("3. Waiting for authorization...\n", .{});
    std.debug.print("\n", .{});

    // 4. Poll for token
    const token_url = "https://github.com/login/oauth/access_token";
    var poll_interval: u64 = 5; // seconds

    while (true) {
        std.time.sleep(poll_interval * std.time.ns_per_s);

        var token_body = try std.fmt.allocPrint(
            self.allocator,
            "client_id={s}&device_code={s}&grant_type=urn:ietf:params:oauth:grant-type:device_code",
            .{client_id, device_code},
        );
        defer self.allocator.free(token_body);

        var token_req = try http_client.request(.POST, token_url, .{});
        defer token_req.deinit();

        try token_req.send(token_body);
        try token_req.wait();

        const token_response = try token_req.reader().readAllAlloc(self.allocator, 4096);
        defer self.allocator.free(token_response);

        // Check for error
        if (std.mem.indexOf(u8, token_response, "authorization_pending") != null) {
            continue; // Keep polling
        }

        if (std.mem.indexOf(u8, token_response, "access_token") != null) {
            const access_token = try self.extractJsonField(token_response, "access_token");
            return access_token; // Success!
        }

        // Other error
        return error.AuthorizationFailed;
    }
}

fn openBrowser(self: *CredentialManager, url: []const u8) !void {
    _ = self;
    const cmd = if (@import("builtin").os.tag == .macos)
        "open"
    else if (@import("builtin").os.tag == .linux)
        "xdg-open"
    else
        "start";

    var child = std.process.Child.init(&.{cmd, url}, self.allocator);
    _ = try child.spawnAndWait();
}
```

---

## First-Run Wizard

`:GrimSetup` implementation in `ui-tui/simple_tui.zig`:

```zig
fn runSetupWizard(self: *SimpleTUI) !void {
    self.clearScreen();

    // Step 1: Detect Ollama
    try self.setupWizardStep1_Ollama();

    // Step 2: GitHub Copilot
    try self.setupWizardStep2_GitHub();

    // Step 3: Anthropic
    try self.setupWizardStep3_Anthropic();

    // Step 4: OpenAI
    try self.setupWizardStep4_OpenAI();

    // Step 5: xAI
    try self.setupWizardStep5_xAI();

    // Done!
    try self.setupWizardComplete();
}

fn setupWizardStep1_Ollama(self: *SimpleTUI) !void {
    try self.renderSetupHeader("Detecting Ollama", 1, 5);

    // Try to connect to Ollama
    var http_client = std.http.Client{ .allocator = self.allocator };
    defer http_client.deinit();

    const ollama_url = "http://localhost:11434/api/tags";
    var req = http_client.request(.GET, ollama_url, .{}) catch {
        try self.renderMessage("❌ Ollama not found (skipping)");
        std.time.sleep(2 * std.time.ns_per_s);
        return;
    };
    defer req.deinit();

    try req.send(null);
    try req.wait();

    try self.renderMessage("✅ Ollama found!");

    // List models
    const response = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
    defer self.allocator.free(response);

    // Count models (simple JSON parsing)
    const model_count = std.mem.count(u8, response, "\"name\":");
    try self.renderMessage(try std.fmt.allocPrint(
        self.allocator,
        "✅ {d} models available",
        .{model_count},
    ));

    std.time.sleep(2 * std.time.ns_per_s);
}

fn setupWizardStep2_GitHub(self: *SimpleTUI) !void {
    try self.renderSetupHeader("GitHub Copilot", 2, 5);

    try self.renderMessage("Do you have a GitHub Copilot subscription?");
    try self.renderMessage("[Y]es  [N]o  [S]kip");

    const choice = try self.waitForKeypress();

    if (choice == 'y' or choice == 'Y') {
        try self.renderMessage("Starting OAuth flow...");

        const token = try self.credential_manager.?.githubOAuthFlow();
        defer self.allocator.free(token);

        try self.credential_manager.?.setApiKey(.github_copilot, token);
        try self.renderMessage("✅ GitHub authenticated");
    } else {
        try self.renderMessage("Skipped");
    }

    std.time.sleep(2 * std.time.ns_per_s);
}

// ... similar for other providers
```

---

## Security Considerations

### Keyring Storage

**macOS:** Use Security framework's Keychain
```bash
security add-generic-password -a grim -s grim.api.anthropic -w "sk-ant-..."
```

**Linux:** Use libsecret (D-Bus Secret Service API)
```bash
secret-tool store --label="Grim Anthropic API" service grim key anthropic
```

**Windows:** Use Credential Manager API
```c
CredWrite(&credential, 0);
```

**Fallback:** Encrypted file at `~/.config/grim/credentials.enc`
- AES-256-GCM encryption
- Key derived from user password + machine ID

---

### Never Log API Keys

All logging must mask keys:

```zig
fn logApiKey(key: []const u8) []const u8 {
    if (key.len <= 8) return "***";

    var masked = try allocator.alloc(u8, key.len);
    std.mem.copy(u8, masked[0..4], key[0..4]);
    std.mem.set(u8, masked[4..key.len-4], '*');
    std.mem.copy(u8, masked[key.len-4..], key[key.len-4..]);
    return masked; // e.g. "sk-a***xyz"
}
```

---

## Thanos.grim Integration

Update thanos.grim to read from Grim credentials:

```zig
// src/root.zig
pub fn initializeThanos(self: *ThanosGrimPlugin) !void {
    // Check if Grim has credentials
    const grim_creds = try checkGrimCredentials();

    var config = thanos.types.Config{
        .mode = .hybrid,
        .debug = false,
        .preferred_provider = .ollama,
    };

    // Load API keys from Grim
    if (grim_creds.anthropic) |key| {
        config.anthropic_key = key;
    }
    if (grim_creds.openai) |key| {
        config.openai_key = key;
    }
    if (grim_creds.xai) |key| {
        config.xai_key = key;
    }
    if (grim_creds.github_token) |token| {
        config.github_token = token;
    }

    // Initialize Thanos
    const instance = try self.allocator.create(thanos.Thanos);
    instance.* = try thanos.Thanos.init(self.allocator, config);
    self.thanos_instance = instance;
    self.initialized = true;
}

fn checkGrimCredentials() !GrimCredentials {
    // Call back to Grim via bridge
    const creds = bridge.getCredentials();
    return creds;
}
```

---

## Summary

**Recommendation: Hybrid Approach**

1. **Grim Core** handles authentication:
   - `:GrimSetup` - First-run wizard
   - `:ApiKey` - Manage API keys
   - `:GithubLogin` - OAuth flow
   - `:OllamaDetect` - Auto-detect local Ollama
   - Secure keyring storage

2. **Thanos.grim** consumes credentials:
   - Reads from Grim credential manager
   - No duplicate auth
   - Focus on AI features

3. **User Experience:**
   - Run `:GrimSetup` once
   - All AI features work immediately
   - No manual config files
   - Secure credential storage

**Next Steps:**
1. Implement `core/credentials.zig`
2. Add `:ApiKey`, `:GithubLogin`, `:GrimSetup` commands
3. Update thanos.grim to read Grim credentials
4. Test end-to-end

Should I start implementing `core/credentials.zig`?
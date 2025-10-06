const std = @import("std");

// Zap types - define locally to avoid import issues during build
// Full Zap integration will be enabled when dependency is properly configured
pub const OllamaConfig = struct {
    host: []const u8 = "http://localhost:11434",
    model: []const u8 = "deepseek-coder:33b",
    timeout_ms: u32 = 30000,
};

pub const GenerateRequest = struct {
    model: []const u8,
    prompt: []const u8,
    stream: bool = false,
    context: ?[]const i64 = null,
    system: ?[]const u8 = null,
    template: ?[]const u8 = null,
    format: ?[]const u8 = null,
    raw: ?bool = null,
    options: ?GenerateOptions = null,
};

pub const GenerateOptions = struct {
    num_predict: ?i32 = null,
    temperature: ?f32 = null,
    top_k: ?i32 = null,
    top_p: ?f32 = null,
    repeat_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
};

pub const OllamaClient = struct {
    allocator: std.mem.Allocator,
    config: OllamaConfig,

    pub fn init(allocator: std.mem.Allocator, config: OllamaConfig) !OllamaClient {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn generateCommitMessage(self: *OllamaClient, diff: []const u8) ![]const u8 {
        // TODO: Implement actual Ollama API call
        _ = self;
        _ = diff;
        return error.NotImplemented;
    }

    pub fn generate(self: *OllamaClient, request: GenerateRequest) ![]const u8 {
        // TODO: Implement actual Ollama API call
        _ = self;
        _ = request;
        return error.NotImplemented;
    }
};

/// Zap AI integration for Grim editor
/// Provides AI-powered git features using local Ollama models
pub const ZapIntegration = struct {
    allocator: std.mem.Allocator,
    ollama_client: ?*OllamaClient,
    config: OllamaConfig,

    pub fn init(allocator: std.mem.Allocator) ZapIntegration {
        return .{
            .allocator = allocator,
            .ollama_client = null,
            .config = .{
                .host = "http://localhost:11434",
                .model = "deepseek-coder:33b",
                .timeout_ms = 30000,
            },
        };
    }

    pub fn deinit(self: *ZapIntegration) void {
        if (self.ollama_client) |client| {
            self.allocator.destroy(client);
        }
    }

    /// Initialize Ollama client with custom config
    pub fn initOllama(self: *ZapIntegration, config: OllamaConfig) !void {
        if (self.ollama_client != null) return;

        self.config = config;
        const client = try self.allocator.create(OllamaClient);
        client.* = try OllamaClient.init(self.allocator, config);
        self.ollama_client = client;
    }

    /// Check if Ollama is available
    pub fn isAvailable(self: *ZapIntegration) bool {
        _ = self;
        // Try to connect to Ollama endpoint
        // For now, just assume it's available if configured
        return true;
    }

    /// Generate AI commit message from staged changes
    pub fn generateCommitMessage(self: *ZapIntegration, diff: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        return try self.ollama_client.?.generateCommitMessage(diff);
    }

    /// Explain code changes in plain English
    pub fn explainChanges(self: *ZapIntegration, diff: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Explain these code changes in plain English:
            \\
            \\{s}
            \\
            \\Be concise and focus on what changed and why.
        , .{diff});
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .options = .{
                .temperature = 0.5,
                .num_predict = 300,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Suggest better variable/function names
    pub fn suggestNames(self: *ZapIntegration, code: []const u8, context: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Context: {s}
            \\
            \\Code: {s}
            \\
            \\Suggest better, more descriptive names for variables and functions in this code.
            \\Follow language conventions (Zig: camelCase for functions, snake_case for variables).
        , .{ context, code });
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .options = .{
                .temperature = 0.4,
                .num_predict = 200,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Detect potential issues in code
    pub fn detectIssues(self: *ZapIntegration, code: []const u8, language: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Analyze this {s} code for potential issues:
            \\
            \\{s}
            \\
            \\Look for: memory leaks, logic errors, security issues, performance problems.
            \\Be specific and provide line references if possible.
        , .{ language, code });
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .system = "You are a code reviewer focusing on correctness, safety, and performance.",
            .options = .{
                .temperature = 0.2,
                .num_predict = 500,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Generate commit message following conventional commits format
    pub fn generateConventionalCommit(self: *ZapIntegration, diff: []const u8, commit_type: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Generate a conventional commit message for these changes:
            \\
            \\{s}
            \\
            \\Type: {s}
            \\Format: <type>(<scope>): <subject>
            \\
            \\Keep subject under 72 characters. Use imperative mood.
        , .{ diff, commit_type });
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .options = .{
                .temperature = 0.3,
                .num_predict = 80,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Suggest merge conflict resolution
    pub fn suggestMergeResolution(self: *ZapIntegration, conflict: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\This is a git merge conflict:
            \\
            \\{s}
            \\
            \\Suggest how to resolve it. Consider both sides and propose a solution.
            \\Explain the reasoning behind your suggestion.
        , .{conflict});
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .system = "You are a git expert helping resolve merge conflicts.",
            .options = .{
                .temperature = 0.4,
                .num_predict = 400,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Generate changelog from commit history
    pub fn generateChangelog(self: *ZapIntegration, commits: []const []const u8, from_tag: []const u8, to_tag: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        // Build commit list
        var commit_list = std.ArrayList(u8).init(self.allocator);
        defer commit_list.deinit();

        for (commits) |commit| {
            try commit_list.appendSlice(commit);
            try commit_list.append('\n');
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Generate a changelog from these commits ({s} to {s}):
            \\
            \\{s}
            \\
            \\Organize by category (Features, Bug Fixes, Performance, etc.).
            \\Use markdown format. Be concise.
        , .{ from_tag, to_tag, commit_list.items });
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .options = .{
                .temperature = 0.5,
                .num_predict = 800,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Explain what a commit range does
    pub fn explainCommitRange(self: *ZapIntegration, start_commit: []const u8, end_commit: []const u8, diffs: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Explain what happened between commits {s} and {s}:
            \\
            \\{s}
            \\
            \\Summarize the overall changes, their purpose, and impact.
        , .{ start_commit, end_commit, diffs });
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .options = .{
                .temperature = 0.5,
                .num_predict = 400,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Review code for best practices
    pub fn reviewCode(self: *ZapIntegration, code: []const u8, language: []const u8, focus: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Review this {s} code with focus on: {s}
            \\
            \\{s}
            \\
            \\Provide actionable feedback. Reference specific lines.
            \\Rate overall quality and suggest improvements.
        , .{ language, focus, code });
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .system = "You are an expert code reviewer focusing on best practices, maintainability, and correctness.",
            .options = .{
                .temperature = 0.3,
                .num_predict = 600,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Detect secrets/sensitive data in code
    pub fn detectSecrets(self: *ZapIntegration, code: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Scan this code for potential secrets or sensitive data:
            \\
            \\{s}
            \\
            \\Look for: API keys, passwords, tokens, private keys, connection strings.
            \\Report findings with line numbers.
        , .{code});
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .system = "You are a security scanner focused on detecting sensitive data leaks.",
            .options = .{
                .temperature = 0.1, // Very focused
                .num_predict = 300,
            },
        };

        return try self.ollama_client.?.generate(request);
    }

    /// Generate documentation from code
    pub fn generateDocs(self: *ZapIntegration, code: []const u8, language: []const u8) ![]const u8 {
        if (self.ollama_client == null) {
            try self.initOllama(self.config);
        }

        const prompt = try std.fmt.allocPrint(self.allocator,
            \\Generate documentation for this {s} code:
            \\
            \\{s}
            \\
            \\Include: function signatures, parameters, return types, examples.
            \\Use language-appropriate doc comment format.
        , .{ language, code });
        defer self.allocator.free(prompt);

        const request = GenerateRequest{
            .model = self.config.model,
            .prompt = prompt,
            .stream = false,
            .options = .{
                .temperature = 0.4,
                .num_predict = 500,
            },
        };

        return try self.ollama_client.?.generate(request);
    }
};

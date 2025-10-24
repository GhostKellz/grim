//! Thanos AI Client for Grim
//! Provides unified AI completions through Thanos orchestration layer
//! Supports: Omen (local), Ollama, Anthropic, OpenAI, xAI, GitHub Copilot

const std = @import("std");
const thanos = @import("thanos");
const context_mod = @import("context.zig");

pub const ThanosClient = struct {
    allocator: std.mem.Allocator,
    thanos_instance: ?*thanos.Thanos = null,
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator) !*ThanosClient {
        const self = try allocator.create(ThanosClient);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *ThanosClient) void {
        if (self.thanos_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }
        self.allocator.destroy(self);
    }

    /// Initialize Thanos with config from thanos.toml or defaults
    pub fn ensureInitialized(self: *ThanosClient) !void {
        if (self.initialized) return;

        // Try to load config from thanos.toml
        var config = if (std.fs.cwd().access("thanos.toml", .{})) |_|
            thanos.config.loadConfig(self.allocator, "thanos.toml") catch blk: {
                std.log.info("[Thanos] Failed to load thanos.toml, using defaults", .{});
                break :blk thanos.types.Config{
                    .mode = .hybrid,
                    .debug = false,
                    .preferred_provider = .omen, // Use local Omen first
                    .fallback_providers = &.{ .ollama, .anthropic },
                };
            }
        else |_| thanos.types.Config{
            .mode = .hybrid,
            .debug = false,
            .preferred_provider = .omen,
            .fallback_providers = &.{ .ollama, .anthropic },
        };

        // Initialize task routing
        try config.initTaskRouting(self.allocator);

        const instance = try self.allocator.create(thanos.Thanos);
        instance.* = try thanos.Thanos.init(self.allocator, config);
        self.thanos_instance = instance;
        self.initialized = true;

        std.log.info("[Thanos] Initialized successfully", .{});
    }

    /// Request code completion at cursor
    pub fn complete(self: *ThanosClient, ctx: *const context_mod.Context) ![]const u8 {
        try self.ensureInitialized();

        const instance = self.thanos_instance orelse return error.NotInitialized;

        // Build prompt from context
        var prompt_buf: [4096]u8 = undefined;
        const prompt = try self.buildPrompt(ctx, &prompt_buf);

        const language = if (ctx.buffer) |buf| buf.language else null;

        const request = thanos.types.CompletionRequest{
            .prompt = prompt,
            .language = language,
            .max_tokens = 150,
        };

        const response = try instance.complete(request);
        return response.text;
    }

    /// Request AI chat/explanation
    pub fn chat(self: *ThanosClient, message: []const u8, ctx: *const context_mod.Context) ![]const u8 {
        try self.ensureInitialized();

        const instance = self.thanos_instance orelse return error.NotInitialized;

        // Build context-aware prompt
        var prompt_buf: [8192]u8 = undefined;
        var stream = std.io.fixedBufferStream(&prompt_buf);
        const writer = stream.writer();

        // Add context
        if (ctx.buffer) |buf| {
            try writer.print("File: {s}\n", .{buf.file_path orelse "[No Name]"});
            try writer.print("Language: {s}\n", .{buf.language orelse "unknown"});
            try writer.print("Line: {d}/{d}\n\n", .{ buf.cursor_line + 1, buf.total_lines });
        }

        if (ctx.selection) |sel| {
            try writer.print("Selected code:\n```\n{s}\n```\n\n", .{sel.content});
        }

        // Add user message
        try writer.print("User: {s}\n", .{message});

        const prompt = stream.getWritten();

        const request = thanos.types.CompletionRequest{
            .prompt = prompt,
            .language = null,
            .max_tokens = 500,
        };

        const response = try instance.complete(request);
        return response.text;
    }

    /// List available AI providers and their health
    pub fn listProviders(self: *ThanosClient) ![]const thanos.types.ProviderHealth {
        try self.ensureInitialized();

        const instance = self.thanos_instance orelse return error.NotInitialized;
        return instance.listProviders();
    }

    /// Get AI statistics
    pub fn getStats(self: *ThanosClient) !thanos.ThanosStats {
        try self.ensureInitialized();

        const instance = self.thanos_instance orelse return error.NotInitialized;
        return instance.getStats();
    }

    // ========================================================================
    // Private helper functions
    // ========================================================================

    fn buildPrompt(self: *ThanosClient, ctx: *const context_mod.Context, buf: []u8) ![]const u8 {
        _ = self;

        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        if (ctx.buffer) |buffer| {
            // Add file context
            if (buffer.file_path) |path| {
                try writer.print("// File: {s}\n", .{path});
            }
            if (buffer.language) |lang| {
                try writer.print("// Language: {s}\n", .{lang});
            }

            // Add content before cursor (last 1000 chars for context)
            const content_before_cursor = buffer.content[0..@min(buffer.content.len, 1000)];
            try writer.writeAll(content_before_cursor);

            // Add cursor marker
            try writer.writeAll("<|cursor|>");
        }

        return stream.getWritten();
    }
};

test "thanos client creation" {
    const allocator = std.testing.allocator;
    const client = try ThanosClient.init(allocator);
    defer client.deinit();

    try std.testing.expect(!client.initialized);
}

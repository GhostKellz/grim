//! Inline AI completion engine for Grim
//! Provides ghost text completions as you type (like GitHub Copilot)

const std = @import("std");

/// Debounce timer for completion requests
pub const DebounceTimer = struct {
    last_trigger: i64,
    debounce_ms: u64,

    pub fn init(debounce_ms: u64) DebounceTimer {
        return .{
            .last_trigger = 0,
            .debounce_ms = debounce_ms,
        };
    }

    /// Check if enough time has passed since last trigger
    pub fn shouldTrigger(self: *DebounceTimer) bool {
        const now = std.time.milliTimestamp();
        if (now - self.last_trigger >= self.debounce_ms) {
            self.last_trigger = now;
            return true;
        }
        return false;
    }

    /// Reset the timer
    pub fn reset(self: *DebounceTimer) void {
        self.last_trigger = std.time.milliTimestamp();
    }
};

/// Completion request context
pub const CompletionContext = struct {
    prefix: []const u8, // Text before cursor
    suffix: []const u8, // Text after cursor
    file_path: []const u8,
    language: []const u8,
    line: u32,
    column: u32,
};

/// Completion result
pub const Completion = struct {
    text: []const u8,
    provider: []const u8,
    confidence: f32,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *Completion) void {
        self.allocator.free(self.text);
        self.allocator.free(self.provider);
    }
};

/// Inline completion engine
pub const InlineCompletionEngine = struct {
    allocator: std.mem.Allocator,
    debounce_timer: DebounceTimer,
    last_completion: ?Completion,
    last_context: ?CompletionContext,
    enabled: bool,
    min_trigger_length: u32, // Minimum chars before triggering
    max_completion_tokens: u32,

    /// FFI bridge function pointer (calls thanos_grim_get_inline_completion_debounced)
    completion_fn: ?*const fn (
        prefix: [*:0]const u8,
        suffix: [*:0]const u8,
        language: [*:0]const u8,
        debounce_ms: c_int,
        max_tokens: c_int,
    ) callconv(.C) [*:0]const u8,

    pub fn init(allocator: std.mem.Allocator, debounce_ms: u64) InlineCompletionEngine {
        return .{
            .allocator = allocator,
            .debounce_timer = DebounceTimer.init(debounce_ms),
            .last_completion = null,
            .last_context = null,
            .enabled = true,
            .min_trigger_length = 3, // Trigger after 3 chars
            .max_completion_tokens = 50, // Small for inline completions
            .completion_fn = null,
        };
    }

    pub fn deinit(self: *InlineCompletionEngine) void {
        if (self.last_completion) |*comp| {
            comp.deinit();
        }
        if (self.last_context) |*ctx| {
            self.allocator.free(ctx.prefix);
            self.allocator.free(ctx.suffix);
            self.allocator.free(ctx.file_path);
            self.allocator.free(ctx.language);
        }
    }

    /// Set FFI completion function pointer
    pub fn setCompletionFunction(
        self: *InlineCompletionEngine,
        func: *const fn (
            prefix: [*:0]const u8,
            suffix: [*:0]const u8,
            language: [*:0]const u8,
            debounce_ms: c_int,
            max_tokens: c_int,
        ) callconv(.C) [*:0]const u8,
    ) void {
        self.completion_fn = func;
    }

    /// Request completion for current context
    pub fn requestCompletion(self: *InlineCompletionEngine, context: CompletionContext) !?Completion {
        if (!self.enabled) return null;

        // Check if we should trigger based on debounce
        if (!self.debounce_timer.shouldTrigger()) {
            return null;
        }

        // Check minimum trigger length
        if (context.prefix.len < self.min_trigger_length) {
            return null;
        }

        // Skip if context hasn't changed much
        if (self.last_context) |last| {
            if (std.mem.eql(u8, last.prefix, context.prefix) and
                std.mem.eql(u8, last.suffix, context.suffix))
            {
                // Return cached completion
                if (self.last_completion) |comp| {
                    return Completion{
                        .text = try self.allocator.dupe(u8, comp.text),
                        .provider = try self.allocator.dupe(u8, comp.provider),
                        .confidence = comp.confidence,
                        .allocator = self.allocator,
                    };
                }
                return null;
            }
        }

        // Call FFI function if available
        if (self.completion_fn) |func| {
            // Convert to C strings
            const prefix_z = try self.allocator.dupeZ(u8, context.prefix);
            defer self.allocator.free(prefix_z);

            const suffix_z = try self.allocator.dupeZ(u8, context.suffix);
            defer self.allocator.free(suffix_z);

            const language_z = try self.allocator.dupeZ(u8, context.language);
            defer self.allocator.free(language_z);

            // Call native function
            const result_ptr = func(
                prefix_z.ptr,
                suffix_z.ptr,
                language_z.ptr,
                @intCast(self.debounce_timer.debounce_ms),
                @intCast(self.max_completion_tokens),
            );

            const result = std.mem.span(result_ptr);

            // Check if empty or error
            if (result.len == 0 or std.mem.startsWith(u8, result, "error:")) {
                return null;
            }

            // Store context and completion
            try self.updateContext(context);

            // Free old completion
            if (self.last_completion) |*old| {
                old.deinit();
            }

            // Create new completion
            const completion = Completion{
                .text = try self.allocator.dupe(u8, result),
                .provider = try self.allocator.dupe(u8, "thanos"),
                .confidence = 0.8,
                .allocator = self.allocator,
            };

            self.last_completion = completion;

            return Completion{
                .text = try self.allocator.dupe(u8, result),
                .provider = try self.allocator.dupe(u8, "thanos"),
                .confidence = 0.8,
                .allocator = self.allocator,
            };
        }

        // No FFI function available, return null
        return null;
    }

    /// Cancel pending completion request
    pub fn cancelCompletion(self: *InlineCompletionEngine) void {
        if (self.last_completion) |*comp| {
            comp.deinit();
            self.last_completion = null;
        }
    }

    /// Accept current completion (clear cache)
    pub fn acceptCompletion(self: *InlineCompletionEngine) void {
        // Clear cache so next request gets fresh completion
        if (self.last_completion) |*comp| {
            comp.deinit();
            self.last_completion = null;
        }
        if (self.last_context) |*ctx| {
            self.allocator.free(ctx.prefix);
            self.allocator.free(ctx.suffix);
            self.allocator.free(ctx.file_path);
            self.allocator.free(ctx.language);
            self.last_context = null;
        }
    }

    /// Enable/disable inline completions
    pub fn setEnabled(self: *InlineCompletionEngine, enabled: bool) void {
        self.enabled = enabled;
        if (!enabled) {
            self.cancelCompletion();
        }
    }

    /// Update stored context
    fn updateContext(self: *InlineCompletionEngine, context: CompletionContext) !void {
        // Free old context
        if (self.last_context) |*old| {
            self.allocator.free(old.prefix);
            self.allocator.free(old.suffix);
            self.allocator.free(old.file_path);
            self.allocator.free(old.language);
        }

        // Store new context
        self.last_context = CompletionContext{
            .prefix = try self.allocator.dupe(u8, context.prefix),
            .suffix = try self.allocator.dupe(u8, context.suffix),
            .file_path = try self.allocator.dupe(u8, context.file_path),
            .language = try self.allocator.dupe(u8, context.language),
            .line = context.line,
            .column = context.column,
        };
    }
};

// Tests
test "debounce timer" {
    var timer = DebounceTimer.init(100);

    // First trigger should work
    try std.testing.expect(timer.shouldTrigger());

    // Immediate second trigger should fail
    try std.testing.expect(!timer.shouldTrigger());

    // Wait and try again
    std.time.sleep(110 * std.time.ns_per_ms);
    try std.testing.expect(timer.shouldTrigger());
}

test "inline completion engine init" {
    var engine = InlineCompletionEngine.init(std.testing.allocator, 200);
    defer engine.deinit();

    try std.testing.expect(engine.enabled);
    try std.testing.expect(engine.last_completion == null);
}

test "completion context min length" {
    var engine = InlineCompletionEngine.init(std.testing.allocator, 200);
    defer engine.deinit();

    engine.min_trigger_length = 5;

    // Too short
    const short_context = CompletionContext{
        .prefix = "ab",
        .suffix = "",
        .file_path = "test.zig",
        .language = "zig",
        .line = 1,
        .column = 2,
    };

    const result = try engine.requestCompletion(short_context);
    try std.testing.expect(result == null);
}

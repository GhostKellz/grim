//! core/syntax_highlighter.zig
//! Wraps grim.syntax highlighting with per-buffer caching.

const std = @import("std");
const grim = @import("grim");
const config = @import("config_manager.zig");

const GrimSyntax = grim.syntax;
const GrimCore = grim.core;

pub const SyntaxHighlighter = struct {
    allocator: std.mem.Allocator,
    cache: CacheMap,
    generation: u64 = 0,
    highlighter: GrimSyntax.SyntaxHighlighter,
    rope: GrimCore.Rope,

    const CacheMap = std.AutoHashMap(CacheKey, CachedValue);

    pub const CacheKey = struct {
        buffer_id: u64,
        language_hash: u64,
        content_hash: u64,
    };

    const CachedValue = struct {
        highlight_set: config.HighlightSet,
        generation: u64,
    };

    pub const Request = struct {
        /// Stable identifier for the buffer/window pair.
        buffer_id: u64,
        /// Name of the language/grammar (e.g. "zig", "lua").
        language: []const u8,
        /// Canonical path used for language inference.
        path: []const u8,
        /// Current buffer contents.
        content: []const u8,
    };

    /// Result view returned to renderers.
    pub const Result = struct {
        highlights: *const config.HighlightSet,
        cache_generation: u64,
        cache_hit: bool,
    };

    pub fn init(allocator: std.mem.Allocator) !SyntaxHighlighter {
        const rope = try GrimCore.Rope.init(allocator);
        return SyntaxHighlighter{
            .allocator = allocator,
            .cache = CacheMap.init(allocator),
            .generation = 0,
            .highlighter = GrimSyntax.SyntaxHighlighter.init(allocator),
            .rope = rope,
        };
    }

    pub fn deinit(self: *SyntaxHighlighter) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.highlight_set.deinit(self.allocator);
        }
        self.cache.deinit();
        self.highlighter.deinit();
        self.rope.deinit();
    }

    fn hashBytes(bytes: []const u8) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(bytes);
        return hasher.final();
    }

    fn makeKey(request: Request) CacheKey {
        return CacheKey{
            .buffer_id = request.buffer_id,
            .language_hash = hashBytes(request.language),
            .content_hash = hashBytes(request.content),
        };
    }

    /// Fetch highlights for the given request, returning a cached entry when available.
    pub fn getHighlights(self: *SyntaxHighlighter, request: Request) !Result {
        const key = makeKey(request);
        if (self.cache.getPtr(key)) |value_ptr| {
            return Result{
                .highlights = &value_ptr.highlight_set,
                .cache_generation = value_ptr.generation,
                .cache_hit = true,
            };
        }

        var highlight_set = try self.computeHighlights(request);
        errdefer highlight_set.deinit(self.allocator);

        self.generation += 1;

        const gop = try self.cache.getOrPut(key);
        if (gop.found_existing) {
            highlight_set.deinit(self.allocator);
            return Result{
                .highlights = &gop.value_ptr.highlight_set,
                .cache_generation = gop.value_ptr.generation,
                .cache_hit = true,
            };
        }

        gop.value_ptr.* = CachedValue{
            .highlight_set = highlight_set,
            .generation = self.generation,
        };

        return Result{
            .highlights = &gop.value_ptr.highlight_set,
            .cache_generation = self.generation,
            .cache_hit = false,
        };
    }

    /// Invalidate any cached highlights for the specified buffer id.
    pub fn invalidateBuffer(self: *SyntaxHighlighter, buffer_id: u64) !void {
        var keys_to_remove = std.ArrayList(CacheKey).empty;
        defer keys_to_remove.deinit(self.allocator);

        var it = self.cache.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.buffer_id == buffer_id) {
                try keys_to_remove.append(self.allocator, entry.key_ptr.*);
            }
        }

        for (keys_to_remove.items) |key| {
            if (self.cache.fetchRemove(key)) |kv| {
                kv.value.highlight_set.deinit(self.allocator);
            }
        }
    }

    /// Reset the cache entirely, freeing all stored highlights.
    pub fn reset(self: *SyntaxHighlighter) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.highlight_set.deinit(self.allocator);
        }
        self.cache.clearRetainingCapacity();
        self.generation += 1;
    }

    fn computeHighlights(self: *SyntaxHighlighter, request: Request) !config.HighlightSet {
        const language_path = if (request.path.len != 0)
            request.path
        else
            fallbackPathForLanguage(request.language);

        try self.highlighter.setLanguage(language_path);
        try self.replaceRopeContent(request.content);

        const syntax_highlights = try self.highlighter.highlight(&self.rope);
        defer self.allocator.free(syntax_highlights);

        var converted = std.ArrayListUnmanaged(config.Highlight){};
        errdefer converted.deinit(self.allocator);

        for (syntax_highlights) |item| {
            const token = tokenForType(item.type) orelse continue;
            try converted.append(self.allocator, .{
                .start = item.start,
                .stop = item.end,
                .token_type = token,
            });
        }

        const highlight_slice = try converted.toOwnedSlice(self.allocator);

        return config.HighlightSet{
            .buffer = &[_]u8{},
            .highlights = highlight_slice,
            .owns_buffer = false,
            .owns_highlights = highlight_slice.len > 0,
        };
    }

    fn replaceRopeContent(self: *SyntaxHighlighter, content: []const u8) !void {
        const current_len = self.rope.len();
        if (current_len != 0) {
            try self.rope.delete(0, current_len);
        }
        if (content.len != 0) {
            try self.rope.insert(0, content);
        }
    }
};

fn fallbackPathForLanguage(language: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(language, "zig")) return "buffer.zig";
    if (std.ascii.eqlIgnoreCase(language, "rust")) return "buffer.rs";
    if (std.ascii.eqlIgnoreCase(language, "ts")) return "buffer.ts";
    if (std.ascii.eqlIgnoreCase(language, "tsx")) return "buffer.tsx";
    if (std.ascii.eqlIgnoreCase(language, "js")) return "buffer.js";
    if (std.ascii.eqlIgnoreCase(language, "lua")) return "buffer.lua";
    if (std.ascii.eqlIgnoreCase(language, "python")) return "buffer.py";
    if (std.ascii.eqlIgnoreCase(language, "toml")) return "buffer.toml";
    if (std.ascii.eqlIgnoreCase(language, "yaml")) return "buffer.yaml";
    if (std.ascii.eqlIgnoreCase(language, "json")) return "buffer.json";
    if (std.ascii.eqlIgnoreCase(language, "markdown")) return "buffer.md";
    if (std.ascii.eqlIgnoreCase(language, "c")) return "buffer.c";
    if (std.ascii.eqlIgnoreCase(language, "cpp")) return "buffer.cpp";
    if (std.ascii.eqlIgnoreCase(language, "go")) return "buffer.go";
    if (std.ascii.eqlIgnoreCase(language, "ghostlang") or std.ascii.eqlIgnoreCase(language, "gza")) return "buffer.gza";
    return "buffer.txt";
}

fn tokenForType(kind: GrimSyntax.HighlightType) ?[]const u8 {
    return switch (kind) {
        .keyword => "keyword",
        .string_literal => "string",
        .number_literal => "number",
        .comment => "comment",
        .function_name => "function",
        .type_name => "type",
        .variable => "variable",
        .operator => "operator",
        .punctuation => "default",
        .@"error" => "error",
        .none => null,
    };
}

//! Context manager for AI requests
//! Intelligently selects and formats context to include in prompts

const std = @import("std");

/// Type of context item
pub const ContextType = enum {
    cursor_line, // Current line at cursor
    selection, // Selected text
    surrounding_lines, // Lines around cursor
    file_content, // Entire file
    lsp_symbols, // LSP symbols (functions, structs, etc.)
    file_tree, // Project file tree
    git_diff, // Current git changes
    diagnostics, // LSP diagnostics/errors

    pub fn priority(self: ContextType) u8 {
        return switch (self) {
            .cursor_line => 10,
            .selection => 9,
            .surrounding_lines => 8,
            .lsp_symbols => 7,
            .diagnostics => 6,
            .file_content => 5,
            .git_diff => 4,
            .file_tree => 3,
        };
    }
};

/// Context item
pub const ContextItem = struct {
    type: ContextType,
    content: []const u8,
    token_estimate: u32,
    metadata: ?[]const u8 = null, // JSON metadata

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, ctx_type: ContextType, content: []const u8) !ContextItem {
        return .{
            .type = ctx_type,
            .content = try allocator.dupe(u8, content),
            .token_estimate = @intCast(content.len / 4), // Rough estimate: 4 chars per token
            .metadata = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContextItem) void {
        self.allocator.free(self.content);
        if (self.metadata) |meta| {
            self.allocator.free(meta);
        }
    }

    pub fn setMetadata(self: *ContextItem, metadata: []const u8) !void {
        if (self.metadata) |old| {
            self.allocator.free(old);
        }
        self.metadata = try self.allocator.dupe(u8, metadata);
    }
};

/// Context manager
pub const ContextManager = struct {
    allocator: std.mem.Allocator,
    context_items: std.ArrayList(ContextItem),
    max_tokens: u32,

    pub fn init(allocator: std.mem.Allocator, max_tokens: u32) ContextManager {
        return .{
            .allocator = allocator,
            .context_items = std.ArrayList(ContextItem).init(allocator),
            .max_tokens = max_tokens,
        };
    }

    pub fn deinit(self: *ContextManager) void {
        for (self.context_items.items) |*item| {
            item.deinit();
        }
        self.context_items.deinit();
    }

    /// Add context item
    pub fn addContext(self: *ContextManager, item: ContextItem) !void {
        try self.context_items.append(item);
    }

    /// Clear all context
    pub fn clear(self: *ContextManager) void {
        for (self.context_items.items) |*item| {
            item.deinit();
        }
        self.context_items.clearRetainingCapacity();
    }

    /// Get formatted context string within token limit
    pub fn getFormattedContext(self: *const ContextManager) ![]const u8 {
        // Sort by priority (highest first)
        var sorted = try self.allocator.alloc(ContextItem, self.context_items.items.len);
        defer self.allocator.free(sorted);

        @memcpy(sorted, self.context_items.items);
        std.mem.sort(ContextItem, sorted, {}, compareByPriority);

        // Build context string within token limit
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var total_tokens: u32 = 0;

        for (sorted) |item| {
            if (total_tokens + item.token_estimate > self.max_tokens) {
                break; // Would exceed token limit
            }

            // Add context with label
            const label = try self.getContextLabel(item.type);
            try result.appendSlice(label);
            try result.appendSlice(":\n");
            try result.appendSlice(item.content);
            try result.appendSlice("\n\n");

            total_tokens += item.token_estimate;
        }

        return try result.toOwnedSlice();
    }

    /// Get estimated total tokens
    pub fn getTotalTokens(self: *const ContextManager) u32 {
        var total: u32 = 0;
        for (self.context_items.items) |item| {
            total += item.token_estimate;
        }
        return total;
    }

    /// Check if context fits within token limit
    pub fn fitsWithinLimit(self: *const ContextManager) bool {
        return self.getTotalTokens() <= self.max_tokens;
    }

    /// Truncate context to fit within token limit
    pub fn truncateToLimit(self: *ContextManager) !void {
        // Sort by priority
        var sorted_indices = try self.allocator.alloc(usize, self.context_items.items.len);
        defer self.allocator.free(sorted_indices);

        for (sorted_indices, 0..) |*idx, i| {
            idx.* = i;
        }

        std.mem.sort(usize, sorted_indices, self, compareIndicesByPriority);

        // Keep items until we hit token limit
        var total_tokens: u32 = 0;
        var keep_count: usize = 0;

        for (sorted_indices) |idx| {
            const item = self.context_items.items[idx];
            if (total_tokens + item.token_estimate > self.max_tokens) {
                break;
            }
            total_tokens += item.token_estimate;
            keep_count += 1;
        }

        // Remove items beyond keep_count
        while (self.context_items.items.len > keep_count) {
            var item = self.context_items.pop();
            item.deinit();
        }
    }

    fn getContextLabel(self: *const ContextManager, ctx_type: ContextType) ![]const u8 {
        _ = self;
        return switch (ctx_type) {
            .cursor_line => "Current Line",
            .selection => "Selected Code",
            .surrounding_lines => "Surrounding Context",
            .file_content => "File Content",
            .lsp_symbols => "Code Symbols",
            .file_tree => "Project Structure",
            .git_diff => "Recent Changes",
            .diagnostics => "Errors & Warnings",
        };
    }

    fn compareByPriority(_: void, a: ContextItem, b: ContextItem) bool {
        return a.type.priority() > b.type.priority();
    }

    fn compareIndicesByPriority(self: *const ContextManager, a: usize, b: usize) bool {
        const item_a = self.context_items.items[a];
        const item_b = self.context_items.items[b];
        return item_a.type.priority() > item_b.type.priority();
    }
};

/// Helper: Create context from buffer
pub fn createBufferContext(
    allocator: std.mem.Allocator,
    buffer: []const u8,
    cursor_line: u32,
    cursor_col: u32,
    context_lines: u32,
) !ContextItem {
    _ = cursor_col;

    // Extract surrounding lines
    var lines = std.mem.split(u8, buffer, "\n");
    var line_list = std.ArrayList([]const u8).init(allocator);
    defer line_list.deinit();

    while (lines.next()) |line| {
        try line_list.append(line);
    }

    // Calculate range
    const start_line = if (cursor_line > context_lines) cursor_line - context_lines else 0;
    const end_line = @min(cursor_line + context_lines, @as(u32, @intCast(line_list.items.len)));

    // Build context
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (start_line..end_line) |i| {
        const line = line_list.items[i];
        try result.appendSlice(line);
        try result.append('\n');
    }

    return try ContextItem.init(allocator, .surrounding_lines, result.items);
}

/// Helper: Create context from selection
pub fn createSelectionContext(allocator: std.mem.Allocator, selection: []const u8) !ContextItem {
    return try ContextItem.init(allocator, .selection, selection);
}

/// Helper: Create context from file
pub fn createFileContext(allocator: std.mem.Allocator, file_path: []const u8, content: []const u8) !ContextItem {
    var item = try ContextItem.init(allocator, .file_content, content);
    const metadata = try std.fmt.allocPrint(allocator, "{{\"file\":\"{s}\"}}", .{file_path});
    try item.setMetadata(metadata);
    return item;
}

// Tests
test "context item creation" {
    var item = try ContextItem.init(std.testing.allocator, .cursor_line, "const x = 42;");
    defer item.deinit();

    try std.testing.expectEqual(ContextType.cursor_line, item.type);
    try std.testing.expectEqualStrings("const x = 42;", item.content);
}

test "context manager" {
    var manager = ContextManager.init(std.testing.allocator, 1000);
    defer manager.deinit();

    var item1 = try ContextItem.init(std.testing.allocator, .cursor_line, "line 1");
    var item2 = try ContextItem.init(std.testing.allocator, .selection, "selected code");

    try manager.addContext(item1);
    try manager.addContext(item2);

    const total = manager.getTotalTokens();
    try std.testing.expect(total > 0);
}

test "context prioritization" {
    var manager = ContextManager.init(std.testing.allocator, 100);
    defer manager.deinit();

    // Add low priority item
    var item1 = try ContextItem.init(std.testing.allocator, .file_tree, "a".** 200); // Too big
    try manager.addContext(item1);

    // Add high priority item
    var item2 = try ContextItem.init(std.testing.allocator, .selection, "important");
    try manager.addContext(item2);

    try manager.truncateToLimit();

    // Should keep high priority item
    try std.testing.expect(manager.context_items.items.len > 0);
}

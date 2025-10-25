//! AI chat window for conversational interactions
//! Implements a split-pane chat interface for asking questions and getting help

const std = @import("std");

/// Chat message role
pub const MessageRole = enum {
    user,
    assistant,
    system,

    pub fn toString(self: MessageRole) []const u8 {
        return switch (self) {
            .user => "You",
            .assistant => "AI",
            .system => "System",
        };
    }
};

/// Chat message
pub const ChatMessage = struct {
    role: MessageRole,
    content: []const u8,
    timestamp: i64,
    provider: ?[]const u8 = null,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, role: MessageRole, content: []const u8) !ChatMessage {
        return .{
            .role = role,
            .content = try allocator.dupe(u8, content),
            .timestamp = std.time.timestamp(),
            .provider = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChatMessage) void {
        self.allocator.free(self.content);
        if (self.provider) |p| {
            self.allocator.free(p);
        }
    }

    pub fn setProvider(self: *ChatMessage, provider: []const u8) !void {
        if (self.provider) |old| {
            self.allocator.free(old);
        }
        self.provider = try self.allocator.dupe(u8, provider);
    }
};

/// Chat history
pub const ChatHistory = struct {
    messages: std.ArrayList(ChatMessage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ChatHistory {
        return .{
            .messages = std.ArrayList(ChatMessage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChatHistory) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.deinit();
    }

    pub fn addMessage(self: *ChatHistory, message: ChatMessage) !void {
        try self.messages.append(message);
    }

    pub fn clear(self: *ChatHistory) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.clearRetainingCapacity();
    }

    pub fn getMessages(self: *const ChatHistory) []const ChatMessage {
        return self.messages.items;
    }
};

/// Chat window state
pub const ChatWindow = struct {
    allocator: std.mem.Allocator,
    history: ChatHistory,
    current_input: std.ArrayList(u8),
    current_provider: []const u8,
    width_percent: u8, // Percentage of screen width
    visible: bool,

    /// FFI function pointer to Thanos complete
    completion_fn: ?*const fn (
        prompt: [*:0]const u8,
        language: [*:0]const u8,
        max_tokens: c_int,
    ) callconv(.C) [*:0]const u8,

    pub fn init(allocator: std.mem.Allocator, width_percent: u8) !ChatWindow {
        return .{
            .allocator = allocator,
            .history = ChatHistory.init(allocator),
            .current_input = std.ArrayList(u8).init(allocator),
            .current_provider = try allocator.dupe(u8, "ollama"),
            .width_percent = width_percent,
            .visible = false,
            .completion_fn = null,
        };
    }

    pub fn deinit(self: *ChatWindow) void {
        self.history.deinit();
        self.current_input.deinit();
        self.allocator.free(self.current_provider);
    }

    /// Set FFI completion function
    pub fn setCompletionFunction(
        self: *ChatWindow,
        func: *const fn (
            prompt: [*:0]const u8,
            language: [*:0]const u8,
            max_tokens: c_int,
        ) callconv(.C) [*:0]const u8,
    ) void {
        self.completion_fn = func;
    }

    /// Show/hide chat window
    pub fn show(self: *ChatWindow) void {
        self.visible = true;
    }

    pub fn hide(self: *ChatWindow) void {
        self.visible = false;
    }

    pub fn toggle(self: *ChatWindow) void {
        self.visible = !self.visible;
    }

    /// Set current AI provider
    pub fn setProvider(self: *ChatWindow, provider: []const u8) !void {
        self.allocator.free(self.current_provider);
        self.current_provider = try self.allocator.dupe(u8, provider);
    }

    /// Add character to current input
    pub fn addChar(self: *ChatWindow, char: u8) !void {
        try self.current_input.append(char);
    }

    /// Backspace current input
    pub fn backspace(self: *ChatWindow) void {
        if (self.current_input.items.len > 0) {
            _ = self.current_input.pop();
        }
    }

    /// Clear current input
    pub fn clearInput(self: *ChatWindow) void {
        self.current_input.clearRetainingCapacity();
    }

    /// Get current input as string
    pub fn getCurrentInput(self: *const ChatWindow) []const u8 {
        return self.current_input.items;
    }

    /// Send current message and get AI response
    pub fn sendMessage(self: *ChatWindow) !void {
        const input = self.current_input.items;
        if (input.len == 0) return;

        // Add user message to history
        var user_msg = try ChatMessage.init(self.allocator, .user, input);
        try self.history.addMessage(user_msg);

        // Clear input
        self.clearInput();

        // Request AI response via FFI
        if (self.completion_fn) |func| {
            // Convert to C string
            const prompt_z = try self.allocator.dupeZ(u8, input);
            defer self.allocator.free(prompt_z);

            // Call native function
            const result_ptr = func(prompt_z.ptr, "markdown".ptr, 2000);
            const result = std.mem.span(result_ptr);

            // Add assistant response to history
            var assistant_msg = try ChatMessage.init(self.allocator, .assistant, result);
            try assistant_msg.setProvider(self.current_provider);
            try self.history.addMessage(assistant_msg);
        } else {
            // No FFI function, show error
            var error_msg = try ChatMessage.init(
                self.allocator,
                .system,
                "Error: AI completion function not available",
            );
            try self.history.addMessage(error_msg);
        }
    }

    /// Stream message response (call callback for each chunk)
    pub fn sendMessageStreaming(
        self: *ChatWindow,
        callback: *const fn (chunk: []const u8, user_data: ?*anyopaque) void,
        user_data: ?*anyopaque,
    ) !void {
        const input = self.current_input.items;
        if (input.len == 0) return;

        // Add user message to history
        var user_msg = try ChatMessage.init(self.allocator, .user, input);
        try self.history.addMessage(user_msg);

        // Clear input
        self.clearInput();

        // Create empty assistant message that we'll update
        var assistant_msg = try ChatMessage.init(self.allocator, .assistant, "");
        try assistant_msg.setProvider(self.current_provider);

        // TODO: Call streaming FFI function when available
        // For now, just call regular completion
        if (self.completion_fn) |func| {
            const prompt_z = try self.allocator.dupeZ(u8, input);
            defer self.allocator.free(prompt_z);

            const result_ptr = func(prompt_z.ptr, "markdown".ptr, 2000);
            const result = std.mem.span(result_ptr);

            // Update message content
            self.allocator.free(assistant_msg.content);
            assistant_msg.content = try self.allocator.dupe(u8, result);

            // Call callback with full result
            callback(result, user_data);
        }

        try self.history.addMessage(assistant_msg);
    }

    /// Clear chat history
    pub fn clearHistory(self: *ChatWindow) void {
        self.history.clear();
    }

    /// Render chat window to buffer
    pub fn render(self: *const ChatWindow, writer: anytype, width: u32, height: u32) !void {
        if (!self.visible) return;

        // Calculate window dimensions
        const window_width = (width * self.width_percent) / 100;
        const window_height = height - 2; // Leave space for input

        // Draw border
        try writer.writeAll("╭");
        try writer.writeByteNTimes('─', window_width - 2);
        try writer.writeAll("╮\n");

        // Draw title
        const title = "Thanos AI Chat";
        const padding = (window_width - title.len - 2) / 2;
        try writer.writeAll("│");
        try writer.writeByteNTimes(' ', padding);
        try writer.writeAll(title);
        try writer.writeByteNTimes(' ', window_width - padding - title.len - 2);
        try writer.writeAll("│\n");

        // Draw separator
        try writer.writeAll("├");
        try writer.writeByteNTimes('─', window_width - 2);
        try writer.writeAll("┤\n");

        // Render messages
        const messages = self.history.getMessages();
        const start_idx = if (messages.len > window_height - 5)
            messages.len - (window_height - 5)
        else
            0;

        for (messages[start_idx..]) |msg| {
            try self.renderMessage(writer, msg, window_width);
        }

        // Fill remaining space
        const rendered_lines = messages.len - start_idx;
        const empty_lines = if (window_height > rendered_lines + 5)
            window_height - rendered_lines - 5
        else
            0;

        for (0..empty_lines) |_| {
            try writer.writeAll("│");
            try writer.writeByteNTimes(' ', window_width - 2);
            try writer.writeAll("│\n");
        }

        // Draw input separator
        try writer.writeAll("├");
        try writer.writeByteNTimes('─', window_width - 2);
        try writer.writeAll("┤\n");

        // Draw input area
        try writer.writeAll("│ > ");
        const input = self.current_input.items;
        const max_input_len = window_width - 6;
        const display_input = if (input.len > max_input_len)
            input[input.len - max_input_len ..]
        else
            input;

        try writer.writeAll(display_input);
        try writer.writeByteNTimes(' ', window_width - display_input.len - 6);
        try writer.writeAll("│\n");

        // Draw bottom border
        try writer.writeAll("╰");
        try writer.writeByteNTimes('─', window_width - 2);
        try writer.writeAll("╯\n");
    }

    /// Render single message
    fn renderMessage(self: *const ChatWindow, writer: anytype, msg: ChatMessage, width: u32) !void {
        // Format: "│ [Role]: content     │"
        const role_str = msg.role.toString();
        const prefix = try std.fmt.allocPrint(self.allocator, "{s}: ", .{role_str});
        defer self.allocator.free(prefix);

        // Word wrap content
        var lines = std.mem.split(u8, msg.content, "\n");
        var is_first = true;

        while (lines.next()) |line| {
            const full_line = if (is_first)
                try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, line })
            else
                try std.fmt.allocPrint(self.allocator, "  {s}", .{line});
            defer self.allocator.free(full_line);

            is_first = false;

            // Wrap if too long
            var offset: usize = 0;
            while (offset < full_line.len) {
                const remaining = full_line.len - offset;
                const chunk_len = @min(remaining, width - 4);
                const chunk = full_line[offset .. offset + chunk_len];

                try writer.writeAll("│ ");
                try writer.writeAll(chunk);
                try writer.writeByteNTimes(' ', width - chunk.len - 4);
                try writer.writeAll("│\n");

                offset += chunk_len;
            }
        }

        // Empty line after message
        try writer.writeAll("│");
        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeAll("│\n");
    }
};

// Tests
test "chat message" {
    var msg = try ChatMessage.init(std.testing.allocator, .user, "Hello AI!");
    defer msg.deinit();

    try std.testing.expectEqualStrings("Hello AI!", msg.content);
    try std.testing.expectEqual(MessageRole.user, msg.role);
}

test "chat history" {
    var history = ChatHistory.init(std.testing.allocator);
    defer history.deinit();

    var msg1 = try ChatMessage.init(std.testing.allocator, .user, "Question");
    try history.addMessage(msg1);

    var msg2 = try ChatMessage.init(std.testing.allocator, .assistant, "Answer");
    try history.addMessage(msg2);

    const messages = history.getMessages();
    try std.testing.expectEqual(@as(usize, 2), messages.len);
}

test "chat window init" {
    var window = try ChatWindow.init(std.testing.allocator, 50);
    defer window.deinit();

    try std.testing.expect(!window.visible);
    try std.testing.expectEqual(@as(u8, 50), window.width_percent);
}

//! Provider switcher UI for selecting AI providers
//! Interactive popup menu for switching between Ollama, Claude, GPT-4, Grok, Copilot, etc.

const std = @import("std");

/// Provider info
pub const ProviderInfo = struct {
    name: []const u8,
    display_name: []const u8,
    available: bool,
    healthy: bool,
    description: []const u8,

    pub fn init(name: []const u8, display_name: []const u8, description: []const u8) ProviderInfo {
        return .{
            .name = name,
            .display_name = display_name,
            .available = false,
            .healthy = false,
            .description = description,
        };
    }
};

/// Provider switcher state
pub const ProviderSwitcher = struct {
    allocator: std.mem.Allocator,
    providers: std.ArrayList(ProviderInfo),
    current_selection: usize,
    current_provider: []const u8,
    visible: bool,

    /// FFI function pointers
    list_providers_fn: ?*const fn () callconv(.C) [*:0]const u8,
    switch_provider_fn: ?*const fn (provider: [*:0]const u8) callconv(.C) c_int,
    get_current_provider_fn: ?*const fn () callconv(.C) [*:0]const u8,

    pub fn init(allocator: std.mem.Allocator) !ProviderSwitcher {
        var switcher = ProviderSwitcher{
            .allocator = allocator,
            .providers = std.ArrayList(ProviderInfo).init(allocator),
            .current_selection = 0,
            .current_provider = try allocator.dupe(u8, "ollama"),
            .visible = false,
            .list_providers_fn = null,
            .switch_provider_fn = null,
            .get_current_provider_fn = null,
        };

        // Add default providers
        try switcher.addDefaultProviders();

        return switcher;
    }

    pub fn deinit(self: *ProviderSwitcher) void {
        self.providers.deinit();
        self.allocator.free(self.current_provider);
    }

    /// Set FFI function pointers
    pub fn setFFIFunctions(
        self: *ProviderSwitcher,
        list_fn: *const fn () callconv(.C) [*:0]const u8,
        switch_fn: *const fn (provider: [*:0]const u8) callconv(.C) c_int,
        get_current_fn: *const fn () callconv(.C) [*:0]const u8,
    ) void {
        self.list_providers_fn = list_fn;
        self.switch_provider_fn = switch_fn;
        self.get_current_provider_fn = get_current_fn;
    }

    /// Add default providers (can be updated by FFI later)
    fn addDefaultProviders(self: *ProviderSwitcher) !void {
        const default_providers = [_]ProviderInfo{
            ProviderInfo.init("ollama", "Ollama", "Local models (CodeLlama, DeepSeek, etc.)"),
            ProviderInfo.init("anthropic", "Claude (Anthropic)", "Claude Sonnet 4.5 - best for complex code"),
            ProviderInfo.init("openai", "GPT-4 (OpenAI)", "GPT-4 Turbo - general purpose AI"),
            ProviderInfo.init("xai", "Grok (xAI)", "Fast, conversational AI from xAI"),
            ProviderInfo.init("github_copilot", "GitHub Copilot", "Code completions from GitHub"),
            ProviderInfo.init("google", "Gemini (Google)", "Multimodal AI from Google"),
            ProviderInfo.init("omen", "Omen (Auto)", "Intelligent routing & cost optimization"),
        };

        for (default_providers) |provider| {
            try self.providers.append(provider);
        }
    }

    /// Refresh provider list from FFI
    pub fn refreshProviders(self: *ProviderSwitcher) !void {
        if (self.list_providers_fn) |func| {
            const json_ptr = func();
            const json = std.mem.span(json_ptr);

            // Parse JSON response
            // Expected format: [{"name":"ollama","available":true,"healthy":true},...]
            try self.parseProvidersJSON(json);

            // Update current provider
            if (self.get_current_provider_fn) |get_fn| {
                const current_ptr = get_fn();
                const current = std.mem.span(current_ptr);

                self.allocator.free(self.current_provider);
                self.current_provider = try self.allocator.dupe(u8, current);
            }
        }
    }

    /// Parse providers JSON response
    fn parseProvidersJSON(self: *ProviderSwitcher, json: []const u8) !void {
        // Simple JSON parsing for provider list
        // Format: [{"name":"ollama","available":true,"healthy":true},...]

        // For now, just mark all as available if JSON is not empty
        if (json.len > 2) { // More than "[]"
            for (self.providers.items) |*provider| {
                // Check if provider name appears in JSON
                if (std.mem.indexOf(u8, json, provider.name)) |_| {
                    // Check if it's marked as available
                    const search = try std.fmt.allocPrint(
                        self.allocator,
                        "\"{s}\",\"available\":true",
                        .{provider.name},
                    );
                    defer self.allocator.free(search);

                    provider.available = std.mem.indexOf(u8, json, search) != null or
                        std.mem.indexOf(u8, json, "\"available\": true") != null or
                        std.mem.indexOf(u8, json, "\"available\":true") != null;

                    provider.healthy = provider.available;
                }
            }
        }
    }

    /// Show provider switcher
    pub fn show(self: *ProviderSwitcher) !void {
        try self.refreshProviders();
        self.visible = true;

        // Set selection to current provider
        for (self.providers.items, 0..) |provider, i| {
            if (std.mem.eql(u8, provider.name, self.current_provider)) {
                self.current_selection = i;
                break;
            }
        }
    }

    /// Hide provider switcher
    pub fn hide(self: *ProviderSwitcher) void {
        self.visible = false;
    }

    /// Move selection up
    pub fn selectPrev(self: *ProviderSwitcher) void {
        if (self.current_selection > 0) {
            self.current_selection -= 1;
        }
    }

    /// Move selection down
    pub fn selectNext(self: *ProviderSwitcher) void {
        if (self.current_selection < self.providers.items.len - 1) {
            self.current_selection += 1;
        }
    }

    /// Confirm selection and switch provider
    pub fn confirmSelection(self: *ProviderSwitcher) !bool {
        const selected = self.providers.items[self.current_selection];

        if (!selected.available) {
            return false; // Can't switch to unavailable provider
        }

        if (self.switch_provider_fn) |func| {
            const provider_z = try self.allocator.dupeZ(u8, selected.name);
            defer self.allocator.free(provider_z);

            const result = func(provider_z.ptr);

            if (result == 1) {
                // Update current provider
                self.allocator.free(self.current_provider);
                self.current_provider = try self.allocator.dupe(u8, selected.name);

                self.hide();
                return true;
            }
        }

        return false;
    }

    /// Render provider switcher UI
    pub fn render(self: *const ProviderSwitcher, writer: anytype, width: u32, height: u32) !void {
        if (!self.visible) return;

        // Calculate window dimensions
        const win_width = @min(width - 4, 60);
        const win_height = @min(height - 4, self.providers.items.len + 6);

        // Center window
        const start_col = (width - win_width) / 2;
        const start_row = (height - win_height) / 2;

        _ = start_col;
        _ = start_row;

        // Draw border
        try writer.writeAll("╭");
        try writer.writeByteNTimes('─', win_width - 2);
        try writer.writeAll("╮\n");

        // Title
        const title = "Select AI Provider";
        const title_padding = (win_width - title.len - 2) / 2;
        try writer.writeAll("│");
        try writer.writeByteNTimes(' ', title_padding);
        try writer.writeAll(title);
        try writer.writeByteNTimes(' ', win_width - title_padding - title.len - 2);
        try writer.writeAll("│\n");

        // Separator
        try writer.writeAll("├");
        try writer.writeByteNTimes('─', win_width - 2);
        try writer.writeAll("┤\n");

        // Provider list
        for (self.providers.items, 0..) |provider, i| {
            try self.renderProviderRow(writer, provider, i, win_width);
        }

        // Separator
        try writer.writeAll("├");
        try writer.writeByteNTimes('─', win_width - 2);
        try writer.writeAll("┤\n");

        // Help text
        const help = "↑↓: Navigate  Enter: Select  Esc: Cancel";
        try writer.writeAll("│ ");
        try writer.writeAll(help);
        try writer.writeByteNTimes(' ', win_width - help.len - 4);
        try writer.writeAll("│\n");

        // Bottom border
        try writer.writeAll("╰");
        try writer.writeByteNTimes('─', win_width - 2);
        try writer.writeAll("╯\n");
    }

    /// Render single provider row
    fn renderProviderRow(self: *const ProviderSwitcher, writer: anytype, provider: ProviderInfo, index: usize, width: u32) !void {
        const is_selected = index == self.current_selection;
        const is_current = std.mem.eql(u8, provider.name, self.current_provider);

        // Selection indicator
        const indicator = if (is_selected) ">" else " ";

        // Status indicator
        const status = if (!provider.available)
            "✗"
        else if (is_current)
            "●"
        else
            "○";

        // Color
        const color = if (!provider.available)
            "\x1b[31m" // Red
        else if (is_current)
            "\x1b[32m" // Green
        else if (is_selected)
            "\x1b[36m" // Cyan
        else
            "\x1b[0m"; // Reset

        const reset = "\x1b[0m";

        // Format: "│ > ● Provider Name (description)    │"
        try writer.writeAll("│ ");
        try writer.writeAll(indicator);
        try writer.writeAll(" ");
        try writer.writeAll(color);
        try writer.writeAll(status);
        try writer.writeAll(" ");
        try writer.writeAll(provider.display_name);

        const desc = try std.fmt.allocPrint(self.allocator, " ({s})", .{provider.description});
        defer self.allocator.free(desc);

        const text_len = provider.display_name.len + desc.len + 5; // 5 for "│ > ● "

        if (text_len < width - 4) {
            try writer.writeAll(desc);
            try writer.writeAll(reset);
            try writer.writeByteNTimes(' ', width - text_len - 2);
        } else {
            try writer.writeAll(reset);
            try writer.writeByteNTimes(' ', width - provider.display_name.len - 9);
        }

        try writer.writeAll("│\n");
    }
};

// Tests
test "provider switcher init" {
    var switcher = try ProviderSwitcher.init(std.testing.allocator);
    defer switcher.deinit();

    try std.testing.expect(!switcher.visible);
    try std.testing.expect(switcher.providers.items.len > 0);
}

test "provider navigation" {
    var switcher = try ProviderSwitcher.init(std.testing.allocator);
    defer switcher.deinit();

    try switcher.show();

    const initial = switcher.current_selection;
    switcher.selectNext();
    try std.testing.expect(switcher.current_selection > initial);

    switcher.selectPrev();
    try std.testing.expectEqual(initial, switcher.current_selection);
}

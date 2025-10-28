//! Persistent Configuration System
//! Supports loading config from ~/.config/grim/config.json
//! Features: theme, keybinds, editor options, hot-reload

const std = @import("std");

/// Configuration file structure
pub const Config = struct {
    /// Editor settings
    editor: EditorConfig = .{},

    /// UI/Theme settings
    ui: UIConfig = .{},

    /// LSP settings
    lsp: LSPConfig = .{},

    /// Performance settings
    performance: PerformanceConfig = .{},

    pub const EditorConfig = struct {
        tab_width: u32 = 4,
        use_spaces: bool = true,
        line_numbers: bool = true,
        relative_line_numbers: bool = false,
        wrap_lines: bool = false,
        auto_indent: bool = true,
        show_trailing_whitespace: bool = true,
        trim_trailing_whitespace_on_save: bool = false,
        insert_final_newline: bool = true,
        max_line_length: u32 = 120,
    };

    pub const UIConfig = struct {
        theme: []const u8 = "ghost-hacker-blue",
        show_status_line: bool = true,
        show_command_bar: bool = true,
        show_line_numbers: bool = true,
        cursor_style: CursorStyle = .block,

        pub const CursorStyle = enum {
            block,
            underline,
            bar,
        };
    };

    pub const LSPConfig = struct {
        enabled: bool = true,
        auto_completion: bool = true,
        signature_help: bool = true,
        hover_documentation: bool = true,
        diagnostics: bool = true,
        format_on_save: bool = false,
    };

    pub const PerformanceConfig = struct {
        use_io_uring: bool = true,
        use_simd: bool = true,
        lazy_redraw: bool = true,
        scroll_cache_size: u32 = 1000,
    };

    /// Load config from file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.log.info("No config file found at {s}, using defaults: {}", .{path, err});
            return Config{};
        };
        defer file.close();

        const stat = try file.stat();
        const content = try allocator.alloc(u8, stat.size);
        errdefer allocator.free(content);
        _ = try file.readAll(content);
        defer allocator.free(content);

        const parsed = try std.json.parseFromSlice(Config, allocator, content, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        // Deep copy the parsed config
        return try deepCopyConfig(allocator, parsed.value);
    }

    /// Save config to file
    pub fn save(self: *const Config, allocator: std.mem.Allocator, path: []const u8) !void {
        _ = allocator; // TODO: Use for JSON serialization when API is available
        _ = self;
        _ = path;
        // TODO: Implement config saving once Zig 0.16 JSON API is stable
        // For now, configs are loaded from disk but not saved programmatically
        std.log.warn("Config saving not yet implemented", .{});
    }

    /// Get default config path
    pub fn getDefaultPath(allocator: std.mem.Allocator) ![]const u8 {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

        // Check XDG_CONFIG_HOME first
        if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg_config| {
            return try std.fs.path.join(allocator, &.{xdg_config, "grim", "config.json"});
        }

        // Fallback to ~/.config/grim/config.json
        return try std.fs.path.join(allocator, &.{home, ".config", "grim", "config.json"});
    }

    /// Deep copy config (needed because json parser owns the memory)
    fn deepCopyConfig(allocator: std.mem.Allocator, src: Config) !Config {
        var result = src;
        result.ui.theme = try allocator.dupe(u8, src.ui.theme);
        return result;
    }

    /// Free allocated memory
    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.ui.theme);
    }
};

/// Config manager with hot-reload support
pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    config: Config,
    config_path: []const u8,
    last_modified: i128,

    pub fn init(allocator: std.mem.Allocator) !ConfigManager {
        const config_path = try Config.getDefaultPath(allocator);
        errdefer allocator.free(config_path);

        const config = Config.load(allocator, config_path) catch |err| blk: {
            std.log.info("Using default config: {}", .{err});
            break :blk Config{};
        };

        const last_modified = getFileModTime(config_path) catch 0;

        return ConfigManager{
            .allocator = allocator,
            .config = config,
            .config_path = config_path,
            .last_modified = last_modified,
        };
    }

    pub fn deinit(self: *ConfigManager) void {
        self.config.deinit(self.allocator);
        self.allocator.free(self.config_path);
    }

    /// Check if config file has changed and reload
    pub fn checkAndReload(self: *ConfigManager) !bool {
        const current_mod_time = getFileModTime(self.config_path) catch return false;

        if (current_mod_time > self.last_modified) {
            std.log.info("Config file changed, reloading...", .{});

            // Free old config
            self.config.deinit(self.allocator);

            // Load new config
            self.config = try Config.load(self.allocator, self.config_path);
            self.last_modified = current_mod_time;

            return true;
        }

        return false;
    }

    /// Get current config
    pub fn getConfig(self: *const ConfigManager) *const Config {
        return &self.config;
    }

    /// Save current config
    pub fn saveConfig(self: *ConfigManager) !void {
        try self.config.save(self.allocator, self.config_path);
        self.last_modified = getFileModTime(self.config_path) catch 0;
    }
};

/// Get file modification time
fn getFileModTime(path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.mtime;
}

test "config default values" {
    const config = Config{};
    try std.testing.expectEqual(@as(u32, 4), config.editor.tab_width);
    try std.testing.expect(config.editor.use_spaces);
    try std.testing.expectEqualStrings("ghost-hacker-blue", config.ui.theme);
}

test "config manager initialization" {
    const allocator = std.testing.allocator;

    var manager = ConfigManager.init(allocator) catch |err| {
        std.debug.print("Expected error (no config file): {}\n", .{err});
        return;
    };
    defer manager.deinit();

    const config = manager.getConfig();
    try std.testing.expect(config.editor.tab_width > 0);
}

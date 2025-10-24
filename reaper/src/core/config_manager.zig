//! core/config_manager.zig
//! Central configuration management using Flare + Ghostlang integration

const std = @import("std");
const flare = @import("flare");
const zlog = @import("zlog");
const plugin_loader_mod = @import("plugin_loader.zig");
const PluginLoader = plugin_loader_mod.PluginLoader;
const PluginConfig = plugin_loader_mod.PluginConfig;
const GhostlangRuntime = @import("ghostlang_runtime.zig").GhostlangRuntime;
const LSPManager = @import("lsp_manager.zig").LSPManager;
const CommandRegistry = @import("command_registry.zig").CommandRegistry;
const KeymapManager = @import("keymap_manager.zig").KeymapManager;
const EventSystem = @import("event_system.zig").EventSystem;
const ThemeManager = @import("theme_manager.zig").ThemeManager;
const SyntaxHighlighter = @import("syntax_highlighter.zig").SyntaxHighlighter;

fn appendJsonString(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    const hex_digits = "0123456789abcdef";
    try buffer.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '"' => try buffer.appendSlice(allocator, "\\\""),
            '\\' => try buffer.appendSlice(allocator, "\\\\"),
            '\n' => try buffer.appendSlice(allocator, "\\n"),
            '\r' => try buffer.appendSlice(allocator, "\\r"),
            '\t' => try buffer.appendSlice(allocator, "\\t"),
            else => {
                if (ch < 0x20) {
                    var buf = [_]u8{ '\\', 'u', '0', '0', 0, 0 };
                    buf[4] = hex_digits[@as(usize, ch >> 4)];
                    buf[5] = hex_digits[@as(usize, ch & 0xF)];
                    try buffer.appendSlice(allocator, buf[0..]);
                } else {
                    try buffer.append(allocator, ch);
                }
            },
        }
    }
    try buffer.append(allocator, '"');
}

fn appendUnsigned(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [20]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    try buffer.appendSlice(allocator, str);
}

fn appendSigned(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i64) !void {
    var buf: [21]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    try buffer.appendSlice(allocator, str);
}

pub const Highlight = struct {
    start: usize,
    stop: usize,
    token_type: []const u8,
};

var global_manager: ?*ConfigManager = null;

pub fn setGlobalManager(manager: *ConfigManager) void {
    global_manager = manager;
}

pub fn globalManager() ?*ConfigManager {
    return global_manager;
}

fn globalLspManager() ?*LSPManager {
    const manager = global_manager orelse return null;
    return manager.lsp_manager;
}

fn sliceFromCString(ptr: [*:0]const u8) []const u8 {
    return std.mem.span(ptr);
}

pub export fn grim_plugin_install(name_ptr: [*:0]const u8, version_ptr: [*:0]const u8) bool {
    const manager = global_manager orelse {
        zlog.err("grim_plugin_install called before ConfigManager initialized", .{});
        return false;
    };

    const name = sliceFromCString(name_ptr);
    const version = sliceFromCString(version_ptr);

    if (name.len == 0) {
        zlog.err("grim_plugin_install requires plugin name", .{});
        return false;
    }

    manager.installPlugin(name, version) catch |err| {
        zlog.err("Failed to install plugin {s}: {any}", .{ name, err });
        return false;
    };

    return true;
}

pub export fn grim_plugin_update(name_ptr: [*:0]const u8, version_ptr: [*:0]const u8) bool {
    const manager = global_manager orelse {
        zlog.err("grim_plugin_update called before ConfigManager initialized", .{});
        return false;
    };

    const name = sliceFromCString(name_ptr);
    const version = sliceFromCString(version_ptr);

    if (name.len == 0) {
        zlog.err("grim_plugin_update requires plugin name", .{});
        return false;
    }

    manager.updatePlugin(name, version) catch |err| {
        zlog.err("Failed to update plugin {s}: {any}", .{ name, err });
        return false;
    };

    return true;
}

pub export fn grim_lsp_start(language_ptr: [*:0]const u8, server_ptr: [*:0]const u8) bool {
    const lsp_manager = globalLspManager() orelse {
        zlog.err("grim_lsp_start called without ConfigManager", .{});
        return false;
    };

    const language = sliceFromCString(language_ptr);
    const server = sliceFromCString(server_ptr);

    if (language.len == 0 or server.len == 0) {
        zlog.warn("grim_lsp_start requires language and server", .{});
        return false;
    }

    _ = lsp_manager.ensureLanguage(language, server) catch |err| {
        zlog.err("Failed to ensure LSP {s}->{s}: {any}", .{ language, server, err });
        return false;
    };

    return true;
}

pub export fn grim_lsp_did_open(path_ptr: [*:0]const u8, language_ptr: [*:0]const u8, content_ptr: [*:0]const u8) bool {
    const lsp_manager = globalLspManager() orelse {
        zlog.err("grim_lsp_did_open called without ConfigManager", .{});
        return false;
    };

    const path = sliceFromCString(path_ptr);
    const language = sliceFromCString(language_ptr);
    const content = sliceFromCString(content_ptr);

    if (path.len == 0 or language.len == 0) {
        zlog.warn("grim_lsp_did_open requires path and language", .{});
        return false;
    }

    lsp_manager.didOpen(language, path, content) catch |err| {
        zlog.err("Failed to open document {s} ({s}): {any}", .{ path, language, err });
        return false;
    };

    return true;
}

pub export fn grim_lsp_did_change(path_ptr: [*:0]const u8, content_ptr: [*:0]const u8) bool {
    const lsp_manager = globalLspManager() orelse {
        zlog.err("grim_lsp_did_change called without ConfigManager", .{});
        return false;
    };

    const path = sliceFromCString(path_ptr);
    const content = sliceFromCString(content_ptr);

    if (path.len == 0) {
        zlog.warn("grim_lsp_did_change requires path", .{});
        return false;
    }

    lsp_manager.didChange(path, content) catch |err| {
        zlog.err("Failed to send change for {s}: {any}", .{ path, err });
        return false;
    };

    return true;
}

pub export fn grim_lsp_did_close(path_ptr: [*:0]const u8) bool {
    const lsp_manager = globalLspManager() orelse {
        zlog.err("grim_lsp_did_close called without ConfigManager", .{});
        return false;
    };

    const path = sliceFromCString(path_ptr);
    if (path.len == 0) {
        zlog.warn("grim_lsp_did_close requires path", .{});
        return false;
    }

    lsp_manager.didClose(path) catch |err| {
        zlog.err("Failed to close document {s}: {any}", .{ path, err });
        return false;
    };

    return true;
}

pub export fn grim_lsp_request_completion(path_ptr: [*:0]const u8, line: u32, character: u32) ?[*]const u8 {
    const lsp_manager = globalLspManager() orelse return null;
    const path = sliceFromCString(path_ptr);
    if (path.len == 0) return null;

    const response = lsp_manager.requestCompletion(path, line, character) catch |err| {
        zlog.err("Completion request failed for {s}: {any}", .{ path, err });
        return null;
    };
    defer lsp_manager.allocator.free(response);

    return lsp_manager.writeResponse(response) catch |err| {
        zlog.err("Failed to stage completion response: {any}", .{err});
        return null;
    };
}

pub export fn grim_lsp_request_hover(path_ptr: [*:0]const u8, line: u32, character: u32) ?[*]const u8 {
    const lsp_manager = globalLspManager() orelse return null;
    const path = sliceFromCString(path_ptr);
    if (path.len == 0) return null;

    const response = lsp_manager.requestHover(path, line, character) catch |err| {
        zlog.err("Hover request failed for {s}: {any}", .{ path, err });
        return null;
    };
    defer lsp_manager.allocator.free(response);

    return lsp_manager.writeResponse(response) catch |err| {
        zlog.err("Failed to stage hover response: {any}", .{err});
        return null;
    };
}

pub export fn grim_lsp_request_definition(path_ptr: [*:0]const u8, line: u32, character: u32) ?[*]const u8 {
    const lsp_manager = globalLspManager() orelse return null;
    const path = sliceFromCString(path_ptr);
    if (path.len == 0) return null;

    const response = lsp_manager.requestDefinition(path, line, character) catch |err| {
        zlog.err("Definition request failed for {s}: {any}", .{ path, err });
        return null;
    };
    defer lsp_manager.allocator.free(response);

    return lsp_manager.writeResponse(response) catch |err| {
        zlog.err("Failed to stage definition response: {any}", .{err});
        return null;
    };
}

pub export fn grim_lsp_request_diagnostics(path_ptr: [*:0]const u8) ?[*]const u8 {
    const lsp_manager = globalLspManager() orelse return null;
    const path = sliceFromCString(path_ptr);
    if (path.len == 0) return null;

    const response = lsp_manager.requestDiagnostics(path) catch |err| {
        zlog.err("Diagnostics request failed for {s}: {any}", .{ path, err });
        return null;
    };
    defer lsp_manager.allocator.free(response);

    return lsp_manager.writeResponse(response) catch |err| {
        zlog.err("Failed to stage diagnostics response: {any}", .{err});
        return null;
    };
}

pub const HighlightSet = struct {
    buffer: []u8,
    highlights: []Highlight,
    owns_buffer: bool = false,
    owns_highlights: bool = false,

    pub fn empty() HighlightSet {
        return HighlightSet{
            .buffer = &[_]u8{},
            .highlights = &[_]Highlight{},
            .owns_buffer = false,
            .owns_highlights = false,
        };
    }

    pub fn deinit(self: HighlightSet, allocator: std.mem.Allocator) void {
        if (self.owns_buffer) allocator.free(self.buffer);
        if (self.owns_highlights) allocator.free(self.highlights);
    }
};

pub const Theme = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(TokenColor),

    const TokenColor = struct {
        token: []const u8,
        color: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Theme {
        return Theme{
            .allocator = allocator,
            .entries = std.ArrayList(TokenColor).empty,
        };
    }

    pub fn deinit(self: *Theme) void {
        self.reset();
        self.entries.deinit(self.allocator);
    }

    pub fn reset(self: *Theme) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.token);
            self.allocator.free(entry.color);
        }
        self.entries.clearRetainingCapacity();
    }

    fn findIndex(self: *const Theme, token: []const u8) ?usize {
        for (self.entries.items, 0..) |entry, idx| {
            if (std.mem.eql(u8, entry.token, token)) {
                return idx;
            }
        }
        return null;
    }

    fn isHexDigit(ch: u8) bool {
        return (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
    }

    fn normalizeHexColor(self: *Theme, input: []const u8) ![]u8 {
        const whitespace = " \t\r\n";
        const trimmed = std.mem.trim(u8, input, whitespace);
        if (trimmed.len == 0) return error.InvalidColor;

        var owned: []u8 = undefined;

        if (trimmed[0] != '#') {
            if (trimmed.len == 6) {
                owned = try self.allocator.alloc(u8, 7);
                owned[0] = '#';
                std.mem.copyForwards(u8, owned[1..], trimmed);
            } else if (trimmed.len == 3) {
                owned = try self.allocator.alloc(u8, 7);
                owned[0] = '#';
                owned[1] = trimmed[0];
                owned[2] = trimmed[0];
                owned[3] = trimmed[1];
                owned[4] = trimmed[1];
                owned[5] = trimmed[2];
                owned[6] = trimmed[2];
            } else {
                return error.InvalidColor;
            }
        } else {
            switch (trimmed.len) {
                7 => {
                    owned = try self.allocator.alloc(u8, 7);
                    std.mem.copyForwards(u8, owned, trimmed);
                },
                4 => {
                    owned = try self.allocator.alloc(u8, 7);
                    owned[0] = '#';
                    owned[1] = trimmed[1];
                    owned[2] = trimmed[1];
                    owned[3] = trimmed[2];
                    owned[4] = trimmed[2];
                    owned[5] = trimmed[3];
                    owned[6] = trimmed[3];
                },
                else => return error.InvalidColor,
            }
        }

        const normalized = owned;
        for (normalized[1..]) |*ch| {
            if (!isHexDigit(ch.*)) {
                self.allocator.free(normalized);
                return error.InvalidColor;
            }
            ch.* = std.ascii.toLower(ch.*);
        }

        return normalized;
    }

    pub fn setToken(self: *Theme, token: []const u8, color_hex: []const u8) !void {
        const normalized = normalizeHexColor(self, color_hex) catch return error.InvalidColor;
        if (self.findIndex(token)) |idx| {
            self.allocator.free(self.entries.items[idx].color);
            self.entries.items[idx].color = normalized;
            return;
        }

        const owned = try self.allocator.dupe(u8, token);
        errdefer self.allocator.free(owned);
        errdefer self.allocator.free(normalized);
        try self.entries.append(self.allocator, TokenColor{
            .token = owned,
            .color = normalized,
        });
    }

    pub fn colorFor(self: *const Theme, token: []const u8) []const u8 {
        if (self.findIndex(token)) |idx| {
            return self.entries.items[idx].color;
        }

        if (self.findIndex("default")) |default_idx| {
            return self.entries.items[default_idx].color;
        }

        return "#c8d3f5";
    }

    pub fn applyDefaults(self: *Theme) !void {
        self.reset();
        const defaults = [_]struct {
            token: []const u8,
            color: []const u8,
        }{
            .{ .token = "default", .color = "#c8d3f5" },
            .{ .token = "foreground", .color = "#c8d3f5" },
            .{ .token = "background", .color = "#222436" },
            .{ .token = "cursor", .color = "#8aff80" },
            .{ .token = "selection", .color = "#a0ffe8" },
            .{ .token = "line_number", .color = "#636da6" },
            .{ .token = "status_bar_bg", .color = "#1e2030" },
            .{ .token = "status_bar_fg", .color = "#c0caf5" },
            .{ .token = "keyword", .color = "#89ddff" },
            .{ .token = "string", .color = "#c3e88d" },
            .{ .token = "number", .color = "#ffc777" },
            .{ .token = "comment", .color = "#57c7ff" },
            .{ .token = "function", .color = "#8aff80" },
            .{ .token = "type", .color = "#65bcff" },
            .{ .token = "variable", .color = "#c8d3f5" },
            .{ .token = "operator", .color = "#c0caf5" },
            .{ .token = "filename", .color = "#8aff80" },
            .{ .token = "match", .color = "#8aff80" },
        };

        for (defaults) |entry| {
            self.setToken(entry.token, entry.color) catch |err| {
                zlog.warn("Failed to apply default theme color {s}: {s}", .{ entry.token, @errorName(err) });
            };
        }
    }
};

pub const FuzzyEntry = struct {
    path: []const u8,
    highlights: []Highlight,
};

pub const FuzzyResults = struct {
    buffer: []u8,
    entries: []FuzzyEntry,
    owns_buffer: bool = false,
    owns_entries: bool = false,

    pub fn empty() FuzzyResults {
        return FuzzyResults{
            .buffer = &[_]u8{},
            .entries = &[_]FuzzyEntry{},
            .owns_buffer = false,
            .owns_entries = false,
        };
    }

    pub fn deinit(self: FuzzyResults, allocator: std.mem.Allocator) void {
        if (self.owns_entries) {
            for (self.entries) |entry| {
                if (entry.highlights.len > 0) allocator.free(entry.highlights);
            }
            allocator.free(self.entries);
        }

        if (self.owns_buffer and self.buffer.len > 0) {
            allocator.free(self.buffer);
        }
    }
};

const PluginLock = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(LockEntry),

    const LockEntry = struct {
        version: []u8,
        registry_url: []u8,
        installed_at: u64,
    };

    pub const EntryView = struct {
        version: []const u8,
        registry_url: []const u8,
        installed_at: u64,
    };

    pub fn init(allocator: std.mem.Allocator) PluginLock {
        return PluginLock{
            .allocator = allocator,
            .map = std.StringHashMap(LockEntry).init(allocator),
        };
    }

    pub fn deinit(self: *PluginLock) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.version);
            self.allocator.free(entry.value_ptr.registry_url);
        }
        self.map.deinit();
    }

    pub fn upsert(
        self: *PluginLock,
        name: []const u8,
        version: []const u8,
        registry_url: []const u8,
        installed_at: u64,
    ) !void {
        const gop = try self.map.getOrPut(name);
        if (!gop.found_existing) {
            gop.key_ptr.* = try self.allocator.dupe(u8, name);
        } else {
            self.allocator.free(gop.value_ptr.version);
            self.allocator.free(gop.value_ptr.registry_url);
        }

        gop.value_ptr.* = LockEntry{
            .version = try self.allocator.dupe(u8, version),
            .registry_url = try self.allocator.dupe(u8, registry_url),
            .installed_at = installed_at,
        };
    }

    pub fn get(self: *PluginLock, name: []const u8) ?EntryView {
        if (self.map.get(name)) |entry| {
            return EntryView{
                .version = entry.version,
                .registry_url = entry.registry_url,
                .installed_at = entry.installed_at,
            };
        }
        return null;
    }
};

const max_lockfile_size: usize = 1024 * 1024;

pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    flare_config: flare.Config,
    ghostlang_runtime: GhostlangRuntime,
    config_dir: []const u8,
    plugin_loader: *PluginLoader,
    plugin_dir: []const u8,
    theme: Theme,
    plugin_lock: PluginLock,
    lsp_manager: *LSPManager,
    command_registry: CommandRegistry,
    keymap_manager: KeymapManager,
    event_system: EventSystem,
    theme_manager: ThemeManager,
    syntax_highlighter: SyntaxHighlighter,

    pub fn init(allocator: std.mem.Allocator, config_dir: []const u8) !ConfigManager {
        // Initialize Flare config
        var flare_config = try flare.Config.init(allocator);
        errdefer flare_config.deinit();

        // Create a pointer to flare_config for GhostlangRuntime
        const flare_ptr = try allocator.create(flare.Config);
        errdefer allocator.destroy(flare_ptr);
        flare_ptr.* = flare_config;

        // Initialize Ghostlang runtime
        var ghostlang_runtime = try GhostlangRuntime.init(allocator, flare_ptr, config_dir);
        errdefer ghostlang_runtime.deinit();

        const plugin_dir = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "plugins" });
        errdefer allocator.free(plugin_dir);
        std.fs.cwd().makePath(plugin_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const default_registry = "https://registry.phantom.grim";
        const loader_config = PluginConfig{
            .registry_url = default_registry,
            .install_dir = plugin_dir,
        };
        const plugin_loader = try PluginLoader.init(allocator, loader_config);
        errdefer plugin_loader.deinit();

        const lsp_manager = try LSPManager.init(allocator);
        errdefer lsp_manager.deinit();

        var syntax_highlighter = try SyntaxHighlighter.init(allocator);
        var syntax_highlighter_cleanup = true;
        defer if (syntax_highlighter_cleanup) syntax_highlighter.deinit();

        var theme = Theme.init(allocator);
        errdefer theme.deinit();
        try theme.applyDefaults();

        var manager = ConfigManager{
            .allocator = allocator,
            .flare_config = flare_config,
            .ghostlang_runtime = ghostlang_runtime,
            .config_dir = config_dir,
            .plugin_loader = plugin_loader,
            .plugin_dir = plugin_dir,
            .theme = theme,
            .plugin_lock = PluginLock.init(allocator),
            .lsp_manager = lsp_manager,
            .command_registry = CommandRegistry.init(allocator),
            .keymap_manager = KeymapManager.init(allocator),
            .event_system = EventSystem.init(allocator),
            .theme_manager = ThemeManager.init(allocator),
            .syntax_highlighter = syntax_highlighter,
        };
        errdefer manager.plugin_lock.deinit();

        syntax_highlighter_cleanup = false;

        manager.plugin_loader.host_adapter.setCommandRegistry(&manager.command_registry);
        manager.plugin_loader.host_adapter.setKeymapManager(&manager.keymap_manager);
        manager.plugin_loader.host_adapter.setEventSystem(&manager.event_system);
        manager.plugin_loader.host_adapter.setThemeManager(&manager.theme_manager);
        manager.plugin_loader.host_adapter.setLSPManager(manager.lsp_manager);
        manager.plugin_loader.host_adapter.setSyntaxHighlighter(&manager.syntax_highlighter);

        manager.loadLockfile() catch |err| {
            zlog.warn("Failed to load plugin lockfile: {any}", .{err});
        };

        return manager;
    }

    pub fn deinit(self: *ConfigManager) void {
        self.plugin_lock.deinit();
        self.syntax_highlighter.deinit();
        self.theme_manager.deinit();
        self.event_system.deinit();
        self.keymap_manager.deinit();
        self.command_registry.deinit();
        self.theme.deinit();
        self.lsp_manager.deinit();
        self.plugin_loader.deinit();
        self.ghostlang_runtime.deinit();
        self.flare_config.deinit();
        self.allocator.free(self.plugin_dir);
    }

    /// Load all configuration files in order
    pub fn loadConfiguration(self: *ConfigManager) !void {
        zlog.info("Loading phantom.grim configuration", .{});

        // Load in order of precedence (lowest to highest):
        // 1. Defaults
        try self.loadDefaults();

        // 2. Bootstrap init script (may load plugins)
        try self.loadInitScript();

        // 3. User configuration
        try self.loadUserConfig();

        // 4. Plugin configurations
        try self.loadPluginConfigs();

        try self.refreshTheme();

        zlog.info("Configuration loaded successfully", .{});
    }

    fn loadInitScript(self: *ConfigManager) !void {
        const init_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.config_dir, "init.gza" });
        defer self.allocator.free(init_path);

        if (std.fs.cwd().access(init_path, .{})) {
            try self.ghostlang_runtime.loadConfigFile(init_path);
        } else |_| {
            zlog.info("No init.gza found at: {s}", .{init_path});
        }
    }

    /// Load default configuration files
    fn loadDefaults(self: *ConfigManager) !void {
        const defaults = [_][]const u8{
            "runtime/defaults/options.gza",
            "runtime/defaults/keymaps.gza",
            "runtime/defaults/autocmds.gza",
        };

        for (defaults) |config_file| {
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.config_dir, config_file });
            defer self.allocator.free(full_path);

            if (std.fs.cwd().access(full_path, .{})) {
                try self.ghostlang_runtime.loadConfigFile(full_path);
            } else |_| {
                zlog.warn("Default config file not found: {s}", .{full_path});
            }
        }
    }

    /// Load user configuration
    fn loadUserConfig(self: *ConfigManager) !void {
        const user_config_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.config_dir, "lua/user/config.gza" });
        defer self.allocator.free(user_config_path);

        if (std.fs.cwd().access(user_config_path, .{})) {
            try self.ghostlang_runtime.loadConfigFile(user_config_path);
        } else |_| {
            zlog.info("No user config found at: {s}", .{user_config_path});
        }
    }

    /// Load plugin configurations
    fn loadPluginConfigs(self: *ConfigManager) !void {
        try self.plugin_loader.loadInstalled();
    }

    fn lockfilePath(self: *ConfigManager) ![]u8 {
        return std.fs.path.join(self.allocator, &[_][]const u8{ self.config_dir, "plugins.lock" });
    }

    fn loadLockfile(self: *ConfigManager) !void {
        const path = try self.lockfilePath();
        defer self.allocator.free(path);

        const limit = std.Io.Limit.limited(max_lockfile_size);
        const data = std.fs.cwd().readFileAlloc(path, self.allocator, limit) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer self.allocator.free(data);

        const PluginEntry = struct {
            name: []const u8,
            version: []const u8,
            registry_url: []const u8,
            installed_at: u64,
        };

        const LockFileSchema = struct {
            generated_at: ?i64 = null,
            plugins: []const PluginEntry = &[_]PluginEntry{},
        };

        const parsed = try std.json.parseFromSlice(LockFileSchema, self.allocator, data, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        for (parsed.value.plugins) |entry| {
            if (entry.name.len == 0) continue;
            self.plugin_lock.upsert(entry.name, entry.version, entry.registry_url, entry.installed_at) catch |err| {
                zlog.err("Failed to record plugin from lockfile {s}: {any}", .{ entry.name, err });
            };
        }
    }

    fn writeLockfile(self: *ConfigManager) !void {
        const path = try self.lockfilePath();
        defer self.allocator.free(path);

        const LockFileEntry = struct {
            name: []const u8,
            version: []const u8,
            registry_url: []const u8,
            installed_at: u64,
        };

        var entries = std.ArrayList(LockFileEntry).empty;
        defer entries.deinit(self.allocator);

        var it = self.plugin_lock.map.iterator();
        while (it.next()) |entry| {
            try entries.append(self.allocator, LockFileEntry{
                .name = entry.key_ptr.*,
                .version = entry.value_ptr.version,
                .registry_url = entry.value_ptr.registry_url,
                .installed_at = entry.value_ptr.installed_at,
            });
        }

        const LockFileWrite = struct {
            generated_at: i64,
            plugins: []const LockFileEntry,
        };

        const lock_data = LockFileWrite{
            .generated_at = std.time.timestamp(),
            .plugins = entries.items,
        };

        var json_buffer = std.ArrayList(u8).empty;
        defer json_buffer.deinit(self.allocator);

        try json_buffer.append(self.allocator, '{');
        try json_buffer.appendSlice(self.allocator, "\"generated_at\":");
        try appendSigned(&json_buffer, self.allocator, lock_data.generated_at);
        try json_buffer.appendSlice(self.allocator, ",\"plugins\":[");

        for (lock_data.plugins, 0..) |entry, idx| {
            if (idx != 0) try json_buffer.append(self.allocator, ',');
            try json_buffer.append(self.allocator, '{');
            try json_buffer.appendSlice(self.allocator, "\"name\":");
            try appendJsonString(&json_buffer, self.allocator, entry.name);
            try json_buffer.appendSlice(self.allocator, ",\"version\":");
            try appendJsonString(&json_buffer, self.allocator, entry.version);
            try json_buffer.appendSlice(self.allocator, ",\"registry_url\":");
            try appendJsonString(&json_buffer, self.allocator, entry.registry_url);
            try json_buffer.appendSlice(self.allocator, ",\"installed_at\":");
            try appendUnsigned(&json_buffer, self.allocator, entry.installed_at);
            try json_buffer.append(self.allocator, '}');
        }

        try json_buffer.appendSlice(self.allocator, "]}");

        const json_text = try json_buffer.toOwnedSlice(self.allocator);
        defer self.allocator.free(json_text);

        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();

        try file.writeAll(json_text);
    }

    fn recordPluginInstall(self: *ConfigManager, name: []const u8, version: []const u8, installed_at: u64) !void {
        try self.plugin_lock.upsert(name, version, self.plugin_loader.config.registry_url, installed_at);
        try self.writeLockfile();
    }

    pub fn installPlugin(self: *ConfigManager, name: []const u8, version: []const u8) !void {
        if (name.len == 0) return error.InvalidPluginName;

        const default_version = "latest";
        const chosen_version = if (version.len == 0) default_version else version;

        try self.plugin_loader.fetchPlugin(name, chosen_version);
        const now = std.math.cast(u64, std.time.timestamp()) orelse 0;
        try self.recordPluginInstall(name, chosen_version, now);
    }

    pub fn updatePlugin(self: *ConfigManager, name: []const u8, version_hint: []const u8) !void {
        if (name.len == 0) return error.InvalidPluginName;

        const default_version = "latest";
        const chosen_version = blk: {
            if (version_hint.len != 0) break :blk version_hint;
            if (self.plugin_lock.get(name)) |entry| break :blk entry.version;
            break :blk default_version;
        };

        try self.plugin_loader.fetchPlugin(name, chosen_version);
        const now = std.math.cast(u64, std.time.timestamp()) orelse 0;
        try self.recordPluginInstall(name, chosen_version, now);
    }

    pub fn pluginLockEntry(self: *ConfigManager, name: []const u8) ?PluginLock.EntryView {
        return self.plugin_lock.get(name);
    }

    fn pluginPathToModuleName(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
        if (!std.mem.endsWith(u8, relative_path, ".gza")) {
            return error.InvalidPluginPath;
        }

        const stem_len = relative_path.len - ".gza".len;
        const prefix = "plugins.";
        const total_len = prefix.len + stem_len;
        var buffer = try allocator.alloc(u8, total_len);

        std.mem.copyForwards(u8, buffer[0..prefix.len], prefix);

        var i: usize = 0;
        while (i < stem_len) : (i += 1) {
            const ch = relative_path[i];
            buffer[prefix.len + i] = if (ch == '/' or ch == '\\') '.' else ch;
        }

        return buffer;
    }

    /// Get a configuration value
    pub fn get(self: *ConfigManager, key: []const u8) ?flare.Value {
        return self.flare_config.get(key);
    }

    /// Get a string configuration value
    pub fn getString(self: *ConfigManager, key: []const u8) ?[]const u8 {
        return self.flare_config.getString(key, null) catch null;
    }

    /// Get a boolean configuration value
    pub fn getBool(self: *ConfigManager, key: []const u8) ?bool {
        return self.flare_config.getBool(key);
    }

    /// Get an integer configuration value
    pub fn getInt(self: *ConfigManager, key: []const u8) ?i64 {
        return self.flare_config.getInt(key, null) catch null;
    }

    /// Fetch the latest statusline rendered by Ghostlang plugins.
    pub fn statuslineCurrent(self: *ConfigManager) !?[]u8 {
        return try self.ghostlang_runtime.statuslineCurrent();
    }

    /// Fetch a newline-separated listing of the file tree.
    pub fn fileTreeListing(self: *ConfigManager) !?[]u8 {
        return try self.ghostlang_runtime.fileTreeListing();
    }

    /// Fetch a newline-separated fuzzy finder listing for the given query.
    pub fn fuzzyFinderListing(self: *ConfigManager, query: []const u8) !?[]u8 {
        return try self.ghostlang_runtime.fuzzyFinderListing(query);
    }

    pub fn themeRef(self: *ConfigManager) *Theme {
        return &self.theme;
    }

    pub fn syntaxHighlighter(self: *ConfigManager) *SyntaxHighlighter {
        return &self.syntax_highlighter;
    }

    pub fn commandRegistry(self: *ConfigManager) *CommandRegistry {
        return &self.command_registry;
    }

    pub fn keymapManager(self: *ConfigManager) *KeymapManager {
        return &self.keymap_manager;
    }

    pub fn eventSystem(self: *ConfigManager) *EventSystem {
        return &self.event_system;
    }

    pub fn themeManager(self: *ConfigManager) *ThemeManager {
        return &self.theme_manager;
    }

    pub fn tokenColor(self: *ConfigManager, token: []const u8) []const u8 {
        return self.theme.colorFor(token);
    }

    fn applyThemeOverrides(self: *ConfigManager) !void {
        const overrides = [_]struct {
            key: []const u8,
            token: []const u8,
        }{
            .{ .key = "theme.tokens.default", .token = "default" },
            .{ .key = "theme.tokens.keyword", .token = "keyword" },
            .{ .key = "theme.tokens.string", .token = "string" },
            .{ .key = "theme.tokens.comment", .token = "comment" },
            .{ .key = "theme.tokens.type", .token = "type" },
            .{ .key = "theme.tokens.function", .token = "function" },
            .{ .key = "theme.tokens.number", .token = "number" },
            .{ .key = "theme.tokens.filename", .token = "filename" },
            .{ .key = "theme.tokens.match", .token = "match" },
        };

        for (overrides) |entry| {
            if (self.getString(entry.key)) |value| {
                self.theme.setToken(entry.token, value) catch |err| {
                    zlog.warn("Theme override {s} invalid color: {s}", .{ entry.key, @errorName(err) });
                };
                continue;
            }

            if (self.getInt(entry.key)) |value| {
                _ = value;
                zlog.warn("Theme override {s} using numeric values is deprecated; please use hex strings", .{entry.key});
            }
        }
    }

    fn loadThemeFromBridge(self: *ConfigManager) !void {
        const snippet =
            "local bridge = require(\"grim.bridge\")\n" ++
            "if not bridge or not bridge.theme then return nil end\n" ++
            "local theme = bridge.theme\n" ++
            "local names = {\"default\",\"foreground\",\"background\",\"cursor\",\"selection\",\"line_number\",\"status_bar_bg\",\"status_bar_fg\",\"keyword\",\"string\",\"number\",\"comment\",\"function\",\"type\",\"variable\",\"operator\",\"filename\",\"match\"}\n" ++
            "local out = {}\n" ++
            "for _, name in ipairs(names) do\n" ++
            "  local hex = theme.get_color(name)\n" ++
            "  if hex and #hex > 0 then\n" ++
            "    table.insert(out, name .. \"=\" .. hex)\n" ++
            "  end\n" ++
            "end\n" ++
            "return table.concat(out, \"\\n\")";

        const listing_opt = try self.ghostlang_runtime.evalStringDup(snippet);
        if (listing_opt == null) return;

        const listing = listing_opt.?;
        defer self.allocator.free(listing);

        var iter = std.mem.splitScalar(u8, listing, '\n');
        while (iter.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0) continue;

            const sep_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const token = std.mem.trim(u8, line[0..sep_idx], " \t");
            const color = std.mem.trim(u8, line[(sep_idx + 1)..], " \t");
            if (token.len == 0 or color.len == 0) continue;

            self.theme.setToken(token, color) catch |err| {
                zlog.warn("Failed to import theme color {s}: {s}", .{ token, @errorName(err) });
            };
        }
    }

    pub fn refreshTheme(self: *ConfigManager) !void {
        try self.theme.applyDefaults();
        self.loadThemeFromBridge() catch |err| {
            zlog.warn("Unable to load Grim theme: {s}", .{@errorName(err)});
        };
        try self.applyThemeOverrides();
    }

    fn parseFuzzyDecoratedListing(
        allocator: std.mem.Allocator,
        listing: []u8,
        owns_buffer: bool,
    ) !FuzzyResults {
        var entries_builder = std.ArrayList(FuzzyEntry).empty;
        var cleanup_entries = true;
        defer if (cleanup_entries) {
            for (entries_builder.items) |entry| {
                if (entry.highlights.len > 0) allocator.free(entry.highlights);
            }
            entries_builder.deinit(allocator);
        };

        var line_iter = std.mem.splitScalar(u8, listing, '\n');
        while (line_iter.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \r");
            if (line.len == 0) continue;

            const tab_index_opt = std.mem.indexOfScalar(u8, line, '\t');
            if (tab_index_opt == null) {
                try entries_builder.append(allocator, FuzzyEntry{
                    .path = line,
                    .highlights = &[_]Highlight{},
                });
                continue;
            }

            const tab_index = tab_index_opt.?;
            const path_slice = std.mem.trim(u8, line[0..tab_index], " ");
            const highlight_data = if (tab_index + 1 < line.len)
                line[(tab_index + 1)..]
            else
                &[_]u8{};

            var highlight_builder = std.ArrayList(Highlight).empty;
            defer highlight_builder.deinit(allocator);

            var segment_iter = std.mem.splitScalar(u8, highlight_data, ';');
            while (segment_iter.next()) |segment_raw| {
                const segment = std.mem.trim(u8, segment_raw, " ");
                if (segment.len == 0) continue;

                var part_iter = std.mem.splitScalar(u8, segment, ':');
                const start_str = part_iter.next() orelse continue;
                const stop_str = part_iter.next() orelse continue;
                const token_str = part_iter.next() orelse continue;

                const start = std.fmt.parseInt(usize, std.mem.trim(u8, start_str, " "), 10) catch continue;
                const stop = std.fmt.parseInt(usize, std.mem.trim(u8, stop_str, " "), 10) catch continue;
                const token = std.mem.trim(u8, token_str, " ");

                try highlight_builder.append(allocator, Highlight{
                    .start = start,
                    .stop = stop,
                    .token_type = token,
                });
            }

            const count = highlight_builder.items.len;
            var highlight_slice: []Highlight = &[_]Highlight{};
            if (count > 0) {
                const owned = try allocator.alloc(Highlight, count);
                errdefer allocator.free(owned);
                std.mem.copyForwards(Highlight, owned, highlight_builder.items[0..count]);
                highlight_slice = owned;
            }

            try entries_builder.append(allocator, FuzzyEntry{
                .path = path_slice,
                .highlights = highlight_slice,
            });
        }

        const entries = try entries_builder.toOwnedSlice(allocator);
        cleanup_entries = false;
        entries_builder.deinit(allocator);

        return FuzzyResults{
            .buffer = listing,
            .entries = entries,
            .owns_buffer = owns_buffer,
            .owns_entries = true,
        };
    }

    pub fn getFuzzyResults(self: *ConfigManager, query: []const u8) !FuzzyResults {
        const listing_opt = try self.ghostlang_runtime.fuzzyFinderDecoratedListing(query);
        if (listing_opt == null) return FuzzyResults.empty();

        const listing = listing_opt.?;
        errdefer self.allocator.free(listing);

        return try parseFuzzyDecoratedListing(self.allocator, listing, true);
    }

    /// Set a configuration value
    pub fn set(self: *ConfigManager, key: []const u8, value: flare.Value) !void {
        try self.flare_config.set(key, value);
    }

    /// Execute a Ghostlang code snippet
    pub fn executeCode(self: *ConfigManager, code: []const u8) !void {
        _ = try self.ghostlang_runtime.executeCode(code);
    }
};

test "pluginPathToModuleName converts plugin paths" {
    const allocator = std.testing.allocator;

    const module1 = try ConfigManager.pluginPathToModuleName(allocator, "core/file-tree.gza");
    defer allocator.free(module1);
    try std.testing.expectEqualStrings("plugins.core.file-tree", module1);

    const module2 = try ConfigManager.pluginPathToModuleName(allocator, "statusline.gza");
    defer allocator.free(module2);
    try std.testing.expectEqualStrings("plugins.statusline", module2);
}

test "parseFuzzyDecoratedListing parses entries and highlights" {
    const allocator = std.testing.allocator;

    const sample_str =
        "src/main.zig\t0:3:filename;4:6:match\n" ++
        "README.md\t0:9:filename\n" ++
        "LICENSE\n";

    const sample = try allocator.dupe(u8, sample_str);
    defer allocator.free(sample);

    const results = try ConfigManager.parseFuzzyDecoratedListing(allocator, sample, false);
    defer results.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), results.entries.len);
    try std.testing.expectEqualStrings("src/main.zig", results.entries[0].path);
    try std.testing.expectEqual(@as(usize, 2), results.entries[0].highlights.len);
    try std.testing.expectEqualStrings("match", results.entries[0].highlights[1].token_type);
    try std.testing.expectEqual(@as(usize, 0), results.entries[2].highlights.len);
    try std.testing.expect(!results.owns_buffer);
}

//! core/lazy_loader.zig
//! Lazy plugin loading system - defers plugin initialization until needed
//! Inspired by lazy.nvim but built for phantom.grim performance

const std = @import("std");
const grim = @import("grim");
const runtime = grim.runtime;
const zlog = @import("zlog");

const PluginLoader = @import("plugin_loader.zig").PluginLoader;
const EventSystem = @import("event_system.zig").EventSystem;

/// Event types that can trigger plugin loading
pub const LoadEvent = union(enum) {
    /// Load on specific file types
    FileType: []const []const u8,
    /// Load when buffer is read (glob pattern)
    BufRead: []const u8,
    /// Load when buffer is written
    BufWrite: []const u8,
    /// Load when entering buffer
    BufEnter: []const u8,
    /// Load when leaving buffer
    BufLeave: []const u8,
    /// Load when entering insert mode
    InsertEnter: void,
    /// Load when entering command line
    CmdlineEnter: void,
    /// Load on vim startup (after UI ready)
    VimEnter: void,
    /// Custom user event
    User: []const u8,
};

/// Keymap specification for lazy loading
pub const KeyMap = struct {
    mode: []const u8, // "n", "v", "i", etc.
    lhs: []const u8,  // Key sequence
};

/// User-facing plugin specification for lazy loading
pub const LazyPluginSpec = struct {
    /// Plugin name or path
    name: []const u8,

    /// Events that trigger loading
    events: ?[]const LoadEvent = null,

    /// Commands that trigger loading
    cmd: ?[]const []const u8 = null,

    /// Keymaps that trigger loading
    keys: ?[]const KeyMap = null,

    /// File types (shorthand for FileType events)
    ft: ?[]const []const u8 = null,

    /// Plugin dependencies (load before this)
    dependencies: ?[]const []const u8 = null,

    /// Disable lazy loading (load immediately)
    lazy: bool = true,

    /// Load priority (higher = earlier, default 50)
    priority: i32 = 50,

    /// Enable/disable plugin
    enabled: bool = true,

    /// Custom load condition
    condition: ?*const fn (*LoadContext) bool = null,
};

/// Context provided to condition functions
pub const LoadContext = struct {
    allocator: std.mem.Allocator,
    plugin_name: []const u8,
    event_type: ?LoadEvent = null,
    buffer_path: ?[]const u8 = null,
    filetype: ?[]const u8 = null,
};

/// Internal plugin state tracking
const PluginState = struct {
    spec: LazyPluginSpec,
    loaded: bool = false,
    loading: bool = false,
    load_time_us: ?i64 = null,
};

/// Manages lazy loading of plugins
pub const LazyPluginManager = struct {
    allocator: std.mem.Allocator,
    plugin_loader: *PluginLoader,
    event_system: *EventSystem,

    /// Map of plugin name → state
    plugins: std.StringHashMap(PluginState),

    /// Event → plugin names mapping
    event_triggers: std.AutoHashMap(EventTriggerKey, std.ArrayList([]const u8)),

    /// Command → plugin names mapping
    cmd_triggers: std.StringHashMap([]const u8),

    /// Key → plugin names mapping
    key_triggers: std.AutoHashMap(KeyTriggerKey, []const u8),

    /// Plugins queued for loading
    load_queue: std.ArrayList([]const u8),

    /// Debug mode - logs all load events
    debug: bool = false,

    const EventTriggerKey = struct {
        event_type: std.meta.Tag(LoadEvent),
        pattern: []const u8,

        pub fn hash(self: EventTriggerKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(@tagName(self.event_type));
            hasher.update(self.pattern);
            return hasher.final();
        }

        pub fn eql(a: EventTriggerKey, b: EventTriggerKey) bool {
            return a.event_type == b.event_type and std.mem.eql(u8, a.pattern, b.pattern);
        }
    };

    const KeyTriggerKey = struct {
        mode: []const u8,
        lhs: []const u8,

        pub fn hash(self: KeyTriggerKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(self.mode);
            hasher.update(self.lhs);
            return hasher.final();
        }

        pub fn eql(a: KeyTriggerKey, b: KeyTriggerKey) bool {
            return std.mem.eql(u8, a.mode, b.mode) and std.mem.eql(u8, a.lhs, b.lhs);
        }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        plugin_loader: *PluginLoader,
        event_system: *EventSystem,
    ) !*LazyPluginManager {
        const manager = try allocator.create(LazyPluginManager);
        errdefer allocator.destroy(manager);

        manager.* = .{
            .allocator = allocator,
            .plugin_loader = plugin_loader,
            .event_system = event_system,
            .plugins = std.StringHashMap(PluginState).init(allocator),
            .event_triggers = std.AutoHashMap(EventTriggerKey, std.ArrayList([]const u8)).init(allocator),
            .cmd_triggers = std.StringHashMap([]const u8).init(allocator),
            .key_triggers = std.AutoHashMap(KeyTriggerKey, []const u8).init(allocator),
            .load_queue = std.ArrayList([]const u8).init(allocator),
        };

        return manager;
    }

    pub fn deinit(self: *LazyPluginManager) void {
        // Free plugin states
        var plugin_it = self.plugins.iterator();
        while (plugin_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.plugins.deinit();

        // Free event triggers
        var event_it = self.event_triggers.iterator();
        while (event_it.next()) |entry| {
            for (entry.value_ptr.items) |name| {
                self.allocator.free(name);
            }
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.pattern);
        }
        self.event_triggers.deinit();

        // Free command triggers
        var cmd_it = self.cmd_triggers.iterator();
        while (cmd_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.cmd_triggers.deinit();

        // Free key triggers
        var key_it = self.key_triggers.iterator();
        while (key_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.mode);
            self.allocator.free(entry.key_ptr.lhs);
            self.allocator.free(entry.value_ptr.*);
        }
        self.key_triggers.deinit();

        self.load_queue.deinit();
        self.allocator.destroy(self);
    }

    /// Register a plugin with lazy loading specification
    pub fn register(self: *LazyPluginManager, spec: LazyPluginSpec) !void {
        if (!spec.enabled) {
            if (self.debug) {
                zlog.debug("[lazy] Skipping disabled plugin: {s}", .{spec.name});
            }
            return;
        }

        const name = try self.allocator.dupe(u8, spec.name);
        errdefer self.allocator.free(name);

        const state = PluginState{
            .spec = spec,
            .loaded = false,
            .loading = false,
        };

        try self.plugins.put(name, state);

        // Register event triggers
        if (spec.events) |events| {
            for (events) |event| {
                try self.registerEvent(name, event);
            }
        }

        // Register FileType shorthand
        if (spec.ft) |filetypes| {
            const ft_event = LoadEvent{ .FileType = filetypes };
            try self.registerEvent(name, ft_event);
        }

        // Register command triggers
        if (spec.cmd) |commands| {
            for (commands) |cmd| {
                const cmd_key = try self.allocator.dupe(u8, cmd);
                const plugin_name = try self.allocator.dupe(u8, name);
                try self.cmd_triggers.put(cmd_key, plugin_name);
            }
        }

        // Register keymap triggers
        if (spec.keys) |keys| {
            for (keys) |key| {
                const key_trigger = KeyTriggerKey{
                    .mode = try self.allocator.dupe(u8, key.mode),
                    .lhs = try self.allocator.dupe(u8, key.lhs),
                };
                const plugin_name = try self.allocator.dupe(u8, name);
                try self.key_triggers.put(key_trigger, plugin_name);
            }
        }

        // Load immediately if not lazy
        if (!spec.lazy) {
            try self.loadPlugin(name);
        }

        if (self.debug) {
            zlog.debug("[lazy] Registered plugin: {s} (lazy={any})", .{ name, spec.lazy });
        }
    }

    /// Register event trigger for a plugin
    fn registerEvent(self: *LazyPluginManager, plugin_name: []const u8, event: LoadEvent) !void {
        const patterns = switch (event) {
            .FileType => |fts| fts,
            .BufRead => |p| &[_][]const u8{p},
            .BufWrite => |p| &[_][]const u8{p},
            .BufEnter => |p| &[_][]const u8{p},
            .BufLeave => |p| &[_][]const u8{p},
            .User => |name| &[_][]const u8{name},
            else => return, // No pattern for these events
        };

        for (patterns) |pattern| {
            const key = EventTriggerKey{
                .event_type = std.meta.activeTag(event),
                .pattern = try self.allocator.dupe(u8, pattern),
            };

            const gop = try self.event_triggers.getOrPut(key);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
            }

            const name = try self.allocator.dupe(u8, plugin_name);
            try gop.value_ptr.append(name);
        }
    }

    /// Handle an event and trigger plugin loading if needed
    pub fn onEvent(self: *LazyPluginManager, event: LoadEvent, context: LoadContext) !void {
        const pattern = switch (event) {
            .FileType => |fts| if (fts.len > 0) fts[0] else return,
            .BufRead => |p| p,
            .BufWrite => |p| p,
            .BufEnter => |p| p,
            .BufLeave => |p| p,
            .User => |name| name,
            else => "",
        };

        const key = EventTriggerKey{
            .event_type = std.meta.activeTag(event),
            .pattern = pattern,
        };

        if (self.event_triggers.get(key)) |plugin_names| {
            for (plugin_names.items) |name| {
                if (self.plugins.get(name)) |state| {
                    if (state.loaded or state.loading) continue;

                    // Check condition if specified
                    if (state.spec.condition) |cond_fn| {
                        var ctx = context;
                        ctx.plugin_name = name;
                        ctx.event_type = event;
                        if (!cond_fn(&ctx)) {
                            if (self.debug) {
                                zlog.debug("[lazy] Condition failed for {s}", .{name});
                            }
                            continue;
                        }
                    }

                    try self.loadPlugin(name);
                }
            }
        }
    }

    /// Handle command execution and trigger loading
    pub fn onCommand(self: *LazyPluginManager, cmd: []const u8) !void {
        if (self.cmd_triggers.get(cmd)) |plugin_name| {
            if (self.debug) {
                zlog.debug("[lazy] Command '{s}' → loading {s}", .{ cmd, plugin_name });
            }
            try self.loadPlugin(plugin_name);
        }
    }

    /// Handle keymap and trigger loading
    pub fn onKey(self: *LazyPluginManager, mode: []const u8, lhs: []const u8) !void {
        const key = KeyTriggerKey{ .mode = mode, .lhs = lhs };
        if (self.key_triggers.get(key)) |plugin_name| {
            if (self.debug) {
                zlog.debug("[lazy] Key '{s}{s}' → loading {s}", .{ mode, lhs, plugin_name });
            }
            try self.loadPlugin(plugin_name);
        }
    }

    /// Load a specific plugin by name
    pub fn loadPlugin(self: *LazyPluginManager, name: []const u8) !void {
        var state_ptr = self.plugins.getPtr(name) orelse return error.PluginNotFound;

        if (state_ptr.loaded or state_ptr.loading) {
            return; // Already loaded or loading
        }

        state_ptr.loading = true;

        const start_time = std.time.microTimestamp();

        if (self.debug) {
            zlog.debug("[lazy] Loading plugin: {s}", .{name});
        }

        // Load dependencies first
        if (state_ptr.spec.dependencies) |deps| {
            for (deps) |dep| {
                try self.loadPlugin(dep);
            }
        }

        // Actually load the plugin via PluginLoader
        self.plugin_loader.loadPlugin(name) catch |err| {
            state_ptr.loading = false;
            zlog.err("[lazy] Failed to load {s}: {any}", .{ name, err });
            return err;
        };

        const end_time = std.time.microTimestamp();
        state_ptr.load_time_us = end_time - start_time;
        state_ptr.loaded = true;
        state_ptr.loading = false;

        if (self.debug) {
            const load_ms = @divFloor(state_ptr.load_time_us.?, 1000);
            zlog.info("[lazy] ✓ Loaded {s} in {d}ms", .{ name, load_ms });
        }
    }

    /// Load all pending plugins (called on VimEnter or similar)
    pub fn loadAll(self: *LazyPluginManager) !void {
        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            if (!entry.value_ptr.loaded and !entry.value_ptr.spec.lazy) {
                try self.loadPlugin(entry.key_ptr.*);
            }
        }
    }

    /// Get stats about loaded plugins
    pub fn getStats(self: *LazyPluginManager) Stats {
        var total: usize = 0;
        var loaded: usize = 0;
        var total_load_time_us: i64 = 0;

        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            total += 1;
            if (entry.value_ptr.loaded) {
                loaded += 1;
                if (entry.value_ptr.load_time_us) |time| {
                    total_load_time_us += time;
                }
            }
        }

        return .{
            .total_plugins = total,
            .loaded_plugins = loaded,
            .total_load_time_ms = @divFloor(total_load_time_us, 1000),
        };
    }

    pub const Stats = struct {
        total_plugins: usize,
        loaded_plugins: usize,
        total_load_time_ms: i64,
    };
};

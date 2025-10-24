//! phantom.zig
//! User-facing API for phantom.grim configuration
//! The ultimate LazyVim alternative

const std = @import("std");
const grim = @import("grim");
const zlog = @import("zlog");

const PluginLoader = @import("core/plugin_loader.zig").PluginLoader;
const LazyPluginManager = @import("core/lazy_loader.zig").LazyPluginManager;
const EventSystem = @import("core/event_system.zig").EventSystem;

pub const LazyPluginSpec = @import("core/lazy_loader.zig").LazyPluginSpec;
pub const LoadEvent = @import("core/lazy_loader.zig").LoadEvent;
pub const KeyMap = @import("core/lazy_loader.zig").KeyMap;

/// Phantom configuration
pub const PhantomConfig = struct {
    /// Plugin specifications for lazy loading
    plugins: []const LazyPluginSpec = &.{},

    /// Plugin installation directory
    install_dir: []const u8 = "~/.local/share/phantom/plugins",

    /// Plugin registry URL
    registry_url: []const u8 = "https://plugins.phantom.grim",

    /// Enable debug logging
    debug: bool = false,

    /// Lazy loading enabled (set false to disable completely)
    lazy_enabled: bool = true,
};

/// Main phantom runtime
pub const Phantom = struct {
    allocator: std.mem.Allocator,
    plugin_loader: *PluginLoader,
    lazy_manager: *LazyPluginManager,
    event_system: *EventSystem,
    config: PhantomConfig,

    pub fn init(allocator: std.mem.Allocator, config: PhantomConfig) !*Phantom {
        const phantom = try allocator.create(Phantom);
        errdefer allocator.destroy(phantom);

        phantom.allocator = allocator;
        phantom.config = config;

        // Initialize event system
        phantom.event_system = try EventSystem.init(allocator);
        errdefer phantom.event_system.deinit();

        // Initialize plugin loader
        const loader_config = PluginLoader.PluginConfig{
            .registry_url = config.registry_url,
            .install_dir = config.install_dir,
        };
        phantom.plugin_loader = try PluginLoader.init(allocator, loader_config);
        errdefer phantom.plugin_loader.deinit();

        // Initialize lazy loading manager
        phantom.lazy_manager = try LazyPluginManager.init(
            allocator,
            phantom.plugin_loader,
            phantom.event_system,
        );
        errdefer phantom.lazy_manager.deinit();

        phantom.lazy_manager.debug = config.debug;

        return phantom;
    }

    pub fn deinit(self: *Phantom) void {
        self.lazy_manager.deinit();
        self.plugin_loader.deinit();
        self.event_system.deinit();
        self.allocator.destroy(self);
    }

    /// Load all plugins according to specs
    pub fn loadPlugins(self: *Phantom) !void {
        if (!self.config.lazy_enabled) {
            // Lazy loading disabled - load everything eagerly
            for (self.config.plugins) |spec| {
                if (!spec.enabled) continue;
                try self.plugin_loader.loadPlugin(spec.name);
            }
            return;
        }

        // Register all plugins with lazy manager
        for (self.config.plugins) |spec| {
            try self.lazy_manager.register(spec);
        }

        // Load non-lazy plugins immediately
        try self.lazy_manager.loadAll();

        if (self.config.debug) {
            const stats = self.lazy_manager.getStats();
            zlog.info("[phantom] Registered {d} plugins, {d} loaded immediately", .{
                stats.total_plugins,
                stats.loaded_plugins,
            });
        }
    }

    /// Get loading statistics
    pub fn stats(self: *Phantom) LazyPluginManager.Stats {
        return self.lazy_manager.getStats();
    }
};

/// Main setup function - the user-facing API
pub fn setup(config: PhantomConfig) !*Phantom {
    const allocator = std.heap.page_allocator;

    zlog.info("🚀 Phantom.grim initializing...", .{});

    const phantom = try Phantom.init(allocator, config);
    errdefer phantom.deinit();

    try phantom.loadPlugins();

    const stats = phantom.stats();
    const startup_ms = stats.total_load_time_ms;

    zlog.info("✓ Phantom ready! ({d}/{d} plugins loaded in {d}ms)", .{
        stats.loaded_plugins,
        stats.total_plugins,
        startup_ms,
    });

    return phantom;
}

// Re-export commonly used types
pub const LoadContext = @import("core/lazy_loader.zig").LoadContext;

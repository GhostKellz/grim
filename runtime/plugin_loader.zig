const std = @import("std");
const host = @import("host");
const PluginManifest = @import("plugin_manifest.zig").PluginManifest;
const DiscoveredPlugin = @import("plugin_discovery.zig").DiscoveredPlugin;

/// Loaded plugin (running state)
pub const LoadedPlugin = struct {
    manifest: PluginManifest,
    plugin_dir: []const u8,
    plugin_type: PluginType,
    state: PluginState,
    allocator: std.mem.Allocator,

    pub const PluginType = enum {
        ghostlang,  // .gza script
        native,     // .so/.dll native library
        hybrid,     // Both Ghostlang + native
    };

    pub const PluginState = union(PluginType) {
        ghostlang: GhostlangState,
        native: NativeState,
        hybrid: HybridState,
    };

    pub const GhostlangState = struct {
        compiled: host.Host.CompiledPlugin,
        setup_called: bool = false,
    };

    pub const NativeState = struct {
        library: std.DynLib,
        setup_fn: ?*const fn () callconv(.c) void,
        teardown_fn: ?*const fn () callconv(.c) void,
    };

    pub const HybridState = struct {
        ghostlang: GhostlangState,
        native: NativeState,
    };

    pub fn deinit(self: *LoadedPlugin) void {
        switch (self.state) {
            .ghostlang => |*gs| {
                gs.compiled.deinit();
            },
            .native => |*ns| {
                ns.library.close();
            },
            .hybrid => |*hs| {
                hs.ghostlang.compiled.deinit();
                hs.native.library.close();
            },
        }

        self.allocator.free(self.plugin_dir);
        self.manifest.deinit();
    }
};

/// Plugin loader - converts discovered plugins to loaded plugins
pub const PluginLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PluginLoader {
        return .{ .allocator = allocator };
    }

    /// Load a discovered plugin (requires shared Host for Ghostlang plugins)
    pub fn load(self: *PluginLoader, discovered: *DiscoveredPlugin, ghostlang_host: *host.Host) !LoadedPlugin {
        std.log.info("Loading plugin: {s} v{s}", .{ discovered.name, discovered.manifest.version });

        // Determine plugin type
        const plugin_type = try self.detectPluginType(discovered);

        const plugin = switch (plugin_type) {
            .ghostlang => try self.loadGhostlang(discovered, ghostlang_host),
            .native => try self.loadNative(discovered),
            .hybrid => try self.loadHybrid(discovered, ghostlang_host),
        };

        std.log.info("Plugin {s} loaded successfully", .{discovered.name});
        return plugin;
    }

    /// Detect plugin type from manifest and files
    fn detectPluginType(self: *PluginLoader, discovered: *DiscoveredPlugin) !LoadedPlugin.PluginType {
        _ = self;

        const has_ghostlang = blk: {
            const main_path = try std.fs.path.join(
                discovered.allocator,
                &.{ discovered.path, discovered.manifest.main },
            );
            defer discovered.allocator.free(main_path);

            // Check if main .gza file exists
            std.fs.cwd().access(main_path, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        const has_native = discovered.manifest.native_library != null;

        // Determine plugin type based on what's present
        if (has_ghostlang and has_native) {
            return .hybrid;
        } else if (has_native) {
            return .native;
        } else if (has_ghostlang) {
            return .ghostlang;
        } else {
            std.log.err("Plugin {s} has neither Ghostlang script nor native library", .{discovered.name});
            return error.InvalidPluginType;
        }
    }

    /// Load Ghostlang (.gza) plugin
    fn loadGhostlang(self: *PluginLoader, discovered: *DiscoveredPlugin, ghostlang_host: *host.Host) !LoadedPlugin {
        // Build path to main script
        const script_path = try std.fs.path.join(
            self.allocator,
            &.{ discovered.path, discovered.manifest.main },
        );
        defer self.allocator.free(script_path);

        // Read script content
        const script_content = try std.fs.cwd().readFileAlloc(
            script_path,
            self.allocator,
            .limited(10 * 1024 * 1024), // 10MB max
        );
        defer self.allocator.free(script_content);

        std.log.debug("Compiling {s}...", .{discovered.name});
        std.log.debug("Script content ({d} bytes): \"{s}\"", .{ script_content.len, script_content });

        // Compile the script using Host API
        const compiled = try ghostlang_host.compilePluginScript(script_content);

        std.log.debug("Compilation successful: {s}", .{discovered.name});

        return LoadedPlugin{
            .manifest = discovered.manifest,
            .plugin_dir = try self.allocator.dupe(u8, discovered.path),
            .plugin_type = .ghostlang,
            .state = .{
                .ghostlang = .{
                    .compiled = compiled,
                    .setup_called = false,
                },
            },
            .allocator = self.allocator,
        };
    }

    /// Load native (.so/.dll) plugin
    fn loadNative(self: *PluginLoader, discovered: *DiscoveredPlugin) !LoadedPlugin {
        const native_plugin = @import("native_plugin.zig");

        // Get native library path from manifest
        const lib_name = discovered.manifest.native_library orelse return error.MissingNativeLibrary;

        // Build full path to library
        const lib_path = try std.fs.path.join(
            self.allocator,
            &.{ discovered.path, lib_name },
        );
        defer self.allocator.free(lib_path);

        std.log.debug("Loading native library: {s}", .{lib_path});

        // Open the shared library
        var library = try std.DynLib.open(lib_path);
        errdefer library.close();

        // Lookup required symbols
        const info_fn = library.lookup(
            *const fn () callconv(.c) native_plugin.NativePluginInfo,
            "grim_plugin_info",
        ) orelse {
            std.log.err("Native plugin missing grim_plugin_info export: {s}", .{lib_path});
            return error.MissingPluginInfo;
        };

        const init_fn = library.lookup(
            *const fn () callconv(.c) bool,
            "grim_plugin_init",
        ) orelse {
            std.log.err("Native plugin missing grim_plugin_init export: {s}", .{lib_path});
            return error.MissingPluginInit;
        };

        const setup_fn = library.lookup(
            *const fn () callconv(.c) void,
            "grim_plugin_setup",
        );

        const teardown_fn = library.lookup(
            *const fn () callconv(.c) void,
            "grim_plugin_teardown",
        );

        // Get plugin info
        const info = info_fn();

        // Validate API version
        if (info.api_version != native_plugin.GRIM_PLUGIN_API_VERSION) {
            std.log.err("Plugin API version mismatch: plugin={d}, grim={d}", .{
                info.api_version,
                native_plugin.GRIM_PLUGIN_API_VERSION,
            });
            return error.APIVersionMismatch;
        }

        // Initialize plugin
        const init_success = init_fn();
        if (!init_success) {
            std.log.err("Plugin initialization failed: {s}", .{info.name});
            return error.PluginInitFailed;
        }

        std.log.info("Native plugin loaded: {s} v{s}", .{ info.name, info.version });

        return LoadedPlugin{
            .manifest = discovered.manifest,
            .plugin_dir = try self.allocator.dupe(u8, discovered.path),
            .plugin_type = .native,
            .state = .{
                .native = .{
                    .library = library,
                    .setup_fn = setup_fn,
                    .teardown_fn = teardown_fn,
                },
            },
            .allocator = self.allocator,
        };
    }

    /// Load hybrid (Ghostlang + native) plugin
    fn loadHybrid(self: *PluginLoader, discovered: *DiscoveredPlugin, ghostlang_host: *host.Host) !LoadedPlugin {
        const native_plugin = @import("native_plugin.zig");

        std.log.info("Loading hybrid plugin: {s}", .{discovered.name});

        // 1. Load Ghostlang component
        const script_path = try std.fs.path.join(
            self.allocator,
            &.{ discovered.path, discovered.manifest.main },
        );
        defer self.allocator.free(script_path);

        const script_content = try std.fs.cwd().readFileAlloc(
            script_path,
            self.allocator,
            .limited(10 * 1024 * 1024), // 10MB max
        );
        defer self.allocator.free(script_content);

        std.log.debug("Compiling Ghostlang script: {s}", .{discovered.name});
        const compiled = try ghostlang_host.compilePluginScript(script_content);

        // 2. Load native component
        const lib_name = discovered.manifest.native_library orelse return error.MissingNativeLibrary;
        const lib_path = try std.fs.path.join(
            self.allocator,
            &.{ discovered.path, lib_name },
        );
        defer self.allocator.free(lib_path);

        std.log.debug("Loading native library: {s}", .{lib_path});
        var library = try std.DynLib.open(lib_path);
        errdefer library.close();

        // Lookup required symbols
        const info_fn = library.lookup(
            *const fn () callconv(.c) native_plugin.NativePluginInfo,
            "grim_plugin_info",
        ) orelse {
            std.log.err("Hybrid plugin missing grim_plugin_info export: {s}", .{lib_path});
            return error.MissingPluginInfo;
        };

        const init_fn = library.lookup(
            *const fn () callconv(.c) bool,
            "grim_plugin_init",
        ) orelse {
            std.log.err("Hybrid plugin missing grim_plugin_init export: {s}", .{lib_path});
            return error.MissingPluginInit;
        };

        const setup_fn = library.lookup(
            *const fn () callconv(.c) void,
            "grim_plugin_setup",
        );

        const teardown_fn = library.lookup(
            *const fn () callconv(.c) void,
            "grim_plugin_teardown",
        );

        // Get plugin info and validate
        const info = info_fn();

        if (info.api_version != native_plugin.GRIM_PLUGIN_API_VERSION) {
            std.log.err("Plugin API version mismatch: plugin={d}, grim={d}", .{
                info.api_version,
                native_plugin.GRIM_PLUGIN_API_VERSION,
            });
            return error.APIVersionMismatch;
        }

        // Initialize native component
        const init_success = init_fn();
        if (!init_success) {
            std.log.err("Hybrid plugin native init failed: {s}", .{info.name});
            return error.PluginInitFailed;
        }

        std.log.info("Hybrid plugin loaded: {s} v{s} (Ghostlang + native)", .{ info.name, info.version });

        return LoadedPlugin{
            .manifest = discovered.manifest,
            .plugin_dir = try self.allocator.dupe(u8, discovered.path),
            .plugin_type = .hybrid,
            .state = .{
                .hybrid = .{
                    .ghostlang = .{
                        .compiled = compiled,
                        .setup_called = false,
                    },
                    .native = .{
                        .library = library,
                        .setup_fn = setup_fn,
                        .teardown_fn = teardown_fn,
                    },
                },
            },
            .allocator = self.allocator,
        };
    }

    /// Call setup() function in plugin
    pub fn callSetup(self: *PluginLoader, plugin: *LoadedPlugin, callbacks: host.Host.ActionCallbacks) !void {
        _ = self;

        switch (plugin.state) {
            .ghostlang => |*gs| {
                if (gs.setup_called) {
                    std.log.warn("Plugin {s} setup() already called", .{plugin.manifest.name});
                    return;
                }

                std.log.debug("Calling setup() for {s}", .{plugin.manifest.name});

                // Execute the plugin script with callbacks
                try gs.compiled.executeSetup(callbacks);
                gs.setup_called = true;

                std.log.info("Plugin {s} setup() complete", .{plugin.manifest.name});
            },
            .native => |*ns| {
                if (ns.setup_fn) |setup| {
                    setup();
                }
            },
            .hybrid => |*hs| {
                // Set native library in host so Ghostlang can call native functions
                hs.ghostlang.compiled.host.setNativeLibrary(&hs.native.library);
                defer hs.ghostlang.compiled.host.setNativeLibrary(null);

                // Call Ghostlang setup first
                if (!hs.ghostlang.setup_called) {
                    try hs.ghostlang.compiled.executeSetup(callbacks);
                    hs.ghostlang.setup_called = true;
                }
                // Then call native setup
                if (hs.native.setup_fn) |setup| {
                    setup();
                }
            },
        }
    }

    /// Call teardown() function in plugin
    pub fn callTeardown(self: *PluginLoader, plugin: *LoadedPlugin) !void {
        _ = self;

        switch (plugin.state) {
            .ghostlang => |*gs| {
                if (!gs.setup_called) {
                    return; // Never set up, nothing to tear down
                }

                std.log.debug("Calling teardown() for {s}", .{plugin.manifest.name});

                // Try to call teardown function (optional - may not exist)
                gs.compiled.callVoid("teardown") catch |err| {
                    std.log.debug("Plugin {s} teardown() not found or failed: {}", .{ plugin.manifest.name, err });
                };

                gs.setup_called = false;
                std.log.info("Plugin {s} teardown() complete", .{plugin.manifest.name});
            },
            .native => |*ns| {
                if (ns.teardown_fn) |teardown| {
                    teardown();
                }
            },
            .hybrid => |*hs| {
                // Call both - Ghostlang first
                if (hs.ghostlang.setup_called) {
                    hs.ghostlang.compiled.callVoid("teardown") catch |err| {
                        std.log.debug("Plugin teardown() failed: {}", .{err});
                    };
                    hs.ghostlang.setup_called = false;
                }
                // Then native
                if (hs.native.teardown_fn) |teardown| {
                    teardown();
                }
            },
        }
    }
};

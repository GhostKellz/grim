//! Native Plugin FFI Bridge
//! Provides ABI-stable interface for Zig native plugins
//! Sprint 14.2 - Plugin System Enhancement

const std = @import("std");
const builtin = @import("builtin");

/// ABI version for compatibility checking
pub const ABI_VERSION: u32 = 1;

/// Plugin metadata exported by native plugins
pub const PluginMetadata = extern struct {
    /// ABI version this plugin was built against
    abi_version: u32,

    /// Plugin name (null-terminated C string)
    name: [*:0]const u8,

    /// Plugin version (null-terminated C string)
    version: [*:0]const u8,

    /// Plugin description (null-terminated C string)
    description: [*:0]const u8,

    /// Plugin author (null-terminated C string)
    author: [*:0]const u8,

    /// Minimum Grim version required (null-terminated C string)
    min_grim_version: [*:0]const u8,
};

/// Plugin lifecycle hooks (all optional)
pub const PluginVTable = extern struct {
    /// Called when plugin is loaded
    /// Return 0 on success, non-zero on error
    on_load: ?*const fn (ctx: *PluginContext) callconv(.C) c_int,

    /// Called when plugin is initialized after all plugins loaded
    /// Return 0 on success, non-zero on error
    on_init: ?*const fn (ctx: *PluginContext) callconv(.C) c_int,

    /// Called when plugin is about to be unloaded
    on_deinit: ?*const fn (ctx: *PluginContext) callconv(.C) void,

    /// Called when plugin is reloaded (hot reload)
    /// Return 0 on success, non-zero on error
    on_reload: ?*const fn (ctx: *PluginContext) callconv(.C) c_int,

    /// Reserved for future use
    reserved: [4]usize = [_]usize{0} ** 4,
};

/// Plugin context provided to plugin functions
pub const PluginContext = extern struct {
    /// Opaque pointer to Grim's internal plugin state
    internal_state: ?*anyopaque,

    /// Allocator provided by Grim (use this for allocations)
    allocator: *Allocator,

    /// API function table
    api: *const GrimAPI,

    /// Plugin's private data pointer
    user_data: ?*anyopaque,

    /// Reserved for future use
    reserved: [4]usize = [_]usize{0} ** 4,
};

/// C-compatible allocator wrapper
pub const Allocator = extern struct {
    /// Allocate memory
    alloc: *const fn (self: *Allocator, size: usize, alignment: usize) callconv(.C) ?*anyopaque,

    /// Free memory
    free: *const fn (self: *Allocator, ptr: *anyopaque, size: usize, alignment: usize) callconv(.C) void,

    /// Reallocate memory
    realloc: *const fn (self: *Allocator, ptr: ?*anyopaque, old_size: usize, new_size: usize, alignment: usize) callconv(.C) ?*anyopaque,
};

/// Grim API provided to plugins
pub const GrimAPI = extern struct {
    /// API version
    version: u32,

    /// Log a message
    log: *const fn (level: LogLevel, message: [*:0]const u8) callconv(.C) void,

    /// Register a command
    register_command: *const fn (
        name: [*:0]const u8,
        callback: *const fn (ctx: *PluginContext, args: [*:0]const u8) callconv(.C) c_int,
    ) callconv(.C) c_int,

    /// Get configuration value
    get_config: *const fn (key: [*:0]const u8, default_value: [*:0]const u8) callconv(.C) [*:0]const u8,

    /// Set configuration value
    set_config: *const fn (key: [*:0]const u8, value: [*:0]const u8) callconv(.C) c_int,

    /// Get buffer content
    get_buffer_content: *const fn (buffer_id: usize) callconv(.C) ?[*:0]const u8,

    /// Set buffer content
    set_buffer_content: *const fn (buffer_id: usize, content: [*:0]const u8) callconv(.C) c_int,

    /// Get current cursor position
    get_cursor_pos: *const fn (buffer_id: usize, row: *usize, col: *usize) callconv(.C) c_int,

    /// Set cursor position
    set_cursor_pos: *const fn (buffer_id: usize, row: usize, col: usize) callconv(.C) c_int,

    /// Reserved for future API functions
    reserved: [16]usize = [_]usize{0} ** 16,
};

/// Log levels
pub const LogLevel = enum(c_int) {
    debug = 0,
    info = 1,
    warning = 2,
    err = 3,
};

/// Plugin handle (opaque)
pub const PluginHandle = struct {
    allocator: std.mem.Allocator,
    lib: std.DynLib,
    metadata: *const PluginMetadata,
    vtable: *const PluginVTable,
    context: PluginContext,
    user_data: ?*anyopaque,

    pub fn deinit(self: *PluginHandle) void {
        self.lib.close();
        self.allocator.destroy(self);
    }
};

/// Plugin loader/manager
pub const PluginLoader = struct {
    allocator: std.mem.Allocator,
    plugins: std.StringHashMap(*PluginHandle),
    grim_api: GrimAPI,
    c_allocator: Allocator,

    pub fn init(allocator: std.mem.Allocator) !*PluginLoader {
        const self = try allocator.create(PluginLoader);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .plugins = std.StringHashMap(*PluginHandle).init(allocator),
            .grim_api = createGrimAPI(),
            .c_allocator = createCAllocator(allocator),
        };

        return self;
    }

    pub fn deinit(self: *PluginLoader) void {
        // Unload all plugins
        var iter = self.plugins.iterator();
        while (iter.next()) |entry| {
            self.unloadPlugin(entry.key_ptr.*) catch {};
        }

        self.plugins.deinit();
        self.allocator.destroy(self);
    }

    /// Load a native plugin from shared library
    pub fn loadPlugin(self: *PluginLoader, path: []const u8) !void {
        var lib = try std.DynLib.open(path);
        errdefer lib.close();

        // Get plugin metadata
        const get_metadata = lib.lookup(*const fn () callconv(.C) *const PluginMetadata, "grim_plugin_metadata") orelse {
            return error.MissingMetadata;
        };
        const metadata = get_metadata();

        // Check ABI compatibility
        if (metadata.abi_version != ABI_VERSION) {
            std.log.err("Plugin ABI version mismatch: expected {d}, got {d}", .{ ABI_VERSION, metadata.abi_version });
            return error.ABIVersionMismatch;
        }

        // Get plugin vtable
        const get_vtable = lib.lookup(*const fn () callconv(.C) *const PluginVTable, "grim_plugin_vtable") orelse {
            return error.MissingVTable;
        };
        const vtable = get_vtable();

        // Create plugin handle
        const handle = try self.allocator.create(PluginHandle);
        errdefer self.allocator.destroy(handle);

        handle.* = .{
            .allocator = self.allocator,
            .lib = lib,
            .metadata = metadata,
            .vtable = vtable,
            .context = .{
                .internal_state = null,
                .allocator = &self.c_allocator,
                .api = &self.grim_api,
                .user_data = null,
            },
            .user_data = null,
        };

        // Set user_data pointer in context
        handle.context.user_data = &handle.user_data;

        // Call on_load hook
        if (vtable.on_load) |on_load| {
            const result = on_load(&handle.context);
            if (result != 0) {
                return error.PluginLoadFailed;
            }
        }

        // Store plugin
        const name = std.mem.span(metadata.name);
        const name_copy = try self.allocator.dupe(u8, name);
        try self.plugins.put(name_copy, handle);

        std.log.info("Loaded plugin: {s} v{s}", .{ name, std.mem.span(metadata.version) });
    }

    /// Initialize all loaded plugins
    pub fn initPlugins(self: *PluginLoader) !void {
        var iter = self.plugins.iterator();
        while (iter.next()) |entry| {
            const handle = entry.value_ptr.*;
            if (handle.vtable.on_init) |on_init| {
                const result = on_init(&handle.context);
                if (result != 0) {
                    std.log.err("Plugin {s} initialization failed", .{entry.key_ptr.*});
                    return error.PluginInitFailed;
                }
            }
        }
    }

    /// Unload a plugin
    pub fn unloadPlugin(self: *PluginLoader, name: []const u8) !void {
        const handle = self.plugins.get(name) orelse return error.PluginNotFound;

        // Call on_deinit hook
        if (handle.vtable.on_deinit) |on_deinit| {
            on_deinit(&handle.context);
        }

        // Remove from map
        const kv = self.plugins.fetchRemove(name) orelse return error.PluginNotFound;
        self.allocator.free(kv.key);

        // Clean up handle
        handle.deinit();

        std.log.info("Unloaded plugin: {s}", .{name});
    }

    /// Reload a plugin (hot reload)
    pub fn reloadPlugin(self: *PluginLoader, name: []const u8, new_path: []const u8) !void {
        const old_handle = self.plugins.get(name) orelse return error.PluginNotFound;

        // Load new version
        var new_lib = try std.DynLib.open(new_path);
        errdefer new_lib.close();

        const get_metadata = new_lib.lookup(*const fn () callconv(.C) *const PluginMetadata, "grim_plugin_metadata") orelse {
            return error.MissingMetadata;
        };
        const new_metadata = get_metadata();

        if (new_metadata.abi_version != ABI_VERSION) {
            return error.ABIVersionMismatch;
        }

        const get_vtable = new_lib.lookup(*const fn () callconv(.C) *const PluginVTable, "grim_plugin_vtable") orelse {
            return error.MissingVTable;
        };
        const new_vtable = get_vtable();

        // Call on_deinit on old version
        if (old_handle.vtable.on_deinit) |on_deinit| {
            on_deinit(&old_handle.context);
        }

        // Close old library
        old_handle.lib.close();

        // Update handle with new library
        old_handle.lib = new_lib;
        old_handle.metadata = new_metadata;
        old_handle.vtable = new_vtable;

        // Call on_reload hook
        if (new_vtable.on_reload) |on_reload| {
            const result = on_reload(&old_handle.context);
            if (result != 0) {
                return error.PluginReloadFailed;
            }
        }

        std.log.info("Reloaded plugin: {s} v{s}", .{ name, std.mem.span(new_metadata.version) });
    }

    /// Get plugin handle
    pub fn getPlugin(self: *PluginLoader, name: []const u8) ?*PluginHandle {
        return self.plugins.get(name);
    }

    /// List all loaded plugins
    pub fn listPlugins(self: *PluginLoader) ![]const []const u8 {
        var list = std.ArrayList([]const u8).init(self.allocator);
        defer list.deinit();

        var iter = self.plugins.iterator();
        while (iter.next()) |entry| {
            try list.append(entry.key_ptr.*);
        }

        return try list.toOwnedSlice();
    }
};

// =============================================================================
// Helper functions
// =============================================================================

fn createGrimAPI() GrimAPI {
    return .{
        .version = 1,
        .log = grimLogImpl,
        .register_command = grimRegisterCommandImpl,
        .get_config = grimGetConfigImpl,
        .set_config = grimSetConfigImpl,
        .get_buffer_content = grimGetBufferContentImpl,
        .set_buffer_content = grimSetBufferContentImpl,
        .get_cursor_pos = grimGetCursorPosImpl,
        .set_cursor_pos = grimSetCursorPosImpl,
    };
}

fn grimLogImpl(level: LogLevel, message: [*:0]const u8) callconv(.C) void {
    const msg = std.mem.span(message);
    switch (level) {
        .debug => std.log.debug("{s}", .{msg}),
        .info => std.log.info("{s}", .{msg}),
        .warning => std.log.warn("{s}", .{msg}),
        .err => std.log.err("{s}", .{msg}),
    }
}

fn grimRegisterCommandImpl(name: [*:0]const u8, callback: *const fn (ctx: *PluginContext, args: [*:0]const u8) callconv(.C) c_int) callconv(.C) c_int {
    _ = name;
    _ = callback;
    // TODO: Implement command registration
    return 0;
}

fn grimGetConfigImpl(key: [*:0]const u8, default_value: [*:0]const u8) callconv(.C) [*:0]const u8 {
    _ = key;
    return default_value;
}

fn grimSetConfigImpl(key: [*:0]const u8, value: [*:0]const u8) callconv(.C) c_int {
    _ = key;
    _ = value;
    return 0;
}

fn grimGetBufferContentImpl(buffer_id: usize) callconv(.C) ?[*:0]const u8 {
    _ = buffer_id;
    return null;
}

fn grimSetBufferContentImpl(buffer_id: usize, content: [*:0]const u8) callconv(.C) c_int {
    _ = buffer_id;
    _ = content;
    return 0;
}

fn grimGetCursorPosImpl(buffer_id: usize, row: *usize, col: *usize) callconv(.C) c_int {
    _ = buffer_id;
    row.* = 0;
    col.* = 0;
    return 0;
}

fn grimSetCursorPosImpl(buffer_id: usize, row: usize, col: usize) callconv(.C) c_int {
    _ = buffer_id;
    _ = row;
    _ = col;
    return 0;
}

fn createCAllocator(allocator: std.mem.Allocator) Allocator {
    _ = allocator;
    return .{
        .alloc = cAllocImpl,
        .free = cFreeImpl,
        .realloc = cReallocImpl,
    };
}

fn cAllocImpl(self: *Allocator, size: usize, alignment: usize) callconv(.C) ?*anyopaque {
    _ = self;
    _ = alignment;
    // For now, use C allocator
    // TODO: Wire up to Zig allocator properly
    const ptr = std.c.malloc(size);
    return ptr;
}

fn cFreeImpl(self: *Allocator, ptr: *anyopaque, size: usize, alignment: usize) callconv(.C) void {
    _ = self;
    _ = size;
    _ = alignment;
    std.c.free(ptr);
}

fn cReallocImpl(self: *Allocator, ptr: ?*anyopaque, old_size: usize, new_size: usize, alignment: usize) callconv(.C) ?*anyopaque {
    _ = self;
    _ = old_size;
    _ = alignment;
    return std.c.realloc(ptr, new_size);
}

// =============================================================================
// Plugin helper macros (for plugin authors)
// =============================================================================

/// Export plugin metadata
pub fn GRIM_PLUGIN_EXPORT(comptime metadata: PluginMetadata) void {
    @export(&metadata, .{ .name = "grim_plugin_metadata", .linkage = .strong });
}

/// Export plugin vtable
pub fn GRIM_PLUGIN_VTABLE(comptime vtable: PluginVTable) void {
    @export(&vtable, .{ .name = "grim_plugin_vtable", .linkage = .strong });
}

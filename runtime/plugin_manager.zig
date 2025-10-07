const std = @import("std");
const runtime = @import("mod.zig");
const host = @import("host");

const PLUGIN_EXTENSION = ".gza";
const PLUGIN_MANIFEST_FILE = "plugin.json";

const ThemeCallbacks = struct {
    pub const RegisterFn = *const fn (ctx: *anyopaque, plugin_id: []const u8, theme_name: []const u8, colors_json: []const u8) anyerror!void;
    pub const UnregisterFn = *const fn (ctx: *anyopaque, plugin_id: []const u8, theme_name: []const u8) anyerror!void;

    ctx: ?*anyopaque = null,
    register_fn: ?RegisterFn = null,
    unregister_fn: ?UnregisterFn = null,
};

const ThemeError = error{
    CallbackUnavailable,
    InvalidName,
};

const GhostlangLoadedPlugin = struct {
    const Self = @This();

    const CommandBinding = struct {
        name: []u8,
        handler: []u8,
        description: ?[]u8,

        fn deinit(self: *CommandBinding, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.handler);
            if (self.description) |desc| allocator.free(desc);
        }
    };

    const KeymapBinding = struct {
        keys: []u8,
        mode: ?runtime.PluginAPI.EditorContext.EditorMode,
        handler: []u8,
        description: ?[]u8,

        fn deinit(self: *KeymapBinding, allocator: std.mem.Allocator) void {
            allocator.free(self.keys);
            allocator.free(self.handler);
            if (self.description) |desc| allocator.free(desc);
        }
    };

    const EventBinding = struct {
        event_type: runtime.PluginAPI.EventType,
        handler: []u8,

        fn deinit(self: *EventBinding, allocator: std.mem.Allocator) void {
            allocator.free(self.handler);
        }
    };

    const ThemeRegistration = struct {
        name: []u8,

        fn deinit(self: *ThemeRegistration, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };

    runtime_plugin: runtime.Plugin,
    host: host.Host,
    compiled: host.Host.CompiledPlugin,
    allocator: std.mem.Allocator,
    command_bindings: std.ArrayList(CommandBinding),
    keymap_bindings: std.ArrayList(KeymapBinding),
    event_bindings: std.ArrayList(EventBinding),
    theme_registrations: std.ArrayList(ThemeRegistration),
    theme_callbacks: *ThemeCallbacks,
    host_deinitialized: bool,

    fn deinitBindings(self: *Self) void {
        self.clearBindings();
        self.command_bindings.deinit(self.allocator);
        self.keymap_bindings.deinit(self.allocator);
        self.event_bindings.deinit(self.allocator);
        self.theme_registrations.deinit(self.allocator);
    }

    fn appendCommandBinding(self: *Self, binding: CommandBinding) !*CommandBinding {
        try self.command_bindings.append(self.allocator, binding);
        return &self.command_bindings.items[self.command_bindings.items.len - 1];
    }

    fn appendKeymapBinding(self: *Self, binding: KeymapBinding) !*KeymapBinding {
        try self.keymap_bindings.append(self.allocator, binding);
        return &self.keymap_bindings.items[self.keymap_bindings.items.len - 1];
    }

    fn appendEventBinding(self: *Self, binding: EventBinding) !*EventBinding {
        try self.event_bindings.append(self.allocator, binding);
        return &self.event_bindings.items[self.event_bindings.items.len - 1];
    }

    fn clearBindings(self: *Self) void {
        for (self.command_bindings.items) |*binding| {
            binding.deinit(self.allocator);
        }
        self.command_bindings.clearRetainingCapacity();

        for (self.keymap_bindings.items) |*binding| {
            binding.deinit(self.allocator);
        }
        self.keymap_bindings.clearRetainingCapacity();

        for (self.event_bindings.items) |*binding| {
            binding.deinit(self.allocator);
        }
        self.event_bindings.clearRetainingCapacity();

        self.unregisterThemes();
    }

    fn findCommandBinding(self: *Self, name: []const u8) ?*const CommandBinding {
        for (self.command_bindings.items) |*binding| {
            if (std.mem.eql(u8, binding.name, name)) {
                return binding;
            }
        }
        return null;
    }

    fn findMutableCommandBinding(self: *Self, name: []const u8) ?*CommandBinding {
        for (self.command_bindings.items) |*binding| {
            if (std.mem.eql(u8, binding.name, name)) {
                return binding;
            }
        }
        return null;
    }

    fn findKeymapBinding(self: *Self, keys: []const u8, mode: ?runtime.PluginAPI.EditorContext.EditorMode) ?*const KeymapBinding {
        for (self.keymap_bindings.items) |*binding| {
            if (!std.mem.eql(u8, binding.keys, keys)) continue;
            if (binding.mode == mode) {
                return binding;
            }
        }
        return null;
    }

    fn findMutableKeymapBinding(self: *Self, keys: []const u8, mode: ?runtime.PluginAPI.EditorContext.EditorMode) ?*KeymapBinding {
        for (self.keymap_bindings.items) |*binding| {
            if (!std.mem.eql(u8, binding.keys, keys)) continue;
            if (binding.mode == mode) {
                return binding;
            }
        }
        return null;
    }

    fn findEventBinding(self: *Self, event_type: runtime.PluginAPI.EventType, handler: []const u8) ?*const EventBinding {
        for (self.event_bindings.items) |*binding| {
            if (binding.event_type == event_type and std.mem.eql(u8, binding.handler, handler)) {
                return binding;
            }
        }
        return null;
    }

    fn findMutableEventBinding(self: *Self, event_type: runtime.PluginAPI.EventType, handler: []const u8) ?*EventBinding {
        for (self.event_bindings.items) |*binding| {
            if (binding.event_type == event_type and std.mem.eql(u8, binding.handler, handler)) {
                return binding;
            }
        }
        return null;
    }

    fn findThemeRegistration(self: *Self, name: []const u8) ?*const ThemeRegistration {
        for (self.theme_registrations.items) |*registration| {
            if (std.mem.eql(u8, registration.name, name)) {
                return registration;
            }
        }
        return null;
    }

    fn findMutableThemeRegistration(self: *Self, name: []const u8) ?*ThemeRegistration {
        for (self.theme_registrations.items) |*registration| {
            if (std.mem.eql(u8, registration.name, name)) {
                return registration;
            }
        }
        return null;
    }

    fn unregisterThemes(self: *Self) void {
        if (self.theme_registrations.items.len == 0) return;

        const callbacks = self.theme_callbacks.*;
        if (callbacks.unregister_fn) |cb| {
            if (callbacks.ctx) |ctx| {
                for (self.theme_registrations.items) |registration| {
                    cb(ctx, self.runtime_plugin.id, registration.name) catch |err| {
                        std.log.err("Failed to unregister theme {s} for plugin {s}: {}", .{ registration.name, self.runtime_plugin.id, err });
                    };
                }
            }
        }

        for (self.theme_registrations.items) |*registration| {
            registration.deinit(self.allocator);
        }
        self.theme_registrations.clearRetainingCapacity();
    }
};

fn dupOptionalSlice(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    if (value) |slice| {
        if (slice.len == 0) return null;
        return try allocator.dupe(u8, slice);
    }
    return null;
}

fn parseEditorMode(value: []const u8) ?runtime.PluginAPI.EditorContext.EditorMode {
    if (std.ascii.eqlIgnoreCase(value, "normal")) return .normal;
    if (std.ascii.eqlIgnoreCase(value, "insert")) return .insert;
    if (std.ascii.eqlIgnoreCase(value, "visual")) return .visual;
    if (std.ascii.eqlIgnoreCase(value, "command")) return .command;
    return null;
}

fn parseEventType(value: []const u8) ?runtime.PluginAPI.EventType {
    return std.meta.stringToEnum(runtime.PluginAPI.EventType, value);
}

fn pluginStateFromContext(ctx: *runtime.PluginAPI.PluginContext) *GhostlangLoadedPlugin {
    const raw = ctx.userData() orelse @panic("Ghostlang plugin context missing state");
    return @as(*GhostlangLoadedPlugin, @ptrCast(@alignCast(raw)));
}

fn ghostlangShowMessageCallback(ctx_ptr: *anyopaque, message: []const u8) anyerror!void {
    const plugin_ctx = @as(*runtime.PluginAPI.PluginContext, @ptrCast(@alignCast(ctx_ptr)));
    try plugin_ctx.showMessage(message);
}

fn ghostlangRegisterCommandCallback(ctx_ptr: *anyopaque, action: *const host.Host.CommandAction) anyerror!void {
    const plugin_ctx = @as(*runtime.PluginAPI.PluginContext, @ptrCast(@alignCast(ctx_ptr)));
    var state = pluginStateFromContext(plugin_ctx);

    const name_copy = try state.allocator.dupe(u8, action.name);
    var name_owned = true;
    errdefer if (name_owned) state.allocator.free(name_copy);

    const handler_copy = try state.allocator.dupe(u8, action.handler);
    var handler_owned = true;
    errdefer if (handler_owned) state.allocator.free(handler_copy);

    const description_copy = try dupOptionalSlice(state.allocator, action.description);
    var description_owned = description_copy != null;
    errdefer if (description_owned) state.allocator.free(description_copy.?);

    if (state.findMutableCommandBinding(action.name)) |binding| {
        const description_slice: []const u8 = if (description_copy) |desc| desc else "";
        try plugin_ctx.api.registerCommand(.{
            .name = name_copy,
            .description = description_slice,
            .handler = ghostlangCommandHandler,
            .plugin_id = plugin_ctx.plugin_id,
        });

        state.allocator.free(binding.name);
        state.allocator.free(binding.handler);
        if (binding.description) |desc| state.allocator.free(desc);

        binding.name = name_copy;
        binding.handler = handler_copy;
        binding.description = description_copy;

        name_owned = false;
        handler_owned = false;
        description_owned = false;
        return;
    }

    const new_binding = GhostlangLoadedPlugin.CommandBinding{
        .name = name_copy,
        .handler = handler_copy,
        .description = description_copy,
    };

    const binding_ptr = try state.appendCommandBinding(new_binding);

    name_owned = false;
    handler_owned = false;
    description_owned = false;

    const description_slice: []const u8 = if (binding_ptr.description) |desc| desc else "";
    plugin_ctx.api.registerCommand(.{
        .name = binding_ptr.name,
        .description = description_slice,
        .handler = ghostlangCommandHandler,
        .plugin_id = plugin_ctx.plugin_id,
    }) catch |err| {
        var removed = state.command_bindings.pop() orelse unreachable;
        removed.deinit(state.allocator);
        return err;
    };
}

fn ghostlangCommandHandler(ctx: *runtime.PluginAPI.PluginContext, args: []const []const u8) anyerror!void {
    _ = args;
    const state = pluginStateFromContext(ctx);
    const command_name = ctx.currentCommand() orelse {
        std.log.warn("Command handler invoked without command context for plugin {s}", .{ctx.plugin_id});
        return;
    };

    const binding = state.findCommandBinding(command_name) orelse {
        std.log.warn("No command binding found for {s} in plugin {s}", .{ command_name, ctx.plugin_id });
        return;
    };

    try state.compiled.callVoid(binding.handler);
}

fn ghostlangRegisterKeymapCallback(ctx_ptr: *anyopaque, action: *const host.Host.KeymapAction) anyerror!void {
    const plugin_ctx = @as(*runtime.PluginAPI.PluginContext, @ptrCast(@alignCast(ctx_ptr)));
    var state = pluginStateFromContext(plugin_ctx);

    const mode = if (action.mode) |mode_str| blk: {
        const parsed = parseEditorMode(mode_str) orelse {
            std.log.warn("Unknown editor mode '{s}' for keymap in plugin {s}", .{ mode_str, plugin_ctx.plugin_id });
            break :blk null;
        };
        break :blk parsed;
    } else null;

    const keys_copy = try state.allocator.dupe(u8, action.keys);
    var keys_owned = true;
    errdefer if (keys_owned) state.allocator.free(keys_copy);

    const handler_copy = try state.allocator.dupe(u8, action.handler);
    var handler_owned = true;
    errdefer if (handler_owned) state.allocator.free(handler_copy);

    const description_copy = try dupOptionalSlice(state.allocator, action.description);
    var description_owned = description_copy != null;
    errdefer if (description_owned) state.allocator.free(description_copy.?);

    if (state.findMutableKeymapBinding(action.keys, mode)) |binding| {
        const description_slice: []const u8 = if (description_copy) |desc| desc else "";
        try plugin_ctx.api.registerKeystrokeHandler(.{
            .key_combination = keys_copy,
            .mode = mode,
            .handler = ghostlangKeystrokeHandler,
            .description = description_slice,
            .plugin_id = plugin_ctx.plugin_id,
        });

        state.allocator.free(binding.keys);
        state.allocator.free(binding.handler);
        if (binding.description) |desc| state.allocator.free(desc);

        binding.keys = keys_copy;
        binding.handler = handler_copy;
        binding.mode = mode;
        binding.description = description_copy;

        keys_owned = false;
        handler_owned = false;
        description_owned = false;
        return;
    }

    const new_binding = GhostlangLoadedPlugin.KeymapBinding{
        .keys = keys_copy,
        .handler = handler_copy,
        .mode = mode,
        .description = description_copy,
    };

    const binding_ptr = try state.appendKeymapBinding(new_binding);

    keys_owned = false;
    handler_owned = false;
    description_owned = false;

    const description_slice: []const u8 = if (binding_ptr.description) |desc| desc else "";
    plugin_ctx.api.registerKeystrokeHandler(.{
        .key_combination = binding_ptr.keys,
        .mode = binding_ptr.mode,
        .handler = ghostlangKeystrokeHandler,
        .description = description_slice,
        .plugin_id = plugin_ctx.plugin_id,
    }) catch |err| {
        var removed = state.keymap_bindings.pop() orelse unreachable;
        removed.deinit(state.allocator);
        return err;
    };
}

fn ghostlangKeystrokeHandler(ctx: *runtime.PluginAPI.PluginContext) anyerror!bool {
    const state = pluginStateFromContext(ctx);
    const invocation = ctx.currentKeystroke() orelse return false;
    const binding = state.findKeymapBinding(invocation.combination, invocation.mode) orelse return false;
    return try state.compiled.callBool(binding.handler);
}

fn ghostlangRegisterEventHandlerCallback(ctx_ptr: *anyopaque, action: *const host.Host.EventAction) anyerror!void {
    const plugin_ctx = @as(*runtime.PluginAPI.PluginContext, @ptrCast(@alignCast(ctx_ptr)));
    var state = pluginStateFromContext(plugin_ctx);

    const event_type = parseEventType(action.event) orelse {
        std.log.warn("Unknown event type '{s}' for plugin {s}", .{ action.event, plugin_ctx.plugin_id });
        return;
    };

    const handler_copy = try state.allocator.dupe(u8, action.handler);
    var handler_owned = true;
    errdefer if (handler_owned) state.allocator.free(handler_copy);

    if (state.findMutableEventBinding(event_type, action.handler)) |binding| {
        // Already registered; update handler binding if needed.
        state.allocator.free(binding.handler);
        binding.handler = handler_copy;
        handler_owned = false;
        return;
    }

    const new_binding = GhostlangLoadedPlugin.EventBinding{
        .event_type = event_type,
        .handler = handler_copy,
    };

    _ = try state.appendEventBinding(new_binding);
    handler_owned = false;

    plugin_ctx.api.registerEventHandler(.{
        .event_type = event_type,
        .handler = ghostlangEventHandler,
        .plugin_id = plugin_ctx.plugin_id,
    }) catch |err| {
        var removed = state.event_bindings.pop() orelse unreachable;
        removed.deinit(state.allocator);
        return err;
    };
}

fn ghostlangRegisterThemeCallback(ctx_ptr: *anyopaque, action: *const host.Host.ThemeAction) anyerror!void {
    const plugin_ctx = @as(*runtime.PluginAPI.PluginContext, @ptrCast(@alignCast(ctx_ptr)));
    var state = pluginStateFromContext(plugin_ctx);

    if (action.name.len == 0) {
        return ThemeError.InvalidName;
    }

    const callbacks_ptr = state.theme_callbacks;
    const register_cb = callbacks_ptr.*.register_fn orelse return ThemeError.CallbackUnavailable;
    const callback_ctx = callbacks_ptr.*.ctx orelse return ThemeError.CallbackUnavailable;

    if (state.findMutableThemeRegistration(action.name)) |registration| {
        try register_cb(callback_ctx, plugin_ctx.plugin_id, registration.name, action.colors);
        return;
    }

    const name_copy = try state.allocator.dupe(u8, action.name);
    var name_owned = true;
    errdefer if (name_owned) state.allocator.free(name_copy);

    const new_registration = GhostlangLoadedPlugin.ThemeRegistration{ .name = name_copy };
    try state.theme_registrations.append(state.allocator, new_registration);
    const registration = &state.theme_registrations.items[state.theme_registrations.items.len - 1];
    name_owned = false;

    register_cb(callback_ctx, plugin_ctx.plugin_id, registration.name, action.colors) catch |err| {
        var removed = state.theme_registrations.pop() orelse unreachable;
        removed.deinit(state.allocator);
        return err;
    };
}

fn ghostlangEventHandler(ctx: *runtime.PluginAPI.PluginContext, data: runtime.PluginAPI.EventData) anyerror!void {
    _ = data;
    const state = pluginStateFromContext(ctx);
    const event_type = ctx.currentEvent() orelse return;

    for (state.event_bindings.items) |binding| {
        if (binding.event_type == event_type) {
            try state.compiled.callVoid(binding.handler);
        }
    }
}
fn ghostlangPluginInit(ctx: *runtime.PluginAPI.PluginContext) anyerror!void {
    var state = pluginStateFromContext(ctx);

    ctx.api.unregisterPluginResources(ctx.plugin_id);
    state.clearBindings();

    const callbacks = host.Host.ActionCallbacks{
        .ctx = @as(*anyopaque, @ptrCast(ctx)),
        .show_message = ghostlangShowMessageCallback,
        .register_command = ghostlangRegisterCommandCallback,
        .register_keymap = ghostlangRegisterKeymapCallback,
        .register_event_handler = ghostlangRegisterEventHandlerCallback,
        .register_theme = ghostlangRegisterThemeCallback,
    };

    try state.compiled.executeSetup(callbacks);
}

fn ghostlangPluginDeinit(ctx: *runtime.PluginAPI.PluginContext) anyerror!void {
    var state = pluginStateFromContext(ctx);
    state.compiled.deinit();
    if (!state.host_deinitialized) {
        state.host.deinit();
        state.host_deinitialized = true;
    }
}

pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugin_api: *runtime.PluginAPI,
    plugin_directories: [][]const u8,
    ghostlang_host: host.Host,
    loaded_plugin_states: std.StringHashMap(*GhostlangLoadedPlugin),
    theme_callbacks: ThemeCallbacks,

    pub const Error = error{
        PluginDirectoryNotFound,
        InvalidPluginScript,
        PluginLoadFailed,
        SecurityViolation,
    } || runtime.PluginAPI.Error || host.Host.Error || std.fs.File.OpenError || std.mem.Allocator.Error;

    pub const PluginManifest = struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
        author: []const u8,
        description: []const u8,
        entry_point: []const u8,
        dependencies: [][]const u8,
        permissions: PluginPermissions,
        enable_on_startup: bool = true,

        pub const PluginPermissions = struct {
            file_system_access: bool = false,
            network_access: bool = false,
            system_calls: bool = false,
            editor_full_access: bool = true,
            allowed_directories: [][]const u8 = &.{},
            blocked_directories: [][]const u8 = &.{},
        };

        pub fn deinit(self: *PluginManifest, allocator: std.mem.Allocator) void {
            allocator.free(self.id);
            allocator.free(self.name);
            allocator.free(self.version);
            allocator.free(self.author);
            allocator.free(self.description);
            allocator.free(self.entry_point);

            if (self.dependencies.len > 0) {
                for (self.dependencies) |dep| allocator.free(dep);
                allocator.free(self.dependencies);
            }

            if (self.permissions.allowed_directories.len > 0) {
                for (self.permissions.allowed_directories) |dir| allocator.free(dir);
                allocator.free(self.permissions.allowed_directories);
            }

            if (self.permissions.blocked_directories.len > 0) {
                for (self.permissions.blocked_directories) |dir| allocator.free(dir);
                allocator.free(self.permissions.blocked_directories);
            }
        }
    };

    pub const PluginInfo = struct {
        manifest: PluginManifest,
        plugin_path: []const u8,
        script_content: []const u8,
        loaded: bool,
        state: ?*GhostlangLoadedPlugin = null,
    };

    pub fn init(allocator: std.mem.Allocator, plugin_api: *runtime.PluginAPI, plugin_directories: [][]const u8) !PluginManager {
        const ghostlang_host = try host.Host.init(allocator);
        return PluginManager{
            .allocator = allocator,
            .plugin_api = plugin_api,
            .plugin_directories = plugin_directories,
            .ghostlang_host = ghostlang_host,
            .loaded_plugin_states = std.StringHashMap(*GhostlangLoadedPlugin).init(allocator),
            .theme_callbacks = .{},
        };
    }

    pub fn setThemeCallbacks(
        self: *PluginManager,
        ctx: *anyopaque,
        register_cb: ?ThemeCallbacks.RegisterFn,
        unregister_cb: ?ThemeCallbacks.UnregisterFn,
    ) void {
        self.theme_callbacks.ctx = ctx;
        self.theme_callbacks.register_fn = register_cb;
        self.theme_callbacks.unregister_fn = unregister_cb;
    }

    pub fn deinit(self: *PluginManager) void {
        var iter = self.loaded_plugin_states.iterator();
        while (iter.next()) |entry| {
            self.cleanupGhostlangState(entry.value_ptr.*);
        }
        self.loaded_plugin_states.deinit();
        self.ghostlang_host.deinit();
    }

    pub fn discoverPlugins(self: *PluginManager) ![]PluginInfo {
        var discovered_plugins = std.ArrayList(PluginInfo).initCapacity(self.allocator, 0) catch unreachable;
        errdefer {
            for (discovered_plugins.items) |plugin_info| {
                self.allocator.free(plugin_info.plugin_path);
                self.allocator.free(plugin_info.script_content);
            }
            discovered_plugins.deinit(self.allocator);
        }

        for (self.plugin_directories) |plugin_dir| {
            try self.discoverPluginsInDirectory(plugin_dir, &discovered_plugins);
        }

        return discovered_plugins.toOwnedSlice(self.allocator);
    }

    fn discoverPluginsInDirectory(self: *PluginManager, directory: []const u8, plugins: *std.ArrayList(PluginInfo)) !void {
        var dir = std.fs.cwd().openDir(directory, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                std.log.warn("Plugin directory not found: {s}", .{directory});
                return;
            }
            return err;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                // Check for plugin manifest in subdirectory
                const plugin_path = try std.fs.path.join(self.allocator, &.{ directory, entry.name });
                defer self.allocator.free(plugin_path);

                if (try self.loadPluginFromDirectory(plugin_path)) |plugin_info| {
                    try plugins.append(self.allocator, plugin_info);
                }
            } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, PLUGIN_EXTENSION)) {
                // Single-file plugin
                const plugin_path = try std.fs.path.join(self.allocator, &.{ directory, entry.name });
                defer self.allocator.free(plugin_path);

                if (try self.loadSingleFilePlugin(plugin_path)) |plugin_info| {
                    try plugins.append(self.allocator, plugin_info);
                }
            }
        }
    }

    fn loadPluginFromDirectory(self: *PluginManager, plugin_dir: []const u8) !?PluginInfo {
        // Try to read plugin manifest
        const manifest_path = try std.fs.path.join(self.allocator, &.{ plugin_dir, PLUGIN_MANIFEST_FILE });
        defer self.allocator.free(manifest_path);

        const manifest_content = std.fs.cwd().readFileAlloc(manifest_path, self.allocator, .limited(1024 * 1024)) catch |err| {
            if (err == error.FileNotFound) {
                return null; // No manifest, skip this directory
            }
            return err;
        };
        defer self.allocator.free(manifest_content);

        const manifest = try self.parsePluginManifest(manifest_content);

        // Load script content
        const script_path = try std.fs.path.join(self.allocator, &.{ plugin_dir, manifest.entry_point });
        defer self.allocator.free(script_path);

        const script_content = try std.fs.cwd().readFileAlloc(script_path, self.allocator, .limited(10 * 1024 * 1024));

        return PluginInfo{
            .manifest = manifest,
            .plugin_path = try self.allocator.dupe(u8, plugin_dir),
            .script_content = script_content,
            .loaded = false,
        };
    }

    fn loadSingleFilePlugin(self: *PluginManager, plugin_path: []const u8) !?PluginInfo {
        const script_content = try std.fs.cwd().readFileAlloc(plugin_path, self.allocator, .limited(10 * 1024 * 1024));
        errdefer self.allocator.free(script_content);

        // Parse embedded manifest from script comments
        const manifest = self.parseEmbeddedManifest(script_content) catch |err| {
            self.allocator.free(script_content);
            std.log.warn("Failed to parse manifest from {s}: {}", .{ plugin_path, err });
            return null;
        };

        return PluginInfo{
            .manifest = manifest,
            .plugin_path = try self.allocator.dupe(u8, plugin_path),
            .script_content = script_content,
            .loaded = false,
        };
    }

    fn parsePluginManifest(self: *PluginManager, manifest_content: []const u8) !PluginManifest {
        const PermissionsDTO = struct {
            file_system_access: ?bool = null,
            network_access: ?bool = null,
            system_calls: ?bool = null,
            editor_full_access: ?bool = null,
            allowed_directories: ?[]const []const u8 = null,
            blocked_directories: ?[]const []const u8 = null,
        };

        const ManifestDTO = struct {
            id: []const u8,
            name: []const u8,
            version: []const u8,
            author: ?[]const u8 = null,
            description: ?[]const u8 = null,
            entry_point: []const u8,
            dependencies: ?[]const []const u8 = null,
            permissions: ?PermissionsDTO = null,
            enable_on_startup: ?bool = null,
        };

        var parsed = try std.json.parseFromSlice(ManifestDTO, self.allocator, manifest_content, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const dto = parsed.value;

        var manifest = PluginManifest{
            .id = try self.allocator.dupe(u8, dto.id),
            .name = try self.allocator.dupe(u8, dto.name),
            .version = try self.allocator.dupe(u8, dto.version),
            .author = try duplicateOptionalString(self.allocator, dto.author, "Unknown"),
            .description = try duplicateOptionalString(self.allocator, dto.description, ""),
            .entry_point = try self.allocator.dupe(u8, dto.entry_point),
            .dependencies = if (dto.dependencies) |deps| try duplicateStringSlice(self.allocator, deps) else &.{},
            .permissions = .{},
            .enable_on_startup = dto.enable_on_startup orelse true,
        };

        errdefer manifest.deinit(self.allocator);

        if (dto.permissions) |perms| {
            manifest.permissions.file_system_access = perms.file_system_access orelse manifest.permissions.file_system_access;
            manifest.permissions.network_access = perms.network_access orelse manifest.permissions.network_access;
            manifest.permissions.system_calls = perms.system_calls orelse manifest.permissions.system_calls;
            manifest.permissions.editor_full_access = perms.editor_full_access orelse manifest.permissions.editor_full_access;
            manifest.permissions.allowed_directories = if (perms.allowed_directories) |dirs| try duplicateStringSlice(self.allocator, dirs) else manifest.permissions.allowed_directories;
            manifest.permissions.blocked_directories = if (perms.blocked_directories) |dirs| try duplicateStringSlice(self.allocator, dirs) else manifest.permissions.blocked_directories;
        }

        try self.validatePermissions(&manifest.permissions);
        return manifest;
    }

    fn duplicateOptionalString(allocator: std.mem.Allocator, value: ?[]const u8, default_value: []const u8) ![]const u8 {
        if (value) |val| {
            return try allocator.dupe(u8, val);
        }
        return try allocator.dupe(u8, default_value);
    }

    fn duplicateStringSlice(allocator: std.mem.Allocator, source: []const []const u8) ![][]const u8 {
        if (source.len == 0) return &.{};
        var dest = try allocator.alloc([]const u8, source.len);
        var i: usize = 0;
        errdefer {
            while (i > 0) : (i -= 1) {
                allocator.free(dest[i - 1]);
            }
            allocator.free(dest);
        }
        while (i < source.len) : (i += 1) {
            dest[i] = try allocator.dupe(u8, source[i]);
        }
        return dest;
    }

    fn validatePermissions(self: *PluginManager, permissions: *PluginManifest.PluginPermissions) !void {
        _ = self;
        const forbidden = [_][]const u8{ "..", "~", "//" };
        for (permissions.allowed_directories) |dir| {
            for (forbidden) |marker| {
                if (std.mem.indexOf(u8, dir, marker)) |_| {
                    return Error.SecurityViolation;
                }
            }
        }
        for (permissions.blocked_directories) |dir| {
            for (forbidden) |marker| {
                if (std.mem.indexOf(u8, dir, marker)) |_| {
                    return Error.SecurityViolation;
                }
            }
        }
    }

    fn parseEmbeddedManifest(self: *PluginManager, script_content: []const u8) !PluginManifest {
        _ = self;

        // Look for plugin metadata in comments at the top of the file
        // Format: // @plugin-id: example-plugin
        //         // @plugin-name: Example Plugin
        //         // @plugin-version: 1.0.0
        //         // etc.

        var id: ?[]const u8 = null;
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var author: ?[]const u8 = null;
        var description: ?[]const u8 = null;

        var lines = std.mem.splitSequence(u8, script_content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Stop parsing metadata when we reach non-comment line
            if (!std.mem.startsWith(u8, trimmed, "//")) {
                break;
            }

            // Parse metadata tags
            if (std.mem.startsWith(u8, trimmed, "// @plugin-id:")) {
                id = std.mem.trim(u8, trimmed[14..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-name:")) {
                name = std.mem.trim(u8, trimmed[16..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-version:")) {
                version = std.mem.trim(u8, trimmed[19..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-author:")) {
                author = std.mem.trim(u8, trimmed[18..], " \t");
            } else if (std.mem.startsWith(u8, trimmed, "// @plugin-description:")) {
                description = std.mem.trim(u8, trimmed[23..], " \t");
            }
        }

        return PluginManifest{
            .id = id orelse "unknown-plugin",
            .name = name orelse "Unknown Plugin",
            .version = version orelse "0.0.0",
            .author = author orelse "Unknown",
            .description = description orelse "No description provided",
            .entry_point = "main.gza",
            .dependencies = &.{},
            .permissions = .{},
            .enable_on_startup = true,
        };
    }

    pub fn loadPlugin(self: *PluginManager, plugin_info: *PluginInfo) !void {
        if (plugin_info.loaded) {
            return; // Already loaded
        }

        // Create sandbox configuration based on plugin permissions
        const sandbox_config = host.Host.SandboxConfig{
            .enable_filesystem_access = plugin_info.manifest.permissions.file_system_access,
            .enable_network_access = plugin_info.manifest.permissions.network_access,
            .enable_system_calls = plugin_info.manifest.permissions.system_calls,
            .allowed_file_patterns = plugin_info.manifest.permissions.allowed_directories,
            .blocked_file_patterns = plugin_info.manifest.permissions.blocked_directories,
        };

        var plugin_host = try host.Host.initWithSandbox(self.allocator, sandbox_config);
        var host_cleanup = true;
        defer if (host_cleanup) plugin_host.deinit();

        const compiled = plugin_host.compilePluginScript(plugin_info.script_content) catch |err| {
            return err;
        };

        var state = try self.allocator.create(GhostlangLoadedPlugin);
        errdefer self.cleanupGhostlangState(state);

        state.* = .{
            .runtime_plugin = runtime.Plugin{
                .id = plugin_info.manifest.id,
                .name = plugin_info.manifest.name,
                .version = plugin_info.manifest.version,
                .author = plugin_info.manifest.author,
                .description = plugin_info.manifest.description,
                .context = undefined,
                .user_data = null,
                .init_fn = ghostlangPluginInit,
                .deinit_fn = ghostlangPluginDeinit,
                .activate_fn = null,
                .deactivate_fn = null,
            },
            .host = plugin_host,
            .compiled = compiled,
            .allocator = self.allocator,
            .command_bindings = std.ArrayList(GhostlangLoadedPlugin.CommandBinding).initCapacity(self.allocator, 0) catch unreachable,
            .keymap_bindings = std.ArrayList(GhostlangLoadedPlugin.KeymapBinding).initCapacity(self.allocator, 0) catch unreachable,
            .event_bindings = std.ArrayList(GhostlangLoadedPlugin.EventBinding).initCapacity(self.allocator, 0) catch unreachable,
            .theme_registrations = std.ArrayList(GhostlangLoadedPlugin.ThemeRegistration).initCapacity(self.allocator, 0) catch unreachable,
            .host_deinitialized = false,
            .theme_callbacks = &self.theme_callbacks,
        };
        state.compiled.host = &state.host;
        host_cleanup = false;

        state.runtime_plugin.user_data = state;

        try self.plugin_api.loadPlugin(&state.runtime_plugin);

        try self.loaded_plugin_states.put(plugin_info.manifest.id, state);
        plugin_info.state = state;
        plugin_info.loaded = true;

        std.log.info("Loaded plugin: {s} v{s} from {s}", .{
            plugin_info.manifest.name,
            plugin_info.manifest.version,
            plugin_info.plugin_path,
        });
    }

    pub fn unloadPlugin(self: *PluginManager, plugin_id: []const u8) !void {
        try self.plugin_api.unloadPlugin(plugin_id);
        if (self.loaded_plugin_states.fetchRemove(plugin_id)) |entry| {
            self.cleanupGhostlangState(entry.value);
        }
    }

    pub fn reloadPlugin(self: *PluginManager, plugin_info: *PluginInfo) !void {
        if (plugin_info.loaded) {
            try self.unloadPlugin(plugin_info.manifest.id);
            plugin_info.loaded = false;
            plugin_info.state = null;
        }

        // Reload script content
        self.allocator.free(plugin_info.script_content);
        plugin_info.script_content = try std.fs.cwd().readFileAlloc(plugin_info.plugin_path, self.allocator, .limited(10 * 1024 * 1024));

        try self.loadPlugin(plugin_info);
    }

    pub fn listCommands(self: *PluginManager, allocator: std.mem.Allocator) ![]runtime.PluginAPI.Command {
        return try self.plugin_api.listCommands(allocator);
    }

    pub fn executeCommand(self: *PluginManager, command_name: []const u8, args: []const []const u8) !void {
        const command = self.plugin_api.findCommand(command_name) orelse return runtime.PluginAPI.Error.CommandNotFound;
        try self.plugin_api.executeCommand(command.name, command.plugin_id, args);
    }

    pub fn emitEvent(self: *PluginManager, event_type: runtime.PluginAPI.EventType, data: runtime.PluginAPI.EventData) !void {
        try self.plugin_api.emitEvent(event_type, data);
    }

    pub fn handleKeystroke(self: *PluginManager, key_combination: []const u8, mode: runtime.PluginAPI.EditorContext.EditorMode) !bool {
        return try self.plugin_api.handleKeystroke(key_combination, mode);
    }

    pub fn listLoadedPlugins(self: *PluginManager, allocator: std.mem.Allocator) ![][]const u8 {
        return try self.plugin_api.getLoadedPlugins(allocator);
    }

    pub fn getPluginStats(self: *PluginManager) host.Host.ExecutionStats {
        var aggregate = host.Host.ExecutionStats{};
        var iter = self.loaded_plugin_states.iterator();
        while (iter.next()) |entry| {
            const state = entry.value_ptr.*;
            const stats = state.host.getExecutionStats();
            aggregate.execution_count += stats.execution_count;
            aggregate.total_execution_time_ms += stats.total_execution_time_ms;
            aggregate.peak_memory_usage = @max(aggregate.peak_memory_usage, stats.peak_memory_usage);
            aggregate.file_operations_count += stats.file_operations_count;
            aggregate.network_requests_count += stats.network_requests_count;
            aggregate.sandbox_violations += stats.sandbox_violations;
            aggregate.last_execution_time = stats.last_execution_time;
        }
        return aggregate;
    }

    pub fn resetStats(self: *PluginManager) void {
        var iter = self.loaded_plugin_states.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.host.resetStats();
        }
    }

    fn cleanupGhostlangState(self: *PluginManager, state: *GhostlangLoadedPlugin) void {
        if (!state.host_deinitialized) {
            state.compiled.deinit();
            state.host.deinit();
            state.host_deinitialized = true;
        }
        state.deinitBindings();
        self.allocator.destroy(state);
    }
};

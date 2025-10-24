//! core/plugin_host_adapter.zig
//! Bridges grim runtime host callbacks into phantom.grim systems.

const std = @import("std");
const zlog = @import("zlog");
const grim = @import("grim");

const CommandRegistry = @import("command_registry.zig").CommandRegistry;
const KeymapManager = @import("keymap_manager.zig").KeymapManager;
const EventSystem = @import("event_system.zig").EventSystem;
const ThemeManager = @import("theme_manager.zig").ThemeManager;
const LSPManager = @import("lsp_manager.zig").LSPManager;
const SyntaxHighlighter = @import("syntax_highlighter.zig").SyntaxHighlighter;

const Host = grim.host.Host;

/// Optional sink for plugin-generated messages.
pub const MessageSink = struct {
    ctx: *anyopaque,
    handlerFn: *const fn (ctx: *anyopaque, message: []const u8) anyerror!void,
};

/// Adapter passed to grim's Host.ActionCallbacks.
pub const PhantomPluginHost = struct {
    allocator: std.mem.Allocator,
    command_registry: ?*CommandRegistry = null,
    keymap_manager: ?*KeymapManager = null,
    event_system: ?*EventSystem = null,
    theme_manager: ?*ThemeManager = null,
    lsp_manager: ?*LSPManager = null,
    syntax_highlighter: ?*SyntaxHighlighter = null,
    message_sink: ?MessageSink = null,

    pub fn init(allocator: std.mem.Allocator) PhantomPluginHost {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PhantomPluginHost) void {
        self.command_registry = null;
        self.keymap_manager = null;
        self.event_system = null;
        self.theme_manager = null;
        self.lsp_manager = null;
        self.syntax_highlighter = null;
        self.message_sink = null;
        self.allocator = undefined;
    }

    pub fn setCommandRegistry(self: *PhantomPluginHost, registry: *CommandRegistry) void {
        self.command_registry = registry;
    }

    pub fn clearCommandRegistry(self: *PhantomPluginHost) void {
        self.command_registry = null;
    }

    pub fn setKeymapManager(self: *PhantomPluginHost, manager: *KeymapManager) void {
        self.keymap_manager = manager;
    }

    pub fn clearKeymapManager(self: *PhantomPluginHost) void {
        self.keymap_manager = null;
    }

    pub fn setEventSystem(self: *PhantomPluginHost, system: *EventSystem) void {
        self.event_system = system;
    }

    pub fn clearEventSystem(self: *PhantomPluginHost) void {
        self.event_system = null;
    }

    pub fn setThemeManager(self: *PhantomPluginHost, manager: *ThemeManager) void {
        self.theme_manager = manager;
    }

    pub fn clearThemeManager(self: *PhantomPluginHost) void {
        self.theme_manager = null;
    }

    pub fn setLSPManager(self: *PhantomPluginHost, manager: *LSPManager) void {
        self.lsp_manager = manager;
    }

    pub fn clearLSPManager(self: *PhantomPluginHost) void {
        self.lsp_manager = null;
    }

    pub fn setSyntaxHighlighter(self: *PhantomPluginHost, highlighter: *SyntaxHighlighter) void {
        self.syntax_highlighter = highlighter;
    }

    pub fn clearSyntaxHighlighter(self: *PhantomPluginHost) void {
        self.syntax_highlighter = null;
    }

    pub fn setMessageSink(self: *PhantomPluginHost, sink: MessageSink) void {
        self.message_sink = sink;
    }

    pub fn clearMessageSink(self: *PhantomPluginHost) void {
        self.message_sink = null;
    }

    /// Build the callback table that grim runtime expects.
    pub fn callbacks(self: *PhantomPluginHost) Host.ActionCallbacks {
        return .{
            .ctx = @as(*anyopaque, @ptrCast(self)),
            .show_message = adapterShowMessage,
            .register_command = adapterRegisterCommand,
            .register_keymap = adapterRegisterKeymap,
            .register_event_handler = adapterRegisterEvent,
            .register_theme = adapterRegisterTheme,
        };
    }

    fn adapterShowMessage(ctx: *anyopaque, message: []const u8) anyerror!void {
        const self = selfFromCtx(ctx);
        if (self.message_sink) |sink| {
            try sink.handlerFn(sink.ctx, message);
            return;
        }
        zlog.info("[plugin] {s}", .{message});
    }

    fn adapterRegisterCommand(ctx: *anyopaque, action: *const Host.CommandAction) anyerror!void {
        const self = selfFromCtx(ctx);
        if (self.command_registry) |registry| {
            registry.register(action) catch |err| {
                zlog.err("Failed to register command {s}: {s}", .{ action.name, @errorName(err) });
                return err;
            };
            return;
        }
        zlog.warn("Plugin attempted to register command without registry: {s}", .{action.name});
        return error.CommandRegistryUnavailable;
    }

    fn adapterRegisterKeymap(ctx: *anyopaque, action: *const Host.KeymapAction) anyerror!void {
        const self = selfFromCtx(ctx);
        const mode = action.mode orelse "";
        const keys = action.keys;
        if (self.keymap_manager) |manager| {
            manager.register(action) catch |err| {
                zlog.err(
                    "Failed to register keymap {s}:{s}: {s}",
                    .{ mode, keys, @errorName(err) },
                );
                return err;
            };
            return;
        }
        zlog.warn("Plugin attempted to register keymap without manager: {s}", .{keys});
        return error.KeymapManagerUnavailable;
    }

    fn adapterRegisterEvent(ctx: *anyopaque, action: *const Host.EventAction) anyerror!void {
        const self = selfFromCtx(ctx);
        if (self.event_system) |system| {
            system.register(action) catch |err| {
                zlog.err("Failed to register event handler {s}: {s}", .{ action.event, @errorName(err) });
                return err;
            };
            return;
        }
        zlog.warn("Plugin attempted to register event handler without system: {s}", .{action.event});
        return error.EventSystemUnavailable;
    }

    fn adapterRegisterTheme(ctx: *anyopaque, action: *const Host.ThemeAction) anyerror!void {
        const self = selfFromCtx(ctx);
        if (self.theme_manager) |manager| {
            manager.register(action) catch |err| {
                zlog.err("Failed to register theme {s}: {s}", .{ action.name, @errorName(err) });
                return err;
            };
            return;
        }
        zlog.warn("Plugin attempted to register theme entry without manager: {s}", .{action.name});
        return error.ThemeManagerUnavailable;
    }

    fn selfFromCtx(ctx: *anyopaque) *PhantomPluginHost {
        const raw: *PhantomPluginHost = @ptrFromInt(@intFromPtr(ctx));
        return @alignCast(raw);
    }
};

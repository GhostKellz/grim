const std = @import("std");
const core = @import("core");
const syntax = @import("syntax");
const host = @import("host");

pub const PluginAPI = struct {
    allocator: std.mem.Allocator,
    editor_context: *EditorContext,
    command_registry: CommandRegistry,
    event_handlers: EventHandlers,
    keystroke_handlers: KeystrokeHandlers,
    loaded_plugins: std.StringHashMap(*Plugin),

    pub const EditorContext = struct {
        rope: *core.Rope,
        cursor_position: *CursorPosition,
        current_mode: *EditorMode,
        highlighter: *syntax.SyntaxHighlighter,

        pub const CursorPosition = struct {
            line: usize,
            column: usize,
            byte_offset: usize,
        };

        pub const EditorMode = enum {
            normal,
            insert,
            visual,
            command,
        };
    };

    pub const Command = struct {
        name: []const u8,
        description: []const u8,
        handler: *const fn (ctx: *PluginContext, args: []const []const u8) anyerror!void,
        plugin_id: []const u8,
    };

    pub const CommandRegistry = struct {
        commands: std.StringHashMap(Command),

        pub fn init(allocator: std.mem.Allocator) CommandRegistry {
            return .{ .commands = std.StringHashMap(Command).init(allocator) };
        }

        pub fn deinit(self: *CommandRegistry) void {
            self.commands.deinit();
        }

        pub fn register(self: *CommandRegistry, command: Command) !void {
            try self.commands.put(command.name, command);
        }

        pub fn execute(self: *CommandRegistry, name: []const u8, ctx: *PluginContext, args: []const []const u8) !void {
            const command = self.commands.get(name) orelse return error.CommandNotFound;
            try command.handler(ctx, args);
        }

        pub fn list(self: *CommandRegistry, allocator: std.mem.Allocator) ![]Command {
            var result = try allocator.alloc(Command, self.commands.count());
            var i: usize = 0;
            var iterator = self.commands.iterator();
            while (iterator.next()) |entry| {
                result[i] = entry.value_ptr.*;
                i += 1;
            }
            return result;
        }
    };

    pub const EventType = enum {
        buffer_created,
        buffer_opened,
        buffer_saved,
        buffer_closed,
        cursor_moved,
        text_inserted,
        text_deleted,
        mode_changed,
        file_opened,
        file_saved,
        window_resized,
        plugin_loaded,
        plugin_unloaded,
    };

    pub const EventData = union(EventType) {
        buffer_created: BufferId,
        buffer_opened: struct { buffer_id: BufferId, filename: []const u8 },
        buffer_saved: struct { buffer_id: BufferId, filename: []const u8 },
        buffer_closed: BufferId,
        cursor_moved: struct { buffer_id: BufferId, line: usize, column: usize },
        text_inserted: struct { buffer_id: BufferId, position: usize, text: []const u8 },
        text_deleted: struct { buffer_id: BufferId, position: usize, length: usize },
        mode_changed: struct { old_mode: EditorContext.EditorMode, new_mode: EditorContext.EditorMode },
        file_opened: []const u8,
        file_saved: []const u8,
        window_resized: struct { width: u32, height: u32 },
        plugin_loaded: []const u8,
        plugin_unloaded: []const u8,
    };

    pub const BufferId = u32;

    pub const EventHandler = struct {
        event_type: EventType,
        handler: *const fn (ctx: *PluginContext, data: EventData) anyerror!void,
        plugin_id: []const u8,
    };

    pub const EventHandlers = struct {
        handlers: std.EnumArray(EventType, std.ArrayList(EventHandler)),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) EventHandlers {
            var handlers = std.EnumArray(EventType, std.ArrayList(EventHandler)).initUndefined();
            for (std.meta.tags(EventType)) |event_type| {
                handlers.set(event_type, std.ArrayList(EventHandler).init(allocator));
            }
            return .{ .handlers = handlers, .allocator = allocator };
        }

        pub fn deinit(self: *EventHandlers) void {
            for (std.meta.tags(EventType)) |event_type| {
                self.handlers.getPtr(event_type).deinit();
            }
        }

        pub fn register(self: *EventHandlers, handler: EventHandler) !void {
            try self.handlers.getPtr(handler.event_type).append(handler);
        }

        pub fn emit(self: *EventHandlers, ctx: *PluginContext, event_type: EventType, data: EventData) !void {
            const handlers_list = self.handlers.get(event_type);
            for (handlers_list.items) |handler| {
                handler.handler(ctx, data) catch |err| {
                    std.log.err("Event handler error in plugin {s}: {}", .{ handler.plugin_id, err });
                };
            }
        }
    };

    pub const KeystrokeHandler = struct {
        key_combination: []const u8, // e.g., "Ctrl+S", "<leader>w"
        mode: ?EditorContext.EditorMode, // null for any mode
        handler: *const fn (ctx: *PluginContext) anyerror!bool, // returns true if handled
        description: []const u8,
        plugin_id: []const u8,
    };

    pub const KeystrokeHandlers = struct {
        handlers: std.ArrayList(KeystrokeHandler),

        pub fn init(allocator: std.mem.Allocator) KeystrokeHandlers {
            return .{ .handlers = std.ArrayList(KeystrokeHandler).init(allocator) };
        }

        pub fn deinit(self: *KeystrokeHandlers) void {
            self.handlers.deinit();
        }

        pub fn register(self: *KeystrokeHandlers, handler: KeystrokeHandler) !void {
            try self.handlers.append(handler);
        }

        pub fn handle(self: *KeystrokeHandlers, ctx: *PluginContext, key_combination: []const u8, mode: EditorContext.EditorMode) !bool {
            for (self.handlers.items) |handler| {
                if (std.mem.eql(u8, handler.key_combination, key_combination)) {
                    if (handler.mode == null or handler.mode.? == mode) {
                        if (try handler.handler(ctx)) {
                            return true; // Key was handled
                        }
                    }
                }
            }
            return false; // Key not handled
        }
    };

    pub const PluginContext = struct {
        plugin_id: []const u8,
        api: *PluginAPI,
        scratch_allocator: std.mem.Allocator,

        // Editor operations
        pub fn getCurrentBuffer(self: *PluginContext) !BufferId {
            _ = self;
            return 1; // Placeholder - would integrate with actual editor
        }

        pub fn getBufferContent(self: *PluginContext, buffer_id: BufferId) ![]const u8 {
            _ = buffer_id;
            return try self.api.editor_context.rope.slice(.{ .start = 0, .end = self.api.editor_context.rope.len() });
        }

        pub fn setBufferContent(self: *PluginContext, buffer_id: BufferId, content: []const u8) !void {
            _ = buffer_id;
            // Clear existing content
            const len = self.api.editor_context.rope.len();
            if (len > 0) {
                try self.api.editor_context.rope.delete(0, len);
            }
            // Insert new content
            try self.api.editor_context.rope.insert(0, content);
        }

        pub fn getBufferLine(self: *PluginContext, buffer_id: BufferId, line_num: usize) ![]const u8 {
            _ = self;
            _ = buffer_id;
            _ = line_num;
            // TODO: Implement line-based access to rope
            return ""; // Placeholder
        }

        pub fn getCursorPosition(self: *PluginContext) EditorContext.CursorPosition {
            return self.api.editor_context.cursor_position.*;
        }

        pub fn setCursorPosition(self: *PluginContext, position: EditorContext.CursorPosition) !void {
            self.api.editor_context.cursor_position.* = position;
        }

        pub fn getCurrentMode(self: *PluginContext) EditorContext.EditorMode {
            return self.api.editor_context.current_mode.*;
        }

        pub fn setMode(self: *PluginContext, mode: EditorContext.EditorMode) !void {
            const old_mode = self.api.editor_context.current_mode.*;
            self.api.editor_context.current_mode.* = mode;

            // Emit mode change event
            try self.api.event_handlers.emit(self, .mode_changed, .{
                .mode_changed = .{ .old_mode = old_mode, .new_mode = mode }
            });
        }

        // UI operations
        pub fn showMessage(self: *PluginContext, message: []const u8) !void {
            _ = self;
            std.log.info("Plugin message: {s}", .{message});
        }

        pub fn showError(self: *PluginContext, error_msg: []const u8) !void {
            _ = self;
            std.log.err("Plugin error: {s}", .{error_msg});
        }

        pub fn getInput(self: *PluginContext, prompt: []const u8) !?[]const u8 {
            _ = self;
            _ = prompt;
            // TODO: Implement input dialog
            return null; // Placeholder
        }

        // File operations (with sandbox validation)
        pub fn readFile(self: *PluginContext, path: []const u8) ![]const u8 {
            // Validate file access through Ghostlang host
            var ghostlang_host = try host.Host.init(self.scratch_allocator);
            defer ghostlang_host.deinit();

            // This would be integrated with the actual Ghostlang safety checks
            // try ghostlang_host.validateFileAccess(path);

            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            return try file.readToEndAlloc(self.scratch_allocator, std.math.maxInt(usize));
        }

        pub fn writeFile(self: *PluginContext, path: []const u8, content: []const u8) !void {
            _ = self;
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(content);
        }

        pub fn fileExists(self: *PluginContext, path: []const u8) bool {
            _ = self;
            std.fs.cwd().access(path, .{}) catch return false;
            return true;
        }
    };

    pub const Plugin = struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
        author: []const u8,
        description: []const u8,
        context: PluginContext,

        // Plugin lifecycle hooks
        init_fn: ?*const fn (ctx: *PluginContext) anyerror!void = null,
        deinit_fn: ?*const fn (ctx: *PluginContext) anyerror!void = null,
        activate_fn: ?*const fn (ctx: *PluginContext) anyerror!void = null,
        deactivate_fn: ?*const fn (ctx: *PluginContext) anyerror!void = null,

        pub fn init(self: *Plugin) !void {
            if (self.init_fn) |init_fn| {
                try init_fn(&self.context);
            }
        }

        pub fn deinit(self: *Plugin) !void {
            if (self.deinit_fn) |deinit_fn| {
                try deinit_fn(&self.context);
            }
        }

        pub fn activate(self: *Plugin) !void {
            if (self.activate_fn) |activate_fn| {
                try activate_fn(&self.context);
            }
        }

        pub fn deactivate(self: *Plugin) !void {
            if (self.deactivate_fn) |deactivate_fn| {
                try deactivate_fn(&self.context);
            }
        }
    };

    pub const Error = error{
        PluginNotFound,
        PluginAlreadyLoaded,
        CommandNotFound,
        InvalidPluginFormat,
    } || std.mem.Allocator.Error || std.fs.File.OpenError;

    pub fn init(allocator: std.mem.Allocator, editor_context: *EditorContext) PluginAPI {
        return .{
            .allocator = allocator,
            .editor_context = editor_context,
            .command_registry = CommandRegistry.init(allocator),
            .event_handlers = EventHandlers.init(allocator),
            .keystroke_handlers = KeystrokeHandlers.init(allocator),
            .loaded_plugins = std.StringHashMap(*Plugin).init(allocator),
        };
    }

    pub fn deinit(self: *PluginAPI) void {
        // Unload all plugins
        var iterator = self.loaded_plugins.iterator();
        while (iterator.next()) |entry| {
            self.unloadPlugin(entry.key_ptr.*) catch {};
        }

        self.command_registry.deinit();
        self.event_handlers.deinit();
        self.keystroke_handlers.deinit();
        self.loaded_plugins.deinit();
    }

    pub fn loadPlugin(self: *PluginAPI, plugin: *Plugin) !void {
        if (self.loaded_plugins.contains(plugin.id)) {
            return Error.PluginAlreadyLoaded;
        }

        // Initialize plugin context
        plugin.context = PluginContext{
            .plugin_id = plugin.id,
            .api = self,
            .scratch_allocator = self.allocator,
        };

        // Initialize plugin
        try plugin.init();

        // Store plugin
        try self.loaded_plugins.put(plugin.id, plugin);

        // Emit plugin loaded event
        try self.event_handlers.emit(&plugin.context, .plugin_loaded, .{ .plugin_loaded = plugin.id });

        std.log.info("Loaded plugin: {s} v{s}", .{ plugin.name, plugin.version });
    }

    pub fn unloadPlugin(self: *PluginAPI, plugin_id: []const u8) !void {
        const plugin = self.loaded_plugins.get(plugin_id) orelse return Error.PluginNotFound;

        // Deactivate and deinitialize plugin
        try plugin.deactivate();
        try plugin.deinit();

        // Remove from loaded plugins
        _ = self.loaded_plugins.remove(plugin_id);

        // Emit plugin unloaded event
        try self.event_handlers.emit(&plugin.context, .plugin_unloaded, .{ .plugin_unloaded = plugin_id });

        std.log.info("Unloaded plugin: {s}", .{plugin_id});
    }

    pub fn registerCommand(self: *PluginAPI, command: Command) !void {
        try self.command_registry.register(command);
    }

    pub fn executeCommand(self: *PluginAPI, name: []const u8, plugin_id: []const u8, args: []const []const u8) !void {
        const plugin = self.loaded_plugins.get(plugin_id) orelse return Error.PluginNotFound;
        try self.command_registry.execute(name, &plugin.context, args);
    }

    pub fn registerEventHandler(self: *PluginAPI, handler: EventHandler) !void {
        try self.event_handlers.register(handler);
    }

    pub fn registerKeystrokeHandler(self: *PluginAPI, handler: KeystrokeHandler) !void {
        try self.keystroke_handlers.register(handler);
    }

    pub fn emitEvent(self: *PluginAPI, event_type: EventType, data: EventData) !void {
        // Create a temporary context for system events
        var temp_context = PluginContext{
            .plugin_id = "system",
            .api = self,
            .scratch_allocator = self.allocator,
        };
        try self.event_handlers.emit(&temp_context, event_type, data);
    }

    pub fn handleKeystroke(self: *PluginAPI, key_combination: []const u8, mode: EditorContext.EditorMode) !bool {
        var temp_context = PluginContext{
            .plugin_id = "system",
            .api = self,
            .scratch_allocator = self.allocator,
        };
        return try self.keystroke_handlers.handle(&temp_context, key_combination, mode);
    }

    pub fn listCommands(self: *PluginAPI) ![]Command {
        return try self.command_registry.list(self.allocator);
    }

    pub fn getLoadedPlugins(self: *PluginAPI, allocator: std.mem.Allocator) ![][]const u8 {
        var result = try allocator.alloc([]const u8, self.loaded_plugins.count());
        var i: usize = 0;
        var iterator = self.loaded_plugins.keyIterator();
        while (iterator.next()) |key| {
            result[i] = key.*;
            i += 1;
        }
        return result;
    }
};
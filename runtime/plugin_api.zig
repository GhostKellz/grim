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
        selection_start: ?*?usize = null,
        selection_end: ?*?usize = null,
        active_buffer_id: BufferId = 1,
        bridge: ?EditorBridge = null,

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

        pub const SelectionRange = struct {
            start: usize,
            end: usize,
        };

        pub const BufferChangeKind = enum {
            insert,
            delete,
            replace,
        };

        pub const BufferChange = struct {
            buffer_id: BufferId,
            range: core.Rope.Range,
            inserted_len: usize,
            kind: BufferChangeKind,
        };

        pub const EditorBridge = struct {
            ctx: *anyopaque,
            getCurrentBuffer: *const fn (ctx: *anyopaque) BufferId,
            getBufferContent: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator, buffer_id: BufferId) anyerror![]const u8 = null,
            setBufferContent: ?*const fn (ctx: *anyopaque, buffer_id: BufferId, content: []const u8) anyerror!void = null,
            getBufferLine: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator, buffer_id: BufferId, line_num: usize) anyerror![]const u8 = null,
            insertText: ?*const fn (ctx: *anyopaque, buffer_id: BufferId, position: usize, text: []const u8) anyerror!void = null,
            deleteRange: ?*const fn (ctx: *anyopaque, buffer_id: BufferId, range: core.Rope.Range) anyerror!void = null,
            getCursorPosition: ?*const fn (ctx: *anyopaque) CursorPosition = null,
            setCursorPosition: ?*const fn (ctx: *anyopaque, position: CursorPosition) anyerror!void = null,
            getSelection: ?*const fn (ctx: *anyopaque) ?SelectionRange = null,
            setSelection: ?*const fn (ctx: *anyopaque, selection: ?SelectionRange) anyerror!void = null,
            notifyChange: ?*const fn (ctx: *anyopaque, change: BufferChange) anyerror!void = null,
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
            const previous = ctx.current_command;
            ctx.current_command = command.name;
            defer ctx.current_command = previous;
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

        pub fn get(self: *CommandRegistry, name: []const u8) ?Command {
            return self.commands.get(name);
        }

        pub fn unregister(self: *CommandRegistry, allocator: std.mem.Allocator, plugin_id: []const u8) void {
            var keys_to_remove = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
            defer keys_to_remove.deinit(allocator);

            var iterator = self.commands.iterator();
            while (iterator.next()) |entry| {
                if (std.mem.eql(u8, entry.value_ptr.plugin_id, plugin_id)) {
                    keys_to_remove.append(allocator, entry.key_ptr.*) catch |err| {
                        std.log.err("Failed to queue command removal for plugin {s}: {}", .{ plugin_id, err });
                        break;
                    };
                }
            }

            for (keys_to_remove.items) |key| {
                _ = self.commands.remove(key);
            }
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
    pub const BufferError = error{InvalidBuffer};

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
                handlers.set(event_type, std.ArrayList(EventHandler).initCapacity(allocator, 0) catch unreachable);
            }
            return .{ .handlers = handlers, .allocator = allocator };
        }

        pub fn deinit(self: *EventHandlers) void {
            for (std.meta.tags(EventType)) |event_type| {
                self.handlers.getPtr(event_type).deinit(self.allocator);
            }
        }

        pub fn register(self: *EventHandlers, handler: EventHandler) !void {
            try self.handlers.getPtr(handler.event_type).append(self.allocator, handler);
        }

        pub fn emit(self: *EventHandlers, ctx: *PluginContext, event_type: EventType, data: EventData) !void {
            const handlers_list = self.handlers.get(event_type);
            for (handlers_list.items) |handler| {
                var target_ctx = ctx;
                if (!std.mem.eql(u8, handler.plugin_id, ctx.plugin_id)) {
                    if (ctx.api.loaded_plugins.get(handler.plugin_id)) |plugin| {
                        target_ctx = &plugin.context;
                    } else {
                        std.log.warn("Event handler for plugin {s} skipped; plugin not loaded", .{handler.plugin_id});
                        continue;
                    }
                }

                const previous_event = target_ctx.current_event;
                target_ctx.current_event = event_type;
                defer target_ctx.current_event = previous_event;

                handler.handler(target_ctx, data) catch |err| {
                    std.log.err("Event handler error in plugin {s}: {}", .{ handler.plugin_id, err });
                };
            }
        }

        pub fn unregister(self: *EventHandlers, plugin_id: []const u8) void {
            for (std.meta.tags(EventType)) |event_type| {
                var list = self.handlers.getPtr(event_type);
                var i: usize = list.items.len;
                while (i > 0) : (i -= 1) {
                    const idx = i - 1;
                    if (std.mem.eql(u8, list.items[idx].plugin_id, plugin_id)) {
                        _ = list.orderedRemove(idx);
                    }
                }
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
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) KeystrokeHandlers {
            return .{
                .handlers = std.ArrayList(KeystrokeHandler).initCapacity(allocator, 0) catch unreachable,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *KeystrokeHandlers) void {
            self.handlers.deinit(self.allocator);
        }

        pub fn register(self: *KeystrokeHandlers, handler: KeystrokeHandler) !void {
            try self.handlers.append(self.allocator, handler);
        }

        pub fn handle(self: *KeystrokeHandlers, ctx: *PluginContext, key_combination: []const u8, mode: EditorContext.EditorMode) !bool {
            for (self.handlers.items) |handler| {
                if (std.mem.eql(u8, handler.key_combination, key_combination)) {
                    if (handler.mode == null or handler.mode.? == mode) {
                        var target_ctx = ctx;
                        if (!std.mem.eql(u8, handler.plugin_id, ctx.plugin_id)) {
                            if (ctx.api.loaded_plugins.get(handler.plugin_id)) |plugin| {
                                target_ctx = &plugin.context;
                            } else {
                                continue;
                            }
                        }

                        const previous_keystroke = target_ctx.current_keystroke;
                        target_ctx.current_keystroke = .{
                            .combination = handler.key_combination,
                            .mode = handler.mode,
                        };
                        defer target_ctx.current_keystroke = previous_keystroke;

                        if (try handler.handler(target_ctx)) {
                            return true; // Key was handled
                        }
                    }
                }
            }
            return false; // Key not handled
        }

        pub fn unregister(self: *KeystrokeHandlers, plugin_id: []const u8) void {
            var i: usize = self.handlers.items.len;
            while (i > 0) : (i -= 1) {
                const idx = i - 1;
                if (std.mem.eql(u8, self.handlers.items[idx].plugin_id, plugin_id)) {
                    _ = self.handlers.orderedRemove(idx);
                }
            }
        }
    };

    pub const PluginContext = struct {
        plugin_id: []const u8,
        api: *PluginAPI,
        scratch_allocator: std.mem.Allocator,
        user_data: ?*anyopaque = null,
        current_command: ?[]const u8 = null,
        current_keystroke: ?KeystrokeInvocation = null,
        current_event: ?EventType = null,

        pub const KeystrokeInvocation = struct {
            combination: []const u8,
            mode: ?EditorContext.EditorMode,
        };

        // Editor operations
        pub fn getCurrentBuffer(self: *PluginContext) !BufferId {
            if (self.api.editor_context.bridge) |bridge| {
                return bridge.getCurrentBuffer(bridge.ctx);
            }
            return self.api.editor_context.active_buffer_id;
        }

        pub fn getBufferContent(self: *PluginContext, buffer_id: BufferId) ![]const u8 {
            try self.ensureFallbackBuffer(buffer_id);

            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.getBufferContent) |func| {
                    return try func(bridge.ctx, self.scratch_allocator, buffer_id);
                }
            }

            const rope = self.api.editor_context.rope;
            return try rope.copyRangeAlloc(self.scratch_allocator, .{ .start = 0, .end = rope.len() });
        }

        pub fn setBufferContent(self: *PluginContext, buffer_id: BufferId, content: []const u8) !void {
            try self.ensureFallbackBuffer(buffer_id);

            const rope = self.api.editor_context.rope;
            const previous_len = rope.len();

            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.setBufferContent) |func| {
                    try func(bridge.ctx, buffer_id, content);
                } else {
                    try self.setBufferContentFallback(content);
                }
            } else {
                try self.setBufferContentFallback(content);
            }

            const change = EditorContext.BufferChange{
                .buffer_id = buffer_id,
                .range = .{ .start = 0, .end = previous_len },
                .inserted_len = content.len,
                .kind = .replace,
            };
            self.notifyBufferChange(change);

            if (previous_len > 0) {
                try self.emitTextDeleted(buffer_id, 0, previous_len);
            }
            if (content.len > 0) {
                try self.emitTextInserted(buffer_id, 0, content);
            }

            self.recomputeCursorFromOffset();
        }

        pub fn getBufferLine(self: *PluginContext, buffer_id: BufferId, line_num: usize) ![]const u8 {
            try self.ensureFallbackBuffer(buffer_id);

            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.getBufferLine) |func| {
                    return try func(bridge.ctx, self.scratch_allocator, buffer_id, line_num);
                }
            }

            return try self.api.editor_context.rope.lineSliceAlloc(self.scratch_allocator, line_num);
        }

        pub fn insertText(self: *PluginContext, buffer_id: BufferId, position: usize, text: []const u8) !void {
            if (text.len == 0) return;
            try self.ensureFallbackBuffer(buffer_id);

            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.insertText) |func| {
                    try func(bridge.ctx, buffer_id, position, text);
                } else {
                    try self.insertTextFallback(position, text);
                }
            } else {
                try self.insertTextFallback(position, text);
            }

            self.adjustStateForInsert(position, text.len);
            self.notifyBufferChange(.{
                .buffer_id = buffer_id,
                .range = .{ .start = position, .end = position },
                .inserted_len = text.len,
                .kind = .insert,
            });
            try self.emitTextInserted(buffer_id, position, text);
        }

        pub fn deleteRange(self: *PluginContext, buffer_id: BufferId, range: core.Rope.Range) !void {
            if (range.len() == 0) return;
            try self.ensureFallbackBuffer(buffer_id);

            if (range.end > self.api.editor_context.rope.len()) {
                return BufferError.InvalidBuffer;
            }

            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.deleteRange) |func| {
                    try func(bridge.ctx, buffer_id, range);
                } else {
                    try self.deleteRangeFallback(range);
                }
            } else {
                try self.deleteRangeFallback(range);
            }

            self.adjustStateForDelete(range.start, range.end);
            self.notifyBufferChange(.{
                .buffer_id = buffer_id,
                .range = range,
                .inserted_len = 0,
                .kind = .delete,
            });
            try self.emitTextDeleted(buffer_id, range.start, range.len());
        }

        pub fn replaceRange(self: *PluginContext, buffer_id: BufferId, range: core.Rope.Range, text: []const u8) !void {
            try self.deleteRange(buffer_id, range);
            try self.insertText(buffer_id, range.start, text);
        }

        pub fn getSelectionRange(self: *PluginContext) ?EditorContext.SelectionRange {
            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.getSelection) |func| {
                    return func(bridge.ctx);
                }
            }

            if (self.api.editor_context.selection_start) |start_ptr| {
                if (self.api.editor_context.selection_end) |end_ptr| {
                    if (start_ptr.*) |start| {
                        if (end_ptr.*) |end| {
                            return .{ .start = start, .end = end };
                        }
                    }
                }
            }
            return null;
        }

        pub fn setSelectionRange(self: *PluginContext, selection: ?EditorContext.SelectionRange) !void {
            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.setSelection) |func| {
                    try func(bridge.ctx, selection);
                }
            }

            if (self.api.editor_context.selection_start) |start_ptr| {
                if (self.api.editor_context.selection_end) |end_ptr| {
                    if (selection) |sel| {
                        const normalized_start = @min(sel.start, sel.end);
                        const normalized_end = @max(sel.start, sel.end);
                        start_ptr.* = normalized_start;
                        end_ptr.* = normalized_end;
                    } else {
                        start_ptr.* = null;
                        end_ptr.* = null;
                    }
                }
            }
        }

        pub fn clearSelection(self: *PluginContext) !void {
            try self.setSelectionRange(null);
        }

        pub fn getCursorPosition(self: *PluginContext) EditorContext.CursorPosition {
            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.getCursorPosition) |func| {
                    return func(bridge.ctx);
                }
            }
            return self.api.editor_context.cursor_position.*;
        }

        pub fn setCursorPosition(self: *PluginContext, position: EditorContext.CursorPosition) !void {
            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.setCursorPosition) |func| {
                    try func(bridge.ctx, position);
                }
            }

            var clamped = position;
            const rope_len = self.api.editor_context.rope.len();
            if (clamped.byte_offset > rope_len) clamped.byte_offset = rope_len;
            self.api.editor_context.cursor_position.* = clamped;
            self.recomputeCursorFromOffset();
        }

        pub fn getCurrentMode(self: *PluginContext) EditorContext.EditorMode {
            return self.api.editor_context.current_mode.*;
        }

        pub fn setMode(self: *PluginContext, mode: EditorContext.EditorMode) !void {
            const old_mode = self.api.editor_context.current_mode.*;
            self.api.editor_context.current_mode.* = mode;

            // Emit mode change event
            try self.api.event_handlers.emit(self, .mode_changed, .{ .mode_changed = .{ .old_mode = old_mode, .new_mode = mode } });
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

        pub fn setUserData(self: *PluginContext, ptr: ?*anyopaque) void {
            self.user_data = ptr;
        }

        pub fn userData(self: *PluginContext) ?*anyopaque {
            return self.user_data;
        }

        pub fn currentCommand(self: *PluginContext) ?[]const u8 {
            return self.current_command;
        }

        pub fn currentKeystroke(self: *PluginContext) ?KeystrokeInvocation {
            return self.current_keystroke;
        }

        pub fn currentEvent(self: *PluginContext) ?EventType {
            return self.current_event;
        }

        fn ensureFallbackBuffer(self: *PluginContext, buffer_id: BufferId) !void {
            if (buffer_id != self.api.editor_context.active_buffer_id) {
                return BufferError.InvalidBuffer;
            }
        }

        fn setBufferContentFallback(self: *PluginContext, content: []const u8) !void {
            const rope = self.api.editor_context.rope;
            const existing_len = rope.len();
            if (existing_len > 0) {
                try rope.delete(0, existing_len);
            }
            if (content.len > 0) {
                try rope.insert(0, content);
            }
        }

        fn insertTextFallback(self: *PluginContext, position: usize, text: []const u8) !void {
            try self.api.editor_context.rope.insert(position, text);
        }

        fn deleteRangeFallback(self: *PluginContext, range: core.Rope.Range) !void {
            try self.api.editor_context.rope.delete(range.start, range.len());
        }

        fn notifyBufferChange(self: *PluginContext, change: EditorContext.BufferChange) void {
            if (self.api.editor_context.bridge) |bridge| {
                if (bridge.notifyChange) |func| {
                    func(bridge.ctx, change) catch |err| {
                        std.log.err("Buffer change notification failed: {}", .{err});
                    };
                }
            }
        }

        fn adjustStateForInsert(self: *PluginContext, position: usize, len: usize) void {
            var cursor = &self.api.editor_context.cursor_position.*;
            if (cursor.byte_offset >= position) {
                cursor.byte_offset += len;
            }

            if (self.api.editor_context.selection_start) |start_ptr| {
                if (start_ptr.*) |start| {
                    if (start >= position) start_ptr.* = start + len;
                }
            }

            if (self.api.editor_context.selection_end) |end_ptr| {
                if (end_ptr.*) |end| {
                    if (end >= position) end_ptr.* = end + len;
                }
            }

            self.recomputeCursorFromOffset();
        }

        fn adjustStateForDelete(self: *PluginContext, start: usize, end: usize) void {
            const removed_len = end - start;
            var cursor = &self.api.editor_context.cursor_position.*;
            if (cursor.byte_offset > end) {
                cursor.byte_offset -= removed_len;
            } else if (cursor.byte_offset > start) {
                cursor.byte_offset = start;
            }

            if (self.api.editor_context.selection_start) |start_ptr| {
                if (start_ptr.*) |sel_start| {
                    if (sel_start >= end) {
                        start_ptr.* = sel_start - removed_len;
                    } else if (sel_start > start) {
                        start_ptr.* = start;
                    }
                }
            }

            if (self.api.editor_context.selection_end) |end_ptr| {
                if (end_ptr.*) |sel_end| {
                    if (sel_end >= end) {
                        end_ptr.* = sel_end - removed_len;
                    } else if (sel_end > start) {
                        end_ptr.* = start;
                    }
                }
            }

            self.recomputeCursorFromOffset();
        }

        fn recomputeCursorFromOffset(self: *PluginContext) void {
            const rope = self.api.editor_context.rope;
            const cursor = self.api.editor_context.cursor_position;
            const lc = rope.lineColumnAtOffset(cursor.byte_offset) catch |err| {
                std.log.err("Failed to recompute cursor line/column: {}", .{err});
                return;
            };
            cursor.line = lc.line;
            cursor.column = lc.column;
        }

        fn emitTextInserted(self: *PluginContext, buffer_id: BufferId, position: usize, text: []const u8) !void {
            try self.api.event_handlers.emit(self, .text_inserted, .{
                .text_inserted = .{ .buffer_id = buffer_id, .position = position, .text = text },
            });
        }

        fn emitTextDeleted(self: *PluginContext, buffer_id: BufferId, position: usize, len: usize) !void {
            try self.api.event_handlers.emit(self, .text_deleted, .{
                .text_deleted = .{ .buffer_id = buffer_id, .position = position, .length = len },
            });
        }
    };

    pub const Plugin = struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
        author: []const u8,
        description: []const u8,
        context: PluginContext,
        user_data: ?*anyopaque = null,

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
            .user_data = null,
            .current_command = null,
            .current_keystroke = null,
            .current_event = null,
        };
        if (plugin.user_data) |ptr| {
            plugin.context.setUserData(ptr);
        }

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

        self.unregisterPluginResources(plugin_id);

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
            .user_data = null,
            .current_command = null,
            .current_keystroke = null,
            .current_event = null,
        };
        try self.event_handlers.emit(&temp_context, event_type, data);
    }

    pub fn handleKeystroke(self: *PluginAPI, key_combination: []const u8, mode: EditorContext.EditorMode) !bool {
        var temp_context = PluginContext{
            .plugin_id = "system",
            .api = self,
            .scratch_allocator = self.allocator,
            .user_data = null,
            .current_command = null,
            .current_keystroke = null,
            .current_event = null,
        };
        return try self.keystroke_handlers.handle(&temp_context, key_combination, mode);
    }

    pub fn listCommands(self: *PluginAPI, allocator: std.mem.Allocator) ![]Command {
        return try self.command_registry.list(allocator);
    }

    pub fn findCommand(self: *PluginAPI, name: []const u8) ?Command {
        return self.command_registry.get(name);
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

    pub fn unregisterPluginResources(self: *PluginAPI, plugin_id: []const u8) void {
        self.command_registry.unregister(self.allocator, plugin_id);
        self.event_handlers.unregister(plugin_id);
        self.keystroke_handlers.unregister(plugin_id);
    }
};

    test "PluginContext routes editor bridge callbacks" {
        const allocator = std.testing.allocator;

        var rope = try core.Rope.init(allocator);
        defer rope.deinit();
        try rope.insert(0, "hello");

        var highlighter = syntax.SyntaxHighlighter.init(allocator);
        defer highlighter.deinit();

        var cursor_storage = PluginAPI.EditorContext.CursorPosition{
            .line = 0,
            .column = 0,
            .byte_offset = 0,
        };
        var mode_storage = PluginAPI.EditorContext.EditorMode.normal;
        var selection_start_opt: ?usize = null;
        var selection_end_opt: ?usize = null;

        const TestBridge = struct {
            current_buffer: PluginAPI.BufferId,
            get_buffer_calls: usize = 0,
            get_cursor_calls: usize = 0,
            set_cursor_calls: usize = 0,
            get_selection_calls: usize = 0,
            set_selection_calls: usize = 0,
            set_selection_null_calls: usize = 0,
            notify_calls: usize = 0,
            cursor_to_return: PluginAPI.EditorContext.CursorPosition,
            selection_to_return: ?PluginAPI.EditorContext.SelectionRange = null,
            last_set_cursor: ?PluginAPI.EditorContext.CursorPosition = null,
            last_set_selection: ?PluginAPI.EditorContext.SelectionRange = null,
            last_notify: ?PluginAPI.EditorContext.BufferChange = null,

            fn getCurrentBuffer(ctx: *anyopaque) PluginAPI.BufferId {
                const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
                self.get_buffer_calls += 1;
                return self.current_buffer;
            }

            fn getCursorPosition(ctx: *anyopaque) PluginAPI.EditorContext.CursorPosition {
                const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
                self.get_cursor_calls += 1;
                return self.cursor_to_return;
            }

            fn setCursorPosition(ctx: *anyopaque, position: PluginAPI.EditorContext.CursorPosition) anyerror!void {
                const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
                self.set_cursor_calls += 1;
                self.last_set_cursor = position;
            }

            fn getSelection(ctx: *anyopaque) ?PluginAPI.EditorContext.SelectionRange {
                const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
                self.get_selection_calls += 1;
                return self.selection_to_return;
            }

            fn setSelection(ctx: *anyopaque, selection: ?PluginAPI.EditorContext.SelectionRange) anyerror!void {
                const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
                if (selection) |sel| {
                    self.set_selection_calls += 1;
                    self.last_set_selection = sel;
                } else {
                    self.set_selection_null_calls += 1;
                    self.last_set_selection = null;
                }
            }

            fn notifyChange(ctx: *anyopaque, change: PluginAPI.EditorContext.BufferChange) anyerror!void {
                const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
                self.notify_calls += 1;
                self.last_notify = change;
            }
        };

        var bridge_state = TestBridge{
            .current_buffer = 1,
            .cursor_to_return = .{ .line = 2, .column = 3, .byte_offset = 4 },
            .selection_to_return = .{ .start = 1, .end = 3 },
        };

        var editor_context = PluginAPI.EditorContext{
            .rope = &rope,
            .cursor_position = &cursor_storage,
            .current_mode = &mode_storage,
            .highlighter = &highlighter,
            .selection_start = &selection_start_opt,
            .selection_end = &selection_end_opt,
            .active_buffer_id = 1,
            .bridge = .{
                .ctx = @as(*anyopaque, @ptrCast(&bridge_state)),
                .getCurrentBuffer = TestBridge.getCurrentBuffer,
                .getCursorPosition = TestBridge.getCursorPosition,
                .setCursorPosition = TestBridge.setCursorPosition,
                .getSelection = TestBridge.getSelection,
                .setSelection = TestBridge.setSelection,
                .notifyChange = TestBridge.notifyChange,
            },
        };

        var plugin_api = PluginAPI.init(allocator, &editor_context);
        defer plugin_api.deinit();

        var plugin_context = PluginAPI.PluginContext{
            .plugin_id = "test",
            .api = &plugin_api,
            .scratch_allocator = allocator,
            .user_data = null,
            .current_command = null,
            .current_keystroke = null,
            .current_event = null,
        };

        const buffer_id = try plugin_context.getCurrentBuffer();
        try std.testing.expectEqual(@as(PluginAPI.BufferId, 1), buffer_id);
        try std.testing.expectEqual(@as(usize, 1), bridge_state.get_buffer_calls);

        const cursor_from_bridge = plugin_context.getCursorPosition();
        try std.testing.expectEqual(bridge_state.cursor_to_return, cursor_from_bridge);
        try std.testing.expectEqual(@as(usize, 1), bridge_state.get_cursor_calls);

        try plugin_context.setCursorPosition(.{ .line = 10, .column = 0, .byte_offset = 999 });
        try std.testing.expectEqual(@as(usize, 1), bridge_state.set_cursor_calls);
        try std.testing.expectEqual(@as(usize, rope.len()), editor_context.cursor_position.byte_offset);
        try std.testing.expectEqual(@as(usize, 999), bridge_state.last_set_cursor.?.byte_offset);

        try plugin_context.setSelectionRange(.{ .start = 20, .end = 5 });
        try std.testing.expectEqual(@as(usize, 1), bridge_state.set_selection_calls);
        try std.testing.expectEqual(@as(usize, rope.len()), selection_start_opt.?);
        try std.testing.expectEqual(@as(usize, rope.len()), selection_end_opt.?);
        try std.testing.expectEqual(@as(usize, rope.len()), bridge_state.last_set_selection.?.start);
        try std.testing.expectEqual(@as(usize, rope.len()), bridge_state.last_set_selection.?.end);

        bridge_state.selection_to_return = .{ .start = 2, .end = 4 };
        const selection_from_bridge = plugin_context.getSelectionRange().?;
        try std.testing.expectEqual(bridge_state.selection_to_return.?, selection_from_bridge);
        try std.testing.expectEqual(@as(usize, 1), bridge_state.get_selection_calls);

        try plugin_context.clearSelection();
        try std.testing.expect(selection_start_opt == null);
        try std.testing.expect(selection_end_opt == null);
        try std.testing.expectEqual(@as(usize, 1), bridge_state.set_selection_null_calls);

        const text = "abc";
        try plugin_context.insertText(1, 0, text);
        try std.testing.expectEqual(@as(usize, 1), bridge_state.notify_calls);
        try std.testing.expectEqual(PluginAPI.EditorContext.BufferChangeKind.insert, bridge_state.last_notify.?.kind);
        try std.testing.expectEqual(@as(usize, text.len), bridge_state.last_notify.?.inserted_len);
        try std.testing.expectEqual(@as(usize, 0), bridge_state.last_notify.?.range.start);
        try std.testing.expectEqual(@as(usize, 0), bridge_state.last_notify.?.range.end - bridge_state.last_notify.?.range.start);
        try std.testing.expectEqual(@as(usize, rope.len()), editor_context.cursor_position.byte_offset);
        try std.testing.expectEqual(@as(usize, 1), bridge_state.last_notify.?.buffer_id);
    }

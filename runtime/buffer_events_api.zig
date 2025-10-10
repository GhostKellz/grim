const std = @import("std");
const core = @import("core");

/// Buffer Change Events API
/// Provides granular buffer lifecycle and text change events with payloads
pub const BufferEventsAPI = struct {
    allocator: std.mem.Allocator,
    listeners: std.EnumArray(BufferEventType, std.ArrayList(EventListener)),

    pub const BufferEventType = enum {
        // Buffer lifecycle events
        buf_new, // New buffer created
        buf_read_pre, // Before reading file into buffer
        buf_read_post, // After reading file into buffer
        buf_write_pre, // Before writing buffer to file
        buf_write_post, // After writing buffer to file
        buf_enter, // After entering a buffer
        buf_leave, // Before leaving a buffer
        buf_delete, // Before deleting a buffer
        buf_wipe_out, // Before wiping out a buffer

        // Text change events
        text_changed, // Text changed in normal mode
        text_changed_i, // Text changed in insert mode
        text_changed_p, // Text changed in replace mode
        text_yank_post, // After yanking text

        // Insert mode events
        insert_enter, // Entering insert mode
        insert_leave, // Leaving insert mode
        insert_leave_pre, // Before leaving insert mode
        insert_char_pre, // Before inserting a character

        // Cursor events
        cursor_moved, // Cursor moved in normal mode
        cursor_moved_i, // Cursor moved in insert mode
        cursor_hold, // Cursor held for updatetime

        // Completion events
        complete_done, // Completion finished
        complete_changed, // Completion selection changed

        // Window events
        win_enter, // After entering window
        win_leave, // Before leaving window
        win_new, // After creating window
        win_closed, // After closing window
        win_resized, // After window resize

        // Mode events
        mode_changed, // After mode changed

        // Custom events
        user, // User-defined custom events
    };

    pub const TextChangePayload = struct {
        buffer_id: u32,
        range: core.Range,
        old_text: []const u8,
        new_text: []const u8,
        change_tick: u64,
    };

    pub const CursorMovePayload = struct {
        buffer_id: u32,
        old_line: usize,
        old_column: usize,
        new_line: usize,
        new_column: usize,
    };

    pub const ModeChangePayload = struct {
        old_mode: EditorMode,
        new_mode: EditorMode,
    };

    pub const BufferLifecyclePayload = struct {
        buffer_id: u32,
        file_path: ?[]const u8,
        buffer_type: BufferType,
    };

    pub const InsertCharPayload = struct {
        buffer_id: u32,
        char: u8,
        position: usize,
    };

    pub const YankPayload = struct {
        buffer_id: u32,
        range: core.Range,
        text: []const u8,
        register: u8,
    };

    pub const CompletionPayload = struct {
        buffer_id: u32,
        selected_item: ?[]const u8,
        items_count: usize,
    };

    pub const WindowPayload = struct {
        window_id: u32,
        buffer_id: u32,
        width: usize,
        height: usize,
    };

    pub const UserEventPayload = struct {
        event_name: []const u8,
        data: ?*anyopaque,
    };

    pub const EditorMode = enum {
        normal,
        insert,
        visual,
        visual_line,
        visual_block,
        command,
        replace,
        terminal,
    };

    pub const BufferType = enum {
        normal,
        help,
        quickfix,
        terminal,
        prompt,
        popup,
    };

    pub const EventPayload = union(BufferEventType) {
        buf_new: BufferLifecyclePayload,
        buf_read_pre: BufferLifecyclePayload,
        buf_read_post: BufferLifecyclePayload,
        buf_write_pre: BufferLifecyclePayload,
        buf_write_post: BufferLifecyclePayload,
        buf_enter: BufferLifecyclePayload,
        buf_leave: BufferLifecyclePayload,
        buf_delete: BufferLifecyclePayload,
        buf_wipe_out: BufferLifecyclePayload,

        text_changed: TextChangePayload,
        text_changed_i: TextChangePayload,
        text_changed_p: TextChangePayload,
        text_yank_post: YankPayload,

        insert_enter: BufferLifecyclePayload,
        insert_leave: BufferLifecyclePayload,
        insert_leave_pre: BufferLifecyclePayload,
        insert_char_pre: InsertCharPayload,

        cursor_moved: CursorMovePayload,
        cursor_moved_i: CursorMovePayload,
        cursor_hold: CursorMovePayload,

        complete_done: CompletionPayload,
        complete_changed: CompletionPayload,

        win_enter: WindowPayload,
        win_leave: WindowPayload,
        win_new: WindowPayload,
        win_closed: WindowPayload,
        win_resized: WindowPayload,

        mode_changed: ModeChangePayload,

        user: UserEventPayload,
    };

    pub const EventListener = struct {
        handler: *const fn (payload: EventPayload) anyerror!void,
        plugin_id: []const u8,
        once: bool = false, // Fire only once
        priority: i32 = 0, // Higher priority = earlier execution
    };

    pub const ChangeTick = struct {
        tick: u64 = 0,

        pub fn increment(self: *ChangeTick) u64 {
            self.tick += 1;
            return self.tick;
        }

        pub fn get(self: *const ChangeTick) u64 {
            return self.tick;
        }
    };

    pub fn init(allocator: std.mem.Allocator) BufferEventsAPI {
        var listeners = std.EnumArray(BufferEventType, std.ArrayList(EventListener)).initUndefined();
        for (std.meta.tags(BufferEventType)) |event_type| {
            listeners.set(event_type, std.ArrayList(EventListener).init(allocator));
        }

        return .{
            .allocator = allocator,
            .listeners = listeners,
        };
    }

    pub fn deinit(self: *BufferEventsAPI) void {
        for (std.meta.tags(BufferEventType)) |event_type| {
            self.listeners.getPtr(event_type).deinit();
        }
    }

    /// Register an event listener
    pub fn on(
        self: *BufferEventsAPI,
        event_type: BufferEventType,
        plugin_id: []const u8,
        handler: *const fn (payload: EventPayload) anyerror!void,
        priority: i32,
    ) !void {
        const listener = EventListener{
            .handler = handler,
            .plugin_id = plugin_id,
            .priority = priority,
        };

        const list = self.listeners.getPtr(event_type);
        try list.append(listener);

        // Sort by priority (descending)
        std.mem.sort(EventListener, list.items, {}, struct {
            fn lessThan(_: void, a: EventListener, b: EventListener) bool {
                return a.priority > b.priority;
            }
        }.lessThan);
    }

    /// Register a one-time event listener
    pub fn once(
        self: *BufferEventsAPI,
        event_type: BufferEventType,
        plugin_id: []const u8,
        handler: *const fn (payload: EventPayload) anyerror!void,
    ) !void {
        const listener = EventListener{
            .handler = handler,
            .plugin_id = plugin_id,
            .once = true,
            .priority = 0,
        };

        try self.listeners.getPtr(event_type).append(listener);
    }

    /// Emit an event
    pub fn emit(self: *BufferEventsAPI, event_type: BufferEventType, payload: EventPayload) !void {
        const list = self.listeners.getPtr(event_type);

        var i: usize = 0;
        while (i < list.items.len) {
            const listener = list.items[i];

            listener.handler(payload) catch |err| {
                std.log.err("Event handler error in plugin {s}: {}", .{ listener.plugin_id, err });
            };

            // Remove one-time listeners
            if (listener.once) {
                _ = list.orderedRemove(i);
                continue;
            }

            i += 1;
        }
    }

    /// Remove all listeners for a plugin
    pub fn removePlugin(self: *BufferEventsAPI, plugin_id: []const u8) void {
        for (std.meta.tags(BufferEventType)) |event_type| {
            const list = self.listeners.getPtr(event_type);
            var i: usize = list.items.len;
            while (i > 0) : (i -= 1) {
                const idx = i - 1;
                if (std.mem.eql(u8, list.items[idx].plugin_id, plugin_id)) {
                    _ = list.orderedRemove(idx);
                }
            }
        }
    }

    /// Remove a specific event listener
    pub fn off(
        self: *BufferEventsAPI,
        event_type: BufferEventType,
        plugin_id: []const u8,
    ) void {
        const list = self.listeners.getPtr(event_type);
        var i: usize = list.items.len;
        while (i > 0) : (i -= 1) {
            const idx = i - 1;
            if (std.mem.eql(u8, list.items[idx].plugin_id, plugin_id)) {
                _ = list.orderedRemove(idx);
            }
        }
    }

    /// Get listener count for an event type
    pub fn listenerCount(self: *const BufferEventsAPI, event_type: BufferEventType) usize {
        return self.listeners.get(event_type).items.len;
    }

    /// Check if any listeners are registered for an event
    pub fn hasListeners(self: *const BufferEventsAPI, event_type: BufferEventType) bool {
        return self.listenerCount(event_type) > 0;
    }
};

test "BufferEventsAPI basic events" {
    const allocator = std.testing.allocator;
    var api = BufferEventsAPI.init(allocator);
    defer api.deinit();

    const TestCtx = struct {
        var fired: bool = false;
        var payload_received: ?BufferEventsAPI.EventPayload = null;

        fn handler(payload: BufferEventsAPI.EventPayload) !void {
            fired = true;
            payload_received = payload;
        }
    };

    try api.on(.text_changed, "test_plugin", TestCtx.handler, 0);

    const payload = BufferEventsAPI.EventPayload{
        .text_changed = .{
            .buffer_id = 1,
            .range = .{ .start = 0, .end = 5 },
            .old_text = "hello",
            .new_text = "world",
            .change_tick = 1,
        },
    };

    try api.emit(.text_changed, payload);

    try std.testing.expect(TestCtx.fired);
    try std.testing.expectEqual(@as(u32, 1), TestCtx.payload_received.?.text_changed.buffer_id);
}

test "BufferEventsAPI priority ordering" {
    const allocator = std.testing.allocator;
    var api = BufferEventsAPI.init(allocator);
    defer api.deinit();

    const TestCtx = struct {
        var execution_order: std.ArrayList(i32) = undefined;

        fn init_list(alloc: std.mem.Allocator) void {
            execution_order = std.ArrayList(i32).init(alloc);
        }

        fn deinit_list() void {
            execution_order.deinit();
        }

        fn handlerHigh(payload: BufferEventsAPI.EventPayload) !void {
            _ = payload;
            try execution_order.append(100);
        }

        fn handlerMedium(payload: BufferEventsAPI.EventPayload) !void {
            _ = payload;
            try execution_order.append(50);
        }

        fn handlerLow(payload: BufferEventsAPI.EventPayload) !void {
            _ = payload;
            try execution_order.append(10);
        }
    };

    TestCtx.init_list(allocator);
    defer TestCtx.deinit_list();

    try api.on(.buf_enter, "plugin1", TestCtx.handlerLow, 10);
    try api.on(.buf_enter, "plugin2", TestCtx.handlerHigh, 100);
    try api.on(.buf_enter, "plugin3", TestCtx.handlerMedium, 50);

    const payload = BufferEventsAPI.EventPayload{
        .buf_enter = .{
            .buffer_id = 1,
            .file_path = null,
            .buffer_type = .normal,
        },
    };

    try api.emit(.buf_enter, payload);

    try std.testing.expectEqual(@as(usize, 3), TestCtx.execution_order.items.len);
    try std.testing.expectEqual(@as(i32, 100), TestCtx.execution_order.items[0]);
    try std.testing.expectEqual(@as(i32, 50), TestCtx.execution_order.items[1]);
    try std.testing.expectEqual(@as(i32, 10), TestCtx.execution_order.items[2]);
}

test "BufferEventsAPI once listener" {
    const allocator = std.testing.allocator;
    var api = BufferEventsAPI.init(allocator);
    defer api.deinit();

    const TestCtx = struct {
        var fire_count: usize = 0;

        fn handler(payload: BufferEventsAPI.EventPayload) !void {
            _ = payload;
            fire_count += 1;
        }
    };

    try api.once(.cursor_moved, "test_plugin", TestCtx.handler);

    const payload = BufferEventsAPI.EventPayload{
        .cursor_moved = .{
            .buffer_id = 1,
            .old_line = 0,
            .old_column = 0,
            .new_line = 1,
            .new_column = 5,
        },
    };

    try api.emit(.cursor_moved, payload);
    try api.emit(.cursor_moved, payload);
    try api.emit(.cursor_moved, payload);

    try std.testing.expectEqual(@as(usize, 1), TestCtx.fire_count);
    try std.testing.expectEqual(@as(usize, 0), api.listenerCount(.cursor_moved));
}

test "BufferEventsAPI remove plugin" {
    const allocator = std.testing.allocator;
    var api = BufferEventsAPI.init(allocator);
    defer api.deinit();

    const TestCtx = struct {
        fn handler(payload: BufferEventsAPI.EventPayload) !void {
            _ = payload;
        }
    };

    try api.on(.text_changed, "plugin1", TestCtx.handler, 0);
    try api.on(.buf_enter, "plugin1", TestCtx.handler, 0);
    try api.on(.text_changed, "plugin2", TestCtx.handler, 0);

    try std.testing.expectEqual(@as(usize, 2), api.listenerCount(.text_changed));
    try std.testing.expectEqual(@as(usize, 1), api.listenerCount(.buf_enter));

    api.removePlugin("plugin1");

    try std.testing.expectEqual(@as(usize, 1), api.listenerCount(.text_changed));
    try std.testing.expectEqual(@as(usize, 0), api.listenerCount(.buf_enter));
}

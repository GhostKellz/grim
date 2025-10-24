//! core/event_system.zig
//! Stores plugin-provided event handlers registered via grim.host callbacks.

const std = @import("std");
const grim = @import("grim");

const Host = grim.host.Host;

pub const EventSystem = struct {
    allocator: std.mem.Allocator,
    handlers: std.StringHashMap(EventList),

    pub const EventList = struct {
        name: []const u8,
        actions: std.ArrayListUnmanaged(Host.EventAction),
    };

    pub fn init(allocator: std.mem.Allocator) EventSystem {
        return EventSystem{
            .allocator = allocator,
            .handlers = std.StringHashMap(EventList).init(allocator),
        };
    }

    pub fn deinit(self: *EventSystem) void {
        var it = self.handlers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.actions.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.handlers.deinit();
    }

    pub fn register(self: *EventSystem, action: *const Host.EventAction) !void {
        if (action.event.len == 0) return error.InvalidEventName;

        const key = try self.allocator.dupe(u8, action.event);
        errdefer self.allocator.free(key);

        const gop = try self.handlers.getOrPut(key);
        if (!gop.found_existing) {
            gop.key_ptr.* = key;
            gop.value_ptr.* = EventList{
                .name = gop.key_ptr.*,
                .actions = std.ArrayListUnmanaged(Host.EventAction){},
            };
        } else {
            self.allocator.free(key);
        }

        try gop.value_ptr.actions.append(self.allocator, action.*);
    }

    pub fn handlersFor(self: *EventSystem, event_name: []const u8) ?*EventList {
        return if (self.handlers.getPtr(event_name)) |list|
            list
        else
            null;
    }
};

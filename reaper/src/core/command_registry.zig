//! core/command_registry.zig
//! Stores plugin-registered commands exposed through grim.host callbacks.

const std = @import("std");
const grim = @import("grim");

const Host = grim.host.Host;

pub const CommandRegistry = struct {
    allocator: std.mem.Allocator,
    commands: std.StringHashMap(CommandEntry),

    pub const CommandEntry = struct {
        name: []const u8,
        action: Host.CommandAction,
    };

    pub fn init(allocator: std.mem.Allocator) CommandRegistry {
        return CommandRegistry{
            .allocator = allocator,
            .commands = std.StringHashMap(CommandEntry).init(allocator),
        };
    }

    pub fn deinit(self: *CommandRegistry) void {
        var it = self.commands.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.commands.deinit();
    }

    pub fn clear(self: *CommandRegistry) void {
        var it = self.commands.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.commands.clearRetainingCapacity();
    }

    pub fn register(self: *CommandRegistry, action: *const Host.CommandAction) !void {
        if (action.name.len == 0) return error.InvalidCommandName;

        const key = try self.allocator.dupe(u8, action.name);
        errdefer self.allocator.free(key);

        const gop = try self.commands.getOrPut(key);
        if (gop.found_existing) {
            self.allocator.free(gop.key_ptr.*);
            gop.key_ptr.* = key;
        } else {
            gop.key_ptr.* = key;
        }

        gop.value_ptr.* = CommandEntry{
            .name = gop.key_ptr.*,
            .action = action.*, // copy
        };
    }

    pub fn get(self: *CommandRegistry, name: []const u8) ?*const CommandEntry {
        return if (self.commands.getPtr(name)) |value_ptr|
            value_ptr
        else
            null;
    }
};

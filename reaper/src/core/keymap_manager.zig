//! core/keymap_manager.zig
//! Tracks plugin-registered keymaps provided through grim.host callbacks.

const std = @import("std");
const grim = @import("grim");

const Host = grim.host.Host;

pub const KeymapManager = struct {
    allocator: std.mem.Allocator,
    keymaps: std.StringHashMap(KeymapEntry),

    pub const KeymapEntry = struct {
        mode: []const u8,
        lhs: []const u8,
        action: Host.KeymapAction,
    };

    pub fn init(allocator: std.mem.Allocator) KeymapManager {
        return KeymapManager{
            .allocator = allocator,
            .keymaps = std.StringHashMap(KeymapEntry).init(allocator),
        };
    }

    pub fn deinit(self: *KeymapManager) void {
        var it = self.keymaps.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.keymaps.deinit();
    }

    pub fn clear(self: *KeymapManager) void {
        var it = self.keymaps.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.keymaps.clearRetainingCapacity();
    }

    pub fn register(self: *KeymapManager, action: *const Host.KeymapAction) !void {
        if (action.keys.len == 0) return error.InvalidKeymap;

        const mode = action.mode orelse "";
        const keys = action.keys;
        const composite = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ mode, keys });
        errdefer self.allocator.free(composite);

        const gop = try self.keymaps.getOrPut(composite);
        if (gop.found_existing) {
            self.allocator.free(gop.key_ptr.*);
            gop.key_ptr.* = composite;
        } else {
            gop.key_ptr.* = composite;
        }

        gop.value_ptr.* = KeymapEntry{
            .mode = mode,
            .lhs = keys,
            .action = action.*,
        };
    }
};

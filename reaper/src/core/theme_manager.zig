//! core/theme_manager.zig
//! Collects theme contributions from plugins for later application.

const std = @import("std");
const grim = @import("grim");

const Host = grim.host.Host;

pub const ThemeManager = struct {
    allocator: std.mem.Allocator,
    themes: std.StringHashMap(ThemeEntry),

    pub const ThemeEntry = struct {
        name: []const u8,
        action: Host.ThemeAction,
    };

    pub fn init(allocator: std.mem.Allocator) ThemeManager {
        return ThemeManager{
            .allocator = allocator,
            .themes = std.StringHashMap(ThemeEntry).init(allocator),
        };
    }

    pub fn deinit(self: *ThemeManager) void {
        var it = self.themes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.themes.deinit();
    }

    pub fn clear(self: *ThemeManager) void {
        var it = self.themes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.themes.clearRetainingCapacity();
    }

    pub fn register(self: *ThemeManager, action: *const Host.ThemeAction) !void {
        if (action.name.len == 0) return error.InvalidThemeName;

        const key = try self.allocator.dupe(u8, action.name);
        errdefer self.allocator.free(key);

        const gop = try self.themes.getOrPut(key);
        if (gop.found_existing) {
            self.allocator.free(gop.key_ptr.*);
            gop.key_ptr.* = key;
        } else {
            gop.key_ptr.* = key;
        }

        gop.value_ptr.* = ThemeEntry{
            .name = gop.key_ptr.*,
            .action = action.*,
        };
    }

    pub fn get(self: *ThemeManager, name: []const u8) ?*const ThemeEntry {
        return if (self.themes.getPtr(name)) |entry|
            entry
        else
            null;
    }
};

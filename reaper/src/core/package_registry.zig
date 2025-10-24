//! core/package_registry.zig
//! Central plugin registry management

const std = @import("std");
const zsync = @import("zsync");
const zlog = @import("zlog");

pub const PackageRegistry = struct {
    allocator: std.mem.Allocator,
    registry_url: []const u8,
    cache: std.StringHashMap(PluginInfo),

    pub fn init(allocator: std.mem.Allocator, registry_url: []const u8) !PackageRegistry {
        return PackageRegistry{
            .allocator = allocator,
            .registry_url = registry_url,
            .cache = std.StringHashMap(PluginInfo).init(allocator),
        };
    }

    pub fn deinit(self: *PackageRegistry) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    /// Fetch plugin information from registry
    pub fn getPluginInfo(self: *PackageRegistry, name: []const u8) !PluginInfo {
        // Check cache first
        if (self.cache.get(name)) |info| {
            return info.clone(self.allocator);
        }

        zlog.info("Fetching plugin info for: {s}", .{name});

        // TODO: HTTP request to registry
        const url = try std.fmt.allocPrint(self.allocator, "{s}/plugins/{s}.json", .{ self.registry_url, name });
        defer self.allocator.free(url);

        // TODO: Parse JSON response
        // For now, return placeholder
        const placeholder = PluginInfo{
            .name = try self.allocator.dupe(u8, name),
            .version = try self.allocator.dupe(u8, "latest"),
            .description = try self.allocator.dupe(u8, "Plugin description"),
            .dependencies = std.ArrayList([]const u8).empty,
        };

        // Cache the result
        try self.cache.put(try self.allocator.dupe(u8, name), placeholder.clone(self.allocator));

        return placeholder;
    }
};

pub const PluginInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    dependencies: std.ArrayList([]const u8),

    pub fn deinit(self: *PluginInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.description);
        self.dependencies.deinit(allocator);
    }

    pub fn clone(self: PluginInfo, allocator: std.mem.Allocator) !PluginInfo {
        return PluginInfo{
            .name = try allocator.dupe(u8, self.name),
            .version = try allocator.dupe(u8, self.version),
            .description = try allocator.dupe(u8, self.description),
            .dependencies = try self.dependencies.clone(allocator),
        };
    }
};

//! Plugin security and sandboxing system
//! Implements policy-based permission control for plugins

const std = @import("std");

/// Security tier for plugins
pub const SecurityTier = enum {
    safe, // No file system access, no network, no process spawning
    restricted, // Limited file system (plugin dir only), no network
    unsafe, // Full system access (requires explicit user consent)

    pub fn fromString(str: []const u8) SecurityTier {
        if (std.mem.eql(u8, str, "safe")) return .safe;
        if (std.mem.eql(u8, str, "restricted")) return .restricted;
        if (std.mem.eql(u8, str, "unsafe")) return .unsafe;
        return .safe; // Default to safest
    }

    pub fn toString(self: SecurityTier) []const u8 {
        return switch (self) {
            .safe => "safe",
            .restricted => "restricted",
            .unsafe => "unsafe",
        };
    }
};

/// Permissions a plugin can request
pub const Permission = enum {
    // File system
    read_files,
    write_files,
    delete_files,
    execute_files,

    // Network
    network_access,
    http_requests,

    // System
    spawn_processes,
    system_info,
    environment_vars,

    // Editor
    modify_buffers,
    run_commands,
    register_keybindings,
    access_clipboard,

    pub fn fromString(str: []const u8) ?Permission {
        inline for (@typeInfo(Permission).Enum.fields) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

/// Plugin security policy
pub const SecurityPolicy = struct {
    tier: SecurityTier,
    permissions: std.EnumSet(Permission),
    allowed_paths: [][]const u8, // Paths plugin can access
    user_approved: bool, // Has user explicitly approved unsafe operations

    pub fn init(allocator: std.mem.Allocator, tier: SecurityTier) !SecurityPolicy {
        var permissions = std.EnumSet(Permission).initEmpty();

        // Grant permissions based on tier
        switch (tier) {
            .safe => {
                // Safe plugins can only modify buffers and register keybindings
                permissions.insert(.modify_buffers);
                permissions.insert(.register_keybindings);
            },
            .restricted => {
                // Restricted plugins get editor access + limited file system
                permissions.insert(.modify_buffers);
                permissions.insert(.run_commands);
                permissions.insert(.register_keybindings);
                permissions.insert(.access_clipboard);
                permissions.insert(.read_files);
                permissions.insert(.write_files);
                permissions.insert(.system_info);
            },
            .unsafe => {
                // Unsafe plugins get everything (but require user approval)
                permissions = std.EnumSet(Permission).initFull();
            },
        }

        return SecurityPolicy{
            .tier = tier,
            .permissions = permissions,
            .allowed_paths = try allocator.alloc([]const u8, 0),
            .user_approved = false,
        };
    }

    pub fn deinit(self: *SecurityPolicy, allocator: std.mem.Allocator) void {
        for (self.allowed_paths) |path| {
            allocator.free(path);
        }
        allocator.free(self.allowed_paths);
    }

    /// Check if plugin has a specific permission
    pub fn hasPermission(self: *const SecurityPolicy, permission: Permission) bool {
        // Unsafe tier requires user approval
        if (self.tier == .unsafe and !self.user_approved) {
            return false;
        }
        return self.permissions.contains(permission);
    }

    /// Add a path to the allowed paths list
    pub fn allowPath(self: *SecurityPolicy, allocator: std.mem.Allocator, path: []const u8) !void {
        const new_paths = try allocator.realloc(self.allowed_paths, self.allowed_paths.len + 1);
        new_paths[new_paths.len - 1] = try allocator.dupe(u8, path);
        self.allowed_paths = new_paths;
    }

    /// Check if plugin can access a specific path
    pub fn canAccessPath(self: *const SecurityPolicy, path: []const u8) bool {
        // Safe tier has no file access
        if (self.tier == .safe) return false;

        // Unsafe tier with approval can access anything
        if (self.tier == .unsafe and self.user_approved) return true;

        // Restricted tier checks allowed paths
        for (self.allowed_paths) |allowed| {
            if (std.mem.startsWith(u8, path, allowed)) {
                return true;
            }
        }

        return false;
    }

    /// Grant user approval for unsafe operations
    pub fn grantUserApproval(self: *SecurityPolicy) void {
        self.user_approved = true;
    }

    /// Revoke user approval
    pub fn revokeUserApproval(self: *SecurityPolicy) void {
        self.user_approved = false;
    }
};

/// Security manager for all plugins
pub const SecurityManager = struct {
    allocator: std.mem.Allocator,
    policies: std.StringHashMap(SecurityPolicy),
    approval_required: std.ArrayList([]const u8), // Plugins awaiting approval

    pub fn init(allocator: std.mem.Allocator) !*SecurityManager {
        const self = try allocator.create(SecurityManager);
        self.* = .{
            .allocator = allocator,
            .policies = std.StringHashMap(SecurityPolicy).init(allocator),
            .approval_required = std.ArrayList([]const u8).empty,
        };
        return self;
    }

    pub fn deinit(self: *SecurityManager) void {
        var it = self.policies.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.policies.deinit();

        for (self.approval_required.items) |name| {
            self.allocator.free(name);
        }
        self.approval_required.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Register a plugin with its security policy
    pub fn registerPlugin(self: *SecurityManager, name: []const u8, tier: SecurityTier) !void {
        const policy = try SecurityPolicy.init(self.allocator, tier);
        const key = try self.allocator.dupe(u8, name);
        try self.policies.put(key, policy);

        // If unsafe, add to approval queue
        if (tier == .unsafe) {
            try self.approval_required.append(self.allocator, try self.allocator.dupe(u8, name));
        }
    }

    /// Check if plugin has permission
    pub fn checkPermission(self: *SecurityManager, plugin_name: []const u8, permission: Permission) !bool {
        const policy = self.policies.getPtr(plugin_name) orelse return error.PluginNotRegistered;
        return policy.hasPermission(permission);
    }

    /// Check if plugin can access path
    pub fn checkPathAccess(self: *SecurityManager, plugin_name: []const u8, path: []const u8) !bool {
        const policy = self.policies.getPtr(plugin_name) orelse return error.PluginNotRegistered;
        return policy.canAccessPath(path);
    }

    /// Approve unsafe plugin
    pub fn approvePlugin(self: *SecurityManager, plugin_name: []const u8) !void {
        const policy = self.policies.getPtr(plugin_name) orelse return error.PluginNotRegistered;
        policy.grantUserApproval();

        // Remove from approval queue
        for (self.approval_required.items, 0..) |name, i| {
            if (std.mem.eql(u8, name, plugin_name)) {
                const removed = self.approval_required.swapRemove(i);
                self.allocator.free(removed);
                break;
            }
        }
    }

    /// Get list of plugins requiring approval
    pub fn getApprovalQueue(self: *SecurityManager) []const []const u8 {
        return self.approval_required.items;
    }

    /// Get policy for a plugin
    pub fn getPolicy(self: *SecurityManager, plugin_name: []const u8) ?*SecurityPolicy {
        return self.policies.getPtr(plugin_name);
    }

    /// Add allowed path for a plugin
    pub fn allowPluginPath(self: *SecurityManager, plugin_name: []const u8, path: []const u8) !void {
        const policy = self.policies.getPtr(plugin_name) orelse return error.PluginNotRegistered;
        try policy.allowPath(self.allocator, path);
    }
};

test "security tiers and permissions" {
    const allocator = std.testing.allocator;

    var manager = try SecurityManager.init(allocator);
    defer manager.deinit();

    // Register safe plugin
    try manager.registerPlugin("safe-plugin", .safe);
    try std.testing.expect(try manager.checkPermission("safe-plugin", .modify_buffers));
    try std.testing.expect(!try manager.checkPermission("safe-plugin", .read_files));

    // Register restricted plugin
    try manager.registerPlugin("restricted-plugin", .restricted);
    try std.testing.expect(try manager.checkPermission("restricted-plugin", .read_files));
    try std.testing.expect(!try manager.checkPermission("restricted-plugin", .network_access));

    // Register unsafe plugin (requires approval)
    try manager.registerPlugin("unsafe-plugin", .unsafe);
    try std.testing.expect(!try manager.checkPermission("unsafe-plugin", .spawn_processes));

    // Approve unsafe plugin
    try manager.approvePlugin("unsafe-plugin");
    try std.testing.expect(try manager.checkPermission("unsafe-plugin", .spawn_processes));
}

test "path access control" {
    const allocator = std.testing.allocator;

    var manager = try SecurityManager.init(allocator);
    defer manager.deinit();

    try manager.registerPlugin("test-plugin", .restricted);
    try manager.allowPluginPath("test-plugin", "/home/user/.config/grim/plugins/test-plugin/");

    try std.testing.expect(try manager.checkPathAccess("test-plugin", "/home/user/.config/grim/plugins/test-plugin/data.json"));
    try std.testing.expect(!try manager.checkPathAccess("test-plugin", "/etc/passwd"));
}

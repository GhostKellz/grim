//! Plugin dependency resolution system
//! Implements topological sort for correct plugin load order
//! Detects circular dependencies

const std = @import("std");

/// Plugin dependency graph node
pub const PluginNode = struct {
    name: []const u8,
    version: []const u8,
    dependencies: std.ArrayList(Dependency),

    pub const Dependency = struct {
        name: []const u8,
        version_constraint: []const u8,
    };
};

/// Dependency graph for topological sorting
pub const DependencyGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.StringHashMap(PluginNode),

    pub fn init(allocator: std.mem.Allocator) !*DependencyGraph {
        const self = try allocator.create(DependencyGraph);
        self.* = .{
            .allocator = allocator,
            .nodes = std.StringHashMap(PluginNode).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *DependencyGraph) void {
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.version);

            for (entry.value_ptr.dependencies.items) |dep| {
                self.allocator.free(dep.name);
                self.allocator.free(dep.version_constraint);
            }
            entry.value_ptr.dependencies.deinit(self.allocator);
        }
        self.nodes.deinit();
        self.allocator.destroy(self);
    }

    /// Add a plugin to the dependency graph
    pub fn addPlugin(self: *DependencyGraph, name: []const u8, version: []const u8, dependencies: []const PluginNode.Dependency) !void {
        const node_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(node_name);

        var deps = std.ArrayList(PluginNode.Dependency){};
        errdefer deps.deinit(self.allocator);

        for (dependencies) |dep| {
            try deps.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, dep.name),
                .version_constraint = try self.allocator.dupe(u8, dep.version_constraint),
            });
        }

        const node = PluginNode{
            .name = try self.allocator.dupe(u8, name),
            .version = try self.allocator.dupe(u8, version),
            .dependencies = deps,
        };

        try self.nodes.put(node_name, node);
    }

    /// Resolve dependencies and return load order using topological sort
    pub fn resolve(self: *DependencyGraph) ![]const []const u8 {
        // Kahn's algorithm for topological sort
        var in_degree = std.StringHashMap(usize).init(self.allocator);
        defer in_degree.deinit();

        // Initialize in-degree for all nodes
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            try in_degree.put(entry.key_ptr.*, 0);
        }

        // Build reverse dependency graph (who depends on me)
        var reverse_deps = std.StringHashMap(std.ArrayList([]const u8)).init(self.allocator);
        defer {
            var rev_it = reverse_deps.iterator();
            while (rev_it.next()) |entry| {
                entry.value_ptr.*.deinit(self.allocator);
            }
            reverse_deps.deinit();
        }

        // Initialize reverse deps for all nodes
        it = self.nodes.iterator();
        while (it.next()) |entry| {
            try reverse_deps.put(entry.key_ptr.*, std.ArrayList([]const u8){});
        }

        // Build reverse edges: if A depends on B, add A to B's reverse deps
        it = self.nodes.iterator();
        while (it.next()) |entry| {
            const node_name = entry.key_ptr.*;
            const node = entry.value_ptr.*;

            for (node.dependencies.items) |dep| {
                if (reverse_deps.getPtr(dep.name)) |list| {
                    try list.append(self.allocator, node_name);
                }
            }
        }

        // Calculate in-degree (number of dependencies for each node)
        it = self.nodes.iterator();
        while (it.next()) |entry| {
            const node_name = entry.key_ptr.*;
            const node = entry.value_ptr.*;
            try in_degree.put(node_name, node.dependencies.items.len);
        }

        // Queue for nodes with zero in-degree (no dependencies)
        var queue = std.ArrayList([]const u8){};
        defer queue.deinit(self.allocator);

        var degree_it = in_degree.iterator();
        while (degree_it.next()) |entry| {
            if (entry.value_ptr.* == 0) {
                try queue.append(self.allocator, entry.key_ptr.*);
            }
        }

        // Topological sort
        var result = std.ArrayList([]const u8){};
        errdefer result.deinit(self.allocator);

        while (queue.items.len > 0) {
            const current = queue.orderedRemove(0);
            try result.append(self.allocator, try self.allocator.dupe(u8, current));

            // For all nodes that depend on current, decrease their in-degree
            if (reverse_deps.get(current)) |dependents| {
                for (dependents.items) |dependent| {
                    if (in_degree.getPtr(dependent)) |degree| {
                        degree.* -= 1;
                        if (degree.* == 0) {
                            try queue.append(self.allocator, dependent);
                        }
                    }
                }
            }
        }

        // Check for circular dependencies
        if (result.items.len != self.nodes.count()) {
            // Circular dependency detected - find the cycle
            const cycle = try self.findCircularDependency();
            defer {
                for (cycle) |name| {
                    self.allocator.free(name);
                }
                self.allocator.free(cycle);
            }

            std.log.err("Circular dependency detected ({d} plugins in cycle)", .{cycle.len});
            return error.CircularDependency;
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Find circular dependency using DFS
    fn findCircularDependency(self: *DependencyGraph) ![][]const u8 {
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();

        var rec_stack = std.StringHashMap(bool).init(self.allocator);
        defer rec_stack.deinit();

        var cycle_path = std.ArrayList([]const u8){};
        errdefer {
            for (cycle_path.items) |name| {
                self.allocator.free(name);
            }
            cycle_path.deinit(self.allocator);
        }

        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            if (!(visited.get(entry.key_ptr.*) orelse false)) {
                if (try self.detectCycleDFS(entry.key_ptr.*, &visited, &rec_stack, &cycle_path)) {
                    return cycle_path.toOwnedSlice(self.allocator);
                }
            }
        }

        return cycle_path.toOwnedSlice(self.allocator);
    }

    fn detectCycleDFS(
        self: *DependencyGraph,
        node_name: []const u8,
        visited: *std.StringHashMap(bool),
        rec_stack: *std.StringHashMap(bool),
        cycle_path: *std.ArrayList([]const u8),
    ) !bool {
        try visited.put(node_name, true);
        try rec_stack.put(node_name, true);
        try cycle_path.append(self.allocator, try self.allocator.dupe(u8, node_name));

        if (self.nodes.get(node_name)) |node| {
            for (node.dependencies.items) |dep| {
                if (!self.nodes.contains(dep.name)) continue;

                if (!(visited.get(dep.name) orelse false)) {
                    if (try self.detectCycleDFS(dep.name, visited, rec_stack, cycle_path)) {
                        return true;
                    }
                } else if (rec_stack.get(dep.name) orelse false) {
                    try cycle_path.append(self.allocator, try self.allocator.dupe(u8, dep.name));
                    return true;
                }
            }
        }

        try rec_stack.put(node_name, false);
        _ = cycle_path.pop();
        return false;
    }

    /// Check version constraint (supports: "1.0.0", "^1.0.0", "~1.0.0", ">=1.0.0")
    pub fn checkVersionConstraint(version: []const u8, constraint: []const u8) bool {
        // Exact match
        if (std.mem.eql(u8, version, constraint)) return true;

        // Caret (^1.0.0 = >=1.0.0 <2.0.0)
        if (std.mem.startsWith(u8, constraint, "^")) {
            const required = constraint[1..];
            return versionCompatibleCaret(version, required);
        }

        // Tilde (~1.0.0 = >=1.0.0 <1.1.0)
        if (std.mem.startsWith(u8, constraint, "~")) {
            const required = constraint[1..];
            return versionCompatibleTilde(version, required);
        }

        // Greater than or equal
        if (std.mem.startsWith(u8, constraint, ">=")) {
            const required = constraint[2..];
            return compareVersions(version, required) >= 0;
        }

        // Greater than
        if (std.mem.startsWith(u8, constraint, ">")) {
            const required = constraint[1..];
            return compareVersions(version, required) > 0;
        }

        return false;
    }

    fn versionCompatibleCaret(version: []const u8, required: []const u8) bool {
        const ver = parseVersion(version) catch return false;
        const req = parseVersion(required) catch return false;

        // Major must match
        if (ver.major != req.major) return false;

        // Version must be >= required
        return compareVersions(version, required) >= 0;
    }

    fn versionCompatibleTilde(version: []const u8, required: []const u8) bool {
        const ver = parseVersion(version) catch return false;
        const req = parseVersion(required) catch return false;

        // Major and minor must match
        if (ver.major != req.major or ver.minor != req.minor) return false;

        // Patch must be >= required
        return ver.patch >= req.patch;
    }

    fn parseVersion(version_str: []const u8) !struct { major: u32, minor: u32, patch: u32 } {
        var parts = std.mem.splitScalar(u8, version_str, '.');

        const major = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidVersion, 10);
        const minor = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidVersion, 10);
        const patch = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidVersion, 10);

        return .{ .major = major, .minor = minor, .patch = patch };
    }

    fn compareVersions(v1: []const u8, v2: []const u8) i32 {
        const ver1 = parseVersion(v1) catch return 0;
        const ver2 = parseVersion(v2) catch return 0;

        if (ver1.major != ver2.major) {
            return if (ver1.major > ver2.major) @as(i32, 1) else -1;
        }
        if (ver1.minor != ver2.minor) {
            return if (ver1.minor > ver2.minor) @as(i32, 1) else -1;
        }
        if (ver1.patch != ver2.patch) {
            return if (ver1.patch > ver2.patch) @as(i32, 1) else -1;
        }
        return 0;
    }
};

test "dependency resolution - simple chain" {
    const allocator = std.testing.allocator;

    var graph = try DependencyGraph.init(allocator);
    defer graph.deinit();

    // A depends on B, B depends on C
    const c_deps: []const PluginNode.Dependency = &[_]PluginNode.Dependency{};
    const b_deps = &[_]PluginNode.Dependency{.{ .name = "C", .version_constraint = "1.0.0" }};
    const a_deps = &[_]PluginNode.Dependency{.{ .name = "B", .version_constraint = "1.0.0" }};

    try graph.addPlugin("C", "1.0.0", c_deps);
    try graph.addPlugin("B", "1.0.0", b_deps);
    try graph.addPlugin("A", "1.0.0", a_deps);

    const order = try graph.resolve();
    defer {
        for (order) |name| {
            allocator.free(name);
        }
        allocator.free(order);
    }

    // Order should be: C, B, A
    try std.testing.expectEqualStrings("C", order[0]);
    try std.testing.expectEqualStrings("B", order[1]);
    try std.testing.expectEqualStrings("A", order[2]);
}

test "dependency resolution - circular detection" {
    const allocator = std.testing.allocator;

    var graph = try DependencyGraph.init(allocator);
    defer graph.deinit();

    // A -> B -> C -> A (circular)
    const a_deps = &[_]PluginNode.Dependency{.{ .name = "B", .version_constraint = "1.0.0" }};
    const b_deps = &[_]PluginNode.Dependency{.{ .name = "C", .version_constraint = "1.0.0" }};
    const c_deps = &[_]PluginNode.Dependency{.{ .name = "A", .version_constraint = "1.0.0" }};

    try graph.addPlugin("A", "1.0.0", a_deps);
    try graph.addPlugin("B", "1.0.0", b_deps);
    try graph.addPlugin("C", "1.0.0", c_deps);

    const result = graph.resolve();
    try std.testing.expectError(error.CircularDependency, result);
}

test "version constraint checking" {
    // Exact match
    try std.testing.expect(DependencyGraph.checkVersionConstraint("1.0.0", "1.0.0"));

    // Caret (^1.0.0 = >=1.0.0 <2.0.0)
    try std.testing.expect(DependencyGraph.checkVersionConstraint("1.2.3", "^1.0.0"));
    try std.testing.expect(!DependencyGraph.checkVersionConstraint("2.0.0", "^1.0.0"));

    // Tilde (~1.0.0 = >=1.0.0 <1.1.0)
    try std.testing.expect(DependencyGraph.checkVersionConstraint("1.0.5", "~1.0.0"));
    try std.testing.expect(!DependencyGraph.checkVersionConstraint("1.1.0", "~1.0.0"));

    // Greater than or equal
    try std.testing.expect(DependencyGraph.checkVersionConstraint("1.5.0", ">=1.0.0"));
    try std.testing.expect(DependencyGraph.checkVersionConstraint("1.0.0", ">=1.0.0"));
}

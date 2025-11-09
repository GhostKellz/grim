//! Lockfile system for gpkg - ensures reproducible plugin installations
//! Format: grim.lock.zon with SHA-256 hashes and dependency tree

const std = @import("std");

/// Lockfile format version
pub const LOCKFILE_VERSION = "1";

/// Entry in the lockfile for a single plugin
pub const LockEntry = struct {
    /// Plugin name
    name: []const u8,

    /// Plugin version (semver)
    version: []const u8,

    /// SHA-256 hash of the plugin directory (hex encoded)
    hash: [64]u8,

    /// Source URL or path
    source: []const u8,

    /// Plugin type: zig, ghostlang, hybrid
    type: []const u8,

    /// Direct dependencies (plugin names)
    dependencies: []const []const u8,

    /// Timestamp of last update (Unix timestamp)
    updated_at: i64,
};

/// Complete lockfile structure
pub const Lockfile = struct {
    allocator: std.mem.Allocator,

    /// Format version
    version: []const u8,

    /// All locked plugins
    plugins: std.StringHashMap(LockEntry),

    /// Global dependency tree (for cycle detection)
    dependency_graph: std.StringHashMap(std.ArrayList([]const u8)),

    pub fn init(allocator: std.mem.Allocator) !*Lockfile {
        const self = try allocator.create(Lockfile);
        self.* = .{
            .allocator = allocator,
            .version = LOCKFILE_VERSION,
            .plugins = std.StringHashMap(LockEntry).init(allocator),
            .dependency_graph = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Lockfile) void {
        // Free plugin entries
        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.version);
            self.allocator.free(entry.value_ptr.source);
            self.allocator.free(entry.value_ptr.type);

            for (entry.value_ptr.dependencies) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(entry.value_ptr.dependencies);
        }
        self.plugins.deinit();

        // Free dependency graph
        var graph_it = self.dependency_graph.iterator();
        while (graph_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |dep| {
                self.allocator.free(dep);
            }
            entry.value_ptr.deinit(self.allocator);
        }
        self.dependency_graph.deinit();

        self.allocator.destroy(self);
    }

    /// Add a plugin to the lockfile
    pub fn addPlugin(
        self: *Lockfile,
        name: []const u8,
        version: []const u8,
        hash: [64]u8,
        source: []const u8,
        plugin_type: []const u8,
        dependencies: []const []const u8,
    ) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        // Copy dependencies
        var owned_deps = try self.allocator.alloc([]const u8, dependencies.len);
        errdefer self.allocator.free(owned_deps);

        for (dependencies, 0..) |dep, i| {
            owned_deps[i] = try self.allocator.dupe(u8, dep);
        }

        const entry = LockEntry{
            .name = try self.allocator.dupe(u8, name),
            .version = try self.allocator.dupe(u8, version),
            .hash = hash,
            .source = try self.allocator.dupe(u8, source),
            .type = try self.allocator.dupe(u8, plugin_type),
            .dependencies = owned_deps,
            .updated_at = blk: {
                const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch {
                    break :blk @as(i64, 0);
                };
                break :blk @as(i64, @intCast(ts.sec)) * 1000 + @divFloor(ts.nsec, 1_000_000);
            },
        };

        try self.plugins.put(owned_name, entry);

        // Update dependency graph
        var dep_list = std.ArrayList([]const u8){};
        for (dependencies) |dep| {
            try dep_list.append(self.allocator, try self.allocator.dupe(u8, dep));
        }

        const graph_key = try self.allocator.dupe(u8, name);
        try self.dependency_graph.put(graph_key, dep_list);
    }

    /// Get a locked plugin entry
    pub fn getPlugin(self: *Lockfile, name: []const u8) ?*const LockEntry {
        return self.plugins.getPtr(name);
    }

    /// Verify a plugin's hash matches the lockfile
    pub fn verifyPlugin(self: *Lockfile, name: []const u8, actual_hash: [64]u8) !bool {
        const entry = self.getPlugin(name) orelse return error.PluginNotInLockfile;

        return std.mem.eql(u8, &entry.hash, &actual_hash);
    }

    /// Write lockfile to grim.lock.zon
    pub fn write(self: *Lockfile, path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var write_buffer: [4096]u8 = undefined;
        var file_writer = file.writer(&write_buffer);
        var writer = &file_writer.interface;

        // Write header
        try writer.writeAll("// Grim Plugin Lockfile\n");
        try writer.writeAll("// This file is auto-generated by gpkg\n");
        try writer.writeAll("// DO NOT EDIT MANUALLY\n\n");

        try writer.print(".{{\n", .{});
        try writer.print("    .version = \"{s}\",\n", .{self.version});
        try writer.print("    .plugins = .{{\n", .{});

        // Sort plugins by name for deterministic output
        var names = std.ArrayList([]const u8){};
        defer names.deinit(self.allocator);

        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            try names.append(self.allocator, entry.key_ptr.*);
        }

        std.mem.sort([]const u8, names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Write each plugin
        for (names.items) |name| {
            const entry = self.plugins.get(name).?;

            try writer.print("        .@\"{s}\" = .{{\n", .{name});
            try writer.print("            .version = \"{s}\",\n", .{entry.version});
            try writer.print("            .hash = \"{s}\",\n", .{entry.hash});
            try writer.print("            .source = \"{s}\",\n", .{entry.source});
            try writer.print("            .type = \"{s}\",\n", .{entry.type});

            if (entry.dependencies.len > 0) {
                try writer.print("            .dependencies = &.{{\n", .{});
                for (entry.dependencies) |dep| {
                    try writer.print("                \"{s}\",\n", .{dep});
                }
                try writer.print("            }},\n", .{});
            } else {
                try writer.print("            .dependencies = &.{{}},\n", .{});
            }

            try writer.print("            .updated_at = {d},\n", .{entry.updated_at});
            try writer.print("        }},\n", .{});
        }

        try writer.print("    }},\n", .{});
        try writer.print("}}\n", .{});

        try writer.flush();
    }

    /// Read lockfile from grim.lock.zon
    pub fn read(allocator: std.mem.Allocator, path: []const u8) !*Lockfile {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        const stat = try file.stat();
        const max_size = @min(stat.size, 10 * 1024 * 1024); // 10MB max
        const content = try allocator.alloc(u8, max_size);
        defer allocator.free(content);

        const bytes_read = try file.read(content);
        const actual_content = content[0..bytes_read];

        return try parseZon(allocator, actual_content);
    }

    /// Parse .zon format lockfile
    fn parseZon(allocator: std.mem.Allocator, content: []const u8) !*Lockfile {
        // Simple .zon parser for lockfile format
        // This is a basic implementation - could be enhanced with full .zon parser

        const lockfile = try Lockfile.init(allocator);
        errdefer lockfile.deinit();

        // Parse each plugin entry
        // Format: .@"name" = .{ .version = "1.0.0", .hash = "...", ... },

        var lines = std.mem.tokenizeScalar(u8, content, '\n');
        var current_plugin: ?struct {
            name: []const u8 = undefined,
            version: []const u8 = undefined,
            hash: [64]u8 = undefined,
            source: []const u8 = undefined,
            type: []const u8 = undefined,
            dependencies: std.ArrayList([]const u8) = undefined,
            updated_at: i64 = 0,
        } = null;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Skip comments and empty lines
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) continue;

            // Plugin name line: .@"plugin-name" = .{
            if (std.mem.indexOf(u8, trimmed, ".@\"")) |_| {
                if (current_plugin) |*p| {
                    // Save previous plugin
                    try lockfile.addPlugin(
                        p.name,
                        p.version,
                        p.hash,
                        p.source,
                        p.type,
                        p.dependencies.items,
                    );
                    p.dependencies.deinit(allocator);
                }

                // Extract plugin name
                const start = std.mem.indexOf(u8, trimmed, "\"").? + 1;
                const end = std.mem.indexOfPos(u8, trimmed, start, "\"").?;
                const name = try allocator.dupe(u8, trimmed[start..end]);

                current_plugin = .{
                    .name = name,
                    .dependencies = std.ArrayList([]const u8){},
                };
            }

            if (current_plugin) |*p| {
                // Parse fields
                if (std.mem.indexOf(u8, trimmed, ".version =")) |_| {
                    const value = try extractQuotedValue(allocator, trimmed);
                    p.version = value;
                } else if (std.mem.indexOf(u8, trimmed, ".hash =")) |_| {
                    const value = try extractQuotedValue(allocator, trimmed);
                    if (value.len != 64) return error.InvalidHash;
                    @memcpy(&p.hash, value);
                } else if (std.mem.indexOf(u8, trimmed, ".source =")) |_| {
                    const value = try extractQuotedValue(allocator, trimmed);
                    p.source = value;
                } else if (std.mem.indexOf(u8, trimmed, ".type =")) |_| {
                    const value = try extractQuotedValue(allocator, trimmed);
                    p.type = value;
                } else if (std.mem.indexOf(u8, trimmed, ".updated_at =")) |_| {
                    const value = try extractNumberValue(trimmed);
                    p.updated_at = value;
                } else if (std.mem.indexOf(u8, trimmed, "\"") != null and
                          !std.mem.startsWith(u8, trimmed, ".")) {
                    // Dependency entry
                    const value = try extractQuotedValue(allocator, trimmed);
                    try p.dependencies.append(allocator, value);
                }
            }
        }

        // Save last plugin
        if (current_plugin) |*p| {
            try lockfile.addPlugin(
                p.name,
                p.version,
                p.hash,
                p.source,
                p.type,
                p.dependencies.items,
            );
            p.dependencies.deinit(allocator);
        }

        return lockfile;
    }

    fn extractQuotedValue(allocator: std.mem.Allocator, line: []const u8) ![]const u8 {
        const start = std.mem.indexOf(u8, line, "\"") orelse return error.InvalidFormat;
        const end = std.mem.indexOfPos(u8, line, start + 1, "\"") orelse return error.InvalidFormat;
        return try allocator.dupe(u8, line[start + 1 .. end]);
    }

    fn extractNumberValue(line: []const u8) !i64 {
        const equals = std.mem.indexOf(u8, line, "=") orelse return error.InvalidFormat;
        const comma = std.mem.indexOf(u8, line, ",") orelse line.len;
        const num_str = std.mem.trim(u8, line[equals + 1 .. comma], " \t");
        return try std.fmt.parseInt(i64, num_str, 10);
    }
};

/// Compute SHA-256 hash of a plugin directory
pub fn hashPluginDirectory(allocator: std.mem.Allocator, plugin_path: []const u8) ![64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    // Walk directory and hash all files in deterministic order
    var dir = try std.fs.openDirAbsolute(plugin_path, .{ .iterate = true });
    defer dir.close();

    // Collect all file paths
    var file_paths = std.ArrayList([]const u8){};
    defer {
        for (file_paths.items) |path| {
            allocator.free(path);
        }
        file_paths.deinit(allocator);
    }

    try collectFilePaths(&file_paths, allocator, dir, "");

    // Sort for deterministic hashing
    std.mem.sort([]const u8, file_paths.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Hash each file
    for (file_paths.items) |rel_path| {
        // Hash the file path
        hasher.update(rel_path);
        hasher.update(&[_]u8{0}); // Null separator

        // Hash the file content
        const file = try dir.openFile(rel_path, .{});
        defer file.close();

        const stat = try file.stat();
        const max_size = @min(stat.size, 100 * 1024 * 1024); // 100MB max per file
        const content = try allocator.alloc(u8, max_size);
        defer allocator.free(content);

        const bytes_read = try file.read(content);
        const actual_content = content[0..bytes_read];

        hasher.update(actual_content);
        hasher.update(&[_]u8{0}); // Null separator
    }

    // Finalize hash
    var hash_bytes: [32]u8 = undefined;
    hasher.final(&hash_bytes);

    // Convert to hex string
    const hex_hash = std.fmt.bytesToHex(hash_bytes, .lower);

    return hex_hash;
}

fn collectFilePaths(
    list: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    prefix: []const u8,
) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip hidden files and build artifacts
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        if (std.mem.eql(u8, entry.name, "zig-out")) continue;
        if (std.mem.eql(u8, entry.name, "zig-cache")) continue;

        const path = if (prefix.len > 0)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, entry.name })
        else
            try allocator.dupe(u8, entry.name);

        if (entry.kind == .directory) {
            defer allocator.free(path);

            var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
            defer sub_dir.close();

            try collectFilePaths(list, allocator, sub_dir, path);
        } else if (entry.kind == .file) {
            try list.append(allocator, path);
        }
    }
}

/// Verify all plugins in lockfile match their hashes
pub fn verifyLockfile(allocator: std.mem.Allocator, lockfile_path: []const u8, plugins_dir: []const u8) !void {
    const lockfile = try Lockfile.read(allocator, lockfile_path);
    defer lockfile.deinit();

    std.debug.print("\n🔒 Verifying lockfile integrity...\n\n", .{});

    var verified: usize = 0;
    var failed: usize = 0;

    var it = lockfile.plugins.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const lock_entry = entry.value_ptr;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const plugin_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ plugins_dir, name });

        // Check if plugin exists
        std.fs.accessAbsolute(plugin_path, .{}) catch {
            std.debug.print("  \x1b[31m✗\x1b[0m {s} - \x1b[31mnot installed\x1b[0m\n", .{name});
            failed += 1;
            continue;
        };

        // Compute hash
        const actual_hash = hashPluginDirectory(allocator, plugin_path) catch |err| {
            std.debug.print("  \x1b[31m✗\x1b[0m {s} - \x1b[31mhash failed: {}\x1b[0m\n", .{ name, err });
            failed += 1;
            continue;
        };

        // Verify hash
        if (std.mem.eql(u8, &lock_entry.hash, &actual_hash)) {
            std.debug.print("  \x1b[32m✓\x1b[0m {s}\n", .{name});
            verified += 1;
        } else {
            std.debug.print("  \x1b[31m✗\x1b[0m {s} - \x1b[31mhash mismatch!\x1b[0m\n", .{name});
            std.debug.print("     Expected: {s}\n", .{lock_entry.hash});
            std.debug.print("     Got:      {s}\n", .{actual_hash});
            failed += 1;
        }
    }

    std.debug.print("\n", .{});
    if (failed == 0) {
        std.debug.print("\x1b[32m✓ All {d} plugins verified successfully\x1b[0m\n", .{verified});
    } else {
        std.debug.print("\x1b[31m✗ {d} plugins failed verification\x1b[0m\n", .{failed});
        std.debug.print("\x1b[33m⚠ Run 'gpkg lock' to regenerate lockfile\x1b[0m\n", .{});
        return error.LockfileVerificationFailed;
    }
}

test "lockfile basic operations" {
    const allocator = std.testing.allocator;

    var lockfile = try Lockfile.init(allocator);
    defer lockfile.deinit();

    const hash: [64]u8 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".*;

    try lockfile.addPlugin(
        "test-plugin",
        "1.0.0",
        hash,
        "https://github.com/user/test-plugin",
        "zig",
        &[_][]const u8{"dep1"},
    );

    const entry = lockfile.getPlugin("test-plugin").?;
    try std.testing.expectEqualStrings("1.0.0", entry.version);
    try std.testing.expectEqualStrings("zig", entry.type);
    try std.testing.expect(entry.dependencies.len == 1);
}

test "lockfile hash verification" {
    const allocator = std.testing.allocator;

    var lockfile = try Lockfile.init(allocator);
    defer lockfile.deinit();

    const hash: [64]u8 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".*;

    try lockfile.addPlugin(
        "test-plugin",
        "1.0.0",
        hash,
        "source",
        "zig",
        &[_][]const u8{},
    );

    try std.testing.expect(try lockfile.verifyPlugin("test-plugin", hash));

    const bad_hash: [64]u8 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".*;
    try std.testing.expect(!try lockfile.verifyPlugin("test-plugin", bad_hash));
}

const std = @import("std");
const lockfile_mod = @import("lockfile.zig");
const pack_mod = @import("pack.zig");

const GPKG_VERSION = "0.1.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printHelp();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "install")) {
        try installCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "update")) {
        try updateCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "list")) {
        try listCommand(allocator);
    } else if (std.mem.eql(u8, command, "remove")) {
        try removeCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "search")) {
        try searchCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "lock")) {
        try lockCommand(allocator);
    } else if (std.mem.eql(u8, command, "verify")) {
        try verifyCommand(allocator);
    } else if (std.mem.eql(u8, command, "pack-install")) {
        try packInstallCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "pack-create")) {
        try packCreateCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "new")) {
        try newPluginCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build")) {
        try buildCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "info")) {
        try infoCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "-v")) {
        try printVersion();
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "-h")) {
        try printHelp();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printHelp();
        std.process.exit(1);
    }
}

fn installCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        // Install all plugins from plugins.zon
        std.debug.print("Installing all plugins from phantom.grim/plugins.zon...\n", .{});
        try installAllPlugins(allocator);
    } else {
        // Install specific plugin
        const plugin_name = args[0];
        std.debug.print("Installing plugin: {s}\n", .{plugin_name});
        try installPlugin(allocator, plugin_name);
    }
}

fn updateCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;
    std.debug.print("Updating all plugins...\n", .{});
    try updateAllPlugins(allocator);
}

fn listCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("Installed plugins:\n", .{});
    try listInstalledPlugins(allocator);
}

fn removeCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: Please specify a plugin to remove\n", .{});
        std.process.exit(1);
    }
    const plugin_name = args[0];
    std.debug.print("Removing plugin: {s}\n", .{plugin_name});
    try removePlugin(allocator, plugin_name);
}

fn searchCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    if (args.len == 0) {
        std.debug.print("Error: Please specify a search query\n", .{});
        std.process.exit(1);
    }
    const query = args[0];
    std.debug.print("Searching for: {s}\n", .{query});
    std.debug.print("(Registry search not yet implemented)\n", .{});
}

fn lockCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("Generating lockfile...\n", .{});
    try generateLockfile(allocator);
}

fn printVersion() !void {
    std.debug.print("gpkg version {s}\n", .{GPKG_VERSION});
}

fn printHelp() !void {
    std.debug.print(
        \\
        \\\x1b[1;36mgpkg\x1b[0m - Grim Package Manager \x1b[2m(v{s})\x1b[0m
        \\
        \\\x1b[1mUSAGE:\x1b[0m
        \\    gpkg \x1b[33m<COMMAND>\x1b[0m [OPTIONS]
        \\
        \\\x1b[1mCOMMANDS:\x1b[0m
        \\    \x1b[32minstall\x1b[0m [PLUGIN]    Install plugin(s) - all if no name given
        \\    \x1b[32mupdate\x1b[0m              Update all installed plugins
        \\    \x1b[32mlist\x1b[0m                List installed plugins with details
        \\    \x1b[32mremove\x1b[0m <PLUGIN>     Remove a plugin
        \\    \x1b[32mbuild\x1b[0m [PATH]        Build a zig plugin (runs zig build)
        \\    \x1b[32minfo\x1b[0m <PLUGIN>       Show detailed info about a plugin
        \\    \x1b[32msearch\x1b[0m <QUERY>      Search for plugins (registry)
        \\    \x1b[32mlock\x1b[0m                Generate lockfile with SHA-256 hashes
        \\    \x1b[32mverify\x1b[0m              Verify all plugins against lockfile
        \\    \x1b[32mnew\x1b[0m <NAME> [TYPE]   Create new plugin (native/ghostlang/hybrid)
        \\    \x1b[32mpack-create\x1b[0m <NAME>  Create a new plugin pack template
        \\    \x1b[32mpack-install\x1b[0m <FILE> Install plugins from a pack file
        \\    \x1b[32mversion\x1b[0m, -v         Show version
        \\    \x1b[32mhelp\x1b[0m, -h            Show this help
        \\
        \\\x1b[1mEXAMPLES:\x1b[0m
        \\    gpkg install                 \x1b[2m# Install all from plugins.zon\x1b[0m
        \\    gpkg install thanos          \x1b[2m# Install specific plugin\x1b[0m
        \\    gpkg update                  \x1b[2m# Update all plugins\x1b[0m
        \\    gpkg list                    \x1b[2m# List installed plugins\x1b[0m
        \\    gpkg lock                    \x1b[2m# Generate lockfile\x1b[0m
        \\    gpkg verify                  \x1b[2m# Verify plugin integrity\x1b[0m
        \\    gpkg build .                 \x1b[2m# Build plugin in current dir\x1b[0m
        \\    gpkg info thanos             \x1b[2m# Show thanos plugin info\x1b[0m
        \\    gpkg remove thanos           \x1b[2m# Remove plugin\x1b[0m
        \\    gpkg new myplugin native     \x1b[2m# Create new native plugin\x1b[0m
        \\    gpkg pack-create mypack      \x1b[2m# Create new pack template\x1b[0m
        \\    gpkg pack-install mypack.reaper.zon  \x1b[2m# Install from pack\x1b[0m
        \\
        \\\x1b[1mFILES:\x1b[0m
        \\    \x1b[2m~/.config/grim/plugins.zon         \x1b[0m Plugin manifest
        \\    \x1b[2m~/.local/share/grim/grim.lock.zon  \x1b[0m Lockfile with SHA-256 hashes
        \\    \x1b[2m~/.local/share/grim/plugins/       \x1b[0m Installed plugins
        \\    \x1b[2m~/.config/grim/*.reaper.zon        \x1b[0m Plugin packs
        \\
        \\
    , .{GPKG_VERSION});
}

// Plugin management functions

const PluginInfo = struct {
    name: []const u8,
    url: ?[]const u8,
    hash: ?[]const u8,
    plugin_type: []const u8,
    bundled: bool,
};

fn installAllPlugins(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const manifest_path = try std.fmt.bufPrint(&path_buf, "{s}/.config/grim/plugins.zon", .{home});

    // Read plugins.zon
    const file = std.fs.openFileAbsolute(manifest_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: plugins.zon not found at {s}\n", .{manifest_path});
            std.debug.print("Make sure phantom.grim is installed to ~/.config/grim/\n", .{});
            return err;
        }
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    const content = try allocator.alloc(u8, stat.size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Parse and install non-bundled zig plugins
    std.debug.print("Scanning plugins.zon for zig plugins...\n", .{});

    // Simple parser: look for .type = "zig" entries with .url
    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_plugin: ?[]const u8 = null;
    var current_url: ?[]const u8 = null;
    var is_zig_plugin = false;
    var is_bundled = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Detect plugin name: .thanos = .{
        if (std.mem.indexOf(u8, trimmed, " = .{")) |_| {
            if (std.mem.startsWith(u8, trimmed, ".")) {
                const end = std.mem.indexOf(u8, trimmed, " = .{") orelse continue;
                current_plugin = std.mem.trim(u8, trimmed[1..end], "\"@");
                current_url = null;
                is_zig_plugin = false;
                is_bundled = false;
            }
        }

        // Detect .url
        if (std.mem.indexOf(u8, trimmed, ".url = \"")) |start_idx| {
            const url_start = start_idx + 8;
            if (std.mem.indexOf(u8, trimmed[url_start..], "\"")) |url_end| {
                current_url = trimmed[url_start..][0..url_end];
            }
        }

        // Detect .type = "zig"
        if (std.mem.indexOf(u8, trimmed, ".type = \"zig\"")) |_| {
            is_zig_plugin = true;
        }

        // Detect .bundled = true
        if (std.mem.indexOf(u8, trimmed, ".bundled = true")) |_| {
            is_bundled = true;
        }

        // End of plugin block
        if (std.mem.indexOf(u8, trimmed, "},")) |_| {
            if (current_plugin) |plugin_name| {
                if (is_zig_plugin and !is_bundled and current_url != null) {
                    std.debug.print("\nFound zig plugin: {s}\n", .{plugin_name});
                    try installZigPlugin(allocator, plugin_name, current_url.?);
                }
            }
            current_plugin = null;
        }
    }

    std.debug.print("\nAll zig plugins installed!\n", .{});
    std.debug.print("Bundled ghostlang plugins are already in ~/.config/grim/plugins/\n", .{});
}

fn installZigPlugin(allocator: std.mem.Allocator, name: []const u8, url: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Create temp directory for download
    const temp_dir = try std.fmt.bufPrint(&path_buf, "/tmp/gpkg-{s}", .{name});
    std.fs.deleteTreeAbsolute(temp_dir) catch {};
    try std.fs.makeDirAbsolute(temp_dir);

    std.debug.print("  \x1b[34m⬇\x1b[0m  Downloading from {s}...\n", .{url});

    // Download tarball
    const tarball_path = try std.fmt.allocPrint(allocator, "{s}/plugin.tar.gz", .{temp_dir});
    defer allocator.free(tarball_path);

    const curl_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "curl", "-sL", url, "-o", tarball_path },
    }) catch |err| {
        std.debug.print("  Error: Failed to download {s}\n", .{url});
        return err;
    };
    defer allocator.free(curl_result.stdout);
    defer allocator.free(curl_result.stderr);

    if (curl_result.term.Exited != 0) {
        std.debug.print("  \x1b[31m✗\x1b[0m  Download failed\n", .{});
        return error.DownloadFailed;
    }

    // Extract tarball
    std.debug.print("  \x1b[35m📦\x1b[0m Extracting tarball...\n", .{});
    const tar_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "tar", "-xzf", tarball_path, "-C", temp_dir },
    }) catch |err| {
        std.debug.print("  Error: Failed to extract tarball\n", .{});
        return err;
    };
    defer allocator.free(tar_result.stdout);
    defer allocator.free(tar_result.stderr);

    // Find extracted directory (usually <name>-main/)
    var temp_dir_handle = try std.fs.openDirAbsolute(temp_dir, .{ .iterate = true });
    defer temp_dir_handle.close();

    var iter = temp_dir_handle.iterate();
    var extracted_dir: ?[]const u8 = null;
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            extracted_dir = try allocator.dupe(u8, entry.name);
            break;
        }
    }

    if (extracted_dir == null) {
        std.debug.print("  Error: No directory found in tarball\n", .{});
        return error.InvalidTarball;
    }
    defer if (extracted_dir) |dir| allocator.free(dir);

    const src_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ temp_dir, extracted_dir.? });
    defer allocator.free(src_dir);

    // Build the plugin
    std.debug.print("  \x1b[33m🔨\x1b[0m Building with zig...\n", .{});
    const build_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build", "-Doptimize=ReleaseSafe" },
        .cwd = src_dir,
    }) catch |err| {
        std.debug.print("  \x1b[31m✗\x1b[0m  Build failed\n", .{});
        return err;
    };
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);

    if (build_result.term.Exited != 0) {
        std.debug.print("  \x1b[31m✗\x1b[0m  Build failed:\n\x1b[2m{s}\x1b[0m\n", .{build_result.stderr});
        return error.BuildFailed;
    }

    // Install to ~/.local/share/grim/plugins/
    const plugins_dir = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins/{s}", .{ home, name });
    std.fs.deleteTreeAbsolute(plugins_dir) catch {};
    try std.fs.makeDirAbsolute(plugins_dir);

    // Copy zig-out/lib/* to plugin directory
    const zig_out_lib = try std.fmt.allocPrint(allocator, "{s}/zig-out/lib", .{src_dir});
    defer allocator.free(zig_out_lib);

    std.debug.print("  \x1b[36m📥\x1b[0m Installing to \x1b[2m{s}\x1b[0m...\n", .{plugins_dir});

    const cp_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cp", "-r", zig_out_lib, plugins_dir },
    }) catch |err| {
        std.debug.print("  Error: Failed to copy built artifacts\n", .{});
        return err;
    };
    defer allocator.free(cp_result.stdout);
    defer allocator.free(cp_result.stderr);

    // Also copy the whole zig-out directory for completeness
    const zig_out = try std.fmt.allocPrint(allocator, "{s}/zig-out", .{src_dir});
    defer allocator.free(zig_out);

    const cp_all_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cp", "-r", zig_out, plugins_dir },
    }) catch {
        std.debug.print("  Warning: Failed to copy full zig-out\n", .{});
        return;
    };
    defer allocator.free(cp_all_result.stdout);
    defer allocator.free(cp_all_result.stderr);

    std.debug.print("  \x1b[32m✓\x1b[0m  Successfully installed \x1b[1m{s}\x1b[0m\n", .{name});

    // Cleanup
    std.fs.deleteTreeAbsolute(temp_dir) catch {};
}

fn installPlugin(allocator: std.mem.Allocator, name: []const u8) !void {
    std.debug.print("Installing specific plugin: {s}\n", .{name});
    std.debug.print("TODO: Parse plugins.zon to find plugin {s}\n", .{name});
    _ = allocator;
}

fn updateAllPlugins(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("TODO: Update all plugins\n", .{});
}

fn listInstalledPlugins(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugins_dir = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins", .{home});

    var dir = std.fs.openDirAbsolute(plugins_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("\x1b[33m📦 No plugins directory found\x1b[0m\n", .{});
            std.debug.print("   Run '\x1b[1mgpkg install\x1b[0m' to install plugins\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    var count: usize = 0;
    var zig_count: usize = 0;
    var ghostlang_count: usize = 0;

    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            count += 1;

            // Check plugin type
            const plugin_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ plugins_dir, entry.name });
            defer allocator.free(plugin_path);

            var plugin_dir = std.fs.openDirAbsolute(plugin_path, .{}) catch continue;
            defer plugin_dir.close();

            const has_lib = blk: {
                plugin_dir.access("zig-out/lib", .{}) catch break :blk false;
                break :blk true;
            };

            const has_bin = blk: {
                plugin_dir.access("zig-out/bin", .{}) catch break :blk false;
                break :blk true;
            };

            if (has_lib or has_bin) {
                zig_count += 1;
                std.debug.print("  \x1b[36m⚡\x1b[0m {s} \x1b[2m(zig)\x1b[0m\n", .{entry.name});
            } else {
                ghostlang_count += 1;
                std.debug.print("  \x1b[35m👻\x1b[0m {s} \x1b[2m(ghostlang)\x1b[0m\n", .{entry.name});
            }
        }
    }

    if (count == 0) {
        std.debug.print("\x1b[33m📦 No plugins installed\x1b[0m\n", .{});
        std.debug.print("   Run '\x1b[1mgpkg install\x1b[0m' to install from plugins.zon\n", .{});
    } else {
        std.debug.print("\n\x1b[1mTotal:\x1b[0m {d} plugins ({d} zig, {d} ghostlang)\n", .{ count, zig_count, ghostlang_count });
        std.debug.print("   Use '\x1b[1mgpkg info <name>\x1b[0m' for details\n", .{});
    }
}

fn removePlugin(allocator: std.mem.Allocator, name: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugin_path = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins/{s}", .{ home, name });

    std.fs.deleteTreeAbsolute(plugin_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Plugin {s} not found\n", .{name});
            return;
        }
        return err;
    };

    std.debug.print("Removed plugin: {s}\n", .{name});
    _ = allocator;
}

fn generateLockfile(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugins_dir = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins", .{home});

    var lockfile_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const lockfile_path = try std.fmt.bufPrint(&lockfile_path_buf, "{s}/.local/share/grim/grim.lock.zon", .{home});

    std.debug.print("\n🔒 Generating lockfile from installed plugins...\n\n", .{});

    // Open plugins directory
    var dir = std.fs.openDirAbsolute(plugins_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("\x1b[33m⚠ No plugins directory found\x1b[0m\n", .{});
            std.debug.print("   Run 'gpkg install' to install plugins first\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();

    // Create lockfile
    var lockfile = try lockfile_mod.Lockfile.init(allocator);
    defer lockfile.deinit();

    var count: usize = 0;

    // Iterate through installed plugins
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        const plugin_name = entry.name;

        // Get full plugin path
        var plugin_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const plugin_path = try std.fmt.bufPrint(&plugin_path_buf, "{s}/{s}", .{ plugins_dir, plugin_name });

        std.debug.print("  Hashing {s}... ", .{plugin_name});

        // Compute hash
        const hash = lockfile_mod.hashPluginDirectory(allocator, plugin_path) catch |err| {
            std.debug.print("\x1b[31mfailed: {}\x1b[0m\n", .{err});
            continue;
        };

        std.debug.print("\x1b[32m✓\x1b[0m\n", .{});

        // Detect plugin type
        var plugin_dir = try dir.openDir(plugin_name, .{});
        defer plugin_dir.close();

        const has_build = blk: {
            plugin_dir.access("build.zig", .{}) catch break :blk false;
            break :blk true;
        };

        const has_lib = blk: {
            plugin_dir.access("zig-out/lib", .{}) catch break :blk false;
            break :blk true;
        };

        const has_gza = blk: {
            plugin_dir.access("init.gza", .{}) catch {
                plugin_dir.access("main.gza", .{}) catch break :blk false;
                break :blk true;
            };
            break :blk true;
        };

        const plugin_type = if (has_lib and has_gza)
            "hybrid"
        else if (has_lib or has_build)
            "zig"
        else
            "ghostlang";

        // Try to extract version from plugin.toml or default to "0.0.0"
        const version = "0.0.0"; // TODO: Parse plugin.toml for version

        // Try to extract dependencies from plugin.toml
        const dependencies = &[_][]const u8{}; // TODO: Parse plugin.toml for dependencies

        // Add to lockfile
        try lockfile.addPlugin(
            plugin_name,
            version,
            hash,
            "local", // TODO: Track actual source URL
            plugin_type,
            dependencies,
        );

        count += 1;
    }

    if (count == 0) {
        std.debug.print("\x1b[33m⚠ No plugins found to lock\x1b[0m\n", .{});
        return;
    }

    // Write lockfile
    std.debug.print("\n  Writing lockfile...\n", .{});
    try lockfile.write(lockfile_path);

    std.debug.print("\n\x1b[32m✓ Lockfile generated successfully\x1b[0m\n", .{});
    std.debug.print("  Location: {s}\n", .{lockfile_path});
    std.debug.print("  Plugins locked: {d}\n", .{count});
    std.debug.print("\n  Use 'gpkg verify' to verify integrity\n", .{});
}

fn verifyCommand(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugins_dir = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins", .{home});

    var lockfile_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const lockfile_path = try std.fmt.bufPrint(&lockfile_path_buf, "{s}/.local/share/grim/grim.lock.zon", .{home});

    // Check if lockfile exists
    std.fs.accessAbsolute(lockfile_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("\x1b[31m✗ Lockfile not found\x1b[0m\n", .{});
            std.debug.print("   Run 'gpkg lock' to generate lockfile\n", .{});
            return;
        }
        return err;
    };

    try lockfile_mod.verifyLockfile(allocator, lockfile_path, plugins_dir);
}

fn packInstallCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("\x1b[31m✗ Error: Pack file path required\x1b[0m\n", .{});
        std.debug.print("   Usage: gpkg pack-install <reaper.zon>\n", .{});
        return;
    }

    const pack_path = args[0];

    // Check if file exists
    std.fs.accessAbsolute(pack_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("\x1b[31m✗ Pack file not found: {s}\x1b[0m\n", .{pack_path});
            return;
        }
        return err;
    };

    try pack_mod.installPack(allocator, pack_path);
}

fn packCreateCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("\x1b[31m✗ Error: Pack name required\x1b[0m\n", .{});
        std.debug.print("   Usage: gpkg pack-create <name>\n", .{});
        return;
    }

    const pack_name = args[0];
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const pack_path = try std.fmt.bufPrint(&path_buf, "{s}/.config/grim/{s}.reaper.zon", .{ home, pack_name });

    try pack_mod.createPackTemplate(allocator, pack_path, pack_name);
}

fn newPluginCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("\x1b[31m✗ Error: Plugin name required\x1b[0m\n", .{});
        std.debug.print("   Usage: gpkg new <name> [type]\n", .{});
        std.debug.print("   Types: native, ghostlang, hybrid (default: native)\n", .{});
        return;
    }

    const plugin_name = args[0];
    const plugin_type = if (args.len > 1) args[1] else "native";

    // Determine plugin type
    const is_native = std.mem.eql(u8, plugin_type, "native") or std.mem.eql(u8, plugin_type, "hybrid");
    const is_ghostlang = std.mem.eql(u8, plugin_type, "ghostlang") or std.mem.eql(u8, plugin_type, "hybrid");

    if (!is_native and !is_ghostlang) {
        std.debug.print("\x1b[31m✗ Error: Invalid plugin type: {s}\x1b[0m\n", .{plugin_type});
        std.debug.print("   Valid types: native, ghostlang, hybrid\n", .{});
        return;
    }

    // Create plugin directory
    try std.fs.cwd().makePath(plugin_name);
    var plugin_dir = try std.fs.cwd().openDir(plugin_name, .{});
    defer plugin_dir.close();

    std.debug.print("\n📦 Creating {s} plugin: {s}\n\n", .{ plugin_type, plugin_name });

    // Create build.zig
    if (is_native) {
        const build_zig_content = try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\
            \\    const lib = b.addSharedLibrary(.{{
            \\        .name = "{s}",
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\
            \\    lib.linkLibC();
            \\
            \\    // Add Grim dependency (adjust path as needed)
            \\    const grim_dep = b.dependency("grim", .{{
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\    lib.root_module.addImport("grim", grim_dep.module("core"));
            \\
            \\    b.installArtifact(lib);
            \\
            \\    // Tests
            \\    const tests = b.addTest(.{{
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\    tests.root_module.addImport("grim", grim_dep.module("core"));
            \\
            \\    const run_tests = b.addRunArtifact(tests);
            \\    const test_step = b.step("test", "Run plugin tests");
            \\    test_step.dependOn(&run_tests.step);
            \\}}
            \\
        , .{plugin_name});
        defer allocator.free(build_zig_content);

        const build_file = try plugin_dir.createFile("build.zig", .{});
        defer build_file.close();
        try build_file.writeAll(build_zig_content);

        std.debug.print("  ✓ Created build.zig\n", .{});

        // Create build.zig.zon
        const build_zon_content = try std.fmt.allocPrint(allocator,
            \\.{{
            \\    .name = "{s}",
            \\    .version = "0.1.0",
            \\    .minimum_zig_version = "0.16.0",
            \\
            \\    .dependencies = .{{
            \\        .grim = .{{
            \\            // Adjust path to point to Grim root
            \\            .path = "../..",
            \\        }},
            \\    }},
            \\
            \\    .paths = .{{
            \\        "build.zig",
            \\        "build.zig.zon",
            \\        "src",
            \\    }},
            \\}}
            \\
        , .{plugin_name});
        defer allocator.free(build_zon_content);

        const zon_file = try plugin_dir.createFile("build.zig.zon", .{});
        defer zon_file.close();
        try zon_file.writeAll(build_zon_content);

        std.debug.print("  ✓ Created build.zig.zon\n", .{});

        // Create src directory and main.zig
        try plugin_dir.makePath("src");
        var src_dir = try plugin_dir.openDir("src", .{});
        defer src_dir.close();

        const main_zig_content = try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\const grim = @import("grim");
            \\
            \\const PluginMetadata = grim.plugin_ffi.PluginMetadata;
            \\const PluginVTable = grim.plugin_ffi.PluginVTable;
            \\const PluginContext = grim.plugin_ffi.PluginContext;
            \\const ABI_VERSION = grim.plugin_ffi.ABI_VERSION;
            \\
            \\// Plugin metadata
            \\const metadata = PluginMetadata{{
            \\    .abi_version = ABI_VERSION,
            \\    .name = "{s}",
            \\    .version = "0.1.0",
            \\    .description = "A Grim plugin",
            \\    .author = "Your Name",
            \\    .min_grim_version = "0.1.0",
            \\}};
            \\
            \\// Plugin vtable
            \\const vtable = PluginVTable{{
            \\    .on_load = onLoad,
            \\    .on_init = onInit,
            \\    .on_deinit = onDeinit,
            \\    .on_reload = null,
            \\}};
            \\
            \\// Export plugin metadata
            \\export fn grim_plugin_metadata() callconv(.C) *const PluginMetadata {{
            \\    return &metadata;
            \\}}
            \\
            \\// Export plugin vtable
            \\export fn grim_plugin_vtable() callconv(.C) *const PluginVTable {{
            \\    return &vtable;
            \\}}
            \\
            \\// Plugin lifecycle hooks
            \\fn onLoad(ctx: *PluginContext) callconv(.C) c_int {{
            \\    const api = ctx.api;
            \\    api.log(.info, "Plugin loaded!");
            \\    return 0;
            \\}}
            \\
            \\fn onInit(ctx: *PluginContext) callconv(.C) c_int {{
            \\    const api = ctx.api;
            \\    api.log(.info, "Plugin initialized!");
            \\
            \\    // Register commands here
            \\    // _ = api.register_command("my-command", myCommand);
            \\
            \\    return 0;
            \\}}
            \\
            \\fn onDeinit(ctx: *PluginContext) callconv(.C) void {{
            \\    const api = ctx.api;
            \\    api.log(.info, "Plugin deinitialized!");
            \\}}
            \\
            \\// Example command handler
            \\// fn myCommand(ctx: *PluginContext, args: [*:0]const u8) callconv(.C) c_int {{
            \\//     _ = ctx;
            \\//     const api = ctx.api;
            \\//     api.log(.info, "Command executed!");
            \\//     api.log(.info, args);
            \\//     return 0;
            \\// }}
            \\
        , .{plugin_name});
        defer allocator.free(main_zig_content);

        const main_file = try src_dir.createFile("main.zig", .{});
        defer main_file.close();
        try main_file.writeAll(main_zig_content);

        std.debug.print("  ✓ Created src/main.zig\n", .{});
    }

    // Create Ghostlang file
    if (is_ghostlang) {
        const gza_content = try std.fmt.allocPrint(allocator,
            \\-- {s} Ghostlang Plugin
            \\-- A simple plugin for Grim editor
            \\
            \\local plugin = {{}}
            \\
            \\-- Plugin metadata
            \\plugin.name = "{s}"
            \\plugin.version = "0.1.0"
            \\plugin.description = "A Grim plugin"
            \\plugin.author = "Your Name"
            \\
            \\-- Called when plugin is loaded
            \\function plugin.on_load()
            \\    print("Plugin loaded!")
            \\end
            \\
            \\-- Called when plugin is initialized
            \\function plugin.on_init()
            \\    print("Plugin initialized!")
            \\
            \\    -- Register commands here
            \\    -- grim.register_command("my-command", plugin.my_command)
            \\end
            \\
            \\-- Example command handler
            \\-- function plugin.my_command(args)
            \\--     print("Command executed: " .. args)
            \\-- end
            \\
            \\-- Called when plugin is unloaded
            \\function plugin.on_deinit()
            \\    print("Plugin deinitialized!")
            \\end
            \\
            \\return plugin
            \\
        , .{ plugin_name, plugin_name });
        defer allocator.free(gza_content);

        const gza_filename = try std.fmt.allocPrint(allocator, "{s}.gza", .{plugin_name});
        defer allocator.free(gza_filename);

        const gza_file = try plugin_dir.createFile(gza_filename, .{});
        defer gza_file.close();
        try gza_file.writeAll(gza_content);

        std.debug.print("  ✓ Created {s}.gza\n", .{plugin_name});
    }

    // Create README.md
    const readme_content = try std.fmt.allocPrint(allocator,
        \\# {s}
        \\
        \\A {s} plugin for Grim editor.
        \\
        \\## Installation
        \\
        \\```bash
        \\gpkg install .
        \\```
        \\
        \\## Building (for native plugins)
        \\
        \\```bash
        \\zig build
        \\```
        \\
        \\## Testing
        \\
        \\```bash
        \\zig build test
        \\```
        \\
        \\## Description
        \\
        \\[Add your plugin description here]
        \\
        \\## License
        \\
        \\[Add your license here]
        \\
    , .{ plugin_name, plugin_type });
    defer allocator.free(readme_content);

    const readme_file = try plugin_dir.createFile("README.md", .{});
    defer readme_file.close();
    try readme_file.writeAll(readme_content);

    std.debug.print("  ✓ Created README.md\n", .{});

    // Create .gitignore
    const gitignore_content =
        \\zig-cache/
        \\zig-out/
        \\.zig-cache/
        \\
    ;

    const gitignore_file = try plugin_dir.createFile(".gitignore", .{});
    defer gitignore_file.close();
    try gitignore_file.writeAll(gitignore_content);

    std.debug.print("  ✓ Created .gitignore\n", .{});

    std.debug.print("\n\x1b[32m✓ Plugin '{s}' created successfully!\x1b[0m\n", .{plugin_name});
    std.debug.print("\nNext steps:\n", .{});
    std.debug.print("  cd {s}\n", .{plugin_name});
    if (is_native) {
        std.debug.print("  zig build        # Build the plugin\n", .{});
        std.debug.print("  zig build test   # Run tests\n", .{});
    }
    std.debug.print("  gpkg install .   # Install the plugin\n", .{});
    std.debug.print("\n", .{});
}

fn buildCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const path = if (args.len > 0) args[0] else ".";

    std.debug.print("Building plugin in {s}...\n", .{path});

    // Run zig build in the plugin directory
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build", "-Doptimize=ReleaseSafe" },
        .cwd = path,
    }) catch |err| {
        std.debug.print("Error: Failed to run zig build: {}\n", .{err});
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("Build failed:\n{s}\n", .{result.stderr});
        return error.BuildFailed;
    }

    std.debug.print("✓ Build successful\n", .{});
    if (result.stdout.len > 0) {
        std.debug.print("{s}\n", .{result.stdout});
    }
}

fn infoCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("\x1b[31m❌ Error:\x1b[0m Please specify a plugin name\n", .{});
        std.debug.print("   Usage: \x1b[1mgpkg info <plugin-name>\x1b[0m\n", .{});
        std.process.exit(1);
    }

    const plugin_name = args[0];
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugin_path = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins/{s}", .{ home, plugin_name });

    // Check if plugin exists
    var dir = std.fs.openDirAbsolute(plugin_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("\x1b[31m❌ Plugin '\x1b[1m{s}\x1b[0m\x1b[31m' not found\x1b[0m\n", .{plugin_name});
            std.debug.print("   Use '\x1b[1mgpkg list\x1b[0m' to see installed plugins\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();

    // Header
    std.debug.print("\n╭─ \x1b[1m{s}\x1b[0m ─────────────────────────────\n", .{plugin_name});
    std.debug.print("│\n", .{});
    std.debug.print("│ \x1b[2mLocation:\x1b[0m {s}\n", .{plugin_path});

    // Check for build artifacts
    const has_lib = blk: {
        dir.access("zig-out/lib", .{}) catch break :blk false;
        break :blk true;
    };

    const has_bin = blk: {
        dir.access("zig-out/bin", .{}) catch break :blk false;
        break :blk true;
    };

    if (has_lib or has_bin) {
        std.debug.print("│ \x1b[2mType:\x1b[0m     \x1b[36m⚡ Zig native plugin\x1b[0m\n", .{});
    } else {
        std.debug.print("│ \x1b[2mType:\x1b[0m     \x1b[35m👻 Ghostlang script\x1b[0m\n", .{});
    }

    if (has_lib) {
        std.debug.print("│\n", .{});
        std.debug.print("│ \x1b[1mLibraries:\x1b[0m\n", .{});

        // List library files
        var lib_dir = try dir.openDir("zig-out/lib", .{ .iterate = true });
        defer lib_dir.close();

        var iter = lib_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                std.debug.print("│   • {s}\n", .{entry.name});
            }
        }
    }

    if (has_bin) {
        std.debug.print("│\n", .{});
        std.debug.print("│ \x1b[1mExecutables:\x1b[0m\n", .{});

        // List executables
        var bin_dir = try dir.openDir("zig-out/bin", .{ .iterate = true });
        defer bin_dir.close();

        var iter = bin_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                std.debug.print("│   • {s}\n", .{entry.name});
            }
        }
    }

    std.debug.print("│\n", .{});
    std.debug.print("╰─────────────────────────────────────────\n\n", .{});

    _ = allocator;
}

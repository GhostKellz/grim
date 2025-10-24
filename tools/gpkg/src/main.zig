const std = @import("std");

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
    const help_text =
        \\gpkg - Grim Package Manager
        \\
        \\USAGE:
        \\    gpkg <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    install [PLUGIN]    Install plugin(s) - all if no name given
        \\    update              Update all installed plugins
        \\    list                List installed plugins
        \\    remove <PLUGIN>     Remove a plugin
        \\    build [PATH]        Build a zig plugin (runs zig build)
        \\    info <PLUGIN>       Show info about an installed plugin
        \\    search <QUERY>      Search for plugins (registry)
        \\    lock                Generate lockfile from current plugins
        \\    version, -v         Show version
        \\    help, -h            Show this help
        \\
        \\EXAMPLES:
        \\    gpkg install                 # Install all from plugins.zon
        \\    gpkg install thanos          # Install specific plugin
        \\    gpkg update                  # Update all plugins
        \\    gpkg list                    # List installed plugins
        \\    gpkg build .                 # Build plugin in current dir
        \\    gpkg info thanos             # Show thanos plugin info
        \\    gpkg remove thanos           # Remove plugin
        \\    gpkg lock                    # Generate phantom.lock.zon
        \\
        \\FILES:
        \\    ~/.config/grim/plugins.zon       Plugin manifest
        \\    ~/.config/grim/phantom.lock.zon  Lockfile (versions)
        \\    ~/.local/share/grim/plugins/     Installed plugins
        \\
    ;
    std.debug.print("{s}\n", .{help_text});
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

    std.debug.print("  Fetching {s}...\n", .{url});

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
        std.debug.print("  Error: curl failed\n", .{});
        return error.DownloadFailed;
    }

    // Extract tarball
    std.debug.print("  Extracting...\n", .{});
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
    std.debug.print("  Building...\n", .{});
    const build_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build", "-Doptimize=ReleaseSafe" },
        .cwd = src_dir,
    }) catch |err| {
        std.debug.print("  Error: Build failed\n", .{});
        return err;
    };
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);

    if (build_result.term.Exited != 0) {
        std.debug.print("  Build output:\n{s}\n", .{build_result.stderr});
        return error.BuildFailed;
    }

    // Install to ~/.local/share/grim/plugins/
    const plugins_dir = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins/{s}", .{ home, name });
    std.fs.deleteTreeAbsolute(plugins_dir) catch {};
    try std.fs.makeDirAbsolute(plugins_dir);

    // Copy zig-out/lib/* to plugin directory
    const zig_out_lib = try std.fmt.allocPrint(allocator, "{s}/zig-out/lib", .{src_dir});
    defer allocator.free(zig_out_lib);

    std.debug.print("  Installing to {s}...\n", .{plugins_dir});

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

    std.debug.print("  ✓ Installed {s}\n", .{name});

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
            std.debug.print("  (No plugins installed)\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    var count: usize = 0;
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            count += 1;
            std.debug.print("  - {s}\n", .{entry.name});
        }
    }

    if (count == 0) {
        std.debug.print("  (No plugins installed)\n", .{});
    }

    _ = allocator;
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
    _ = allocator;
    std.debug.print("TODO: Generate phantom.lock.zon\n", .{});
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
        std.debug.print("Error: Please specify a plugin name\n", .{});
        std.process.exit(1);
    }

    const plugin_name = args[0];
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugin_path = try std.fmt.bufPrint(&path_buf, "{s}/.local/share/grim/plugins/{s}", .{ home, plugin_name });

    // Check if plugin exists
    var dir = std.fs.openDirAbsolute(plugin_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Plugin '{s}' not found\n", .{plugin_name});
            std.debug.print("Use 'gpkg list' to see installed plugins\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();

    std.debug.print("Plugin: {s}\n", .{plugin_name});
    std.debug.print("Location: {s}\n", .{plugin_path});

    // Check for build artifacts
    const has_lib = blk: {
        dir.access("zig-out/lib", .{}) catch break :blk false;
        break :blk true;
    };

    const has_bin = blk: {
        dir.access("zig-out/bin", .{}) catch break :blk false;
        break :blk true;
    };

    if (has_lib) {
        std.debug.print("Type: Native library (.so)\n", .{});

        // List library files
        var lib_dir = try dir.openDir("zig-out/lib", .{ .iterate = true });
        defer lib_dir.close();

        std.debug.print("Libraries:\n", .{});
        var iter = lib_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                std.debug.print("  - {s}\n", .{entry.name});
            }
        }
    }

    if (has_bin) {
        std.debug.print("Type: Executable\n", .{});

        // List executables
        var bin_dir = try dir.openDir("zig-out/bin", .{ .iterate = true });
        defer bin_dir.close();

        std.debug.print("Executables:\n", .{});
        var iter = bin_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                std.debug.print("  - {s}\n", .{entry.name});
            }
        }
    }

    if (!has_lib and !has_bin) {
        std.debug.print("Type: Ghostlang script\n", .{});
    }

    _ = allocator;
}

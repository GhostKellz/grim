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
        \\    search <QUERY>      Search for plugins (registry)
        \\    lock                Generate lockfile from current plugins
        \\    version, -v         Show version
        \\    help, -h            Show this help
        \\
        \\EXAMPLES:
        \\    gpkg install                 # Install all from plugins.zon
        \\    gpkg install thanos.grim     # Install specific plugin
        \\    gpkg update                  # Update all plugins
        \\    gpkg list                    # List installed plugins
        \\    gpkg remove thanos.grim      # Remove plugin
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

// Plugin management functions (stubs for now)

fn installAllPlugins(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("TODO: Read plugins.zon and install all plugins\n", .{});
}

fn installPlugin(allocator: std.mem.Allocator, name: []const u8) !void {
    _ = allocator;
    std.debug.print("TODO: Install plugin {s}\n", .{name});
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

const std = @import("std");
const runtime = @import("runtime");

const PluginManifest = runtime.PluginManifest;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return error.InvalidArguments;
    }

    const subcommand = args[1];
    const tail = args[2..];

    if (std.mem.eql(u8, subcommand, "build")) {
        try cmdBuild(allocator, tail);
    } else if (std.mem.eql(u8, subcommand, "install")) {
        try cmdInstall(tail);
    } else if (std.mem.eql(u8, subcommand, "publish")) {
        try cmdPublish(tail);
    } else if (std.mem.eql(u8, subcommand, "search")) {
        try cmdSearch(tail);
    } else if (std.mem.eql(u8, subcommand, "info")) {
        try cmdInfo(tail);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try cmdList(tail);
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        try cmdRemove(allocator, tail);
    } else if (std.mem.eql(u8, subcommand, "update")) {
        try cmdUpdate(tail);
    } else if (std.mem.eql(u8, subcommand, "help")) {
        printUsage();
    } else {
        std.log.err("Unknown subcommand '{s}'", .{subcommand});
        printUsage();
        return error.InvalidArguments;
    }
}

fn printUsage() void {
    std.debug.print(
        "grim-pkg <command> [options]\n\n" ++
            "Commands:\n" ++
            "  build [path] [--out dir]    Build a Phantom.grim plugin\n" ++
            "  install <path>              Install plugin from path or registry\n" ++
            "  list                        List installed plugins\n" ++
            "  info <path-or-id>           Inspect plugin manifest\n" ++
            "  remove <id>                 Remove installed plugin\n" ++
            "  search <query>              Search plugin registry\n" ++
            "  publish                     Publish plugin to registry\n" ++
            "  update [name]               Update plugins to latest\n" ++
            "  help                        Show this message\n",
        .{},
    );
}

const BuildOptions = struct {
    plugin_path: []const u8 = ".",
    out_dir: []const u8 = "dist",
    release: bool = false,
    manifest_path: ?[]const u8 = null,
};

fn cmdBuild(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    var opts = BuildOptions{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg_z = args[i];
        const arg = std.mem.sliceTo(arg_z, 0);
        if (std.mem.eql(u8, arg, "--out")) {
            i += 1;
            if (i >= args.len) return error.MissingOutDirectory;
            opts.out_dir = std.mem.sliceTo(args[i], 0);
        } else if (std.mem.eql(u8, arg, "--manifest")) {
            i += 1;
            if (i >= args.len) return error.MissingManifestPath;
            opts.manifest_path = std.mem.sliceTo(args[i], 0);
        } else if (std.mem.eql(u8, arg, "--release")) {
            opts.release = true;
        } else if (arg.len > 0 and arg[0] == '-') {
            std.log.err("Unknown build option '{s}'", .{arg});
            return error.InvalidArguments;
        } else {
            opts.plugin_path = arg;
        }
    }

    const plugin_root = try std.fs.cwd().realpathAlloc(allocator, opts.plugin_path);
    defer allocator.free(plugin_root);

    const manifest_path = blk: {
        if (opts.manifest_path) |explicit| {
            break :blk try std.fs.cwd().realpathAlloc(allocator, explicit);
        } else {
            const toml_path = try std.fs.path.join(allocator, &.{ plugin_root, "plugin.toml" });
            if (try fileExists(toml_path)) break :blk toml_path;
            allocator.free(toml_path);

            const json_path = try std.fs.path.join(allocator, &.{ plugin_root, "plugin.json" });
            if (try fileExists(json_path)) break :blk json_path;
            allocator.free(json_path);

            std.log.err("No plugin.toml or plugin.json found in {s}", .{plugin_root});
            return error.ManifestNotFound;
        }
    };
    defer allocator.free(manifest_path);

    const manifest_ext = std.fs.path.extension(manifest_path);
    if (!std.mem.eql(u8, manifest_ext, ".toml")) {
        std.log.err("Unsupported manifest extension '{s}'", .{manifest_ext});
        return error.InvalidManifest;
    }

    var manifest = try PluginManifest.parseFile(allocator, manifest_path);
    defer manifest.deinit();

    const artifact_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ manifest.name, manifest.version });
    defer allocator.free(artifact_name);

    try std.fs.cwd().makePath(opts.out_dir);

    const out_abs = try std.fs.cwd().realpathAlloc(allocator, opts.out_dir);
    defer allocator.free(out_abs);

    const dest_root = try std.fs.path.join(allocator, &.{ out_abs, artifact_name });
    defer allocator.free(dest_root);

    var out_dir_handle = try std.fs.openDirAbsolute(out_abs, .{});
    defer out_dir_handle.close();
    try out_dir_handle.makePath(artifact_name);

    try writeManifestJson(allocator, &manifest, dest_root);
    try copyPluginEntry(allocator, &manifest, plugin_root, dest_root);

    std.log.info("Built plugin {s} {s} -> {s}", .{ manifest.name, manifest.version, dest_root });
}

fn writeManifestJson(allocator: std.mem.Allocator, manifest: *const PluginManifest, dest_root: []const u8) !void {
    var dest_dir = try std.fs.openDirAbsolute(dest_root, .{});
    defer dest_dir.close();

    var file = try dest_dir.createFile("manifest.json", .{ .truncate = true });
    defer file.close();

    const PluginSection = struct {
        name: []const u8,
        version: []const u8,
        author: []const u8,
        description: []const u8,
        main: []const u8,
        license: ?[]const u8,
        homepage: ?[]const u8,
        min_grim_version: ?[]const u8,
    };

    const ConfigSection = struct {
        enable_on_startup: bool,
        lazy_load: bool,
        priority: u8,
        load_after: [][]const u8,
    };

    const DependenciesSection = struct {
        requires: [][]const u8,
        optional: [][]const u8,
        conflicts: [][]const u8,
    };

    const ManifestJson = struct {
        plugin: PluginSection,
        config: ConfigSection,
        dependencies: DependenciesSection,
    };

    const data = ManifestJson{
        .plugin = PluginSection{
            .name = manifest.name,
            .version = manifest.version,
            .author = manifest.author,
            .description = manifest.description,
            .main = manifest.main,
            .license = manifest.license,
            .homepage = manifest.homepage,
            .min_grim_version = manifest.min_grim_version,
        },
        .config = ConfigSection{
            .enable_on_startup = manifest.enable_on_startup,
            .lazy_load = manifest.lazy_load,
            .priority = manifest.priority,
            .load_after = manifest.load_after,
        },
        .dependencies = DependenciesSection{
            .requires = manifest.requires,
            .optional = manifest.optional_deps,
            .conflicts = manifest.conflicts,
        },
    };

    const rendered = try std.json.Stringify.valueAlloc(allocator, data, .{});
    defer allocator.free(rendered);

    try file.writeAll(rendered);
    try file.writeAll("\n");
}

fn copyPluginEntry(allocator: std.mem.Allocator, manifest: *const PluginManifest, plugin_root: []const u8, dest_root: []const u8) !void {
    const dest_path = try std.fs.path.join(allocator, &.{ dest_root, manifest.main });
    defer allocator.free(dest_path);

    var source_dir = try std.fs.openDirAbsolute(plugin_root, .{});
    defer source_dir.close();

    var dest_dir = try std.fs.openDirAbsolute(dest_root, .{});
    defer dest_dir.close();

    if (std.fs.path.dirname(manifest.main)) |dir_name| {
        try dest_dir.makePath(dir_name);
    }

    try source_dir.copyFile(manifest.main, dest_dir, manifest.main, .{});
}

fn getPluginDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_DATA_HOME")) |xdg_data| {
        return try std.fs.path.join(allocator, &.{ xdg_data, "grim", "plugins" });
    }
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return try std.fs.path.join(allocator, &.{ home, ".local", "share", "grim", "plugins" });
}

fn cmdInstall(args: []const [:0]u8) !void {
    if (args.len < 1) {
        std.log.err("install requires a path argument", .{});
        return error.InvalidArguments;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source_path = std.mem.sliceTo(args[0], 0);
    const plugin_dir = try getPluginDir(allocator);
    defer allocator.free(plugin_dir);

    try std.fs.cwd().makePath(plugin_dir);

    // Check if source is directory or file
    const stat = try std.fs.cwd().statFile(source_path);

    if (stat.kind == .directory) {
        try installFromDirectory(allocator, source_path, plugin_dir);
    } else if (std.mem.endsWith(u8, source_path, ".gza")) {
        try installFromFile(allocator, source_path, plugin_dir);
    } else {
        std.log.err("Source must be a directory or .gza file", .{});
        return error.InvalidSource;
    }
}

fn installFromDirectory(allocator: std.mem.Allocator, source_path: []const u8, plugin_dir: []const u8) !void {
    const manifest_path = try std.fs.path.join(allocator, &.{ source_path, "plugin.json" });
    defer allocator.free(manifest_path);

    const manifest_content = std.fs.cwd().readFileAlloc(manifest_path, allocator, .limited(1024 * 1024)) catch |err| {
        if (err == error.FileNotFound) {
            std.log.err("plugin.json not found in {s}", .{source_path});
            return error.ManifestNotFound;
        }
        return err;
    };
    defer allocator.free(manifest_content);

    const parsed = try std.json.parseFromSlice(struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
    }, allocator, manifest_content, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const plugin_id = parsed.value.id;
    const dest_path = try std.fs.path.join(allocator, &.{ plugin_dir, plugin_id });
    defer allocator.free(dest_path);

    // Check if exists and overwrite if needed
    const exists = blk: {
        std.fs.cwd().access(dest_path, .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    if (exists) {
        std.log.info("Plugin '{s}' already installed. Overwriting...", .{plugin_id});
        try std.fs.cwd().deleteTree(dest_path);
    }

    std.log.info("Installing plugin '{s}' v{s}...", .{ parsed.value.name, parsed.value.version });
    try copyDirectory(source_path, dest_path);
    std.log.info("✓ Plugin '{s}' installed to {s}", .{ plugin_id, dest_path });
}

fn installFromFile(allocator: std.mem.Allocator, source_path: []const u8, plugin_dir: []const u8) !void {
    const content = try std.fs.cwd().readFileAlloc(source_path, allocator, .limited(10 * 1024 * 1024));
    defer allocator.free(content);

    var plugin_id: ?[]const u8 = null;
    var plugin_name: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "//")) break;

        if (std.mem.startsWith(u8, trimmed, "// @plugin-id:")) {
            plugin_id = std.mem.trim(u8, trimmed[14..], " \t");
        } else if (std.mem.startsWith(u8, trimmed, "// @plugin-name:")) {
            plugin_name = std.mem.trim(u8, trimmed[16..], " \t");
        }
    }

    const id = plugin_id orelse {
        std.log.err("No @plugin-id found in .gza file", .{});
        return error.InvalidManifest;
    };

    const dest_dir = try std.fs.path.join(allocator, &.{ plugin_dir, id });
    defer allocator.free(dest_dir);

    try std.fs.cwd().makePath(dest_dir);

    const dest_file = try std.fs.path.join(allocator, &.{ dest_dir, "init.gza" });
    defer allocator.free(dest_file);

    try std.fs.cwd().copyFile(source_path, std.fs.cwd(), dest_file, .{});
    std.log.info("✓ Plugin '{s}' installed", .{plugin_name orelse id});
}

fn copyDirectory(source: []const u8, dest: []const u8) !void {
    try std.fs.cwd().makePath(dest);

    var source_dir = try std.fs.cwd().openDir(source, .{ .iterate = true });
    defer source_dir.close();

    var iterator = source_dir.iterate();
    while (try iterator.next()) |entry| {
        const source_path = try std.fs.path.join(std.heap.page_allocator, &.{ source, entry.name });
        defer std.heap.page_allocator.free(source_path);

        const dest_path = try std.fs.path.join(std.heap.page_allocator, &.{ dest, entry.name });
        defer std.heap.page_allocator.free(dest_path);

        if (entry.kind == .directory) {
            try copyDirectory(source_path, dest_path);
        } else {
            try std.fs.cwd().copyFile(source_path, std.fs.cwd(), dest_path, .{});
        }
    }
}

fn fileExists(path: []const u8) !bool {
    const parent = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);

    var dir = if (std.fs.path.isAbsolute(parent))
        try std.fs.openDirAbsolute(parent, .{})
    else
        try std.fs.cwd().openDir(parent, .{});
    defer dir.close();

    const file = dir.openFile(base, .{ .mode = .read_only }) catch |err| {
        return switch (err) {
            error.FileNotFound => false,
            else => |e| return e,
        };
    };
    file.close();
    return true;
}

fn cmdPublish(args: []const [:0]u8) !void {
    _ = args;
    std.log.warn("publish command not yet implemented", .{});
}

fn cmdSearch(args: []const [:0]u8) !void {
    _ = args;
    std.log.warn("search command not yet implemented", .{});
}

fn cmdInfo(args: []const [:0]u8) !void {
    if (args.len < 1) {
        std.log.err("info requires a path or plugin ID", .{});
        return error.InvalidArguments;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path_or_id = std.mem.sliceTo(args[0], 0);
    const is_path = std.mem.indexOfScalar(u8, path_or_id, '/') != null or std.mem.endsWith(u8, path_or_id, ".gza");

    var manifest_path: []const u8 = undefined;
    const should_free = true;
    defer if (should_free) allocator.free(manifest_path);

    if (is_path) {
        const stat = try std.fs.cwd().statFile(path_or_id);
        if (stat.kind == .directory) {
            manifest_path = try std.fs.path.join(allocator, &.{ path_or_id, "plugin.json" });
        } else {
            try showPluginInfoFromGza(allocator, path_or_id);
            return;
        }
    } else {
        const plugin_dir = try getPluginDir(allocator);
        defer allocator.free(plugin_dir);
        manifest_path = try std.fs.path.join(allocator, &.{ plugin_dir, path_or_id, "plugin.json" });
    }

    const manifest_content = std.fs.cwd().readFileAlloc(manifest_path, allocator, .limited(1024 * 1024)) catch |err| {
        if (err == error.FileNotFound) {
            std.log.err("plugin.json not found", .{});
            return error.ManifestNotFound;
        }
        return err;
    };
    defer allocator.free(manifest_content);

    const parsed = try std.json.parseFromSlice(struct {
        id: []const u8,
        name: []const u8,
        version: []const u8,
        author: ?[]const u8 = null,
        description: ?[]const u8 = null,
        entry_point: ?[]const u8 = null,
        enable_on_startup: ?bool = null,
    }, allocator, manifest_content, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    std.debug.print("Plugin Information:\n\n", .{});
    std.debug.print("  ID:          {s}\n", .{parsed.value.id});
    std.debug.print("  Name:        {s}\n", .{parsed.value.name});
    std.debug.print("  Version:     {s}\n", .{parsed.value.version});
    if (parsed.value.author) |author| {
        std.debug.print("  Author:      {s}\n", .{author});
    }
    if (parsed.value.description) |desc| {
        std.debug.print("  Description: {s}\n", .{desc});
    }
    if (parsed.value.entry_point) |entry| {
        std.debug.print("  Entry Point: {s}\n", .{entry});
    }
    if (parsed.value.enable_on_startup) |enable| {
        std.debug.print("  Auto-start:  {s}\n", .{if (enable) "yes" else "no"});
    }
}

fn showPluginInfoFromGza(allocator: std.mem.Allocator, gza_path: []const u8) !void {
    const content = try std.fs.cwd().readFileAlloc(gza_path, allocator, .limited(10 * 1024 * 1024));
    defer allocator.free(content);

    var id: ?[]const u8 = null;
    var name: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    var author: ?[]const u8 = null;
    var description: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "//")) break;

        if (std.mem.startsWith(u8, trimmed, "// @plugin-id:")) {
            id = std.mem.trim(u8, trimmed[14..], " \t");
        } else if (std.mem.startsWith(u8, trimmed, "// @plugin-name:")) {
            name = std.mem.trim(u8, trimmed[16..], " \t");
        } else if (std.mem.startsWith(u8, trimmed, "// @plugin-version:")) {
            version = std.mem.trim(u8, trimmed[19..], " \t");
        } else if (std.mem.startsWith(u8, trimmed, "// @plugin-author:")) {
            author = std.mem.trim(u8, trimmed[18..], " \t");
        } else if (std.mem.startsWith(u8, trimmed, "// @plugin-description:")) {
            description = std.mem.trim(u8, trimmed[23..], " \t");
        }
    }

    std.debug.print("Plugin Information (from .gza):\n\n", .{});
    std.debug.print("  ID:          {s}\n", .{id orelse "unknown"});
    std.debug.print("  Name:        {s}\n", .{name orelse "Unknown"});
    std.debug.print("  Version:     {s}\n", .{version orelse "0.0.0"});
    if (author) |a| {
        std.debug.print("  Author:      {s}\n", .{a});
    }
    if (description) |d| {
        std.debug.print("  Description: {s}\n", .{d});
    }
}

fn cmdList(args: []const [:0]u8) !void {
    _ = args;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const plugin_dir = try getPluginDir(allocator);
    defer allocator.free(plugin_dir);

    var dir = std.fs.cwd().openDir(plugin_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No plugins installed.\n", .{});
            std.debug.print("Plugin directory: {s}\n", .{plugin_dir});
            return;
        }
        return err;
    };
    defer dir.close();

    std.debug.print("Installed plugins:\n\n", .{});

    var count: usize = 0;
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .directory) continue;

        const manifest_path = try std.fs.path.join(allocator, &.{ plugin_dir, entry.name, "plugin.json" });
        defer allocator.free(manifest_path);

        const manifest_content = std.fs.cwd().readFileAlloc(manifest_path, allocator, .limited(1024 * 1024)) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("  {s} (no manifest)\n", .{entry.name});
                count += 1;
                continue;
            }
            return err;
        };
        defer allocator.free(manifest_content);

        const parsed = try std.json.parseFromSlice(struct {
            id: []const u8,
            name: []const u8,
            version: []const u8,
            author: ?[]const u8 = null,
            description: ?[]const u8 = null,
        }, allocator, manifest_content, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        std.debug.print("  {s} - {s} v{s}\n", .{ parsed.value.id, parsed.value.name, parsed.value.version });
        if (parsed.value.author) |author| {
            std.debug.print("    Author: {s}\n", .{author});
        }
        if (parsed.value.description) |desc| {
            std.debug.print("    {s}\n", .{desc});
        }
        std.debug.print("\n", .{});
        count += 1;
    }

    if (count == 0) {
        std.debug.print("No plugins installed.\n", .{});
    } else {
        std.debug.print("Total: {d} plugin(s)\n", .{count});
    }
    std.debug.print("\nPlugin directory: {s}\n", .{plugin_dir});
}

fn cmdRemove(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        std.log.err("remove requires a plugin ID", .{});
        return error.InvalidArguments;
    }

    const plugin_id = std.mem.sliceTo(args[0], 0);
    const plugin_dir = try getPluginDir(allocator);
    defer allocator.free(plugin_dir);

    const plugin_path = try std.fs.path.join(allocator, &.{ plugin_dir, plugin_id });
    defer allocator.free(plugin_path);

    std.fs.cwd().access(plugin_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.log.err("Plugin '{s}' not found", .{plugin_id});
            return error.PluginNotFound;
        }
        return err;
    };

    try std.fs.cwd().deleteTree(plugin_path);
    std.log.info("✓ Plugin '{s}' removed", .{plugin_id});
}

fn cmdUpdate(args: []const [:0]u8) !void {
    _ = args;
    std.log.warn("update command not yet implemented", .{});
}

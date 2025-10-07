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
        "  install <name>              Install plugin from registry\n" ++
        "  publish                     Publish plugin to registry\n" ++
        "  search <query>              Search plugin registry\n" ++
        "  info <name>                 Inspect plugin manifest\n" ++
        "  list                        List installed plugins\n" ++
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

fn cmdInstall(args: []const [:0]u8) !void {
    _ = args;
    std.log.warn("install command not yet implemented", .{});
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
    _ = args;
    std.log.warn("info command not yet implemented", .{});
}

fn cmdList(args: []const [:0]u8) !void {
    _ = args;
    std.log.warn("list command not yet implemented", .{});
}

fn cmdUpdate(args: []const [:0]u8) !void {
    _ = args;
    std.log.warn("update command not yet implemented", .{});
}

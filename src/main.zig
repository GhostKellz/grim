const std = @import("std");
const grim = @import("grim");
const runtime = grim.runtime;
const EditorLSP = @import("ui_tui").EditorLSP;
const core = grim.core;

pub fn main() !void {
    const start_time = std.time.nanoTimestamp();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Detect platform capabilities
    var platform_caps = try core.PlatformCapabilities.detect(allocator);
    defer platform_caps.deinit(allocator);

    // Log detected capabilities
    std.log.info("=== Grim Platform Detection ===", .{});
    platform_caps.print();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse command line options
    var theme_name: ?[]const u8 = null;
    var files_to_load: std.ArrayList([]const u8) = .empty;
    defer files_to_load.deinit(allocator);
    var use_zigzag = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--zigzag")) {
            use_zigzag = true;
        } else if (std.mem.eql(u8, arg, "--theme") or std.mem.eql(u8, arg, "-t")) {
            // Next arg is theme name
            if (i + 1 < args.len) {
                i += 1;
                theme_name = args[i];
            } else {
                std.debug.print("Error: --theme requires a theme name\n", .{});
                std.debug.print("Usage: grim [--theme <name>] [files...]\n", .{});
                std.debug.print("Available themes: ghost-hacker-blue, tokyonight-moon\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(
                \\Grim - A modal text editor
                \\
                \\Usage: grim [options] [files...]
                \\
                \\Options:
                \\  -t, --theme <name>    Set theme (default: ghost-hacker-blue)
                \\  -h, --help            Show this help message
                \\
                \\Available themes:
                \\  ghost-hacker-blue     Cyan/teal/mint hacker aesthetic (default)
                \\  tokyonight-moon       Tokyo Night Moon theme
                \\
                \\Examples:
                \\  grim                                # Start with default theme
                \\  grim myfile.zig                     # Open file with default theme
                \\  grim file1.zig file2.zig file3.zig  # Open multiple files
                \\  grim --theme tokyonight-moon        # Start with Tokyo Night theme
                \\  grim -t gruvbox myfile.rs           # Open file with custom theme
                \\
            , .{});
            return;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // Non-option argument is a file to load
            try files_to_load.append(allocator, arg);
        } else {
            std.debug.print("Unknown option: {s}\n", .{arg});
            std.debug.print("Use --help for usage information\n", .{});
            return;
        }
    }

    // Use first file for backwards compatibility
    const file_to_load: ?[]const u8 = if (files_to_load.items.len > 0) files_to_load.items[0] else null;

    // Choose event loop: ZigZag (high-performance) or Phantom (simple)
    if (use_zigzag) {
        std.log.info("Using ZigZag event loop (io_uring/epoll/kqueue)", .{});
        const GrimAppZigZag = @import("ui_tui").grim_app_zigzag.GrimAppZigZag;
        const GrimConfig = @import("ui_tui").grim_app_zigzag.GrimConfig;

        const config = GrimConfig{};
        var app = try GrimAppZigZag.init(allocator, config);
        defer app.deinit();

        // Open file if provided
        if (file_to_load) |path| {
            try app.openFile(path);
        }

        // Run with ZigZag
        try app.run();
    } else {
        std.log.info("Using Phantom event loop (default)", .{});
        const GrimApp = @import("ui_tui").grim_app.GrimApp;
        const GrimConfig = @import("ui_tui").grim_app.GrimConfig;

        const config = GrimConfig{
            .initial_file = file_to_load,
        };

        var app = try GrimApp.init(allocator, config);
        defer app.deinit();

        // Build plugin directories list
        var plugin_dirs = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        defer {
            for (plugin_dirs.items) |dir| allocator.free(dir);
            plugin_dirs.deinit(allocator);
        }
        try collectPluginDirectories(&plugin_dirs, allocator);

        // Initialize plugin API editor context
        var plugin_cursor_position = runtime.PluginAPI.EditorContext.CursorPosition{
            .line = 0,
            .column = 0,
            .byte_offset = 0,
        };
        var plugin_mode = runtime.PluginAPI.EditorContext.EditorMode.normal;
        app.plugin_cursor = &plugin_cursor_position;

        const active_editor = app.layout_manager.getActiveEditor() orelse {
            std.log.err("No active editor available", .{});
            return error.NoActiveEditor;
        };

        var editor_context = runtime.PluginAPI.EditorContext{
            .rope = &active_editor.editor.rope,
            .cursor_position = &plugin_cursor_position,
            .current_mode = &plugin_mode,
            .highlighter = &active_editor.editor.highlighter,
            .selection_start = &active_editor.editor.selection_start,
            .selection_end = &active_editor.editor.selection_end,
            .active_buffer_id = app.getActiveBufferId(),
            .bridge = app.makeEditorBridge(),
        };

        app.setEditorContext(&editor_context);

        var plugin_api = runtime.PluginAPI.init(allocator, &editor_context);
        defer plugin_api.deinit();

        // Initialize plugin manager and discovery
        var plugin_manager = try runtime.PluginManager.init(allocator, &plugin_api, plugin_dirs.items);
        defer plugin_manager.deinit();

        app.attachPluginManager(&plugin_manager);

        var editor_lsp = try EditorLSP.init(allocator, active_editor.editor);
        defer {
            app.detachEditorLSP();
            editor_lsp.deinit();
        }
        app.attachEditorLSP(editor_lsp);
        defer app.closeActiveBuffer();

        // Set default theme to ghost-hacker-blue if no theme specified
        if (theme_name == null) {
            app.setTheme("ghost-hacker-blue") catch |err| {
                std.debug.print("Warning: Failed to set default theme: {}\n", .{err});
            };
        }

        const discovered_plugins = try plugin_manager.discoverPlugins();
        defer cleanupDiscoveredPlugins(allocator, &plugin_manager, discovered_plugins);

        // Lazy load plugins - only load on first use instead of at startup
        // This dramatically improves startup time
        var loaded_count: usize = 0;
        for (discovered_plugins) |*plugin_info| {
            if (!plugin_info.manifest.enable_on_startup) continue;

            // Only load critical plugins at startup (none by default for fast start)
            // Others loaded on-demand when first command is used
            if (std.mem.eql(u8, plugin_info.manifest.name, "core")) {
                plugin_manager.loadPlugin(plugin_info) catch |err| {
                    std.log.err("Failed to load plugin '{s}': {}", .{ plugin_info.manifest.name, err });
                    continue;
                };
                loaded_count += 1;
            }
        }

        const init_time = std.time.nanoTimestamp() - start_time;
        std.log.info("Initialized in {d:.2}ms ({} plugins loaded)", .{
            @as(f64, @floatFromInt(init_time)) / 1_000_000.0,
            loaded_count,
        });

        // Apply theme if specified
        if (theme_name) |theme| {
            app.setTheme(theme) catch |err| {
                std.debug.print("Warning: Failed to set theme '{s}': {}\n", .{ theme, err });
            };
        }

        // Load all files provided on command line
        if (files_to_load.items.len > 0) {
            // Load first file into current tab
            app.loadFile(files_to_load.items[0]) catch |err| {
                std.debug.print("Failed to load file {s}: {}\n", .{ files_to_load.items[0], err });
            };

            // Load remaining files into new tabs
            for (files_to_load.items[1..]) |file_path| {
                app.openFileInNewTab(file_path) catch |err| {
                    std.debug.print("Failed to load file {s}: {}\n", .{ file_path, err });
                };
            }
        } else {
            // Load a sample file for testing
            try active_editor.editor.rope.insert(0,
                \\fn main() !void {
                \\    const std = @import("std");
                \\    std.debug.print("Hello, Grim!\n", .{});
                \\
                \\    // This is a comment
                \\    const x: u32 = 42;
                \\    var y = x * 2;
                \\
                \\    if (y > 80) {
                \\        std.debug.print("y is large: {}\n", .{y});
                \\    }
                \\}
            );
            // Set language for syntax highlighting (sample is Zig code)
            try active_editor.editor.highlighter.setLanguage("sample.zig");
        }

        // Run the TUI immediately (show help in status line instead)
        app.run() catch |err| {
            std.debug.print("TUI error: {}\n", .{err});
            return;
        };

        std.debug.print("Grim editor closed.\n", .{});
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

fn collectPluginDirectories(list: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    // Only add directories that exist to avoid warnings
    try appendPathIfExists(list, allocator, "plugins/examples");
    try appendPathIfExists(list, allocator, "plugins");

    if (std.posix.getenv("HOME")) |home| {
        // Check XDG_DATA_HOME first, then fallback
        if (std.posix.getenv("XDG_DATA_HOME")) |xdg_data| {
            try appendJoinedPathIfExists(list, allocator, &.{ xdg_data, "grim", "plugins" });
        } else {
            try appendJoinedPathIfExists(list, allocator, &.{ home, ".local", "share", "grim", "plugins" });
        }
        try appendJoinedPathIfExists(list, allocator, &.{ home, ".config", "grim", "plugins" });
        try appendJoinedPathIfExists(list, allocator, &.{ home, ".local", "share", "phantom.grim", "plugins" });
    }

    try appendPathIfExists(list, allocator, "/usr/share/grim/plugins");
    try appendPathIfExists(list, allocator, "/usr/local/share/grim/plugins");
}

fn appendPath(list: *std.ArrayList([]const u8), allocator: std.mem.Allocator, path: []const u8) !void {
    const owned = try allocator.dupe(u8, path);
    list.append(allocator, owned) catch |err| {
        allocator.free(owned);
        return err;
    };
}

fn appendPathIfExists(list: *std.ArrayList([]const u8), allocator: std.mem.Allocator, path: []const u8) !void {
    // Check if directory exists
    std.fs.cwd().access(path, .{}) catch return; // Silently skip if doesn't exist
    try appendPath(list, allocator, path);
}

fn appendJoinedPath(list: *std.ArrayList([]const u8), allocator: std.mem.Allocator, parts: []const []const u8) !void {
    const joined = try std.fs.path.join(allocator, parts);
    list.append(allocator, joined) catch |err| {
        allocator.free(joined);
        return err;
    };
}

fn appendJoinedPathIfExists(list: *std.ArrayList([]const u8), allocator: std.mem.Allocator, parts: []const []const u8) !void {
    const joined = try std.fs.path.join(allocator, parts);
    defer allocator.free(joined);
    // Check if directory exists
    std.fs.cwd().access(joined, .{}) catch return; // Silently skip if doesn't exist
    try appendJoinedPath(list, allocator, parts);
}

fn cleanupDiscoveredPlugins(
    allocator: std.mem.Allocator,
    manager: *runtime.PluginManager,
    plugins: []runtime.PluginManager.PluginInfo,
) void {
    for (plugins) |*info| {
        if (info.loaded) {
            manager.unloadPlugin(info.manifest.id) catch |err| {
                std.log.err("Failed to unload plugin '{s}': {}", .{ info.manifest.id, err });
            };
        }

        allocator.free(info.plugin_path);
        allocator.free(info.script_content);
        info.manifest.deinit(allocator);
    }

    allocator.free(plugins);
}

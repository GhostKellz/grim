//! core/plugin_loader.zig
//! Handles plugin loading, fetching, and management

const std = @import("std");
const Io = std.Io;
const zsync = @import("zsync");
const zlog = @import("zlog");
const zhttp = @import("zhttp");
const tar = std.tar;
const grim = @import("grim");
const runtime = grim.runtime;
const plugin_discovery = runtime.plugin_discovery;
const core = grim.core;
const syntax = grim.syntax;

const phantom_host = @import("plugin_host_adapter.zig");
const PhantomPluginHost = phantom_host.PhantomPluginHost;

fn appendJsonString(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    const hex_digits = "0123456789abcdef";
    try buffer.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '"' => try buffer.appendSlice(allocator, "\\\""),
            '\\' => try buffer.appendSlice(allocator, "\\\\"),
            '\n' => try buffer.appendSlice(allocator, "\\n"),
            '\r' => try buffer.appendSlice(allocator, "\\r"),
            '\t' => try buffer.appendSlice(allocator, "\\t"),
            else => {
                if (ch < 0x20) {
                    var buf = [_]u8{ '\\', 'u', '0', '0', 0, 0 };
                    buf[4] = hex_digits[@as(usize, ch >> 4)];
                    buf[5] = hex_digits[@as(usize, ch & 0xF)];
                    try buffer.appendSlice(allocator, buf[0..]);
                } else {
                    try buffer.append(allocator, ch);
                }
            },
        }
    }
    try buffer.append(allocator, '"');
}

fn appendUnsigned(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [20]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
    try buffer.appendSlice(allocator, str);
}

pub const PluginConfig = struct {
    registry_url: []const u8,
    install_dir: []const u8,
};

pub const PluginLoader = struct {
    allocator: std.mem.Allocator,

    // Grim runtime components
    plugin_api: *runtime.PluginAPI,
    plugin_manager: *runtime.PluginManager,
    runtime_loader: runtime.PluginLoader,
    discovery: runtime.PluginDiscovery,

    // Phantom host integration
    host_adapter: *PhantomPluginHost,
    loaded_plugins: std.StringHashMap(*runtime.LoadedPlugin),

    // Minimal editor context for runtime APIs
    editor_context: *runtime.PluginAPI.EditorContext,
    cursor_storage: runtime.PluginAPI.EditorContext.CursorPosition,
    mode_storage: runtime.PluginAPI.EditorContext.EditorMode,
    rope: core.Rope,
    highlighter: syntax.SyntaxHighlighter,

    // Phantom-specific configuration
    config: PluginConfig,
    install_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, config: PluginConfig) !*PluginLoader {
        const loader = try allocator.create(PluginLoader);
        errdefer allocator.destroy(loader);

        loader.* = undefined;
        loader.allocator = allocator;
        loader.install_dir = try allocator.dupe(u8, config.install_dir);
        errdefer allocator.free(loader.install_dir);

        loader.config = .{
            .registry_url = config.registry_url,
            .install_dir = loader.install_dir,
        };

        loader.loaded_plugins = std.StringHashMap(*runtime.LoadedPlugin).init(allocator);
        errdefer loader.loaded_plugins.deinit();

        loader.rope = try core.Rope.init(allocator);
        errdefer loader.rope.deinit();

        loader.highlighter = syntax.SyntaxHighlighter.init(allocator);
        errdefer loader.highlighter.deinit();

        loader.cursor_storage = .{ .line = 0, .column = 0, .byte_offset = 0 };
        loader.mode_storage = runtime.PluginAPI.EditorContext.EditorMode.normal;

        loader.editor_context = try allocator.create(runtime.PluginAPI.EditorContext);
        errdefer allocator.destroy(loader.editor_context);
        loader.editor_context.* = .{
            .rope = &loader.rope,
            .cursor_position = &loader.cursor_storage,
            .current_mode = &loader.mode_storage,
            .highlighter = &loader.highlighter,
            .active_buffer_id = 1,
        };

        loader.host_adapter = try allocator.create(PhantomPluginHost);
        errdefer allocator.destroy(loader.host_adapter);
        loader.host_adapter.* = PhantomPluginHost.init(allocator);
        errdefer loader.host_adapter.deinit();

        loader.plugin_api = try allocator.create(runtime.PluginAPI);
        errdefer allocator.destroy(loader.plugin_api);
        loader.plugin_api.* = runtime.PluginAPI.init(allocator, loader.editor_context);
        errdefer loader.plugin_api.deinit();

        var plugin_dirs = [_][]const u8{
            loader.install_dir,
            "~/.config/grim/plugins/",
        };

        loader.plugin_manager = try allocator.create(runtime.PluginManager);
        errdefer allocator.destroy(loader.plugin_manager);
        loader.plugin_manager.* = try runtime.PluginManager.init(
            allocator,
            loader.plugin_api,
            plugin_dirs[0..],
        );
        errdefer loader.plugin_manager.deinit();

        loader.runtime_loader = runtime.PluginLoader.init(allocator);
        loader.discovery = runtime.PluginDiscovery.init(allocator);
        errdefer loader.discovery.deinit();

        try loader.discovery.addSearchPath(loader.install_dir);
        if (@hasDecl(runtime.PluginDiscovery, "addDefaultPaths")) {
            try loader.discovery.addDefaultPaths();
        }

        return loader;
    }

    pub fn deinit(self: *PluginLoader) void {
        var it = self.loaded_plugins.iterator();
        while (it.next()) |entry| {
            const loaded = entry.value_ptr.*;
            self.runtime_loader.callTeardown(loaded) catch {};
            loaded.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.loaded_plugins.deinit();

        self.discovery.deinit();
        comptime {
            if (@hasDecl(runtime.PluginLoader, "deinit")) {
                self.runtime_loader.deinit();
            }
        }

        self.plugin_manager.deinit();
        self.allocator.destroy(self.plugin_manager);

        self.plugin_api.deinit();
        self.allocator.destroy(self.plugin_api);

        self.host_adapter.deinit();
        self.allocator.destroy(self.host_adapter);

        self.allocator.destroy(self.editor_context);

        self.highlighter.deinit();
        self.rope.deinit();

        self.allocator.free(self.install_dir);
        self.allocator.destroy(self);
    }

    /// Fetch a plugin from the registry
    pub fn fetchPlugin(self: *PluginLoader, name: []const u8, version: []const u8) !void {
        zlog.info("Fetching plugin: {s}@{s}", .{ name, version });

        // Construct download URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}.tar.gz", .{ self.config.registry_url, name, version });
        defer self.allocator.free(url);

        const plugin_relative = try normalizedPluginPath(self.allocator, name);
        defer self.allocator.free(plugin_relative);

        // Create plugin directory
        const plugin_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.install_dir, plugin_relative });
        defer self.allocator.free(plugin_path);

        if (try self.isPluginUpToDate(plugin_path, name, version)) {
            zlog.info("Plugin {s}@{s} already installed", .{ name, version });
            return;
        }

        errdefer std.fs.cwd().deleteTree(plugin_path) catch {};

        std.fs.cwd().deleteTree(plugin_path) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };

        try std.fs.cwd().makePath(plugin_path);

        // Download the plugin archive
        try self.downloadPlugin(url, plugin_path);

        // Extract the plugin
        try self.extractPlugin(plugin_path);

        try self.writeManifest(plugin_path, name, version);

        zlog.info("Plugin {s} fetched successfully", .{name});
    }

    /// Download plugin archive
    fn downloadPlugin(self: *PluginLoader, url: []const u8, dest_dir: []const u8) !void {
        zlog.info("Downloading from: {s}", .{url});

        // Use zhttp for simple HTTP GET
        var response = try zhttp.get(self.allocator, url);
        defer response.deinit();

        if (!response.isSuccess()) {
            zlog.err("HTTP request failed with status: {}", .{response.status});
            return error.HttpRequestFailed;
        }

        // Create destination file
        const archive_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dest_dir, "plugin.tar.gz" });
        defer self.allocator.free(archive_path);

        var file = try std.fs.cwd().createFile(archive_path, .{ .truncate = true });
        defer file.close();

        // Read response body into memory
        const body = try response.readAll(max_archive_size);
        defer self.allocator.free(body);

        // Write to file
        try file.writeAll(body);

        zlog.info("Downloaded archive to: {s}", .{archive_path});
    }

    /// Extract plugin archive into the destination directory.
    fn extractPlugin(self: *PluginLoader, plugin_dir: []const u8) !void {
        const archive_path = try std.fs.path.join(self.allocator, &[_][]const u8{ plugin_dir, "plugin.tar.gz" });
        defer self.allocator.free(archive_path);

        zlog.info("Extracting archive: {s}", .{archive_path});

        var file = try std.fs.cwd().openFile(archive_path, .{});
        defer file.close();

        var file_reader_buffer: [8 * 1024]u8 = undefined;
        var file_reader = file.reader(&file_reader_buffer);

        var gzip_buffer: [std.compress.flate.max_window_len]u8 = undefined;
        var gzip_stream = std.compress.flate.Decompress.init(&file_reader.interface, .gzip, &gzip_buffer);

        var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
        var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
        var tar_iter: tar.Iterator = .init(&gzip_stream.reader, .{
            .file_name_buffer = &file_name_buffer,
            .link_name_buffer = &link_name_buffer,
            .diagnostics = null,
        });

        var out_dir = try std.fs.cwd().openDir(plugin_dir, .{ .iterate = true, .access_sub_paths = true });
        defer out_dir.close();

        var discard_buffer: [256]u8 = undefined;

        while (try tar_iter.next()) |entry| {
            const original_name = entry.name;
            const name = trimTrailingSeparators(original_name);

            var discarding = Io.Writer.Discarding.init(&discard_buffer);

            if (!isSafeRelativePath(name)) {
                zlog.warn("Skipping unsafe archive path: {s}", .{original_name});
                try tar_iter.streamRemaining(entry, &discarding.writer);
                continue;
            }

            switch (entry.kind) {
                .directory => {
                    if (name.len != 0) {
                        try out_dir.makePath(name);
                    }
                    try tar_iter.streamRemaining(entry, &discarding.writer);
                },
                .sym_link => {
                    zlog.warn("Skipping link entry in plugin archive: {s}", .{name});
                    try tar_iter.streamRemaining(entry, &discarding.writer);
                },
                .file => {
                    if (std.fs.path.dirname(name)) |parent| {
                        if (parent.len != 0) {
                            try out_dir.makePath(parent);
                        }
                    }

                    var out_file = try out_dir.createFile(name, .{ .truncate = true });
                    defer out_file.close();

                    var file_buffer: [4 * 1024]u8 = undefined;
                    var file_writer = out_file.writer(&file_buffer);
                    try tar_iter.streamRemaining(entry, &file_writer.interface);
                    try file_writer.interface.flush();
                },
            }
        }

        std.fs.cwd().deleteFile(archive_path) catch |err| {
            zlog.warn("Failed to remove plugin archive {s}: {any}", .{ archive_path, err });
        };
    }

    fn isPluginUpToDate(self: *PluginLoader, plugin_path: []const u8, name: []const u8, version: []const u8) !bool {
        const manifest_path = try std.fs.path.join(self.allocator, &[_][]const u8{ plugin_path, manifest_file });
        defer self.allocator.free(manifest_path);

        const limit = Io.Limit.limited(max_manifest_size);
        const data = std.fs.cwd().readFileAlloc(manifest_path, self.allocator, limit) catch |err| {
            if (err == error.FileNotFound) {
                return false;
            }
            return err;
        };
        defer self.allocator.free(data);

        const parsed = try std.json.parseFromSlice(Manifest, self.allocator, data, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const manifest = parsed.value;
        return std.mem.eql(u8, manifest.name, name) and
            std.mem.eql(u8, manifest.version, version) and
            std.mem.eql(u8, manifest.registry_url, self.config.registry_url);
    }

    fn writeManifest(self: *PluginLoader, plugin_path: []const u8, name: []const u8, version: []const u8) !void {
        const manifest_path = try std.fs.path.join(self.allocator, &[_][]const u8{ plugin_path, manifest_file });
        defer self.allocator.free(manifest_path);

        const now = std.time.timestamp();

        const manifest = Manifest{
            .name = name,
            .version = version,
            .registry_url = self.config.registry_url,
            .installed_at = std.math.cast(u64, now) orelse 0,
        };

        var json_buffer = std.ArrayList(u8).empty;
        defer json_buffer.deinit(self.allocator);

        try json_buffer.append(self.allocator, '{');
        try json_buffer.appendSlice(self.allocator, "\"name\":");
        try appendJsonString(&json_buffer, self.allocator, manifest.name);
        try json_buffer.appendSlice(self.allocator, ",\"version\":");
        try appendJsonString(&json_buffer, self.allocator, manifest.version);
        try json_buffer.appendSlice(self.allocator, ",\"registry_url\":");
        try appendJsonString(&json_buffer, self.allocator, manifest.registry_url);
        try json_buffer.appendSlice(self.allocator, ",\"installed_at\":");
        try appendUnsigned(&json_buffer, self.allocator, manifest.installed_at);
        try json_buffer.append(self.allocator, '}');

        const json_text = try json_buffer.toOwnedSlice(self.allocator);
        defer self.allocator.free(json_text);

        var file = try std.fs.cwd().createFile(manifest_path, .{ .truncate = true });
        defer file.close();

        try file.writeAll(json_text);
    }

    fn isSafeRelativePath(path: []const u8) bool {
        if (path.len == 0) return false;
        if (std.fs.path.isAbsolute(path)) return false;
        if (std.mem.indexOf(u8, path, ":")) |_| return false;

        var i: usize = 0;
        while (i < path.len) : (i += 1) {
            if (path[i] == '.' and i + 1 < path.len and path[i + 1] == '.') {
                const before = if (i == 0) null else path[i - 1];
                const after = if (i + 2 < path.len) path[i + 2] else null;
                const before_sep = before == null or before == '/' or before == '\\';
                const after_sep = after == null or after == '/' or after == '\\';
                if (before_sep and after_sep) return false;
            }
        }

        return true;
    }

    fn trimTrailingSeparators(path: []const u8) []const u8 {
        var end = path.len;
        while (end > 0) : (end -= 1) {
            const ch = path[end - 1];
            if (ch != '/' and ch != '\\') break;
        }
        return path[0..end];
    }

    fn normalizedPluginPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        var buffer = try allocator.alloc(u8, name.len);
        for (name, 0..) |ch, idx| {
            buffer[idx] = switch (ch) {
                '.' => '/',
                '\\' => '/',
                else => ch,
            };
        }
        return buffer;
    }

    const manifest_file = "manifest.json";
    const max_manifest_size: usize = 64 * 1024;
    const max_archive_size: usize = 20 * 1024 * 1024;

    const Manifest = struct {
        name: []const u8,
        version: []const u8,
        registry_url: []const u8,
        installed_at: u64,
    };
    /// Load all installed plugin modules into the Ghostlang runtime.
    pub fn loadInstalled(self: *PluginLoader) !void {
        var discovered = try self.discovery.discoverAll();
        defer discovered.deinit(self.allocator);

        runtime.PluginDiscovery.sortByPriority(&discovered);
        try runtime.PluginDiscovery.checkDependencies(discovered.items);

        var loaded_count: usize = 0;

        for (discovered.items) |*entry| {
            self.loadDiscovered(entry) catch |err| {
                zlog.err("Failed to load plugin {s}: {any}", .{ entry.name, err });
                continue;
            };
            loaded_count += 1;
        }

        zlog.info("Loaded {d} plugins from discovery", .{loaded_count});
    }

    /// Load a single plugin module by path (absolute or relative to install directory).
    pub fn loadPlugin(self: *PluginLoader, plugin_path: []const u8) !void {
        const resolved_path = try self.resolvePluginPath(plugin_path);
        defer self.allocator.free(resolved_path);

        var discovered = try self.discovery.discoverAll();
        defer discovered.deinit(self.allocator);

        runtime.PluginDiscovery.sortByPriority(&discovered);
        try runtime.PluginDiscovery.checkDependencies(discovered.items);

        for (discovered.items) |*entry| {
            if (std.mem.eql(u8, entry.path, resolved_path)) {
                try self.loadDiscovered(entry);
                return;
            }
        }

        return error.PluginNotFound;
    }

    fn loadDiscovered(self: *PluginLoader, entry: *plugin_discovery.DiscoveredPlugin) !void {
        const loaded_value = try self.runtime_loader.load(entry, &self.plugin_manager.ghostlang_host);

        const loaded = try self.allocator.create(runtime.LoadedPlugin);
        loaded.* = loaded_value;

        errdefer {
            self.runtime_loader.callTeardown(loaded) catch {};
            loaded.deinit();
            self.allocator.destroy(loaded);
        }

        const callbacks = self.host_adapter.callbacks();
        try self.runtime_loader.callSetup(loaded, callbacks);

        if (self.loaded_plugins.fetchRemove(entry.name)) |previous| {
            self.runtime_loader.callTeardown(previous.value) catch {};
            previous.value.deinit();
            self.allocator.free(previous.key);
        }

        const key = try self.allocator.dupe(u8, entry.name);
        errdefer self.allocator.free(key);

        try self.loaded_plugins.put(key, loaded);
        zlog.info("Plugin loaded: {s}", .{entry.name});
    }

    fn resolvePluginPath(self: *PluginLoader, plugin_path: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(plugin_path)) {
            return try self.allocator.dupe(u8, plugin_path);
        }

        return std.fs.path.join(self.allocator, &[_][]const u8{ self.install_dir, plugin_path });
    }

    fn relativePathToModuleName(self: *PluginLoader, relative_path: []const u8) ![]u8 {
        if (!std.mem.endsWith(u8, relative_path, ".gza")) {
            return error.InvalidPluginPath;
        }

        const stem_len = relative_path.len - ".gza".len;
        const prefix = "plugins.";
        const total_len = prefix.len + stem_len;
        var buffer = try self.allocator.alloc(u8, total_len);

        std.mem.copyForwards(u8, buffer[0..prefix.len], prefix);

        var i: usize = 0;
        while (i < stem_len) : (i += 1) {
            const ch = relative_path[i];
            buffer[prefix.len + i] = switch (ch) {
                '/', '\\' => '.',
                else => ch,
            };
        }

        return buffer;
    }
};

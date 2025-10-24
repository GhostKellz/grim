//! core/ghostlang_runtime.zig
//! Integration layer for Ghostlang scripting engine

const std = @import("std");
const ghostlang = @import("ghostlang");
const zlog = @import("zlog");
const flare = @import("flare");

pub const GhostlangRuntime = struct {
    allocator: std.mem.Allocator,
    engine: ghostlang.ScriptEngine,
    config_manager: *flare.Config,
    config_dir: []const u8,
    loaded_modules: std.StringHashMap(void),
    next_keymap_id: usize = 0,
    next_autocmd_id: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config_manager: *flare.Config, config_dir: []const u8) !GhostlangRuntime {
        const engine_config = ghostlang.EngineConfig{
            .allocator = allocator,
            // TODO: Configure sandboxing options
            .allow_io = true, // Allow for plugin loading
            .allow_syscalls = false, // Keep sandboxed
            .deterministic = false, // Allow timing-dependent operations
            .memory_limit = 10 * 1024 * 1024, // 10MB limit
            .execution_timeout_ms = 5000, // 5 second timeout
        };

        var engine = try ghostlang.ScriptEngine.create(engine_config);

        // Register built-in functions
        try engine.registerFunction("print", printFunc);
        try engine.registerFunction("set", setOptionFunc);
        try engine.registerFunction("map", mapKeyFunc);
        try engine.registerFunction("autocmd", autocmdFunc);
        try engine.registerFunction("require", requireFunc);

        return GhostlangRuntime{
            .allocator = allocator,
            .engine = engine,
            .config_manager = config_manager,
            .config_dir = config_dir,
            .loaded_modules = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *GhostlangRuntime) void {
        var it = self.loaded_modules.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.loaded_modules.deinit();
        self.engine.deinit();
    }

    /// Load and execute a .gza configuration file
    pub fn loadConfigFile(self: *GhostlangRuntime, file_path: []const u8) !void {
        zlog.info("Loading config file: {s}", .{file_path});

        // Read the file
        const source = try std.fs.cwd().readFileAlloc(file_path, self.allocator, std.Io.Limit.unlimited);
        defer self.allocator.free(source);

        // Load and execute the script
        var script = try self.engine.loadScript(source);
        defer script.deinit();

        const previous = active_runtime;
        active_runtime = self;
        defer active_runtime = previous;

        const result = try script.run();
        _ = result; // TODO: Handle return values

        zlog.info("Config file loaded successfully: {s}", .{file_path});
    }

    /// Execute a Ghostlang code snippet
    pub fn executeCode(self: *GhostlangRuntime, code: []const u8) !ghostlang.ScriptValue {
        var script = try self.engine.loadScript(code);
        defer script.deinit();

        const previous = active_runtime;
        active_runtime = self;
        defer active_runtime = previous;

        return try script.run();
    }

    /// Call a function defined in loaded scripts
    pub fn callFunction(self: *GhostlangRuntime, name: []const u8, args: anytype) !ghostlang.ScriptValue {
        const previous = active_runtime;
        active_runtime = self;
        defer active_runtime = previous;

        return try self.engine.call(name, args);
    }

    /// Execute a snippet and duplicate the resulting string (if any).
    pub fn evalStringDup(self: *GhostlangRuntime, code: []const u8) !?[]u8 {
        const value = try self.executeCode(code);
        const string_value = scriptValueToString(value) orelse return null;
        return try self.allocator.dupe(u8, string_value);
    }

    /// Retrieve the current statusline text rendered by the Ghostlang plugin layer.
    pub fn statuslineCurrent(self: *GhostlangRuntime) !?[]u8 {
        const snippet =
            "local status = require(\"plugins.core.statusline\")\n" ++
            "if status and status.refresh then status.refresh({}) end\n" ++
            "if status and status.current then return status.current() end\n" ++
            "return nil";

        return try self.evalStringDup(snippet);
    }

    /// Retrieve a newline-separated listing of the file tree.
    pub fn fileTreeListing(self: *GhostlangRuntime) !?[]u8 {
        const snippet =
            "local tree = require(\"plugins.core.file-tree\")\n" ++
            "if not tree then return nil end\n" ++
            "if tree.open then tree.open() end\n" ++
            "if tree.nodes then\n" ++
            "  local nodes = tree.nodes()\n" ++
            "  if type(nodes) == \"table\" and #nodes > 0 then\n" ++
            "    return table.concat(nodes, \"\\n\")\n" ++
            "  end\n" ++
            "end\n" ++
            "return nil";

        return try self.evalStringDup(snippet);
    }

    /// Retrieve newline-separated fuzzy finder results (files list).
    pub fn fuzzyFinderListing(self: *GhostlangRuntime, query: []const u8) !?[]u8 {
        const escaped_query = try escapeGhostlangString(self.allocator, query);
        defer self.allocator.free(escaped_query);

        const snippet = try std.mem.concat(self.allocator, u8, &[_][]const u8{
            "local fuzzy = require(\"plugins.core.fuzzy-finder\")\n",
            "if not fuzzy then return nil end\n",
            "local results = fuzzy.find_files({ query = \"",
            escaped_query,
            "\" })\n",
            "if type(results) ~= \"table\" or #results == 0 then return nil end\n",
            "local lines = {}\n",
            "for _, entry in ipairs(results) do\n",
            "  if type(entry) == \"table\" and entry.path then\n",
            "    table.insert(lines, entry.path)\n",
            "  elseif type(entry) == \"string\" then\n",
            "    table.insert(lines, entry)\n",
            "  end\n",
            "end\n",
            "if #lines == 0 then return nil end\n",
            "return table.concat(lines, \"\\n\")",
        });
        defer self.allocator.free(snippet);

        return try self.evalStringDup(snippet);
    }

    pub fn fuzzyFinderDecoratedListing(self: *GhostlangRuntime, query: []const u8) !?[]u8 {
        const escaped_query = try escapeGhostlangString(self.allocator, query);
        defer self.allocator.free(escaped_query);

        const snippet = try std.mem.concat(self.allocator, u8, &[_][]const u8{
            "local fuzzy = require(\"plugins.core.fuzzy-finder\")\n",
            "if not fuzzy or not fuzzy.render_listing then return nil end\n",
            "return fuzzy.render_listing({ query = \"",
            escaped_query,
            "\" })",
        });
        defer self.allocator.free(snippet);

        return try self.evalStringDup(snippet);
    }

    /// Retrieve newline-separated highlight entries for a buffer via treesitter plugin.
    pub fn treesitterHighlightListing(self: *GhostlangRuntime, path: []const u8, content: []const u8) !?[]u8 {
        const escaped_path = try escapeGhostlangString(self.allocator, path);
        defer self.allocator.free(escaped_path);

        const escaped_content = try escapeGhostlangString(self.allocator, content);
        defer self.allocator.free(escaped_content);

        const snippet = try std.fmt.allocPrint(
            self.allocator,
            "local tree = require(\"plugins.core.treesitter\")\n" ++
                "if not tree or not tree.highlight_buffer then return nil end\n" ++
                "return tree.highlight_buffer({{ path = \"{s}\", content = \"{s}\" }})",
            .{ escaped_path, escaped_content },
        );
        defer self.allocator.free(snippet);

        return try self.evalStringDup(snippet);
    }
};

var active_runtime: ?*GhostlangRuntime = null;

fn getActiveRuntimeFor(name: []const u8) ?*GhostlangRuntime {
    if (active_runtime) |runtime| {
        return runtime;
    }
    zlog.err("{s} called without active runtime context", .{name});
    return null;
}

fn scriptValueToString(value: ghostlang.ScriptValue) ?[]const u8 {
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn scriptValueToFlareValue(value: ghostlang.ScriptValue) ?flare.Value {
    const max_safe_int: f64 = 9007199254740991.0; // 2^53 - 1

    return switch (value) {
        .nil => flare.Value{ .null_value = {} },
        .boolean => |b| flare.Value{ .bool_value = b },
        .number => |n| blk: {
            const floored = std.math.floor(n);
            if (floored == n and n >= -max_safe_int and n <= max_safe_int) {
                const as_int: i64 = @intFromFloat(n);
                break :blk flare.Value{ .int_value = as_int };
            }
            break :blk flare.Value{ .float_value = n };
        },
        .string => |s| flare.Value{ .string_value = s },
        else => null,
    };
}

fn storeConfigValue(runtime: *GhostlangRuntime, key: []const u8, value: flare.Value) void {
    runtime.config_manager.setValue(key, value) catch |err| {
        zlog.err("Failed to set config key {s}: {any}", .{ key, err });
    };
}

fn storeIndexedField(runtime: *GhostlangRuntime, prefix: []const u8, index: usize, field: []const u8, value: flare.Value) void {
    const key = std.fmt.allocPrint(runtime.allocator, "{s}.{d}.{s}", .{ prefix, index, field }) catch {
        zlog.err("Failed to allocate config key for {s}.{d}.{s}", .{ prefix, index, field });
        return;
    };
    defer runtime.allocator.free(key);
    storeConfigValue(runtime, key, value);
}

fn setCounter(runtime: *GhostlangRuntime, prefix: []const u8, count: usize) void {
    const key = std.fmt.allocPrint(runtime.allocator, "{s}.count", .{prefix}) catch {
        zlog.err("Failed to allocate config counter key for {s}", .{prefix});
        return;
    };
    defer runtime.allocator.free(key);
    const count_i64: i64 = @intCast(count);
    storeConfigValue(runtime, key, flare.Value{ .int_value = count_i64 });
}

fn moduleNameToRelativePath(allocator: std.mem.Allocator, module_name: []const u8) ![]u8 {
    const suffix = ".gza";
    var buffer = try allocator.alloc(u8, module_name.len + suffix.len);
    var i: usize = 0;
    while (i < module_name.len) : (i += 1) {
        buffer[i] = if (module_name[i] == '.') '/' else module_name[i];
    }
    std.mem.copyForwards(u8, buffer[module_name.len .. module_name.len + suffix.len], suffix);
    return buffer;
}

fn escapeGhostlangString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return allocator.alloc(u8, 0);

    const max_len = std.math.mul(usize, input.len, 2) catch return error.OutOfMemory;
    var buffer = try allocator.alloc(u8, max_len);
    var index: usize = 0;

    for (input) |byte| {
        switch (byte) {
            '"' => {
                buffer[index] = '\\';
                buffer[index + 1] = '"';
                index += 2;
            },
            '\\' => {
                buffer[index] = '\\';
                buffer[index + 1] = '\\';
                index += 2;
            },
            '\n' => {
                buffer[index] = '\\';
                buffer[index + 1] = 'n';
                index += 2;
            },
            '\r' => {
                buffer[index] = '\\';
                buffer[index + 1] = 'r';
                index += 2;
            },
            '\t' => {
                buffer[index] = '\\';
                buffer[index + 1] = 't';
                index += 2;
            },
            else => {
                buffer[index] = byte;
                index += 1;
            },
        }
    }

    return buffer[0..index];
}

fn resolveModulePath(runtime: *GhostlangRuntime, relative: []const u8) ![]u8 {
    const direct = try std.fs.path.join(runtime.allocator, &[_][]const u8{ runtime.config_dir, relative });
    if (std.fs.cwd().access(direct, .{})) {
        return direct;
    } else |err| {
        runtime.allocator.free(direct);
        if (err != error.FileNotFound) {
            return err;
        }
    }

    const fallback_dirs = [_][]const u8{
        "runtime/lib",
        "runtime/defaults",
        "lua/user",
    };

    for (fallback_dirs) |dir| {
        const path = try std.fs.path.join(runtime.allocator, &[_][]const u8{ runtime.config_dir, dir, relative });
        if (std.fs.cwd().access(path, .{})) {
            return path;
        } else |err| {
            runtime.allocator.free(path);
            if (err != error.FileNotFound) {
                return err;
            }
        }
    }

    return error.ModuleNotFound;
}

// Built-in functions available to Ghostlang scripts

fn printFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    for (args) |arg| {
        switch (arg) {
            .string => |s| std.debug.print("{s}", .{s}),
            .number => |n| std.debug.print("{}", .{n}),
            .boolean => |b| std.debug.print("{}", .{b}),
            else => std.debug.print("{any}", .{arg}),
        }
        std.debug.print(" ", .{});
    }
    std.debug.print("\n", .{});
    return ghostlang.ScriptValue{ .nil = {} };
}

fn setOptionFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const runtime = getActiveRuntimeFor("set") orelse return ghostlang.ScriptValue{ .nil = {} };

    if (args.len < 2) {
        zlog.warn("set() requires at least 2 arguments", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    }

    const key = scriptValueToString(args[0]) orelse {
        zlog.warn("set() key must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };

    if (scriptValueToFlareValue(args[1])) |value| {
        storeConfigValue(runtime, key, value);
    } else {
        zlog.warn("set() unsupported value type for key {s}", .{key});
    }

    return ghostlang.ScriptValue{ .nil = {} };
}

fn mapKeyFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const runtime = getActiveRuntimeFor("map") orelse return ghostlang.ScriptValue{ .nil = {} };

    if (args.len < 3) {
        zlog.warn("map() requires 3 arguments: mode, key, command", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    }

    const mode = scriptValueToString(args[0]) orelse {
        zlog.warn("map() mode must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };
    const lhs = scriptValueToString(args[1]) orelse {
        zlog.warn("map() key must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };
    const rhs = scriptValueToString(args[2]) orelse {
        zlog.warn("map() command must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };

    const index = runtime.next_keymap_id;
    runtime.next_keymap_id += 1;

    storeIndexedField(runtime, "keymaps", index, "mode", flare.Value{ .string_value = mode });
    storeIndexedField(runtime, "keymaps", index, "lhs", flare.Value{ .string_value = lhs });
    storeIndexedField(runtime, "keymaps", index, "rhs", flare.Value{ .string_value = rhs });

    if (args.len >= 4) {
        if (scriptValueToString(args[3])) |desc| {
            storeIndexedField(runtime, "keymaps", index, "desc", flare.Value{ .string_value = desc });
        } else if (args[3] != .nil) {
            zlog.warn("map() optional description must be a string", .{});
        }
    }

    setCounter(runtime, "keymaps", runtime.next_keymap_id);
    return ghostlang.ScriptValue{ .nil = {} };
}

fn autocmdFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const runtime = getActiveRuntimeFor("autocmd") orelse return ghostlang.ScriptValue{ .nil = {} };

    if (args.len < 3) {
        zlog.warn("autocmd() requires at least 3 arguments: event, pattern, command", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    }

    const event = scriptValueToString(args[0]) orelse {
        zlog.warn("autocmd() event must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };
    const pattern = scriptValueToString(args[1]) orelse {
        zlog.warn("autocmd() pattern must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };
    const command = scriptValueToString(args[2]) orelse {
        zlog.warn("autocmd() command must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };

    const index = runtime.next_autocmd_id;
    runtime.next_autocmd_id += 1;

    storeIndexedField(runtime, "autocmds", index, "event", flare.Value{ .string_value = event });
    storeIndexedField(runtime, "autocmds", index, "pattern", flare.Value{ .string_value = pattern });
    storeIndexedField(runtime, "autocmds", index, "command", flare.Value{ .string_value = command });

    setCounter(runtime, "autocmds", runtime.next_autocmd_id);
    return ghostlang.ScriptValue{ .nil = {} };
}

fn requireFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const runtime = getActiveRuntimeFor("require") orelse return ghostlang.ScriptValue{ .nil = {} };

    if (args.len < 1) {
        zlog.warn("require() requires 1 argument: module name", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    }

    const module_name = scriptValueToString(args[0]) orelse {
        zlog.warn("require() module name must be a string", .{});
        return ghostlang.ScriptValue{ .nil = {} };
    };

    if (runtime.loaded_modules.contains(module_name)) {
        return ghostlang.ScriptValue{ .nil = {} };
    }

    const relative = moduleNameToRelativePath(runtime.allocator, module_name) catch {
        zlog.err("require(): failed to build path for module {s}", .{module_name});
        return ghostlang.ScriptValue{ .nil = {} };
    };
    defer runtime.allocator.free(relative);

    const full_path = resolveModulePath(runtime, relative) catch |err| {
        switch (err) {
            error.ModuleNotFound => {
                zlog.err("require(): module {s} not found", .{module_name});
            },
            else => {
                zlog.err("require(): failed to resolve module {s}: {any}", .{ module_name, err });
            },
        }
        return ghostlang.ScriptValue{ .nil = {} };
    };
    defer runtime.allocator.free(full_path);

    runtime.loadConfigFile(full_path) catch |err| {
        zlog.err("require(): failed to load module {s}: {any}", .{ module_name, err });
        return ghostlang.ScriptValue{ .nil = {} };
    };

    const module_key = runtime.allocator.dupe(u8, module_name) catch {
        zlog.err("require(): failed to cache module name {s}", .{module_name});
        return ghostlang.ScriptValue{ .nil = {} };
    };
    errdefer runtime.allocator.free(module_key);

    const gop = runtime.loaded_modules.getOrPut(module_key) catch {
        zlog.err("require(): failed to record module {s}", .{module_name});
        return ghostlang.ScriptValue{ .nil = {} };
    };
    if (gop.found_existing) {
        runtime.allocator.free(module_key);
    } else {
        gop.value_ptr.* = {};
    }

    return ghostlang.ScriptValue{ .nil = {} };
}

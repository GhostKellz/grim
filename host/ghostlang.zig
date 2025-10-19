const std = @import("std");
const ghostlang = @import("ghostlang");
const ai = @import("ai");

threadlocal var active_host: ?*Host = null;

fn builtinShowMessage(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (active_host) |host| {
        host.handleShowMessageBuiltin(args);
    }
    return .{ .nil = {} };
}

fn getMandatoryStringArg(host: *Host, args: []const ghostlang.ScriptValue, idx: usize) ?[]const u8 {
    if (idx >= args.len) {
        host.recordScriptError(Host.Error.InvalidScript);
        return null;
    }
    const value = args[idx];
    if (value != .string) {
        host.recordScriptError(Host.Error.InvalidScript);
        return null;
    }
    return value.string;
}

fn getOptionalStringArg(host: *Host, args: []const ghostlang.ScriptValue, idx: usize) ?[]const u8 {
    if (idx >= args.len) return null;
    const value = args[idx];
    if (value == .string) {
        return value.string;
    }
    host.recordScriptError(Host.Error.InvalidScript);
    return null;
}

fn builtinRegisterCommand(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .nil = {} };
    const plugin = host.active_plugin orelse {
        host.recordScriptError(Host.Error.InvalidScript);
        return .{ .nil = {} };
    };

    const name = getMandatoryStringArg(host, args, 0) orelse return .{ .nil = {} };
    const handler = getMandatoryStringArg(host, args, 1) orelse return .{ .nil = {} };
    const description = getOptionalStringArg(host, args, 2);

    plugin.appendRegisterCommand(name, handler, description) catch |err| switch (err) {
        error.OutOfMemory => host.recordScriptError(Host.Error.MemoryLimitExceeded),
    };

    return .{ .nil = {} };
}

fn builtinRegisterKeymap(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .nil = {} };
    const plugin = host.active_plugin orelse {
        host.recordScriptError(Host.Error.InvalidScript);
        return .{ .nil = {} };
    };

    const keys = getMandatoryStringArg(host, args, 0) orelse return .{ .nil = {} };
    const handler = getMandatoryStringArg(host, args, 1) orelse return .{ .nil = {} };
    const mode = getOptionalStringArg(host, args, 2);
    const description = getOptionalStringArg(host, args, 3);

    plugin.appendRegisterKeymap(keys, handler, mode, description) catch |err| switch (err) {
        error.OutOfMemory => host.recordScriptError(Host.Error.MemoryLimitExceeded),
    };

    return .{ .nil = {} };
}

fn builtinRegisterEventHandler(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .nil = {} };
    const plugin = host.active_plugin orelse {
        host.recordScriptError(Host.Error.InvalidScript);
        return .{ .nil = {} };
    };

    const event = getMandatoryStringArg(host, args, 0) orelse return .{ .nil = {} };
    const handler = getMandatoryStringArg(host, args, 1) orelse return .{ .nil = {} };

    plugin.appendRegisterEventHandler(event, handler) catch |err| switch (err) {
        error.OutOfMemory => host.recordScriptError(Host.Error.MemoryLimitExceeded),
    };

    return .{ .nil = {} };
}

fn builtinRegisterTheme(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .nil = {} };
    const plugin = host.active_plugin orelse {
        host.recordScriptError(Host.Error.InvalidScript);
        return .{ .nil = {} };
    };

    const name = getMandatoryStringArg(host, args, 0) orelse return .{ .nil = {} };
    const colors = getMandatoryStringArg(host, args, 1) orelse return .{ .nil = {} };

    plugin.appendRegisterTheme(name, colors) catch |err| switch (err) {
        error.OutOfMemory => host.recordScriptError(Host.Error.MemoryLimitExceeded),
    };

    return .{ .nil = {} };
}

// Reaper AI integration builtins

fn builtinReaperComplete(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .string = "error: no active host" };

    // Parse arguments: reaper_complete(prompt, language, [provider])
    const prompt = getMandatoryStringArg(host, args, 0) orelse return .{ .string = "error: missing prompt" };
    const language = getMandatoryStringArg(host, args, 1) orelse return .{ .string = "error: missing language" };
    const provider = getOptionalStringArg(host, args, 2);

    // Get or init reaper client
    const client = ai.reaper_client.getOrInitClient(host.allocator) catch |err| {
        var buf: [128]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&buf, "error: failed to init reaper client: {s}", .{@errorName(err)}) catch "error: failed to init client";
        return .{ .string = error_msg };
    };

    // Make completion request
    const request = ai.reaper_client.CompletionRequest{
        .prompt = prompt,
        .language = language,
        .provider = provider,
    };

    const response = client.complete(request) catch |err| {
        var buf: [128]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&buf, "error: completion failed: {s}", .{@errorName(err)}) catch "error: completion failed";
        return .{ .string = error_msg };
    };

    if (!response.success) {
        return .{ .string = response.error_message orelse "error: completion failed" };
    }

    return .{ .string = response.text };
}

fn builtinReaperChat(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .string = "error: no active host" };

    const message = getMandatoryStringArg(host, args, 0) orelse return .{ .string = "error: missing message" };
    const provider = getOptionalStringArg(host, args, 1);

    const client = ai.reaper_client.getOrInitClient(host.allocator) catch |err| {
        var buf: [128]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&buf, "error: failed to init reaper client: {s}", .{@errorName(err)}) catch "error: failed to init client";
        return .{ .string = error_msg };
    };

    const request = ai.reaper_client.ChatRequest{
        .message = message,
        .provider = provider,
    };

    const response = client.chat(request) catch |err| {
        var buf: [128]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&buf, "error: chat failed: {s}", .{@errorName(err)}) catch "error: chat failed";
        return .{ .string = error_msg };
    };

    if (!response.success) {
        return .{ .string = response.error_message orelse "error: chat failed" };
    }

    return .{ .string = response.message };
}

fn builtinReaperAgentic(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .string = "error: no active host" };

    const task = getMandatoryStringArg(host, args, 0) orelse return .{ .string = "error: missing task" };
    const provider = getOptionalStringArg(host, args, 1);

    const client = ai.reaper_client.getOrInitClient(host.allocator) catch |err| {
        var buf: [128]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&buf, "error: failed to init reaper client: {s}", .{@errorName(err)}) catch "error: failed to init client";
        return .{ .string = error_msg };
    };

    const request = ai.reaper_client.AgenticRequest{
        .task = task,
        .provider = provider,
    };

    const response = client.agentic(request) catch |err| {
        var buf: [128]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&buf, "error: agentic task failed: {s}", .{@errorName(err)}) catch "error: agentic task failed";
        return .{ .string = error_msg };
    };

    if (!response.success) {
        return .{ .string = response.error_message orelse "error: agentic task failed" };
    }

    return .{ .string = response.result };
}

// Native FFI bridge for hybrid plugins
// Allows Ghostlang to call native functions with C calling convention
fn builtinCallNative(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    const host = active_host orelse return .{ .string = "error: no active host" };
    const native_lib = host.active_native_library orelse {
        return .{ .string = "error: no native library loaded" };
    };

    // First arg: function name (string)
    const function_name = getMandatoryStringArg(host, args, 0) orelse {
        return .{ .string = "error: missing function name" };
    };

    // Remaining args: passed to native function
    const native_args = if (args.len > 1) args[1..] else &[_]ghostlang.ScriptValue{};

    // Convert function name to null-terminated string
    var fn_name_buf: [256]u8 = undefined;
    const fn_name_z = std.fmt.bufPrintZ(&fn_name_buf, "{s}", .{function_name}) catch {
        return .{ .string = "error: function name too long" };
    };

    // Look up the native function
    // For now, we support simple string → string functions
    // Format: fn nativeFunctionName(arg: [*:0]const u8) callconv(.c) [*:0]const u8
    const NativeFn = *const fn (arg: [*:0]const u8) callconv(.c) [*:0]const u8;
    const native_fn = native_lib.lookup(NativeFn, fn_name_z) orelse {
        var buf: [256]u8 = undefined;
        const error_msg = std.fmt.bufPrint(&buf, "error: native function not found: {s}", .{function_name}) catch "error: function not found";
        return .{ .string = error_msg };
    };

    // Convert first Ghostlang arg to C string
    const arg_str = if (native_args.len > 0 and native_args[0] == .string)
        native_args[0].string
    else
        "";

    // Allocate null-terminated string for C
    var buf: [4096]u8 = undefined;
    const c_str = std.fmt.bufPrintZ(&buf, "{s}", .{arg_str}) catch {
        return .{ .string = "error: argument too long" };
    };

    // Call native function
    const result_ptr = native_fn(c_str.ptr);
    const result_str = std.mem.span(result_ptr);

    return .{ .string = result_str };
}

pub const Host = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    config_dir: ?[]const u8,
    config_source: ?[]const u8,
    setup_invoked: bool,
    sandbox_config: SandboxConfig,
    execution_stats: ExecutionStats,
    engine: ?*ghostlang.ScriptEngine,
    config_script: ?*ghostlang.Script,
    active_plugin: ?*Self.CompiledPlugin,
    active_native_library: ?*std.DynLib,  // For hybrid plugins
    pending_error: ?Error,
    builtins_registered: bool,

    pub const Error = error{
        ConfigNotLoaded,
        SetupSymbolMissing,
        SandboxViolation,
        ExecutionTimeout,
        MemoryLimitExceeded,
        UnauthorizedFileAccess,
        UnauthorizedNetworkAccess,
        InvalidConfig,
        InvalidScript,
    } || std.fs.Dir.OpenError || std.fs.File.OpenError || std.fs.File.ReadError || std.mem.Allocator.Error;

    pub const SandboxConfig = struct {
        max_execution_time_ms: u64 = 5000,
        max_memory_bytes: usize = 50 * 1024 * 1024, // 50MB
        max_file_operations: u32 = 100,
        max_network_requests: u32 = 0, // Disabled by default
        allowed_file_patterns: []const []const u8 = &.{},
        blocked_file_patterns: []const []const u8 = &.{
            "/etc/*", "/sys/*", "/proc/*", "/dev/*", "/root/*",
        },
        enable_filesystem_access: bool = true,
        enable_network_access: bool = false,
        enable_system_calls: bool = false,
    };

    pub const ExecutionStats = struct {
        execution_count: u64 = 0,
        total_execution_time_ms: u64 = 0,
        peak_memory_usage: usize = 0,
        file_operations_count: u32 = 0,
        network_requests_count: u32 = 0,
        sandbox_violations: u32 = 0,
        last_execution_time: i64 = 0,

        pub fn reset(self: *ExecutionStats) void {
            self.* = .{};
        }
    };

    pub const CommandAction = struct {
        name: []u8,
        handler: []u8,
        description: ?[]u8,
    };

    pub const KeymapAction = struct {
        keys: []u8,
        handler: []u8,
        mode: ?[]u8,
        description: ?[]u8,
    };

    pub const EventAction = struct {
        event: []u8,
        handler: []u8,
    };

    pub const ThemeAction = struct {
        name: []u8,
        colors: []u8,
    };

    const Action = union(enum) {
        show_message: []u8,
        register_command: CommandAction,
        register_keymap: KeymapAction,
        register_event_handler: EventAction,
        register_theme: ThemeAction,
    };

    pub const ActionCallbacks = struct {
        ctx: *anyopaque,
        show_message: *const fn (ctx: *anyopaque, message: []const u8) anyerror!void,
        register_command: ?*const fn (ctx: *anyopaque, action: *const CommandAction) anyerror!void = null,
        register_keymap: ?*const fn (ctx: *anyopaque, action: *const KeymapAction) anyerror!void = null,
        register_event_handler: ?*const fn (ctx: *anyopaque, action: *const EventAction) anyerror!void = null,
        register_theme: ?*const fn (ctx: *anyopaque, action: *const ThemeAction) anyerror!void = null,
    };

    pub const CompiledPlugin = struct {
        allocator: std.mem.Allocator,
        host: *Host,
        script: *ghostlang.Script,
        actions: std.ArrayList(Action),

        pub fn deinit(self: *CompiledPlugin) void {
            self.clearActions();
            self.actions.deinit(self.allocator);
            self.script.deinit();
            self.allocator.destroy(self.script);
        }

        pub fn executeSetup(self: *CompiledPlugin, callbacks: ActionCallbacks) Error!void {
            const engine = try self.host.ensureEngine();
            try self.host.ensureHostBuiltins(engine);

            self.clearActions();

            const start_time = self.host.startExecution();
            var end_called = false;
            defer if (!end_called) self.host.endExecution(start_time) catch {};

            self.host.pending_error = null;
            const prev_host = active_host;
            active_host = self.host;
            defer active_host = prev_host;

            const prev_plugin = self.host.active_plugin;
            self.host.active_plugin = self;
            defer self.host.active_plugin = prev_plugin;

            _ = self.script.run() catch |err| {
                return self.host.mapExecutionError(err);
            };

            if (self.host.pending_error) |err| {
                self.host.pending_error = null;
                return err;
            }

            var idx: usize = 0;
            while (idx < self.actions.items.len) : (idx += 1) {
                const action_ptr = &self.actions.items[idx];
                switch (action_ptr.*) {
                    .show_message => |msg| callbacks.show_message(callbacks.ctx, msg) catch |err| {
                        std.log.err("Plugin show_message callback failed: {}", .{err});
                        return Host.Error.Unexpected;
                    },
                    .register_command => |*cmd| {
                        if (callbacks.register_command) |cb| {
                            cb(callbacks.ctx, cmd) catch |err| {
                                std.log.err("Plugin register_command callback failed: {}", .{err});
                                return Host.Error.Unexpected;
                            };
                        }
                    },
                    .register_keymap => |*km| {
                        if (callbacks.register_keymap) |cb| {
                            cb(callbacks.ctx, km) catch |err| {
                                std.log.err("Plugin register_keymap callback failed: {}", .{err});
                                return Host.Error.Unexpected;
                            };
                        }
                    },
                    .register_event_handler => |*ev| {
                        if (callbacks.register_event_handler) |cb| {
                            cb(callbacks.ctx, ev) catch |err| {
                                std.log.err("Plugin register_event_handler callback failed: {}", .{err});
                                return Host.Error.Unexpected;
                            };
                        }
                    },
                    .register_theme => |*theme| {
                        if (callbacks.register_theme) |cb| {
                            cb(callbacks.ctx, theme) catch |err| {
                                std.log.err("Plugin register_theme callback failed: {}", .{err});
                                return Host.Error.Unexpected;
                            };
                        }
                    },
                }
            }

            try self.host.endExecution(start_time);
            end_called = true;
            self.host.setup_invoked = true;
        }

        fn appendShowMessage(self: *CompiledPlugin, message: []const u8) !void {
            const copy = try self.allocator.dupe(u8, message);
            errdefer self.allocator.free(copy);
            try self.actions.append(self.allocator, .{ .show_message = copy });
        }

        fn appendRegisterCommand(
            self: *CompiledPlugin,
            name: []const u8,
            handler: []const u8,
            description: ?[]const u8,
        ) !void {
            const name_copy = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(name_copy);
            const handler_copy = try self.allocator.dupe(u8, handler);
            errdefer self.allocator.free(handler_copy);

            var description_copy: ?[]u8 = null;
            if (description) |desc| {
                if (desc.len > 0) {
                    description_copy = try self.allocator.dupe(u8, desc);
                }
            }
            errdefer if (description_copy) |desc| self.allocator.free(desc);

            try self.actions.append(self.allocator, .{ .register_command = .{
                .name = name_copy,
                .handler = handler_copy,
                .description = description_copy,
            } });
        }

        fn appendRegisterKeymap(
            self: *CompiledPlugin,
            keys: []const u8,
            handler: []const u8,
            mode: ?[]const u8,
            description: ?[]const u8,
        ) !void {
            const keys_copy = try self.allocator.dupe(u8, keys);
            errdefer self.allocator.free(keys_copy);
            const handler_copy = try self.allocator.dupe(u8, handler);
            errdefer self.allocator.free(handler_copy);

            var mode_copy: ?[]u8 = null;
            if (mode) |m| {
                if (m.len > 0) {
                    mode_copy = try self.allocator.dupe(u8, m);
                }
            }
            errdefer if (mode_copy) |m| self.allocator.free(m);

            var description_copy: ?[]u8 = null;
            if (description) |desc| {
                if (desc.len > 0) {
                    description_copy = try self.allocator.dupe(u8, desc);
                }
            }
            errdefer if (description_copy) |desc| self.allocator.free(desc);

            try self.actions.append(self.allocator, .{ .register_keymap = .{
                .keys = keys_copy,
                .handler = handler_copy,
                .mode = mode_copy,
                .description = description_copy,
            } });
        }

        fn appendRegisterEventHandler(
            self: *CompiledPlugin,
            event: []const u8,
            handler: []const u8,
        ) !void {
            const event_copy = try self.allocator.dupe(u8, event);
            errdefer self.allocator.free(event_copy);
            const handler_copy = try self.allocator.dupe(u8, handler);
            errdefer self.allocator.free(handler_copy);

            try self.actions.append(self.allocator, .{ .register_event_handler = .{
                .event = event_copy,
                .handler = handler_copy,
            } });
        }

        fn appendRegisterTheme(
            self: *CompiledPlugin,
            name: []const u8,
            colors: []const u8,
        ) !void {
            const name_copy = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(name_copy);
            const colors_copy = try self.allocator.dupe(u8, colors);
            errdefer self.allocator.free(colors_copy);

            try self.actions.append(self.allocator, .{ .register_theme = .{
                .name = name_copy,
                .colors = colors_copy,
            } });
        }

        pub fn callVoid(self: *CompiledPlugin, function_name: []const u8) Host.Error!void {
            const engine = self.script.engine;
            try self.host.ensureHostBuiltins(engine);

            const start_time = self.host.startExecution();
            var end_called = false;
            defer if (!end_called) self.host.endExecution(start_time) catch {};

            self.host.pending_error = null;
            const prev_host = active_host;
            active_host = self.host;
            defer active_host = prev_host;

            const prev_plugin = self.host.active_plugin;
            self.host.active_plugin = self;
            defer self.host.active_plugin = prev_plugin;

            var result = engine.call(function_name, .{}) catch |err| {
                return self.host.mapExecutionError(err);
            };
            defer result.deinit(engine.tracked_allocator);

            if (self.host.pending_error) |err| {
                self.host.pending_error = null;
                return err;
            }

            try self.host.endExecution(start_time);
            end_called = true;
        }

        pub fn callBool(self: *CompiledPlugin, function_name: []const u8) Host.Error!bool {
            const engine = self.script.engine;
            try self.host.ensureHostBuiltins(engine);

            const start_time = self.host.startExecution();
            var end_called = false;
            defer if (!end_called) self.host.endExecution(start_time) catch {};

            self.host.pending_error = null;
            const prev_host = active_host;
            active_host = self.host;
            defer active_host = prev_host;

            const prev_plugin = self.host.active_plugin;
            self.host.active_plugin = self;
            defer self.host.active_plugin = prev_plugin;

            var result = engine.call(function_name, .{}) catch |err| {
                return self.host.mapExecutionError(err);
            };
            defer result.deinit(engine.tracked_allocator);

            if (self.host.pending_error) |err| {
                self.host.pending_error = null;
                return err;
            }

            const handled = switch (result) {
                .boolean => |flag| flag,
                else => false,
            };

            try self.host.endExecution(start_time);
            end_called = true;
            return handled;
        }

        fn clearActions(self: *CompiledPlugin) void {
            for (self.actions.items) |action| {
                deinitAction(action, self.allocator);
            }
            self.actions.clearRetainingCapacity();
        }
    };

    fn deinitAction(action: Action, allocator: std.mem.Allocator) void {
        switch (action) {
            .show_message => |msg| allocator.free(msg),
            .register_command => |cmd| {
                allocator.free(cmd.name);
                allocator.free(cmd.handler);
                if (cmd.description) |desc| allocator.free(desc);
            },
            .register_keymap => |km| {
                allocator.free(km.keys);
                allocator.free(km.handler);
                if (km.mode) |mode| allocator.free(mode);
                if (km.description) |desc| allocator.free(desc);
            },
            .register_event_handler => |ev| {
                allocator.free(ev.event);
                allocator.free(ev.handler);
            },
            .register_theme => |theme| {
                allocator.free(theme.name);
                allocator.free(theme.colors);
            },
        }
    }

    const config_file_name = "init.gza";
    const max_config_size = 16 * 1024 * 1024; // 16 MiB safety limit

    pub fn init(allocator: std.mem.Allocator) !Host {
        return initWithSandbox(allocator, .{});
    }

    pub fn initWithSandbox(allocator: std.mem.Allocator, sandbox_config: SandboxConfig) !Host {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        return Host{
            .allocator = allocator,
            .arena = arena,
            .config_dir = null,
            .config_source = null,
            .setup_invoked = false,
            .sandbox_config = sandbox_config,
            .execution_stats = .{},
            .engine = null,
            .config_script = null,
            .active_plugin = null,
            .active_native_library = null,
            .pending_error = null,
            .builtins_registered = false,
        };
    }

    pub fn deinit(self: *Host) void {
        self.releaseConfigScript();
        if (self.engine) |engine| {
            engine.deinit();
            self.allocator.destroy(engine);
            self.engine = null;
        }
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn loadConfig(self: *Host, config_dir: []const u8) Error!void {
        self.resetArena();

        var dir = try std.fs.cwd().openDir(config_dir, .{});
        defer dir.close();

        const allocator = self.arena.allocator();
        const source_buffer = try dir.readFileAlloc(config_file_name, allocator, max_config_size);
        const dir_copy = try allocator.dupe(u8, config_dir);

        self.config_source = source_buffer;
        self.config_dir = dir_copy;
        self.setup_invoked = false;

        const engine = try self.ensureEngine();
        self.releaseConfigScript();

        const script_ptr = self.allocator.create(ghostlang.Script) catch |err| {
            return self.mapAllocatorError(err);
        };
        var destroy_script_ptr = true;
        errdefer if (destroy_script_ptr) self.allocator.destroy(script_ptr);

        script_ptr.* = engine.loadScript(source_buffer) catch |err| {
            return self.mapExecutionError(err);
        };

        self.config_script = script_ptr;
        destroy_script_ptr = false;
        self.pending_error = null;
    }

    pub fn callSetup(self: *Host) Error!void {
        _ = try self.ensureEngine();
        const script_ptr = self.config_script orelse return Error.ConfigNotLoaded;

        const start_time = self.startExecution();
        var end_called = false;
        defer if (!end_called) self.endExecution(start_time) catch {};

        self.pending_error = null;
        const prev_host = active_host;
        active_host = self;
        defer active_host = prev_host;

        const prev_plugin = self.active_plugin;
        self.active_plugin = null;
        defer self.active_plugin = prev_plugin;

        _ = script_ptr.run() catch |err| {
            return self.mapExecutionError(err);
        };

        if (self.pending_error) |err| {
            self.pending_error = null;
            return err;
        }

        try self.endExecution(start_time);
        end_called = true;
        self.setup_invoked = true;
    }

    pub fn compilePluginScript(self: *Host, script_source: []const u8) Error!CompiledPlugin {
        const engine = try self.ensureEngine();
        self.pending_error = null;

        var actions = std.ArrayList(Action).initCapacity(self.allocator, 0) catch |err| {
            return self.mapAllocatorError(err);
        };
        var actions_valid = true;
        errdefer if (actions_valid) actions.deinit(self.allocator);

        const script_ptr = self.allocator.create(ghostlang.Script) catch |err| {
            return self.mapAllocatorError(err);
        };
        var destroy_script_ptr = true;
        errdefer if (destroy_script_ptr) self.allocator.destroy(script_ptr);

        script_ptr.* = engine.loadScript(script_source) catch |err| {
            return self.mapExecutionError(err);
        };
        var deinit_script = true;
        errdefer if (deinit_script) script_ptr.deinit();

        actions_valid = false;
        destroy_script_ptr = false;
        deinit_script = false;

        return CompiledPlugin{
            .allocator = self.allocator,
            .host = self,
            .script = script_ptr,
            .actions = actions,
        };
    }

    pub fn configPath(self: *const Host) ?[]const u8 {
        return self.config_dir;
    }

    pub fn configSource(self: *const Host) ?[]const u8 {
        return self.config_source;
    }

    pub fn setupInvoked(self: *const Host) bool {
        return self.setup_invoked;
    }

    fn releaseConfigScript(self: *Host) void {
        if (self.config_script) |script_ptr| {
            script_ptr.deinit();
            self.allocator.destroy(script_ptr);
            self.config_script = null;
        }
    }

    fn resetArena(self: *Host) void {
        self.releaseConfigScript();
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.allocator);
        self.config_dir = null;
        self.config_source = null;
        self.setup_invoked = false;
    }

    fn ensureEngine(self: *Host) Error!*ghostlang.ScriptEngine {
        if (self.engine) |engine| return engine;

        const engine_ptr = self.allocator.create(ghostlang.ScriptEngine) catch |err| {
            return self.mapAllocatorError(err);
        };
        var destroy_engine_ptr = true;
        errdefer if (destroy_engine_ptr) self.allocator.destroy(engine_ptr);

        const config = ghostlang.EngineConfig{
            .allocator = self.allocator,
            .memory_limit = self.sandbox_config.max_memory_bytes,
            .execution_timeout_ms = self.sandbox_config.max_execution_time_ms,
            .allow_io = self.sandbox_config.enable_filesystem_access,
            .allow_syscalls = self.sandbox_config.enable_system_calls,
        };

        engine_ptr.* = ghostlang.ScriptEngine.create(config) catch |err| {
            return self.mapAllocatorError(err);
        };

        self.engine = engine_ptr;
        self.builtins_registered = false;
        try self.ensureHostBuiltins(engine_ptr);

        destroy_engine_ptr = false;
        return engine_ptr;
    }

    fn ensureHostBuiltins(self: *Host, engine: *ghostlang.ScriptEngine) Error!void {
        if (self.builtins_registered) return;
        try self.registerBuiltin(engine, "showMessage", builtinShowMessage);
        try self.registerBuiltin(engine, "show_message", builtinShowMessage);
        try self.registerBuiltin(engine, "registerCommand", builtinRegisterCommand);
        try self.registerBuiltin(engine, "register_command", builtinRegisterCommand);
        try self.registerBuiltin(engine, "registerKeymap", builtinRegisterKeymap);
        try self.registerBuiltin(engine, "register_keymap", builtinRegisterKeymap);
        try self.registerBuiltin(engine, "registerEventHandler", builtinRegisterEventHandler);
        try self.registerBuiltin(engine, "register_event_handler", builtinRegisterEventHandler);
        try self.registerBuiltin(engine, "registerTheme", builtinRegisterTheme);
        try self.registerBuiltin(engine, "register_theme", builtinRegisterTheme);

        // Reaper AI integration builtins
        try self.registerBuiltin(engine, "reaper_complete", builtinReaperComplete);
        try self.registerBuiltin(engine, "reaper_chat", builtinReaperChat);
        try self.registerBuiltin(engine, "reaper_agentic", builtinReaperAgentic);

        // Native FFI bridge (for hybrid plugins)
        try self.registerBuiltin(engine, "call_native", builtinCallNative);

        self.builtins_registered = true;
    }

    fn registerBuiltin(
        self: *Host,
        engine: *ghostlang.ScriptEngine,
        name: []const u8,
        func: *const fn (args: []const ghostlang.ScriptValue) ghostlang.ScriptValue,
    ) Error!void {
        engine.registerFunction(name, func) catch |err| {
            return self.mapExecutionError(err);
        };
    }

    fn handleShowMessageBuiltin(self: *Host, args: []const ghostlang.ScriptValue) void {
        if (args.len == 0) return;
        if (args[0] != .string) return;
        const plugin = self.active_plugin orelse return;
        plugin.appendShowMessage(args[0].string) catch |err| switch (err) {
            error.OutOfMemory => self.recordScriptError(Error.MemoryLimitExceeded),
        };
    }

    pub fn validateFileAccess(self: *Host, file_path: []const u8) Error!void {
        if (!self.sandbox_config.enable_filesystem_access) {
            self.execution_stats.sandbox_violations += 1;
            return Error.UnauthorizedFileAccess;
        }

        // Check blocked patterns first
        for (self.sandbox_config.blocked_file_patterns) |pattern| {
            if (matchesPattern(file_path, pattern)) {
                self.execution_stats.sandbox_violations += 1;
                return Error.UnauthorizedFileAccess;
            }
        }

        // If allowed patterns are specified, check them
        if (self.sandbox_config.allowed_file_patterns.len > 0) {
            var allowed = false;
            for (self.sandbox_config.allowed_file_patterns) |pattern| {
                if (matchesPattern(file_path, pattern)) {
                    allowed = true;
                    break;
                }
            }
            if (!allowed) {
                self.execution_stats.sandbox_violations += 1;
                return Error.UnauthorizedFileAccess;
            }
        }

        // Increment file operation counter
        self.execution_stats.file_operations_count += 1;
        if (self.execution_stats.file_operations_count > self.sandbox_config.max_file_operations) {
            self.execution_stats.sandbox_violations += 1;
            return Error.SandboxViolation;
        }
    }

    pub fn validateNetworkAccess(self: *Host) Error!void {
        if (!self.sandbox_config.enable_network_access) {
            self.execution_stats.sandbox_violations += 1;
            return Error.UnauthorizedNetworkAccess;
        }

        self.execution_stats.network_requests_count += 1;
        if (self.execution_stats.network_requests_count > self.sandbox_config.max_network_requests) {
            self.execution_stats.sandbox_violations += 1;
            return Error.SandboxViolation;
        }
    }

    pub fn validateMemoryUsage(self: *Host, requested_bytes: usize) Error!void {
        if (requested_bytes > self.sandbox_config.max_memory_bytes) {
            self.execution_stats.sandbox_violations += 1;
            return Error.MemoryLimitExceeded;
        }

        self.execution_stats.peak_memory_usage = @max(self.execution_stats.peak_memory_usage, requested_bytes);
    }

    pub fn startExecution(self: *Host) i64 {
        self.execution_stats.execution_count += 1;
        return std.time.milliTimestamp();
    }

    pub fn endExecution(self: *Host, start_time: i64) Error!void {
        const end_time = std.time.milliTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));

        self.execution_stats.total_execution_time_ms += duration;
        self.execution_stats.last_execution_time = start_time;

        if (duration > self.sandbox_config.max_execution_time_ms) {
            self.execution_stats.sandbox_violations += 1;
            return Error.ExecutionTimeout;
        }
    }

    pub fn getExecutionStats(self: *const Host) ExecutionStats {
        return self.execution_stats;
    }

    pub fn resetStats(self: *Host) void {
        self.execution_stats.reset();
    }

    /// Set the active native library (for hybrid plugins)
    pub fn setNativeLibrary(self: *Host, library: ?*std.DynLib) void {
        self.active_native_library = library;
    }

    fn mapExecutionError(self: *Host, err: ghostlang.ExecutionError) Error {
        _ = self;
        return switch (err) {
            error.MemoryLimitExceeded => Error.MemoryLimitExceeded,
            error.ExecutionTimeout => Error.ExecutionTimeout,
            error.IONotAllowed => Error.UnauthorizedFileAccess,
            error.SyscallNotAllowed => Error.SandboxViolation,
            error.SecurityViolation => Error.SandboxViolation,
            error.ParseError => Error.InvalidScript,
            error.TypeError => Error.InvalidScript,
            error.FunctionNotFound => Error.InvalidScript,
            error.NotAFunction => Error.InvalidScript,
            error.UndefinedVariable => Error.InvalidScript,
            error.ScopeUnderflow => Error.InvalidScript,
            error.InvalidFunctionName => Error.InvalidScript,
            error.InvalidGlobalName => Error.InvalidScript,
            error.GlobalNotFound => Error.InvalidScript,
            error.UnsupportedArgumentType => Error.InvalidScript,
            error.OutOfMemory => Error.MemoryLimitExceeded,
            error.ScriptError => Error.InvalidScript,
        };
    }

    fn mapAllocatorError(self: *Host, err: std.mem.Allocator.Error) Error {
        _ = self;
        return switch (err) {
            error.OutOfMemory => Error.MemoryLimitExceeded,
        };
    }

    fn recordScriptError(self: *Host, err: Error) void {
        if (self.pending_error == null) {
            self.pending_error = err;
        }
    }

    fn matchesPattern(path: []const u8, pattern: []const u8) bool {
        // Simple glob pattern matching - supports * wildcard at end
        if (std.mem.endsWith(u8, pattern, "*")) {
            const prefix = pattern[0 .. pattern.len - 1];
            return std.mem.startsWith(u8, path, prefix);
        }
        return std.mem.eql(u8, path, pattern);
    }
};

test "host loads config and executes script" {
    const allocator = std.testing.allocator;
    var host = try Host.init(allocator);
    defer host.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile("init.gza", "var x = 5; x + 7;");

    try host.loadConfig(tmp.path);
    try std.testing.expect(host.configSource() != null);

    try host.callSetup();
    try std.testing.expect(host.setupInvoked());
}

test "load config with invalid script fails" {
    const allocator = std.testing.allocator;
    var host = try Host.init(allocator);
    defer host.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile("init.gza", "var broken = ");
    try std.testing.expectError(Host.Error.InvalidScript, host.loadConfig(tmp.path));
}

test "calling setup before loading config errors" {
    const allocator = std.testing.allocator;
    var host = try Host.init(allocator);
    defer host.deinit();

    try std.testing.expectError(Host.Error.ConfigNotLoaded, host.callSetup());
}

test "plugin script showMessage action executes" {
    const allocator = std.testing.allocator;
    var host = try Host.init(allocator);
    defer host.deinit();

    const plugin_source = "showMessage(\"hello from plugin\")";
    var compiled = try host.compilePluginScript(plugin_source);
    defer compiled.deinit();

    const CallbackCtx = struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        message: ?[]u8 = null,

        fn capture(self: *Self, msg: []const u8) !void {
            if (self.message) |existing| {
                self.allocator.free(existing);
            }
            self.message = try self.allocator.dupe(u8, msg);
        }
    };

    const ShowMessageShim = struct {
        fn call(ctx_ptr: *anyopaque, message: []const u8) anyerror!void {
            const ctx = @as(*CallbackCtx, @ptrCast(@alignCast(ctx_ptr)));
            try ctx.capture(message);
        }
    };

    var ctx = CallbackCtx{ .allocator = allocator };
    defer if (ctx.message) |msg| allocator.free(msg);

    const callbacks = Host.ActionCallbacks{
        .ctx = @as(*anyopaque, @ptrCast(&ctx)),
        .show_message = ShowMessageShim.call,
    };

    try compiled.executeSetup(callbacks);
    try std.testing.expect(ctx.message != null);
}

test "sandbox config validates file access" {
    const allocator = std.testing.allocator;
    const sandbox_config = Host.SandboxConfig{
        .blocked_file_patterns = &.{ "/etc/*", "/sys/*" },
        .allowed_file_patterns = &.{ "/home/*", "/tmp/*" },
    };

    var host = try Host.initWithSandbox(allocator, sandbox_config);
    defer host.deinit();

    // Should allow access to allowed patterns
    try host.validateFileAccess("/home/user/config.gza");
    try host.validateFileAccess("/tmp/test.txt");

    // Should block access to blocked patterns
    try std.testing.expectError(Host.Error.UnauthorizedFileAccess, host.validateFileAccess("/etc/passwd"));
    try std.testing.expectError(Host.Error.UnauthorizedFileAccess, host.validateFileAccess("/sys/kernel"));

    // Should block access to paths not in allowed patterns
    try std.testing.expectError(Host.Error.UnauthorizedFileAccess, host.validateFileAccess("/usr/bin/ls"));
}

test "sandbox tracks execution stats" {
    const allocator = std.testing.allocator;
    const sandbox_config = Host.SandboxConfig{
        .max_file_operations = 2,
    };

    var host = try Host.initWithSandbox(allocator, sandbox_config);
    defer host.deinit();

    // First operations should succeed
    try host.validateFileAccess("/home/test1.txt");
    try host.validateFileAccess("/home/test2.txt");

    // Third should fail due to limit
    try std.testing.expectError(Host.Error.SandboxViolation, host.validateFileAccess("/home/test3.txt"));

    const stats = host.getExecutionStats();
    try std.testing.expectEqual(@as(u32, 3), stats.file_operations_count);
    try std.testing.expectEqual(@as(u32, 1), stats.sandbox_violations);
}

test "execution timeout validation" {
    const allocator = std.testing.allocator;
    const sandbox_config = Host.SandboxConfig{
        .max_execution_time_ms = 100,
    };

    var host = try Host.initWithSandbox(allocator, sandbox_config);
    defer host.deinit();

    const start_time = host.startExecution();

    // Simulate long execution by manually setting old timestamp
    const old_start = start_time - 200;
    try std.testing.expectError(Host.Error.ExecutionTimeout, host.endExecution(old_start));

    const stats = host.getExecutionStats();
    try std.testing.expectEqual(@as(u32, 1), stats.sandbox_violations);
}

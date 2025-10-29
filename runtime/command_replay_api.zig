const std = @import("std");

/// Command and Key Replay API
/// Allows lazy-loaded plugins to replay commands and key sequences
pub const CommandReplayAPI = struct {
    allocator: std.mem.Allocator,
    pending_commands: std.ArrayList(PendingCommand),
    pending_keys: std.ArrayList(PendingKeySequence),
    command_executor: ?CommandExecutor = null,
    key_handler: ?KeyHandler = null,

    pub const PendingCommand = struct {
        command: []const u8,
        args: []const []const u8,
        mode: ?EditorMode = null,
        bang: bool = false,

        pub fn deinit(self: *PendingCommand, allocator: std.mem.Allocator) void {
            allocator.free(self.command);
            for (self.args) |arg| {
                allocator.free(arg);
            }
            allocator.free(self.args);
        }
    };

    pub const PendingKeySequence = struct {
        keys: []const u8,
        mode: ?EditorMode = null,
        remap: bool = true,

        pub fn deinit(self: *PendingKeySequence, allocator: std.mem.Allocator) void {
            allocator.free(self.keys);
        }
    };

    pub const EditorMode = enum {
        normal,
        insert,
        visual,
        visual_line,
        visual_block,
        command,
        terminal,
    };

    pub const CommandExecutor = struct {
        ctx: *anyopaque,
        execute_fn: *const fn (
            ctx: *anyopaque,
            command: []const u8,
            args: []const []const u8,
            bang: bool,
        ) anyerror!void,
    };

    pub const KeyHandler = struct {
        ctx: *anyopaque,
        handle_fn: *const fn (
            ctx: *anyopaque,
            keys: []const u8,
            mode: EditorMode,
            remap: bool,
        ) anyerror!void,
    };

    pub fn init(allocator: std.mem.Allocator) CommandReplayAPI {
        return .{
            .allocator = allocator,
            .pending_commands = std.ArrayList(PendingCommand){},
            .pending_keys = std.ArrayList(PendingKeySequence){},
        };
    }

    pub fn deinit(self: *CommandReplayAPI) void {
        for (self.pending_commands.items) |*cmd| {
            cmd.deinit(self.allocator);
        }
        self.pending_commands.deinit(self.allocator);

        for (self.pending_keys.items) |*keys| {
            keys.deinit(self.allocator);
        }
        self.pending_keys.deinit(self.allocator);
    }

    /// Set the command executor
    pub fn setCommandExecutor(self: *CommandReplayAPI, executor: CommandExecutor) void {
        self.command_executor = executor;
    }

    /// Set the key handler
    pub fn setKeyHandler(self: *CommandReplayAPI, handler: KeyHandler) void {
        self.key_handler = handler;
    }

    /// Execute a command immediately (phantom.exec_command)
    pub fn execCommand(
        self: *CommandReplayAPI,
        command: []const u8,
        args: []const []const u8,
        bang: bool,
    ) !void {
        if (self.command_executor) |executor| {
            try executor.execute_fn(executor.ctx, command, args, bang);
        } else {
            // Queue for later if no executor is set
            try self.queueCommand(command, args, bang, null);
        }
    }

    /// Queue a command for later execution
    pub fn queueCommand(
        self: *CommandReplayAPI,
        command: []const u8,
        args: []const []const u8,
        bang: bool,
        mode: ?EditorMode,
    ) !void {
        const cmd_copy = try self.allocator.dupe(u8, command);
        errdefer self.allocator.free(cmd_copy);

        var args_copy = try self.allocator.alloc([]const u8, args.len);
        errdefer self.allocator.free(args_copy);

        for (args, 0..) |arg, i| {
            args_copy[i] = try self.allocator.dupe(u8, arg);
        }

        try self.pending_commands.append(self.allocator, .{
            .command = cmd_copy,
            .args = args_copy,
            .mode = mode,
            .bang = bang,
        });
    }

    /// Feed keys to the editor (phantom.feedkeys)
    pub fn feedKeys(
        self: *CommandReplayAPI,
        keys: []const u8,
        mode: EditorMode,
        remap: bool,
    ) !void {
        if (self.key_handler) |handler| {
            try handler.handle_fn(handler.ctx, keys, mode, remap);
        } else {
            // Queue for later if no handler is set
            try self.queueKeys(keys, mode, remap);
        }
    }

    /// Queue keys for later feeding
    pub fn queueKeys(
        self: *CommandReplayAPI,
        keys: []const u8,
        mode: EditorMode,
        remap: bool,
    ) !void {
        const keys_copy = try self.allocator.dupe(u8, keys);
        try self.pending_keys.append(self.allocator, .{
            .keys = keys_copy,
            .mode = mode,
            .remap = remap,
        });
    }

    /// Flush all pending commands
    pub fn flushCommands(self: *CommandReplayAPI) !void {
        const executor = self.command_executor orelse return error.NoCommandExecutor;

        for (self.pending_commands.items) |*cmd| {
            try executor.execute_fn(executor.ctx, cmd.command, cmd.args, cmd.bang);
            cmd.deinit(self.allocator);
        }

        self.pending_commands.clearRetainingCapacity();
    }

    /// Flush all pending keys
    pub fn flushKeys(self: *CommandReplayAPI) !void {
        const handler = self.key_handler orelse return error.NoKeyHandler;

        for (self.pending_keys.items) |*keys| {
            const mode = keys.mode orelse .normal;
            try handler.handle_fn(handler.ctx, keys.keys, mode, keys.remap);
            keys.deinit(self.allocator);
        }

        self.pending_keys.clearRetainingCapacity();
    }

    /// Flush both commands and keys
    pub fn flushAll(self: *CommandReplayAPI) !void {
        try self.flushCommands();
        try self.flushKeys();
    }

    /// Get pending command count
    pub fn pendingCommandCount(self: *const CommandReplayAPI) usize {
        return self.pending_commands.items.len;
    }

    /// Get pending key sequence count
    pub fn pendingKeyCount(self: *const CommandReplayAPI) usize {
        return self.pending_keys.items.len;
    }

    /// Parse a command string (":command arg1 arg2")
    pub fn parseCommandString(
        self: *CommandReplayAPI,
        command_str: []const u8,
    ) !struct {
        command: []const u8,
        args: []const []const u8,
        bang: bool,
    } {
        var it = std.mem.tokenizeScalar(u8, command_str, ' ');

        var cmd = it.next() orelse return error.EmptyCommand;

        // Check for ! suffix
        const bang = std.mem.endsWith(u8, cmd, "!");
        if (bang) {
            cmd = cmd[0 .. cmd.len - 1];
        }

        var args = std.ArrayList([]const u8){};
        errdefer args.deinit(self.allocator);

        while (it.next()) |arg| {
            try args.append(self.allocator, try self.allocator.dupe(u8, arg));
        }

        return .{
            .command = try self.allocator.dupe(u8, cmd),
            .args = try args.toOwnedSlice(self.allocator),
            .bang = bang,
        };
    }

    /// Normalize key sequence (convert <C-x> to internal representation)
    pub fn normalizeKeySequence(
        self: *CommandReplayAPI,
        keys: []const u8,
    ) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < keys.len) {
            if (keys[i] == '<') {
                // Find closing >
                var end: ?usize = null;
                for (keys[i + 1 ..], i + 1..) |ch, idx| {
                    if (ch == '>') {
                        end = idx;
                        break;
                    }
                }

                if (end) |e| {
                    const special = keys[i + 1 .. e];
                    try self.appendSpecialKey(&result, special);
                    i = e + 1;
                    continue;
                }
            }

            try result.append(self.allocator, keys[i]);
            i += 1;
        }

        return result.toOwnedSlice(self.allocator);
    }

    fn appendSpecialKey(self: *CommandReplayAPI, result: *std.ArrayList(u8), special: []const u8) !void {

        // Map special keys to internal representation
        if (std.mem.eql(u8, special, "CR") or std.mem.eql(u8, special, "Enter")) {
            try result.append(self.allocator, '\n');
        } else if (std.mem.eql(u8, special, "Esc")) {
            try result.append(self.allocator, 0x1b);
        } else if (std.mem.eql(u8, special, "Tab")) {
            try result.append(self.allocator, '\t');
        } else if (std.mem.eql(u8, special, "BS") or std.mem.eql(u8, special, "Backspace")) {
            try result.append(self.allocator, 0x08);
        } else if (std.mem.eql(u8, special, "Space")) {
            try result.append(self.allocator, ' ');
        } else if (std.mem.startsWith(u8, special, "C-")) {
            // Control key: C-x -> Ctrl+X
            if (special.len == 3) {
                const ch = special[2];
                if (ch >= 'a' and ch <= 'z') {
                    try result.append(self.allocator, ch - 'a' + 1);
                } else if (ch >= 'A' and ch <= 'Z') {
                    try result.append(self.allocator, ch - 'A' + 1);
                }
            }
        } else if (std.mem.startsWith(u8, special, "M-") or std.mem.startsWith(u8, special, "A-")) {
            // Meta/Alt key: M-x -> Alt+X
            if (special.len == 3) {
                try result.append(self.allocator, 0x1b); // Escape prefix for meta
                try result.append(self.allocator, special[2]);
            }
        } else if (std.mem.eql(u8, special, "leader")) {
            try result.append(self.allocator, '\\'); // Default leader
        } else {
            // Unknown special key, keep as-is
            try result.append(self.allocator, '<');
            try result.appendSlice(self.allocator, special);
            try result.append(self.allocator, '>');
        }
    }
};

test "CommandReplayAPI exec command" {
    const allocator = std.testing.allocator;
    var api = CommandReplayAPI.init(allocator);
    defer api.deinit();

    const TestCtx = struct {
        executed: bool = false,
        command: ?[]const u8 = null,
        args: ?[]const []const u8 = null,

        fn execute(
            ctx: *anyopaque,
            command: []const u8,
            args: []const []const u8,
            bang: bool,
        ) !void {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            _ = bang;
            self.executed = true;
            self.command = command;
            self.args = args;
        }
    };

    var test_ctx = TestCtx{};
    api.setCommandExecutor(.{ .ctx = &test_ctx, .execute_fn = TestCtx.execute });

    const args = [_][]const u8{ "arg1", "arg2" };
    try api.execCommand("test", &args, false);

    try std.testing.expect(test_ctx.executed);
    try std.testing.expectEqualStrings("test", test_ctx.command.?);
    try std.testing.expectEqual(@as(usize, 2), test_ctx.args.?.len);
}

test "CommandReplayAPI feed keys" {
    const allocator = std.testing.allocator;
    var api = CommandReplayAPI.init(allocator);
    defer api.deinit();

    const TestCtx = struct {
        keys_received: ?[]const u8 = null,
        mode: ?CommandReplayAPI.EditorMode = null,

        fn handle(
            ctx: *anyopaque,
            keys: []const u8,
            mode: CommandReplayAPI.EditorMode,
            remap: bool,
        ) !void {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            _ = remap;
            self.keys_received = keys;
            self.mode = mode;
        }
    };

    var test_ctx = TestCtx{};
    api.setKeyHandler(.{ .ctx = &test_ctx, .handle_fn = TestCtx.handle });

    try api.feedKeys("dd", .normal, true);

    try std.testing.expectEqualStrings("dd", test_ctx.keys_received.?);
    try std.testing.expectEqual(CommandReplayAPI.EditorMode.normal, test_ctx.mode.?);
}

test "CommandReplayAPI queue and flush" {
    const allocator = std.testing.allocator;
    var api = CommandReplayAPI.init(allocator);
    defer api.deinit();

    // Queue commands without executor
    const args1 = [_][]const u8{"arg1"};
    try api.queueCommand("cmd1", &args1, false, null);

    const args2 = [_][]const u8{"arg2"};
    try api.queueCommand("cmd2", &args2, false, null);

    try std.testing.expectEqual(@as(usize, 2), api.pendingCommandCount());

    // Set executor and flush
    const TestCtx = struct {
        exec_count: usize = 0,

        fn execute(
            ctx: *anyopaque,
            command: []const u8,
            args: []const []const u8,
            bang: bool,
        ) !void {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            _ = command;
            _ = args;
            _ = bang;
            self.exec_count += 1;
        }
    };

    var test_ctx = TestCtx{};
    api.setCommandExecutor(.{ .ctx = &test_ctx, .execute_fn = TestCtx.execute });

    try api.flushCommands();

    try std.testing.expectEqual(@as(usize, 2), test_ctx.exec_count);
    try std.testing.expectEqual(@as(usize, 0), api.pendingCommandCount());
}

test "CommandReplayAPI parse command" {
    const allocator = std.testing.allocator;
    var api = CommandReplayAPI.init(allocator);
    defer api.deinit();

    const parsed = try api.parseCommandString("write! file.txt backup");
    defer {
        allocator.free(parsed.command);
        for (parsed.args) |arg| allocator.free(arg);
        allocator.free(parsed.args);
    }

    try std.testing.expectEqualStrings("write", parsed.command);
    try std.testing.expect(parsed.bang);
    try std.testing.expectEqual(@as(usize, 2), parsed.args.len);
    try std.testing.expectEqualStrings("file.txt", parsed.args[0]);
    try std.testing.expectEqualStrings("backup", parsed.args[1]);
}

test "CommandReplayAPI normalize keys" {
    const allocator = std.testing.allocator;
    var api = CommandReplayAPI.init(allocator);
    defer api.deinit();

    const normalized = try api.normalizeKeySequence("<C-x><CR>abc<Esc>");
    defer allocator.free(normalized);

    try std.testing.expectEqual(@as(u8, 0x18), normalized[0]); // Ctrl+X
    try std.testing.expectEqual(@as(u8, '\n'), normalized[1]); // CR
    try std.testing.expectEqual(@as(u8, 'a'), normalized[2]);
    try std.testing.expectEqual(@as(u8, 'b'), normalized[3]);
    try std.testing.expectEqual(@as(u8, 'c'), normalized[4]);
    try std.testing.expectEqual(@as(u8, 0x1b), normalized[5]); // Esc
}

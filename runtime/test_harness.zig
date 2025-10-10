const std = @import("std");
const core = @import("core");
const plugin_api = @import("plugin_api.zig");

/// Ghostlang Regression Test Harness
/// Provides headless buffer and command runner for plugin testing
pub const TestHarness = struct {
    allocator: std.mem.Allocator,
    buffers: std.AutoHashMap(u32, TestBuffer),
    next_buffer_id: u32 = 1,
    plugin_api: plugin_api.PluginAPI,
    command_log: std.ArrayList(LoggedCommand),
    event_log: std.ArrayList(LoggedEvent),
    verbose: bool = false,

    pub const TestBuffer = struct {
        id: u32,
        rope: core.Rope,
        file_path: ?[]const u8 = null,
        modified: bool = false,
        cursor: plugin_api.PluginAPI.EditorContext.CursorPosition,

        pub fn init(allocator: std.mem.Allocator, id: u32) !TestBuffer {
            return TestBuffer{
                .id = id,
                .rope = try core.Rope.init(allocator),
                .cursor = .{ .line = 0, .column = 0, .byte_offset = 0 },
            };
        }

        pub fn deinit(self: *TestBuffer) void {
            self.rope.deinit();
            if (self.file_path) |path| {
                self.rope.allocator.free(path);
            }
        }

        pub fn setContent(self: *TestBuffer, content: []const u8) !void {
            const len = self.rope.len();
            if (len > 0) {
                try self.rope.delete(0, len);
            }
            if (content.len > 0) {
                try self.rope.insert(0, content);
            }
            self.modified = true;
        }

        pub fn getContent(self: *const TestBuffer, allocator: std.mem.Allocator) ![]const u8 {
            return try self.rope.copyRangeAlloc(allocator, .{ .start = 0, .end = self.rope.len() });
        }
    };

    pub const LoggedCommand = struct {
        timestamp: i64,
        command: []const u8,
        args: []const []const u8,
        success: bool,
        error_msg: ?[]const u8 = null,

        pub fn deinit(self: *LoggedCommand, allocator: std.mem.Allocator) void {
            allocator.free(self.command);
            for (self.args) |arg| allocator.free(arg);
            allocator.free(self.args);
            if (self.error_msg) |msg| allocator.free(msg);
        }
    };

    pub const LoggedEvent = struct {
        timestamp: i64,
        event_type: plugin_api.PluginAPI.EventType,
        plugin_id: []const u8,

        pub fn deinit(self: *LoggedEvent, allocator: std.mem.Allocator) void {
            allocator.free(self.plugin_id);
        }
    };

    pub const TestCase = struct {
        name: []const u8,
        setup: ?*const fn (harness: *TestHarness) anyerror!void = null,
        run: *const fn (harness: *TestHarness) anyerror!void,
        teardown: ?*const fn (harness: *TestHarness) anyerror!void = null,
        timeout_ms: u64 = 5000,
    };

    pub const TestResult = struct {
        name: []const u8,
        passed: bool,
        duration_ms: u64,
        error_msg: ?[]const u8 = null,

        pub fn deinit(self: *TestResult, allocator: std.mem.Allocator) void {
            if (self.error_msg) |msg| allocator.free(msg);
        }
    };

    pub fn init(allocator: std.mem.Allocator) !TestHarness {
        var buffers = std.AutoHashMap(u32, TestBuffer).init(allocator);
        errdefer buffers.deinit();

        // Create initial buffer
        var initial_buffer = try TestBuffer.init(allocator, 1);
        try buffers.put(1, initial_buffer);

        // Create editor context
        var cursor_storage = plugin_api.PluginAPI.EditorContext.CursorPosition{
            .line = 0,
            .column = 0,
            .byte_offset = 0,
        };
        var mode_storage = plugin_api.PluginAPI.EditorContext.EditorMode.normal;

        const syntax = @import("syntax");
        var highlighter = syntax.SyntaxHighlighter.init(allocator);

        const editor_context = try allocator.create(plugin_api.PluginAPI.EditorContext);
        editor_context.* = .{
            .rope = &initial_buffer.rope,
            .cursor_position = &cursor_storage,
            .current_mode = &mode_storage,
            .highlighter = &highlighter,
            .active_buffer_id = 1,
        };

        const api = plugin_api.PluginAPI.init(allocator, editor_context);

        return TestHarness{
            .allocator = allocator,
            .buffers = buffers,
            .plugin_api = api,
            .command_log = std.ArrayList(LoggedCommand).init(allocator),
            .event_log = std.ArrayList(LoggedEvent).init(allocator),
        };
    }

    pub fn deinit(self: *TestHarness) void {
        var it = self.buffers.iterator();
        while (it.next()) |entry| {
            var buffer = entry.value_ptr;
            buffer.deinit();
        }
        self.buffers.deinit();

        self.plugin_api.deinit();

        for (self.command_log.items) |*cmd| {
            cmd.deinit(self.allocator);
        }
        self.command_log.deinit();

        for (self.event_log.items) |*event| {
            event.deinit(self.allocator);
        }
        self.event_log.deinit();

        self.allocator.destroy(self.plugin_api.editor_context);
    }

    /// Create a new test buffer
    pub fn createBuffer(self: *TestHarness, content: []const u8) !u32 {
        const id = self.next_buffer_id;
        self.next_buffer_id += 1;

        var buffer = try TestBuffer.init(self.allocator, id);
        errdefer buffer.deinit();

        try buffer.setContent(content);
        try self.buffers.put(id, buffer);

        return id;
    }

    /// Switch to a buffer
    pub fn switchBuffer(self: *TestHarness, buffer_id: u32) !void {
        if (!self.buffers.contains(buffer_id)) return error.BufferNotFound;
        self.plugin_api.editor_context.active_buffer_id = buffer_id;

        const buffer = self.buffers.getPtr(buffer_id).?;
        self.plugin_api.editor_context.rope = &buffer.rope;
        self.plugin_api.editor_context.cursor_position.* = buffer.cursor;
    }

    /// Get buffer content
    pub fn getBufferContent(self: *TestHarness, buffer_id: u32) ![]const u8 {
        const buffer = self.buffers.get(buffer_id) orelse return error.BufferNotFound;
        return try buffer.getContent(self.allocator);
    }

    /// Set buffer content
    pub fn setBufferContent(self: *TestHarness, buffer_id: u32, content: []const u8) !void {
        var buffer = self.buffers.getPtr(buffer_id) orelse return error.BufferNotFound;
        try buffer.setContent(content);
    }

    /// Execute a command
    pub fn execCommand(self: *TestHarness, command: []const u8, args: []const []const u8) !void {
        const start_time = std.time.milliTimestamp();

        const success = blk: {
            self.plugin_api.executeCommand(command, "test_harness", args) catch |err| {
                const error_msg = try std.fmt.allocPrint(self.allocator, "{}", .{err});
                try self.logCommand(command, args, false, error_msg);
                break :blk false;
            };
            try self.logCommand(command, args, true, null);
            break :blk true;
        };

        if (self.verbose) {
            const duration = std.time.milliTimestamp() - start_time;
            std.debug.print("[{d}ms] Command '{s}' {s}\n", .{ duration, command, if (success) "OK" else "FAILED" });
        }
    }

    /// Send key sequence
    pub fn sendKeys(self: *TestHarness, keys: []const u8, mode: plugin_api.PluginAPI.EditorContext.EditorMode) !void {
        _ = try self.plugin_api.handleKeystroke(keys, mode);

        if (self.verbose) {
            std.debug.print("Keys: '{s}' in {s} mode\n", .{ keys, @tagName(mode) });
        }
    }

    /// Assert buffer content
    pub fn assertBufferContent(self: *TestHarness, buffer_id: u32, expected: []const u8) !void {
        const actual = try self.getBufferContent(buffer_id);
        defer self.allocator.free(actual);

        if (!std.mem.eql(u8, actual, expected)) {
            std.debug.print("Buffer content mismatch:\nExpected: {s}\nActual: {s}\n", .{ expected, actual });
            return error.AssertionFailed;
        }
    }

    /// Assert cursor position
    pub fn assertCursorPosition(self: *TestHarness, line: usize, column: usize) !void {
        const cursor = self.plugin_api.editor_context.cursor_position.*;
        if (cursor.line != line or cursor.column != column) {
            std.debug.print("Cursor position mismatch:\nExpected: ({d}, {d})\nActual: ({d}, {d})\n", .{
                line,
                column,
                cursor.line,
                cursor.column,
            });
            return error.AssertionFailed;
        }
    }

    /// Assert mode
    pub fn assertMode(self: *TestHarness, expected_mode: plugin_api.PluginAPI.EditorContext.EditorMode) !void {
        const actual_mode = self.plugin_api.editor_context.current_mode.*;
        if (actual_mode != expected_mode) {
            std.debug.print("Mode mismatch:\nExpected: {s}\nActual: {s}\n", .{
                @tagName(expected_mode),
                @tagName(actual_mode),
            });
            return error.AssertionFailed;
        }
    }

    /// Run a test case
    pub fn runTest(self: *TestHarness, test_case: TestCase) !TestResult {
        const start_time = std.time.milliTimestamp();

        if (self.verbose) {
            std.debug.print("\n=== Running test: {s} ===\n", .{test_case.name});
        }

        // Setup
        if (test_case.setup) |setup| {
            try setup(self);
        }

        // Run test
        const success = blk: {
            test_case.run(self) catch |err| {
                const error_msg = try std.fmt.allocPrint(self.allocator, "{}", .{err});
                const duration = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
                break :blk TestResult{
                    .name = test_case.name,
                    .passed = false,
                    .duration_ms = duration,
                    .error_msg = error_msg,
                };
            };
            break :blk TestResult{
                .name = test_case.name,
                .passed = true,
                .duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time)),
            };
        };

        // Teardown
        if (test_case.teardown) |teardown| {
            try teardown(self);
        }

        if (self.verbose) {
            const status = if (success.passed) "PASS" else "FAIL";
            std.debug.print("[{s}] {s} ({d}ms)\n", .{ status, test_case.name, success.duration_ms });
        }

        return success;
    }

    /// Run multiple test cases
    pub fn runTests(self: *TestHarness, test_cases: []const TestCase) ![]TestResult {
        var results = try self.allocator.alloc(TestResult, test_cases.len);
        errdefer self.allocator.free(results);

        for (test_cases, 0..) |test_case, i| {
            results[i] = try self.runTest(test_case);
        }

        return results;
    }

    fn logCommand(self: *TestHarness, command: []const u8, args: []const []const u8, success: bool, error_msg: ?[]const u8) !void {
        var args_copy = try self.allocator.alloc([]const u8, args.len);
        for (args, 0..) |arg, i| {
            args_copy[i] = try self.allocator.dupe(u8, arg);
        }

        try self.command_log.append(.{
            .timestamp = std.time.milliTimestamp(),
            .command = try self.allocator.dupe(u8, command),
            .args = args_copy,
            .success = success,
            .error_msg = error_msg,
        });
    }
};

test "TestHarness basic buffer operations" {
    const allocator = std.testing.allocator;
    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    const buf_id = try harness.createBuffer("hello world");

    try harness.assertBufferContent(buf_id, "hello world");

    try harness.setBufferContent(buf_id, "goodbye");
    try harness.assertBufferContent(buf_id, "goodbye");
}

test "TestHarness multi-buffer" {
    const allocator = std.testing.allocator;
    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    const buf1 = try harness.createBuffer("buffer one");
    const buf2 = try harness.createBuffer("buffer two");

    try harness.switchBuffer(buf1);
    try harness.assertBufferContent(buf1, "buffer one");

    try harness.switchBuffer(buf2);
    try harness.assertBufferContent(buf2, "buffer two");
}

test "TestHarness test case execution" {
    const allocator = std.testing.allocator;
    var harness = try TestHarness.init(allocator);
    defer harness.deinit();

    const TestImpl = struct {
        fn setup(h: *TestHarness) !void {
            _ = try h.createBuffer("test content");
        }

        fn run(h: *TestHarness) !void {
            try h.assertBufferContent(1, "");
        }

        fn teardown(h: *TestHarness) !void {
            _ = h;
        }
    };

    const test_case = TestHarness.TestCase{
        .name = "example test",
        .setup = TestImpl.setup,
        .run = TestImpl.run,
        .teardown = TestImpl.teardown,
    };

    const result = try harness.runTest(test_case);
    defer if (result.error_msg) |msg| allocator.free(msg);

    try std.testing.expect(result.passed);
}

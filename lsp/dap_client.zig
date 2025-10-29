//! Debug Adapter Protocol (DAP) client implementation

const std = @import("std");

pub const Breakpoint = struct {
    filepath: []const u8,
    line: usize,
    verified: bool,
    id: ?usize,

    pub fn deinit(self: *Breakpoint, allocator: std.mem.Allocator) void {
        allocator.free(self.filepath);
    }
};

pub const StackFrame = struct {
    id: usize,
    name: []const u8,
    source: ?[]const u8,
    line: usize,
    column: usize,

    pub fn deinit(self: *StackFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.source) |src| allocator.free(src);
    }
};

pub const Variable = struct {
    name: []const u8,
    value: []const u8,
    type: ?[]const u8,

    pub fn deinit(self: *Variable, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
        if (self.type) |t| allocator.free(t);
    }
};

pub const DAPClient = struct {
    allocator: std.mem.Allocator,
    process: ?std.process.Child,
    adapter_command: []const u8,
    adapter_args: []const[]const u8,

    breakpoints: std.ArrayList(Breakpoint),
    stack_frames: std.ArrayList(StackFrame),
    variables: std.ArrayList(Variable),

    next_request_id: usize,
    running: bool,

    pub fn init(allocator: std.mem.Allocator, adapter_command: []const u8, adapter_args: []const []const u8) DAPClient {
        return .{
            .allocator = allocator,
            .process = null,
            .adapter_command = adapter_command,
            .adapter_args = adapter_args,
            .breakpoints = std.ArrayList(Breakpoint){},
            .stack_frames = std.ArrayList(StackFrame){},
            .variables = std.ArrayList(Variable){},
            .next_request_id = 1,
            .running = false,
        };
    }

    pub fn deinit(self: *DAPClient) void {
        for (self.breakpoints.items) |*bp| {
            bp.deinit(self.allocator);
        }
        self.breakpoints.deinit(self.allocator);

        for (self.stack_frames.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.stack_frames.deinit(self.allocator);

        for (self.variables.items) |*variable| {
            variable.deinit(self.allocator);
        }
        self.variables.deinit(self.allocator);

        if (self.process) |*proc| {
            _ = proc.kill() catch {};
        }
    }

    pub fn start(self: *DAPClient, program_path: []const u8) !void {
        // Build command
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, self.adapter_command);
        for (self.adapter_args) |arg| {
            try argv.append(self.allocator, arg);
        }

        // Start adapter process
        var child = std.process.Child.init(argv.items, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        self.process = child;

        // Send initialize request
        try self.sendRequest("initialize", .{
            .clientID = "grim",
            .adapterID = "lldb",
            .linesStartAt1 = true,
            .columnsStartAt1 = true,
        });

        // Send launch request
        try self.sendRequest("launch", .{
            .program = program_path,
            .stopAtEntry = true,
        });

        self.running = true;
    }

    pub fn stop(self: *DAPClient) !void {
        if (self.process) |*proc| {
            try self.sendRequest("disconnect", .{});
            _ = try proc.wait();
            self.process = null;
        }
        self.running = false;
    }

    pub fn continue_(self: *DAPClient) !void {
        try self.sendRequest("continue", .{ .threadId = 1 });
    }

    pub fn stepOver(self: *DAPClient) !void {
        try self.sendRequest("next", .{ .threadId = 1 });
    }

    pub fn stepInto(self: *DAPClient) !void {
        try self.sendRequest("stepIn", .{ .threadId = 1 });
    }

    pub fn stepOut(self: *DAPClient) !void {
        try self.sendRequest("stepOut", .{ .threadId = 1 });
    }

    pub fn setBreakpoint(self: *DAPClient, filepath: []const u8, line: usize) !void {
        const bp = Breakpoint{
            .filepath = try self.allocator.dupe(u8, filepath),
            .line = line,
            .verified = false,
            .id = null,
        };
        try self.breakpoints.append(bp);

        // Send setBreakpoints request
        try self.sendRequest("setBreakpoints", .{
            .source = .{ .path = filepath },
            .breakpoints = &[_]struct { line: usize }{.{ .line = line }},
        });
    }

    pub fn removeBreakpoint(self: *DAPClient, filepath: []const u8, line: usize) !void {
        var i: usize = 0;
        while (i < self.breakpoints.items.len) {
            const bp = &self.breakpoints.items[i];
            if (std.mem.eql(u8, bp.filepath, filepath) and bp.line == line) {
                bp.deinit(self.allocator);
                _ = self.breakpoints.orderedRemove(i);
                break;
            }
            i += 1;
        }

        // Send updated breakpoints list
        try self.sendRequest("setBreakpoints", .{
            .source = .{ .path = filepath },
            .breakpoints = &[_]struct { line: usize }{},
        });
    }

    pub fn getStackTrace(self: *DAPClient) !void {
        try self.sendRequest("stackTrace", .{ .threadId = 1 });
    }

    pub fn getVariables(self: *DAPClient, frame_id: usize) !void {
        try self.sendRequest("scopes", .{ .frameId = frame_id });
    }

    fn sendRequest(self: *DAPClient, command: []const u8, arguments: anytype) !void {
        const proc = self.process orelse return error.NotStarted;

        // Build JSON-RPC request
        const request_id = self.next_request_id;
        self.next_request_id += 1;

        var json_buf = std.ArrayList(u8){};
        defer json_buf.deinit(self.allocator);

        try std.json.stringify(.{
            .seq = request_id,
            .type = "request",
            .command = command,
            .arguments = arguments,
        }, .{}, json_buf.writer());

        const content = json_buf.items;

        // Send Content-Length header + content
        const header = try std.fmt.allocPrint(
            self.allocator,
            "Content-Length: {d}\r\n\r\n",
            .{content.len},
        );
        defer self.allocator.free(header);

        try proc.stdin.?.writeAll(header);
        try proc.stdin.?.writeAll(content);
    }

    pub fn handleResponse(self: *DAPClient) !void {
        const proc = self.process orelse return;

        // Read response (simplified - should handle Content-Length)
        var buf: [8192]u8 = undefined;
        const bytes_read = try proc.stdout.?.read(&buf);

        if (bytes_read == 0) return;

        const response_text = buf[0..bytes_read];

        // Find JSON content after headers
        const json_start = std.mem.indexOf(u8, response_text, "{") orelse return;
        const json_content = response_text[json_start..];

        // Parse response
        var parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer parser.deinit();

        var tree = parser.parse(json_content) catch return;
        defer tree.deinit();

        // Handle different response types
        // (stack frames, variables, breakpoints, etc.)
        _ = tree;
    }
};

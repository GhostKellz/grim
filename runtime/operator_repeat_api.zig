const std = @import("std");
const core = @import("core");

/// Operator-Pending and Dot-Repeat API
/// Enables Vim-style operator composition and repeat functionality
pub const OperatorRepeatAPI = struct {
    allocator: std.mem.Allocator,
    last_operation: ?RecordedOperation = null,
    pending_operator: ?PendingOperator = null,
    operation_history: std.ArrayList(RecordedOperation),

    pub const OperatorType = enum {
        change,
        delete,
        yank,
        format,
        comment,
        surround,
        custom,
    };

    pub const MotionType = enum {
        char_wise,
        line_wise,
        block_wise,
    };

    pub const TextRange = struct {
        start: usize,
        end: usize,
        motion_type: MotionType,
    };

    pub const RecordedOperation = struct {
        operator: OperatorType,
        range: ?TextRange,
        replacement_text: ?[]const u8,
        count: usize,
        metadata: ?[]const u8, // JSON or custom data
        timestamp: i64,

        pub fn clone(self: *const RecordedOperation, allocator: std.mem.Allocator) !RecordedOperation {
            return RecordedOperation{
                .operator = self.operator,
                .range = self.range,
                .replacement_text = if (self.replacement_text) |text|
                    try allocator.dupe(u8, text)
                else
                    null,
                .count = self.count,
                .metadata = if (self.metadata) |meta|
                    try allocator.dupe(u8, meta)
                else
                    null,
                .timestamp = self.timestamp,
            };
        }

        pub fn deinit(self: *RecordedOperation, allocator: std.mem.Allocator) void {
            if (self.replacement_text) |text| allocator.free(text);
            if (self.metadata) |meta| allocator.free(meta);
        }
    };

    pub const PendingOperator = struct {
        operator: OperatorType,
        count: usize,
        started_at: i64,
        handler: *const fn (
            ctx: *anyopaque,
            operator: OperatorType,
            range: TextRange,
        ) anyerror!?[]const u8,
        ctx: *anyopaque,
    };

    pub const RepeatableCommand = struct {
        name: []const u8,
        execute: *const fn (ctx: *anyopaque, count: usize) anyerror!void,
        ctx: *anyopaque,
        count: usize,
    };

    pub fn init(allocator: std.mem.Allocator) OperatorRepeatAPI {
        return .{
            .allocator = allocator,
            .last_operation = null,
            .pending_operator = null,
            .operation_history = std.ArrayList(RecordedOperation){},
        };
    }

    pub fn deinit(self: *OperatorRepeatAPI) void {
        if (self.last_operation) |*op| {
            op.deinit(self.allocator);
        }
        for (self.operation_history.items) |*op| {
            op.deinit(self.allocator);
        }
        self.operation_history.deinit(self.allocator);
    }

    /// Start an operator-pending mode
    pub fn startOperator(
        self: *OperatorRepeatAPI,
        operator: OperatorType,
        count: usize,
        handler: *const fn (
            ctx: *anyopaque,
            operator: OperatorType,
            range: TextRange,
        ) anyerror!?[]const u8,
        ctx: *anyopaque,
    ) !void {
        self.pending_operator = PendingOperator{
            .operator = operator,
            .count = count,
            .started_at = std.time.milliTimestamp(),
            .handler = handler,
            .ctx = ctx,
        };
    }

    /// Complete a pending operator with a motion
    pub fn completeOperator(
        self: *OperatorRepeatAPI,
        range: TextRange,
    ) !?[]const u8 {
        const pending = self.pending_operator orelse return error.NoPendingOperator;

        // Execute the operator
        const result = try pending.handler(pending.ctx, pending.operator, range);

        // Record the operation
        const recorded = RecordedOperation{
            .operator = pending.operator,
            .range = range,
            .replacement_text = if (result) |text|
                try self.allocator.dupe(u8, text)
            else
                null,
            .count = pending.count,
            .metadata = null,
            .timestamp = std.time.milliTimestamp(),
        };

        // Store as last operation
        if (self.last_operation) |*old| {
            old.deinit(self.allocator);
        }
        self.last_operation = try recorded.clone(self.allocator);

        // Add to history
        try self.operation_history.append(self.allocator, recorded);

        // Clear pending operator
        self.pending_operator = null;

        return result;
    }

    /// Cancel a pending operator
    pub fn cancelOperator(self: *OperatorRepeatAPI) void {
        self.pending_operator = null;
    }

    /// Check if there's a pending operator
    pub fn hasPendingOperator(self: *const OperatorRepeatAPI) bool {
        return self.pending_operator != null;
    }

    /// Get the current pending operator type
    pub fn getPendingOperator(self: *const OperatorRepeatAPI) ?OperatorType {
        if (self.pending_operator) |pending| {
            return pending.operator;
        }
        return null;
    }

    /// Repeat the last operation (Vim's dot command)
    pub fn repeatLast(
        self: *OperatorRepeatAPI,
        ctx: *anyopaque,
        execute_fn: *const fn (ctx: *anyopaque, op: RecordedOperation) anyerror!void,
    ) !void {
        const last_op = self.last_operation orelse return error.NoOperationToRepeat;
        try execute_fn(ctx, last_op);
    }

    /// Repeat the last operation N times
    pub fn repeatLastN(
        self: *OperatorRepeatAPI,
        ctx: *anyopaque,
        count: usize,
        execute_fn: *const fn (ctx: *anyopaque, op: RecordedOperation) anyerror!void,
    ) !void {
        const last_op = self.last_operation orelse return error.NoOperationToRepeat;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try execute_fn(ctx, last_op);
        }
    }

    /// Record a simple operation (for non-operator commands)
    pub fn recordOperation(
        self: *OperatorRepeatAPI,
        operator: OperatorType,
        range: ?TextRange,
        replacement_text: ?[]const u8,
        count: usize,
        metadata: ?[]const u8,
    ) !void {
        const recorded = RecordedOperation{
            .operator = operator,
            .range = range,
            .replacement_text = if (replacement_text) |text|
                try self.allocator.dupe(u8, text)
            else
                null,
            .count = count,
            .metadata = if (metadata) |meta|
                try self.allocator.dupe(u8, meta)
            else
                null,
            .timestamp = std.time.milliTimestamp(),
        };

        if (self.last_operation) |*old| {
            old.deinit(self.allocator);
        }
        self.last_operation = try recorded.clone(self.allocator);

        try self.operation_history.append(self.allocator, recorded);
    }

    /// Get operation history
    pub fn getHistory(self: *const OperatorRepeatAPI) []const RecordedOperation {
        return self.operation_history.items;
    }

    /// Clear operation history
    pub fn clearHistory(self: *OperatorRepeatAPI) void {
        for (self.operation_history.items) |*op| {
            op.deinit(self.allocator);
        }
        self.operation_history.clearRetainingCapacity();

        if (self.last_operation) |*op| {
            op.deinit(self.allocator);
            self.last_operation = null;
        }
    }

    /// Export operation history as JSON
    pub fn exportHistoryJSON(self: *const OperatorRepeatAPI) ![]const u8 {
        var buffer = std.ArrayList(u8){};
        errdefer buffer.deinit(self.allocator);

        var writer = buffer.writer();
        try writer.writeAll("[");

        for (self.operation_history.items, 0..) |op, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("{");
            try writer.print("\"operator\":\"{s}\",", .{@tagName(op.operator)});
            try writer.print("\"count\":{d},", .{op.count});
            try writer.print("\"timestamp\":{d}", .{op.timestamp});

            if (op.range) |range| {
                try writer.print(",\"range\":{{\"start\":{d},\"end\":{d},\"motion\":\"{s}\"}}", .{
                    range.start,
                    range.end,
                    @tagName(range.motion_type),
                });
            }

            try writer.writeAll("}");
        }

        try writer.writeAll("]");
        return buffer.toOwnedSlice(self.allocator);
    }
};

test "OperatorRepeatAPI pending operator" {
    const allocator = std.testing.allocator;
    var api = OperatorRepeatAPI.init(allocator);
    defer api.deinit();

    const TestCtx = struct {
        executed: bool = false,
        operator_type: ?OperatorRepeatAPI.OperatorType = null,
        range: ?OperatorRepeatAPI.TextRange = null,

        fn handler(
            ctx: *anyopaque,
            operator: OperatorRepeatAPI.OperatorType,
            range: OperatorRepeatAPI.TextRange,
        ) !?[]const u8 {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            self.executed = true;
            self.operator_type = operator;
            self.range = range;
            return null;
        }
    };

    var test_ctx = TestCtx{};

    try std.testing.expect(!api.hasPendingOperator());

    try api.startOperator(.delete, 1, TestCtx.handler, &test_ctx);
    try std.testing.expect(api.hasPendingOperator());
    try std.testing.expectEqual(OperatorRepeatAPI.OperatorType.delete, api.getPendingOperator().?);

    const range = OperatorRepeatAPI.TextRange{
        .start = 0,
        .end = 10,
        .motion_type = .char_wise,
    };

    _ = try api.completeOperator(range);

    try std.testing.expect(test_ctx.executed);
    try std.testing.expectEqual(OperatorRepeatAPI.OperatorType.delete, test_ctx.operator_type.?);
    try std.testing.expectEqual(@as(usize, 0), test_ctx.range.?.start);
    try std.testing.expectEqual(@as(usize, 10), test_ctx.range.?.end);
    try std.testing.expect(!api.hasPendingOperator());
}

test "OperatorRepeatAPI dot repeat" {
    const allocator = std.testing.allocator;
    var api = OperatorRepeatAPI.init(allocator);
    defer api.deinit();

    // Record an operation
    try api.recordOperation(
        .change,
        .{ .start = 5, .end = 10, .motion_type = .char_wise },
        "hello",
        1,
        null,
    );

    try std.testing.expect(api.last_operation != null);

    const TestCtx = struct {
        execute_count: usize = 0,

        fn execute(ctx: *anyopaque, op: OperatorRepeatAPI.RecordedOperation) !void {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx)));
            self.execute_count += 1;
            try std.testing.expectEqual(OperatorRepeatAPI.OperatorType.change, op.operator);
        }
    };

    var test_ctx = TestCtx{};

    try api.repeatLast(&test_ctx, TestCtx.execute);
    try std.testing.expectEqual(@as(usize, 1), test_ctx.execute_count);

    try api.repeatLastN(&test_ctx, 3, TestCtx.execute);
    try std.testing.expectEqual(@as(usize, 4), test_ctx.execute_count);
}

test "OperatorRepeatAPI history" {
    const allocator = std.testing.allocator;
    var api = OperatorRepeatAPI.init(allocator);
    defer api.deinit();

    try api.recordOperation(.delete, null, null, 1, null);
    try api.recordOperation(.change, null, "test", 1, null);
    try api.recordOperation(.yank, null, null, 1, null);

    const history = api.getHistory();
    try std.testing.expectEqual(@as(usize, 3), history.len);

    const json = try api.exportHistoryJSON();
    defer allocator.free(json);
    try std.testing.expect(json.len > 0);
}

const std = @import("std");
const zsync = @import("zsync");

/// Zsync integration for Grim LSP server
/// Provides optimized async runtime configuration and diagnostics
pub const ZsyncIntegration = struct {
    runtime: *zsync.Runtime,
    config: zsync.Config,
    allocator: std.mem.Allocator,

    /// Initialize zsync runtime with optimal LSP server configuration
    pub fn init(allocator: std.mem.Allocator) !*ZsyncIntegration {
        const self = try allocator.create(ZsyncIntegration);
        errdefer allocator.destroy(self);

        // Use zsync Config.forServer() for optimal LSP performance
        const config = zsync.Config.forServer();
        const runtime = try zsync.Runtime.init(allocator, config);

        self.* = .{
            .runtime = runtime,
            .config = config,
            .allocator = allocator,
        };

        return self;
    }

    /// Initialize with custom configuration using RuntimeBuilder
    pub fn initWithBuilder(allocator: std.mem.Allocator, configure_fn: fn (*zsync.RuntimeBuilder) void) !*ZsyncIntegration {
        const self = try allocator.create(ZsyncIntegration);
        errdefer allocator.destroy(self);

        var builder = zsync.RuntimeBuilder.init(allocator);
        configure_fn(&builder);
        const runtime = try builder.build();
        const config = builder.config;

        self.* = .{
            .runtime = runtime,
            .config = config,
            .allocator = allocator,
        };

        return self;
    }

    /// Initialize with optimal configuration for current platform
    pub fn initOptimal(allocator: std.mem.Allocator) !*ZsyncIntegration {
        const self = try allocator.create(ZsyncIntegration);
        errdefer allocator.destroy(self);

        const config = zsync.Config.optimal();
        const runtime = try zsync.Runtime.init(allocator, config);

        self.* = .{
            .runtime = runtime,
            .config = config,
            .allocator = allocator,
        };

        return self;
    }

    pub fn deinit(self: *ZsyncIntegration) void {
        self.runtime.deinit();
        self.allocator.destroy(self);
    }

    /// Get the zsync Io interface for async operations
    pub fn getIo(self: *ZsyncIntegration) zsync.io_interface.Io {
        return self.runtime.getIo();
    }

    /// Run the LSP server task with zsync runtime
    pub fn runServer(self: *ZsyncIntegration, comptime task_fn: anytype, args: anytype) !void {
        try self.runtime.run(task_fn, args);
    }

    /// Print runtime capabilities and diagnostics
    pub fn printDiagnostics(self: *ZsyncIntegration) void {
        std.debug.print("\n=== Grim LSP Server - Zsync Runtime ===\n", .{});
        std.debug.print("Execution Model: {s}\n", .{@tagName(self.runtime.getExecutionModel())});
        std.debug.print("Thread Pool Size: {d}\n", .{self.config.thread_pool_threads});
        std.debug.print("Buffer Size: {d} bytes\n", .{self.config.buffer_size});
        std.debug.print("Zero-Copy Enabled: {}\n", .{self.config.enable_zero_copy});
        std.debug.print("Vectorized I/O Enabled: {}\n", .{self.config.enable_vectorized_io});
        std.debug.print("Metrics Enabled: {}\n", .{self.config.enable_metrics});
        std.debug.print("============================================\n\n", .{});
    }

    /// Print runtime metrics
    pub fn printMetrics(self: *ZsyncIntegration) void {
        const metrics = self.runtime.getMetrics();
        std.debug.print("\n=== Zsync Runtime Metrics ===\n", .{});
        std.debug.print("Tasks: {} spawned, {} completed\n", .{
            metrics.tasks_spawned.load(.monotonic),
            metrics.tasks_completed.load(.monotonic),
        });
        std.debug.print("Futures: {} created, {} cancelled\n", .{
            metrics.futures_created.load(.monotonic),
            metrics.futures_cancelled.load(.monotonic),
        });
        std.debug.print("I/O Operations: {}, Avg Latency: {}ns\n", .{
            metrics.total_io_operations.load(.monotonic),
            metrics.average_latency_ns.load(.monotonic),
        });
        std.debug.print("============================\n\n", .{});
    }

    /// Validate configuration and print warnings
    pub fn validateConfig(self: *ZsyncIntegration) !void {
        try self.config.validate();
    }
};

/// Create a zsync runtime with LSP-optimized configuration
pub fn createLspRuntime(allocator: std.mem.Allocator) !*zsync.Runtime {
    const config = zsync.Config.forServer();
    return try zsync.Runtime.init(allocator, config);
}

/// Create a zsync runtime with custom configuration using builder pattern
pub fn createCustomRuntime(
    allocator: std.mem.Allocator,
    comptime configure: fn (*zsync.RuntimeBuilder) void,
) !*zsync.Runtime {
    var builder = zsync.RuntimeBuilder.init(allocator);
    configure(&builder);
    return try builder.build();
}

/// Example configuration for high-throughput LSP server
pub fn configureHighThroughput(builder: *zsync.RuntimeBuilder) void {
    _ = builder
        .executionModel(.thread_pool)
        .threads(16)
        .bufferSize(8192)
        .enableZeroCopy()
        .enableVectorizedIo()
        .enableMetrics();
}

/// Example configuration for low-latency LSP server
pub fn configureLowLatency(builder: *zsync.RuntimeBuilder) void {
    const cpu_count = std.Thread.getCpuCount() catch 4;
    _ = builder
        .executionModel(.thread_pool)
        .threads(@intCast(@min(cpu_count * 2, 8)))
        .bufferSize(4096)
        .enableZeroCopy()
        .enableVectorizedIo();
}

/// Example configuration for debugging
pub fn configureDebug(builder: *zsync.RuntimeBuilder) void {
    _ = builder
        .executionModel(.blocking)
        .enableMetrics()
        .enableDebugging();
}

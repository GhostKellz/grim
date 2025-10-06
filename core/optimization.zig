const std = @import("std");
const Rope = @import("rope.zig").Rope;

/// Performance optimization utilities for Grim core systems
pub const Optimization = struct {
    /// Rope optimization parameters
    pub const RopeConfig = struct {
        // Minimum piece size before merging small adjacent pieces
        min_piece_size: usize = 64,
        // Maximum piece size before splitting large pieces
        max_piece_size: usize = 4096,
        // Threshold for triggering defragmentation
        fragmentation_threshold: f32 = 0.3,
        // Enable piece merging on insertions
        enable_piece_merging: bool = true,
        // Enable lazy deletion (mark for deletion instead of immediate removal)
        enable_lazy_deletion: bool = true,
    };

    /// Rope performance optimizer
    pub const RopeOptimizer = struct {
        config: RopeConfig,
        stats: Stats,

        pub const Stats = struct {
            total_pieces: usize = 0,
            total_size: usize = 0,
            small_pieces: usize = 0,
            large_pieces: usize = 0,
            fragmentation_ratio: f32 = 0.0,
            merge_operations: usize = 0,
            split_operations: usize = 0,
            last_optimization: i64 = 0,

            pub fn calculateFragmentation(self: *Stats) void {
                if (self.total_pieces == 0) {
                    self.fragmentation_ratio = 0.0;
                } else {
                    self.fragmentation_ratio = @as(f32, @floatFromInt(self.small_pieces)) / @as(f32, @floatFromInt(self.total_pieces));
                }
            }
        };

        pub fn init(config: RopeConfig) RopeOptimizer {
            return .{
                .config = config,
                .stats = .{},
            };
        }

        /// Analyze rope structure and update statistics
        pub fn analyzeRope(self: *RopeOptimizer, rope: *const Rope) void {
            self.stats = .{};

            for (rope.pieces.items) |piece| {
                const piece_size = piece.len();
                self.stats.total_pieces += 1;
                self.stats.total_size += piece_size;

                if (piece_size < self.config.min_piece_size) {
                    self.stats.small_pieces += 1;
                } else if (piece_size > self.config.max_piece_size) {
                    self.stats.large_pieces += 1;
                }
            }

            self.stats.calculateFragmentation();
        }

        /// Check if rope needs optimization
        pub fn needsOptimization(self: *const RopeOptimizer) bool {
            return self.stats.fragmentation_ratio > self.config.fragmentation_threshold;
        }

        /// Suggest optimization strategy
        pub const OptimizationStrategy = enum {
            none,
            merge_small_pieces,
            split_large_pieces,
            defragment,
            rebuild,
        };

        pub fn suggestStrategy(self: *const RopeOptimizer) OptimizationStrategy {
            if (self.stats.fragmentation_ratio > self.config.fragmentation_threshold) {
                if (self.stats.small_pieces > self.stats.total_pieces / 2) {
                    return .merge_small_pieces;
                } else if (self.stats.large_pieces > 0) {
                    return .split_large_pieces;
                } else {
                    return .defragment;
                }
            }
            return .none;
        }

        /// Get performance report
        pub fn getReport(self: *const RopeOptimizer, allocator: std.mem.Allocator) ![]u8 {
            return std.fmt.allocPrint(allocator,
                \\Rope Performance Analysis:
                \\  Total pieces: {d}
                \\  Total size: {d} bytes
                \\  Small pieces: {d} ({d:.1}%)
                \\  Large pieces: {d} ({d:.1}%)
                \\  Fragmentation: {d:.1}%
                \\  Merge operations: {d}
                \\  Split operations: {d}
                \\  Suggested strategy: {s}
            , .{
                self.stats.total_pieces,
                self.stats.total_size,
                self.stats.small_pieces,
                if (self.stats.total_pieces > 0) @as(f32, @floatFromInt(self.stats.small_pieces)) * 100.0 / @as(f32, @floatFromInt(self.stats.total_pieces)) else 0.0,
                self.stats.large_pieces,
                if (self.stats.total_pieces > 0) @as(f32, @floatFromInt(self.stats.large_pieces)) * 100.0 / @as(f32, @floatFromInt(self.stats.total_pieces)) else 0.0,
                self.stats.fragmentation_ratio * 100.0,
                self.stats.merge_operations,
                self.stats.split_operations,
                @tagName(self.suggestStrategy()),
            });
        }
    };

    /// Memory pool for frequent allocations
    pub const MemoryPool = struct {
        allocator: std.mem.Allocator,
        pools: std.EnumArray(PoolType, Pool),

        const PoolType = enum {
            small_buffers, // <= 256 bytes
            medium_buffers, // <= 4KB
            large_buffers, // <= 64KB
        };

        const Pool = struct {
            items: std.ArrayList([]u8),
            item_size: usize,
            max_items: usize,

            fn init(allocator: std.mem.Allocator, item_size: usize, max_items: usize) Pool {
                return .{
                    .items = std.ArrayList([]u8).init(allocator),
                    .item_size = item_size,
                    .max_items = max_items,
                };
            }

            fn deinit(self: *Pool, allocator: std.mem.Allocator) void {
                for (self.items.items) |item| {
                    allocator.free(item);
                }
                self.items.deinit();
            }
        };

        pub fn init(allocator: std.mem.Allocator) MemoryPool {
            var pools = std.EnumArray(PoolType, Pool).initUndefined();
            pools.set(.small_buffers, Pool.init(allocator, 256, 100));
            pools.set(.medium_buffers, Pool.init(allocator, 4096, 50));
            pools.set(.large_buffers, Pool.init(allocator, 65536, 10));

            return .{
                .allocator = allocator,
                .pools = pools,
            };
        }

        pub fn deinit(self: *MemoryPool) void {
            for (std.meta.tags(PoolType)) |pool_type| {
                self.pools.getPtr(pool_type).deinit(self.allocator);
            }
        }

        fn getPoolType(size: usize) PoolType {
            if (size <= 256) return .small_buffers;
            if (size <= 4096) return .medium_buffers;
            return .large_buffers;
        }

        pub fn acquire(self: *MemoryPool, size: usize) ![]u8 {
            const pool_type = getPoolType(size);
            var pool = self.pools.getPtr(pool_type);

            if (pool.items.items.len > 0) {
                const item = pool.items.pop();
                return item[0..size]; // Return only requested size
            }

            // Allocate new buffer
            return try self.allocator.alloc(u8, pool.item_size);
        }

        pub fn release(self: *MemoryPool, buffer: []u8) void {
            const pool_type = getPoolType(buffer.len);
            var pool = self.pools.getPtr(pool_type);

            if (pool.items.items.len < pool.max_items) {
                pool.items.append(buffer) catch {
                    // If append fails, just free the buffer
                    self.allocator.free(buffer);
                };
            } else {
                self.allocator.free(buffer);
            }
        }
    };

    /// Performance monitoring and metrics
    pub const PerformanceMonitor = struct {
        allocator: std.mem.Allocator,
        metrics: std.StringHashMap(Metric),
        start_time: i64,

        const Metric = struct {
            count: u64,
            total_time: u64, // nanoseconds
            min_time: u64,
            max_time: u64,
            last_time: u64,

            pub fn update(self: *Metric, time_ns: u64) void {
                self.count += 1;
                self.total_time += time_ns;
                self.min_time = if (self.count == 1) time_ns else @min(self.min_time, time_ns);
                self.max_time = @max(self.max_time, time_ns);
                self.last_time = time_ns;
            }

            pub fn averageTime(self: *const Metric) f64 {
                if (self.count == 0) return 0.0;
                return @as(f64, @floatFromInt(self.total_time)) / @as(f64, @floatFromInt(self.count));
            }
        };

        pub fn init(allocator: std.mem.Allocator) PerformanceMonitor {
            return .{
                .allocator = allocator,
                .metrics = std.StringHashMap(Metric).init(allocator),
                .start_time = std.time.nanoTimestamp(),
            };
        }

        pub fn deinit(self: *PerformanceMonitor) void {
            self.metrics.deinit();
        }

        pub fn startTimer(self: *PerformanceMonitor, name: []const u8) Timer {
            _ = self;
            return Timer{
                .name = name,
                .start_time = std.time.nanoTimestamp(),
            };
        }

        pub fn recordTime(self: *PerformanceMonitor, name: []const u8, time_ns: u64) !void {
            const result = try self.metrics.getOrPut(name);
            if (!result.found_existing) {
                result.value_ptr.* = .{
                    .count = 0,
                    .total_time = 0,
                    .min_time = 0,
                    .max_time = 0,
                    .last_time = 0,
                };
            }
            result.value_ptr.update(time_ns);
        }

        pub fn getMetrics(self: *const PerformanceMonitor, allocator: std.mem.Allocator) ![]u8 {
            var result = std.ArrayList(u8).init(allocator);
            defer result.deinit();

            try result.appendSlice("Performance Metrics:\n");

            var iterator = self.metrics.iterator();
            while (iterator.next()) |entry| {
                const metric = entry.value_ptr.*;
                const avg_ms = metric.averageTime() / std.time.ns_per_ms;
                const min_ms = @as(f64, @floatFromInt(metric.min_time)) / std.time.ns_per_ms;
                const max_ms = @as(f64, @floatFromInt(metric.max_time)) / std.time.ns_per_ms;

                try result.writer().print("  {s}: {d} calls, avg: {d:.2}ms, min: {d:.2}ms, max: {d:.2}ms\n", .{ entry.key_ptr.*, metric.count, avg_ms, min_ms, max_ms });
            }

            return result.toOwnedSlice();
        }

        const Timer = struct {
            name: []const u8,
            start_time: i64,

            pub fn end(self: Timer, monitor: *PerformanceMonitor) void {
                const end_time = std.time.nanoTimestamp();
                const duration = @as(u64, @intCast(end_time - self.start_time));
                monitor.recordTime(self.name, duration) catch {};
            }
        };
    };

    /// Cache for frequently accessed data
    pub const Cache = struct {
        allocator: std.mem.Allocator,
        entries: std.StringHashMap(Entry),
        max_size: usize,
        current_size: usize,

        const Entry = struct {
            data: []const u8,
            last_access: i64,
            access_count: u32,
        };

        pub fn init(allocator: std.mem.Allocator, max_size: usize) Cache {
            return .{
                .allocator = allocator,
                .entries = std.StringHashMap(Entry).init(allocator),
                .max_size = max_size,
                .current_size = 0,
            };
        }

        pub fn deinit(self: *Cache) void {
            var iterator = self.entries.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.value_ptr.data);
            }
            self.entries.deinit();
        }

        pub fn put(self: *Cache, key: []const u8, data: []const u8) !void {
            // Check if we need to evict entries
            while (self.current_size + data.len > self.max_size and self.entries.count() > 0) {
                try self.evictLRU();
            }

            const data_copy = try self.allocator.dupe(u8, data);
            const key_copy = try self.allocator.dupe(u8, key);

            const result = try self.entries.getOrPut(key_copy);
            if (result.found_existing) {
                self.allocator.free(result.value_ptr.data);
                self.current_size -= result.value_ptr.data.len;
            }

            result.value_ptr.* = .{
                .data = data_copy,
                .last_access = std.time.nanoTimestamp(),
                .access_count = 1,
            };

            self.current_size += data.len;
        }

        pub fn get(self: *Cache, key: []const u8) ?[]const u8 {
            if (self.entries.getPtr(key)) |entry| {
                entry.last_access = std.time.nanoTimestamp();
                entry.access_count += 1;
                return entry.data;
            }
            return null;
        }

        fn evictLRU(self: *Cache) !void {
            var oldest_key: ?[]const u8 = null;
            var oldest_time: i64 = std.time.nanoTimestamp();

            var iterator = self.entries.iterator();
            while (iterator.next()) |entry| {
                if (entry.value_ptr.last_access < oldest_time) {
                    oldest_time = entry.value_ptr.last_access;
                    oldest_key = entry.key_ptr.*;
                }
            }

            if (oldest_key) |key| {
                const entry = self.entries.get(key).?;
                self.current_size -= entry.data.len;
                self.allocator.free(entry.data);
                _ = self.entries.remove(key);
                self.allocator.free(key);
            }
        }

        pub fn getStats(self: *const Cache) struct { entries: u32, size: usize, max_size: usize } {
            return .{
                .entries = @intCast(self.entries.count()),
                .size = self.current_size,
                .max_size = self.max_size,
            };
        }
    };
};

// Tests for optimization utilities
test "rope optimizer analysis" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    // Add some content to test analysis
    try rope.insert(0, "Hello");
    try rope.insert(5, " ");
    try rope.insert(6, "World");

    var optimizer = Optimization.RopeOptimizer.init(.{});
    optimizer.analyzeRope(&rope);

    try std.testing.expect(optimizer.stats.total_pieces > 0);
    try std.testing.expect(optimizer.stats.total_size > 0);
}

test "memory pool operations" {
    const allocator = std.testing.allocator;
    var pool = Optimization.MemoryPool.init(allocator);
    defer pool.deinit();

    // Test acquiring and releasing buffers
    const buffer1 = try pool.acquire(100);
    const buffer2 = try pool.acquire(1000);
    const buffer3 = try pool.acquire(10000);

    pool.release(buffer1);
    pool.release(buffer2);
    pool.release(buffer3);

    // Try to reuse released buffers
    const reused_buffer = try pool.acquire(100);
    pool.release(reused_buffer);
}

test "performance monitor" {
    const allocator = std.testing.allocator;
    var monitor = Optimization.PerformanceMonitor.init(allocator);
    defer monitor.deinit();

    // Test recording metrics
    try monitor.recordTime("test_operation", 1000000); // 1ms in ns
    try monitor.recordTime("test_operation", 2000000); // 2ms in ns

    const metrics_report = try monitor.getMetrics(allocator);
    defer allocator.free(metrics_report);

    try std.testing.expect(std.mem.indexOf(u8, metrics_report, "test_operation") != null);
}

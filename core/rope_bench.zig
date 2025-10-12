const std = @import("std");
const Rope = @import("rope.zig").Rope;
const Range = @import("rope.zig").Range;

/// Benchmark configuration
const BenchConfig = struct {
    iterations: usize = 1000,
    warmup_iterations: usize = 100,
};

/// Timing result for a benchmark
const BenchResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    avg_ns: u64,
    ops_per_sec: f64,

    fn print(self: BenchResult) void {
        std.debug.print("{s}:\n", .{self.name});
        std.debug.print("  Iterations: {d}\n", .{self.iterations});
        std.debug.print("  Total: {d}ns ({d}ms)\n", .{ self.total_ns, self.total_ns / 1_000_000 });
        std.debug.print("  Average: {d}ns ({d}µs)\n", .{ self.avg_ns, self.avg_ns / 1_000 });
        std.debug.print("  Throughput: {d:.2} ops/sec\n\n", .{self.ops_per_sec});
    }
};

/// Run a benchmark with timing
fn runBenchmark(
    comptime name: []const u8,
    config: BenchConfig,
    comptime func: fn (allocator: std.mem.Allocator) anyerror!void,
    allocator: std.mem.Allocator,
) !BenchResult {
    // Warmup
    var i: usize = 0;
    while (i < config.warmup_iterations) : (i += 1) {
        try func(allocator);
    }

    // Actual benchmark
    var timer = try std.time.Timer.start();
    i = 0;
    while (i < config.iterations) : (i += 1) {
        try func(allocator);
    }
    const elapsed_ns = timer.read();

    const avg_ns = elapsed_ns / config.iterations;
    const ops_per_sec = @as(f64, @floatFromInt(config.iterations)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

    return BenchResult{
        .name = name,
        .iterations = config.iterations,
        .total_ns = elapsed_ns,
        .avg_ns = avg_ns,
        .ops_per_sec = ops_per_sec,
    };
}

// ============================================================================
// BENCHMARK IMPLEMENTATIONS
// ============================================================================

fn benchRopeInsertSmall(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
}

fn benchRopeInsertMedium(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    const text = "This is a medium sized text block for benchmarking rope insert operations.";
    try rope.insert(0, text);
}

fn benchRopeInsertMultiple(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
    try rope.insert(5, " ");
    try rope.insert(6, "world");
    try rope.insert(11, "!");
}

fn benchRopeDeleteSmall(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello world");
    try rope.delete(5, 6); // Delete " world"
}

fn benchRopeSliceSinglePiece(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello world");
    _ = try rope.slice(.{ .start = 0, .end = rope.len() });
}

fn benchRopeSliceMultiPiece(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
    try rope.insert(5, " ");
    try rope.insert(6, "world");

    _ = try rope.slice(.{ .start = 0, .end = rope.len() });
}

fn benchRopeIteratorZeroCopy(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
    try rope.insert(5, " ");
    try rope.insert(6, "world");
    try rope.insert(11, "!");

    var iter = rope.iterator(.{ .start = 0, .end = rope.len() });
    var total: usize = 0;
    while (iter.next()) |segment| {
        total += segment.len;
    }
    std.mem.doNotOptimizeAway(total);
}

fn benchRopeLineCount(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "line 1\nline 2\nline 3\nline 4\nline 5");

    // First call: O(n) calculation
    _ = rope.lineCount();
    // Second call: O(1) cached
    _ = rope.lineCount();
}

fn benchRopeLineRange(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "line 1\nline 2\nline 3\nline 4\nline 5");

    _ = try rope.lineRange(2);
}

fn benchRopeSnapshotRestore(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello world");
    const snap = try rope.snapshot();
    try rope.insert(11, " again");
    try rope.restore(snap);
}

fn benchRopeLargeFile(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    // Simulate a large file (1000 lines)
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try rope.insert(rope.len(), "This is a line of text in a large file for performance testing.\n");
    }

    // Do some operations
    _ = rope.lineCount();
    _ = try rope.slice(.{ .start = 0, .end = @min(100, rope.len()) });
}

fn benchRopeHugeFile10MB(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    // Simulate 10MB file (~160k lines of 64 bytes each)
    const line = "The quick brown fox jumps over the lazy dog. Line content here.\n";
    var i: usize = 0;
    while (i < 160_000) : (i += 1) {
        try rope.insert(rope.len(), line);
    }

    // Perform operations on huge file
    _ = rope.lineCount();
    _ = try rope.lineRange(80_000); // Middle line
    _ = try rope.slice(.{ .start = 5_000_000, .end = 5_000_100 }); // Middle slice
}

fn benchRopeHugeFileRandomAccess(allocator: std.mem.Allocator) !void {
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    // Build medium file (10k lines)
    const line = "Random access test line with some content in it for benchmarking.\n";
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        try rope.insert(rope.len(), line);
    }

    // Random access patterns (common in editing)
    _ = try rope.lineRange(1_000);
    _ = try rope.lineRange(5_000);
    _ = try rope.lineRange(9_000);
    _ = try rope.slice(.{ .start = 100_000, .end = 100_100 });
    _ = try rope.slice(.{ .start = 300_000, .end = 300_100 });
}

// ============================================================================
// MAIN BENCHMARK RUNNER
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BenchConfig{
        .iterations = 10000,
        .warmup_iterations = 100,
    };

    const large_config = BenchConfig{
        .iterations = 100,
        .warmup_iterations = 10,
    };

    std.debug.print("\n=== GRIM ROPE BENCHMARKS ===\n\n", .{});

    // Insert benchmarks
    std.debug.print("--- INSERT OPERATIONS ---\n", .{});
    (try runBenchmark("Insert Small (5 bytes)", config, benchRopeInsertSmall, allocator)).print();
    (try runBenchmark("Insert Medium (75 bytes)", config, benchRopeInsertMedium, allocator)).print();
    (try runBenchmark("Insert Multiple (4 pieces)", config, benchRopeInsertMultiple, allocator)).print();

    // Delete benchmarks
    std.debug.print("--- DELETE OPERATIONS ---\n", .{});
    (try runBenchmark("Delete Small (6 bytes)", config, benchRopeDeleteSmall, allocator)).print();

    // Slice benchmarks
    std.debug.print("--- SLICE OPERATIONS ---\n", .{});
    (try runBenchmark("Slice Single Piece (zero-copy)", config, benchRopeSliceSinglePiece, allocator)).print();
    (try runBenchmark("Slice Multi-Piece (arena alloc)", config, benchRopeSliceMultiPiece, allocator)).print();
    (try runBenchmark("Iterator Zero-Copy", config, benchRopeIteratorZeroCopy, allocator)).print();

    // Line operations
    std.debug.print("--- LINE OPERATIONS ---\n", .{});
    (try runBenchmark("Line Count (O(1) cached)", config, benchRopeLineCount, allocator)).print();
    (try runBenchmark("Line Range Lookup", config, benchRopeLineRange, allocator)).print();

    // Snapshot/restore
    std.debug.print("--- SNAPSHOT/RESTORE ---\n", .{});
    (try runBenchmark("Snapshot + Restore", config, benchRopeSnapshotRestore, allocator)).print();

    // Large file benchmarks
    std.debug.print("--- LARGE FILE (1000 lines) ---\n", .{});
    (try runBenchmark("Large File Operations", large_config, benchRopeLargeFile, allocator)).print();

    // Huge file benchmarks (fewer iterations)
    const huge_config = BenchConfig{
        .iterations = 5,
        .warmup_iterations = 1,
    };

    std.debug.print("--- HUGE FILE (10MB / 160k lines) ---\n", .{});
    (try runBenchmark("10MB File Build + Operations", huge_config, benchRopeHugeFile10MB, allocator)).print();
    (try runBenchmark("Medium File Random Access", huge_config, benchRopeHugeFileRandomAccess, allocator)).print();

    std.debug.print("=== BENCHMARKS COMPLETE ===\n\n", .{});
}

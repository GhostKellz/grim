//! Grim Performance Benchmarking Suite
//!
//! Benchmarks:
//! - Rope operations (insert, delete, slice)
//! - LSP client performance
//! - Rendering performance
//! - Plugin loading/execution
//! - Memory allocation patterns

const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Grim Performance Benchmark Suite ===\n", .{});

    try benchmarkRope(allocator);
    try benchmarkFuzzyFinder(allocator);
    try benchmarkRendering(allocator);
    try benchmarkMemory(allocator);

    std.log.info("\n=== Benchmark Complete ===", .{});
}

// ==================
// Rope Benchmarks
// ==================

fn benchmarkRope(allocator: std.mem.Allocator) !void {
    std.log.info("--- Rope Benchmarks ---", .{});

    // Benchmark: Sequential inserts
    {
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        const iterations = 10_000;
        const start = std.time.nanoTimestamp();

        for (0..iterations) |i| {
            const text = try std.fmt.allocPrint(allocator, "Line {d}\n", .{i});
            defer allocator.free(text);
            try rope.insert(rope.length(), text);
        }

        const elapsed_ns = std.time.nanoTimestamp() - start;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

        std.log.info("Sequential inserts: {d} ops in {d}ms ({d:.0} ops/sec)", .{
            iterations,
            @divTrunc(elapsed_ns, 1_000_000),
            ops_per_sec,
        });
    }

    // Benchmark: Random inserts
    {
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        // Seed with some content
        try rope.insert(0, "Hello, World!\n" ** 100);

        var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();

        const iterations = 1_000;
        const start = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            const pos = random.intRangeAtMost(usize, 0, rope.length());
            try rope.insert(pos, "X");
        }

        const elapsed_ns = std.time.nanoTimestamp() - start;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

        std.log.info("Random inserts: {d} ops in {d}ms ({d:.0} ops/sec)", .{
            iterations,
            @divTrunc(elapsed_ns, 1_000_000),
            ops_per_sec,
        });
    }

    // Benchmark: Delete operations
    {
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        // Seed with content
        try rope.insert(0, "X" ** 10_000);

        const iterations = 1_000;
        const start = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            if (rope.length() > 0) {
                try rope.delete(0, 1);
            }
        }

        const elapsed_ns = std.time.nanoTimestamp() - start;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

        std.log.info("Delete operations: {d} ops in {d}ms ({d:.0} ops/sec)", .{
            iterations,
            @divTrunc(elapsed_ns, 1_000_000),
            ops_per_sec,
        });
    }

    // Benchmark: Slice operations (critical for rendering)
    {
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        try rope.insert(0, "The quick brown fox jumps over the lazy dog.\n" ** 1000);

        const iterations = 10_000;
        const start = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            const slice = try rope.slice(.{ .start = 0, .end = 100 });
            allocator.free(slice);
        }

        const elapsed_ns = std.time.nanoTimestamp() - start;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

        std.log.info("Slice operations: {d} ops in {d}ms ({d:.0} ops/sec)", .{
            iterations,
            @divTrunc(elapsed_ns, 1_000_000),
            ops_per_sec,
        });
    }

    std.log.info("", .{});
}

// ==================
// Fuzzy Finder Benchmarks
// ==================

fn benchmarkFuzzyFinder(allocator: std.mem.Allocator) !void {
    std.log.info("--- Fuzzy Finder Benchmarks ---", .{});

    // Generate test file list
    var files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (files.items) |file| allocator.free(file);
        files.deinit();
    }

    for (0..1000) |i| {
        const file = try std.fmt.allocPrint(allocator, "src/module_{d}/file_{d}.zig", .{ i / 100, i });
        try files.append(file);
    }

    // Benchmark: Fuzzy search
    {
        var fuzzy = core.FuzzyFinder.init(allocator);
        defer fuzzy.deinit();

        try fuzzy.setItems(files.items);

        const queries = [_][]const u8{ "mod", "file", "zig", "src/m5", "f_5.z" };
        var total_time: i64 = 0;
        var total_queries: usize = 0;

        for (queries) |query| {
            const start = std.time.nanoTimestamp();
            const results = try fuzzy.search(query, 10);
            const elapsed_ns = std.time.nanoTimestamp() - start;

            total_time += elapsed_ns;
            total_queries += 1;

            std.log.info("Query '{s}': {d} results in {d}μs", .{
                query,
                results.len,
                @divTrunc(elapsed_ns, 1_000),
            });

            allocator.free(results);
        }

        const avg_time_us = @divTrunc(total_time, @as(i64, @intCast(total_queries)) * 1_000);
        std.log.info("Average query time: {d}μs", .{avg_time_us});
    }

    std.log.info("", .{});
}

// ==================
// Rendering Benchmarks
// ==================

fn benchmarkRendering(allocator: std.mem.Allocator) !void {
    std.log.info("--- Rendering Benchmarks ---", .{});

    // Benchmark: Line rendering (simulate 1000 lines of 80 chars)
    {
        const iterations = 1_000;
        const chars_per_line = 80;
        const start = std.time.nanoTimestamp();

        var total_chars: usize = 0;
        for (0..iterations) |_| {
            // Simulate rendering overhead
            for (0..chars_per_line) |_| {
                total_chars += 1;
            }
        }

        const elapsed_ns = std.time.nanoTimestamp() - start;
        const chars_per_sec = @as(f64, @floatFromInt(total_chars)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);
        const lines_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

        std.log.info("Line rendering: {d} lines ({d} chars) in {d}ms", .{
            iterations,
            total_chars,
            @divTrunc(elapsed_ns, 1_000_000),
        });
        std.log.info("  {d:.0} lines/sec, {d:.0} chars/sec", .{ lines_per_sec, chars_per_sec });
    }

    // Benchmark: Frame rendering at different resolutions
    const resolutions = [_]struct { w: u32, h: u32, name: []const u8 }{
        .{ .w = 1920, .h = 1080, .name = "1080p" },
        .{ .w = 2560, .h = 1440, .name = "1440p" },
        .{ .w = 3840, .h = 2160, .name = "4K" },
    };

    for (resolutions) |res| {
        const cells = res.w * res.h;
        const frames = 60; // Simulate 1 second at 60fps

        const start = std.time.nanoTimestamp();

        for (0..frames) |_| {
            // Simulate rendering each cell
            var sum: u64 = 0;
            for (0..cells) |i| {
                sum +%= i; // Simulate work
            }
            std.mem.doNotOptimizeAway(&sum);
        }

        const elapsed_ns = std.time.nanoTimestamp() - start;
        const fps = @as(f64, @floatFromInt(frames)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);
        const mpixels_per_sec = (@as(f64, @floatFromInt(cells)) * @as(f64, @floatFromInt(frames))) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0) / 1_000_000.0;

        std.log.info("{s} ({d}x{d}): {d:.1} fps, {d:.1} Mpixels/sec", .{
            res.name,
            res.w,
            res.h,
            fps,
            mpixels_per_sec,
        });
    }

    std.log.info("", .{});
}

// ==================
// Memory Benchmarks
// ==================

fn benchmarkMemory(allocator: std.mem.Allocator) !void {
    std.log.info("--- Memory Benchmarks ---", .{});

    // Benchmark: Memory allocation patterns
    {
        const allocations = 10_000;
        const sizes = [_]usize{ 16, 64, 256, 1024, 4096 };

        for (sizes) |size| {
            var ptrs = try allocator.alloc(?[]u8, allocations);
            defer allocator.free(ptrs);

            const start = std.time.nanoTimestamp();

            // Allocate
            for (0..allocations) |i| {
                ptrs[i] = try allocator.alloc(u8, size);
            }

            // Free
            for (0..allocations) |i| {
                if (ptrs[i]) |ptr| {
                    allocator.free(ptr);
                }
            }

            const elapsed_ns = std.time.nanoTimestamp() - start;
            const ops_per_sec = @as(f64, @floatFromInt(allocations * 2)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

            std.log.info("{d}B allocations: {d} alloc+free in {d}ms ({d:.0} ops/sec)", .{
                size,
                allocations,
                @divTrunc(elapsed_ns, 1_000_000),
                ops_per_sec,
            });
        }
    }

    // Benchmark: Arena allocator vs GPA
    {
        const iterations = 1_000;

        // GPA
        {
            const start = std.time.nanoTimestamp();

            for (0..iterations) |_| {
                const data = try allocator.alloc(u8, 1024);
                @memset(data, 0);
                allocator.free(data);
            }

            const elapsed_ns = std.time.nanoTimestamp() - start;
            std.log.info("GPA 1KB alloc+free: {d}ms ({d}μs avg)", .{
                @divTrunc(elapsed_ns, 1_000_000),
                @divTrunc(elapsed_ns, iterations * 1_000),
            });
        }

        // Arena
        {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            const start = std.time.nanoTimestamp();

            for (0..iterations) |_| {
                const data = try arena.allocator().alloc(u8, 1024);
                @memset(data, 0);
                // No free needed
            }

            const elapsed_ns = std.time.nanoTimestamp() - start;
            std.log.info("Arena 1KB alloc: {d}ms ({d}μs avg)", .{
                @divTrunc(elapsed_ns, 1_000_000),
                @divTrunc(elapsed_ns, iterations * 1_000),
            });
        }
    }

    std.log.info("", .{});
}

const std = @import("std");
const grim = @import("grim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Grim Performance Benchmarks ===\n\n");

    try benchmarkColdStart(allocator);
    try benchmarkLargeFile(allocator);
    try benchmarkTypingLatency(allocator);
    try benchmarkSearchPerformance(allocator);

    std.debug.print("=== Benchmarks completed ===\n");
}

fn benchmarkColdStart(allocator: std.mem.Allocator) !void {
    std.debug.print("Cold Start Benchmark:\n");

    const iterations = 100;
    var total_time: u64 = 0;

    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // Simulate cold start
        var editor = try grim.ui.tui.Editor.init(allocator);
        try editor.rope.insert(0, "fn main() {}\n");

        const elapsed = timer.read();
        total_time += elapsed;

        editor.deinit();

        if (i % 10 == 0) {
            std.debug.print("  Iteration {}: {}μs\n", .{i, elapsed / std.time.ns_per_us});
        }
    }

    const avg_time = total_time / iterations;
    std.debug.print("  Average cold start: {}μs\n", .{avg_time / std.time.ns_per_us});
    std.debug.print("  Target: <40ms ({})\n", .{if (avg_time < 40 * std.time.ns_per_ms) "✓ PASS" else "✗ FAIL"});
    std.debug.print("\n");
}

fn benchmarkLargeFile(allocator: std.mem.Allocator) !void {
    std.debug.print("Large File Handling:\n");

    // Create 10MB test file
    const file_size = 10 * 1024 * 1024;
    const line = "This is a test line with some content to make it realistic.\n";
    const lines_needed = file_size / line.len;

    var editor = try grim.ui.tui.Editor.init(allocator);
    defer editor.deinit();

    // Measure loading time
    var timer = try std.time.Timer.start();

    for (0..lines_needed) |i| {
        try editor.rope.insert(editor.rope.len(), line);
        if (i % 10000 == 0) {
            std.debug.print("  Loaded {}KB...\n", .{(i * line.len) / 1024});
        }
    }

    const load_time = timer.read();
    std.debug.print("  File loading (10MB): {}ms\n", .{load_time / std.time.ns_per_ms});

    // Measure navigation performance
    timer.reset();

    const nav_operations = 1000;
    var pos: usize = 0;

    for (0..nav_operations) |i| {
        // Simulate navigation
        editor.cursor.offset = pos;
        pos = (pos + line.len * 100) % editor.rope.len();

        // Simulate rendering a viewport
        const viewport_start = pos;
        const viewport_size = 2000; // 2KB viewport
        const viewport_end = @min(viewport_start + viewport_size, editor.rope.len());

        const slice = editor.rope.slice(.{
            .start = viewport_start,
            .end = viewport_end,
        }) catch continue;
        _ = slice;

        if (i % 100 == 0) {
            const current_time = timer.read();
            const ops_per_sec = (@as(f64, i + 1) * std.time.ns_per_s) / @as(f64, current_time);
            std.debug.print("  Navigation ops/sec: {:.0}\n", .{ops_per_sec});
        }
    }

    const nav_time = timer.read();
    const avg_nav_time = nav_time / nav_operations;
    std.debug.print("  Average navigation time: {}μs\n", .{avg_nav_time / std.time.ns_per_us});
    std.debug.print("  Target: <16ms per frame ({})\n", .{if (avg_nav_time < 16 * std.time.ns_per_ms) "✓ PASS" else "✗ FAIL"});
    std.debug.print("\n");
}

fn benchmarkTypingLatency(allocator: std.mem.Allocator) !void {
    std.debug.print("Typing Latency Benchmark:\n");

    var editor = try grim.ui.tui.Editor.init(allocator);
    defer editor.deinit();

    // Pre-populate with some content
    try editor.rope.insert(0, "fn main() {\n    \n}\n");
    editor.cursor.offset = 11; // Position cursor inside function

    const test_text = "const std = @import(\"std\");\n    std.debug.print(\"Hello, World!\\n\", .{});\n";
    var total_time: u64 = 0;

    // Measure individual key insertion latency
    for (test_text) |char| {
        var timer = try std.time.Timer.start();

        // Simulate typing
        try editor.handleKey('i'); // Enter insert mode
        try editor.handleKey(char);
        try editor.handleKey(0x1B); // Exit insert mode

        const elapsed = timer.read();
        total_time += elapsed;
    }

    const avg_latency = total_time / test_text.len;
    std.debug.print("  Average key latency: {}μs\n", .{avg_latency / std.time.ns_per_us});
    std.debug.print("  Target: <1ms per key ({})\n", .{if (avg_latency < std.time.ns_per_ms) "✓ PASS" else "✗ FAIL"});

    // Test burst typing
    var timer = try std.time.Timer.start();
    try editor.handleKey('i');
    for (test_text) |char| {
        try editor.handleKey(char);
    }
    try editor.handleKey(0x1B);

    const burst_time = timer.read();
    const burst_latency = burst_time / test_text.len;
    std.debug.print("  Burst typing latency: {}μs per char\n", .{burst_latency / std.time.ns_per_us});
    std.debug.print("\n");
}

fn benchmarkSearchPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("Search Performance:\n");

    var file_manager = try grim.ui.tui.file_ops.FileManager.init(allocator);
    defer file_manager.deinit();

    var finder = try grim.ui.tui.file_ops.FileFinder.init(allocator, file_manager);
    defer finder.deinit();

    // Create mock file list
    var mock_files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (mock_files.items) |file| {
            allocator.free(file);
        }
        mock_files.deinit();
    }

    // Generate test files
    const file_count = 10000;
    for (0..file_count) |i| {
        const filename = try std.fmt.allocPrint(allocator, "src/module_{d}.zig", .{i});
        try mock_files.append(filename);
    }

    // Test search performance
    const search_queries = [_][]const u8{
        "module_1", "test", "src", ".zig", "xyz", "500", "main"
    };

    for (search_queries) |query| {
        var timer = try std.time.Timer.start();

        var matches = std.ArrayList([]const u8).init(allocator);
        defer {
            for (matches.items) |match| {
                allocator.free(match);
            }
            matches.deinit();
        }

        // Simple fuzzy search simulation
        for (mock_files.items) |file| {
            if (std.mem.indexOf(u8, file, query) != null) {
                try matches.append(try allocator.dupe(u8, file));
            }
        }

        const elapsed = timer.read();
        std.debug.print("  Search '{s}': {}ms ({} matches)\n", .{
            query, elapsed / std.time.ns_per_ms, matches.items.len
        });
    }

    std.debug.print("  ✓ Search benchmarks completed\n\n");
}

// Benchmarking utilities
pub const BenchResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,

    pub fn avgTimeNs(self: BenchResult) u64 {
        return self.total_time_ns / self.iterations;
    }

    pub fn opsPerSec(self: BenchResult) f64 {
        return (@as(f64, self.iterations) * std.time.ns_per_s) / @as(f64, self.total_time_ns);
    }

    pub fn print(self: BenchResult) void {
        std.debug.print("Benchmark: {s}\n", .{self.name});
        std.debug.print("  Iterations: {}\n", .{self.iterations});
        std.debug.print("  Average: {}μs\n", .{self.avgTimeNs() / std.time.ns_per_us});
        std.debug.print("  Min: {}μs\n", .{self.min_time_ns / std.time.ns_per_us});
        std.debug.print("  Max: {}μs\n", .{self.max_time_ns / std.time.ns_per_us});
        std.debug.print("  Ops/sec: {:.0}\n", .{self.opsPerSec()});
        std.debug.print("\n");
    }
};

pub fn benchmark(comptime func: anytype, iterations: u64, args: anytype) !BenchResult {
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;

    for (0..iterations) |_| {
        var timer = try std.time.Timer.start();

        try @call(.auto, func, args);

        const elapsed = timer.read();
        total_time += elapsed;
        min_time = @min(min_time, elapsed);
        max_time = @max(max_time, elapsed);
    }

    return BenchResult{
        .name = @typeName(@TypeOf(func)),
        .iterations = iterations,
        .total_time_ns = total_time,
        .min_time_ns = min_time,
        .max_time_ns = max_time,
    };
}
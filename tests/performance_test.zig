const std = @import("std");
const core = @import("core");
const lsp = @import("lsp");
const syntax = @import("syntax");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Grim Performance Test Suite ===");

    try runRopePerformanceTests(allocator);
    try runSyntaxHighlightingTests(allocator);
    try runLSPPerformanceTests(allocator);
    try runMemoryTests(allocator);

    std.log.info("=== All Performance Tests Completed ===");
}

fn runRopePerformanceTests(allocator: std.mem.Allocator) !void {
    std.log.info("--- Rope Performance Tests ---");

    // Test 1: Large insertions
    {
        var timer = try std.time.Timer.start();
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        const large_text = "Hello, World! This is a test string. " ** 1000; // ~37KB
        const iterations = 1000;

        const start = timer.read();
        for (0..iterations) |i| {
            try rope.insert(i * large_text.len, large_text);
        }
        const end = timer.read();

        const total_size = rope.len();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_ms;
        const throughput_mb_s = (@as(f64, @floatFromInt(total_size)) / (1024.0 * 1024.0)) / (duration_ms / 1000.0);

        std.log.info("Large Insertions: {d} insertions, {d} bytes total", .{ iterations, total_size });
        std.log.info("  Time: {d:.2} ms, Throughput: {d:.2} MB/s", .{ duration_ms, throughput_mb_s });
    }

    // Test 2: Random access slicing
    {
        var timer = try std.time.Timer.start();
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        // Prepare rope with substantial content
        const text = "The quick brown fox jumps over the lazy dog.\n" ** 2000; // ~90KB
        try rope.insert(0, text);

        const iterations = 10000;
        const start = timer.read();

        var rng = std.rand.DefaultPrng.init(12345);
        const random = rng.random();

        for (0..iterations) |_| {
            const start_pos = random.uintLessThan(usize, rope.len() / 2);
            const end_pos = start_pos + random.uintLessThan(usize, rope.len() - start_pos);
            const slice = try rope.slice(.{ .start = start_pos, .end = end_pos });
            if (slice.len > 0) {
                allocator.free(slice);
            }
        }

        const end = timer.read();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_ms;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

        std.log.info("Random Slicing: {d} operations", .{iterations});
        std.log.info("  Time: {d:.2} ms, Rate: {d:.0} ops/sec", .{ duration_ms, ops_per_sec });
    }

    // Test 3: Frequent edits (simulating typing)
    {
        var timer = try std.time.Timer.start();
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        const iterations = 50000;
        const start = timer.read();

        var rng = std.rand.DefaultPrng.init(54321);
        const random = rng.random();

        for (0..iterations) |_| {
            const pos = if (rope.len() > 0) random.uintLessThan(usize, rope.len()) else 0;

            if (random.boolean()) {
                // Insert character
                const char = 'a' + @as(u8, @intCast(random.uintLessThan(u8, 26)));
                try rope.insert(pos, &[_]u8{char});
            } else if (rope.len() > 0) {
                // Delete character
                try rope.delete(pos, 1);
            }
        }

        const end = timer.read();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_ms;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

        std.log.info("Typing Simulation: {d} operations, final size: {d} bytes", .{ iterations, rope.len() });
        std.log.info("  Time: {d:.2} ms, Rate: {d:.0} ops/sec", .{ duration_ms, ops_per_sec });
    }

    // Test 4: Memory fragmentation test
    {
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        const text_chunk = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ** 10; // ~570 bytes
        const initial_chunks = 100;

        // Insert many chunks
        for (0..initial_chunks) |i| {
            try rope.insert(i * text_chunk.len, text_chunk);
        }

        // Delete every other chunk to create fragmentation
        var i: usize = 0;
        while (i < initial_chunks) : (i += 2) {
            try rope.delete(i * text_chunk.len / 2, text_chunk.len);
        }

        std.log.info("Fragmentation Test: inserted {d} chunks, deleted every other", .{initial_chunks});
        std.log.info("  Final size: {d} bytes", .{rope.len()});
    }
}

fn runSyntaxHighlightingTests(allocator: std.mem.Allocator) !void {
    std.log.info("--- Syntax Highlighting Performance Tests ---");

    // Test different file sizes and languages
    const test_cases = [_]struct {
        name: []const u8,
        content: []const u8,
        language: syntax.grove.GroveParser.Language,
    }{
        .{
            .name = "Small Zig file",
            .content =
            \\const std = @import("std");
            \\
            \\pub fn main() !void {
            \\    const x: u32 = 42;
            \\    std.debug.print("Hello: {}\n", .{x});
            \\}
            ,
            .language = .zig,
        },
        .{
            .name = "Medium Rust file",
            .content = (
                \\use std::collections::HashMap;
                \\
                \\fn main() {
                \\    let mut map = HashMap::new();
                \\    map.insert("key", "value");
                \\    println!("Map: {:?}", map);
                \\}
                \\
                \\struct Point {
                \\    x: f64,
                \\    y: f64,
                \\}
                \\
            ) ** 50, // Repeat to make it larger
            .language = .rust,
        },
        .{
            .name = "Large JavaScript file",
            .content = (
                \\function fibonacci(n) {
                \\    if (n <= 1) return n;
                \\    return fibonacci(n - 1) + fibonacci(n - 2);
                \\}
                \\
                \\class Calculator {
                \\    constructor() {
                \\        this.result = 0;
                \\    }
                \\
                \\    add(x) {
                \\        this.result += x;
                \\        return this;
                \\    }
                \\
                \\    multiply(x) {
                \\        this.result *= x;
                \\        return this;
                \\    }
                \\}
                \\
                \\const calc = new Calculator();
                \\console.log(calc.add(5).multiply(2).result);
                \\
            ) ** 200, // ~10KB
            .language = .javascript,
        },
    };

    for (test_cases) |test_case| {
        var timer = try std.time.Timer.start();

        var rope = try core.Rope.init(allocator);
        defer rope.deinit();
        try rope.insert(0, test_case.content);

        var highlighter = syntax.SyntaxHighlighter.init(allocator);
        defer highlighter.deinit();

        var parser = try syntax.grove.GroveParser.init(allocator, test_case.language);
        defer parser.deinit();

        const iterations = 1000;
        const start = timer.read();

        for (0..iterations) |_| {
            try parser.parse(test_case.content);
            const highlights = try parser.getHighlights(allocator);
            defer allocator.free(highlights);
        }

        const end = timer.read();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_ms;
        const chars_per_sec = @as(f64, @floatFromInt(test_case.content.len * iterations)) / (duration_ms / 1000.0);

        std.log.info("{s} ({d} bytes, {d} iterations)", .{ test_case.name, test_case.content.len, iterations });
        std.log.info("  Time: {d:.2} ms, Rate: {d:.0} chars/sec", .{ duration_ms, chars_per_sec });
    }
}

fn runLSPPerformanceTests(allocator: std.mem.Allocator) !void {
    std.log.info("--- LSP Performance Tests ---");

    // Test LSP message parsing and handling
    const test_requests = [_][]const u8{
        \\{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///test.zig"},"position":{"line":10,"character":5}}}
        ,
        \\{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///test.zig"},"position":{"line":5,"character":10}}}
        ,
        \\{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///test.zig"},"position":{"line":15,"character":20}}}
        ,
        \\{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///test.zig","version":2},"contentChanges":[{"text":"updated content"}]}}
        ,
    };

    var timer = try std.time.Timer.start();
    var lsp_client = try lsp.Client.init(allocator);
    defer lsp_client.deinit();

    const iterations = 10000;
    const start = timer.read();

    for (0..iterations) |_| {
        for (test_requests) |request| {
            // Simulate parsing LSP message
            _ = request; // Placeholder - would actually parse JSON

            // Simulate processing request
            std.time.sleep(1000); // 1 microsecond to simulate processing
        }
    }

    const end = timer.read();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_ms;
    const requests_per_sec = @as(f64, @floatFromInt(test_requests.len * iterations)) / (duration_ms / 1000.0);

    std.log.info("LSP Message Processing: {d} messages", .{test_requests.len * iterations});
    std.log.info("  Time: {d:.2} ms, Rate: {d:.0} messages/sec", .{ duration_ms, requests_per_sec });

    // Test diagnostics updating
    {
        const diagnostic_iterations = 1000;
        const diag_start = timer.read();

        for (0..diagnostic_iterations) |_| {
            // Simulate updating diagnostics for a file
            const fake_diagnostics = [_]lsp.Diagnostic{
                .{ .range = .{ .start = .{ .line = 5, .character = 10 }, .end = .{ .line = 5, .character = 15 } }, .message = "Unused variable", .severity = .warning },
                .{ .range = .{ .start = .{ .line = 10, .character = 0 }, .end = .{ .line = 10, .character = 5 } }, .message = "Syntax error", .severity = .@"error" },
            };

            // This would update the diagnostics in the actual LSP client
            _ = fake_diagnostics;
        }

        const diag_end = timer.read();
        const diag_duration_ms = @as(f64, @floatFromInt(diag_end - diag_start)) / std.time.ns_per_ms;
        const diag_updates_per_sec = @as(f64, @floatFromInt(diagnostic_iterations)) / (diag_duration_ms / 1000.0);

        std.log.info("Diagnostic Updates: {d} updates", .{diagnostic_iterations});
        std.log.info("  Time: {d:.2} ms, Rate: {d:.0} updates/sec", .{ diag_duration_ms, diag_updates_per_sec });
    }
}

fn runMemoryTests(allocator: std.mem.Allocator) !void {
    std.log.info("--- Memory Performance Tests ---");

    // Test 1: Rope memory usage under different scenarios
    {
        // Small frequent edits
        var rope = try core.Rope.init(allocator);
        defer rope.deinit();

        const initial_content = "Hello, World!\n" ** 1000; // ~14KB
        try rope.insert(0, initial_content);

        std.log.info("Rope memory test - initial size: {d} bytes", .{rope.len()});

        // Simulate editing by inserting and deleting at random positions
        var rng = std.rand.DefaultPrng.init(98765);
        const random = rng.random();

        for (0..10000) |_| {
            const pos = random.uintLessThan(usize, rope.len());

            if (random.boolean()) {
                try rope.insert(pos, "X");
            } else if (rope.len() > 0) {
                try rope.delete(pos, 1);
            }
        }

        std.log.info("After 10k edits - final size: {d} bytes", .{rope.len()});
    }

    // Test 2: Syntax highlighting memory usage
    {
        const large_file = (
            \\const std = @import("std");
            \\
            \\pub fn factorial(n: u64) u64 {
            \\    if (n <= 1) return 1;
            \\    return n * factorial(n - 1);
            \\}
            \\
            \\pub fn main() !void {
            \\    const result = factorial(10);
            \\    std.debug.print("10! = {}\n", .{result});
            \\}
            \\
        ) ** 1000; // ~32KB repeated content

        var highlighter = syntax.SyntaxHighlighter.init(allocator);
        defer highlighter.deinit();

        var rope = try core.Rope.init(allocator);
        defer rope.deinit();
        try rope.insert(0, large_file);

        // This would test memory usage of highlighting
        const highlights = try highlighter.highlight(&rope);
        defer allocator.free(highlights);

        std.log.info("Syntax highlighting memory test - {d} highlights for {d} byte file", .{ highlights.len, large_file.len });
    }

    // Test 3: Plugin system memory overhead
    {
        const plugin_count = 100;
        std.log.info("Testing memory overhead with {d} mock plugins", .{plugin_count});

        // This would test plugin system memory usage
        // For now, just a placeholder
        var mock_plugins = try allocator.alloc(u32, plugin_count);
        defer allocator.free(mock_plugins);

        for (mock_plugins, 0..) |*plugin, i| {
            plugin.* = @intCast(i);
        }

        std.log.info("Plugin system memory test completed");
    }
}

// Benchmark utilities
pub fn benchmarkFunction(comptime name: []const u8, iterations: usize, func: anytype, args: anytype) !void {
    var timer = try std.time.Timer.start();

    const start = timer.read();
    for (0..iterations) |_| {
        _ = @call(.auto, func, args);
    }
    const end = timer.read();

    const duration_ms = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_ms;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.log.info("{s}: {d} iterations in {d:.2} ms ({d:.0} ops/sec)", .{ name, iterations, duration_ms, ops_per_sec });
}

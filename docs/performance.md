# Performance Guide

Grim is designed for speed. This guide covers performance profiling, optimization, and best practices.

## Performance Metrics

### Startup Time

Target: < 50ms

```bash
# Measure startup time
time grim --version

# Detailed timing breakdown
grim --profile-startup
```

### Memory Usage

Target: < 50MB for typical editing session

```bash
# Monitor memory usage
ps aux | grep grim

# Memory profiling
grim --profile-memory file.zig
```

### Key Metrics

| Metric | Target | Typical |
|--------|--------|---------|
| Cold start | < 50ms | ~35ms |
| Hot start (cached) | < 20ms | ~15ms |
| File open (1MB) | < 100ms | ~60ms |
| File open (10MB) | < 500ms | ~300ms |
| LSP response | < 200ms | ~150ms |
| Syntax highlight | < 50ms | ~30ms |

## Profiling

### Built-in Profiling

Grim includes built-in performance profiling:

```bash
# Profile startup
grim --profile startup

# Profile file operations
grim --profile file operations.zig

# Profile LSP interactions
grim --profile lsp server.zig

# Profile syntax highlighting
grim --profile syntax large_file.zig
```

### Error Handler Integration

The error handler tracks performance metrics:

```zig
const core = @import("core");

// Profile a function
const start = std.time.milliTimestamp();
try someExpensiveOperation();
const elapsed = std.time.milliTimestamp() - start;

if (elapsed > 100) {  // Warn if > 100ms
    core.ErrorHandler.logError(error.PerformanceDegradation, .{
        .operation = "Expensive operation",
        .details = try std.fmt.allocPrint(allocator, "Took {d}ms", .{elapsed}),
    });
}
```

### External Profiling Tools

#### Linux Perf

```bash
# Record performance data
perf record -g grim large_file.zig

# View report
perf report

# Flame graph
perf script | flamegraph.pl > grim.svg
```

#### Valgrind (Memory)

```bash
# Memory profiling
valgrind --tool=massif grim file.zig

# View results
ms_print massif.out.*
```

#### Heaptrack

```bash
# Track heap allocations
heaptrack grim file.zig

# Analyze
heaptrack_gui heaptrack.grim.*
```

## Optimization Strategies

### 1. Rope Data Structure

Grim uses a rope for efficient large file handling:

**Benefits**:
- O(log n) insertions/deletions
- Lazy evaluation
- Memory-efficient for large files

**Location**: `core/rope.zig`

```zig
pub const Rope = struct {
    // Balanced binary tree of text chunks
    // Optimized for:
    // - Random access: O(log n)
    // - Insert/delete: O(log n)
    // - Slice: O(log n + k) where k is result size
};
```

### 2. SIMD UTF-8 Validation

Fast UTF-8 validation using SIMD instructions:

**Location**: `core/simd_utf8.zig`

```zig
pub fn validateUtf8SIMD(bytes: []const u8) bool {
    // Uses AVX2/SSE4.2 when available
    // Fallback to scalar validation
    // ~10x faster than naive implementation
}
```

### 3. Incremental Syntax Highlighting

Tree-sitter provides incremental parsing:

```zig
// Only re-parse changed regions
try parser.edit(.{
    .start_byte = edit_start,
    .old_end_byte = old_end,
    .new_end_byte = new_end,
    .start_point = .{ .row = line, .column = col },
    .old_end_point = old_point,
    .new_end_point = new_point,
});

// Re-parse (incremental)
const new_tree = try parser.parse(text);
```

### 4. LSP Request Batching

Batch multiple LSP requests to reduce overhead:

```zig
pub fn batchRequests(requests: []LSPRequest) !void {
    var batch = std.ArrayList(std.json.Value){};
    
    for (requests) |req| {
        try batch.append(allocator, req.toJson());
    }
    
    // Send all at once
    try lsp_client.sendBatch(batch.items);
}
```

### 5. io_uring for File I/O

Asynchronous file operations using io_uring (Linux):

**Location**: `core/io_uring_file.zig`

```zig
pub const IoUringFileManager = struct {
    // Async file operations
    // ~2x faster than sync I/O for large files
    // Minimal CPU usage while waiting
    
    pub fn readFileAsync(path: []const u8) ![]const u8
    pub fn writeFileAsync(path: []const u8, content: []const u8) !void
};
```

## Configuration for Performance

### Optimize for Speed

```json
{
  "editor": {
    "line_numbers": true,
    "relative_line_numbers": false,  // Disable for speed
    "word_wrap": false,  // Faster rendering
    "auto_save": true,
    "auto_save_interval_ms": 60000  // Less frequent = faster
  },
  "lsp": {
    "enabled": true,
    "completion": {
      "auto_trigger": false,  // Manual trigger faster
      "max_items": 10  // Fewer items = faster
    },
    "diagnostics": {
      "debounce_ms": 500  // Less frequent updates
    }
  },
  "syntax": {
    "enabled": true,
    "max_file_size_mb": 10,  // Skip highlighting for huge files
    "incremental": true  // Faster for edits
  }
}
```

### Optimize for Large Files

```json
{
  "editor": {
    "lazy_loading": true,  // Load file in chunks
    "chunk_size_kb": 512,
    "max_undo_history": 100  // Limit memory usage
  },
  "lsp": {
    "enabled": false  // LSP slow for huge files
  },
  "syntax": {
    "enabled": false  // Skip highlighting for huge files
  }
}
```

## Benchmarking

### File Operations

```bash
# Benchmark file open
hyperfine 'grim --benchmark-open large_file.zig'

# Benchmark save
hyperfine 'grim --benchmark-save large_file.zig'
```

### Editing Operations

```zig
// Location: tests/benchmark.zig

test "Benchmark insert performance" {
    var rope = try Rope.init(allocator);
    defer rope.deinit();
    
    const start = std.time.nanoTimestamp();
    
    // 10,000 insertions
    for (0..10000) |i| {
        try rope.insert(i * 10, "test");
    }
    
    const elapsed = std.time.nanoTimestamp() - start;
    const avg_ns = @divFloor(elapsed, 10000);
    
    std.debug.print("Avg insert: {d}ns\n", .{avg_ns});
    try std.testing.expect(avg_ns < 1000);  // < 1μs per insert
}
```

### LSP Performance

```bash
# Test LSP response time
grim --benchmark-lsp file.zig

# Typical output:
# Completion: 145ms
# Hover: 89ms  
# Goto Definition: 67ms
# Diagnostics: 234ms
```

## Common Performance Issues

### Issue: Slow Startup

**Symptoms**: Editor takes > 200ms to start

**Causes**:
1. Too many plugins loading
2. Large config file
3. Slow LSP server auto-start
4. Network-mounted home directory

**Solutions**:
```bash
# Profile startup
grim --profile startup

# Disable plugins temporarily
grim --no-plugins

# Skip LSP auto-start
grim --no-lsp

# Use local config
grim --config /tmp/minimal-config.json
```

### Issue: Sluggish Editing

**Symptoms**: Lag when typing or moving cursor

**Causes**:
1. LSP sending too many requests
2. Syntax highlighting too aggressive
3. Too many visual effects
4. Large undo history

**Solutions**:
```json
{
  "lsp": {
    "diagnostics": {
      "debounce_ms": 1000  // Increase debounce
    }
  },
  "syntax": {
    "max_file_size_mb": 5  // Lower threshold
  },
  "editor": {
    "max_undo_history": 100  // Limit history
  }
}
```

### Issue: High Memory Usage

**Symptoms**: Grim using > 500MB RAM

**Causes**:
1. Multiple large files open
2. Unbounded undo history
3. LSP caching too much
4. Memory leak

**Solutions**:
```bash
# Check memory usage
grim --report-memory

# Limit buffers
:set max_buffers=10

# Clear undo history
:clearundo

# Restart LSP
:LspRestart
```

### Issue: Slow LSP Responses

**Symptoms**: Completions taking > 500ms

**Causes**:
1. LSP server overwhelmed
2. Large project/workspace
3. Network LSP (remote development)
4. Outdated LSP server

**Solutions**:
```bash
# Check LSP server load
:LspStatus

# Restart LSP
:LspRestart

# Update LSP server
# For ZLS:
zig build -Doptimize=ReleaseFast

# Use local LSP for remote files
grim --lsp-local file.zig
```

## Performance Best Practices

1. **Keep Files Reasonably Sized**: Split files > 10,000 lines
2. **Use Lazy Loading**: Enable for files > 1MB
3. **Limit Open Buffers**: Close unused buffers with `:bd`
4. **Disable Unused Features**: Turn off LSP/syntax for plain text
5. **Update Regularly**: Newer versions often have performance improvements
6. **Profile Before Optimizing**: Use built-in profiling tools
7. **Monitor Resource Usage**: Check memory/CPU periodically

## Performance Monitoring

### Built-in Stats

```vim
:perf               " Show performance stats
:perf startup       " Startup time breakdown
:perf memory        " Memory usage by component
:perf lsp           " LSP request timings
```

### Continuous Monitoring

```bash
# Monitor in real-time
watch -n 1 'ps aux | grep grim'

# Log performance metrics
grim --log-performance /tmp/grim-perf.log
```

## Future Optimizations

Planned performance improvements:

- [ ] Parallel syntax highlighting
- [ ] Lazy buffer loading
- [ ] GPU-accelerated rendering (GUI mode)
- [ ] JIT compilation for Ghostlang plugins
- [ ] mmap for very large files
- [ ] Background LSP request queue

## See Also

- [Error Handling](error-handling.md)
- [Configuration](configuration.md)
- [Profiling Tools](profiling-tools.md)
- [Architecture](architecture.md)

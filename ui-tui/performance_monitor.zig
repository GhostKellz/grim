const std = @import("std");
const core = @import("core");
const syntax = @import("syntax");
const runtime = @import("runtime");

/// Integrated performance monitoring for the Grim editor
pub const EditorPerformanceMonitor = struct {
    allocator: std.mem.Allocator,
    core_monitor: core.Optimization.PerformanceMonitor,
    rope_optimizer: core.Optimization.RopeOptimizer,
    memory_pool: core.Optimization.MemoryPool,
    cache: core.Optimization.Cache,
    stats: EditorStats,
    enabled: bool,

    pub const EditorStats = struct {
        // Editor operation counters
        key_presses: u64 = 0,
        buffer_switches: u64 = 0,
        file_operations: u64 = 0,
        syntax_highlighting_requests: u64 = 0,
        plugin_calls: u64 = 0,

        // Performance metrics
        average_render_time: f64 = 0.0,
        peak_memory_usage: usize = 0,
        total_allocations: usize = 0,
        cache_hits: u64 = 0,
        cache_misses: u64 = 0,

        // System health indicators
        rope_fragmentation: f32 = 0.0,
        plugin_response_time: f64 = 0.0,
        lsp_latency: f64 = 0.0,

        pub fn reset(self: *EditorStats) void {
            self.* = .{};
        }

        pub fn getCacheHitRate(self: *const EditorStats) f64 {
            const total = self.cache_hits + self.cache_misses;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total)) * 100.0;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !*EditorPerformanceMonitor {
        const monitor = try allocator.create(EditorPerformanceMonitor);
        monitor.* = .{
            .allocator = allocator,
            .core_monitor = core.Optimization.PerformanceMonitor.init(allocator),
            .rope_optimizer = core.Optimization.RopeOptimizer.init(.{}),
            .memory_pool = core.Optimization.MemoryPool.init(allocator),
            .cache = core.Optimization.Cache.init(allocator, 10 * 1024 * 1024), // 10MB cache
            .stats = .{},
            .enabled = true,
        };
        return monitor;
    }

    pub fn deinit(self: *EditorPerformanceMonitor) void {
        self.core_monitor.deinit();
        self.memory_pool.deinit();
        self.cache.deinit();
        self.allocator.destroy(self);
    }

    pub fn enable(self: *EditorPerformanceMonitor) void {
        self.enabled = true;
    }

    pub fn disable(self: *EditorPerformanceMonitor) void {
        self.enabled = false;
    }

    /// Start timing an operation
    pub fn startOperation(self: *EditorPerformanceMonitor, name: []const u8) OperationTimer {
        if (!self.enabled) return OperationTimer.dummy();

        return OperationTimer{
            .monitor = self,
            .name = name,
            .start_time = std.time.nanoTimestamp(),
            .enabled = true,
        };
    }

    /// Record a completed operation
    pub fn recordOperation(self: *EditorPerformanceMonitor, name: []const u8, duration_ns: u64) void {
        if (!self.enabled) return;

        self.core_monitor.recordTime(name, duration_ns) catch {};

        // Update specific stats based on operation type
        if (std.mem.eql(u8, name, "render")) {
            const duration_ms = @as(f64, @floatFromInt(duration_ns)) / std.time.ns_per_ms;
            self.stats.average_render_time = (self.stats.average_render_time + duration_ms) / 2.0;
        } else if (std.mem.eql(u8, name, "key_press")) {
            self.stats.key_presses += 1;
        } else if (std.mem.eql(u8, name, "syntax_highlight")) {
            self.stats.syntax_highlighting_requests += 1;
        } else if (std.mem.eql(u8, name, "plugin_call")) {
            self.stats.plugin_calls += 1;
            const duration_ms = @as(f64, @floatFromInt(duration_ns)) / std.time.ns_per_ms;
            self.stats.plugin_response_time = (self.stats.plugin_response_time + duration_ms) / 2.0;
        }
    }

    /// Analyze rope performance
    pub fn analyzeRope(self: *EditorPerformanceMonitor, rope: *const core.Rope) void {
        if (!self.enabled) return;

        self.rope_optimizer.analyzeRope(rope);
        self.stats.rope_fragmentation = self.rope_optimizer.stats.fragmentation_ratio;
    }

    /// Get or allocate memory from pool
    pub fn acquireMemory(self: *EditorPerformanceMonitor, size: usize) ![]u8 {
        if (!self.enabled) {
            return try self.allocator.alloc(u8, size);
        }

        self.stats.total_allocations += 1;
        return try self.memory_pool.acquire(size);
    }

    /// Release memory back to pool
    pub fn releaseMemory(self: *EditorPerformanceMonitor, buffer: []u8) void {
        if (!self.enabled) {
            self.allocator.free(buffer);
            return;
        }

        self.memory_pool.release(buffer);
    }

    /// Cache frequently used data
    pub fn cacheData(self: *EditorPerformanceMonitor, key: []const u8, data: []const u8) !void {
        if (!self.enabled) return;

        try self.cache.put(key, data);
    }

    /// Retrieve cached data
    pub fn getCachedData(self: *EditorPerformanceMonitor, key: []const u8) ?[]const u8 {
        if (!self.enabled) return null;

        if (self.cache.get(key)) |data| {
            self.stats.cache_hits += 1;
            return data;
        } else {
            self.stats.cache_misses += 1;
            return null;
        }
    }

    /// Generate comprehensive performance report
    pub fn generateReport(self: *const EditorPerformanceMonitor, allocator: std.mem.Allocator) ![]u8 {
        if (!self.enabled) {
            return try allocator.dupe(u8, "Performance monitoring is disabled");
        }

        var report = std.ArrayList(u8).init(allocator);
        defer report.deinit();

        const writer = report.writer();

        try writer.print("=== Grim Editor Performance Report ===\n\n");

        // Editor Statistics
        try writer.print("Editor Statistics:\n");
        try writer.print("  Key presses: {d}\n", .{self.stats.key_presses});
        try writer.print("  Buffer switches: {d}\n", .{self.stats.buffer_switches});
        try writer.print("  File operations: {d}\n", .{self.stats.file_operations});
        try writer.print("  Syntax highlighting requests: {d}\n", .{self.stats.syntax_highlighting_requests});
        try writer.print("  Plugin calls: {d}\n", .{self.stats.plugin_calls});
        try writer.print("\n");

        // Performance Metrics
        try writer.print("Performance Metrics:\n");
        try writer.print("  Average render time: {d:.2} ms\n", .{self.stats.average_render_time});
        try writer.print("  Peak memory usage: {d} KB\n", .{self.stats.peak_memory_usage / 1024});
        try writer.print("  Total allocations: {d}\n", .{self.stats.total_allocations});
        try writer.print("  Plugin response time: {d:.2} ms\n", .{self.stats.plugin_response_time});
        try writer.print("  LSP latency: {d:.2} ms\n", .{self.stats.lsp_latency});
        try writer.print("\n");

        // Cache Statistics
        const cache_stats = self.cache.getStats();
        try writer.print("Cache Statistics:\n");
        try writer.print("  Entries: {d}\n", .{cache_stats.entries});
        try writer.print("  Size: {d} KB / {d} KB\n", .{ cache_stats.size / 1024, cache_stats.max_size / 1024 });
        try writer.print("  Hit rate: {d:.1}%\n", .{self.stats.getCacheHitRate()});
        try writer.print("\n");

        // Rope Analysis
        try writer.print("Rope Analysis:\n");
        try writer.print("  Pieces: {d}\n", .{self.rope_optimizer.stats.total_pieces});
        try writer.print("  Total size: {d} bytes\n", .{self.rope_optimizer.stats.total_size});
        try writer.print("  Fragmentation: {d:.1}%\n", .{self.stats.rope_fragmentation * 100.0});
        try writer.print("  Optimization needed: {s}\n", .{if (self.rope_optimizer.needsOptimization()) "Yes" else "No"});
        if (self.rope_optimizer.needsOptimization()) {
            try writer.print("  Suggested strategy: {s}\n", .{@tagName(self.rope_optimizer.suggestStrategy())});
        }
        try writer.print("\n");

        // Core Performance Metrics
        const core_metrics = try self.core_monitor.getMetrics(allocator);
        defer allocator.free(core_metrics);
        try writer.print("{s}\n", .{core_metrics});

        // Health Assessment
        try writer.print("Health Assessment:\n");
        const health = self.assessHealth();
        try writer.print("  Overall: {s}\n", .{@tagName(health.overall)});
        try writer.print("  Memory: {s}\n", .{@tagName(health.memory)});
        try writer.print("  Performance: {s}\n", .{@tagName(health.performance)});
        try writer.print("  Cache efficiency: {s}\n", .{@tagName(health.cache)});

        if (health.recommendations.len > 0) {
            try writer.print("\nRecommendations:\n");
            for (health.recommendations) |recommendation| {
                try writer.print("  - {s}\n", .{recommendation});
            }
        }

        return report.toOwnedSlice();
    }

    /// System health assessment
    pub const HealthStatus = enum { excellent, good, fair, poor };

    pub const SystemHealth = struct {
        overall: HealthStatus,
        memory: HealthStatus,
        performance: HealthStatus,
        cache: HealthStatus,
        recommendations: []const []const u8,
    };

    fn assessHealth(self: *const EditorPerformanceMonitor) SystemHealth {
    var recommendations = std.ArrayList([]const u8).empty;
    recommendations.allocator = self.allocator;

        // Assess memory health
        const memory_health = if (self.stats.peak_memory_usage > 100 * 1024 * 1024) // 100MB
            HealthStatus.poor
        else if (self.stats.peak_memory_usage > 50 * 1024 * 1024) // 50MB
            HealthStatus.fair
        else if (self.stats.peak_memory_usage > 20 * 1024 * 1024) // 20MB
            HealthStatus.good
        else
            HealthStatus.excellent;

        // Assess performance health
        const performance_health = if (self.stats.average_render_time > 16.0) // 60 FPS threshold
            HealthStatus.poor
        else if (self.stats.average_render_time > 8.0) // 120 FPS threshold
            HealthStatus.fair
        else if (self.stats.average_render_time > 4.0) // 240 FPS threshold
            HealthStatus.good
        else
            HealthStatus.excellent;

        // Assess cache health
        const cache_hit_rate = self.stats.getCacheHitRate();
        const cache_health = if (cache_hit_rate < 50.0)
            HealthStatus.poor
        else if (cache_hit_rate < 70.0)
            HealthStatus.fair
        else if (cache_hit_rate < 85.0)
            HealthStatus.good
        else
            HealthStatus.excellent;

        // Add recommendations based on health
        if (memory_health == .poor) {
            recommendations.append(self.allocator, "Consider reducing memory usage or increasing available memory") catch {};
        }
        if (performance_health == .poor) {
            recommendations.append(self.allocator, "Performance is below optimal - consider rope defragmentation") catch {};
        }
        if (cache_health == .poor) {
            recommendations.append(self.allocator, "Low cache hit rate - review caching strategy") catch {};
        }
        if (self.rope_optimizer.needsOptimization()) {
            recommendations.append(self.allocator, "Rope needs optimization - run defragmentation") catch {};
        }

        // Overall health is the worst of individual components
        const overall = @min(@min(memory_health, performance_health), cache_health);

        return SystemHealth{
            .overall = overall,
            .memory = memory_health,
            .performance = performance_health,
            .cache = cache_health,
            .recommendations = recommendations.items,
        };
    }

    /// Reset all statistics
    pub fn resetStats(self: *EditorPerformanceMonitor) void {
        self.stats.reset();
    }

    /// Performance optimization suggestions
    pub fn getOptimizationSuggestions(self: *const EditorPerformanceMonitor, allocator: std.mem.Allocator) ![][]const u8 {
    var suggestions = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    errdefer suggestions.deinit();

        if (self.rope_optimizer.needsOptimization()) {
            const strategy = self.rope_optimizer.suggestStrategy();
            const suggestion = try std.fmt.allocPrint(allocator, "Optimize rope structure using {s} strategy", .{@tagName(strategy)});
            try suggestions.append(allocator, suggestion);
        }

        if (self.stats.average_render_time > 16.0) {
            try suggestions.append(allocator, try allocator.dupe(u8, "Reduce render complexity or optimize rendering pipeline"));
        }

        if (self.stats.getCacheHitRate() < 70.0) {
            try suggestions.append(allocator, try allocator.dupe(u8, "Improve caching strategy to reduce redundant operations"));
        }

        if (self.stats.plugin_response_time > 10.0) {
            try suggestions.append(allocator, try allocator.dupe(u8, "Review plugin performance or consider plugin optimization"));
        }

        return suggestions.toOwnedSlice();
    }
};

/// Timer for measuring operation duration
pub const OperationTimer = struct {
    monitor: ?*EditorPerformanceMonitor,
    name: []const u8,
    start_time: i64,
    enabled: bool,

    pub fn dummy() OperationTimer {
        return .{
            .monitor = null,
            .name = "",
            .start_time = 0,
            .enabled = false,
        };
    }

    pub fn end(self: OperationTimer) void {
        if (!self.enabled or self.monitor == null) return;

        const end_time = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(end_time - self.start_time));
        self.monitor.?.recordOperation(self.name, duration);
    }
};

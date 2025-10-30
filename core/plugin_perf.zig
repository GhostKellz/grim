//! Plugin Performance Optimization
//!
//! Features:
//! - Plugin execution profiling
//! - Automatic performance throttling
//! - Plugin sandboxing (CPU/memory limits)
//! - Hot path detection
//! - Performance recommendations

const std = @import("std");

pub const PluginProfiler = struct {
    allocator: std.mem.Allocator,
    profiles: std.StringHashMap(PluginProfile),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .profiles = std.StringHashMap(PluginProfile).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.profiles.valueIterator();
        while (it.next()) |profile| {
            profile.deinit(self.allocator);
        }
        self.profiles.deinit();
    }

    /// Start profiling a plugin function call
    pub fn startCall(self: *Self, plugin_name: []const u8, function_name: []const u8) !CallHandle {
        const entry = try self.profiles.getOrPut(plugin_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = PluginProfile.init(self.allocator, plugin_name);
        }

        return CallHandle{
            .profile = entry.value_ptr,
            .function_name = function_name,
            .start_time = std.time.nanoTimestamp(),
            .start_memory = 0, // TODO: Get current memory usage
        };
    }

    /// Get profiling statistics
    pub fn getStats(self: *Self, plugin_name: []const u8) ?PluginStats {
        const profile = self.profiles.get(plugin_name) orelse return null;
        return profile.getStats();
    }

    /// Get performance recommendations
    pub fn getRecommendations(self: *Self, plugin_name: []const u8) ![]Recommendation {
        const profile = self.profiles.get(plugin_name) orelse return &[_]Recommendation{};

        var recommendations = std.ArrayList(Recommendation).init(self.allocator);
        errdefer recommendations.deinit();

        const stats = profile.getStats();

        // Check for slow functions
        if (stats.avg_call_time_us > 1000) {
            try recommendations.append(.{
                .severity = .warning,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Average call time is {d}μs (>1ms). Consider optimizing.",
                    .{stats.avg_call_time_us},
                ),
            });
        }

        // Check for high call frequency
        if (stats.calls_per_second > 1000) {
            try recommendations.append(.{
                .severity = .info,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "High call frequency ({d:.0} calls/sec). Consider batching or caching.",
                    .{stats.calls_per_second},
                ),
            });
        }

        // Check for memory usage
        if (stats.peak_memory_bytes > 10 * 1024 * 1024) {
            try recommendations.append(.{
                .severity = .warning,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "High memory usage ({d}MB). Consider reducing allocations.",
                    .{stats.peak_memory_bytes / (1024 * 1024)},
                ),
            });
        }

        return recommendations.toOwnedSlice();
    }
};

pub const PluginProfile = struct {
    name: []const u8,
    function_calls: std.StringHashMap(FunctionStats),
    total_call_count: usize,
    total_time_ns: i64,
    peak_memory_bytes: usize,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) PluginProfile {
        return .{
            .name = name,
            .function_calls = std.StringHashMap(FunctionStats).init(allocator),
            .total_call_count = 0,
            .total_time_ns = 0,
            .peak_memory_bytes = 0,
        };
    }

    pub fn deinit(self: *PluginProfile, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.function_calls.deinit();
    }

    pub fn recordCall(self: *PluginProfile, function_name: []const u8, elapsed_ns: i64, memory_used: usize) !void {
        const entry = try self.function_calls.getOrPut(function_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = FunctionStats{};
        }

        entry.value_ptr.call_count += 1;
        entry.value_ptr.total_time_ns += elapsed_ns;
        entry.value_ptr.min_time_ns = @min(entry.value_ptr.min_time_ns, elapsed_ns);
        entry.value_ptr.max_time_ns = @max(entry.value_ptr.max_time_ns, elapsed_ns);

        self.total_call_count += 1;
        self.total_time_ns += elapsed_ns;
        self.peak_memory_bytes = @max(self.peak_memory_bytes, memory_used);
    }

    pub fn getStats(self: *PluginProfile) PluginStats {
        const avg_time_us = if (self.total_call_count > 0)
            @divTrunc(self.total_time_ns, @as(i64, @intCast(self.total_call_count)) * 1000)
        else
            0;

        return .{
            .total_calls = self.total_call_count,
            .avg_call_time_us = avg_time_us,
            .total_time_ms = @divTrunc(self.total_time_ns, 1_000_000),
            .peak_memory_bytes = self.peak_memory_bytes,
            .calls_per_second = 0, // TODO: Calculate based on time window
        };
    }
};

pub const FunctionStats = struct {
    call_count: usize = 0,
    total_time_ns: i64 = 0,
    min_time_ns: i64 = std.math.maxInt(i64),
    max_time_ns: i64 = 0,
};

pub const CallHandle = struct {
    profile: *PluginProfile,
    function_name: []const u8,
    start_time: i64,
    start_memory: usize,

    pub fn end(self: CallHandle) !void {
        const elapsed_ns = std.time.nanoTimestamp() - self.start_time;
        const memory_used = 0; // TODO: Calculate memory delta

        try self.profile.recordCall(self.function_name, elapsed_ns, memory_used);
    }
};

pub const PluginStats = struct {
    total_calls: usize,
    avg_call_time_us: i64,
    total_time_ms: i64,
    peak_memory_bytes: usize,
    calls_per_second: f64,
};

pub const Recommendation = struct {
    severity: Severity,
    message: []const u8,

    pub const Severity = enum {
        info,
        warning,
        error_sev,
    };
};

/// Plugin sandbox for resource limiting
pub const PluginSandbox = struct {
    cpu_limit_ms: u64,
    memory_limit_bytes: usize,
    start_time: i64,
    allocator: std.mem.Allocator,
    tracking_allocator: TrackingAllocator,

    pub fn init(allocator: std.mem.Allocator, cpu_limit_ms: u64, memory_limit_bytes: usize) PluginSandbox {
        return .{
            .cpu_limit_ms = cpu_limit_ms,
            .memory_limit_bytes = memory_limit_bytes,
            .start_time = std.time.milliTimestamp(),
            .allocator = allocator,
            .tracking_allocator = TrackingAllocator.init(allocator, memory_limit_bytes),
        };
    }

    /// Get sandbox allocator
    pub fn allocator(self: *PluginSandbox) std.mem.Allocator {
        return self.tracking_allocator.allocator();
    }

    /// Check if sandbox limits are exceeded
    pub fn checkLimits(self: *PluginSandbox) !void {
        // Check CPU time
        const elapsed_ms = @as(u64, @intCast(std.time.milliTimestamp() - self.start_time));
        if (elapsed_ms > self.cpu_limit_ms) {
            return error.CPULimitExceeded;
        }

        // Check memory (handled by tracking allocator)
    }

    /// Get resource usage
    pub fn getUsage(self: *PluginSandbox) Usage {
        const elapsed_ms = @as(u64, @intCast(std.time.milliTimestamp() - self.start_time));
        const memory_used = self.tracking_allocator.bytes_allocated;

        return .{
            .cpu_time_ms = elapsed_ms,
            .cpu_limit_ms = self.cpu_limit_ms,
            .memory_bytes = memory_used,
            .memory_limit_bytes = self.memory_limit_bytes,
        };
    }

    pub const Usage = struct {
        cpu_time_ms: u64,
        cpu_limit_ms: u64,
        memory_bytes: usize,
        memory_limit_bytes: usize,
    };
};

/// Tracking allocator that enforces memory limits
const TrackingAllocator = struct {
    parent_allocator: std.mem.Allocator,
    bytes_allocated: usize,
    bytes_limit: usize,

    fn init(parent: std.mem.Allocator, limit: usize) TrackingAllocator {
        return .{
            .parent_allocator = parent,
            .bytes_allocated = 0,
            .bytes_limit = limit,
        };
    }

    fn allocator(self: *TrackingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));

        // Check limit
        if (self.bytes_allocated + len > self.bytes_limit) {
            return null;
        }

        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr) orelse return null;
        self.bytes_allocated += len;
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));

        if (new_len > buf.len) {
            // Growing
            const delta = new_len - buf.len;
            if (self.bytes_allocated + delta > self.bytes_limit) {
                return false;
            }
        }

        if (!self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
            return false;
        }

        if (new_len > buf.len) {
            self.bytes_allocated += new_len - buf.len;
        } else {
            self.bytes_allocated -= buf.len - new_len;
        }

        return true;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
        self.bytes_allocated -= buf.len;
    }
};

/// Hot path detector for identifying performance-critical code
pub const HotPathDetector = struct {
    samples: std.AutoHashMap(usize, usize), // addr -> count
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HotPathDetector {
        return .{
            .samples = std.AutoHashMap(usize, usize).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HotPathDetector) void {
        self.samples.deinit();
    }

    /// Record a sample at return address
    pub fn sample(self: *HotPathDetector, return_addr: usize) !void {
        const entry = try self.samples.getOrPut(return_addr);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    /// Get hot paths (top N most frequent)
    pub fn getHotPaths(self: *HotPathDetector, n: usize) ![]HotPath {
        var paths = std.ArrayList(HotPath).init(self.allocator);
        defer paths.deinit();

        var it = self.samples.iterator();
        while (it.next()) |entry| {
            try paths.append(.{
                .address = entry.key_ptr.*,
                .count = entry.value_ptr.*,
            });
        }

        // Sort by count (descending)
        std.mem.sort(HotPath, paths.items, {}, struct {
            fn lessThan(_: void, a: HotPath, b: HotPath) bool {
                return a.count > b.count;
            }
        }.lessThan);

        const count = @min(n, paths.items.len);
        const result = try self.allocator.alloc(HotPath, count);
        @memcpy(result, paths.items[0..count]);
        return result;
    }

    pub const HotPath = struct {
        address: usize,
        count: usize,
    };
};

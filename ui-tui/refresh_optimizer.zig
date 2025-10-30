//! Refresh Rate Optimization for 120Hz+ Displays
//!
//! Features:
//! - Adaptive refresh rate based on activity
//! - Dirty region tracking for partial redraws
//! - Frame pacing for consistent timing
//! - Power-saving mode when idle

const std = @import("std");

pub const RefreshOptimizer = struct {
    allocator: std.mem.Allocator,

    // Refresh rate configuration
    max_refresh_rate: f32,      // Maximum supported (e.g., 120, 144, 240 Hz)
    current_refresh_rate: f32,  // Current target rate
    min_refresh_rate: f32,      // Minimum when idle (e.g., 30 Hz)

    // Activity tracking
    last_input_time: i64,
    last_render_time: i64,
    activity_state: ActivityState,

    // Dirty region tracking
    dirty_regions: std.ArrayList(Rect),
    full_redraw_pending: bool,

    // Frame pacing
    frame_budget_ns: u64,       // Nanoseconds per frame
    last_frame_time: i64,
    frame_times: [60]u64,       // Rolling average
    frame_time_index: usize,

    // Statistics
    frames_rendered: u64,
    frames_skipped: u64,
    partial_redraws: u64,
    full_redraws: u64,

    const Self = @This();

    pub const ActivityState = enum {
        idle,       // No input for >5 seconds
        typing,     // Active text input
        scrolling,  // Scrolling through content
        animating,  // UI animations active
    };

    pub const Rect = struct {
        x: u32,
        y: u32,
        width: u32,
        height: u32,

        pub fn intersects(self: Rect, other: Rect) bool {
            return !(self.x + self.width < other.x or
                other.x + other.width < self.x or
                self.y + self.height < other.y or
                other.y + other.height < self.y);
        }

        pub fn merge(self: Rect, other: Rect) Rect {
            const x1 = @min(self.x, other.x);
            const y1 = @min(self.y, other.y);
            const x2 = @max(self.x + self.width, other.x + other.width);
            const y2 = @max(self.y + self.height, other.y + other.height);
            return .{
                .x = x1,
                .y = y1,
                .width = x2 - x1,
                .height = y2 - y1,
            };
        }

        pub fn area(self: Rect) u64 {
            return @as(u64, self.width) * @as(u64, self.height);
        }
    };

    pub fn init(allocator: std.mem.Allocator, max_hz: f32) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .max_refresh_rate = max_hz,
            .current_refresh_rate = max_hz,
            .min_refresh_rate = 30.0,
            .last_input_time = std.time.milliTimestamp(),
            .last_render_time = 0,
            .activity_state = .idle,
            .dirty_regions = std.ArrayList(Rect).init(allocator),
            .full_redraw_pending = true,
            .frame_budget_ns = @intFromFloat(1_000_000_000.0 / max_hz),
            .last_frame_time = std.time.nanoTimestamp(),
            .frame_times = [_]u64{0} ** 60,
            .frame_time_index = 0,
            .frames_rendered = 0,
            .frames_skipped = 0,
            .partial_redraws = 0,
            .full_redraws = 0,
        };

        std.log.info("Refresh optimizer initialized: {d:.0}Hz max", .{max_hz});
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.dirty_regions.deinit();
        self.allocator.destroy(self);
    }

    /// Mark a region as dirty (needs redraw)
    pub fn markDirty(self: *Self, rect: Rect) !void {
        // Try to merge with existing dirty regions
        var merged = false;
        for (self.dirty_regions.items) |*existing| {
            if (existing.intersects(rect)) {
                existing.* = existing.merge(rect);
                merged = true;
                break;
            }
        }

        if (!merged) {
            try self.dirty_regions.append(rect);
        }

        // If dirty regions cover >70% of screen, do full redraw instead
        const total_area = self.calculateDirtyArea();
        const screen_area = 1920 * 1080; // TODO: Get actual screen size
        if (total_area > screen_area * 70 / 100) {
            self.markFullRedraw();
        }
    }

    /// Mark entire screen for redraw
    pub fn markFullRedraw(self: *Self) void {
        self.dirty_regions.clearRetainingCapacity();
        self.full_redraw_pending = true;
    }

    /// Clear all dirty regions
    pub fn clearDirty(self: *Self) void {
        self.dirty_regions.clearRetainingCapacity();
        self.full_redraw_pending = false;
    }

    fn calculateDirtyArea(self: *Self) u64 {
        var total: u64 = 0;
        for (self.dirty_regions.items) |rect| {
            total += rect.area();
        }
        return total;
    }

    /// Record input activity
    pub fn recordInput(self: *Self) void {
        self.last_input_time = std.time.milliTimestamp();
        self.updateActivityState();
    }

    /// Update activity state based on time since last input
    fn updateActivityState(self: *Self) void {
        const now = std.time.milliTimestamp();
        const idle_time = now - self.last_input_time;

        const old_state = self.activity_state;
        self.activity_state = if (idle_time > 5000)
            .idle
        else if (idle_time < 100)
            .typing
        else
            .idle;

        // Adjust refresh rate based on activity
        if (self.activity_state != old_state) {
            self.current_refresh_rate = switch (self.activity_state) {
                .idle => self.min_refresh_rate,
                .typing => self.max_refresh_rate,
                .scrolling => self.max_refresh_rate,
                .animating => self.max_refresh_rate,
            };

            self.frame_budget_ns = @intFromFloat(1_000_000_000.0 / self.current_refresh_rate);

            std.log.debug("Activity state: {} -> {d:.0}Hz", .{
                self.activity_state,
                self.current_refresh_rate,
            });
        }
    }

    /// Check if we should render a frame
    pub fn shouldRenderFrame(self: *Self) bool {
        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - self.last_frame_time));

        // Update activity state
        self.updateActivityState();

        // Always render if we have pending changes
        if (self.full_redraw_pending or self.dirty_regions.items.len > 0) {
            return elapsed >= self.frame_budget_ns;
        }

        // In idle mode, render at min refresh rate
        if (self.activity_state == .idle) {
            const idle_budget = @as(u64, @intFromFloat(1_000_000_000.0 / self.min_refresh_rate));
            return elapsed >= idle_budget;
        }

        // Otherwise render at current refresh rate
        return elapsed >= self.frame_budget_ns;
    }

    /// Begin a frame
    pub fn beginFrame(self: *Self) FrameInfo {
        const now = std.time.nanoTimestamp();
        const frame_time = @as(u64, @intCast(now - self.last_frame_time));

        // Record frame time for statistics
        self.frame_times[self.frame_time_index] = frame_time;
        self.frame_time_index = (self.frame_time_index + 1) % self.frame_times.len;

        self.last_frame_time = now;
        self.frames_rendered += 1;

        const is_full_redraw = self.full_redraw_pending;
        if (is_full_redraw) {
            self.full_redraws += 1;
        } else if (self.dirty_regions.items.len > 0) {
            self.partial_redraws += 1;
        }

        return FrameInfo{
            .is_full_redraw = is_full_redraw,
            .dirty_regions = if (is_full_redraw) &[_]Rect{} else self.dirty_regions.items,
            .frame_time_ns = frame_time,
            .target_fps = self.current_refresh_rate,
        };
    }

    /// End a frame
    pub fn endFrame(self: *Self) void {
        self.clearDirty();
    }

    /// Get average frame time in milliseconds
    pub fn getAverageFrameTime(self: *Self) f32 {
        var total: u64 = 0;
        var count: usize = 0;
        for (self.frame_times) |time| {
            if (time > 0) {
                total += time;
                count += 1;
            }
        }
        if (count == 0) return 0.0;
        return @as(f32, @floatFromInt(total / count)) / 1_000_000.0; // Convert to ms
    }

    /// Get current FPS
    pub fn getCurrentFPS(self: *Self) f32 {
        const avg_frame_time = self.getAverageFrameTime();
        if (avg_frame_time == 0.0) return 0.0;
        return 1000.0 / avg_frame_time;
    }

    /// Get statistics
    pub fn getStats(self: *Self) Stats {
        return .{
            .frames_rendered = self.frames_rendered,
            .frames_skipped = self.frames_skipped,
            .partial_redraws = self.partial_redraws,
            .full_redraws = self.full_redraws,
            .current_fps = self.getCurrentFPS(),
            .average_frame_time_ms = self.getAverageFrameTime(),
            .activity_state = self.activity_state,
            .target_refresh_rate = self.current_refresh_rate,
        };
    }

    /// Set maximum refresh rate
    pub fn setMaxRefreshRate(self: *Self, hz: f32) void {
        self.max_refresh_rate = hz;
        if (self.current_refresh_rate > hz) {
            self.current_refresh_rate = hz;
            self.frame_budget_ns = @intFromFloat(1_000_000_000.0 / hz);
        }
        std.log.info("Max refresh rate set to {d:.0}Hz", .{hz});
    }

    /// Enable/disable power saving mode
    pub fn setPowerSaving(self: *Self, enabled: bool) void {
        if (enabled) {
            self.min_refresh_rate = 30.0;
            std.log.info("Power saving enabled: idle={d:.0}Hz", .{self.min_refresh_rate});
        } else {
            self.min_refresh_rate = 60.0;
            std.log.info("Power saving disabled: idle={d:.0}Hz", .{self.min_refresh_rate});
        }
    }
};

pub const FrameInfo = struct {
    is_full_redraw: bool,
    dirty_regions: []const RefreshOptimizer.Rect,
    frame_time_ns: u64,
    target_fps: f32,
};

pub const Stats = struct {
    frames_rendered: u64,
    frames_skipped: u64,
    partial_redraws: u64,
    full_redraws: u64,
    current_fps: f32,
    average_frame_time_ms: f32,
    activity_state: RefreshOptimizer.ActivityState,
    target_refresh_rate: f32,
};

/// Frame limiter for consistent timing
pub const FrameLimiter = struct {
    target_frame_time_ns: u64,
    last_frame_time: i64,

    pub fn init(target_fps: f32) FrameLimiter {
        return .{
            .target_frame_time_ns = @intFromFloat(1_000_000_000.0 / target_fps),
            .last_frame_time = std.time.nanoTimestamp(),
        };
    }

    /// Wait until next frame should be rendered
    pub fn wait(self: *FrameLimiter) void {
        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - self.last_frame_time));

        if (elapsed < self.target_frame_time_ns) {
            const sleep_time = self.target_frame_time_ns - elapsed;
            std.time.sleep(sleep_time);
        }

        self.last_frame_time = std.time.nanoTimestamp();
    }

    /// Set target FPS
    pub fn setTargetFPS(self: *FrameLimiter, fps: f32) void {
        self.target_frame_time_ns = @intFromFloat(1_000_000_000.0 / fps);
    }
};

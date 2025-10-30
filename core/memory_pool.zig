//! Memory Pool Allocator for High-Performance Object Allocation
//!
//! Features:
//! - Fixed-size object pools (no fragmentation)
//! - O(1) allocation and deallocation
//! - Cache-friendly memory layout
//! - Thread-safe option
//! - Memory usage tracking

const std = @import("std");

/// Generic memory pool for fixed-size objects
pub fn MemoryPool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        free_list: ?*Node,
        chunks: std.ArrayList([]align(@alignOf(Node)) u8),
        objects_per_chunk: usize,
        total_allocated: usize,
        total_free: usize,

        const Self = @This();

        const Node = struct {
            next: ?*Node,
            data: T align(@alignOf(T)),
        };

        pub fn init(allocator: std.mem.Allocator, objects_per_chunk: usize) Self {
            return .{
                .allocator = allocator,
                .free_list = null,
                .chunks = std.ArrayList([]align(@alignOf(Node)) u8).init(allocator),
                .objects_per_chunk = objects_per_chunk,
                .total_allocated = 0,
                .total_free = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.chunks.items) |chunk| {
                self.allocator.free(chunk);
            }
            self.chunks.deinit();
        }

        /// Allocate an object from the pool
        pub fn alloc(self: *Self) !*T {
            // Check free list
            if (self.free_list) |node| {
                self.free_list = node.next;
                self.total_free -= 1;
                return &node.data;
            }

            // Need to allocate a new chunk
            try self.allocateChunk();
            return self.alloc();
        }

        /// Return an object to the pool
        pub fn free(self: *Self, ptr: *T) void {
            const node: *Node = @fieldParentPtr("data", ptr);
            node.next = self.free_list;
            self.free_list = node;
            self.total_free += 1;
        }

        fn allocateChunk(self: *Self) !void {
            const chunk_size = self.objects_per_chunk * @sizeOf(Node);
            const chunk = try self.allocator.alignedAlloc(u8, @alignOf(Node), chunk_size);
            errdefer self.allocator.free(chunk);

            try self.chunks.append(chunk);

            // Add all nodes to free list
            for (0..self.objects_per_chunk) |i| {
                const offset = i * @sizeOf(Node);
                const node: *Node = @ptrCast(@alignCast(&chunk[offset]));
                node.next = self.free_list;
                self.free_list = node;
                self.total_free += 1;
            }

            self.total_allocated += self.objects_per_chunk;
        }

        /// Get memory usage statistics
        pub fn getStats(self: *Self) Stats {
            return .{
                .total_allocated = self.total_allocated,
                .total_free = self.total_free,
                .in_use = self.total_allocated - self.total_free,
                .chunks = self.chunks.items.len,
                .bytes_allocated = self.chunks.items.len * self.objects_per_chunk * @sizeOf(Node),
            };
        }

        pub const Stats = struct {
            total_allocated: usize,
            total_free: usize,
            in_use: usize,
            chunks: usize,
            bytes_allocated: usize,
        };
    };
}

/// Slab allocator for variable-size allocations
pub const SlabAllocator = struct {
    allocator: std.mem.Allocator,
    slabs: [NUM_SLABS]Slab,

    const NUM_SLABS = 8;
    const SLAB_SIZES = [NUM_SLABS]usize{
        16,    // Tiny (strings, small buffers)
        32,    // Small
        64,    // Medium-small
        128,   // Medium
        256,   // Medium-large
        512,   // Large
        1024,  // Very large
        4096,  // Huge
    };

    const Slab = struct {
        pool: std.heap.MemoryPool(u8),
        size: usize,
    };

    pub fn init(allocator: std.mem.Allocator) SlabAllocator {
        var slabs: [NUM_SLABS]Slab = undefined;

        for (&slabs, 0..) |*slab, i| {
            slab.* = .{
                .pool = std.heap.MemoryPool(u8).init(allocator),
                .size = SLAB_SIZES[i],
            };
        }

        return .{
            .allocator = allocator,
            .slabs = slabs,
        };
    }

    pub fn deinit(self: *SlabAllocator) void {
        for (&self.slabs) |*slab| {
            slab.pool.deinit();
        }
    }

    pub fn allocator(self: *SlabAllocator) std.mem.Allocator {
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
        _ = ret_addr;
        const self: *SlabAllocator = @ptrCast(@alignCast(ctx));

        // Find appropriate slab
        for (&self.slabs) |*slab| {
            if (len <= slab.size and ptr_align <= @alignOf(u8)) {
                return slab.pool.create() catch return null;
            }
        }

        // Fall back to backing allocator for large allocations
        return @ptrCast(self.allocator.rawAlloc(len, ptr_align, ret_addr) orelse return null);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Cannot resize in slab allocator
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ret_addr;
        const self: *SlabAllocator = @ptrCast(@alignCast(ctx));

        // Find appropriate slab
        for (&self.slabs) |*slab| {
            if (buf.len <= slab.size and buf_align <= @alignOf(u8)) {
                slab.pool.destroy(buf.ptr);
                return;
            }
        }

        // Fall back to backing allocator
        self.allocator.rawFree(buf, buf_align, ret_addr);
    }
};

/// Stack allocator for temporary allocations (reset at frame end)
pub const StackAllocator = struct {
    buffer: []u8,
    offset: usize,
    high_water_mark: usize,

    pub fn init(backing_buffer: []u8) StackAllocator {
        return .{
            .buffer = backing_buffer,
            .offset = 0,
            .high_water_mark = 0,
        };
    }

    pub fn allocator(self: *StackAllocator) std.mem.Allocator {
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
        _ = ret_addr;
        const self: *StackAllocator = @ptrCast(@alignCast(ctx));

        // Align offset
        const aligned_offset = std.mem.alignForward(usize, self.offset, ptr_align);

        // Check if we have space
        if (aligned_offset + len > self.buffer.len) {
            return null;
        }

        const ptr = self.buffer[aligned_offset..].ptr;
        self.offset = aligned_offset + len;
        self.high_water_mark = @max(self.high_water_mark, self.offset);

        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ret_addr;
        const self: *StackAllocator = @ptrCast(@alignCast(ctx));

        // Can only resize if this was the last allocation
        const buf_end = @intFromPtr(buf.ptr) + buf.len;
        const stack_end = @intFromPtr(self.buffer.ptr) + self.offset;

        if (buf_end != stack_end) return false;

        // Align new size
        const aligned_new_len = std.mem.alignForward(usize, new_len, buf_align);
        const old_end = @intFromPtr(buf.ptr) + buf.len;
        const new_end = @intFromPtr(buf.ptr) + aligned_new_len;

        if (new_end > @intFromPtr(self.buffer.ptr) + self.buffer.len) {
            return false;
        }

        self.offset = new_end - @intFromPtr(self.buffer.ptr);
        return true;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // No-op: freed on reset()
    }

    /// Reset allocator (free all allocations)
    pub fn reset(self: *StackAllocator) void {
        self.offset = 0;
    }

    /// Get memory usage
    pub fn getUsage(self: *StackAllocator) struct { used: usize, total: usize, high_water: usize } {
        return .{
            .used = self.offset,
            .total = self.buffer.len,
            .high_water = self.high_water_mark,
        };
    }
};

/// Memory usage tracker
pub const MemoryTracker = struct {
    total_allocated: std.atomic.Value(usize),
    total_freed: std.atomic.Value(usize),
    peak_usage: std.atomic.Value(usize),
    allocation_count: std.atomic.Value(usize),
    free_count: std.atomic.Value(usize),

    pub fn init() MemoryTracker {
        return .{
            .total_allocated = std.atomic.Value(usize).init(0),
            .total_freed = std.atomic.Value(usize).init(0),
            .peak_usage = std.atomic.Value(usize).init(0),
            .allocation_count = std.atomic.Value(usize).init(0),
            .free_count = std.atomic.Value(usize).init(0),
        };
    }

    pub fn recordAlloc(self: *MemoryTracker, size: usize) void {
        const allocated = self.total_allocated.fetchAdd(size, .monotonic) + size;
        const freed = self.total_freed.load(.monotonic);
        const current_usage = allocated - freed;

        // Update peak
        var peak = self.peak_usage.load(.monotonic);
        while (current_usage > peak) {
            peak = self.peak_usage.cmpxchgWeak(peak, current_usage, .monotonic, .monotonic) orelse break;
        }

        _ = self.allocation_count.fetchAdd(1, .monotonic);
    }

    pub fn recordFree(self: *MemoryTracker, size: usize) void {
        _ = self.total_freed.fetchAdd(size, .monotonic);
        _ = self.free_count.fetchAdd(1, .monotonic);
    }

    pub fn getStats(self: *MemoryTracker) Stats {
        const allocated = self.total_allocated.load(.monotonic);
        const freed = self.total_freed.load(.monotonic);

        return .{
            .current_usage = allocated - freed,
            .peak_usage = self.peak_usage.load(.monotonic),
            .total_allocated = allocated,
            .total_freed = freed,
            .allocation_count = self.allocation_count.load(.monotonic),
            .free_count = self.free_count.load(.monotonic),
        };
    }

    pub const Stats = struct {
        current_usage: usize,
        peak_usage: usize,
        total_allocated: usize,
        total_freed: usize,
        allocation_count: usize,
        free_count: usize,
    };
};

test "MemoryPool basic" {
    const TestStruct = struct {
        value: u32,
    };

    var pool = MemoryPool(TestStruct).init(std.testing.allocator, 4);
    defer pool.deinit();

    const obj1 = try pool.alloc();
    obj1.value = 42;

    const obj2 = try pool.alloc();
    obj2.value = 100;

    try std.testing.expectEqual(@as(u32, 42), obj1.value);
    try std.testing.expectEqual(@as(u32, 100), obj2.value);

    pool.free(obj1);
    pool.free(obj2);

    const stats = pool.getStats();
    try std.testing.expectEqual(@as(usize, 4), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 4), stats.total_free);
}

test "StackAllocator basic" {
    var buffer: [1024]u8 = undefined;
    var stack = StackAllocator.init(&buffer);

    const alloc = stack.allocator();

    const data1 = try alloc.alloc(u8, 64);
    @memset(data1, 0xAA);

    const data2 = try alloc.alloc(u8, 128);
    @memset(data2, 0xBB);

    const usage = stack.getUsage();
    try std.testing.expect(usage.used > 0);
    try std.testing.expect(usage.used <= usage.total);

    stack.reset();
    try std.testing.expectEqual(@as(usize, 0), stack.offset);
}

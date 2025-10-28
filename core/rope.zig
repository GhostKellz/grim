const std = @import("std");
const simd_utf8 = @import("simd_utf8.zig");

/// Lookup table for UTF-8 byte classification (faster than bitwise ops)
/// true = start byte (valid boundary), false = continuation byte
const utf8_boundary_table = blk: {
    @setEvalBranchQuota(300);
    var table: [256]bool = undefined;
    for (&table, 0..) |*entry, i| {
        // Continuation bytes: 0x80-0xBF (10xxxxxx)
        entry.* = (i < 0x80) or (i >= 0xC0);
    }
    break :blk table;
};

/// Check if position is at a valid UTF-8 boundary (optimized with lookup table)
inline fn isUtf8Boundary(data: []const u8, pos: usize) bool {
    if (pos == 0 or pos >= data.len) return true;
    return utf8_boundary_table[data[pos]];
}

/// Find the nearest UTF-8 boundary at or before pos (optimized)
fn findUtf8BoundaryBefore(data: []const u8, pos: usize) usize {
    if (pos == 0 or pos >= data.len) return pos;

    // Fast path: already at boundary
    if (utf8_boundary_table[data[pos]]) return pos;

    // Scan backwards (max 3 bytes in UTF-8)
    var i = pos;
    const min_pos = if (pos >= 3) pos - 3 else 0;
    while (i > min_pos) {
        i -= 1;
        if (utf8_boundary_table[data[i]]) return i;
    }

    // Fallback: scan all the way back (shouldn't happen with valid UTF-8)
    while (i > 0) {
        i -= 1;
        if (utf8_boundary_table[data[i]]) return i;
    }

    return 0;
}

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        return self.end - self.start;
    }
};

const EmptySlice = [_]u8{};

/// Iterator for zero-copy access to rope data segments
/// Allows reading rope content without allocating or copying
pub const RopeIterator = struct {
    pieces: []const *Rope.Piece,
    range: Range,
    piece_index: usize,
    absolute_offset: usize,

    /// Get next segment of data within the range (zero-copy)
    /// Returns null when iteration is complete
    pub fn next(self: *RopeIterator) ?[]const u8 {
        while (self.piece_index < self.pieces.len) {
            const piece = self.pieces[self.piece_index].*;
            const piece_len = piece.len();
            const piece_start = self.absolute_offset;
            const piece_end = piece_start + piece_len;

            defer {
                self.piece_index += 1;
                self.absolute_offset = piece_end;
            }

            // Skip pieces before range
            if (piece_end <= self.range.start) {
                continue;
            }

            // Stop if past range
            if (piece_start >= self.range.end) {
                return null;
            }

            // Calculate segment within this piece
            const local_start = if (self.range.start > piece_start) self.range.start - piece_start else 0;
            const local_end = if (self.range.end < piece_end) self.range.end - piece_start else piece_len;

            const segment = piece.data[local_start..local_end];
            if (segment.len > 0) {
                return segment;
            }
        }
        return null;
    }
};

pub const Rope = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    pieces: std.ArrayListUnmanaged(*Piece),
    length: usize,
    // Cache line count for O(1) access - invalidated on insert/delete
    cached_line_count: ?usize,

    const Piece = struct {
        data: []const u8,

        fn len(self: *const Piece) usize {
            return self.data.len;
        }
    };

    pub const Snapshot = struct {
        nodes: []const *Piece,
        length: usize,
    };

    pub const Error = error{
        OutOfBounds,
        InvalidRange,
        InvalidUtf8,
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator) !Rope {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        return Rope{
            .allocator = allocator,
            .arena = arena,
            .pieces = .{},
            .length = 0,
            .cached_line_count = 1, // Empty buffer has 1 line
        };
    }

    pub fn deinit(self: *Rope) void {
        self.pieces.deinit(self.allocator);
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn isEmpty(self: *const Rope) bool {
        return self.length == 0;
    }

    pub fn len(self: *const Rope) usize {
        return self.length;
    }

    /// Create a zero-copy iterator over a range of rope data
    /// Use this for performance-critical code that can handle segments
    /// Example:
    ///   var iter = rope.iterator(.{ .start = 0, .end = rope.len() });
    ///   while (iter.next()) |segment| {
    ///       // Process segment without copying
    ///   }
    pub fn iterator(self: *const Rope, range: Range) RopeIterator {
        return RopeIterator{
            .pieces = self.pieces.items,
            .range = range,
            .piece_index = 0,
            .absolute_offset = 0,
        };
    }

    pub fn insert(self: *Rope, pos: usize, bytes: []const u8) Error!void {
        if (pos > self.length) return Error.OutOfBounds;
        if (bytes.len == 0) return;

        // SIMD-accelerated UTF-8 validation (AVX-512/AVX2/SSE4.2/scalar)
        // This provides 10-20 GB/s throughput on modern CPUs
        if (!simd_utf8.validate(bytes)) {
            return Error.InvalidUtf8;
        }

        const piece_ptr = try self.createPieceCopy(bytes);
        const index = try self.ensureCut(pos);
        try self.pieces.insert(self.allocator, index, piece_ptr);
        self.length += bytes.len;

        // Invalidate line count cache
        self.cached_line_count = null;
    }

    pub fn delete(self: *Rope, start: usize, len_to_remove: usize) Error!void {
        if (len_to_remove == 0) return;
        if (start > self.length) return Error.OutOfBounds;
        if (start + len_to_remove > self.length) return Error.OutOfBounds;

        const begin_index = try self.ensureCut(start);
        const end_index = try self.ensureCut(start + len_to_remove);

        // Optimized: Use replaceRange for batch removal (faster than loop)
        const num_to_remove = end_index - begin_index;
        if (num_to_remove > 0) {
            self.pieces.replaceRange(self.allocator, begin_index, num_to_remove, &[_]*Piece{}) catch |err| return err;
        }

        self.length -= len_to_remove;

        // Invalidate line count cache
        self.cached_line_count = null;
    }

    /// Get a contiguous slice of rope data
    /// - For single-piece ranges: returns zero-copy view (fast!)
    /// - For multi-piece ranges: allocates via arena (auto-cleanup)
    /// - For zero-copy iteration over segments, use iterator() instead
    /// Memory is tied to rope lifetime (arena-allocated), no manual free needed
    pub fn slice(self: *Rope, range: Range) Error![]const u8 {
        if (range.start > range.end) return Error.InvalidRange;
        if (range.end > self.length) return Error.OutOfBounds;
        const total_len = range.len();
        if (total_len == 0) return &EmptySlice;

        var remaining = total_len;
        var cursor = range.start;
        var running: usize = 0;
        var first = true;
        var buffer: ?[]u8 = null;
        var write_index: usize = 0;

        for (self.pieces.items[0..self.pieces.items.len]) |piece_ptr| {
            const piece = piece_ptr.*;
            const piece_len = piece.len();
            if (cursor >= running + piece_len) {
                running += piece_len;
                continue;
            }

            const local_start = cursor - running;
            const available = piece_len - local_start;
            const take = @min(available, remaining);
            const segment = piece.data[local_start .. local_start + take];

            // Fast path: entire range is in a single piece (zero-copy!)
            if (first and take == total_len) {
                return segment;
            }

            // Allocate from arena (auto-cleanup on rope.deinit)
            if (buffer == null) {
                var arena_alloc = self.arena.allocator();
                buffer = try arena_alloc.alloc(u8, total_len);
            }

            @memcpy(buffer.?[write_index .. write_index + take], segment);
            write_index += take;
            remaining -= take;
            if (remaining == 0) {
                break;
            }

            running += piece_len;
            cursor = running;
            first = false;
        }

        if (remaining != 0 or buffer == null) return Error.OutOfBounds;
        return buffer.?;
    }

    pub fn lineCount(self: *Rope) usize {
        // Return cached value if available (O(1) instead of O(n))
        if (self.cached_line_count) |count| {
            return count;
        }

        // Calculate and cache
        if (self.length == 0) {
            self.cached_line_count = 1;
            return 1;
        }

        var count: usize = 1;
        for (self.pieces.items) |piece_ptr| {
            for (piece_ptr.data) |byte| {
                if (byte == '\n') count += 1;
            }
        }

        self.cached_line_count = count;
        return count;
    }

    pub fn lineRange(self: *const Rope, line_num: usize) Error!Range {
        if (line_num == 0 and self.length == 0) {
            return .{ .start = 0, .end = 0 };
        }

        var current_line: usize = 0;
        var absolute_offset: usize = 0;
        var line_start: usize = 0;
        var start_set = false;

        for (self.pieces.items) |piece_ptr| {
            const data = piece_ptr.data;
            var idx: usize = 0;
            while (idx < data.len) : (idx += 1) {
                if (!start_set and current_line == line_num) {
                    line_start = absolute_offset;
                    start_set = true;
                }

                if (data[idx] == '\n') {
                    if (current_line == line_num and start_set) {
                        return .{ .start = line_start, .end = absolute_offset };
                    }
                    current_line += 1;
                    absolute_offset += 1;
                    continue;
                }

                absolute_offset += 1;
            }
        }

        if (!start_set) {
            if (current_line == line_num and line_num != 0) {
                line_start = absolute_offset;
                start_set = true;
            } else if (line_num > current_line) {
                return Error.OutOfBounds;
            }
        }

        if (start_set and current_line >= line_num) {
            return .{ .start = line_start, .end = absolute_offset };
        }

        if (line_num == 0 and self.length == 0) {
            return .{ .start = 0, .end = 0 };
        }

        return Error.OutOfBounds;
    }

    pub fn copyRangeAlloc(self: *const Rope, allocator: std.mem.Allocator, range: Range) Error![]u8 {
        if (range.start > range.end or range.end > self.length) return Error.OutOfBounds;
        const total_len = range.len();
        if (total_len == 0) return allocator.alloc(u8, 0);

        var result = try allocator.alloc(u8, total_len);
        errdefer allocator.free(result);

        var written: usize = 0;
        var absolute_offset: usize = 0;

        for (self.pieces.items) |piece_ptr| {
            const data = piece_ptr.data;
            const piece_len = data.len;
            const piece_start = absolute_offset;
            const piece_end = piece_start + piece_len;

            if (piece_end <= range.start) {
                absolute_offset = piece_end;
                continue;
            }

            if (piece_start >= range.end) break;

            const local_start = if (range.start > piece_start) range.start - piece_start else 0;
            const local_end = if (range.end < piece_end) range.end - piece_start else piece_len;

            const segment = data[local_start..local_end];
            if (segment.len > 0) {
                @memcpy(result[written .. written + segment.len], segment);
                written += segment.len;
            }

            absolute_offset = piece_end;
            if (written == total_len) break;
        }

        return result;
    }

    pub fn lineSliceAlloc(self: *const Rope, allocator: std.mem.Allocator, line_num: usize) Error![]u8 {
        const range = try self.lineRange(line_num);
        if (range.len() == 0) {
            return allocator.alloc(u8, 0);
        }
        return try self.copyRangeAlloc(allocator, range);
    }

    pub fn lineColumnAtOffset(self: *const Rope, offset: usize) Error!struct { line: usize, column: usize } {
        if (offset > self.length) return Error.OutOfBounds;

        var line: usize = 0;
        var column: usize = 0;
        var processed: usize = 0;

        for (self.pieces.items) |piece_ptr| {
            const data = piece_ptr.data;
            var idx: usize = 0;
            while (idx < data.len and processed < offset) : (idx += 1) {
                const byte = data[idx];
                if (byte == '\n') {
                    line += 1;
                    column = 0;
                } else {
                    column += 1;
                }
                processed += 1;
                if (processed == offset) break;
            }
            if (processed == offset) break;
        }

        return .{ .line = line, .column = column };
    }

    pub fn snapshot(self: *Rope) !Snapshot {
        var arena_alloc = self.arena.allocator();
        const copy = try arena_alloc.alloc(*Piece, self.pieces.items.len);
        @memcpy(copy, self.pieces.items[0..self.pieces.items.len]);
        return Snapshot{ .nodes = copy, .length = self.length };
    }

    pub fn restore(self: *Rope, state: Snapshot) !void {
        self.pieces.clearRetainingCapacity();
        try self.pieces.ensureTotalCapacity(self.allocator, state.nodes.len);
        self.pieces.appendSliceAssumeCapacity(state.nodes);
        self.length = state.length;
        // Invalidate line count cache on restore
        self.cached_line_count = null;
    }

    fn createPieceCopy(self: *Rope, data: []const u8) !*Piece {
        var arena_alloc = self.arena.allocator();
        const storage = try arena_alloc.alloc(u8, data.len);
        @memcpy(storage, data);
        return try self.createPieceView(storage);
    }

    fn createPieceView(self: *Rope, data: []const u8) !*Piece {
        var arena_alloc = self.arena.allocator();
        const node = try arena_alloc.create(Piece);
        node.* = .{ .data = data };
        return node;
    }

    fn ensureCut(self: *Rope, pos: usize) Error!usize {
        if (pos > self.length) return Error.OutOfBounds;
        if (self.pieces.items.len == 0) {
            return if (pos == 0) 0 else Error.OutOfBounds;
        }
        if (pos == self.length) return self.pieces.items.len;

        var running: usize = 0;
        var i: usize = 0;
        while (i < self.pieces.items.len) : (i += 1) {
            const piece_ptr = self.pieces.items[i];
            const size = piece_ptr.len();
            if (pos == running) return i;
            if (pos < running + size) {
                const offset = pos - running;
                if (offset == 0) return i;
                if (offset == size) return i + 1;
                try self.splitPiece(i, offset);
                return i + 1;
            }
            running += size;
        }
        return Error.OutOfBounds;
    }

    fn splitPiece(self: *Rope, index: usize, offset: usize) !void {
        const piece_ptr = self.pieces.items[index];
        const piece_len = piece_ptr.len();
        if (offset == 0 or offset >= piece_len) return;

        const original = piece_ptr.data;
        // Create two new pieces instead of mutating (preserves snapshots!)
        const prefix_piece = try self.createPieceView(original[0..offset]);
        const suffix_piece = try self.createPieceView(original[offset..]);

        // Replace original with prefix, add suffix after
        self.pieces.items[index] = prefix_piece;
        try self.pieces.insert(self.allocator, index + 1, suffix_piece);
    }
};

test "rope insert and slice" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
    try rope.insert(5, " world");

    const slice_all = try rope.slice(.{ .start = 0, .end = rope.len() });
    try std.testing.expectEqualStrings("hello world", slice_all);

    const slice_part = try rope.slice(.{ .start = 6, .end = 11 });
    try std.testing.expectEqualStrings("world", slice_part);
}

test "rope delete middle" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "abcdef");
    try rope.delete(2, 2);

    const view = try rope.slice(.{ .start = 0, .end = rope.len() });
    try std.testing.expectEqualStrings("abef", view);
}

test "rope snapshot and restore" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "grim");
    const snap = try rope.snapshot();

    try rope.insert(4, " reaper");
    try rope.delete(0, 2);

    const mutated = try rope.slice(.{ .start = 0, .end = rope.len() });
    try std.testing.expectEqualStrings("im reaper", mutated);

    try rope.restore(snap);
    const restored = try rope.slice(.{ .start = 0, .end = rope.len() });
    try std.testing.expectEqualStrings("grim", restored);
}

test "rope line helpers" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "first\nsecond line\nthird");

    const range_second = try rope.lineRange(1);
    try std.testing.expectEqual(@as(usize, "first\n".len), range_second.start);
    try std.testing.expectEqual(@as(usize, "first\nsecond line".len), range_second.end);

    const second_line = try rope.lineSliceAlloc(allocator, 1);
    defer allocator.free(second_line);
    try std.testing.expectEqualStrings("second line", second_line);

    const third_line = try rope.lineSliceAlloc(allocator, 2);
    defer allocator.free(third_line);
    try std.testing.expectEqualStrings("third", third_line);

    try std.testing.expectError(Rope.Error.OutOfBounds, rope.lineRange(3));

    const offset = "first\nsecond".len;
    const lc = try rope.lineColumnAtOffset(offset);
    try std.testing.expectEqual(@as(usize, 1), lc.line);
    try std.testing.expectEqual(@as(usize, "second".len), lc.column);
}

test "rope zero-copy iterator" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    // Create rope with multiple pieces
    try rope.insert(0, "hello");
    try rope.insert(5, " ");
    try rope.insert(6, "world");
    try rope.insert(11, "!");

    // Iterate over all segments (zero-copy)
    var iter = rope.iterator(.{ .start = 0, .end = rope.len() });
    var total_len: usize = 0;
    var segment_count: usize = 0;

    while (iter.next()) |segment| {
        total_len += segment.len;
        segment_count += 1;
    }

    try std.testing.expectEqual(@as(usize, "hello world!".len), total_len);
    try std.testing.expectEqual(@as(usize, 4), segment_count); // 4 pieces

    // Iterate over partial range
    var iter_part = rope.iterator(.{ .start = 6, .end = 11 });
    var part_data: [5]u8 = undefined;
    var write_pos: usize = 0;

    while (iter_part.next()) |segment| {
        @memcpy(part_data[write_pos .. write_pos + segment.len], segment);
        write_pos += segment.len;
    }

    try std.testing.expectEqualStrings("world", part_data[0..write_pos]);
}

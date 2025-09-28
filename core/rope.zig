const std = @import("std");

/// Check if position is at a valid UTF-8 boundary
fn isUtf8Boundary(data: []const u8, pos: usize) bool {
    if (pos == 0 or pos >= data.len) return true;
    // UTF-8 continuation bytes start with 10xxxxxx
    return (data[pos] & 0xC0) != 0x80;
}

/// Find the nearest UTF-8 boundary at or before pos
fn findUtf8BoundaryBefore(data: []const u8, pos: usize) usize {
    if (pos == 0 or pos >= data.len) return pos;
    var i = pos;
    while (i > 0 and !isUtf8Boundary(data, i)) {
        i -= 1;
    }
    return i;
}

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        return self.end - self.start;
    }
};

const EmptySlice = [_]u8{};

pub const Rope = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    pieces: std.ArrayListUnmanaged(*Piece),
    length: usize,

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
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator) !Rope {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        return Rope{
            .allocator = allocator,
            .arena = arena,
            .pieces = .{},
            .length = 0,
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

    pub fn insert(self: *Rope, pos: usize, bytes: []const u8) Error!void {
        if (pos > self.length) return Error.OutOfBounds;
        if (bytes.len == 0) return;

        const piece_ptr = try self.createPieceCopy(bytes);
        const index = try self.ensureCut(pos);
        try self.pieces.insert(self.allocator, index, piece_ptr);
        self.length += bytes.len;
    }

    pub fn delete(self: *Rope, start: usize, len_to_remove: usize) Error!void {
        if (len_to_remove == 0) return;
        if (start > self.length) return Error.OutOfBounds;
        if (start + len_to_remove > self.length) return Error.OutOfBounds;

        const begin_index = try self.ensureCut(start);
        const end_index = try self.ensureCut(start + len_to_remove);

        var i = end_index;
        while (i > begin_index) {
            _ = self.pieces.orderedRemove(begin_index);
            i -= 1;
        }

        self.length -= len_to_remove;
    }

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

            if (first and take == total_len) {
                return segment;
            }

            if (buffer == null) {
                buffer = try self.allocator.alloc(u8, total_len);
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

    pub fn snapshot(self: *Rope) !Snapshot {
        var arena_alloc = self.arena.allocator();
        const copy = try arena_alloc.alloc(*Piece, self.pieces.len);
        @memcpy(copy, self.pieces.items[0..self.pieces.len]);
        return Snapshot{ .nodes = copy, .length = self.length };
    }

    pub fn restore(self: *Rope, state: Snapshot) !void {
        self.pieces.deinit(self.allocator);
        self.pieces = .{};
        try self.pieces.ensureTotalCapacity(self.allocator, state.nodes.len);
        @memcpy(self.pieces.items[0..state.nodes.len], state.nodes);
        self.pieces.len = state.nodes.len;
        self.length = state.length;
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
        const suffix_slice = original[offset..];
        piece_ptr.*.data = original[0..offset];
        const suffix_piece = try self.createPieceView(suffix_slice);
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

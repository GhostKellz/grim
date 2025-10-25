//! LSP completion menu

const std = @import("std");

pub const CompletionKind = enum(u8) {
    text = 1,
    method = 2,
    function = 3,
    constructor = 4,
    field = 5,
    variable = 6,
    class = 7,
    interface = 8,
    module = 9,
    keyword = 14,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionKind,
    detail: ?[]const u8 = null,
    insert_text: []const u8,
};

pub const CompletionMenu = struct {
    items: std.ArrayList(CompletionItem),
    filtered: std.ArrayList(usize), // Indices of filtered items
    selected: usize = 0,
    visible: bool = false,
    filter_prefix: []const u8 = "",
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CompletionMenu {
        return .{
            .items = std.ArrayList(CompletionItem){},
            .filtered = std.ArrayList(usize){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CompletionMenu) void {
        for (self.items.items) |item| {
            self.allocator.free(item.label);
            self.allocator.free(item.insert_text);
            if (item.detail) |d| self.allocator.free(d);
        }
        self.items.deinit(self.allocator);
        self.filtered.deinit(self.allocator);
        if (self.filter_prefix.len > 0) self.allocator.free(self.filter_prefix);
    }

    pub fn setItems(self: *CompletionMenu, items: []const CompletionItem) !void {
        self.clear();
        for (items) |item| {
            try self.items.append(.{
                .label = try self.allocator.dupe(u8, item.label),
                .kind = item.kind,
                .detail = if (item.detail) |d| try self.allocator.dupe(u8, d) else null,
                .insert_text = try self.allocator.dupe(u8, item.insert_text),
            });
        }
        try self.rebuildFiltered();
    }

    pub fn show(self: *CompletionMenu) void {
        self.visible = true;
    }

    pub fn hide(self: *CompletionMenu) void {
        self.visible = false;
    }

    pub fn moveUp(self: *CompletionMenu) void {
        if (self.filtered.items.len == 0) return;
        if (self.selected > 0) self.selected -= 1;
    }

    pub fn moveDown(self: *CompletionMenu) void {
        if (self.filtered.items.len == 0) return;
        if (self.selected + 1 < self.filtered.items.len) self.selected += 1;
    }

    pub fn getSelected(self: *const CompletionMenu) ?CompletionItem {
        if (self.filtered.items.len == 0) return null;
        const idx = self.filtered.items[self.selected];
        return self.items.items[idx];
    }

    pub fn render(self: *const CompletionMenu, file: anytype, x: u32, y: u32, max_height: u32) !void {
        if (!self.visible or self.filtered.items.len == 0) return;

        const visible_items = @min(self.filtered.items.len, max_height);

        for (0..visible_items) |i| {
            const idx = self.filtered.items[i];
            const item = self.items.items[idx];

            var buf: [256]u8 = undefined;
            const pos_seq = try std.fmt.bufPrint(&buf, "\x1b[{};{}H", .{ y + i, x });
            try file.writeAll(pos_seq);

            if (i == self.selected) {
                try file.writeAll("\x1b[7m");
            }

            const icon = switch (item.kind) {
                .function, .method => "ƒ",
                .variable, .field => "v",
                .class => "C",
                .keyword => "k",
                else => " ",
            };

            const text = try std.fmt.bufPrint(&buf, " {s} {s}", .{ icon, item.label });
            try file.writeAll(text);

            if (item.detail) |detail| {
                if (detail.len < 20) {
                    const detail_text = try std.fmt.bufPrint(&buf, " \x1b[2m{s}\x1b[0m", .{detail});
                    try file.writeAll(detail_text);
                }
            }

            if (i == self.selected) {
                try file.writeAll("\x1b[0m");
            }
        }
    }

    fn clear(self: *CompletionMenu) void {
        for (self.items.items) |item| {
            self.allocator.free(item.label);
            self.allocator.free(item.insert_text);
            if (item.detail) |d| self.allocator.free(d);
        }
        self.items.clearRetainingCapacity();
        self.filtered.clearRetainingCapacity();
    }

    fn rebuildFiltered(self: *CompletionMenu) !void {
        self.filtered.clearRetainingCapacity();
        for (self.items.items, 0..) |item, i| {
            if (self.filter_prefix.len == 0 or std.mem.startsWith(u8, item.label, self.filter_prefix)) {
                try self.filtered.append(i);
            }
        }
        self.selected = 0;
    }
};

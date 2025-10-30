//! LSP completion menu with documentation preview

const std = @import("std");
const phantom = @import("phantom");
const lsp = @import("lsp");

pub const CompletionKind = enum {
    text,
    method,
    function,
    constructor,
    field,
    variable,
    class,
    interface,
    module,
    property,
    unit,
    value,
    enum_value,
    keyword,
    snippet,
    color,
    file,
    reference,
    folder,
    enum_member,
    constant,
    struct_type,
    event,
    operator,
    type_parameter,

    pub fn icon(self: CompletionKind) []const u8 {
        return switch (self) {
            .text => "󰉿",
            .method => "󰊕",
            .function => "󰊕",
            .constructor => "",
            .field => "󰜢",
            .variable => "󰀫",
            .class => "󰠱",
            .interface => "",
            .module => "",
            .property => "󰜢",
            .unit => "󰑭",
            .value => "󰎠",
            .enum_value => "",
            .keyword => "󰌋",
            .snippet => "",
            .color => "󰏘",
            .file => "󰈙",
            .reference => "󰈇",
            .folder => "󰉋",
            .enum_member => "",
            .constant => "󰏿",
            .struct_type => "󰙅",
            .event => "",
            .operator => "󰆕",
            .type_parameter => "󰊄",
        };
    }
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionKind,
    detail: ?[]const u8,
    documentation: ?[]const u8,
    insert_text: []const u8,
    sort_text: ?[]const u8,
    filter_text: ?[]const u8,
};

pub const CompletionMenu = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(CompletionItem),
    filtered_indices: std.ArrayList(usize),
    selected_index: usize,
    filter_query: std.ArrayList(u8),
    visible: bool,
    max_visible_items: usize,
    scroll_offset: usize,

    pub fn init(allocator: std.mem.Allocator) !*CompletionMenu {
        const self = try allocator.create(CompletionMenu);
        self.* = .{
            .allocator = allocator,
            .items = std.ArrayList(CompletionItem){},
            .filtered_indices = std.ArrayList(usize){},
            .selected_index = 0,
            .filter_query = std.ArrayList(u8){},
            .visible = false,
            .max_visible_items = 10,
            .scroll_offset = 0,
        };
        return self;
    }

    pub fn deinit(self: *CompletionMenu) void {
        self.items.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        self.filter_query.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn show(self: *CompletionMenu, items: []const CompletionItem) !void {
        self.items.clearRetainingCapacity();
        for (items) |item| {
            try self.items.append(self.allocator, item);
        }
        try self.updateFiltered();
        self.visible = true;
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    pub fn hide(self: *CompletionMenu) void {
        self.visible = false;
        self.items.clearRetainingCapacity();
        self.filtered_indices.clearRetainingCapacity();
        self.filter_query.clearRetainingCapacity();
    }

    pub fn setFilter(self: *CompletionMenu, query: []const u8) !void {
        self.filter_query.clearRetainingCapacity();
        try self.filter_query.appendSlice(self.allocator, query);
        try self.updateFiltered();
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    fn updateFiltered(self: *CompletionMenu) !void {
        self.filtered_indices.clearRetainingCapacity();
        
        if (self.filter_query.items.len == 0) {
            for (0..self.items.items.len) |i| {
                try self.filtered_indices.append(self.allocator, i);
            }
            return;
        }

        for (self.items.items, 0..) |item, i| {
            const text = item.filter_text orelse item.label;
            if (self.fuzzyMatch(text, self.filter_query.items)) {
                try self.filtered_indices.append(self.allocator, i);
            }
        }
    }

    fn fuzzyMatch(self: *CompletionMenu, text: []const u8, query: []const u8) bool {
        _ = self;
        if (query.len == 0) return true;
        if (text.len == 0) return false;

        var text_idx: usize = 0;
        var query_idx: usize = 0;

        while (text_idx < text.len and query_idx < query.len) {
            if (std.ascii.toLower(text[text_idx]) == std.ascii.toLower(query[query_idx])) {
                query_idx += 1;
            }
            text_idx += 1;
        }

        return query_idx == query.len;
    }

    pub fn selectNext(self: *CompletionMenu) void {
        if (self.filtered_indices.items.len == 0) return;
        
        self.selected_index = (self.selected_index + 1) % self.filtered_indices.items.len;
        
        // Update scroll offset
        if (self.selected_index >= self.scroll_offset + self.max_visible_items) {
            self.scroll_offset = self.selected_index - self.max_visible_items + 1;
        } else if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        }
    }

    pub fn selectPrev(self: *CompletionMenu) void {
        if (self.filtered_indices.items.len == 0) return;
        
        if (self.selected_index == 0) {
            self.selected_index = self.filtered_indices.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
        
        // Update scroll offset
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + self.max_visible_items) {
            self.scroll_offset = self.selected_index - self.max_visible_items + 1;
        }
    }

    pub fn getSelected(self: *CompletionMenu) ?CompletionItem {
        if (self.filtered_indices.items.len == 0) return null;
        const idx = self.filtered_indices.items[self.selected_index];
        return self.items.items[idx];
    }

    pub fn render(self: *CompletionMenu, buffer: anytype, area: phantom.Rect) !void {
        if (!self.visible or self.filtered_indices.items.len == 0) return;

        const menu_width = @min(50, area.width);
        const menu_height = @min(self.max_visible_items + 2, area.height);
        
        // Calculate menu position (center of screen)
        const menu_x = area.x + (area.width - menu_width) / 2;
        const menu_y = area.y + (area.height - menu_height) / 2;
        
        const menu_area = phantom.Rect{
            .x = menu_x,
            .y = menu_y,
            .width = menu_width,
            .height = menu_height,
        };

        // Draw border
        try self.renderBorder(buffer, menu_area);

        // Draw items
        const visible_end = @min(
            self.scroll_offset + self.max_visible_items,
            self.filtered_indices.items.len,
        );

        for (self.scroll_offset..visible_end) |i| {
            const item_idx = self.filtered_indices.items[i];
            const item = self.items.items[item_idx];
            const is_selected = (i == self.selected_index);
            
            const item_y = menu_y + 1 + @as(u16, @intCast(i - self.scroll_offset));
            try self.renderItem(buffer, item, menu_x + 2, item_y, menu_width - 4, is_selected);
        }

        // Draw scroll indicator
        if (self.filtered_indices.items.len > self.max_visible_items) {
            try self.renderScrollbar(buffer, menu_area, self.filtered_indices.items.len);
        }
    }

    fn renderBorder(self: *CompletionMenu, buffer: anytype, area: phantom.Rect) !void {
        _ = self;
        
        // Top border
        try buffer.setCursor(area.x, area.y);
        try buffer.write("┌");
        for (0..area.width - 2) |_| {
            try buffer.write("─");
        }
        try buffer.write("┐");

        // Side borders
        for (1..area.height - 1) |y| {
            try buffer.setCursor(area.x, area.y + @as(u16, @intCast(y)));
            try buffer.write("│");
            try buffer.setCursor(area.x + area.width - 1, area.y + @as(u16, @intCast(y)));
            try buffer.write("│");
        }

        // Bottom border
        try buffer.setCursor(area.x, area.y + area.height - 1);
        try buffer.write("└");
        for (0..area.width - 2) |_| {
            try buffer.write("─");
        }
        try buffer.write("┘");
    }

    fn renderItem(
        self: *CompletionMenu,
        buffer: anytype,
        item: CompletionItem,
        x: u16,
        y: u16,
        width: u16,
        selected: bool,
    ) !void {
        _ = self;
        
        try buffer.setCursor(x, y);
        
        if (selected) {
            try buffer.setStyle(.{ .bg = .blue, .fg = .white });
        }

        // Render icon
        const icon_str = item.kind.icon();
        try buffer.write(icon_str);
        try buffer.write(" ");

        // Render label
        const max_label_width = width - 10;
        const label = if (item.label.len > max_label_width)
            item.label[0..max_label_width]
        else
            item.label;
        try buffer.write(label);

        // Render detail (right-aligned)
        if (item.detail) |detail| {
            const detail_width = @min(detail.len, 15);
            const detail_x = x + width - @as(u16, @intCast(detail_width));
            try buffer.setCursor(detail_x, y);
            try buffer.write(detail[0..detail_width]);
        }

        if (selected) {
            try buffer.resetStyle();
        }
    }

    fn renderScrollbar(
        self: *CompletionMenu,
        buffer: anytype,
        area: phantom.Rect,
        total_items: usize,
    ) !void {
        _ = self;
        _ = buffer;
        _ = area;
        _ = total_items;
        // TODO: Implement scrollbar rendering
    }
};

test "CompletionMenu init and deinit" {
    const allocator = std.testing.allocator;
    const menu = try CompletionMenu.init(allocator);
    defer menu.deinit();
    
    try std.testing.expect(!menu.visible);
    try std.testing.expectEqual(@as(usize, 0), menu.items.items.len);
}

test "CompletionMenu fuzzy matching" {
    const allocator = std.testing.allocator;
    const menu = try CompletionMenu.init(allocator);
    defer menu.deinit();
    
    try std.testing.expect(menu.fuzzyMatch("testFunction", "tf"));
    try std.testing.expect(menu.fuzzyMatch("testFunction", "test"));
    try std.testing.expect(menu.fuzzyMatch("testFunction", "Func"));
    try std.testing.expect(!menu.fuzzyMatch("testFunction", "xyz"));
}

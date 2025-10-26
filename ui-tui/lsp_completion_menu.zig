const std = @import("std");
const phantom = @import("phantom");
const Buffer = @import("phantom").Terminal.buffer; // Get Buffer from Terminal
const editor_lsp = @import("editor_lsp.zig");

const Completion = editor_lsp.Completion;
const CompletionKind = editor_lsp.Completion.CompletionKind;

/// LSP completion item kinds mapped to Nerd Font icons
const CompletionIcon = enum {
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
    enum_member,
    keyword,
    snippet,
    color,
    file,
    reference,
    folder,
    enum_type,
    constant,
    struct_type,
    event,
    operator,
    type_parameter,

    pub fn toIcon(self: CompletionIcon) []const u8 {
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
            .enum_member => "",
            .keyword => "󰌋",
            .snippet => "",
            .color => "󰏘",
            .file => "󰈙",
            .reference => "󰈇",
            .folder => "󰉋",
            .enum_type => "",
            .constant => "󰏿",
            .struct_type => "󰙅",
            .event => "",
            .operator => "󰆕",
            .type_parameter => "󰊄",
        };
    }

    pub fn fromCompletionKind(kind: CompletionKind) CompletionIcon {
        return switch (kind) {
            .text => .text,
            .method => .method,
            .function => .function,
            .constructor => .constructor,
            .field => .field,
            .variable => .variable,
            .class => .class,
            .interface => .interface,
            .module => .module,
            .property => .property,
            .unit => .unit,
            .value => .value,
            .enum_member => .enum_member,
            .keyword => .keyword,
            .snippet => .snippet,
            .color => .color,
            .file => .file,
            .reference => .reference,
            .folder => .folder,
            .enum_type => .enum_type,
            .constant => .constant,
            .struct_type => .struct_type,
            .event => .event,
            .operator => .operator,
            .type_parameter => .type_parameter,
        };
    }
};

pub const LSPCompletionMenu = struct {
    list_view: *phantom.widgets.ListView,
    border: *phantom.widgets.Border,
    allocator: std.mem.Allocator,
    visible: bool,

    pub fn init(allocator: std.mem.Allocator) !*LSPCompletionMenu {
        const self = try allocator.create(LSPCompletionMenu);

        // Create ListView
        const list_view = try phantom.widgets.ListView.init(allocator);

        // Configure styles
        list_view.selected_style = phantom.Style.default()
            .withFg(phantom.Color.white)
            .withBg(phantom.Color.blue)
            .withBold();

        list_view.hovered_style = phantom.Style.default()
            .withFg(phantom.Color.bright_cyan)
            .withBg(phantom.Color.bright_black);

        list_view.icon_style = phantom.Style.default()
            .withFg(phantom.Color.bright_yellow);

        list_view.secondary_style = phantom.Style.default()
            .withFg(phantom.Color.bright_black);

        // Create border
        const border = try phantom.widgets.Border.init(allocator);
        border.setBorderStyle(.rounded);
        try border.setTitle(" Completions ");
        border.setChild(&list_view.widget);
        border.border_color = phantom.Style.default().withFg(phantom.Color.bright_cyan);
        border.title_style = phantom.Style.default().withFg(phantom.Color.bright_yellow).withBold();

        self.* = .{
            .list_view = list_view,
            .border = border,
            .allocator = allocator,
            .visible = false,
        };

        return self;
    }

    pub fn deinit(self: *LSPCompletionMenu) void {
        self.border.widget.vtable.deinit(&self.border.widget);
        self.list_view.widget.vtable.deinit(&self.list_view.widget);
        self.allocator.destroy(self);
    }

    pub fn setCompletions(self: *LSPCompletionMenu, items: []const Completion) !void {
        self.list_view.clear();

        for (items) |item| {
            const kind = CompletionIcon.fromCompletionKind(item.kind);
            const icon_str = kind.toIcon();

            // Convert icon string to u21 codepoint
            const icon_codepoint = blk: {
                var view = std.unicode.Utf8View.init(icon_str) catch break :blk @as(u21, ' ');
                var iter = view.iterator();
                if (iter.nextCodepoint()) |cp| {
                    break :blk cp;
                }
                break :blk @as(u21, ' ');
            };

            const list_item = phantom.widgets.ListViewItem{
                .text = try self.allocator.dupe(u8, item.label),
                .secondary_text = if (item.detail) |detail|
                    try self.allocator.dupe(u8, detail)
                else
                    null,
                .icon = icon_codepoint,
            };

            try self.list_view.addItem(list_item);
        }

        // Update border title with count
        const title = try std.fmt.allocPrint(
            self.allocator,
            " Completions ({d}) ",
            .{items.len},
        );
        defer self.allocator.free(title);
        self.border.setTitle(title);

        self.visible = items.len > 0;
    }

    pub fn selectNext(self: *LSPCompletionMenu) void {
        self.list_view.selectNext();
    }

    pub fn selectPrev(self: *LSPCompletionMenu) void {
        self.list_view.selectPrev();
    }

    pub fn getSelectedIndex(self: *LSPCompletionMenu) ?usize {
        return self.list_view.selected_index;
    }

    pub fn getSelectedItem(self: *LSPCompletionMenu) ?*const phantom.widgets.ListViewItem {
        const idx = self.getSelectedIndex() orelse return null;
        if (idx >= self.list_view.items.items.len) return null;
        return &self.list_view.items.items[idx];
    }

    pub fn hide(self: *LSPCompletionMenu) void {
        self.visible = false;
    }

    pub fn show(self: *LSPCompletionMenu) void {
        if (self.list_view.items.items.len > 0) {
            self.visible = true;
        }
    }

    pub fn handleKeyEvent(self: *LSPCompletionMenu, key: phantom.Key) bool {
        if (!self.visible) return false;

        return switch (key) {
            .down, .char => |c| if (c == 'j') {
                self.selectNext();
                return true;
            } else false,
            .up => {
                self.selectPrev();
                return true;
            },
            .char => |c| if (c == 'k') {
                self.selectPrev();
                return true;
            } else false,
            .page_down => {
                // TODO: Jump down by viewport height
                var i: usize = 0;
                while (i < self.list_view.viewport_height) : (i += 1) {
                    self.selectNext();
                }
                return true;
            },
            .page_up => {
                var i: usize = 0;
                while (i < self.list_view.viewport_height) : (i += 1) {
                    self.selectPrev();
                }
                return true;
            },
            .home => {
                self.list_view.selected_index = 0;
                self.list_view.ensureSelectedVisible();
                return true;
            },
            .end => {
                if (self.list_view.items.items.len > 0) {
                    self.list_view.selected_index = self.list_view.items.items.len - 1;
                    self.list_view.ensureSelectedVisible();
                }
                return true;
            },
            else => false,
        };
    }

    pub fn render(self: *LSPCompletionMenu, buffer: *phantom.Buffer, area: phantom.Rect) !void {
        if (!self.visible) return;
        try self.border.widget.vtable.render(&self.border.widget, buffer, area);
    }
};

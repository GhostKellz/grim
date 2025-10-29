//! Search and replace panel for project-wide operations

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const project_search = @import("../core/project_search.zig");

pub const SearchReplacePanel = struct {
    allocator: std.mem.Allocator,
    search: project_search.ProjectSearch,
    selected_index: usize,
    visible: bool,

    pub fn init(allocator: std.mem.Allocator) SearchReplacePanel {
        return .{
            .allocator = allocator,
            .search = project_search.ProjectSearch.init(allocator),
            .selected_index = 0,
            .visible = false,
        };
    }

    pub fn deinit(self: *SearchReplacePanel) void {
        self.search.deinit();
    }

    pub fn show(self: *SearchReplacePanel) void {
        self.visible = true;
    }

    pub fn hide(self: *SearchReplacePanel) void {
        self.visible = false;
    }

    pub fn searchProject(self: *SearchReplacePanel, pattern: []const u8) !void {
        try self.search.search(pattern, null);
        self.selected_index = 0;
        self.visible = true;
    }

    pub fn replaceAll(self: *SearchReplacePanel, pattern: []const u8, replacement: []const u8) !usize {
        return try self.search.replace(pattern, replacement, null);
    }

    pub fn render(self: *SearchReplacePanel, buffer: anytype, area: phantom.Rect) void {
        if (!self.visible) return;

        // Draw border
        const border_style = phantom.Style.default().withFg(phantom.Color.cyan);
        buffer.drawRect(area, border_style);

        // Draw title
        buffer.writeText(area.x + 2, area.y, " Project Search Results ", border_style);

        // Draw results
        var y: u16 = area.y + 1;
        const max_y = area.y + area.height - 1;

        for (self.search.results.items, 0..) |*result, i| {
            if (y >= max_y) break;

            const selected = (i == self.selected_index);
            const style = if (selected)
                phantom.Style.default().withBg(phantom.Color.blue).withFg(phantom.Color.white)
            else
                phantom.Style.default();

            // Format: file:line:col: matched_line
            var line_buf: [256]u8 = undefined;
            const line_text = std.fmt.bufPrint(
                &line_buf,
                "{s}:{d}:{d}: {s}",
                .{ result.filepath, result.line_number, result.column, result.matched_line },
            ) catch continue;

            const display_text = if (line_text.len > area.width - 2)
                line_text[0 .. area.width - 2]
            else
                line_text;

            buffer.writeText(area.x + 1, y, display_text, style);
            y += 1;
        }

        // Show count
        if (self.search.results.items.len > 0) {
            var count_buf: [64]u8 = undefined;
            const count_text = std.fmt.bufPrint(
                &count_buf,
                " {d} matches ",
                .{self.search.results.items.len},
            ) catch return;
            buffer.writeText(area.x + 2, max_y, count_text, border_style);
        }
    }

    pub fn selectNext(self: *SearchReplacePanel) void {
        if (self.search.results.items.len == 0) return;
        self.selected_index = (self.selected_index + 1) % self.search.results.items.len;
    }

    pub fn selectPrev(self: *SearchReplacePanel) void {
        if (self.search.results.items.len == 0) return;
        if (self.selected_index == 0) {
            self.selected_index = self.search.results.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
    }

    pub fn getSelectedResult(self: *SearchReplacePanel) ?*project_search.SearchResult {
        if (self.search.results.items.len == 0) return null;
        if (self.selected_index >= self.search.results.items.len) return null;
        return &self.search.results.items[self.selected_index];
    }
};

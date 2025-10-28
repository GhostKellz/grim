//! Tab Bar Widget for Grim
//! Shows all open tabs with active tab highlighted

const std = @import("std");
const phantom = @import("phantom");
const grim_layout = @import("grim_layout.zig");

pub const TabBar = struct {
    layout_manager: *grim_layout.LayoutManager,

    pub fn init(layout_manager: *grim_layout.LayoutManager) TabBar {
        return .{
            .layout_manager = layout_manager,
        };
    }

    pub fn render(self: *TabBar, buffer: anytype, area: phantom.Rect) void {
        if (area.height == 0 or area.width == 0) return;

        // Clear tab bar area
        const bg_style = phantom.Style.default().withBg(phantom.Color.black);
        for (0..area.width) |x| {
            buffer.setCell(@intCast(area.x + x), area.y, .{ .char = ' ', .style = bg_style });
        }

        var x_pos: usize = 1; // Start with padding

        // Render each tab
        for (self.layout_manager.tabs.items, 0..) |tab, i| {
            const is_active = i == self.layout_manager.active_tab_index;

            // Get tab name (filename of active editor or "Untitled")
            const tab_name = blk: {
                const editor = tab.active_editor;
                if (editor.editor.current_filename) |filename| {
                    // Extract just the filename from path
                    if (std.mem.lastIndexOfScalar(u8, filename, '/')) |last_slash| {
                        break :blk filename[last_slash + 1 ..];
                    }
                    break :blk filename;
                } else {
                    break :blk "Untitled";
                }
            };

            // Check if modified
            const is_modified = tab.active_editor.is_modified;

            // Format: [1:filename*] or 1:filename
            var buf: [256]u8 = undefined;
            const tab_str = if (is_modified)
                std.fmt.bufPrint(&buf, "{d}:{s}*", .{ i + 1, tab_name }) catch "[?]"
            else
                std.fmt.bufPrint(&buf, "{d}:{s}", .{ i + 1, tab_name }) catch "[?]";

            // Calculate tab width (text + brackets/padding)
            const tab_width = tab_str.len + 2; // [] brackets

            // Check if we have space
            if (x_pos + tab_width + 2 > area.width) break;

            // Render tab with active/inactive styling
            const style = if (is_active)
                phantom.Style.default()
                .withFg(phantom.Color.black)
                .withBg(phantom.Color.cyan) // Cyan for active
                .withBold()
            else
                phantom.Style.default()
                .withFg(phantom.Color.white)
                .withBg(phantom.Color.bright_black); // Gray for inactive

            // Opening bracket
            buffer.setCell(@intCast(area.x + x_pos), area.y, .{ .char = '[', .style = style });
            x_pos += 1;

            // Tab text
            for (tab_str) |ch| {
                if (x_pos >= area.width) break;
                buffer.setCell(@intCast(area.x + x_pos), area.y, .{ .char = @intCast(ch), .style = style });
                x_pos += 1;
            }

            // Closing bracket
            if (x_pos < area.width) {
                buffer.setCell(@intCast(area.x + x_pos), area.y, .{ .char = ']', .style = style });
                x_pos += 1;
            }

            // Spacing
            x_pos += 1;
        }

        // Show total tabs if we ran out of space
        if (self.layout_manager.tabs.items.len > 3 and x_pos < area.width - 10) {
            const total_str = std.fmt.allocPrint(
                std.heap.page_allocator,
                " ({d} tabs)",
                .{self.layout_manager.tabs.items.len},
            ) catch return;
            defer std.heap.page_allocator.free(total_str);

            const info_style = phantom.Style.default().withFg(phantom.Color.bright_black);
            for (total_str) |ch| {
                if (x_pos >= area.width) break;
                buffer.setCell(@intCast(area.x + x_pos), area.y, .{ .char = @intCast(ch), .style = info_style });
                x_pos += 1;
            }
        }
    }
};

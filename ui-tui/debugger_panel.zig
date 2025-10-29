//! DAP debugger panel

const std = @import("std");
const phantom = @import("phantom");
const dap = @import("../lsp/dap_client.zig");

pub const DebuggerPanel = struct {
    allocator: std.mem.Allocator,
    dap_client: ?*dap.DAPClient,
    visible: bool,
    selected_tab: usize, // 0=stack, 1=variables, 2=breakpoints

    pub fn init(allocator: std.mem.Allocator) DebuggerPanel {
        return .{
            .allocator = allocator,
            .dap_client = null,
            .visible = false,
            .selected_tab = 0,
        };
    }

    pub fn deinit(self: *DebuggerPanel) void {
        if (self.dap_client) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
    }

    pub fn render(self: *DebuggerPanel, buffer: anytype, area: phantom.Rect) void {
        if (!self.visible) return;

        // Draw border
        const style = phantom.Style.default().withFg(phantom.Color.yellow);
        buffer.drawRect(area, style);
        buffer.writeText(area.x + 2, area.y, " Debugger ", style);

        // Draw tabs
        const tab_names = [_][]const u8{ "Stack", "Variables", "Breakpoints" };
        var x: u16 = area.x + 2;
        for (tab_names, 0..) |name, i| {
            const tab_style = if (i == self.selected_tab)
                phantom.Style.default().withBg(phantom.Color.yellow).withFg(phantom.Color.black)
            else
                style;
            buffer.writeText(x, area.y + 1, name, tab_style);
            x += @intCast(name.len + 2);
        }

        // Draw content based on selected tab
        const content_area = phantom.Rect{
            .x = area.x + 1,
            .y = area.y + 3,
            .width = area.width - 2,
            .height = area.height - 4,
        };

        switch (self.selected_tab) {
            0 => self.renderStackTrace(buffer, content_area),
            1 => self.renderVariables(buffer, content_area),
            2 => self.renderBreakpoints(buffer, content_area),
            else => {},
        }
    }

    fn renderStackTrace(self: *DebuggerPanel, buffer: anytype, area: phantom.Rect) void {
        if (self.dap_client) |client| {
            var y: u16 = area.y;
            for (client.stack_frames.items) |*frame| {
                if (y >= area.y + area.height) break;
                var buf: [256]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "{s}:{d}", .{ frame.name, frame.line }) catch continue;
                buffer.writeText(area.x, y, text, phantom.Style.default());
                y += 1;
            }
        }
    }

    fn renderVariables(self: *DebuggerPanel, buffer: anytype, area: phantom.Rect) void {
        if (self.dap_client) |client| {
            var y: u16 = area.y;
            for (client.variables.items) |*variable| {
                if (y >= area.y + area.height) break;
                var buf: [256]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "{s} = {s}", .{ variable.name, variable.value }) catch continue;
                buffer.writeText(area.x, y, text, phantom.Style.default());
                y += 1;
            }
        }
    }

    fn renderBreakpoints(self: *DebuggerPanel, buffer: anytype, area: phantom.Rect) void {
        if (self.dap_client) |client| {
            var y: u16 = area.y;
            for (client.breakpoints.items) |*bp| {
                if (y >= area.y + area.height) break;
                var buf: [256]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "{s}:{d}", .{ bp.filepath, bp.line }) catch continue;
                buffer.writeText(area.x, y, text, phantom.Style.default());
                y += 1;
            }
        }
    }
};

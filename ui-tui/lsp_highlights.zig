const std = @import("std");
const runtime = @import("runtime");
const editor_lsp = @import("editor_lsp.zig");

/// LSP Diagnostics → HighlightThemeAPI Integration
/// Bridges LSP diagnostics with grim's highlight system
pub const LSPHighlights = struct {
    allocator: std.mem.Allocator,
    highlight_api: runtime.HighlightThemeAPI,
    namespace_id: u32,

    const NAMESPACE_NAME = "lsp_diagnostics";

    pub fn init(allocator: std.mem.Allocator) !LSPHighlights {
        var highlight_api = runtime.HighlightThemeAPI.init(allocator);

        // Define LSP diagnostic highlight groups
        try setupDiagnosticHighlights(&highlight_api);

        // Create namespace for LSP diagnostics
        const ns_id = try highlight_api.createNamespace(NAMESPACE_NAME);

        return LSPHighlights{
            .allocator = allocator,
            .highlight_api = highlight_api,
            .namespace_id = ns_id,
        };
    }

    pub fn deinit(self: *LSPHighlights) void {
        self.highlight_api.deinit();
    }

    /// Apply LSP diagnostics as highlights to a buffer
    pub fn applyDiagnostics(
        self: *LSPHighlights,
        buffer_id: u32,
        diagnostics: []const editor_lsp.Diagnostic,
    ) !void {
        // Clear previous diagnostics
        try self.highlight_api.clearNamespace(NAMESPACE_NAME, buffer_id);

        // Apply each diagnostic as a highlight
        for (diagnostics) |diag| {
            const group_name = self.getHighlightGroupForSeverity(diag.severity);

            try self.highlight_api.addNamespaceHighlight(
                NAMESPACE_NAME,
                buffer_id,
                group_name,
                diag.range.start.line,
                diag.range.start.character,
                diag.range.end.character,
            );
        }
    }

    /// Render diagnostic gutter signs (error/warning icons)
    pub fn renderGutterSigns(
        self: *LSPHighlights,
        diagnostics: []const editor_lsp.Diagnostic,
    ) ![]GutterSign {
        var signs = std.ArrayList(GutterSign){};
        errdefer signs.deinit(self.allocator);

        // Group diagnostics by line (show most severe per line)
        var line_map = std.AutoHashMap(u32, editor_lsp.Diagnostic.Severity).init(self.allocator);
        defer line_map.deinit();

        for (diagnostics) |diag| {
            const line = diag.range.start.line;
            const existing = line_map.get(line);

            if (existing == null or self.isMoreSevere(diag.severity, existing.?)) {
                try line_map.put(line, diag.severity);
            }
        }

        // Convert to gutter signs
        var iter = line_map.iterator();
        while (iter.next()) |entry| {
            try signs.append(self.allocator, .{
                .line = entry.key_ptr.*,
                .icon = self.getIconForSeverity(entry.value_ptr.*),
                .highlight_group = self.getHighlightGroupForSeverity(entry.value_ptr.*),
            });
        }

        return signs.toOwnedSlice(self.allocator);
    }

    /// Get diagnostic count for status line
    pub fn getDiagnosticCount(
        self: *LSPHighlights,
        lsp: *editor_lsp.EditorLSP,
        path: []const u8,
        severity: editor_lsp.Diagnostic.Severity,
    ) usize {
        _ = self;
        const diagnostics = lsp.getDiagnostics(path) orelse return 0;

        var count: usize = 0;
        for (diagnostics) |diag| {
            if (diag.severity == severity) count += 1;
        }
        return count;
    }

    /// Format diagnostic message for display
    pub fn formatDiagnosticMessage(
        self: *LSPHighlights,
        diag: editor_lsp.Diagnostic,
    ) ![]const u8 {
        const severity_str = switch (diag.severity) {
            .error_sev => "Error",
            .warning => "Warning",
            .information => "Info",
            .hint => "Hint",
        };

        if (diag.source) |source| {
            if (diag.code) |code| {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "[{s}] {s}({s}): {s}",
                    .{ source, severity_str, code, diag.message }
                );
            }
            return try std.fmt.allocPrint(
                self.allocator,
                "[{s}] {s}: {s}",
                .{ source, severity_str, diag.message }
            );
        }

        return try std.fmt.allocPrint(
            self.allocator,
            "{s}: {s}",
            .{ severity_str, diag.message }
        );
    }

    // Private helpers

    fn getHighlightGroupForSeverity(self: *LSPHighlights, severity: editor_lsp.Diagnostic.Severity) []const u8 {
        _ = self;
        return switch (severity) {
            .error_sev => "LspError",
            .warning => "LspWarning",
            .information => "LspInfo",
            .hint => "LspHint",
        };
    }

    fn getIconForSeverity(self: *LSPHighlights, severity: editor_lsp.Diagnostic.Severity) []const u8 {
        _ = self;
        return switch (severity) {
            .error_sev => "E",  // "●" or "✗" with Nerd Fonts
            .warning => "W",    // "⚠" with Nerd Fonts
            .information => "I", // "ℹ" with Nerd Fonts
            .hint => "H",       // "💡" with Nerd Fonts
        };
    }

    fn isMoreSevere(self: *LSPHighlights, a: editor_lsp.Diagnostic.Severity, b: editor_lsp.Diagnostic.Severity) bool {
        _ = self;
        // Lower number = more severe (error=1, hint=4)
        return @intFromEnum(a) < @intFromEnum(b);
    }

    fn setupDiagnosticHighlights(api: *runtime.HighlightThemeAPI) !void {
        // Error - bold red
        const red = try runtime.HighlightThemeAPI.Color.fromHex("#fb4934");
        _ = try api.defineHighlight("LspError", red, null, null, .{ .bold = true, .undercurl = true });

        // Warning - bold yellow
        const yellow = try runtime.HighlightThemeAPI.Color.fromHex("#fabd2f");
        _ = try api.defineHighlight("LspWarning", yellow, null, yellow, .{ .bold = true, .undercurl = true });

        // Info - blue
        const blue = try runtime.HighlightThemeAPI.Color.fromHex("#83a598");
        _ = try api.defineHighlight("LspInfo", blue, null, null, .{});

        // Hint - cyan
        const cyan = try runtime.HighlightThemeAPI.Color.fromHex("#8ec07c");
        _ = try api.defineHighlight("LspHint", cyan, null, null, .{ .italic = true });

        // Gutter signs
        _ = try api.defineHighlight("LspErrorSign", red, null, null, .{ .bold = true });
        _ = try api.defineHighlight("LspWarningSign", yellow, null, null, .{ .bold = true });
        _ = try api.defineHighlight("LspInfoSign", blue, null, null, .{});
        _ = try api.defineHighlight("LspHintSign", cyan, null, null, .{});
    }
};

pub const GutterSign = struct {
    line: u32,
    icon: []const u8,
    highlight_group: []const u8,
};

test "LSPHighlights init" {
    const allocator = std.testing.allocator;

    var lsp_hl = try LSPHighlights.init(allocator);
    defer lsp_hl.deinit();

    // Verify namespace was created
    try std.testing.expectEqual(@as(u32, 0), lsp_hl.namespace_id);
}

test "LSPHighlights apply diagnostics" {
    const allocator = std.testing.allocator;

    var lsp_hl = try LSPHighlights.init(allocator);
    defer lsp_hl.deinit();

    const diagnostics = [_]editor_lsp.Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 10, .character = 5 },
                .end = .{ .line = 10, .character = 15 },
            },
            .severity = .error_sev,
            .message = "undefined variable",
            .source = "zls",
            .code = "E001",
        },
    };

    try lsp_hl.applyDiagnostics(1, &diagnostics);

    // Verify highlight was added to namespace
    const ns = lsp_hl.highlight_api.namespaces.get("lsp_diagnostics").?;
    try std.testing.expectEqual(@as(usize, 1), ns.highlights.items.len);
    try std.testing.expectEqual(@as(u32, 10), ns.highlights.items[0].line);
}

test "LSPHighlights gutter signs" {
    const allocator = std.testing.allocator;

    var lsp_hl = try LSPHighlights.init(allocator);
    defer lsp_hl.deinit();

    const diagnostics = [_]editor_lsp.Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 5, .character = 0 },
                .end = .{ .line = 5, .character = 10 },
            },
            .severity = .error_sev,
            .message = "error",
            .source = null,
            .code = null,
        },
        .{
            .range = .{
                .start = .{ .line = 5, .character = 15 },
                .end = .{ .line = 5, .character = 20 },
            },
            .severity = .warning,
            .message = "warning",
            .source = null,
            .code = null,
        },
    };

    const signs = try lsp_hl.renderGutterSigns(&diagnostics);
    defer allocator.free(signs);

    // Should show most severe (error) for line 5
    try std.testing.expectEqual(@as(usize, 1), signs.len);
    try std.testing.expectEqual(@as(u32, 5), signs[0].line);
    try std.testing.expectEqualStrings("E", signs[0].icon);
}

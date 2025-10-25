//! LSP diagnostics rendering in gutter

const std = @import("std");

pub const Severity = enum(u8) {
    error_ = 1,
    warning = 2,
    info = 3,
    hint = 4,
};

pub const Diagnostic = struct {
    line: u32,
    col: u32,
    severity: Severity,
    message: []const u8,
    source: ?[]const u8 = null,
};

pub const DiagnosticsUI = struct {
    diagnostics: std.ArrayList(Diagnostic),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiagnosticsUI {
        return .{
            .diagnostics = std.ArrayList(Diagnostic).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DiagnosticsUI) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
            if (diag.source) |s| self.allocator.free(s);
        }
        self.diagnostics.deinit(self.allocator);
    }

    pub fn addDiagnostic(self: *DiagnosticsUI, diag: Diagnostic) !void {
        try self.diagnostics.append(.{
            .line = diag.line,
            .col = diag.col,
            .severity = diag.severity,
            .message = try self.allocator.dupe(u8, diag.message),
            .source = if (diag.source) |s| try self.allocator.dupe(u8, s) else null,
        });
    }

    pub fn clear(self: *DiagnosticsUI) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
            if (diag.source) |s| self.allocator.free(s);
        }
        self.diagnostics.clearRetainingCapacity();
    }

    /// Render diagnostic symbol in gutter
    pub fn renderGutter(self: *const DiagnosticsUI, writer: anytype, line: u32) !void {
        const sev = self.getSeverityForLine(line);

        if (sev) |s| {
            const symbol: []const u8 = switch (s) {
                .error_ => "E",
                .warning => "W",
                .info => "I",
                .hint => "H",
            };
            const color: []const u8 = switch (s) {
                .error_ => "\x1b[31m",
                .warning => "\x1b[33m",
                .info => "\x1b[34m",
                .hint => "\x1b[36m",
            };
            try writer.print("{s}{s}\x1b[0m", .{ color, symbol });
        } else {
            try writer.writeAll(" ");
        }
    }

    /// Get diagnostic message at line
    pub fn getMessageAtLine(self: *const DiagnosticsUI, line: u32) ?[]const u8 {
        for (self.diagnostics.items) |diag| {
            if (diag.line == line) return diag.message;
        }
        return null;
    }

    fn getSeverityForLine(self: *const DiagnosticsUI, line: u32) ?Severity {
        var worst: ?Severity = null;
        for (self.diagnostics.items) |diag| {
            if (diag.line == line) {
                if (worst == null or @intFromEnum(diag.severity) < @intFromEnum(worst.?)) {
                    worst = diag.severity;
                }
            }
        }
        return worst;
    }
};

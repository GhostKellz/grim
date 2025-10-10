const std = @import("std");
const lsp_highlights = @import("lsp_highlights.zig");
const syntax_highlights = @import("syntax_highlights.zig");
const buffer_manager = @import("buffer_manager.zig");
const config_mod = @import("config.zig");
const editor_lsp_mod = @import("editor_lsp.zig");
const core = @import("core");

/// Integration layer for wiring new features into SimpleTUI
/// This module provides high-level integration functions to connect:
/// - LSP diagnostics → HighlightThemeAPI
/// - Tree-sitter/Grove → HighlightThemeAPI
/// - BufferManager lifecycle
/// - Config system
pub const EditorIntegration = struct {
    allocator: std.mem.Allocator,
    lsp_highlights: ?*lsp_highlights.LSPHighlights,
    syntax_highlights: ?*syntax_highlights.SyntaxHighlights,
    buffer_manager: ?*buffer_manager.BufferManager,
    config: config_mod.Config,

    pub fn init(allocator: std.mem.Allocator) !EditorIntegration {
        return EditorIntegration{
            .allocator = allocator,
            .lsp_highlights = null,
            .syntax_highlights = null,
            .buffer_manager = null,
            .config = config_mod.Config.init(allocator),
        };
    }

    pub fn deinit(self: *EditorIntegration) void {
        if (self.lsp_highlights) |lsp_hl| {
            lsp_hl.deinit();
            self.allocator.destroy(lsp_hl);
        }
        if (self.syntax_highlights) |syntax_hl| {
            syntax_hl.deinit();
            self.allocator.destroy(syntax_hl);
        }
        if (self.buffer_manager) |mgr| {
            mgr.deinit();
            self.allocator.destroy(mgr);
        }
        self.config.deinit();
    }

    /// Initialize LSP highlights integration
    pub fn initLSPHighlights(self: *EditorIntegration) !void {
        if (self.lsp_highlights != null) return; // Already initialized

        const lsp_hl = try self.allocator.create(lsp_highlights.LSPHighlights);
        lsp_hl.* = try lsp_highlights.LSPHighlights.init(self.allocator);
        self.lsp_highlights = lsp_hl;
    }

    /// Initialize syntax highlights integration
    pub fn initSyntaxHighlights(self: *EditorIntegration) !void {
        if (self.syntax_highlights != null) return; // Already initialized

        const syntax_hl = try self.allocator.create(syntax_highlights.SyntaxHighlights);
        syntax_hl.* = try syntax_highlights.SyntaxHighlights.init(self.allocator);
        self.syntax_highlights = syntax_hl;
    }

    /// Initialize buffer manager
    pub fn initBufferManager(self: *EditorIntegration) !void {
        if (self.buffer_manager != null) return; // Already initialized

        const mgr = try self.allocator.create(buffer_manager.BufferManager);
        mgr.* = try buffer_manager.BufferManager.init(self.allocator);
        self.buffer_manager = mgr;
    }

    /// Load configuration from default location
    pub fn loadConfig(self: *EditorIntegration) !void {
        try self.config.loadDefault();
    }

    /// Apply LSP diagnostics as highlights
    pub fn applyLSPDiagnostics(
        self: *EditorIntegration,
        buffer_id: u32,
        diagnostics: []const editor_lsp_mod.Diagnostic,
    ) !void {
        const lsp_hl = self.lsp_highlights orelse return error.LSPHighlightsNotInitialized;
        try lsp_hl.applyDiagnostics(buffer_id, diagnostics);
    }

    /// Get LSP gutter signs for rendering
    pub fn getLSPGutterSigns(
        self: *EditorIntegration,
        diagnostics: []const editor_lsp_mod.Diagnostic,
    ) ![]lsp_highlights.GutterSign {
        const lsp_hl = self.lsp_highlights orelse return error.LSPHighlightsNotInitialized;
        return lsp_hl.renderGutterSigns(diagnostics);
    }

    /// Get diagnostic count for status line
    pub fn getDiagnosticCount(
        self: *EditorIntegration,
        lsp: *editor_lsp_mod.EditorLSP,
        path: []const u8,
        severity: editor_lsp_mod.Diagnostic.Severity,
    ) usize {
        const lsp_hl = self.lsp_highlights orelse return 0;
        return lsp_hl.getDiagnosticCount(lsp, path, severity);
    }

    /// Format diagnostic message for display
    pub fn formatDiagnosticMessage(
        self: *EditorIntegration,
        diagnostic: editor_lsp_mod.Diagnostic,
    ) ![]const u8 {
        const lsp_hl = self.lsp_highlights orelse return error.LSPHighlightsNotInitialized;
        return lsp_hl.formatDiagnosticMessage(diagnostic);
    }

    /// Apply syntax highlighting to buffer
    pub fn applySyntaxHighlights(
        self: *EditorIntegration,
        buffer_id: u32,
        rope: *core.Rope,
        filename: ?[]const u8,
    ) !void {
        const syntax_hl = self.syntax_highlights orelse return error.SyntaxHighlightsNotInitialized;

        // Set language based on filename
        if (filename) |file| {
            try syntax_hl.setLanguage(file);
        }

        // Apply highlights
        try syntax_hl.applyHighlights(buffer_id, rope);
    }

    /// Get current language name for status line
    pub fn getLanguageName(self: *EditorIntegration) []const u8 {
        if (self.syntax_highlights) |syntax_hl| {
            return syntax_hl.getLanguageName();
        }
        return "unknown";
    }

    /// Enhanced status line info
    pub const StatusInfo = struct {
        mode: []const u8,
        line: usize,
        column: usize,
        total_bytes: usize,
        language: []const u8,
        error_count: usize,
        warning_count: usize,
        modified: bool,
        buffer_count: usize,
        active_buffer_name: []const u8,
    };

    /// Get comprehensive status line info
    pub fn getStatusInfo(
        self: *EditorIntegration,
        mode: []const u8,
        line: usize,
        column: usize,
        total_bytes: usize,
        lsp: ?*editor_lsp_mod.EditorLSP,
        current_file: ?[]const u8,
    ) StatusInfo {
        var error_count: usize = 0;
        var warning_count: usize = 0;

        if (lsp) |lsp_ptr| {
            if (current_file) |path| {
                error_count = self.getDiagnosticCount(lsp_ptr, path, .error_sev);
                warning_count = self.getDiagnosticCount(lsp_ptr, path, .warning);
            }
        }

        const language = self.getLanguageName();

        var buffer_count: usize = 1;
        var active_buffer_name: []const u8 = "[No Name]";
        var modified = false;

        if (self.buffer_manager) |mgr| {
            buffer_count = mgr.buffers.items.len;
            if (mgr.getActiveBuffer()) |buf| {
                active_buffer_name = buf.display_name;
                modified = buf.modified;
            }
        }

        return StatusInfo{
            .mode = mode,
            .line = line,
            .column = column,
            .total_bytes = total_bytes,
            .language = language,
            .error_count = error_count,
            .warning_count = warning_count,
            .modified = modified,
            .buffer_count = buffer_count,
            .active_buffer_name = active_buffer_name,
        };
    }
};

test "EditorIntegration init" {
    const allocator = std.testing.allocator;

    var integration = try EditorIntegration.init(allocator);
    defer integration.deinit();

    try std.testing.expect(integration.lsp_highlights == null);
    try std.testing.expect(integration.syntax_highlights == null);
    try std.testing.expect(integration.buffer_manager == null);
}

test "EditorIntegration LSP highlights init" {
    const allocator = std.testing.allocator;

    var integration = try EditorIntegration.init(allocator);
    defer integration.deinit();

    try integration.initLSPHighlights();
    try std.testing.expect(integration.lsp_highlights != null);
}

test "EditorIntegration syntax highlights init" {
    const allocator = std.testing.allocator;

    var integration = try EditorIntegration.init(allocator);
    defer integration.deinit();

    try integration.initSyntaxHighlights();
    try std.testing.expect(integration.syntax_highlights != null);
}

const std = @import("std");
const core = @import("core");
const lsp = @import("lsp");
const syntax = @import("syntax");
const Editor = @import("editor.zig").Editor;

pub const Diagnostic = struct {
    range: Range,
    severity: Severity,
    message: []const u8,
    source: ?[]const u8,
    code: ?[]const u8,

    pub const Severity = enum(u8) {
        error_sev = 1,
        warning = 2,
        information = 3,
        hint = 4,
    };

    pub const Range = struct {
        start: Position,
        end: Position,
    };

    pub const Position = struct {
        line: u32,
        character: u32,
    };
};

pub const Completion = struct {
    label: []const u8,
    kind: CompletionKind,
    detail: ?[]const u8,
    documentation: ?[]const u8,
    insert_text: ?[]const u8,

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
        property = 10,
        unit = 11,
        value = 12,
        @"enum" = 13,
        keyword = 14,
        snippet = 15,
        color = 16,
        file = 17,
        reference = 18,
    };
};

pub const EditorLSP = struct {
    allocator: std.mem.Allocator,
    editor: *Editor,
    server_registry: lsp.ServerRegistry,
    diagnostics: std.HashMap([]const u8, []Diagnostic),
    completions: std.ArrayList(Completion),
    hover_info: ?[]const u8,
    current_file: ?[]const u8,
    language: ?syntax.Language,

    pub const Error = lsp.LanguageServer.Error || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator, editor: *Editor) !*EditorLSP {
        const self = try allocator.create(EditorLSP);
        self.* = .{
            .allocator = allocator,
            .editor = editor,
            .server_registry = lsp.ServerRegistry.init(allocator),
            .diagnostics = std.HashMap([]const u8, []Diagnostic).init(allocator),
            .completions = std.ArrayList(Completion).init(allocator),
            .hover_info = null,
            .current_file = null,
            .language = null,
        };
        return self;
    }

    pub fn deinit(self: *EditorLSP) void {
        self.server_registry.deinit();

        // Free diagnostics
        var iter = self.diagnostics.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |diag| {
                self.allocator.free(diag.message);
                if (diag.source) |src| self.allocator.free(src);
                if (diag.code) |code| self.allocator.free(code);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.diagnostics.deinit();

        // Free completions
        for (self.completions.items) |comp| {
            self.allocator.free(comp.label);
            if (comp.detail) |detail| self.allocator.free(detail);
            if (comp.documentation) |doc| self.allocator.free(doc);
            if (comp.insert_text) |text| self.allocator.free(text);
        }
        self.completions.deinit();

        if (self.hover_info) |info| self.allocator.free(info);
        if (self.current_file) |path| self.allocator.free(path);

        self.allocator.destroy(self);
    }

    pub fn openFile(self: *EditorLSP, path: []const u8) !void {
        // Detect language
        self.language = syntax.detectLanguage(path);
        if (self.language == null) return; // No LSP support for this file type

        // Update current file
        if (self.current_file) |current| self.allocator.free(current);
        self.current_file = try self.allocator.dupe(u8, path);

        // Start language server if needed
        const server = try self.getOrStartServer(self.language.?);

        // Get file content
        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });

        // Convert file path to URI
        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        // Send didOpen notification
        try server.openDocument(uri, @tagName(self.language.?), 1, content);
    }

    pub fn closeFile(self: *EditorLSP, path: []const u8) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        try server.closeDocument(uri);
    }

    pub fn notifyChange(self: *EditorLSP, path: []const u8, version: u32, changes: []const lsp.LanguageServer.TextChange) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        try server.changeDocument(uri, version, changes);
    }

    pub fn requestCompletion(self: *EditorLSP, path: []const u8, line: u32, character: u32) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const position = lsp.LanguageServer.Position{ .line = line, .character = character };
        _ = try server.requestCompletion(uri, position);
    }

    pub fn requestHover(self: *EditorLSP, path: []const u8, line: u32, character: u32) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const position = lsp.LanguageServer.Position{ .line = line, .character = character };
        _ = try server.requestHover(uri, position);
    }

    pub fn requestDefinition(self: *EditorLSP, path: []const u8, line: u32, character: u32) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const position = lsp.LanguageServer.Position{ .line = line, .character = character };
        _ = try server.requestDefinition(uri, position);
    }

    pub fn getDiagnostics(self: *EditorLSP, path: []const u8) ?[]const Diagnostic {
        return self.diagnostics.get(path);
    }

    pub fn getCompletions(self: *EditorLSP) []const Completion {
        return self.completions.items;
    }

    pub fn getHoverInfo(self: *EditorLSP) ?[]const u8 {
        return self.hover_info;
    }

    fn getOrStartServer(self: *EditorLSP, language: syntax.Language) !*lsp.LanguageServer {
        const lang_str = @tagName(language);

        if (self.server_registry.getServer(lang_str)) |server| {
            return server;
        }

        // Start new server
        const config = self.getServerConfig(language) orelse return error.ServerNotAvailable;
        return try self.server_registry.startServer(lang_str, config);
    }

    fn getServerConfig(self: *EditorLSP, language: syntax.Language) ?lsp.LanguageServer.ServerConfig {
        _ = self;
        return switch (language) {
            .zig => .{
                .command = &[_][]const u8{ "zls", "--enable-debug-log" },
                .root_uri = "file:///data/projects/grim", // TODO: Use actual project root
            },
            .rust => .{
                .command = &[_][]const u8{"rust-analyzer"},
                .root_uri = "file:///data/projects/grim",
            },
            .javascript, .typescript => .{
                .command = &[_][]const u8{ "typescript-language-server", "--stdio" },
                .root_uri = "file:///data/projects/grim",
            },
            .python => .{
                .command = &[_][]const u8{"pylsp"},
                .root_uri = "file:///data/projects/grim",
            },
            .c, .cpp => .{
                .command = &[_][]const u8{"clangd"},
                .root_uri = "file:///data/projects/grim",
            },
            .ghostlang => .{
                .command = &[_][]const u8{"ghostlang-lsp"},
                .root_uri = "file:///data/projects/grim",
            },
            else => null,
        };
    }

    fn pathToUri(self: *EditorLSP, path: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(path)) {
            return try std.fmt.allocPrint(self.allocator, "file://{s}", .{path});
        } else {
            const cwd = try std.process.getCwdAlloc(self.allocator);
            defer self.allocator.free(cwd);
            const abs_path = try std.fs.path.join(self.allocator, &[_][]const u8{ cwd, path });
            defer self.allocator.free(abs_path);
            return try std.fmt.allocPrint(self.allocator, "file://{s}", .{abs_path});
        }
    }

    fn offsetToPosition(self: *EditorLSP, offset: usize) Diagnostic.Position {
        const content = self.editor.rope.slice(.{ .start = 0, .end = offset }) catch return .{ .line = 0, .character = 0 };

        var line: u32 = 0;
        var character: u32 = 0;

        for (content) |ch| {
            if (ch == '\n') {
                line += 1;
                character = 0;
            } else {
                character += 1;
            }
        }

        return .{ .line = line, .character = character };
    }

    fn positionToOffset(self: *EditorLSP, position: Diagnostic.Position) usize {
        const content = self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() }) catch return 0;

        var current_line: u32 = 0;
        var current_char: u32 = 0;

        for (content, 0..) |ch, i| {
            if (current_line == position.line and current_char == position.character) {
                return i;
            }

            if (ch == '\n') {
                current_line += 1;
                current_char = 0;
            } else {
                current_char += 1;
            }
        }

        return content.len;
    }

    // Diagnostic rendering utilities
    pub fn renderDiagnostics(self: *EditorLSP, path: []const u8, start_line: u32, end_line: u32) ![]DiagnosticRender {
        const diagnostics = self.getDiagnostics(path) orelse return &[_]DiagnosticRender{};

        var renders = std.ArrayList(DiagnosticRender).init(self.allocator);
        errdefer renders.deinit();

        for (diagnostics) |diag| {
            if (diag.range.start.line >= start_line and diag.range.start.line <= end_line) {
                try renders.append(.{
                    .line = diag.range.start.line,
                    .column = diag.range.start.character,
                    .length = if (diag.range.start.line == diag.range.end.line)
                        diag.range.end.character - diag.range.start.character
                    else
                        1,
                    .severity = diag.severity,
                    .message = diag.message,
                });
            }
        }

        return renders.toOwnedSlice();
    }

    pub const DiagnosticRender = struct {
        line: u32,
        column: u32,
        length: u32,
        severity: Diagnostic.Severity,
        message: []const u8,
    };

    // Auto-completion integration
    pub fn shouldTriggerCompletion(self: *EditorLSP, last_char: u8) bool {
        _ = self;
        return switch (last_char) {
            '.', ':', '(', ' ', '\t' => true,
            else => false,
        };
    }

    pub fn filterCompletions(self: *EditorLSP, allocator: std.mem.Allocator, prefix: []const u8) ![]Completion {
        if (prefix.len == 0) return try allocator.dupe(Completion, self.completions.items);

        var filtered = std.ArrayList(Completion).init(allocator);
        errdefer filtered.deinit();

        for (self.completions.items) |comp| {
            if (std.mem.startsWith(u8, comp.label, prefix)) {
                try filtered.append(comp);
            }
        }

        return filtered.toOwnedSlice();
    }
};

// LSP diagnostics sink for handling server messages
pub const DiagnosticsSink = struct {
    editor_lsp: *EditorLSP,

    pub fn init(editor_lsp: *EditorLSP) DiagnosticsSink {
        return .{ .editor_lsp = editor_lsp };
    }

    pub fn log(ctx: *anyopaque, message: []const u8) std.mem.Allocator.Error!void {
        const self = @as(*DiagnosticsSink, @ptrCast(@alignCast(ctx)));

        // Parse LSP diagnostic message
        // This is a simplified version - real implementation would parse JSON
        if (std.mem.indexOf(u8, message, "textDocument/publishDiagnostics") != null) {
            try self.parseDiagnostics(message);
        }
    }

    fn parseDiagnostics(self: *DiagnosticsSink, message: []const u8) !void {
        // TODO: Implement proper JSON parsing of LSP diagnostics
        // For now, just log the message
        _ = self;
        std.debug.print("LSP Diagnostic: {s}\n", .{message});
    }
};

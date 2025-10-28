const std = @import("std");
const core = @import("core");
const lsp = @import("lsp");
const syntax = @import("syntax");
const Editor = @import("editor.zig").Editor;

pub const Diagnostic = struct {
    test "editor lsp uri to path" {
        const allocator = std.testing.allocator;

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const uri = "file:///tmp/sample.zig";
        const path = try editor_lsp.uriToPath(uri);
        defer editor_lsp.allocator.free(path);

        try std.testing.expectEqualStrings("/tmp/sample.zig", path);
    }

    test "editor lsp offset from position" {
        const allocator = std.testing.allocator;

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        try editor.rope.insert(0, "first line\nsecond\n");

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const offset = editor_lsp.offsetFromPosition(1, 3);
        try std.testing.expectEqual(@as(usize, 14), offset);
    }

    test "editor lsp definition result lifecycle" {
        const allocator = std.testing.allocator;

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        editor_lsp.storeDefinitionResult("file:///workspace/lib.zig", 2, 4);

        const result = editor_lsp.takeDefinitionResult() orelse {
            return std.testing.expect(false);
        };
        defer editor_lsp.freeDefinitionResult(result);

        try std.testing.expectEqualStrings("/workspace/lib.zig", result.path);
        try std.testing.expectEqual(@as(u32, 2), result.line);
        try std.testing.expectEqual(@as(u32, 4), result.character);
        try std.testing.expect(editor_lsp.takeDefinitionResult() == null);
    }

    test "editor lsp stores and clears diagnostics" {
        const allocator = std.testing.allocator;

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const payload =
            "{\"uri\":\"file:///tmp/sample.zig\",\"diagnostics\":[{" ++ "\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":5}}," ++ "\"severity\":1,\"message\":\"oops\",\"source\":\"zls\",\"code\":123}]}";

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
        defer parsed.deinit();

        try DiagnosticsSink.handle(@as(*anyopaque, @ptrCast(&editor_lsp.diagnostics_sink)), parsed.value);

        const diagnostics = editor_lsp.getDiagnostics("/tmp/sample.zig") orelse return std.testing.expect(false);
        try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
        try std.testing.expectEqual(@as(u32, 1), diagnostics[0].range.start.line);
        try std.testing.expectEqual(@as(u32, 2), diagnostics[0].range.start.character);
        try std.testing.expectEqual(Diagnostic.Severity.error_sev, diagnostics[0].severity);
        try std.testing.expectEqualStrings("oops", diagnostics[0].message);
        try std.testing.expectEqualStrings("zls", diagnostics[0].source.?);
        try std.testing.expectEqualStrings("123", diagnostics[0].code.?);

        const clear_payload = "{\"uri\":\"file:///tmp/sample.zig\",\"diagnostics\":[]}";
        const clear_parsed = try std.json.parseFromSlice(std.json.Value, allocator, clear_payload, .{});
        defer clear_parsed.deinit();

        try DiagnosticsSink.handle(@as(*anyopaque, @ptrCast(&editor_lsp.diagnostics_sink)), clear_parsed.value);

        try std.testing.expect(editor_lsp.getDiagnostics("/tmp/sample.zig") == null);
    }

    test "editor lsp detects workspace root with marker" {
        const allocator = std.testing.allocator;

        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        try tmp.dir.makeDir("project");
        try tmp.dir.makeDir("project/src");
        try tmp.dir.writeFile("project/build.zig", "// root marker");

        const project_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp.path, "project" });
        defer allocator.free(project_path);

        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ project_path, "src", "main.zig" });
        defer allocator.free(file_path);

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const root = try editor_lsp.detectWorkspaceRoot(file_path);
        defer allocator.free(root);

        try std.testing.expectEqualStrings(project_path, root);
    }

    test "editor lsp detects workspace root fallback" {
        const allocator = std.testing.allocator;

        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        try tmp.dir.makeDir("workspace");
        try tmp.dir.makeDir("workspace/nested");

        const nested_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp.path, "workspace", "nested" });
        defer allocator.free(nested_dir);

        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ nested_dir, "file.zig" });
        defer allocator.free(file_path);

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const root = try editor_lsp.detectWorkspaceRoot(file_path);
        defer allocator.free(root);

        try std.testing.expectEqualStrings(nested_dir, root);
    }

    test "editor lsp stores completion items" {
        const allocator = std.testing.allocator;

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const payload =
            "{\"items\":[{" ++ "\"label\":\"greet\"," ++ "\"kind\":3," ++ "\"detail\":\"fn greet()\"," ++ "\"documentation\":\"Greets the user\"," ++ "\"insertText\":\"greet()\"" ++ "}]}";

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
        defer parsed.deinit();

        editor_lsp.pending_completion = 42;
        try editor_lsp.processCompletionResponse(.{ .request_id = 42, .result = parsed.value });

        const completions = editor_lsp.getCompletions();
        try std.testing.expectEqual(@as(usize, 1), completions.len);
        try std.testing.expectEqualStrings("greet", completions[0].label);
        try std.testing.expectEqual(Completion.CompletionKind.function, completions[0].kind);
        try std.testing.expectEqualStrings("fn greet()", completions[0].detail.?);
        try std.testing.expectEqualStrings("Greets the user", completions[0].documentation.?);
        try std.testing.expectEqualStrings("greet()", completions[0].insert_text.?);
        try std.testing.expect(editor_lsp.pending_completion == null);
    }

    test "editor lsp ignores stale completion responses" {
        const allocator = std.testing.allocator;

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const payload = "{\"items\":[]}";
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
        defer parsed.deinit();

        editor_lsp.pending_completion = 7;
        try editor_lsp.processCompletionResponse(.{ .request_id = 99, .result = parsed.value });

        try std.testing.expectEqual(@as(usize, 0), editor_lsp.getCompletions().len);
        try std.testing.expectEqual(@as(?u32, 7), editor_lsp.pending_completion);
    }

    test "editor lsp parses snippet text edit completions" {
        const allocator = std.testing.allocator;

        var editor = try Editor.init(allocator);
        defer editor.deinit();

        var editor_lsp = try EditorLSP.init(allocator, &editor);
        defer editor_lsp.deinit();

        const payload = "{\"items\":[{\"label\":\"wrap\",\"insertTextFormat\":2,\"textEdit\":{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":0,\"character\":3}},\"newText\":\"${1:foo}\"}}]}";

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
        defer parsed.deinit();

        editor_lsp.pending_completion = 5;
        try editor_lsp.processCompletionResponse(.{ .request_id = 5, .result = parsed.value });

        const completions = editor_lsp.getCompletions();
        try std.testing.expectEqual(@as(usize, 1), completions.len);
        const comp = completions[0];
        try std.testing.expectEqualStrings("wrap", comp.label);
        try std.testing.expect(comp.text_edit != null);
        try std.testing.expectEqual(Completion.InsertTextFormat.snippet, comp.insert_text_format);
        const edit = comp.text_edit.?;
        try std.testing.expectEqual(@as(u32, 0), edit.range.start.line);
        try std.testing.expectEqual(@as(u32, 0), edit.range.start.character);
        try std.testing.expectEqual(@as(u32, 0), edit.range.end.line);
        try std.testing.expectEqual(@as(u32, 3), edit.range.end.character);
        try std.testing.expectEqualStrings("${1:foo}", edit.new_text);
    }

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
    text_edit: ?TextEdit,
    insert_text_format: InsertTextFormat,

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

    pub const InsertTextFormat = enum(u8) {
        plain_text = 1,
        snippet = 2,
    };

    pub const TextEdit = struct {
        range: Diagnostic.Range,
        new_text: []const u8,
    };
};

// Ghostls v0.3.0 Data Structures
pub const SignatureHelp = struct {
    active_signature: u32,
    active_parameter: u32,
    signatures: []SignatureInfo,

    pub const SignatureInfo = struct {
        label: []const u8,
        documentation: ?[]const u8,
        parameters: []ParameterInfo,

        pub const ParameterInfo = struct {
            label: []const u8,
            documentation: ?[]const u8,
        };
    };
};

pub const InlayHint = struct {
    position: Diagnostic.Position,
    label: []const u8,
    kind: HintKind,
    tooltip: ?[]const u8,

    pub const HintKind = enum {
        type,
        parameter,
    };
};

pub const SelectionRange = struct {
    range: Diagnostic.Range,
    parent: ?*SelectionRange,
};

pub const CodeAction = struct {
    title: []const u8,
    kind: []const u8,
    is_preferred: bool,
    edit: ?WorkspaceEdit,

    pub const WorkspaceEdit = struct {
        changes: std.StringHashMap([]TextEdit),

        pub const TextEdit = struct {
            range: Diagnostic.Range,
            new_text: []const u8,
        };
    };
};

pub const EditorLSP = struct {
    allocator: std.mem.Allocator,
    editor: *Editor,
    server_registry: lsp.ServerRegistry,
    diagnostics: std.StringHashMap([]Diagnostic),
    completions: std.ArrayList(Completion),
    documents: std.ArrayList(DocumentEntry),
    hover_info: ?[]u8,
    pending_definition: ?DefinitionResult,
    pending_completion: ?u32,
    completion_generation: u64,
    current_file: ?[]const u8,
    language: ?syntax.Language,
    diagnostics_sink: DiagnosticsSink,
    // Ghostls v0.3.0 features
    signature_help: ?SignatureHelp,
    inlay_hints: std.ArrayList(InlayHint),
    inlay_hints_enabled: bool,
    selection_ranges: std.ArrayList(SelectionRange),
    code_actions: std.ArrayList(CodeAction),

    pub const Error = lsp.LanguageServer.Error || std.mem.Allocator.Error;

    const DocumentEntry = struct {
        path: []u8,
        language: syntax.Language,
        version: u32,
    };

    const DefinitionResult = struct {
        path: []u8,
        line: u32,
        character: u32,
    };

    pub fn init(allocator: std.mem.Allocator, editor: *Editor) !*EditorLSP {
        const self = try allocator.create(EditorLSP);
        self.* = .{
            .allocator = allocator,
            .editor = editor,
            .server_registry = lsp.ServerRegistry.init(allocator),
            .diagnostics = std.StringHashMap([]Diagnostic).init(allocator),
            .completions = std.ArrayList(Completion).empty,
            .documents = std.ArrayList(DocumentEntry).empty,
            .hover_info = null,
            .pending_definition = null,
            .pending_completion = null,
            .completion_generation = 0,
            .current_file = null,
            .language = null,
            .diagnostics_sink = undefined,
            // Ghostls v0.3.0 features
            .signature_help = null,
            .inlay_hints = std.ArrayList(InlayHint).empty,
            .inlay_hints_enabled = true,
            .selection_ranges = std.ArrayList(SelectionRange).empty,
            .code_actions = std.ArrayList(CodeAction).empty,
        };
        self.diagnostics_sink = DiagnosticsSink.init(self);
        return self;
    }

    pub fn deinit(self: *EditorLSP) void {
        self.server_registry.deinit();

        // Free diagnostics
        var iter = self.diagnostics.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.freeDiagnosticSlice(entry.value_ptr.*);
        }
        self.diagnostics.deinit();

        // Free completions
        self.clearCompletions();
        self.completions.deinit(self.allocator);

        for (self.documents.items) |doc| {
            self.allocator.free(doc.path);
        }
        self.documents.deinit(self.allocator);

        if (self.hover_info) |info| self.allocator.free(info);
        if (self.pending_definition) |def| self.allocator.free(def.path);
        if (self.current_file) |path| self.allocator.free(path);

        // Free ghostls v0.3.0 features
        self.clearSignatureHelp();
        self.clearInlayHints();
        self.inlay_hints.deinit(self.allocator);
        self.clearSelectionRanges();
        self.selection_ranges.deinit(self.allocator);
        self.clearCodeActions();
        self.code_actions.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    pub fn openFile(self: *EditorLSP, path: []const u8) !void {
        const language = syntax.detectLanguage(path);
        if (self.getServerCommand(language) == null) {
            self.language = null;
            return;
        }

        if (self.findDocumentIndex(path)) |_| {
            self.closeFile(path) catch |err| {
                std.log.warn("Failed to close existing LSP document before reopen: {}", .{err});
            };
        }

        const server = try self.getOrStartServer(language, path);

        if (self.current_file) |current| self.allocator.free(current);
        self.current_file = try self.allocator.dupe(u8, path);
        self.language = language;
        self.clearCompletions();
        self.pending_completion = null;
        self.bumpCompletionGeneration();

        if (self.hover_info) |info| {
            self.allocator.free(info);
            self.hover_info = null;
        }

        if (self.pending_definition) |def| {
            self.allocator.free(def.path);
            self.pending_definition = null;
        }

        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        defer self.allocator.free(content);

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        try server.openDocument(uri, @tagName(language), 1, content);
        try self.trackDocument(path, language, 1);
    }

    pub fn closeFile(self: *EditorLSP, path: []const u8) !void {
        if (self.findDocumentIndex(path)) |idx| {
            const doc = self.documents.items[idx];
            if (self.server_registry.getServer(@tagName(doc.language))) |server| {
                const uri = try self.pathToUri(path);
                defer self.allocator.free(uri);
                try server.closeDocument(uri);
            }
            self.removeDocumentAt(idx);
        }

        if (self.current_file) |current| {
            if (std.mem.eql(u8, current, path)) {
                self.allocator.free(current);
                self.current_file = null;
                self.language = null;
                if (self.hover_info) |info| {
                    self.allocator.free(info);
                    self.hover_info = null;
                }
                if (self.pending_definition) |def| {
                    self.allocator.free(def.path);
                    self.pending_definition = null;
                }
                self.clearCompletions();
                self.pending_completion = null;
                self.bumpCompletionGeneration();
            }
        }
    }

    pub fn notifyBufferChange(self: *EditorLSP, path: []const u8) !void {
        var doc = self.getDocument(path) orelse return;
        const server = try self.getOrStartServer(doc.language, doc.path);

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const content = try self.editor.rope.slice(.{ .start = 0, .end = self.editor.rope.len() });
        defer self.allocator.free(content);

        doc.version += 1;
        errdefer doc.version -= 1;

        const change = lsp.LanguageServer.TextChange{ .range = null, .text = content };
        try server.changeDocument(uri, doc.version, &.{change});

        if (self.hover_info) |existing| {
            self.allocator.free(existing);
            self.hover_info = null;
        }
    }

    pub fn notifyFileSaved(self: *EditorLSP, path: []const u8) !void {
        const doc = self.getDocument(path) orelse return;
        const server = try self.getOrStartServer(doc.language, doc.path);

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        try server.saveDocument(uri, null);
    }

    pub fn requestCompletion(self: *EditorLSP, path: []const u8, line: u32, character: u32) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const position = lsp.LanguageServer.Position{ .line = line, .character = character };
        const request_id = try server.requestCompletion(uri, position);
        self.pending_completion = request_id;
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

    pub fn requestSignatureHelp(self: *EditorLSP, path: []const u8, line: u32, character: u32) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const position = lsp.LanguageServer.Position{ .line = line, .character = character };
        _ = try server.requestSignatureHelp(uri, position);
    }

    pub fn requestInlayHints(self: *EditorLSP, path: []const u8, start_line: u32, end_line: u32) !void {
        if (self.language == null) return;
        if (!self.inlay_hints_enabled) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const range = lsp.LanguageServer.Range{
            .start = .{ .line = start_line, .character = 0 },
            .end = .{ .line = end_line, .character = 0 },
        };
        _ = try server.requestInlayHints(uri, range);
    }

    pub fn requestCodeActions(self: *EditorLSP, path: []const u8, start_line: u32, end_line: u32) !void {
        if (self.language == null) return;

        const server = self.server_registry.getServer(@tagName(self.language.?)) orelse return;

        const uri = try self.pathToUri(path);
        defer self.allocator.free(uri);

        const range = lsp.LanguageServer.Range{
            .start = .{ .line = start_line, .character = 0 },
            .end = .{ .line = end_line, .character = 0 },
        };
        _ = try server.requestCodeActions(uri, range);
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

    pub fn isLoading(self: *EditorLSP) bool {
        return self.pending_completion != null or self.pending_definition != null;
    }

    pub fn takeDefinitionResult(self: *EditorLSP) ?DefinitionResult {
        if (self.pending_definition) |result| {
            self.pending_definition = null;
            return result;
        }
        return null;
    }

    pub fn freeDefinitionResult(self: *EditorLSP, result: DefinitionResult) void {
        self.allocator.free(result.path);
    }

    fn handlePublishDiagnostics(self: *EditorLSP, params: std.json.Value) std.mem.Allocator.Error!void {
        if (params != .object) return;
        const object = params.object;

        const uri_node = object.get("uri") orelse return;
        if (uri_node != .string) return;

        const path = self.uriToPath(uri_node.string) catch |err| {
            std.log.warn("Failed to decode diagnostics URI: {}", .{err});
            return;
        };

        const diagnostics_node = object.get("diagnostics") orelse {
            self.clearDiagnostics(path);
            self.allocator.free(path);
            return;
        };

        if (diagnostics_node != .array or diagnostics_node.array.items.len == 0) {
            self.clearDiagnostics(path);
            self.allocator.free(path);
            return;
        }

        var list = try std.ArrayList(Diagnostic).initCapacity(self.allocator, 0);
        errdefer list.deinit(self.allocator);

        for (diagnostics_node.array.items) |diag_node| {
            if (diag_node != .object) continue;
            const diag_obj = diag_node.object;

            const message_node = diag_obj.get("message") orelse continue;
            if (message_node != .string) continue;

            const message = self.allocator.dupe(u8, message_node.string) catch |err| {
                std.log.warn("Failed to duplicate diagnostic message: {}", .{err});
                continue;
            };

            var entry = Diagnostic{
                .range = .{
                    .start = .{ .line = 0, .character = 0 },
                    .end = .{ .line = 0, .character = 0 },
                },
                .severity = .information,
                .message = message,
                .source = null,
                .code = null,
            };

            if (diag_obj.get("severity")) |severity_node| {
                if (severity_node == .integer and severity_node.integer >= 1 and severity_node.integer <= 4) {
                    entry.severity = switch (@as(u3, @intCast(severity_node.integer))) {
                        1 => .error_sev,
                        2 => .warning,
                        3 => .information,
                        else => .hint,
                    };
                }
            }

            if (diag_obj.get("range")) |range_node| {
                if (range_node == .object) {
                    entry.range.start = parsePosition(range_node.object.get("start"));
                    entry.range.end = parsePosition(range_node.object.get("end"));
                }
            }

            if (diag_obj.get("source")) |source_node| {
                if (source_node == .string) {
                    entry.source = self.allocator.dupe(u8, source_node.string) catch |err| blk: {
                        std.log.warn("Failed to duplicate diagnostic source: {}", .{err});
                        break :blk null;
                    };
                }
            }

            if (diag_obj.get("code")) |code_node| {
                entry.code = self.cloneDiagnosticCode(code_node) catch |err| blk: {
                    std.log.warn("Failed to duplicate diagnostic code: {}", .{err});
                    break :blk null;
                };
            }

            list.append(self.allocator, entry) catch |err| {
                self.freeDiagnostic(entry);
                return err;
            };
        }

        if (list.items.len == 0) {
            list.deinit(self.allocator);
            self.clearDiagnostics(path);
            self.allocator.free(path);
            return;
        }

        const diagnostics_slice = try list.toOwnedSlice(self.allocator);
        errdefer self.freeDiagnosticSlice(diagnostics_slice);

        try self.storeDiagnostics(path, diagnostics_slice);
    }

    fn parsePosition(node: ?std.json.Value) Diagnostic.Position {
        var position = Diagnostic.Position{ .line = 0, .character = 0 };
        if (node) |value| {
            if (value == .object) {
                if (value.object.get("line")) |line_node| {
                    if (line_node == .integer and line_node.integer >= 0 and line_node.integer <= std.math.maxInt(u32)) {
                        position.line = @intCast(line_node.integer);
                    }
                }
                if (value.object.get("character")) |char_node| {
                    if (char_node == .integer and char_node.integer >= 0 and char_node.integer <= std.math.maxInt(u32)) {
                        position.character = @intCast(char_node.integer);
                    }
                }
            }
        }
        return position;
    }

    fn cloneDiagnosticCode(self: *EditorLSP, node: std.json.Value) std.mem.Allocator.Error!?[]const u8 {
        if (node == .string) {
            const duped = try self.allocator.dupe(u8, node.string);
            return duped;
        }
        if (node == .integer) {
            const formatted = try std.fmt.allocPrint(self.allocator, "{d}", .{node.integer});
            return formatted;
        }
        return null;
    }

    fn storeDiagnostics(self: *EditorLSP, path: []u8, diagnostics: []Diagnostic) !void {
        if (diagnostics.len == 0) {
            self.clearDiagnostics(path);
            self.allocator.free(path);
            return;
        }

        const gop = try self.diagnostics.getOrPut(path);
        if (gop.found_existing) {
            self.freeDiagnosticSlice(gop.value_ptr.*);
            self.allocator.free(path);
        } else {
            gop.key_ptr.* = path;
        }
        gop.value_ptr.* = diagnostics;
    }

    fn clearDiagnostics(self: *EditorLSP, path: []const u8) void {
        if (self.diagnostics.fetchRemove(path)) |entry| {
            self.freeDiagnosticSlice(entry.value);
            self.allocator.free(entry.key);
        }
    }

    fn freeDiagnosticSlice(self: *EditorLSP, diagnostics: []Diagnostic) void {
        for (diagnostics) |diag| {
            self.freeDiagnostic(diag);
        }
        self.allocator.free(diagnostics);
    }

    fn freeDiagnostic(self: *EditorLSP, diag: Diagnostic) void {
        self.allocator.free(diag.message);
        if (diag.source) |src| self.allocator.free(src);
        if (diag.code) |code| self.allocator.free(code);
    }

    fn freeCompletion(self: *EditorLSP, completion: Completion) void {
        self.allocator.free(completion.label);
        if (completion.detail) |detail| self.allocator.free(detail);
        if (completion.documentation) |doc| self.allocator.free(doc);
        if (completion.insert_text) |text| self.allocator.free(text);
        if (completion.text_edit) |edit| self.allocator.free(edit.new_text);
    }

    fn clearCompletions(self: *EditorLSP) void {
        for (self.completions.items) |comp| {
            self.freeCompletion(comp);
        }
        self.completions.clearRetainingCapacity();
    }

    fn bumpCompletionGeneration(self: *EditorLSP) void {
        self.completion_generation +%= 1;
    }

    pub fn getCompletionGeneration(self: *EditorLSP) u64 {
        return self.completion_generation;
    }

    // Ghostls v0.3.0 cleanup helpers
    fn clearSignatureHelp(self: *EditorLSP) void {
        if (self.signature_help) |sig_help| {
            self.freeSignatureHelp(sig_help);
            self.signature_help = null;
        }
    }

    fn freeSignatureHelp(self: *EditorLSP, sig_help: SignatureHelp) void {
        for (sig_help.signatures) |sig| {
            self.allocator.free(sig.label);
            if (sig.documentation) |doc| self.allocator.free(doc);
            for (sig.parameters) |param| {
                self.allocator.free(param.label);
                if (param.documentation) |doc| self.allocator.free(doc);
            }
            self.allocator.free(sig.parameters);
        }
        self.allocator.free(sig_help.signatures);
    }

    fn clearInlayHints(self: *EditorLSP) void {
        for (self.inlay_hints.items) |hint| {
            self.freeInlayHint(hint);
        }
        self.inlay_hints.clearRetainingCapacity();
    }

    fn freeInlayHint(self: *EditorLSP, hint: InlayHint) void {
        self.allocator.free(hint.label);
        if (hint.tooltip) |tip| self.allocator.free(tip);
    }

    fn clearSelectionRanges(self: *EditorLSP) void {
        for (self.selection_ranges.items) |_| {
            // SelectionRange only contains stack values, no heap allocations
        }
        self.selection_ranges.clearRetainingCapacity();
    }

    fn clearCodeActions(self: *EditorLSP) void {
        for (self.code_actions.items) |action| {
            self.freeCodeAction(action);
        }
        self.code_actions.clearRetainingCapacity();
    }

    fn freeCodeAction(self: *EditorLSP, action: CodeAction) void {
        self.allocator.free(action.title);
        self.allocator.free(action.kind);
        if (action.edit) |edit| {
            // Need to make a mutable copy to deinit the HashMap
            var mutable_edit = edit;
            var iter = mutable_edit.changes.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                for (entry.value_ptr.*) |text_edit| {
                    self.allocator.free(text_edit.new_text);
                }
                self.allocator.free(entry.value_ptr.*);
            }
            mutable_edit.changes.deinit();
        }
    }

    fn extractDocumentationText(node: std.json.Value) ?[]const u8 {
        return switch (node) {
            .string => node.string,
            .object => if (node.object.get("value")) |value_node|
                if (value_node == .string) value_node.string else null
            else
                null,
            else => null,
        };
    }

    fn extractInsertText(node: std.json.Value) ?[]const u8 {
        if (node != .object) return null;
        const obj = node.object;

        if (obj.get("insertText")) |insert_node| {
            if (insert_node == .string) return insert_node.string;
        }

        if (obj.get("textEdit")) |edit_node| {
            if (edit_node == .object) {
                if (edit_node.object.get("newText")) |text_node| {
                    if (text_node == .string) return text_node.string;
                }
            }
        }

        return null;
    }

    fn parseRange(node: std.json.Value) ?Diagnostic.Range {
        if (node != .object) return null;
        const obj = node.object;
        const start_node = obj.get("start") orelse return null;
        const end_node = obj.get("end") orelse return null;
        if (start_node != .object or end_node != .object) return null;

        return Diagnostic.Range{
            .start = parsePosition(start_node),
            .end = parsePosition(end_node),
        };
    }

    fn parseTextEdit(self: *EditorLSP, node: std.json.Value) std.mem.Allocator.Error!?Completion.TextEdit {
        if (node != .object) return null;
        const obj = node.object;

        const range_node = obj.get("range") orelse return null;
        const range = parseRange(range_node) orelse return null;

        const new_text_node = obj.get("newText") orelse return null;
        if (new_text_node != .string) return null;

        const duped = try self.allocator.dupe(u8, new_text_node.string);
        return Completion.TextEdit{ .range = range, .new_text = duped };
    }

    fn parseCompletionItem(self: *EditorLSP, node: std.json.Value) ?Completion {
        if (node != .object) return null;
        const obj = node.object;
        const label_node = obj.get("label") orelse return null;
        if (label_node != .string) return null;

        const label = self.allocator.dupe(u8, label_node.string) catch |err| {
            std.log.warn("Failed to duplicate completion label: {}", .{err});
            return null;
        };

        var completion = Completion{
            .label = label,
            .kind = .text,
            .detail = null,
            .documentation = null,
            .insert_text = null,
            .text_edit = null,
            .insert_text_format = .plain_text,
        };

        if (obj.get("kind")) |kind_node| {
            if (kind_node == .integer and kind_node.integer >= 1 and kind_node.integer <= 18) {
                const tag_value = @as(u8, @intCast(kind_node.integer));
                const maybe_kind = std.meta.intToEnum(Completion.CompletionKind, tag_value) catch null;
                if (maybe_kind) |resolved| completion.kind = resolved;
            }
        }

        if (obj.get("insertTextFormat")) |format_node| {
            if (format_node == .integer and format_node.integer >= 1 and format_node.integer <= 2) {
                const format_value = @as(u8, @intCast(format_node.integer));
                if (std.meta.intToEnum(Completion.InsertTextFormat, format_value) catch null) |fmt| {
                    completion.insert_text_format = fmt;
                }
            }
        }

        if (obj.get("detail")) |detail_node| {
            if (detail_node == .string) {
                completion.detail = self.allocator.dupe(u8, detail_node.string) catch |err| {
                    std.log.warn("Failed to duplicate completion detail: {}", .{err});
                    self.freeCompletion(completion);
                    return null;
                };
            }
        }

        if (obj.get("documentation")) |doc_node| {
            if (extractDocumentationText(doc_node)) |doc_text| {
                completion.documentation = self.allocator.dupe(u8, doc_text) catch |err| {
                    std.log.warn("Failed to duplicate completion documentation: {}", .{err});
                    self.freeCompletion(completion);
                    return null;
                };
            }
        }

        if (extractInsertText(node)) |insert_text| {
            completion.insert_text = self.allocator.dupe(u8, insert_text) catch |err| {
                std.log.warn("Failed to duplicate completion insert text: {}", .{err});
                self.freeCompletion(completion);
                return null;
            };
        }

        if (obj.get("textEdit")) |text_edit_node| {
            const edit = self.parseTextEdit(text_edit_node) catch |err| {
                std.log.warn("Failed to parse completion text edit: {}", .{err});
                self.freeCompletion(completion);
                return null;
            };
            if (edit) |owned_edit| {
                completion.text_edit = owned_edit;
            }
        }

        return completion;
    }

    fn storeCompletionsFromValue(self: *EditorLSP, value: std.json.Value) std.mem.Allocator.Error!void {
        const items_node = switch (value) {
            .array => value,
            .object => value.object.get("items") orelse {
                self.clearCompletions();
                return;
            },
            else => {
                self.clearCompletions();
                return;
            },
        };

        if (items_node != .array) {
            self.clearCompletions();
            return;
        }

        self.clearCompletions();

        for (items_node.array.items) |item_node| {
            if (item_node != .object) continue;
            if (self.parseCompletionItem(item_node)) |completion| {
                self.completions.append(self.allocator, completion) catch |err| {
                    self.freeCompletion(completion);
                    return err;
                };
            }
        }

        self.bumpCompletionGeneration();
    }

    pub fn offsetFromPosition(self: *EditorLSP, line: u32, character: u32) usize {
        return self.positionToOffset(.{ .line = line, .character = character });
    }

    fn getOrStartServer(self: *EditorLSP, language: syntax.Language, document_path: []const u8) !*lsp.LanguageServer {
        const lang_str = @tagName(language);

        if (self.server_registry.getServer(lang_str)) |server| {
            self.configureServer(server);
            return server;
        }

        const command = self.getServerCommand(language) orelse return error.ServerNotAvailable;

        const root_path = try self.detectWorkspaceRoot(document_path);
        const root_uri = try self.pathToUri(root_path);
        self.allocator.free(root_path);

        errdefer self.allocator.free(root_uri);

        const config = lsp.LanguageServer.ServerConfig{
            .command = command,
            .root_uri = root_uri,
            .initialization_options = null,
            .env = null,
        };

        const server = try self.server_registry.startServer(lang_str, config);
        self.configureServer(server);
        self.allocator.free(root_uri);
        return server;
    }

    fn getServerCommand(self: *EditorLSP, language: syntax.Language) ?[]const []const u8 {
        _ = self;
        return switch (language) {
            .zig => &[_][]const u8{ "zls", "--enable-debug-log" },
            .rust => &[_][]const u8{"rust-analyzer"},
            .javascript, .typescript => &[_][]const u8{ "typescript-language-server", "--stdio" },
            .python => &[_][]const u8{"pylsp"},
            .c, .cpp => &[_][]const u8{"clangd"},
            .ghostlang => &[_][]const u8{"ghostls"}, // ghostls v0.3.0 LSP server
            else => null,
        };
    }

    fn detectWorkspaceRoot(self: *EditorLSP, file_path: []const u8) ![]u8 {
        const absolute_path = try self.makeAbsolutePath(file_path);
        defer self.allocator.free(absolute_path);

        const start_dir = std.fs.path.dirname(absolute_path) orelse absolute_path;
        var current = try self.allocator.dupe(u8, start_dir);
        errdefer self.allocator.free(current);

        while (true) {
            if (directoryHasRootMarker(current)) {
                return current;
            }

            const parent_slice = std.fs.path.dirname(current) orelse break;
            if (parent_slice.len == 0 or std.mem.eql(u8, parent_slice, current)) break;

            const parent_owned = self.allocator.dupe(u8, parent_slice) catch break;
            self.allocator.free(current);
            current = parent_owned;
        }

        return current;
    }

    fn makeAbsolutePath(self: *EditorLSP, path: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(path)) {
            return try self.allocator.dupe(u8, path);
        }

        const cwd = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd);
        return try std.fs.path.join(self.allocator, &[_][]const u8{ cwd, path });
    }

    fn directoryHasRootMarker(dir_path: []const u8) bool {
        var dir = std.fs.openDirAbsolute(dir_path, .{}) catch return false;
        defer dir.close();

        const markers = workspaceMarkers();
        for (markers) |marker| {
            if (dir.statFile(marker)) |_| {
                return true;
            } else |_| {}
        }
        return false;
    }

    fn workspaceMarkers() []const []const u8 {
        return &[_][]const u8{
            "grim.json",
            ".grim-root",
            ".git",
            ".hg",
            ".svn",
            "Cargo.toml",
            "package.json",
            "pnpm-workspace.yaml",
            "yarn.lock",
            "pyproject.toml",
            "requirements.txt",
            "go.mod",
            "build.zig",
            "Makefile",
            "CMakeLists.txt",
            "composer.json",
            "Gemfile",
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

    fn findDocumentIndex(self: *EditorLSP, path: []const u8) ?usize {
        for (self.documents.items, 0..) |doc, idx| {
            if (std.mem.eql(u8, doc.path, path)) return idx;
        }
        return null;
    }

    fn getDocument(self: *EditorLSP, path: []const u8) ?*DocumentEntry {
        if (self.findDocumentIndex(path)) |idx| {
            return &self.documents.items[idx];
        }
        return null;
    }

    fn trackDocument(self: *EditorLSP, path: []const u8, language: syntax.Language, version: u32) !void {
        if (self.findDocumentIndex(path)) |idx| {
            var entry = &self.documents.items[idx];
            entry.language = language;
            entry.version = version;
            return;
        }

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        try self.documents.append(self.allocator, .{
            .path = owned_path,
            .language = language,
            .version = version,
        });
    }

    fn removeDocumentAt(self: *EditorLSP, idx: usize) void {
        const removed = self.documents.orderedRemove(idx);
        self.allocator.free(removed.path);
    }

    fn configureServer(self: *EditorLSP, server: *lsp.LanguageServer) void {
        server.setDiagnosticsSink(.{
            .ctx = @as(*anyopaque, @ptrCast(&self.diagnostics_sink)),
            .handleFn = DiagnosticsSink.handle,
        });
        server.setResponseCallback(.{
            .ctx = @as(*anyopaque, @ptrCast(self)),
            .onHover = handleHoverCallback,
            .onDefinition = handleDefinitionCallback,
            .onCompletion = handleCompletionCallback,
            .onSignatureHelp = handleSignatureHelpCallback,
            .onInlayHints = handleInlayHintsCallback,
            .onSelectionRange = handleSelectionRangeCallback,
            .onCodeActions = handleCodeActionsCallback,
        });
    }

    fn updateHoverInfo(self: *EditorLSP, contents: []const u8) void {
        if (self.hover_info) |existing| {
            self.allocator.free(existing);
            self.hover_info = null;
        }

        if (contents.len == 0) return;

        const duped = self.allocator.dupe(u8, contents) catch |err| {
            std.log.warn("Failed to store hover info: {}", .{err});
            return;
        };
        self.hover_info = duped;
    }

    fn uriToPath(self: *EditorLSP, uri: []const u8) ![]u8 {
        if (std.mem.startsWith(u8, uri, "file://")) {
            return try self.allocator.dupe(u8, uri[7..]);
        }
        return try self.allocator.dupe(u8, uri);
    }

    fn storeDefinitionResult(self: *EditorLSP, uri: []const u8, line: u32, character: u32) void {
        if (self.pending_definition) |existing| {
            self.allocator.free(existing.path);
            self.pending_definition = null;
        }

        const path = self.uriToPath(uri) catch |err| {
            std.log.warn("Failed to decode definition URI: {}", .{err});
            return;
        };

        self.pending_definition = .{
            .path = path,
            .line = line,
            .character = character,
        };
    }

    fn handleHoverCallback(ctx: *anyopaque, response: lsp.HoverResponse) void {
        const self = @as(*EditorLSP, @ptrCast(@alignCast(ctx)));
        self.updateHoverInfo(response.contents);
    }

    fn handleDefinitionCallback(ctx: *anyopaque, response: lsp.DefinitionResponse) void {
        const self = @as(*EditorLSP, @ptrCast(@alignCast(ctx)));
        if (response.uri.len == 0) {
            if (self.pending_definition) |existing| {
                self.allocator.free(existing.path);
                self.pending_definition = null;
            }
            return;
        }
        self.storeDefinitionResult(response.uri, response.line, response.character);
    }

    fn handleCompletionCallback(ctx: *anyopaque, response: lsp.CompletionResponse) void {
        const self = @as(*EditorLSP, @ptrCast(@alignCast(ctx)));
        self.processCompletionResponse(response) catch |err| {
            std.log.warn("Failed to process completion response: {}", .{err});
        };
    }

    fn handleSignatureHelpCallback(ctx: *anyopaque, response: lsp.SignatureHelpResponse) void {
        const self = @as(*EditorLSP, @ptrCast(@alignCast(ctx)));
        self.storeSignatureHelp(response.result) catch |err| {
            std.log.warn("Failed to process signature help response: {}", .{err});
        };
    }

    fn handleInlayHintsCallback(ctx: *anyopaque, response: lsp.InlayHintsResponse) void {
        const self = @as(*EditorLSP, @ptrCast(@alignCast(ctx)));
        self.storeInlayHints(response.result) catch |err| {
            std.log.warn("Failed to process inlay hints response: {}", .{err});
        };
    }

    fn handleSelectionRangeCallback(ctx: *anyopaque, response: lsp.SelectionRangeResponse) void {
        const self = @as(*EditorLSP, @ptrCast(@alignCast(ctx)));
        self.storeSelectionRanges(response.result) catch |err| {
            std.log.warn("Failed to process selection range response: {}", .{err});
        };
    }

    fn handleCodeActionsCallback(ctx: *anyopaque, response: lsp.CodeActionsResponse) void {
        const self = @as(*EditorLSP, @ptrCast(@alignCast(ctx)));
        self.storeCodeActions(response.result) catch |err| {
            std.log.warn("Failed to process code actions response: {}", .{err});
        };
    }

    fn processCompletionResponse(self: *EditorLSP, response: lsp.CompletionResponse) std.mem.Allocator.Error!void {
        const pending = self.pending_completion orelse return;
        if (pending != response.request_id) return;

        defer self.pending_completion = null;
        try self.storeCompletionsFromValue(response.result);
    }

    // Ghostls v0.3.0 response parsers
    fn storeSignatureHelp(self: *EditorLSP, value: std.json.Value) !void {
        self.clearSignatureHelp();

        if (value != .object) return;
        const obj = value.object;

        const sigs_node = obj.get("signatures") orelse return;
        if (sigs_node != .array) return;

        const active_sig = if (obj.get("activeSignature")) |node|
            if (node == .integer) @as(u32, @intCast(@max(0, @min(node.integer, std.math.maxInt(u32))))) else 0
        else 0;

        const active_param = if (obj.get("activeParameter")) |node|
            if (node == .integer) @as(u32, @intCast(@max(0, @min(node.integer, std.math.maxInt(u32))))) else 0
        else 0;

        var signatures = std.ArrayList(SignatureHelp.SignatureInfo){};
        defer signatures.deinit(self.allocator);

        for (sigs_node.array.items) |sig_node| {
            if (sig_node != .object) continue;
            const sig_obj = sig_node.object;

            const label_node = sig_obj.get("label") orelse continue;
            if (label_node != .string) continue;

            const label = try self.allocator.dupe(u8, label_node.string);
            errdefer self.allocator.free(label);

            const doc = if (sig_obj.get("documentation")) |doc_node|
                if (extractDocumentationText(doc_node)) |text|
                    try self.allocator.dupe(u8, text)
                else null
            else null;

            var params = std.ArrayList(SignatureHelp.SignatureInfo.ParameterInfo){};
            defer params.deinit(self.allocator);

            if (sig_obj.get("parameters")) |params_node| {
                if (params_node == .array) {
                    for (params_node.array.items) |param_node| {
                        if (param_node != .object) continue;
                        const param_obj = param_node.object;

                        const param_label_node = param_obj.get("label") orelse continue;
                        const param_label = if (param_label_node == .string)
                            try self.allocator.dupe(u8, param_label_node.string)
                        else continue;
                        errdefer self.allocator.free(param_label);

                        const param_doc = if (param_obj.get("documentation")) |pdoc_node|
                            if (extractDocumentationText(pdoc_node)) |ptext|
                                try self.allocator.dupe(u8, ptext)
                            else null
                        else null;

                        try params.append(self.allocator, .{
                            .label = param_label,
                            .documentation = param_doc,
                        });
                    }
                }
            }

            try signatures.append(self.allocator, .{
                .label = label,
                .documentation = doc,
                .parameters = try params.toOwnedSlice(self.allocator),
            });
        }

        if (signatures.items.len > 0) {
            self.signature_help = .{
                .active_signature = active_sig,
                .active_parameter = active_param,
                .signatures = try signatures.toOwnedSlice(self.allocator),
            };
        }
    }

    fn storeInlayHints(self: *EditorLSP, value: std.json.Value) !void {
        self.clearInlayHints();

        if (value != .array) return;

        for (value.array.items) |hint_node| {
            if (hint_node != .object) continue;
            const hint_obj = hint_node.object;

            const pos_node = hint_obj.get("position") orelse continue;
            const position = parsePosition(pos_node);

            const label_node = hint_obj.get("label") orelse continue;
            if (label_node != .string) continue;
            const label = try self.allocator.dupe(u8, label_node.string);
            errdefer self.allocator.free(label);

            const kind: InlayHint.HintKind = if (hint_obj.get("kind")) |kind_node|
                if (kind_node == .integer)
                    if (kind_node.integer == 1) .type else .parameter
                else .type
            else .type;

            const tooltip = if (hint_obj.get("tooltip")) |tip_node|
                if (tip_node == .string)
                    try self.allocator.dupe(u8, tip_node.string)
                else null
            else null;

            try self.inlay_hints.append(self.allocator, .{
                .position = position,
                .label = label,
                .kind = kind,
                .tooltip = tooltip,
            });
        }
    }

    fn storeSelectionRanges(self: *EditorLSP, value: std.json.Value) !void {
        self.clearSelectionRanges();

        if (value != .object) return;
        const obj = value.object;

        const range_node = obj.get("range") orelse return;
        const range = parseRange(range_node) orelse return;

        try self.selection_ranges.append(self.allocator, .{
            .range = range,
            .parent = null, // Note: parent parsing would require recursive structure
        });
    }

    fn storeCodeActions(self: *EditorLSP, value: std.json.Value) !void {
        self.clearCodeActions();

        if (value != .array) return;

        for (value.array.items) |action_node| {
            if (action_node != .object) continue;
            const action_obj = action_node.object;

            const title_node = action_obj.get("title") orelse continue;
            if (title_node != .string) continue;
            const title = try self.allocator.dupe(u8, title_node.string);
            errdefer self.allocator.free(title);

            const kind_node = action_obj.get("kind") orelse {
                self.allocator.free(title);
                continue;
            };
            if (kind_node != .string) {
                self.allocator.free(title);
                continue;
            }
            const kind = try self.allocator.dupe(u8, kind_node.string);
            errdefer self.allocator.free(kind);

            const is_preferred = if (action_obj.get("isPreferred")) |pref_node|
                if (pref_node == .bool) pref_node.bool else false
            else false;

            const edit: ?CodeAction.WorkspaceEdit = null; // Simplified: full edit parsing is complex

            try self.code_actions.append(self.allocator, .{
                .title = title,
                .kind = kind,
                .is_preferred = is_preferred,
                .edit = edit,
            });
        }
    }

    // Diagnostic rendering utilities
    pub fn renderDiagnostics(self: *EditorLSP, path: []const u8, start_line: u32, end_line: u32) ![]DiagnosticRender {
        const diagnostics = self.getDiagnostics(path) orelse return &[_]DiagnosticRender{};

        var renders = try std.ArrayList(DiagnosticRender).initCapacity(self.allocator, 0);
        errdefer renders.deinit();

        for (diagnostics) |diag| {
            if (diag.range.start.line >= start_line and diag.range.start.line <= end_line) {
                try renders.append(self.allocator, .{
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

        var filtered = try std.ArrayList(Completion).initCapacity(allocator, 0);
        errdefer filtered.deinit(allocator);

        for (self.completions.items) |comp| {
            if (std.mem.startsWith(u8, comp.label, prefix)) {
                try filtered.append(allocator, comp);
            }
        }

        return filtered.toOwnedSlice(allocator);
    }
};

// LSP diagnostics sink for handling server messages
pub const DiagnosticsSink = struct {
    editor_lsp: *EditorLSP,

    pub fn init(editor_lsp: *EditorLSP) DiagnosticsSink {
        return .{ .editor_lsp = editor_lsp };
    }

    pub fn handle(ctx: *anyopaque, params: std.json.Value) std.mem.Allocator.Error!void {
        const self = @as(*DiagnosticsSink, @ptrCast(@alignCast(ctx)));
        try self.editor_lsp.handlePublishDiagnostics(params);
    }
};

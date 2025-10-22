// ai/context.zig
// Context gathering for AI completions - collects relevant editor state
// Provides buffer content, LSP diagnostics, git status, etc.

const std = @import("std");
const core = @import("core");

pub const ContextType = enum {
    buffer,
    selection,
    diagnostics,
    git_status,
    project_files,
    lsp_symbols,
};

pub const BufferContext = struct {
    file_path: ?[]const u8 = null,
    language: ?[]const u8 = null,
    content: []const u8,
    cursor_line: usize,
    cursor_col: usize,
    total_lines: usize,
};

pub const SelectionContext = struct {
    start_line: usize,
    start_col: usize,
    end_line: usize,
    end_col: usize,
    content: []const u8,
};

pub const DiagnosticContext = struct {
    severity: Severity,
    line: usize,
    col: usize,
    message: []const u8,
    source: ?[]const u8 = null,

    pub const Severity = enum {
        error_,
        warning,
        info,
        hint,
    };
};

pub const GitContext = struct {
    branch: ?[]const u8 = null,
    status: Status = .clean,
    uncommitted_files: []const []const u8,
    current_diff: ?[]const u8 = null,

    pub const Status = enum {
        clean,
        modified,
        staged,
        conflict,
    };
};

pub const ProjectContext = struct {
    root_path: []const u8,
    open_files: []const []const u8,
    file_count: usize,
};

/// Main context gathering interface
pub const Context = struct {
    allocator: std.mem.Allocator,
    buffer: ?BufferContext = null,
    selection: ?SelectionContext = null,
    diagnostics: std.ArrayList(DiagnosticContext),
    git: ?GitContext = null,
    project: ?ProjectContext = null,

    pub fn init(allocator: std.mem.Allocator) Context {
        return Context{
            .allocator = allocator,
            .diagnostics = std.ArrayList(DiagnosticContext){},
        };
    }

    pub fn deinit(self: *Context) void {
        // Free diagnostics
        for (self.diagnostics.items) |diag| {
            if (diag.message.len > 0) {
                self.allocator.free(diag.message);
            }
            if (diag.source) |src| {
                self.allocator.free(src);
            }
        }
        self.diagnostics.deinit(self.allocator);

        // Free buffer context
        if (self.buffer) |buf| {
            if (buf.content.len > 0) self.allocator.free(buf.content);
            if (buf.file_path) |path| self.allocator.free(path);
            if (buf.language) |lang| self.allocator.free(lang);
        }

        // Free selection context
        if (self.selection) |sel| {
            if (sel.content.len > 0) self.allocator.free(sel.content);
        }

        // Free git context
        if (self.git) |git| {
            if (git.branch) |branch| self.allocator.free(branch);
            if (git.current_diff) |diff| self.allocator.free(diff);
            for (git.uncommitted_files) |file| {
                self.allocator.free(file);
            }
            if (git.uncommitted_files.len > 0) {
                self.allocator.free(git.uncommitted_files);
            }
        }

        // Free project context
        if (self.project) |proj| {
            self.allocator.free(proj.root_path);
            for (proj.open_files) |file| {
                self.allocator.free(file);
            }
            if (proj.open_files.len > 0) {
                self.allocator.free(proj.open_files);
            }
        }
    }

    /// Gather buffer context from current editor state
    /// Expects buffer to have: .getContent(), .getCursorLine(), .getCursorCol(), .getFilePath(), .getLanguage()
    pub fn gatherBuffer(self: *Context, buffer: anytype) !void {
        const T = @TypeOf(buffer);

        // Get buffer content
        const content = if (@hasDecl(T, "getContent"))
            try buffer.getContent(self.allocator)
        else if (@hasDecl(T, "content"))
            try self.allocator.dupe(u8, buffer.content)
        else
            unreachable;

        // Get cursor position
        const cursor_line = if (@hasDecl(T, "getCursorLine"))
            buffer.getCursorLine()
        else if (@hasDecl(T, "cursor_line"))
            buffer.cursor_line
        else
            0;

        const cursor_col = if (@hasDecl(T, "getCursorCol"))
            buffer.getCursorCol()
        else if (@hasDecl(T, "cursor_col"))
            buffer.cursor_col
        else
            0;

        // Get file path (optional)
        const file_path = if (@hasDecl(T, "getFilePath"))
            try self.allocator.dupe(u8, buffer.getFilePath() orelse "")
        else if (@hasDecl(T, "file_path"))
            try self.allocator.dupe(u8, buffer.file_path orelse "")
        else
            null;

        // Get language (optional)
        const language = if (@hasDecl(T, "getLanguage"))
            try self.allocator.dupe(u8, buffer.getLanguage() orelse "")
        else if (@hasDecl(T, "language"))
            try self.allocator.dupe(u8, buffer.language orelse "")
        else
            null;

        // Count lines
        const total_lines = std.mem.count(u8, content, "\n") + 1;

        self.buffer = BufferContext{
            .file_path = file_path,
            .language = language,
            .content = content,
            .cursor_line = cursor_line,
            .cursor_col = cursor_col,
            .total_lines = total_lines,
        };
    }

    /// Gather selection context if text is selected
    /// Expects selection to have: .getContent(), .start_line, .start_col, .end_line, .end_col
    pub fn gatherSelection(self: *Context, selection: anytype) !void {
        const T = @TypeOf(selection);

        // Get selection content
        const content = if (@hasDecl(T, "getContent"))
            try selection.getContent(self.allocator)
        else if (@hasDecl(T, "content"))
            try self.allocator.dupe(u8, selection.content)
        else
            return; // No selection

        // Get selection bounds
        const start_line = if (@hasDecl(T, "start_line"))
            selection.start_line
        else
            0;

        const start_col = if (@hasDecl(T, "start_col"))
            selection.start_col
        else
            0;

        const end_line = if (@hasDecl(T, "end_line"))
            selection.end_line
        else
            start_line;

        const end_col = if (@hasDecl(T, "end_col"))
            selection.end_col
        else
            content.len;

        self.selection = SelectionContext{
            .start_line = start_line,
            .start_col = start_col,
            .end_line = end_line,
            .end_col = end_col,
            .content = content,
        };
    }

    /// Gather LSP diagnostics for current buffer
    /// Expects lsp_client to have: .getDiagnostics() or .diagnostics field
    pub fn gatherDiagnostics(self: *Context, lsp_client: anytype) !void {
        const T = @TypeOf(lsp_client);

        // Get diagnostics list
        const diagnostics = if (@hasDecl(T, "getDiagnostics"))
            try lsp_client.getDiagnostics()
        else if (@hasDecl(T, "diagnostics"))
            lsp_client.diagnostics
        else
            return; // No diagnostics available

        // Convert to our format
        for (diagnostics) |diag| {
            const severity: DiagnosticContext.Severity = if (@hasDecl(@TypeOf(diag), "severity"))
                switch (diag.severity) {
                    1 => .error_,
                    2 => .warning,
                    3 => .info,
                    4 => .hint,
                    else => .info,
                }
            else
                .info;

            const line = if (@hasDecl(@TypeOf(diag), "line"))
                diag.line
            else if (@hasDecl(@TypeOf(diag), "range"))
                diag.range.start.line
            else
                0;

            const col = if (@hasDecl(@TypeOf(diag), "col"))
                diag.col
            else if (@hasDecl(@TypeOf(diag), "range"))
                diag.range.start.character
            else
                0;

            const message = if (@hasDecl(@TypeOf(diag), "message"))
                try self.allocator.dupe(u8, diag.message)
            else
                try self.allocator.dupe(u8, "Unknown diagnostic");

            const source = if (@hasDecl(@TypeOf(diag), "source"))
                if (diag.source) |src| try self.allocator.dupe(u8, src) else null
            else
                null;

            try self.diagnostics.append(self.allocator, .{
                .severity = severity,
                .line = line,
                .col = col,
                .message = message,
                .source = source,
            });
        }
    }

    /// Gather git status for current buffer/project
    /// Expects git_client to be core.Git from grim/core/git.zig or compatible
    pub fn gatherGit(self: *Context, git_client: anytype) !void {
        const T = @TypeOf(git_client);

        // Get current branch
        const branch = if (@hasDecl(T, "current_branch"))
            if (git_client.current_branch) |b|
                try self.allocator.dupe(u8, b)
            else
                null
        else
            null;

        // Get status
        const status: GitContext.Status = blk: {
            if (@hasDecl(T, "status_cache")) {
                var iter = git_client.status_cache.iterator();
                var has_modified = false;
                var has_staged = false;
                const has_conflict = false;

                while (iter.next()) |entry| {
                    const file_status = entry.value_ptr.*;
                    switch (file_status) {
                        .modified => has_modified = true,
                        .added => has_staged = true,
                        .deleted => has_modified = true,
                        .renamed => has_modified = true,
                        else => {},
                    }
                }

                if (has_conflict) break :blk .conflict;
                if (has_staged) break :blk .staged;
                if (has_modified) break :blk .modified;
            }
            break :blk .clean;
        };

        // Get uncommitted files list
        var uncommitted = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (uncommitted.items) |file| {
                self.allocator.free(file);
            }
            uncommitted.deinit();
        }

        if (@hasDecl(T, "status_cache")) {
            var iter = git_client.status_cache.iterator();
            while (iter.next()) |entry| {
                const file_status = entry.value_ptr.*;
                if (file_status != .unmodified) {
                    try uncommitted.append(try self.allocator.dupe(u8, entry.key_ptr.*));
                }
            }
        }

        self.git = GitContext{
            .branch = branch,
            .status = status,
            .uncommitted_files = try uncommitted.toOwnedSlice(),
            .current_diff = null, // TODO: Get diff from git client
        };
    }

    /// Gather project structure information
    /// Expects project to have: .root_path, .getOpenFiles() or .open_files, .file_count
    pub fn gatherProject(self: *Context, project: anytype) !void {
        const T = @TypeOf(project);

        // Get root path
        const root_path = if (@hasDecl(T, "root_path"))
            try self.allocator.dupe(u8, project.root_path)
        else if (@hasDecl(T, "getRootPath"))
            try self.allocator.dupe(u8, project.getRootPath())
        else
            try self.allocator.dupe(u8, ".");

        // Get open files
        var open_files = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (open_files.items) |file| {
                self.allocator.free(file);
            }
            open_files.deinit();
        }

        if (@hasDecl(T, "getOpenFiles")) {
            const files = try project.getOpenFiles();
            for (files) |file| {
                try open_files.append(try self.allocator.dupe(u8, file));
            }
        } else if (@hasDecl(T, "open_files")) {
            for (project.open_files) |file| {
                try open_files.append(try self.allocator.dupe(u8, file));
            }
        }

        const file_count = if (@hasDecl(T, "file_count"))
            project.file_count
        else if (@hasDecl(T, "getFileCount"))
            project.getFileCount()
        else
            open_files.items.len;

        self.project = ProjectContext{
            .root_path = root_path,
            .open_files = try open_files.toOwnedSlice(),
            .file_count = file_count,
        };
    }

    /// Format context into a system message for AI
    pub fn toSystemMessage(self: *Context) ![]const u8 {
        var message = std.ArrayList(u8).init(self.allocator);
        defer message.deinit();

       const writer = message.writer();

        // Add buffer context
        if (self.buffer) |buf| {
            try writer.print("# Current Buffer\n", .{});
            if (buf.file_path) |path| {
                try writer.print("File: {s}\n", .{path});
            }
            if (buf.language) |lang| {
                try writer.print("Language: {s}\n", .{lang});
            }
            try writer.print("Cursor: Line {}, Col {}\n", .{ buf.cursor_line, buf.cursor_col });
            try writer.print("\n```\n{s}\n```\n\n", .{buf.content});
        }

        // Add selection context
        if (self.selection) |sel| {
            try writer.print("# Selected Text\n", .{});
            try writer.print("Lines {}-{}\n", .{ sel.start_line, sel.end_line });
            try writer.print("```\n{s}\n```\n\n", .{sel.content});
        }

        // Add diagnostics
        if (self.diagnostics.items.len > 0) {
            try writer.print("# Diagnostics\n", .{});
            for (self.diagnostics.items) |diag| {
                const severity = switch (diag.severity) {
                    .error_ => "ERROR",
                    .warning => "WARN",
                    .info => "INFO",
                    .hint => "HINT",
                };
                try writer.print("[{s}] Line {}: {s}\n", .{
                    severity,
                    diag.line,
                    diag.message,
                });
            }
            try writer.print("\n", .{});
        }

        // Add git context
        if (self.git) |git| {
            try writer.print("# Git Status\n", .{});
            if (git.branch) |branch| {
                try writer.print("Branch: {s}\n", .{branch});
            }
            try writer.print("Status: {s}\n", .{@tagName(git.status)});
            if (git.uncommitted_files.len > 0) {
                try writer.print("Uncommitted files: {}\n", .{git.uncommitted_files.len});
            }
            try writer.print("\n", .{});
        }

        return try message.toOwnedSlice();
    }

    /// Format context into user message (for specific requests)
    pub fn toUserMessage(self: *Context, prompt: []const u8) ![]const u8 {
        var message = std.ArrayList(u8).init(self.allocator);
        defer message.deinit();

        const writer = message.writer();

        // Include the user's prompt
        try writer.print("{s}\n\n", .{prompt});

        // Add relevant context snippets
        if (self.selection) |sel| {
            try writer.print("Selected code:\n```\n{s}\n```\n", .{sel.content});
        } else if (self.buffer) |buf| {
            // Include a snippet around cursor if no selection
            const start_line = if (buf.cursor_line > 5) buf.cursor_line - 5 else 0;
            const end_line = @min(buf.cursor_line + 5, buf.total_lines);

            // TODO: Extract specific lines from buffer content
            try writer.print("Code context (lines {}-{}):\n```\n{s}\n```\n", .{ start_line, end_line, buf.content });
        }

        return try message.toOwnedSlice();
    }
};

/// Helper to create minimal buffer context for testing
pub fn createBufferContext(
    allocator: std.mem.Allocator,
    content: []const u8,
    cursor_line: usize,
    cursor_col: usize,
) !BufferContext {
    const lines = std.mem.count(u8, content, "\n") + 1;

    return BufferContext{
        .content = try allocator.dupe(u8, content),
        .cursor_line = cursor_line,
        .cursor_col = cursor_col,
        .total_lines = lines,
    };
}

/// Helper to create selection context
pub fn createSelectionContext(
    allocator: std.mem.Allocator,
    content: []const u8,
    start_line: usize,
    start_col: usize,
    end_line: usize,
    end_col: usize,
) !SelectionContext {
    return SelectionContext{
        .start_line = start_line,
        .start_col = start_col,
        .end_line = end_line,
        .end_col = end_col,
        .content = try allocator.dupe(u8, content),
    };
}

test "Context init/deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try testing.expect(ctx.diagnostics.items.len == 0);
    try testing.expect(ctx.buffer == null);
}

test "toSystemMessage with buffer" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    // Add buffer context
    ctx.buffer = try createBufferContext(
        allocator,
        "fn main() {\n    // TODO\n}",
        1,
        4,
    );

    const message = try ctx.toSystemMessage();
    defer allocator.free(message);

    try testing.expect(std.mem.indexOf(u8, message, "Current Buffer") != null);
    try testing.expect(std.mem.indexOf(u8, message, "fn main()") != null);
    try testing.expect(std.mem.indexOf(u8, message, "Line 1, Col 4") != null);
}

test "toSystemMessage with diagnostics" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    // Add a diagnostic
    try ctx.diagnostics.append(allocator, .{
        .severity = .error_,
        .line = 10,
        .col = 5,
        .message = try allocator.dupe(u8, "undefined variable 'foo'"),
    });

    const message = try ctx.toSystemMessage();
    defer allocator.free(message);

    try testing.expect(std.mem.indexOf(u8, message, "Diagnostics") != null);
    try testing.expect(std.mem.indexOf(u8, message, "ERROR") != null);
    try testing.expect(std.mem.indexOf(u8, message, "undefined variable") != null);
}

test "createBufferContext" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const buf = try createBufferContext(
        allocator,
        "line 1\nline 2\nline 3",
        1,
        3,
    );
    defer allocator.free(buf.content);

    try testing.expect(buf.total_lines == 3);
    try testing.expect(buf.cursor_line == 1);
    try testing.expect(buf.cursor_col == 3);
}

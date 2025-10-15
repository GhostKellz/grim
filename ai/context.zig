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
            .diagnostics = std.ArrayList(DiagnosticContext).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.diagnostics.deinit();
        // TODO: Free allocated strings in contexts
    }

    /// Gather buffer context from current editor state
    pub fn gatherBuffer(self: *Context, buffer: anytype) !void {
        // TODO: Extract buffer information
        // This will integrate with grim's buffer system
        _ = self;
        _ = buffer;
    }

    /// Gather selection context if text is selected
    pub fn gatherSelection(self: *Context, selection: anytype) !void {
        // TODO: Extract selection information
        _ = self;
        _ = selection;
    }

    /// Gather LSP diagnostics for current buffer
    pub fn gatherDiagnostics(self: *Context, lsp_client: anytype) !void {
        // TODO: Query LSP for diagnostics
        _ = self;
        _ = lsp_client;
    }

    /// Gather git status for current buffer/project
    pub fn gatherGit(self: *Context, git_client: anytype) !void {
        // TODO: Query git status
        _ = self;
        _ = git_client;
    }

    /// Gather project structure information
    pub fn gatherProject(self: *Context, project: anytype) !void {
        // TODO: Collect project metadata
        _ = self;
        _ = project;
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

            try writer.print("Code context (lines {}-{}):\n```\n", .{ start_line, end_line });

            // TODO: Extract specific lines from buffer content
            _ = start_line;
            _ = end_line;

            try writer.print("{s}\n```\n", .{buf.content});
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
    try ctx.diagnostics.append(.{
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

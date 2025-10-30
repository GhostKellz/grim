//! Advanced Git Integration for Grim
//!
//! Features:
//! - Interactive staging (stage hunks, not just files)
//! - Commit history browser
//! - Branch management (create, switch, merge)
//! - Rebase interactive
//! - Stash management
//! - Conflict resolution UI

const std = @import("std");

pub const GitAdvanced = struct {
    allocator: std.mem.Allocator,
    repo_root: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, repo_root: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .repo_root = try allocator.dupe(u8, repo_root),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.repo_root);
        self.allocator.destroy(self);
    }

    // ==================
    // Interactive Staging
    // ==================

    /// Get hunks for a file (for interactive staging)
    pub fn getFileHunks(self: *Self, file_path: []const u8) ![]Hunk {
        var hunks = std.ArrayList(Hunk).init(self.allocator);
        errdefer hunks.deinit();

        // Run: git diff -U0 --no-color <file>
        const result = try self.runGitCommand(&[_][]const u8{
            "diff",
            "-U0",     // No context lines (just changed lines)
            "--no-color",
            file_path,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        // Parse diff output
        var lines = std.mem.split(u8, result.stdout, "\n");
        var current_hunk: ?Hunk = null;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Hunk header: @@ -10,5 +10,7 @@
            if (std.mem.startsWith(u8, line, "@@")) {
                if (current_hunk) |hunk| {
                    try hunks.append(hunk);
                }

                const hunk_info = try parseHunkHeader(line);
                current_hunk = Hunk{
                    .old_start = hunk_info.old_start,
                    .old_count = hunk_info.old_count,
                    .new_start = hunk_info.new_start,
                    .new_count = hunk_info.new_count,
                    .lines = std.ArrayList(HunkLine).init(self.allocator),
                    .staged = false,
                };
            } else if (current_hunk != null) {
                // Added line
                if (std.mem.startsWith(u8, line, "+")) {
                    try current_hunk.?.lines.append(.{
                        .type = .added,
                        .content = try self.allocator.dupe(u8, line[1..]),
                    });
                }
                // Removed line
                else if (std.mem.startsWith(u8, line, "-")) {
                    try current_hunk.?.lines.append(.{
                        .type = .removed,
                        .content = try self.allocator.dupe(u8, line[1..]),
                    });
                }
            }
        }

        if (current_hunk) |hunk| {
            try hunks.append(hunk);
        }

        return hunks.toOwnedSlice();
    }

    /// Stage a specific hunk
    pub fn stageHunk(self: *Self, file_path: []const u8, hunk: *Hunk) !void {
        // Create patch file
        const patch = try self.createHunkPatch(file_path, hunk);
        defer self.allocator.free(patch);

        // Apply patch: git apply --cached
        const result = try self.runGitCommandWithInput(
            &[_][]const u8{ "apply", "--cached", "--unidiff-zero", "-" },
            patch,
        );
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            std.log.err("Failed to stage hunk: {s}", .{result.stderr});
            return error.StagingFailed;
        }

        hunk.staged = true;
    }

    /// Unstage a specific hunk
    pub fn unstageHunk(self: *Self, file_path: []const u8, hunk: *Hunk) !void {
        // Reset hunk: git reset HEAD <file> (then reapply other hunks)
        _ = file_path;
        _ = hunk;
        // TODO: Implement unstaging
    }

    fn createHunkPatch(self: *Self, file_path: []const u8, hunk: *Hunk) ![]u8 {
        var patch = std.ArrayList(u8).init(self.allocator);
        errdefer patch.deinit();

        // Header
        try patch.writer().print("--- a/{s}\n", .{file_path});
        try patch.writer().print("+++ b/{s}\n", .{file_path});
        try patch.writer().print("@@ -{d},{d} +{d},{d} @@\n", .{
            hunk.old_start,
            hunk.old_count,
            hunk.new_start,
            hunk.new_count,
        });

        // Lines
        for (hunk.lines.items) |line| {
            const prefix: u8 = switch (line.type) {
                .added => '+',
                .removed => '-',
                .context => ' ',
            };
            try patch.writer().print("{c}{s}\n", .{ prefix, line.content });
        }

        return patch.toOwnedSlice();
    }

    fn parseHunkHeader(header: []const u8) !HunkInfo {
        // Parse: @@ -10,5 +10,7 @@
        var it = std.mem.tokenize(u8, header, " ,@+-");

        const old_start = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidHunk, 10);
        const old_count = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidHunk, 10);
        const new_start = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidHunk, 10);
        const new_count = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidHunk, 10);

        return HunkInfo{
            .old_start = old_start,
            .old_count = old_count,
            .new_start = new_start,
            .new_count = new_count,
        };
    }

    // ==================
    // Commit History
    // ==================

    /// Get commit history
    pub fn getCommitHistory(self: *Self, limit: usize) ![]Commit {
        const limit_str = try std.fmt.allocPrint(self.allocator, "{d}", .{limit});
        defer self.allocator.free(limit_str);

        const result = try self.runGitCommand(&[_][]const u8{
            "log",
            "--format=%H%n%an%n%ae%n%at%n%s%n%b%n---END---",
            "-n",
            limit_str,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        var commits = std.ArrayList(Commit).init(self.allocator);
        errdefer commits.deinit();

        var lines = std.mem.split(u8, result.stdout, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            const hash = try self.allocator.dupe(u8, line);
            const author = try self.allocator.dupe(u8, lines.next() orelse break);
            const email = try self.allocator.dupe(u8, lines.next() orelse break);
            const timestamp_str = lines.next() orelse break;
            const timestamp = try std.fmt.parseInt(i64, timestamp_str, 10);
            const subject = try self.allocator.dupe(u8, lines.next() orelse break);

            // Collect body lines until ---END---
            var body = std.ArrayList(u8).init(self.allocator);
            while (lines.next()) |body_line| {
                if (std.mem.eql(u8, body_line, "---END---")) break;
                try body.appendSlice(body_line);
                try body.append('\n');
            }

            try commits.append(Commit{
                .hash = hash,
                .author = author,
                .email = email,
                .timestamp = timestamp,
                .subject = subject,
                .body = try body.toOwnedSlice(),
            });
        }

        return commits.toOwnedSlice();
    }

    /// Get commit diff
    pub fn getCommitDiff(self: *Self, commit_hash: []const u8) ![]u8 {
        const result = try self.runGitCommand(&[_][]const u8{
            "show",
            "--format=",
            commit_hash,
        });
        defer self.allocator.free(result.stderr);

        return result.stdout;
    }

    // ==================
    // Branch Management
    // ==================

    /// List all branches
    pub fn getBranches(self: *Self) ![]Branch {
        const result = try self.runGitCommand(&[_][]const u8{
            "branch",
            "-a",
            "--format=%(refname:short)%09%(upstream:short)%09%(HEAD)",
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        var branches = std.ArrayList(Branch).init(self.allocator);
        errdefer branches.deinit();

        var lines = std.mem.split(u8, result.stdout, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var it = std.mem.split(u8, line, "\t");
            const name = it.next() orelse continue;
            const upstream = it.next() orelse "";
            const is_current = it.next();

            try branches.append(Branch{
                .name = try self.allocator.dupe(u8, name),
                .upstream = if (upstream.len > 0) try self.allocator.dupe(u8, upstream) else null,
                .is_current = is_current != null and is_current.?.len > 0,
            });
        }

        return branches.toOwnedSlice();
    }

    /// Create new branch
    pub fn createBranch(self: *Self, name: []const u8, checkout: bool) !void {
        const args = if (checkout)
            &[_][]const u8{ "checkout", "-b", name }
        else
            &[_][]const u8{ "branch", name };

        const result = try self.runGitCommand(args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            return error.BranchCreationFailed;
        }
    }

    /// Switch branch
    pub fn switchBranch(self: *Self, name: []const u8) !void {
        const result = try self.runGitCommand(&[_][]const u8{ "checkout", name });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            return error.BranchSwitchFailed;
        }
    }

    /// Delete branch
    pub fn deleteBranch(self: *Self, name: []const u8, force: bool) !void {
        const flag = if (force) "-D" else "-d";
        const result = try self.runGitCommand(&[_][]const u8{ "branch", flag, name });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            return error.BranchDeletionFailed;
        }
    }

    // ==================
    // Stash Management
    // ==================

    /// List stashes
    pub fn getStashes(self: *Self) ![]Stash {
        const result = try self.runGitCommand(&[_][]const u8{
            "stash",
            "list",
            "--format=%gd%09%s%09%ct",
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        var stashes = std.ArrayList(Stash).init(self.allocator);
        errdefer stashes.deinit();

        var lines = std.mem.split(u8, result.stdout, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var it = std.mem.split(u8, line, "\t");
            const ref = it.next() orelse continue;
            const message = it.next() orelse "";
            const timestamp_str = it.next() orelse "0";
            const timestamp = try std.fmt.parseInt(i64, timestamp_str, 10);

            try stashes.append(Stash{
                .ref = try self.allocator.dupe(u8, ref),
                .message = try self.allocator.dupe(u8, message),
                .timestamp = timestamp,
            });
        }

        return stashes.toOwnedSlice();
    }

    /// Create stash
    pub fn createStash(self: *Self, message: ?[]const u8) !void {
        const args = if (message) |msg|
            &[_][]const u8{ "stash", "push", "-m", msg }
        else
            &[_][]const u8{ "stash", "push" };

        const result = try self.runGitCommand(args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
    }

    /// Apply stash
    pub fn applyStash(self: *Self, ref: []const u8, pop: bool) !void {
        const command = if (pop) "pop" else "apply";
        const result = try self.runGitCommand(&[_][]const u8{ "stash", command, ref });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            return error.StashApplyFailed;
        }
    }

    /// Drop stash
    pub fn dropStash(self: *Self, ref: []const u8) !void {
        const result = try self.runGitCommand(&[_][]const u8{ "stash", "drop", ref });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
    }

    // ==================
    // Conflict Resolution
    // ==================

    /// Get files with conflicts
    pub fn getConflictedFiles(self: *Self) ![][]const u8 {
        const result = try self.runGitCommand(&[_][]const u8{
            "diff",
            "--name-only",
            "--diff-filter=U",
        });
        defer self.allocator.free(result.stderr);

        var files = std.ArrayList([]const u8).init(self.allocator);
        errdefer files.deinit();

        var lines = std.mem.split(u8, result.stdout, "\n");
        while (lines.next()) |line| {
            if (line.len > 0) {
                try files.append(try self.allocator.dupe(u8, line));
            }
        }

        return files.toOwnedSlice();
    }

    /// Parse conflict markers in file
    pub fn parseConflicts(self: *Self, file_path: []const u8) ![]Conflict {
        const content = try std.fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        var conflicts = std.ArrayList(Conflict).init(self.allocator);
        errdefer conflicts.deinit();

        var lines = std.mem.split(u8, content, "\n");
        var line_num: usize = 0;
        var in_conflict = false;
        var current_conflict: ?Conflict = null;

        while (lines.next()) |line| {
            line_num += 1;

            if (std.mem.startsWith(u8, line, "<<<<<<<")) {
                // Start of conflict
                in_conflict = true;
                current_conflict = Conflict{
                    .start_line = line_num,
                    .end_line = 0,
                    .ours = std.ArrayList(u8).init(self.allocator),
                    .theirs = std.ArrayList(u8).init(self.allocator),
                    .base = null,
                };
            } else if (std.mem.startsWith(u8, line, "=======")) {
                // Middle marker (switch from ours to theirs)
                continue;
            } else if (std.mem.startsWith(u8, line, ">>>>>>>")) {
                // End of conflict
                if (current_conflict) |*conflict| {
                    conflict.end_line = line_num;
                    try conflicts.append(conflict.*);
                    current_conflict = null;
                }
                in_conflict = false;
            } else if (in_conflict and current_conflict != null) {
                // Add line to appropriate section
                // TODO: Distinguish between ours/theirs/base
                try current_conflict.?.ours.appendSlice(line);
                try current_conflict.?.ours.append('\n');
            }
        }

        return conflicts.toOwnedSlice();
    }

    /// Resolve conflict by choosing a side
    pub fn resolveConflict(
        self: *Self,
        file_path: []const u8,
        resolution: ConflictResolution,
    ) !void {
        const result = try self.runGitCommand(&[_][]const u8{
            "checkout",
            if (resolution == .ours) "--ours" else "--theirs",
            file_path,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        // Stage the resolved file
        try self.stageFile(file_path);
    }

    fn stageFile(self: *Self, file_path: []const u8) !void {
        const result = try self.runGitCommand(&[_][]const u8{ "add", file_path });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
    }

    // ==================
    // Utility Methods
    // ==================

    fn runGitCommand(self: *Self, args: []const []const u8) !CommandResult {
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append("git");
        try argv.appendSlice(args);

        var child = std.process.Child.init(argv.items, self.allocator);
        child.cwd = self.repo_root;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);

        const term = try child.wait();
        const exit_code: u8 = switch (term) {
            .Exited => |code| code,
            else => 1,
        };

        return CommandResult{
            .stdout = stdout,
            .stderr = stderr,
            .exit_code = exit_code,
        };
    }

    fn runGitCommandWithInput(self: *Self, args: []const []const u8, input: []const u8) !CommandResult {
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append("git");
        try argv.appendSlice(args);

        var child = std.process.Child.init(argv.items, self.allocator);
        child.cwd = self.repo_root;
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        try child.stdin.?.writeAll(input);
        child.stdin.?.close();
        child.stdin = null;

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);

        const term = try child.wait();
        const exit_code: u8 = switch (term) {
            .Exited => |code| code,
            else => 1,
        };

        return CommandResult{
            .stdout = stdout,
            .stderr = stderr,
            .exit_code = exit_code,
        };
    }
};

// Types
pub const Hunk = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
    lines: std.ArrayList(HunkLine),
    staged: bool,
};

pub const HunkLine = struct {
    type: enum { added, removed, context },
    content: []const u8,
};

const HunkInfo = struct {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
};

pub const Commit = struct {
    hash: []const u8,
    author: []const u8,
    email: []const u8,
    timestamp: i64,
    subject: []const u8,
    body: []const u8,
};

pub const Branch = struct {
    name: []const u8,
    upstream: ?[]const u8,
    is_current: bool,
};

pub const Stash = struct {
    ref: []const u8,
    message: []const u8,
    timestamp: i64,
};

pub const Conflict = struct {
    start_line: usize,
    end_line: usize,
    ours: std.ArrayList(u8),
    theirs: std.ArrayList(u8),
    base: ?std.ArrayList(u8),
};

pub const ConflictResolution = enum {
    ours,
    theirs,
    manual,
};

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

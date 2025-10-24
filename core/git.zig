const std = @import("std");

/// Git integration module for Grim
/// Provides: git blame, hunk detection, status, diff views
pub const Git = struct {
    allocator: std.mem.Allocator,
    repo_root: ?[]u8,
    current_branch: ?[]u8,
    status_cache: std.StringHashMap(FileStatus),
    blame_cache: std.StringHashMap([]BlameInfo),

    pub const FileStatus = enum {
        unmodified,
        modified,
        added,
        deleted,
        renamed,
        untracked,
    };

    pub const BlameInfo = struct {
        commit_hash: []const u8,
        author: []const u8,
        date: []const u8,
        line_content: []const u8,
    };

    pub const Hunk = struct {
        start_line: usize,
        end_line: usize,
        hunk_type: HunkType,
        content: []const u8,

        pub const HunkType = enum {
            added,
            modified,
            deleted,
        };
    };

    pub fn init(allocator: std.mem.Allocator) Git {
        return .{
            .allocator = allocator,
            .repo_root = null,
            .current_branch = null,
            .status_cache = std.StringHashMap(FileStatus).init(allocator),
            .blame_cache = std.StringHashMap([]BlameInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Git) void {
        if (self.repo_root) |root| self.allocator.free(root);
        if (self.current_branch) |branch| self.allocator.free(branch);

        var blame_iter = self.blame_cache.valueIterator();
        while (blame_iter.next()) |blame_info| {
            for (blame_info.*) |info| {
                self.allocator.free(info.commit_hash);
                self.allocator.free(info.author);
                self.allocator.free(info.date);
                self.allocator.free(info.line_content);
            }
            self.allocator.free(blame_info.*);
        }
        self.blame_cache.deinit();
        self.status_cache.deinit();
    }

    /// Detect if we're in a git repository
    pub fn detectRepository(self: *Git, path: []const u8) !bool {
        // Convert to absolute path if needed
        const abs_path = if (std.fs.path.isAbsolute(path))
            try self.allocator.dupe(u8, path)
        else
            try std.fs.cwd().realpathAlloc(self.allocator, path);
        defer self.allocator.free(abs_path);

        // Walk up directory tree looking for .git
        var current_path = try self.allocator.dupe(u8, abs_path);
        defer self.allocator.free(current_path);

        while (true) {
            const git_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ current_path, ".git" });
            defer self.allocator.free(git_dir);

            // Use regular access, not accessAbsolute, since std.fs.path.join doesn't guarantee absolute paths
            std.fs.cwd().access(git_dir, .{}) catch {
                // Try parent directory
                const parent = std.fs.path.dirname(current_path) orelse break;
                // Free old current_path and allocate new
                self.allocator.free(current_path);
                current_path = try self.allocator.dupe(u8, parent);
                continue;
            };

            // Found .git directory
            if (self.repo_root) |old| self.allocator.free(old);
            self.repo_root = try self.allocator.dupe(u8, current_path);
            return true;
        }

        return false;
    }

    /// Get current git branch
    pub fn getCurrentBranch(self: *Git) ![]const u8 {
        if (self.repo_root == null) return error.NotInGitRepo;

        var result: std.ArrayList(u8) = .empty;
        defer result.deinit(self.allocator);

        const argv = [_][]const u8{ "git", "branch", "--show-current" };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        // Trim whitespace
        const branch = std.mem.trim(u8, exec_result.stdout, &std.ascii.whitespace);
        if (self.current_branch) |old| self.allocator.free(old);
        self.current_branch = try self.allocator.dupe(u8, branch);

        return self.current_branch.?;
    }

    /// Get git blame for a file
    pub fn getBlame(self: *Git, filepath: []const u8) ![]BlameInfo {
        if (self.repo_root == null) return error.NotInGitRepo;

        // Check cache first
        if (self.blame_cache.get(filepath)) |cached| {
            return cached;
        }

        var blame_list: std.ArrayList(BlameInfo) = .empty;
        defer blame_list.deinit(self.allocator);

        const argv = [_][]const u8{ "git", "blame", "--line-porcelain", filepath };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        // Parse porcelain format
        var lines = std.mem.splitSequence(u8, exec_result.stdout, "\n");
        var current_commit: ?[]const u8 = null;
        var current_author: ?[]const u8 = null;
        var current_date: ?[]const u8 = null;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            if (line[0] != '\t') {
                // Header line
                if (std.mem.startsWith(u8, line, "author ")) {
                    current_author = line[7..];
                } else if (std.mem.startsWith(u8, line, "author-time ")) {
                    current_date = line[12..];
                } else if (current_commit == null) {
                    // First line is commit hash
                    var parts = std.mem.splitSequence(u8, line, " ");
                    if (parts.next()) |hash| {
                        current_commit = hash;
                    }
                }
            } else {
                // Content line (starts with tab)
                if (current_commit != null and current_author != null and current_date != null) {
                    const info = BlameInfo{
                        .commit_hash = try self.allocator.dupe(u8, current_commit.?),
                        .author = try self.allocator.dupe(u8, current_author.?),
                        .date = try self.allocator.dupe(u8, current_date.?),
                        .line_content = try self.allocator.dupe(u8, line[1..]), // Skip tab
                    };
                    try blame_list.append(self.allocator, info);
                }
                current_commit = null;
                current_author = null;
                current_date = null;
            }
        }

        const blame_slice = try blame_list.toOwnedSlice(self.allocator);
        try self.blame_cache.put(filepath, blame_slice);

        return blame_slice;
    }

    /// Get diff hunks for a file
    pub fn getHunks(self: *Git, filepath: []const u8) ![]Hunk {
        if (self.repo_root == null) return error.NotInGitRepo;

        var hunk_list: std.ArrayList(Hunk) = .empty;
        defer hunk_list.deinit(self.allocator);

        const argv = [_][]const u8{ "git", "diff", "--unified=3", filepath };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        // Parse unified diff format
        var lines = std.mem.splitSequence(u8, exec_result.stdout, "\n");
        var content_buffer: std.ArrayList(u8) = .empty;
        defer content_buffer.deinit(self.allocator);

        var current_hunk_start: ?usize = null;
        var current_hunk_type: ?Hunk.HunkType = null;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Parse hunk header: @@ -old_start,old_count +new_start,new_count @@
            if (std.mem.startsWith(u8, line, "@@")) {
                // Save previous hunk if exists
                if (current_hunk_start) |start| {
                    const content = try content_buffer.toOwnedSlice(self.allocator);
                    try hunk_list.append(self.allocator, .{
                        .start_line = start,
                        .end_line = start, // Will be updated by line count
                        .hunk_type = current_hunk_type orelse .modified,
                        .content = content,
                    });
                    content_buffer = .empty;
                }

                // Parse new hunk header
                // Format: @@ -old_start,old_count +new_start,new_count @@
                var parts = std.mem.splitSequence(u8, line, " ");
                _ = parts.next(); // Skip "@@"
                _ = parts.next(); // Skip old range "-..."

                if (parts.next()) |new_range| {
                    // Parse +new_start,new_count
                    if (new_range.len > 1 and new_range[0] == '+') {
                        const range_str = new_range[1..];
                        var range_parts = std.mem.splitSequence(u8, range_str, ",");
                        if (range_parts.next()) |start_str| {
                            current_hunk_start = std.fmt.parseInt(usize, start_str, 10) catch null;
                        }
                    }
                }

                current_hunk_type = .modified;
            } else if (std.mem.startsWith(u8, line, "+") and !std.mem.startsWith(u8, line, "+++")) {
                // Added line
                current_hunk_type = .added;
                try content_buffer.appendSlice(self.allocator, line);
                try content_buffer.append(self.allocator, '\n');
            } else if (std.mem.startsWith(u8, line, "-") and !std.mem.startsWith(u8, line, "---")) {
                // Deleted line
                current_hunk_type = .deleted;
                try content_buffer.appendSlice(self.allocator, line);
                try content_buffer.append(self.allocator, '\n');
            } else if (std.mem.startsWith(u8, line, " ")) {
                // Context line
                try content_buffer.appendSlice(self.allocator, line);
                try content_buffer.append(self.allocator, '\n');
            }
        }

        // Save final hunk
        if (current_hunk_start) |start| {
            const content = try content_buffer.toOwnedSlice(self.allocator);
            try hunk_list.append(self.allocator, .{
                .start_line = start,
                .end_line = start,
                .hunk_type = current_hunk_type orelse .modified,
                .content = content,
            });
        }

        return try hunk_list.toOwnedSlice(self.allocator);
    }

    /// Get file status
    pub fn getFileStatus(self: *Git, filepath: []const u8) !FileStatus {
        if (self.repo_root == null) return .unmodified;

        // Check cache
        if (self.status_cache.get(filepath)) |status| {
            return status;
        }

        const argv = [_][]const u8{ "git", "status", "--porcelain", filepath };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return .unmodified;
        }

        const status: FileStatus = blk: {
            if (exec_result.stdout.len < 2) break :blk .unmodified;

            const status_code = exec_result.stdout[0..2];
            if (std.mem.eql(u8, status_code, "M ") or std.mem.eql(u8, status_code, " M")) {
                break :blk .modified;
            } else if (std.mem.eql(u8, status_code, "A ") or std.mem.eql(u8, status_code, " A")) {
                break :blk .added;
            } else if (std.mem.eql(u8, status_code, "D ") or std.mem.eql(u8, status_code, " D")) {
                break :blk .deleted;
            } else if (std.mem.eql(u8, status_code, "R ")) {
                break :blk .renamed;
            } else if (std.mem.eql(u8, status_code, "??")) {
                break :blk .untracked;
            } else {
                break :blk .unmodified;
            }
        };

        try self.status_cache.put(filepath, status);
        return status;
    }

    /// Stage a file
    pub fn stageFile(self: *Git, filepath: []const u8) !void {
        if (self.repo_root == null) return error.NotInGitRepo;

        const argv = [_][]const u8{ "git", "add", filepath };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        self.clearCaches();
    }

    /// Unstage a file
    pub fn unstageFile(self: *Git, filepath: []const u8) !void {
        if (self.repo_root == null) return error.NotInGitRepo;

        const argv = [_][]const u8{ "git", "restore", "--staged", filepath };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        self.clearCaches();
    }

    /// Stage hunk at line number
    pub fn stageHunk(self: *Git, filepath: []const u8, line: usize) !void {
        if (self.repo_root == null) return error.NotInGitRepo;

        // Get all hunks
        const hunks = try self.getHunks(filepath);
        defer {
            for (hunks) |hunk| {
                self.allocator.free(hunk.content);
            }
            self.allocator.free(hunks);
        }

        // Find hunk containing the line
        var target_hunk: ?Hunk = null;
        for (hunks) |hunk| {
            if (hunk.start_line <= line and line <= hunk.end_line) {
                target_hunk = hunk;
                break;
            }
        }

        if (target_hunk == null) {
            // No hunk at this line, stage whole file
            return try self.stageFile(filepath);
        }

        // Create patch file
        const patch_path = try std.fs.path.join(self.allocator, &[_][]const u8{ "/tmp", "grim_hunk.patch" });
        defer self.allocator.free(patch_path);

        var patch_file = try std.fs.createFileAbsolute(patch_path, .{});
        defer patch_file.close();

        const writer = patch_file.writer();
        try writer.print("diff --git a/{s} b/{s}\n", .{ filepath, filepath });
        try writer.print("--- a/{s}\n", .{filepath});
        try writer.print("+++ b/{s}\n", .{filepath});
        try writer.print("@@ -{d},0 +{d},0 @@\n", .{ target_hunk.?.start_line, target_hunk.?.start_line });
        try writer.writeAll(target_hunk.?.content);

        // Apply patch to index
        const argv = [_][]const u8{ "git", "apply", "--cached", patch_path };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        self.clearCaches();
    }

    /// Unstage hunk at line number
    pub fn unstageHunk(self: *Git, filepath: []const u8, line: usize) !void {
        if (self.repo_root == null) return error.NotInGitRepo;

        // Get staged hunks (diff between HEAD and index)
        const argv_cached = [_][]const u8{ "git", "diff", "--cached", "--unified=3", filepath };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv_cached,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        // Parse staged hunks
        var hunk_list: std.ArrayList(Hunk) = .empty;
        defer {
            for (hunk_list.items) |hunk| {
                self.allocator.free(hunk.content);
            }
            hunk_list.deinit(self.allocator);
        }

        var lines = std.mem.splitSequence(u8, exec_result.stdout, "\n");
        var content_buffer: std.ArrayList(u8) = .empty;
        defer content_buffer.deinit(self.allocator);

        var current_hunk_start: ?usize = null;

        while (lines.next()) |diff_line| {
            if (diff_line.len == 0) continue;

            if (std.mem.startsWith(u8, diff_line, "@@")) {
                if (current_hunk_start) |start| {
                    const content = try content_buffer.toOwnedSlice(self.allocator);
                    try hunk_list.append(self.allocator, .{
                        .start_line = start,
                        .end_line = start,
                        .hunk_type = .modified,
                        .content = content,
                    });
                    content_buffer = .empty;
                }

                var parts = std.mem.splitSequence(u8, diff_line, " ");
                _ = parts.next(); // Skip "@@"
                _ = parts.next(); // Skip old range

                if (parts.next()) |new_range| {
                    if (new_range.len > 1 and new_range[0] == '+') {
                        const range_str = new_range[1..];
                        var range_parts = std.mem.splitSequence(u8, range_str, ",");
                        if (range_parts.next()) |start_str| {
                            current_hunk_start = std.fmt.parseInt(usize, start_str, 10) catch null;
                        }
                    }
                }
            } else {
                try content_buffer.appendSlice(self.allocator, diff_line);
                try content_buffer.append(self.allocator, '\n');
            }
        }

        if (current_hunk_start) |start| {
            const content = try content_buffer.toOwnedSlice(self.allocator);
            try hunk_list.append(self.allocator, .{
                .start_line = start,
                .end_line = start,
                .hunk_type = .modified,
                .content = content,
            });
        }

        // Find hunk at line
        var target_hunk: ?Hunk = null;
        for (hunk_list.items) |hunk| {
            if (hunk.start_line <= line and line <= hunk.end_line) {
                target_hunk = hunk;
                break;
            }
        }

        if (target_hunk == null) {
            return try self.unstageFile(filepath);
        }

        // Create reverse patch
        const patch_path = try std.fs.path.join(self.allocator, &[_][]const u8{ "/tmp", "grim_unstage.patch" });
        defer self.allocator.free(patch_path);

        var patch_file = try std.fs.createFileAbsolute(patch_path, .{});
        defer patch_file.close();

        const writer = patch_file.writer();
        try writer.print("diff --git a/{s} b/{s}\n", .{ filepath, filepath });
        try writer.print("--- a/{s}\n", .{filepath});
        try writer.print("+++ b/{s}\n", .{filepath});
        try writer.print("@@ -{d},0 +{d},0 @@\n", .{ target_hunk.?.start_line, target_hunk.?.start_line });
        try writer.writeAll(target_hunk.?.content);

        // Apply reverse patch to index
        const argv_reset = [_][]const u8{ "git", "apply", "--cached", "--reverse", patch_path };
        const reset_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv_reset,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(reset_result.stdout);
        defer self.allocator.free(reset_result.stderr);

        if (reset_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        self.clearCaches();
    }

    /// Discard changes in file
    pub fn discardChanges(self: *Git, filepath: []const u8) !void {
        if (self.repo_root == null) return error.NotInGitRepo;

        const argv = [_][]const u8{ "git", "restore", filepath };
        const exec_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd = self.repo_root,
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            return error.GitCommandFailed;
        }

        self.clearCaches();
    }

    /// Clear all caches (call after git operations)
    pub fn clearCaches(self: *Git) void {
        var blame_iter = self.blame_cache.valueIterator();
        while (blame_iter.next()) |blame_info| {
            for (blame_info.*) |info| {
                self.allocator.free(info.commit_hash);
                self.allocator.free(info.author);
                self.allocator.free(info.date);
                self.allocator.free(info.line_content);
            }
            self.allocator.free(blame_info.*);
        }
        self.blame_cache.clearAndFree();
        self.status_cache.clearAndFree();
    }
};

test "git module basic" {
    const allocator = std.testing.allocator;

    var git = Git.init(allocator);
    defer git.deinit();

    // Try to detect repository (will fail in non-git directory)
    const is_repo = git.detectRepository(".") catch false;
    _ = is_repo;
}

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
        var dir = try std.fs.cwd().openDir(path, .{});
        defer dir.close();

        // Walk up directory tree looking for .git
        var current_path = try self.allocator.dupe(u8, path);
        defer self.allocator.free(current_path);

        while (true) {
            const git_dir = std.fs.path.join(self.allocator, &[_][]const u8{ current_path, ".git" }) catch break;
            defer self.allocator.free(git_dir);

            std.fs.accessAbsolute(git_dir, .{}) catch {
                // Try parent directory
                const parent = std.fs.path.dirname(current_path) orelse break;
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

        const argv = [_][]const u8{ "git", "diff", "--unified=0", filepath };
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
        while (lines.next()) |_| {
            // TODO: Parse hunk header: @@ -start,count +start,count @@
            // For now, just detect the hunk
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

    /// Stage hunk at line number (simplified - stages whole file for now)
    pub fn stageHunk(self: *Git, filepath: []const u8, _: usize) !void {
        // TODO: Implement proper hunk staging with git add -p
        // For now, just stage the whole file
        try self.stageFile(filepath);
    }

    /// Unstage hunk at line number (simplified - unstages whole file for now)
    pub fn unstageHunk(self: *Git, filepath: []const u8, _: usize) !void {
        // TODO: Implement proper hunk unstaging
        // For now, just unstage the whole file
        try self.unstageFile(filepath);
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

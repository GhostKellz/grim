const std = @import("std");
const core = @import("core");

pub const FileManager = struct {
    allocator: std.mem.Allocator,
    current_dir: std.ArrayList(u8),
    recent_files: std.ArrayList([]u8),
    project_root: ?std.ArrayList(u8),

    pub const Error = error{
        DirectoryNotFound,
        PermissionDenied,
        FileNotFound,
        InvalidPath,
    } || std.mem.Allocator.Error || std.fs.File.OpenError;

    pub const FileEntry = struct {
        name: []const u8,
        path: []const u8,
        is_directory: bool,
        size: u64,
        modified: i64,
        permissions: u32,
    };

    pub fn init(allocator: std.mem.Allocator) !*FileManager {
        var self = try allocator.create(FileManager);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .current_dir = std.ArrayList(u8).init(allocator),
            .recent_files = std.ArrayList([]u8).init(allocator),
            .project_root = null,
        };

        // Initialize with current working directory
        const cwd = try std.process.getCwdAlloc(allocator);
        errdefer allocator.free(cwd);
        try self.current_dir.appendSlice(cwd);
        allocator.free(cwd);

        return self;
    }

    pub fn deinit(self: *FileManager) void {
        self.current_dir.deinit();

        for (self.recent_files.items) |path| {
            self.allocator.free(path);
        }
        self.recent_files.deinit();

        if (self.project_root) |*root| {
            root.deinit();
        }

        self.allocator.destroy(self);
    }

    pub fn getCurrentDir(self: *FileManager) []const u8 {
        return self.current_dir.items;
    }

    pub fn changeDirectory(self: *FileManager, path: []const u8) Error!void {
        // Validate directory exists and is accessible
        var dir = std.fs.cwd().openDir(path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => Error.DirectoryNotFound,
                error.AccessDenied => Error.PermissionDenied,
                else => err,
            };
        };
        defer dir.close();

        // Update current directory
        self.current_dir.clearAndFree();

        if (std.fs.path.isAbsolute(path)) {
            try self.current_dir.appendSlice(path);
        } else {
            try self.current_dir.appendSlice(self.current_dir.items);
            try self.current_dir.append('/');
            try self.current_dir.appendSlice(path);
        }

        // Normalize path
        const normalized = try std.fs.path.resolve(self.allocator, &[_][]const u8{self.current_dir.items});
        defer self.allocator.free(normalized);

        self.current_dir.clearAndFree();
        try self.current_dir.appendSlice(normalized);
    }

    pub fn listDirectory(self: *FileManager, allocator: std.mem.Allocator, path: ?[]const u8) Error![]FileEntry {
        const dir_path = path orelse self.current_dir.items;

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            return switch (err) {
                error.FileNotFound => Error.DirectoryNotFound,
                error.AccessDenied => Error.PermissionDenied,
                else => err,
            };
        };
        defer dir.close();

        var entries = std.ArrayList(FileEntry).init(allocator);
        errdefer {
            for (entries.items) |entry| {
                allocator.free(entry.name);
                allocator.free(entry.path);
            }
            entries.deinit();
        }

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            errdefer allocator.free(full_path);

            const stat = dir.statFile(entry.name) catch |err| {
                allocator.free(full_path);
                switch (err) {
                    error.AccessDenied => continue, // Skip inaccessible files
                    else => return err,
                }
            };

            try entries.append(.{
                .name = try allocator.dupe(u8, entry.name),
                .path = full_path,
                .is_directory = entry.kind == .directory,
                .size = stat.size,
                .modified = stat.mtime,
                .permissions = stat.mode,
            });
        }

        // Sort entries: directories first, then alphabetically
        const SortContext = struct {
            fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
                if (a.is_directory != b.is_directory) {
                    return a.is_directory;
                }
                return std.mem.lessThan(u8, a.name, b.name);
            }
        };
        std.mem.sort(FileEntry, entries.items, {}, SortContext.lessThan);

        return entries.toOwnedSlice();
    }

    pub fn readFile(self: *FileManager, path: []const u8, allocator: std.mem.Allocator) Error![]u8 {
        _ = self;
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => Error.FileNotFound,
                error.AccessDenied => Error.PermissionDenied,
                else => err,
            };
        };
        defer file.close();

        const stat = try file.stat();
        const content = try file.readToEndAlloc(allocator, stat.size);
        return content;
    }

    pub fn writeFile(self: *FileManager, path: []const u8, content: []const u8) Error!void {
        _ = self;
        const file = std.fs.cwd().createFile(path, .{}) catch |err| {
            return switch (err) {
                error.AccessDenied => Error.PermissionDenied,
                else => err,
            };
        };
        defer file.close();

        try file.writeAll(content);
    }

    pub fn addRecentFile(self: *FileManager, path: []const u8) !void {
        const MAX_RECENT = 20;

        // Check if file already exists in recent list
        for (self.recent_files.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing, path)) {
                // Move to front
                const item = self.recent_files.orderedRemove(i);
                try self.recent_files.insert(0, item);
                return;
            }
        }

        // Add new entry at front
        const path_copy = try self.allocator.dupe(u8, path);
        try self.recent_files.insert(0, path_copy);

        // Trim to max size
        while (self.recent_files.items.len > MAX_RECENT) {
            const removed = self.recent_files.pop();
            self.allocator.free(removed);
        }
    }

    pub fn getRecentFiles(self: *FileManager) []const []const u8 {
        return self.recent_files.items;
    }

    pub fn findProjectRoot(self: *FileManager) Error!?[]const u8 {
        if (self.project_root) |*root| {
            return root.items;
        }

        // Look for common project markers
        const markers = [_][]const u8{
            ".git",
            ".gitignore",
            "build.zig",
            "Cargo.toml",
            "package.json",
            "pyproject.toml",
            "Makefile",
            "CMakeLists.txt",
            ".project",
        };

        var current = try std.ArrayList(u8).initCapacity(self.allocator, self.current_dir.items.len);
        defer current.deinit();
        try current.appendSlice(self.current_dir.items);

        while (current.items.len > 1) {
            // Check if any marker exists in current directory
            for (markers) |marker| {
                const marker_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current.items, marker });
                defer self.allocator.free(marker_path);

                const file_or_dir = std.fs.cwd().openFile(marker_path, .{}) catch
                    std.fs.cwd().openDir(marker_path, .{}) catch continue;
                file_or_dir.close();

                // Found project root
                self.project_root = try std.ArrayList(u8).initCapacity(self.allocator, current.items.len);
                try self.project_root.?.appendSlice(current.items);
                return self.project_root.?.items;
            }

            // Go up one directory
            const parent = std.fs.path.dirname(current.items);
            if (parent == null or std.mem.eql(u8, parent.?, current.items)) {
                break; // Reached filesystem root
            }

            current.clearAndFree();
            try current.appendSlice(parent.?);
        }

        return null;
    }

    pub fn searchFiles(self: *FileManager, allocator: std.mem.Allocator, pattern: []const u8, dir: ?[]const u8) Error![][]const u8 {
        var results = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (results.items) |path| {
                allocator.free(path);
            }
            results.deinit();
        }

        const search_dir = dir orelse ".";

        try self.searchFilesRecursive(allocator, search_dir, pattern, &results);

        return results.toOwnedSlice();
    }

    fn searchFilesRecursive(self: *FileManager, allocator: std.mem.Allocator, dir_path: []const u8, pattern: []const u8, results: *std.ArrayList([]const u8)) Error!void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });

            if (entry.kind == .directory) {
                // Skip hidden directories and common ignore patterns
                if (std.mem.startsWith(u8, entry.name, ".") or
                    std.mem.eql(u8, entry.name, "node_modules") or
                    std.mem.eql(u8, entry.name, "target") or
                    std.mem.eql(u8, entry.name, "build") or
                    std.mem.eql(u8, entry.name, "zig-cache"))
                {
                    allocator.free(full_path);
                    continue;
                }

                // Recurse into subdirectory
                self.searchFilesRecursive(allocator, full_path, pattern, results) catch {};
                allocator.free(full_path);
            } else {
                // Check if filename matches pattern (simple substring match for now)
                if (std.mem.indexOf(u8, entry.name, pattern) != null) {
                    try results.append(full_path);
                } else {
                    allocator.free(full_path);
                }
            }
        }
    }

    pub fn isTextFile(self: *FileManager, path: []const u8) bool {
        _ = self;
        const ext = std.fs.path.extension(path);
        const text_extensions = [_][]const u8{
            ".zig", ".rs",   ".c",    ".cpp",  ".h",    ".hpp",  ".cc",
            ".js",  ".ts",   ".jsx",  ".tsx",  ".py",   ".java", ".go",
            ".txt", ".md",   ".json", ".toml", ".yaml", ".yml",  ".html",
            ".css", ".scss", ".xml",  ".sh",   ".bash", ".vim",  ".lua",
            ".rb",  ".php",  ".sql",  ".csv",  ".log",  ".ini",  ".conf",
            ".cfg",
        };

        for (text_extensions) |text_ext| {
            if (std.mem.eql(u8, ext, text_ext)) {
                return true;
            }
        }

        return false;
    }

    pub fn getFileInfo(self: *FileManager, path: []const u8) Error!FileEntry {
        _ = self;
        const stat = std.fs.cwd().statFile(path) catch |err| {
            return switch (err) {
                error.FileNotFound => Error.FileNotFound,
                error.AccessDenied => Error.PermissionDenied,
                else => err,
            };
        };

        return FileEntry{
            .name = std.fs.path.basename(path),
            .path = path,
            .is_directory = stat.kind == .directory,
            .size = stat.size,
            .modified = stat.mtime,
            .permissions = stat.mode,
        };
    }
};

// Fuzzy file finder
pub const FileFinder = struct {
    allocator: std.mem.Allocator,
    file_manager: *FileManager,
    cached_files: [][]const u8,
    last_scan: i64,

    pub fn init(allocator: std.mem.Allocator, file_manager: *FileManager) !*FileFinder {
        const self = try allocator.create(FileFinder);
        self.* = .{
            .allocator = allocator,
            .file_manager = file_manager,
            .cached_files = &[_][]const u8{},
            .last_scan = 0,
        };
        return self;
    }

    pub fn deinit(self: *FileFinder) void {
        for (self.cached_files) |path| {
            self.allocator.free(path);
        }
        if (self.cached_files.len > 0) {
            self.allocator.free(self.cached_files);
        }
        self.allocator.destroy(self);
    }

    pub fn refreshCache(self: *FileFinder) !void {
        // Free existing cache
        for (self.cached_files) |path| {
            self.allocator.free(path);
        }
        if (self.cached_files.len > 0) {
            self.allocator.free(self.cached_files);
        }

        // Scan project for files
        const root = try self.file_manager.findProjectRoot() orelse self.file_manager.getCurrentDir();
        self.cached_files = try self.file_manager.searchFiles(self.allocator, "", root);
        self.last_scan = std.time.timestamp();
    }

    pub fn search(self: *FileFinder, allocator: std.mem.Allocator, query: []const u8) ![][]const u8 {
        // Refresh cache if needed (every 30 seconds)
        const now = std.time.timestamp();
        if (now - self.last_scan > 30) {
            try self.refreshCache();
        }

        if (query.len == 0) {
            // Return all files
            var results = try allocator.alloc([]const u8, self.cached_files.len);
            for (self.cached_files, 0..) |path, i| {
                results[i] = try allocator.dupe(u8, path);
            }
            return results;
        }

        // Fuzzy search
        var matches = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (matches.items) |path| {
                allocator.free(path);
            }
            matches.deinit();
        }

        for (self.cached_files) |path| {
            if (self.fuzzyMatch(std.fs.path.basename(path), query)) {
                try matches.append(try allocator.dupe(u8, path));
            }
        }

        return matches.toOwnedSlice();
    }

    fn fuzzyMatch(self: *FileFinder, text: []const u8, query: []const u8) bool {
        _ = self;
        if (query.len == 0) return true;
        if (query.len > text.len) return false;

        var text_i: usize = 0;
        var query_i: usize = 0;

        while (text_i < text.len and query_i < query.len) {
            if (std.ascii.toLower(text[text_i]) == std.ascii.toLower(query[query_i])) {
                query_i += 1;
            }
            text_i += 1;
        }

        return query_i == query.len;
    }
};

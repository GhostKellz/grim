//! Session Management for Grim
//!
//! Features:
//! - Auto-save workspace state
//! - Recent projects list
//! - Restore open files with cursor positions
//! - Window layout persistence
//! - Search history preservation

const std = @import("std");

pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    session_dir: []const u8,
    current_session: ?Session,
    recent_projects: std.ArrayList(RecentProject),
    auto_save_enabled: bool,
    auto_save_interval_ms: u64,
    last_save_time: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Get session directory: ~/.local/share/grim/sessions
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;
        const session_dir = try std.fs.path.join(allocator, &[_][]const u8{
            home,
            ".local",
            "share",
            "grim",
            "sessions",
        });
        errdefer allocator.free(session_dir);

        // Create session directory if it doesn't exist
        std.fs.cwd().makePath(session_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        self.* = .{
            .allocator = allocator,
            .session_dir = session_dir,
            .current_session = null,
            .recent_projects = .empty,
            .auto_save_enabled = true,
            .auto_save_interval_ms = 30_000, // 30 seconds
            .last_save_time = std.time.milliTimestamp(),
        };

        // Load recent projects
        try self.loadRecentProjects();

        std.log.info("Session manager initialized: {s}", .{session_dir});
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.current_session) |*session| {
            session.deinit(self.allocator);
        }

        for (self.recent_projects.items) |*project| {
            project.deinit(self.allocator);
        }
        self.recent_projects.deinit(self.allocator);

        self.allocator.free(self.session_dir);
        self.allocator.destroy(self);
    }

    /// Create a new session for a project
    pub fn createSession(self: *Self, project_path: []const u8) !void {
        // Clean up existing session
        if (self.current_session) |*session| {
            session.deinit(self.allocator);
        }

        const session = Session{
            .project_path = try self.allocator.dupe(u8, project_path),
            .open_files = .empty,
            .window_layout = WindowLayout{},
            .search_history = .empty,
            .created_at = std.time.timestamp(),
            .last_modified = std.time.timestamp(),
        };

        self.current_session = session;

        // Add to recent projects
        try self.addRecentProject(project_path);

        std.log.info("Created session for: {s}", .{project_path});
    }

    /// Load an existing session
    pub fn loadSession(self: *Self, project_path: []const u8) !void {
        const session_file = try self.getSessionPath(project_path);
        defer self.allocator.free(session_file);

        const file = std.fs.cwd().openFile(session_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Create new session
                try self.createSession(project_path);
                return;
            }
            return err;
        };
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(content);
        _ = try file.readAll(content);
        defer self.allocator.free(content);

        // Parse JSON
        const parsed = try std.json.parseFromSlice(SessionJson, self.allocator, content, .{});
        defer parsed.deinit();

        // Convert to Session
        const session = try Session.fromJson(self.allocator, parsed.value);
        self.current_session = session;

        // Update recent projects
        try self.addRecentProject(project_path);

        std.log.info("Loaded session for: {s}", .{project_path});
    }

    /// Save current session
    pub fn saveSession(self: *Self) !void {
        const session = self.current_session orelse return;

        const session_file = try self.getSessionPath(session.project_path);
        defer self.allocator.free(session_file);

        const file = try std.fs.cwd().createFile(session_file, .{});
        defer file.close();

        // Convert to JSON
        const json_session = try session.toJson(self.allocator);
        defer json_session.deinit(self.allocator);

        // Write JSON
        const json_str = try std.json.Stringify.valueAlloc(self.allocator, json_session, .{});
        defer self.allocator.free(json_str);
        try file.writeAll(json_str);

        self.last_save_time = std.time.milliTimestamp();
        std.log.debug("Saved session for: {s}", .{session.project_path});
    }

    /// Auto-save session if interval elapsed
    pub fn tick(self: *Self) !void {
        if (!self.auto_save_enabled) return;
        if (self.current_session == null) return;

        const now = std.time.milliTimestamp();
        if (now - self.last_save_time >= self.auto_save_interval_ms) {
            try self.saveSession();
        }
    }

    /// Add file to current session
    pub fn addOpenFile(self: *Self, file_path: []const u8, cursor_line: usize, cursor_col: usize) !void {
        const session = &(self.current_session orelse return);

        // Check if file already open
        for (session.open_files.items) |*open_file| {
            if (std.mem.eql(u8, open_file.path, file_path)) {
                // Update cursor position
                open_file.cursor_line = cursor_line;
                open_file.cursor_col = cursor_col;
                return;
            }
        }

        // Add new file
        try session.open_files.append(self.allocator, OpenFile{
            .path = try self.allocator.dupe(u8, file_path),
            .cursor_line = cursor_line,
            .cursor_col = cursor_col,
            .scroll_top = 0,
        });

        session.last_modified = std.time.timestamp();
    }

    /// Remove file from current session
    pub fn removeOpenFile(self: *Self, file_path: []const u8) !void {
        const session = &(self.current_session orelse return);

        var i: usize = 0;
        while (i < session.open_files.items.len) {
            if (std.mem.eql(u8, session.open_files.items[i].path, file_path)) {
                const removed = session.open_files.orderedRemove(i);
                self.allocator.free(removed.path);
                session.last_modified = std.time.timestamp();
                return;
            }
            i += 1;
        }
    }

    /// Get list of open files in current session
    pub fn getOpenFiles(self: *Self) ?[]const OpenFile {
        const session = self.current_session orelse return null;
        return session.open_files.items;
    }

    /// Add search term to history
    pub fn addSearchHistory(self: *Self, search_term: []const u8) !void {
        const session = &(self.current_session orelse return);

        // Don't add duplicates
        for (session.search_history.items) |term| {
            if (std.mem.eql(u8, term, search_term)) return;
        }

        try session.search_history.append(self.allocator, try self.allocator.dupe(u8, search_term));

        // Keep only last 50
        if (session.search_history.items.len > 50) {
            const removed = session.search_history.orderedRemove(0);
            self.allocator.free(removed);
        }
    }

    /// Get recent projects
    pub fn getRecentProjects(self: *Self) []const RecentProject {
        return self.recent_projects.items;
    }

    /// Delete a session
    pub fn deleteSession(self: *Self, project_path: []const u8) !void {
        const session_file = try self.getSessionPath(project_path);
        defer self.allocator.free(session_file);

        std.fs.cwd().deleteFile(session_file) catch |err| {
            if (err != error.FileNotFound) return err;
        };

        std.log.info("Deleted session for: {s}", .{project_path});
    }

    // Internal methods

    fn getSessionPath(self: *Self, project_path: []const u8) ![]const u8 {
        // Hash project path to create unique session filename
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(project_path);
        const hash = hasher.final();

        const filename = try std.fmt.allocPrint(self.allocator, "{x}.json", .{hash});
        defer self.allocator.free(filename);

        return std.fs.path.join(self.allocator, &[_][]const u8{ self.session_dir, filename });
    }

    fn addRecentProject(self: *Self, project_path: []const u8) !void {
        // Check if already exists
        for (self.recent_projects.items, 0..) |*project, i| {
            if (std.mem.eql(u8, project.path, project_path)) {
                // Move to front
                project.last_accessed = std.time.timestamp();
                const moved = self.recent_projects.orderedRemove(i);
                try self.recent_projects.insert(self.allocator, 0, moved);
                try self.saveRecentProjects();
                return;
            }
        }

        // Add new
        try self.recent_projects.insert(self.allocator, 0, RecentProject{
            .path = try self.allocator.dupe(u8, project_path),
            .last_accessed = std.time.timestamp(),
        });

        // Keep only last 20
        while (self.recent_projects.items.len > 20) {
            if (self.recent_projects.pop()) |removed| {
                var r = removed;
                r.deinit(self.allocator);
            }
        }

        try self.saveRecentProjects();
    }

    fn loadRecentProjects(self: *Self) !void {
        const recent_file = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.session_dir,
            "recent.json",
        });
        defer self.allocator.free(recent_file);

        const file = std.fs.cwd().openFile(recent_file, .{}) catch return;
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(content);
        _ = try file.readAll(content);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice([]RecentProjectJson, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |project_json| {
            try self.recent_projects.append(self.allocator, RecentProject{
                .path = try self.allocator.dupe(u8, project_json.path),
                .last_accessed = project_json.last_accessed,
            });
        }
    }

    fn saveRecentProjects(self: *Self) !void {
        const recent_file = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.session_dir,
            "recent.json",
        });
        defer self.allocator.free(recent_file);

        const recent_file_handle = try std.fs.cwd().createFile(recent_file, .{});
        defer recent_file_handle.close();

        var json_projects = try self.allocator.alloc(RecentProjectJson, self.recent_projects.items.len);
        defer self.allocator.free(json_projects);

        for (self.recent_projects.items, 0..) |project, i| {
            json_projects[i] = .{
                .path = project.path,
                .last_accessed = project.last_accessed,
            };
        }

        const json_str = try std.json.Stringify.valueAlloc(self.allocator, json_projects, .{});
        defer self.allocator.free(json_str);
        try recent_file_handle.writeAll(json_str);
    }
};

pub const Session = struct {
    project_path: []const u8,
    open_files: std.ArrayList(OpenFile),
    window_layout: WindowLayout,
    search_history: std.ArrayList([]const u8),
    created_at: i64,
    last_modified: i64,

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.project_path);

        for (self.open_files.items) |*file| {
            allocator.free(file.path);
        }
        self.open_files.deinit(allocator);

        for (self.search_history.items) |term| {
            allocator.free(term);
        }
        self.search_history.deinit(allocator);
    }

    pub fn toJson(self: *const Session, allocator: std.mem.Allocator) !SessionJson {
        var open_files = try allocator.alloc(OpenFileJson, self.open_files.items.len);
        for (self.open_files.items, 0..) |file, i| {
            open_files[i] = .{
                .path = file.path,
                .cursor_line = file.cursor_line,
                .cursor_col = file.cursor_col,
                .scroll_top = file.scroll_top,
            };
        }

        return SessionJson{
            .project_path = self.project_path,
            .open_files = open_files,
            .window_layout = self.window_layout,
            .search_history = self.search_history.items,
            .created_at = self.created_at,
            .last_modified = self.last_modified,
        };
    }

    pub fn fromJson(allocator: std.mem.Allocator, json: SessionJson) !Session {
        var open_files: std.ArrayList(OpenFile) = .empty;
        for (json.open_files) |file_json| {
            try open_files.append(allocator, OpenFile{
                .path = try allocator.dupe(u8, file_json.path),
                .cursor_line = file_json.cursor_line,
                .cursor_col = file_json.cursor_col,
                .scroll_top = file_json.scroll_top,
            });
        }

        var search_history: std.ArrayList([]const u8) = .empty;
        for (json.search_history) |term| {
            try search_history.append(allocator, try allocator.dupe(u8, term));
        }

        return Session{
            .project_path = try allocator.dupe(u8, json.project_path),
            .open_files = open_files,
            .window_layout = json.window_layout,
            .search_history = search_history,
            .created_at = json.created_at,
            .last_modified = json.last_modified,
        };
    }
};

pub const OpenFile = struct {
    path: []const u8,
    cursor_line: usize,
    cursor_col: usize,
    scroll_top: usize,
};

pub const WindowLayout = struct {
    // TODO: Expand with split panes, panel states, etc.
};

pub const RecentProject = struct {
    path: []const u8,
    last_accessed: i64,

    pub fn deinit(self: *RecentProject, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

// JSON types for serialization
const SessionJson = struct {
    project_path: []const u8,
    open_files: []const OpenFileJson,
    window_layout: WindowLayout,
    search_history: []const []const u8,
    created_at: i64,
    last_modified: i64,

    pub fn deinit(self: SessionJson, allocator: std.mem.Allocator) void {
        allocator.free(self.open_files);
    }
};

const OpenFileJson = struct {
    path: []const u8,
    cursor_line: usize,
    cursor_col: usize,
    scroll_top: usize,
};

const RecentProjectJson = struct {
    path: []const u8,
    last_accessed: i64,
};

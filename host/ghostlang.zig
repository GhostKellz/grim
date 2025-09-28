const std = @import("std");

pub const Host = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    config_dir: ?[]const u8,
    config_source: ?[]const u8,
    setup_invoked: bool,
    sandbox_config: SandboxConfig,
    execution_stats: ExecutionStats,

    pub const Error = error{
        ConfigNotLoaded,
        SetupSymbolMissing,
        SandboxViolation,
        ExecutionTimeout,
        MemoryLimitExceeded,
        UnauthorizedFileAccess,
        UnauthorizedNetworkAccess,
    } || std.fs.Dir.OpenError || std.fs.File.OpenError || std.fs.File.ReadError || std.mem.Allocator.Error;

    pub const SandboxConfig = struct {
        max_execution_time_ms: u64 = 5000,
        max_memory_bytes: usize = 50 * 1024 * 1024, // 50MB
        max_file_operations: u32 = 100,
        max_network_requests: u32 = 0, // Disabled by default
        allowed_file_patterns: []const []const u8 = &.{},
        blocked_file_patterns: []const []const u8 = &.{
            "/etc/*", "/sys/*", "/proc/*", "/dev/*", "/root/*",
        },
        enable_filesystem_access: bool = true,
        enable_network_access: bool = false,
        enable_system_calls: bool = false,
    };

    pub const ExecutionStats = struct {
        execution_count: u64 = 0,
        total_execution_time_ms: u64 = 0,
        peak_memory_usage: usize = 0,
        file_operations_count: u32 = 0,
        network_requests_count: u32 = 0,
        sandbox_violations: u32 = 0,
        last_execution_time: i64 = 0,

        pub fn reset(self: *ExecutionStats) void {
            self.* = .{};
        }
    };

    const config_file_name = "init.gza";
    const max_config_size = 16 * 1024 * 1024; // 16 MiB safety limit

    pub fn init(allocator: std.mem.Allocator) !Host {
        return initWithSandbox(allocator, .{});
    }

    pub fn initWithSandbox(allocator: std.mem.Allocator, sandbox_config: SandboxConfig) !Host {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        return Host{
            .allocator = allocator,
            .arena = arena,
            .config_dir = null,
            .config_source = null,
            .setup_invoked = false,
            .sandbox_config = sandbox_config,
            .execution_stats = .{},
        };
    }

    pub fn deinit(self: *Host) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn loadConfig(self: *Host, config_dir: []const u8) Error!void {
        self.resetArena();

        var dir = try std.fs.cwd().openDir(config_dir, .{});
        defer dir.close();

        const allocator = self.arena.allocator();
        const source_buffer = try dir.readFileAlloc(allocator, config_file_name, max_config_size);
        const dir_copy = try allocator.dupe(u8, config_dir);

        self.config_source = source_buffer;
        self.config_dir = dir_copy;
        self.setup_invoked = false;
    }

    pub fn callSetup(self: *Host) Error!void {
        const config_buffer = self.config_source orelse return Error.ConfigNotLoaded;
        if (!containsSetupDeclaration(config_buffer)) {
            return Error.SetupSymbolMissing;
        }
        self.setup_invoked = true;
    }

    pub fn configPath(self: *const Host) ?[]const u8 {
        return self.config_dir;
    }

    pub fn configSource(self: *const Host) ?[]const u8 {
        return self.config_source;
    }

    pub fn setupInvoked(self: *const Host) bool {
        return self.setup_invoked;
    }

    fn resetArena(self: *Host) void {
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.allocator);
        self.config_dir = null;
        self.config_source = null;
        self.setup_invoked = false;
    }

    pub fn validateFileAccess(self: *Host, file_path: []const u8) Error!void {
        if (!self.sandbox_config.enable_filesystem_access) {
            self.execution_stats.sandbox_violations += 1;
            return Error.UnauthorizedFileAccess;
        }

        // Check blocked patterns first
        for (self.sandbox_config.blocked_file_patterns) |pattern| {
            if (matchesPattern(file_path, pattern)) {
                self.execution_stats.sandbox_violations += 1;
                return Error.UnauthorizedFileAccess;
            }
        }

        // If allowed patterns are specified, check them
        if (self.sandbox_config.allowed_file_patterns.len > 0) {
            var allowed = false;
            for (self.sandbox_config.allowed_file_patterns) |pattern| {
                if (matchesPattern(file_path, pattern)) {
                    allowed = true;
                    break;
                }
            }
            if (!allowed) {
                self.execution_stats.sandbox_violations += 1;
                return Error.UnauthorizedFileAccess;
            }
        }

        // Increment file operation counter
        self.execution_stats.file_operations_count += 1;
        if (self.execution_stats.file_operations_count > self.sandbox_config.max_file_operations) {
            self.execution_stats.sandbox_violations += 1;
            return Error.SandboxViolation;
        }
    }

    pub fn validateNetworkAccess(self: *Host) Error!void {
        if (!self.sandbox_config.enable_network_access) {
            self.execution_stats.sandbox_violations += 1;
            return Error.UnauthorizedNetworkAccess;
        }

        self.execution_stats.network_requests_count += 1;
        if (self.execution_stats.network_requests_count > self.sandbox_config.max_network_requests) {
            self.execution_stats.sandbox_violations += 1;
            return Error.SandboxViolation;
        }
    }

    pub fn validateMemoryUsage(self: *Host, requested_bytes: usize) Error!void {
        if (requested_bytes > self.sandbox_config.max_memory_bytes) {
            self.execution_stats.sandbox_violations += 1;
            return Error.MemoryLimitExceeded;
        }

        self.execution_stats.peak_memory_usage = @max(self.execution_stats.peak_memory_usage, requested_bytes);
    }

    pub fn startExecution(self: *Host) i64 {
        self.execution_stats.execution_count += 1;
        return std.time.milliTimestamp();
    }

    pub fn endExecution(self: *Host, start_time: i64) Error!void {
        const end_time = std.time.milliTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));

        self.execution_stats.total_execution_time_ms += duration;
        self.execution_stats.last_execution_time = start_time;

        if (duration > self.sandbox_config.max_execution_time_ms) {
            self.execution_stats.sandbox_violations += 1;
            return Error.ExecutionTimeout;
        }
    }

    pub fn getExecutionStats(self: *const Host) ExecutionStats {
        return self.execution_stats;
    }

    pub fn resetStats(self: *Host) void {
        self.execution_stats.reset();
    }

    fn matchesPattern(path: []const u8, pattern: []const u8) bool {
        // Simple glob pattern matching - supports * wildcard at end
        if (std.mem.endsWith(u8, pattern, "*")) {
            const prefix = pattern[0..pattern.len - 1];
            return std.mem.startsWith(u8, path, prefix);
        }
        return std.mem.eql(u8, path, pattern);
    }

    fn containsSetupDeclaration(buffer: []const u8) bool {
        const delimiters = " \t\r\n(){};,";
        var tokenizer = std.mem.tokenizeAny(u8, buffer, delimiters);
        var prev: ?[]const u8 = null;
        var prev2: ?[]const u8 = null;

        while (tokenizer.next()) |token| {
            if (std.mem.eql(u8, token, "setup")) {
                if (prev) |p| {
                    if (std.mem.eql(u8, p, "fn")) return true;
                    if (prev2) |p2| {
                        if (std.mem.eql(u8, p2, "pub") and std.mem.eql(u8, p, "fn")) {
                            return true;
                        }
                    }
                }
            }
            prev2 = prev;
            prev = token;
        }
        return false;
    }
};

test "host loads config and detects setup" {
    const allocator = std.testing.allocator;
    var host = try Host.init(allocator);
    defer host.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile("init.gza", "fn setup() { return 1; }");

    try host.loadConfig(tmp.path);
    try std.testing.expect(host.configSource() != null);

    try host.callSetup();
    try std.testing.expect(host.setupInvoked());
}

test "call setup without declaration fails" {
    const allocator = std.testing.allocator;
    var host = try Host.init(allocator);
    defer host.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile("init.gza", "fn other() {}");
    try host.loadConfig(tmp.path);

    try std.testing.expectError(Host.Error.SetupSymbolMissing, host.callSetup());
}

test "calling setup before loading config errors" {
    const allocator = std.testing.allocator;
    var host = try Host.init(allocator);
    defer host.deinit();

    try std.testing.expectError(Host.Error.ConfigNotLoaded, host.callSetup());
}

test "sandbox config validates file access" {
    const allocator = std.testing.allocator;
    const sandbox_config = Host.SandboxConfig{
        .blocked_file_patterns = &.{"/etc/*", "/sys/*"},
        .allowed_file_patterns = &.{"/home/*", "/tmp/*"},
    };

    var host = try Host.initWithSandbox(allocator, sandbox_config);
    defer host.deinit();

    // Should allow access to allowed patterns
    try host.validateFileAccess("/home/user/config.gza");
    try host.validateFileAccess("/tmp/test.txt");

    // Should block access to blocked patterns
    try std.testing.expectError(Host.Error.UnauthorizedFileAccess, host.validateFileAccess("/etc/passwd"));
    try std.testing.expectError(Host.Error.UnauthorizedFileAccess, host.validateFileAccess("/sys/kernel"));

    // Should block access to paths not in allowed patterns
    try std.testing.expectError(Host.Error.UnauthorizedFileAccess, host.validateFileAccess("/usr/bin/ls"));
}

test "sandbox tracks execution stats" {
    const allocator = std.testing.allocator;
    const sandbox_config = Host.SandboxConfig{
        .max_file_operations = 2,
    };

    var host = try Host.initWithSandbox(allocator, sandbox_config);
    defer host.deinit();

    // First operations should succeed
    try host.validateFileAccess("/home/test1.txt");
    try host.validateFileAccess("/home/test2.txt");

    // Third should fail due to limit
    try std.testing.expectError(Host.Error.SandboxViolation, host.validateFileAccess("/home/test3.txt"));

    const stats = host.getExecutionStats();
    try std.testing.expectEqual(@as(u32, 3), stats.file_operations_count);
    try std.testing.expectEqual(@as(u32, 1), stats.sandbox_violations);
}

test "execution timeout validation" {
    const allocator = std.testing.allocator;
    const sandbox_config = Host.SandboxConfig{
        .max_execution_time_ms = 100,
    };

    var host = try Host.initWithSandbox(allocator, sandbox_config);
    defer host.deinit();

    const start_time = host.startExecution();

    // Simulate long execution by manually setting old timestamp
    const old_start = start_time - 200;
    try std.testing.expectError(Host.Error.ExecutionTimeout, host.endExecution(old_start));

    const stats = host.getExecutionStats();
    try std.testing.expectEqual(@as(u32, 1), stats.sandbox_violations);
}

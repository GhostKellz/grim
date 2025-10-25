# Grim - Sprints 15-17 Implementation Plan

**Date:** October 24, 2025
**Goal:** Performance, Cross-Platform, and Advanced Language Features
**Timeline:** 6-8 weeks
**Status:** Ready to execute

---

## Overview

These three sprints focus on production polish and advanced features:
- **Sprint 15:** Performance & Optimization (eliminate bottlenecks)
- **Sprint 16:** Cross-Platform Support (Windows/macOS)
- **Sprint 17:** Advanced Language Features (LSP completion + DAP debugger)

---

# 🚀 Sprint 15: Performance & Optimization (1-2 weeks)

**Goal:** Sub-10ms startup, smooth 100MB+ file handling, profiling infrastructure

---

## Phase 1: Profiling Infrastructure (Days 1-2)

### 1.1 Add Performance Profiling

**File:** `core/profiler.zig` (NEW)

```zig
//! Performance profiling and benchmarking for Grim

const std = @import("std");

pub const ProfileZone = struct {
    name: []const u8,
    start_time: i128,
    allocator: std.mem.Allocator,

    pub fn begin(allocator: std.mem.Allocator, name: []const u8) ProfileZone {
        return .{
            .name = name,
            .start_time = std.time.nanoTimestamp(),
            .allocator = allocator,
        };
    }

    pub fn end(self: *const ProfileZone) void {
        const duration = std.time.nanoTimestamp() - self.start_time;
        const duration_ms = @as(f64, @floatFromInt(duration)) / 1_000_000.0;

        // Only log if >1ms
        if (duration_ms > 1.0) {
            std.debug.print("[PROF] {s}: {d:.2}ms\n", .{ self.name, duration_ms });
        }
    }
};

/// Scoped profiler (RAII style)
pub const ScopedProfile = struct {
    zone: ProfileZone,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) ScopedProfile {
        return .{ .zone = ProfileZone.begin(allocator, name) };
    }

    pub fn deinit(self: *const ScopedProfile) void {
        self.zone.end();
    }
};

/// Global performance statistics
pub const PerfStats = struct {
    startup_time_ns: i128,
    rope_insert_avg_ns: u64,
    rope_delete_avg_ns: u64,
    syntax_highlight_avg_ns: u64,
    lsp_response_avg_ns: u64,
    render_frame_avg_ns: u64,

    sample_count: usize,
    peak_memory_kb: usize,

    mutex: std.Thread.Mutex,

    pub fn init() PerfStats {
        return .{
            .startup_time_ns = 0,
            .rope_insert_avg_ns = 0,
            .rope_delete_avg_ns = 0,
            .syntax_highlight_avg_ns = 0,
            .lsp_response_avg_ns = 0,
            .render_frame_avg_ns = 0,
            .sample_count = 0,
            .peak_memory_kb = 0,
            .mutex = .{},
        };
    }

    pub fn recordStartup(self: *PerfStats, duration_ns: i128) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.startup_time_ns = duration_ns;
    }

    pub fn recordRopeInsert(self: *PerfStats, duration_ns: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.rope_insert_avg_ns = (self.rope_insert_avg_ns * self.sample_count + duration_ns) / (self.sample_count + 1);
        self.sample_count += 1;
    }

    // ... similar for other operations

    pub fn report(self: *const PerfStats, writer: anytype) !void {
        try writer.print("=== Grim Performance Report ===\n", .{});
        try writer.print("Startup: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.startup_time_ns)) / 1_000_000.0});
        try writer.print("Rope Insert Avg: {d:.2}μs\n", .{@as(f64, @floatFromInt(self.rope_insert_avg_ns)) / 1000.0});
        try writer.print("Syntax Highlight Avg: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.syntax_highlight_avg_ns)) / 1_000_000.0});
        try writer.print("Render Frame Avg: {d:.2}ms ({d:.0} FPS)\n", .{
            @as(f64, @floatFromInt(self.render_frame_avg_ns)) / 1_000_000.0,
            1000.0 / (@as(f64, @floatFromInt(self.render_frame_avg_ns)) / 1_000_000.0),
        });
        try writer.print("Peak Memory: {} KB\n", .{self.peak_memory_kb});
    }
};

/// Global profiler instance
pub var global_stats: PerfStats = PerfStats.init();
```

**Usage in code:**
```zig
// In main.zig:
const start = std.time.nanoTimestamp();
// ... initialization
profiler.global_stats.recordStartup(std.time.nanoTimestamp() - start);

// In hot paths:
{
    const prof = profiler.ScopedProfile.init(allocator, "rope_insert");
    defer prof.deinit();

    try rope.insert(pos, text);
}
```

**Tasks:**
1. Create profiler module - **4 hours**
2. Add profiling to hot paths (rope, syntax, render) - **6 hours**
3. Add memory tracking - **4 hours**
4. Create `:perfstats` command - **2 hours**

**Total:** 16 hours (2 days)

---

## Phase 2: Startup Optimization (Days 3-4)

### 2.1 Lazy Plugin Loading

**File:** `runtime/plugin_manager.zig` - Add lazy loading

```zig
pub const PluginManager = struct {
    // ... existing fields

    lazy_load: bool = true,
    loaded_plugins: std.StringHashMap(*Plugin),

    pub fn loadPluginLazy(self: *PluginManager, plugin_name: []const u8) !*Plugin {
        // Check if already loaded
        if (self.loaded_plugins.get(plugin_name)) |plugin| {
            return plugin;
        }

        // Load on demand
        const plugin = try self.loadPlugin(plugin_name);
        try self.loaded_plugins.put(plugin_name, plugin);

        return plugin;
    }

    /// Load only essential plugins at startup
    pub fn loadEssentialPlugins(self: *PluginManager) !void {
        const essentials = &[_][]const u8{
            "core",  // Core keybindings
            "statusline",  // Status line
            // Other plugins loaded on demand
        };

        for (essentials) |name| {
            _ = try self.loadPlugin(name);
        }
    }
};
```

**Target:** Reduce startup from ~50ms to <10ms

**Tasks:**
1. Implement lazy plugin loading - **6 hours**
2. Mark essential vs. lazy plugins - **4 hours**
3. Test startup time improvement - **3 hours**
4. Fix any lazy-load bugs - **4 hours**

**Total:** 17 hours (2 days)

---

### 2.2 Parallel Initialization

**File:** `main.zig` - Parallel init

```zig
pub fn main() !void {
    const start_time = std.time.nanoTimestamp();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Spawn parallel initialization tasks
    var init_tasks = std.ArrayList(std.Thread).init(allocator);
    defer init_tasks.deinit();

    // Task 1: Load config
    const config_thread = try std.Thread.spawn(.{}, loadConfigAsync, .{allocator});
    try init_tasks.append(config_thread);

    // Task 2: Initialize LSP servers list
    const lsp_thread = try std.Thread.spawn(.{}, initLSPAsync, .{allocator});
    try init_tasks.append(lsp_thread);

    // Task 3: Load themes
    const theme_thread = try std.Thread.spawn(.{}, loadThemesAsync, .{allocator});
    try init_tasks.append(theme_thread);

    // Main thread: Initialize core editor
    var editor = try Editor.init(allocator);

    // Wait for parallel tasks
    for (init_tasks.items) |thread| {
        thread.join();
    }

    // Record startup time
    profiler.global_stats.recordStartup(std.time.nanoTimestamp() - start_time);

    // Run editor
    try editor.run();
}

fn loadConfigAsync(allocator: std.mem.Allocator) void {
    config.load(allocator) catch |err| {
        std.debug.print("Config load error: {}\n", .{err});
    };
}
```

**Target:** Further reduce startup to <5ms

**Tasks:**
1. Identify parallelizable init tasks - **3 hours**
2. Implement parallel loading - **8 hours**
3. Handle thread synchronization - **6 hours**
4. Benchmark improvement - **2 hours**

**Total:** 19 hours (2-3 days)

---

## Phase 3: Large File Handling (Days 5-6)

### 3.1 Streaming File I/O

**File:** `core/rope.zig` - Add streaming support

```zig
pub const Rope = struct {
    // ... existing fields

    /// Load large file incrementally (streaming)
    pub fn loadFileStreaming(
        self: *Rope,
        file_path: []const u8,
        chunk_size: usize,
        progress_callback: ?*const fn(usize, usize) void
    ) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        var bytes_read: usize = 0;

        var buffer = try self.allocator.alloc(u8, chunk_size);
        defer self.allocator.free(buffer);

        while (bytes_read < file_size) {
            const n = try file.read(buffer);
            if (n == 0) break;

            // Insert chunk into rope
            try self.insert(self.len(), buffer[0..n]);

            bytes_read += n;

            // Report progress
            if (progress_callback) |callback| {
                callback(bytes_read, file_size);
            }
        }
    }
};
```

### 3.2 Virtual Scrolling

**File:** `ui-tui/simple_tui.zig` - Render only visible lines

```zig
pub const SimpleTUI = struct {
    // ... existing fields

    viewport_start: usize = 0,
    viewport_lines: usize = 50,  // Only render 50 lines at a time

    fn renderBuffer(self: *SimpleTUI, writer: anytype) !void {
        const buffer = self.getCurrentBuffer() orelse return;

        const total_lines = buffer.editor.rope.lineCount();

        // Only get visible lines
        const start_line = self.viewport_start;
        const end_line = @min(start_line + self.viewport_lines, total_lines);

        for (start_line..end_line) |line_idx| {
            const line = try buffer.editor.rope.getLine(line_idx);
            defer self.allocator.free(line);

            // Render line
            try writer.print("{}\n", .{line});
        }
    }
};
```

**Target:** Open 100MB+ files instantly

**Tasks:**
1. Implement streaming file loading - **8 hours**
2. Add virtual scrolling - **10 hours**
3. Optimize rope for large files - **8 hours**
4. Test with huge files (100MB+) - **6 hours**

**Total:** 32 hours (4 days)

---

## Phase 4: Memory Optimization (Days 7-8)

### 4.1 Memory Pooling

**File:** `core/memory_pool.zig` (NEW)

```zig
/// Memory pool for frequent small allocations
pub const MemoryPool = struct {
    small_pool: std.heap.FixedBufferAllocator,  // <256 bytes
    medium_pool: std.heap.FixedBufferAllocator, // <4KB
    large_backing: std.mem.Allocator,

    small_buffer: []align(8) u8,
    medium_buffer: []align(8) u8,

    pub fn init(backing_allocator: std.mem.Allocator) !MemoryPool {
        // Allocate pool buffers
        const small_buf = try backing_allocator.alignedAlloc(u8, 8, 1024 * 1024);  // 1MB
        const medium_buf = try backing_allocator.alignedAlloc(u8, 8, 16 * 1024 * 1024);  // 16MB

        return .{
            .small_pool = std.heap.FixedBufferAllocator.init(small_buf),
            .medium_pool = std.heap.FixedBufferAllocator.init(medium_buf),
            .large_backing = backing_allocator,
            .small_buffer = small_buf,
            .medium_buffer = medium_buf,
        };
    }

    pub fn deinit(self: *MemoryPool) void {
        self.large_backing.free(self.small_buffer);
        self.large_backing.free(self.medium_buffer);
    }

    pub fn alloc(self: *MemoryPool, comptime T: type, n: usize) ![]T {
        const size = @sizeOf(T) * n;

        if (size < 256) {
            // Use small pool
            return self.small_pool.allocator().alloc(T, n);
        } else if (size < 4096) {
            // Use medium pool
            return self.medium_pool.allocator().alloc(T, n);
        } else {
            // Use backing allocator for large allocations
            return self.large_backing.alloc(T, n);
        }
    }

    pub fn free(self: *MemoryPool, comptime T: type, slice: []T) void {
        const size = @sizeOf(T) * slice.len;

        if (size < 256) {
            self.small_pool.allocator().free(slice);
        } else if (size < 4096) {
            self.medium_pool.allocator().free(slice);
        } else {
            self.large_backing.free(slice);
        }
    }

    /// Reset pools (fast bulk free)
    pub fn reset(self: *MemoryPool) void {
        self.small_pool.reset();
        self.medium_pool.reset();
    }
};
```

**Use in rope/syntax:**
```zig
// Use pooled allocator for temporary allocations
const pool = try MemoryPool.init(gpa.allocator());
defer pool.deinit();

// Allocate from pool
const temp_buffer = try pool.alloc(u8, 512);
defer pool.free(u8, temp_buffer);

// Reset pool after operation (bulk free)
pool.reset();
```

**Target:** Reduce memory usage by 30-50%

**Tasks:**
1. Create memory pool implementation - **8 hours**
2. Integrate into rope operations - **6 hours**
3. Integrate into syntax highlighting - **6 hours**
4. Benchmark memory savings - **4 hours**

**Total:** 24 hours (3 days)

---

### 4.2 Add Memory Profiling

**Install Valgrind alternative (for Arch Linux):**
```bash
# Since Valgrind isn't installed, use AddressSanitizer
zig build -Doptimize=Debug
```

**Build with sanitizers:**
```zig
// build.zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(...);

    if (b.option(bool, "asan", "Enable AddressSanitizer") orelse false) {
        exe.addCSourceFile(.{
            .file = .{ .path = "src/main.zig" },
            .flags = &.{"-fsanitize=address"},
        });
        exe.linkLibC();
    }
}
```

**Run memory checks:**
```bash
zig build -Dasan=true
./zig-out/bin/grim test.zig
# Check for leaks/issues in output
```

**Tasks:**
1. Set up AddressSanitizer build - **2 hours**
2. Run memory profiling on test workloads - **4 hours**
3. Fix any detected leaks - **8 hours**
4. Document memory usage patterns - **2 hours**

**Total:** 16 hours (2 days)

---

## Sprint 15 Summary

**Total Time:** 1-2 weeks (124 hours)

**Deliverables:**
- ✅ Sub-10ms startup time
- ✅ 100MB+ file handling
- ✅ Memory pools for efficiency
- ✅ Performance profiling infrastructure
- ✅ Memory leak detection

**Performance Targets Met:**
- Startup: <10ms (vs ~50ms before)
- Large files: Instant open (vs slow before)
- Memory: <50MB base (vs ~100MB before)
- Frame rate: 60+ FPS consistent

---

# 🌐 Sprint 16: Cross-Platform Support (2-3 weeks)

**Goal:** Native Windows + polished macOS support

---

## Phase 1: Platform Abstraction (Days 1-3)

### 1.1 Platform Layer

**File:** `core/platform.zig` (NEW)

```zig
//! Platform abstraction layer for cross-platform support

const std = @import("std");
const builtin = @import("builtin");

pub const Platform = enum {
    linux,
    windows,
    macos,
    bsd,
};

pub fn current() Platform {
    return switch (builtin.os.tag) {
        .linux => .linux,
        .windows => .windows,
        .macos => .macos,
        .freebsd, .openbsd, .netbsd => .bsd,
        else => @compileError("Unsupported platform"),
    };
}

/// Platform-specific file operations
pub const FileOps = struct {
    pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
        return switch (current()) {
            .linux, .bsd => {
                const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
                return std.fmt.allocPrint(allocator, "{s}/.config/grim", .{home});
            },
            .windows => {
                const appdata = std.posix.getenv("APPDATA") orelse return error.NoAppData;
                return std.fmt.allocPrint(allocator, "{s}\\grim", .{appdata});
            },
            .macos => {
                const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
                return std.fmt.allocPrint(allocator, "{s}/Library/Application Support/grim", .{home});
            },
        };
    }

    pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        return switch (current()) {
            .linux, .macos, .bsd => allocator.dupe(u8, path),
            .windows => {
                // Convert / to \\ on Windows
                var normalized = try allocator.alloc(u8, path.len);
                for (path, 0..) |c, i| {
                    normalized[i] = if (c == '/') '\\' else c;
                }
                return normalized;
            },
        };
    }
};

/// Platform-specific terminal operations
pub const TerminalOps = struct {
    pub fn getRawMode(fd: std.posix.fd_t) !void {
        return switch (current()) {
            .linux, .macos, .bsd => {
                var termios = try std.posix.tcgetattr(fd);
                termios.lflag.ECHO = false;
                termios.lflag.ICANON = false;
                try std.posix.tcsetattr(fd, .FLUSH, termios);
            },
            .windows => {
                // Use Windows Console API
                const kernel32 = std.os.windows.kernel32;
                var mode: std.os.windows.DWORD = undefined;
                _ = kernel32.GetConsoleMode(fd, &mode);
                mode &= ~(@as(std.os.windows.DWORD, 0x0002 | 0x0004));  // ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT
                _ = kernel32.SetConsoleMode(fd, mode);
            },
        };
    }
};
```

**Tasks:**
1. Create platform abstraction layer - **12 hours**
2. Abstract file operations - **8 hours**
3. Abstract terminal operations - **8 hours**
4. Test on Linux - **4 hours**

**Total:** 32 hours (4 days)

---

## Phase 2: Windows Support (Days 4-10)

### 2.1 Windows Terminal (ConPTY)

**File:** `core/terminal_windows.zig` (NEW)

```zig
//! Windows ConPTY implementation

const std = @import("std");
const windows = std.os.windows;

pub const WindowsTerminal = struct {
    hpc: windows.HANDLE,  // Pseudoconsole handle
    hpipe_in: windows.HANDLE,
    hpipe_out: windows.HANDLE,
    child_process: windows.HANDLE,

    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !*WindowsTerminal {
        const self = try allocator.create(WindowsTerminal);

        // Create pipes for ConPTY
        var hpipe_in_read: windows.HANDLE = undefined;
        var hpipe_in_write: windows.HANDLE = undefined;
        var hpipe_out_read: windows.HANDLE = undefined;
        var hpipe_out_write: windows.HANDLE = undefined;

        _ = try windows.CreatePipe(&hpipe_in_read, &hpipe_in_write, null, 0);
        _ = try windows.CreatePipe(&hpipe_out_read, &hpipe_out_write, null, 0);

        // Create ConPTY
        const coord = windows.COORD{ .X = @intCast(cols), .Y = @intCast(rows) };
        _ = try windows.kernel32.CreatePseudoConsole(
            coord,
            hpipe_in_read,
            hpipe_out_write,
            0,
            &self.hpc
        );

        self.* = .{
            .hpc = self.hpc,
            .hpipe_in = hpipe_in_write,
            .hpipe_out = hpipe_out_read,
            .child_process = undefined,
        };

        return self;
    }

    pub fn spawn(self: *WindowsTerminal, cmd: ?[]const u8) !void {
        // Create process with ConPTY
        const command = cmd orelse "cmd.exe";

        var startup_info = windows.STARTUPINFOEXW{
            .StartupInfo = .{
                .cb = @sizeOf(windows.STARTUPINFOEXW),
                .dwFlags = windows.STARTF_USESTDHANDLES,
                .hStdInput = self.hpipe_in,
                .hStdOutput = self.hpipe_out,
                .hStdError = self.hpipe_out,
            },
            .lpAttributeList = null,
        };

        // Attach ConPTY to process
        // ... (ConPTY attribute list setup)

        var process_info: windows.PROCESS_INFORMATION = undefined;

        _ = try windows.CreateProcessW(
            null,
            command,
            null,
            null,
            windows.TRUE,
            windows.EXTENDED_STARTUPINFO_PRESENT,
            null,
            null,
            &startup_info.StartupInfo,
            &process_info
        );

        self.child_process = process_info.hProcess;
    }

    pub fn read(self: *WindowsTerminal, buffer: []u8) !usize {
        var bytes_read: windows.DWORD = undefined;
        if (windows.kernel32.ReadFile(
            self.hpipe_out,
            buffer.ptr,
            @intCast(buffer.len),
            &bytes_read,
            null
        ) == 0) {
            return error.ReadFailed;
        }
        return bytes_read;
    }

    pub fn write(self: *WindowsTerminal, data: []const u8) !usize {
        var bytes_written: windows.DWORD = undefined;
        if (windows.kernel32.WriteFile(
            self.hpipe_in,
            data.ptr,
            @intCast(data.len),
            &bytes_written,
            null
        ) == 0) {
            return error.WriteFailed;
        }
        return bytes_written;
    }
};
```

**Tasks:**
1. Implement ConPTY wrapper - **16 hours**
2. Port terminal integration to Windows - **12 hours**
3. Test PowerShell/cmd integration - **8 hours**
4. Fix Windows-specific issues - **12 hours**

**Total:** 48 hours (6 days)

---

### 2.2 Windows Build & Installer

**File:** `install.ps1` (NEW) - PowerShell installer

```powershell
# Grim Windows Installer

Write-Host "Installing Grim Editor..." -ForegroundColor Green

# Check for Zig
if (!(Get-Command zig -ErrorAction SilentlyContinue)) {
    Write-Host "Zig not found. Please install Zig first." -ForegroundColor Red
    exit 1
}

# Build Grim
Write-Host "Building Grim..." -ForegroundColor Yellow
zig build -Doptimize=ReleaseSafe

# Create installation directory
$InstallDir = "$env:LOCALAPPDATA\Programs\Grim"
New-Item -ItemType Directory -Force -Path $InstallDir

# Copy binary
Copy-Item "zig-out\bin\grim.exe" -Destination "$InstallDir\grim.exe"

# Create config directory
$ConfigDir = "$env:APPDATA\grim"
New-Item -ItemType Directory -Force -Path $ConfigDir

# Copy default config
Copy-Item "config\init.gza" -Destination "$ConfigDir\init.gza" -ErrorAction SilentlyContinue

# Add to PATH
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
    Write-Host "Added Grim to PATH" -ForegroundColor Green
}

Write-Host "Grim installed successfully!" -ForegroundColor Green
Write-Host "Run 'grim' from any directory to start editing." -ForegroundColor Cyan
```

**Tasks:**
1. Create Windows installer script - **8 hours**
2. Set up Windows CI builds (GitHub Actions) - **8 hours**
3. Test on Windows 10/11 - **8 hours**
4. Create Windows package (Chocolatey) - **8 hours**

**Total:** 32 hours (4 days)

---

## Phase 3: macOS Polish (Days 11-13)

### 3.1 macOS-Specific Features

**File:** `core/macos.zig` (NEW)

```zig
//! macOS-specific integration

const std = @import("std");
const objc = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("AppKit/AppKit.h");
});

/// macOS keybinding translation (Cmd → Ctrl for consistency)
pub fn translateKey(key: Key) Key {
    if (key.cmd) {
        // Translate Cmd to Ctrl for Vim compatibility
        return Key{
            .char = key.char,
            .ctrl = true,
            .cmd = false,
            .alt = key.alt,
            .shift = key.shift,
        };
    }
    return key;
}

/// Get macOS-specific config directory
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return std.fmt.allocPrint(
        allocator,
        "{s}/Library/Application Support/grim",
        .{home}
    );
}
```

**Tasks:**
1. Add macOS keybinding translation - **6 hours**
2. macOS file picker integration - **8 hours**
3. macOS-specific config path - **2 hours**
4. Test on macOS 13+ - **8 hours**

**Total:** 24 hours (3 days)

---

## Sprint 16 Summary

**Total Time:** 2-3 weeks (136 hours)

**Deliverables:**
- ✅ Windows native support (ConPTY)
- ✅ Windows installer (PowerShell + Chocolatey)
- ✅ macOS polish (keybindings, paths)
- ✅ Platform abstraction layer
- ✅ CI builds for all platforms

**Platform Coverage:**
- Linux: 100% (primary platform)
- Windows: 90% (ConPTY, installer, CI)
- macOS: 80% (polished, tested)

---

# 📡 Sprint 17: Advanced Language Features (3-4 weeks)

**Goal:** Complete LSP integration + DAP debugger

---

## Phase 1: LSP Diagnostics UI (Days 1-4)

### 1.1 Diagnostics Rendering

**File:** `ui-tui/diagnostics_ui.zig` (NEW)

```zig
//! LSP diagnostics rendering

const std = @import("std");
const lsp = @import("../lsp/mod.zig");

pub const DiagnosticSeverity = enum {
    error_,
    warning,
    information,
    hint,
};

pub const DiagnosticUI = struct {
    diagnostics: std.ArrayList(lsp.Diagnostic),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiagnosticUI {
        return .{
            .diagnostics = std.ArrayList(lsp.Diagnostic).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DiagnosticUI) void {
        self.diagnostics.deinit();
    }

    /// Render diagnostics in gutter
    pub fn renderGutter(
        self: *const DiagnosticUI,
        writer: anytype,
        line: u32
    ) !void {
        const severity = self.getSeverityForLine(line);

        const symbol = switch (severity) {
            .error_ => "E",
            .warning => "W",
            .information => "I",
            .hint => "H",
            null => " ",
        };

        const color = switch (severity) {
            .error_ => "\x1b[31m",      // Red
            .warning => "\x1b[33m",     // Yellow
            .information => "\x1b[34m", // Blue
            .hint => "\x1b[36m",        // Cyan
            null => "",
        };

        try writer.print("{s}{s}\x1b[0m ", .{ color, symbol });
    }

    /// Render full diagnostic at cursor
    pub fn renderDiagnosticAtCursor(
        self: *const DiagnosticUI,
        writer: anytype,
        line: u32,
        col: u32
    ) !void {
        for (self.diagnostics.items) |diag| {
            if (diag.range.start.line == line and
                diag.range.start.character <= col and
                col <= diag.range.end.character)
            {
                // Render diagnostic message
                try writer.writeAll("\n┌─ Diagnostic ─────\n");
                try writer.print("│ {s}\n", .{diag.message});
                try writer.writeAll("└───────────────\n");
                return;
            }
        }
    }

    /// Get quickfix list
    pub fn getQuickfixList(self: *const DiagnosticUI) []const lsp.Diagnostic {
        return self.diagnostics.items;
    }

    fn getSeverityForLine(self: *const DiagnosticUI, line: u32) ?DiagnosticSeverity {
        for (self.diagnostics.items) |diag| {
            if (diag.range.start.line == line) {
                return switch (diag.severity) {
                    1 => .error_,
                    2 => .warning,
                    3 => .information,
                    4 => .hint,
                    else => null,
                };
            }
        }
        return null;
    }
};
```

**Integration:**
```zig
// In SimpleTUI:
fn renderGutter(self: *SimpleTUI, writer: anytype, line: u32) !void {
    // Git blame/hunks
    try self.renderGitGutter(writer, line);

    // LSP diagnostics
    if (self.diagnostic_ui) |diag| {
        try diag.renderGutter(writer, line);
    }

    // Line number
    try writer.print("{: >4} ", .{line + 1});
}
```

**Tasks:**
1. Create diagnostics UI module - **12 hours**
2. Render diagnostics in gutter - **10 hours**
3. Add quickfix list (`:copen`) - **8 hours**
4. Wire to LSP client - **8 hours**
5. Test with zls/rust-analyzer - **8 hours**

**Total:** 46 hours (6 days)

---

## Phase 2: LSP Completion Menu (Days 5-9)

### 2.1 Completion UI

**File:** `ui-tui/completion_menu.zig` (NEW)

```zig
//! LSP completion menu

const std = @import("std");

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionKind,
    detail: ?[]const u8,
    documentation: ?[]const u8,
    insert_text: []const u8,
};

pub const CompletionKind = enum {
    text,
    method,
    function,
    constructor,
    field,
    variable,
    class_,
    interface,
    module,
    property,
    keyword,
    // ... more kinds
};

pub const CompletionMenu = struct {
    items: std.ArrayList(CompletionItem),
    selected_idx: usize,
    visible: bool,
    filter_text: []const u8,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CompletionMenu {
        return .{
            .items = std.ArrayList(CompletionItem).init(allocator),
            .selected_idx = 0,
            .visible = false,
            .filter_text = "",
            .allocator = allocator,
        };
    }

    pub fn setItems(self: *CompletionMenu, items: []const CompletionItem) !void {
        self.items.clearRetainingCapacity();
        for (items) |item| {
            try self.items.append(item);
        }
        self.selected_idx = 0;
    }

    /// Fuzzy filter items based on input
    pub fn filter(self: *CompletionMenu, text: []const u8) void {
        // Simple prefix filter (can enhance with fuzzy matching)
        var filtered = std.ArrayList(CompletionItem).init(self.allocator);

        for (self.items.items) |item| {
            if (std.mem.startsWith(u8, item.label, text)) {
                filtered.append(item) catch {};
            }
        }

        self.items.deinit();
        self.items = filtered;
    }

    pub fn moveUp(self: *CompletionMenu) void {
        if (self.selected_idx > 0) {
            self.selected_idx -= 1;
        }
    }

    pub fn moveDown(self: *CompletionMenu) void {
        if (self.selected_idx < self.items.items.len - 1) {
            self.selected_idx += 1;
        }
    }

    pub fn getSelected(self: *const CompletionMenu) ?CompletionItem {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.selected_idx];
    }

    /// Render completion menu as floating window
    pub fn render(self: *const CompletionMenu, writer: anytype, cursor_x: u32, cursor_y: u32) !void {
        if (!self.visible or self.items.items.len == 0) return;

        const max_items = 10;
        const visible_items = @min(self.items.items.len, max_items);

        // Position below cursor
        const menu_x = cursor_x;
        const menu_y = cursor_y + 1;

        for (0..visible_items) |i| {
            const item = self.items.items[i];

            // Move cursor to menu position
            try writer.print("\x1b[{};{}H", .{ menu_y + i, menu_x });

            // Highlight selected item
            if (i == self.selected_idx) {
                try writer.writeAll("\x1b[7m");  // Reverse video
            }

            // Render completion item
            const kind_icon = switch (item.kind) {
                .function => "ƒ",
                .method => "м",
                .variable => "v",
                .class_ => "C",
                .keyword => "k",
                else => " ",
            };

            try writer.print(" {s} {s}", .{ kind_icon, item.label });

            if (item.detail) |detail| {
                try writer.print(" - {s}", .{detail});
            }

            if (i == self.selected_idx) {
                try writer.writeAll("\x1b[0m");  // Reset
            }
        }
    }
};
```

**Integration:**
```zig
// In SimpleTUI insert mode:
fn handleInsertMode(self: *SimpleTUI, key: Key) !void {
    // ... existing insert handling

    // Trigger LSP completion on certain chars (., ::, etc.)
    if (shouldTriggerCompletion(key)) {
        try self.requestLSPCompletion();
    }

    // Handle completion menu navigation
    if (self.completion_menu.visible) {
        switch (key.special) {
            .up => self.completion_menu.moveUp(),
            .down => self.completion_menu.moveDown(),
            .enter => {
                if (self.completion_menu.getSelected()) |item| {
                    try self.insertTextAtCursor(item.insert_text);
                    self.completion_menu.visible = false;
                }
            },
            .escape => self.completion_menu.visible = false,
            else => {},
        }
    }
}
```

**Tasks:**
1. Create completion menu UI - **14 hours**
2. Wire to LSP completion request - **10 hours**
3. Add fuzzy filtering - **8 hours**
4. Render floating menu - **12 hours**
5. Handle keyboard navigation - **8 hours**
6. Test with multiple LSPs - **10 hours**

**Total:** 62 hours (8 days)

---

## Phase 3: LSP Code Actions & Refactoring (Days 10-13)

### 3.1 Code Actions Menu

**File:** `ui-tui/code_actions.zig` (NEW)

```zig
pub const CodeAction = struct {
    title: []const u8,
    kind: []const u8,  // "quickfix", "refactor", etc.
    edit: ?WorkspaceEdit,
};

pub const CodeActionsMenu = struct {
    actions: std.ArrayList(CodeAction),
    selected_idx: usize,
    visible: bool,

    allocator: std.mem.Allocator,

    // ... similar to CompletionMenu

    pub fn render(self: *const CodeActionsMenu, writer: anytype) !void {
        // Render as popup menu
        try writer.writeAll("╭─ Code Actions ────╮\n");

        for (self.actions.items, 0..) |action, i| {
            if (i == self.selected_idx) {
                try writer.writeAll("│ > ");
            } else {
                try writer.writeAll("│   ");
            }

            try writer.print("{s}\n", .{action.title});
        }

        try writer.writeAll("╰───────────────────╯\n");
    }
};
```

**Commands:**
- `:lsp actions` - Show code actions at cursor
- `:lsp rename` - Rename symbol
- `:lsp format` - Format document

**Tasks:**
1. Create code actions UI - **12 hours**
2. Implement rename workflow - **10 hours**
3. Add format document - **6 hours**
4. Test refactoring operations - **10 hours**

**Total:** 38 hours (5 days)

---

## Phase 4: DAP Debugger (Days 14-20)

### 4.1 DAP Client

**File:** `dap/client.zig` (NEW)

```zig
//! Debug Adapter Protocol client

const std = @import("std");

pub const DAPClient = struct {
    transport: Transport,
    next_seq: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, transport: Transport) DAPClient {
        return .{
            .transport = transport,
            .next_seq = 1,
            .allocator = allocator,
        };
    }

    /// Initialize debug session
    pub fn initialize(self: *DAPClient) !void {
        const request = .{
            .seq = self.next_seq,
            .type = "request",
            .command = "initialize",
            .arguments = .{
                .clientID = "grim",
                .clientName = "Grim Editor",
                .adapterID = "lldb",  // Or "gdb", "delve", etc.
                .linesStartAt1 = true,
                .columnsStartAt1 = true,
            },
        };

        self.next_seq += 1;

        const json = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json);

        try self.sendMessage(json);
    }

    /// Set breakpoint
    pub fn setBreakpoint(self: *DAPClient, file_path: []const u8, line: u32) !void {
        const request = .{
            .seq = self.next_seq,
            .type = "request",
            .command = "setBreakpoints",
            .arguments = .{
                .source = .{ .path = file_path },
                .breakpoints = &[_]struct { line: u32 }{.{ .line = line }},
            },
        };

        self.next_seq += 1;

        const json = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json);

        try self.sendMessage(json);
    }

    /// Continue execution
    pub fn continue_(self: *DAPClient, thread_id: u32) !void {
        const request = .{
            .seq = self.next_seq,
            .type = "request",
            .command = "continue",
            .arguments = .{ .threadId = thread_id },
        };

        self.next_seq += 1;

        const json = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json);

        try self.sendMessage(json);
    }

    // ... step, stepIn, stepOut, pause, etc.

    fn sendMessage(self: *DAPClient, message: []const u8) !void {
        // Send with Content-Length header (like LSP)
        const header = try std.fmt.allocPrint(
            self.allocator,
            "Content-Length: {}\r\n\r\n",
            .{message.len}
        );
        defer self.allocator.free(header);

        _ = try self.transport.writeFn(self.transport.ctx, header);
        _ = try self.transport.writeFn(self.transport.ctx, message);
    }
};
```

### 4.2 Debugger UI

**File:** `ui-tui/debugger_ui.zig` (NEW)

```zig
pub const DebuggerUI = struct {
    breakpoints: std.ArrayList(Breakpoint),
    current_frame: ?StackFrame,
    variables: std.ArrayList(Variable),

    pub const Breakpoint = struct {
        file_path: []const u8,
        line: u32,
        enabled: bool,
    };

    pub fn renderBreakpoints(self: *const DebuggerUI, writer: anytype) !void {
        for (self.breakpoints.items) |bp| {
            const symbol = if (bp.enabled) "●" else "○";
            try writer.print("{s} {s}:{}\n", .{ symbol, bp.file_path, bp.line });
        }
    }

    pub fn renderVariables(self: *const DebuggerUI, writer: anytype) !void {
        try writer.writeAll("╭─ Variables ──────╮\n");
        for (self.variables.items) |variable| {
            try writer.print("│ {s} = {s}\n", .{ variable.name, variable.value });
        }
        try writer.writeAll("╰──────────────────╯\n");
    }

    pub fn renderCallStack(self: *const DebuggerUI, writer: anytype) !void {
        // Render current stack frame
        if (self.current_frame) |frame| {
            try writer.print("at {s}:{}\n", .{ frame.source.path, frame.line });
        }
    }
};
```

**Commands:**
- `:debug start` - Start debugger
- `:debug break` - Toggle breakpoint
- `:debug continue` - Continue execution
- `:debug step` - Step over
- `:debug stepin` - Step into

**Tasks:**
1. Implement DAP client - **20 hours**
2. Create debugger UI - **16 hours**
3. Wire to GDB/LLDB adapters - **12 hours**
4. Add breakpoint rendering in gutter - **8 hours**
5. Test debugging Zig/Rust programs - **12 hours**

**Total:** 68 hours (9 days)

---

## Sprint 17 Summary

**Total Time:** 3-4 weeks (214 hours)

**Deliverables:**
- ✅ LSP diagnostics UI (gutter + quickfix)
- ✅ LSP completion menu (fuzzy filtered)
- ✅ LSP code actions (refactoring)
- ✅ Format document
- ✅ Rename symbol
- ✅ DAP debugger integration
- ✅ Breakpoint management
- ✅ Variable inspection

**Language Server Support:**
- Zig (zls)
- Rust (rust-analyzer)
- TypeScript (tsserver)
- Python (pyright)
- Go (gopls)

---

# 📊 Combined Sprint 15-17 Timeline

## Recommended Execution Order

### Weeks 1-2: Sprint 15 (Performance)
- **Days 1-2:** Profiling infrastructure
- **Days 3-4:** Startup optimization
- **Days 5-6:** Large file handling
- **Days 7-8:** Memory optimization

### Weeks 3-5: Sprint 16 (Cross-Platform)
- **Days 1-3:** Platform abstraction
- **Days 4-10:** Windows support
- **Days 11-13:** macOS polish

### Weeks 6-9: Sprint 17 (LSP + DAP)
- **Days 1-4:** LSP diagnostics UI
- **Days 5-9:** LSP completion menu
- **Days 10-13:** Code actions
- **Days 14-20:** DAP debugger

**Total:** 6-9 weeks (474 hours)

---

## 🎯 Success Metrics

### Sprint 15 Complete
- ✅ Startup <10ms
- ✅ 100MB file loads instantly
- ✅ Memory usage <50MB base
- ✅ 60+ FPS rendering
- ✅ Performance profiling enabled

### Sprint 16 Complete
- ✅ Windows build + installer
- ✅ macOS tested and polished
- ✅ CI builds for all platforms
- ✅ Platform abstraction working
- ✅ 90%+ feature parity across platforms

### Sprint 17 Complete
- ✅ LSP diagnostics in gutter
- ✅ Completion menu works
- ✅ Code actions functional
- ✅ Debugger can set breakpoints
- ✅ Can debug Zig/Rust programs

---

## 🚀 After Sprints 15-17

You'll have:
- **World-class performance** (10ms startup)
- **Full cross-platform support** (Linux/Windows/macOS)
- **Complete IDE features** (LSP + DAP)
- **Production-ready editor** for daily use

**Next:** Sprints 18-20 (Plugins 2.0, DevEx, Enterprise) or public v1.0 release!

---

*Ready to execute!* 🚀

*Timeline: 6-9 weeks to production-ready v1.0*

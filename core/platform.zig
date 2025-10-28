//! Platform Detection and Optimization
//!
//! Detects hardware capabilities and selects optimal code paths at runtime.
//! Supports:
//! - Wayland vs X11 detection
//! - GPU detection (NVIDIA, AMD, Intel)
//! - CPU features (AVX-512, SIMD)
//! - io_uring availability
//! - tmux detection

const std = @import("std");

pub const PlatformCapabilities = struct {
    // Display server
    has_wayland: bool,
    has_x11: bool,
    wayland_display: ?[]const u8,

    // GPU capabilities
    has_nvidia_gpu: bool,
    has_amd_gpu: bool,
    has_intel_gpu: bool,
    gpu_vendor: ?GpuVendor,

    // CPU features
    has_avx512: bool,
    has_avx2: bool,
    has_sse42: bool,
    cpu_model: ?[]const u8,
    has_amd_3d_vcache: bool,

    // Kernel features
    has_io_uring: bool,
    kernel_version: ?[]const u8,

    // Terminal multiplexer
    is_tmux: bool,
    is_screen: bool,
    tmux_version: ?[]const u8,

    // Platform info
    os_name: []const u8,
    arch: []const u8,

    pub const GpuVendor = enum {
        nvidia,
        amd,
        intel,
        other,
    };

    /// Detect all platform capabilities
    pub fn detect(allocator: std.mem.Allocator) !PlatformCapabilities {
        return PlatformCapabilities{
            .has_wayland = detectWayland(),
            .has_x11 = detectX11(),
            .wayland_display = getWaylandDisplay(allocator) catch null,
            .has_nvidia_gpu = detectNvidiaGPU(),
            .has_amd_gpu = detectAmdGPU(),
            .has_intel_gpu = detectIntelGPU(),
            .gpu_vendor = detectGpuVendor(),
            .has_avx512 = detectAVX512(),
            .has_avx2 = detectAVX2(),
            .has_sse42 = detectSSE42(),
            .cpu_model = getCpuModel(allocator) catch null,
            .has_amd_3d_vcache = detectAmd3DVCache(),
            .has_io_uring = detectIoUring(),
            .kernel_version = getKernelVersion(allocator) catch null,
            .is_tmux = detectTmux(),
            .is_screen = detectScreen(),
            .tmux_version = getTmuxVersion(allocator) catch null,
            .os_name = getOSName(),
            .arch = getArchitecture(),
        };
    }

    /// Free allocated strings
    pub fn deinit(self: *PlatformCapabilities, allocator: std.mem.Allocator) void {
        if (self.wayland_display) |display| {
            allocator.free(display);
        }
        if (self.cpu_model) |model| {
            allocator.free(model);
        }
        if (self.kernel_version) |version| {
            allocator.free(version);
        }
        if (self.tmux_version) |version| {
            allocator.free(version);
        }
    }

    /// Print detected capabilities
    pub fn print(self: *const PlatformCapabilities) void {
        std.log.info("=== Platform Capabilities ===", .{});
        std.log.info("OS: {s} ({s})", .{self.os_name, self.arch});

        std.log.info("Display:", .{});
        if (self.has_wayland) {
            std.log.info("  Wayland: yes ({s})", .{self.wayland_display orelse "unknown"});
        } else {
            std.log.info("  Wayland: no", .{});
        }
        if (self.has_x11) {
            std.log.info("  X11: yes", .{});
        } else {
            std.log.info("  X11: no", .{});
        }

        std.log.info("GPU:", .{});
        if (self.gpu_vendor) |vendor| {
            std.log.info("  Vendor: {s}", .{@tagName(vendor)});
        }
        std.log.info("  NVIDIA: {}", .{self.has_nvidia_gpu});
        std.log.info("  AMD: {}", .{self.has_amd_gpu});
        std.log.info("  Intel: {}", .{self.has_intel_gpu});

        std.log.info("CPU:", .{});
        if (self.cpu_model) |model| {
            std.log.info("  Model: {s}", .{model});
        }
        std.log.info("  AVX-512: {}", .{self.has_avx512});
        std.log.info("  AVX2: {}", .{self.has_avx2});
        std.log.info("  SSE4.2: {}", .{self.has_sse42});
        std.log.info("  AMD 3D V-Cache: {}", .{self.has_amd_3d_vcache});

        std.log.info("Kernel:", .{});
        if (self.kernel_version) |version| {
            std.log.info("  Version: {s}", .{version});
        }
        std.log.info("  io_uring: {}", .{self.has_io_uring});

        std.log.info("Terminal:", .{});
        std.log.info("  tmux: {}", .{self.is_tmux});
        std.log.info("  screen: {}", .{self.is_screen});
        if (self.tmux_version) |version| {
            std.log.info("  tmux version: {s}", .{version});
        }
    }
};

// === Display Server Detection ===

fn detectWayland() bool {
    return std.posix.getenv("WAYLAND_DISPLAY") != null;
}

fn detectX11() bool {
    return std.posix.getenv("DISPLAY") != null;
}

fn getWaylandDisplay(allocator: std.mem.Allocator) ![]const u8 {
    const display = std.posix.getenv("WAYLAND_DISPLAY") orelse return error.NoWayland;
    return try allocator.dupe(u8, display);
}

// === GPU Detection ===

fn detectNvidiaGPU() bool {
    // Check for /dev/nvidia0
    var devices = std.fs.openDirAbsolute("/dev", .{}) catch return false;
    defer devices.close();

    _ = devices.statFile("nvidia0") catch return false;
    return true;
}

fn detectAmdGPU() bool {
    // Check for /dev/dri/card* with AMD vendor
    var dri_dir = std.fs.openDirAbsolute("/dev/dri", .{}) catch return false;
    defer dri_dir.close();

    // Check if any card exists (simplified check)
    _ = dri_dir.statFile("card0") catch return false;
    return true;
}

fn detectIntelGPU() bool {
    // Similar to AMD, check for Intel integrated graphics
    var dri_dir = std.fs.openDirAbsolute("/dev/dri", .{}) catch return false;
    defer dri_dir.close();

    _ = dri_dir.statFile("card0") catch return false;
    return true;
}

fn detectGpuVendor() ?PlatformCapabilities.GpuVendor {
    if (detectNvidiaGPU()) return .nvidia;
    if (detectAmdGPU()) return .amd;
    if (detectIntelGPU()) return .intel;
    return null;
}

// === CPU Detection ===

fn detectAVX512() bool {
    // Check /proc/cpuinfo for avx512f flag
    const cpuinfo = std.fs.cwd().openFile("/proc/cpuinfo", .{}) catch return false;
    defer cpuinfo.close();

    var buf: [4096]u8 = undefined;
    const n = cpuinfo.readAll(&buf) catch return false;

    return std.mem.indexOf(u8, buf[0..n], "avx512f") != null;
}

fn detectAVX2() bool {
    const cpuinfo = std.fs.cwd().openFile("/proc/cpuinfo", .{}) catch return false;
    defer cpuinfo.close();

    var buf: [4096]u8 = undefined;
    const n = cpuinfo.readAll(&buf) catch return false;

    return std.mem.indexOf(u8, buf[0..n], "avx2") != null;
}

fn detectSSE42() bool {
    const cpuinfo = std.fs.cwd().openFile("/proc/cpuinfo", .{}) catch return false;
    defer cpuinfo.close();

    var buf: [4096]u8 = undefined;
    const n = cpuinfo.readAll(&buf) catch return false;

    return std.mem.indexOf(u8, buf[0..n], "sse4_2") != null;
}

fn getCpuModel(allocator: std.mem.Allocator) ![]const u8 {
    const cpuinfo = try std.fs.cwd().openFile("/proc/cpuinfo", .{});
    defer cpuinfo.close();

    var buf: [4096]u8 = undefined;
    const n = try cpuinfo.readAll(&buf);

    // Find "model name" line
    var iter = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "model name")) {
            // Extract value after ": "
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const model = std.mem.trim(u8, line[colon_pos + 2..], " \t");
                return try allocator.dupe(u8, model);
            }
        }
    }

    return error.CpuModelNotFound;
}

fn detectAmd3DVCache() bool {
    const cpuinfo = std.fs.cwd().openFile("/proc/cpuinfo", .{}) catch return false;
    defer cpuinfo.close();

    var buf: [4096]u8 = undefined;
    const n = cpuinfo.readAll(&buf) catch return false;

    // AMD 3D V-Cache CPUs have "AMD Ryzen" and "3D" in model name
    return std.mem.indexOf(u8, buf[0..n], "AMD Ryzen") != null and
           std.mem.indexOf(u8, buf[0..n], "3D") != null;
}

// === Kernel Detection ===

fn detectIoUring() bool {
    // Check if io_uring syscall is available by trying to create a ring
    const IORING_SETUP_SQPOLL = 0x1;
    _ = IORING_SETUP_SQPOLL;

    // For now, check kernel version >= 5.1
    const version = getKernelVersionParsed() catch return false;
    return version.major >= 5 and version.minor >= 1;
}

fn getKernelVersion(allocator: std.mem.Allocator) ![]const u8 {
    const uname_result = std.posix.uname();
    return try allocator.dupe(u8, std.mem.sliceTo(&uname_result.release, 0));
}

fn getKernelVersionParsed() !struct { major: u32, minor: u32 } {
    const uname_result = std.posix.uname();
    const release = std.mem.sliceTo(&uname_result.release, 0);

    // Parse "5.1.0-..." → major=5, minor=1
    var iter = std.mem.splitScalar(u8, release, '.');
    const major_str = iter.next() orelse return error.InvalidVersion;
    const minor_str = iter.next() orelse return error.InvalidVersion;

    return .{
        .major = try std.fmt.parseInt(u32, major_str, 10),
        .minor = try std.fmt.parseInt(u32, minor_str, 10),
    };
}

// === Terminal Multiplexer Detection ===

fn detectTmux() bool {
    return std.posix.getenv("TMUX") != null;
}

fn detectScreen() bool {
    const term = std.posix.getenv("TERM") orelse return false;
    return std.mem.startsWith(u8, term, "screen");
}

fn getTmuxVersion(allocator: std.mem.Allocator) ![]const u8 {
    // Parse $TMUX environment variable or run tmux -V
    // For now, just return a placeholder
    if (std.posix.getenv("TMUX")) |_| {
        return try allocator.dupe(u8, "unknown");
    }
    return error.NotInTmux;
}

// === Platform Info ===

fn getOSName() []const u8 {
    return "Linux"; // Grim is Linux-only for now
}

fn getArchitecture() []const u8 {
    return @tagName(@import("builtin").target.cpu.arch);
}

//! Vulkan Integration Helper for Grim
//!
//! Provides high-level Vulkan API integration for text rendering
//! Uses vulkan-zig bindings (when available)

const std = @import("std");
const builtin = @import("builtin");

// Vulkan bindings stub (would use vulkan-zig in production)
const vk = @import("vulkan_renderer.zig").vk;

pub const VulkanContext = struct {
    allocator: std.mem.Allocator,

    // Vulkan objects
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    graphics_queue: vk.Queue,

    // Memory properties
    memory_properties: MemoryProperties,

    // Shader modules
    text_vert_shader: vk.ShaderModule,
    text_frag_shader: vk.ShaderModule,
    sdf_frag_shader: vk.ShaderModule,

    // Pipeline cache
    pipeline_cache: vk.PipelineCache,

    const Self = @This();

    pub const MemoryProperties = struct {
        device_local: bool,
        host_visible: bool,
        host_coherent: bool,
        host_cached: bool,
    };

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Create Vulkan instance
        const instance = try createInstance(allocator);

        // Pick best physical device
        const physical_device = try pickPhysicalDevice(instance);

        // Query memory properties
        const mem_props = try queryMemoryProperties(physical_device);

        // Create logical device
        const device = try createDevice(physical_device);

        // Get graphics queue
        const graphics_queue = try getQueue(device, 0);

        // Load shaders
        const text_vert = try loadShader(device, allocator, "ui-tui/shaders/text.vert.spv");
        const text_frag = try loadShader(device, allocator, "ui-tui/shaders/text.frag.spv");
        const sdf_frag = try loadShader(device, allocator, "ui-tui/shaders/text_sdf.frag.spv");

        // Create pipeline cache
        const cache = try createPipelineCache(device);

        self.* = .{
            .allocator = allocator,
            .instance = instance,
            .physical_device = physical_device,
            .device = device,
            .graphics_queue = graphics_queue,
            .memory_properties = mem_props,
            .text_vert_shader = text_vert,
            .text_frag_shader = text_frag,
            .sdf_frag_shader = sdf_frag,
            .pipeline_cache = cache,
        };

        std.log.info("Vulkan context initialized", .{});
        return self;
    }

    pub fn deinit(self: *Self) void {
        // Cleanup in reverse order
        // TODO: Actual Vulkan cleanup
        self.allocator.destroy(self);
    }

    /// Allocate GPU buffer
    pub fn allocateBuffer(
        self: *Self,
        size: usize,
        usage: BufferUsage,
        memory_type: MemoryType,
    ) !Buffer {
        _ = self;
        _ = usage;
        _ = memory_type;

        return Buffer{
            .handle = undefined,
            .memory = undefined,
            .size = size,
            .mapped = null,
        };
    }

    /// Allocate GPU image
    pub fn allocateImage(
        self: *Self,
        width: u32,
        height: u32,
        format: vk.Format,
        usage: ImageUsage,
    ) !Image {
        _ = self;
        _ = format;
        _ = usage;

        return Image{
            .handle = undefined,
            .view = undefined,
            .memory = undefined,
            .width = width,
            .height = height,
        };
    }

    /// Create graphics pipeline
    pub fn createGraphicsPipeline(
        self: *Self,
        config: PipelineConfig,
    ) !vk.Pipeline {
        _ = self;
        _ = config;

        // TODO: Create actual Vulkan pipeline
        return undefined;
    }

    /// Wait for device idle
    pub fn waitIdle(self: *Self) !void {
        _ = self;
        // TODO: vkDeviceWaitIdle
    }

    // ==================
    // Internal Functions
    // ==================

    fn createInstance(allocator: std.mem.Allocator) !vk.Instance {
        _ = allocator;
        // TODO: vkCreateInstance with validation layers in debug
        std.log.debug("Creating Vulkan instance", .{});
        return undefined;
    }

    fn pickPhysicalDevice(instance: vk.Instance) !vk.PhysicalDevice {
        _ = instance;
        // TODO: Enumerate and pick best GPU (prefer discrete over integrated)
        std.log.debug("Picking physical device", .{});
        return undefined;
    }

    fn queryMemoryProperties(physical_device: vk.PhysicalDevice) !MemoryProperties {
        _ = physical_device;
        // TODO: vkGetPhysicalDeviceMemoryProperties
        return MemoryProperties{
            .device_local = true,
            .host_visible = true,
            .host_coherent = true,
            .host_cached = false,
        };
    }

    fn createDevice(physical_device: vk.PhysicalDevice) !vk.Device {
        _ = physical_device;
        // TODO: vkCreateDevice with required extensions
        std.log.debug("Creating logical device", .{});
        return undefined;
    }

    fn getQueue(device: vk.Device, queue_index: u32) !vk.Queue {
        _ = device;
        _ = queue_index;
        // TODO: vkGetDeviceQueue
        return undefined;
    }

    fn loadShader(device: vk.Device, allocator: std.mem.Allocator, path: []const u8) !vk.ShaderModule {
        _ = device;

        // Read SPIR-V bytecode
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const spirv = try allocator.alloc(u8, stat.size);
        defer allocator.free(spirv);

        _ = try file.readAll(spirv);

        // TODO: vkCreateShaderModule
        std.log.debug("Loaded shader: {s}", .{path});
        return undefined;
    }

    fn createPipelineCache(device: vk.Device) !vk.PipelineCache {
        _ = device;
        // TODO: vkCreatePipelineCache
        return undefined;
    }
};

pub const Buffer = struct {
    handle: vk.Buffer,
    memory: vk.DeviceMemory,
    size: usize,
    mapped: ?*anyopaque,

    pub fn map(self: *Buffer) !*anyopaque {
        // TODO: vkMapMemory
        _ = self;
        return undefined;
    }

    pub fn unmap(self: *Buffer) void {
        // TODO: vkUnmapMemory
        _ = self;
    }

    pub fn upload(self: *Buffer, data: []const u8) !void {
        const ptr = try self.map();
        @memcpy(@as([*]u8, @ptrCast(ptr))[0..data.len], data);
        self.unmap();
    }
};

pub const Image = struct {
    handle: vk.Image,
    view: vk.ImageView,
    memory: vk.DeviceMemory,
    width: u32,
    height: u32,

    pub fn upload(self: *Image, data: []const u8) !void {
        // TODO: Create staging buffer, copy to image, transition layout
        _ = self;
        _ = data;
    }
};

pub const BufferUsage = packed struct {
    vertex: bool = false,
    index: bool = false,
    uniform: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
};

pub const MemoryType = enum {
    device_local,   // GPU memory (fastest)
    host_visible,   // CPU-accessible
    host_coherent,  // Always synchronized
};

pub const ImageUsage = packed struct {
    sampled: bool = false,
    storage: bool = false,
    color_attachment: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
};

pub const PipelineConfig = struct {
    vertex_shader: vk.ShaderModule,
    fragment_shader: vk.ShaderModule,
    render_pass: vk.RenderPass,
    vertex_binding: VertexBinding,
    blend_enabled: bool,
    depth_test: bool,
};

pub const VertexBinding = struct {
    stride: u32,
    attributes: []const VertexAttribute,
};

pub const VertexAttribute = struct {
    location: u32,
    format: vk.Format,
    offset: u32,
};

/// Compile GLSL shader to SPIR-V using glslc
pub fn compileShader(allocator: std.mem.Allocator, glsl_path: []const u8, output_path: []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "glslc",
            glsl_path,
            "-o",
            output_path,
            "-O", // Optimize
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.log.err("Shader compilation failed: {s}", .{result.stderr});
        return error.ShaderCompilationFailed;
    }

    std.log.info("Compiled shader: {s} -> {s}", .{ glsl_path, output_path });
}

/// Compile all shaders in a directory
pub fn compileAllShaders(allocator: std.mem.Allocator, shader_dir: []const u8) !void {
    var dir = try std.fs.cwd().openDir(shader_dir, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        const ext = std.fs.path.extension(entry.name);
        if (!std.mem.eql(u8, ext, ".vert") and !std.mem.eql(u8, ext, ".frag")) continue;

        const input_path = try std.fs.path.join(allocator, &[_][]const u8{ shader_dir, entry.name });
        defer allocator.free(input_path);

        const output_path = try std.fmt.allocPrint(allocator, "{s}.spv", .{input_path});
        defer allocator.free(output_path);

        try compileShader(allocator, input_path, output_path);
    }

    std.log.info("All shaders compiled", .{});
}

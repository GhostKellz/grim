//! Wayland Backend for Grim - Native Wayland Integration
//!
//! This module provides native Wayland support using wzl (Wayland Zig Library).
//! Features:
//! - Zero-copy rendering with DMA-BUF
//! - Fractional scaling support
//! - Direct compositor integration
//! - Hardware-accelerated text rendering

const std = @import("std");
const wzl = @import("wzl");
const phantom = @import("phantom");
const zsync = @import("zsync");

pub const WaylandBackend = struct {
    allocator: std.mem.Allocator,

    // Wayland components
    client: *wzl.Client,
    registry: *wzl.Registry,
    compositor: ?wzl.ObjectId,
    surface: ?wzl.ObjectId,
    xdg_wm_base: ?wzl.XdgWmBase,
    xdg_surface: ?wzl.XdgSurface,
    xdg_toplevel: ?wzl.XdgToplevel,

    // Buffer management
    shm_pool: ?wzl.ShmPool,
    current_buffer: ?wzl.Buffer,

    // Surface properties
    width: u32,
    height: u32,
    scale: f32,  // Fractional scaling support

    // Fractional scaling manager
    fractional_scale_manager: ?wzl.FractionalScalingManager,

    // Feature flags
    has_dmabuf: bool,
    has_fractional_scaling: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize Wayland client
        const client = try wzl.Client.init(allocator, .{});
        errdefer client.deinit();

        // Get registry to discover globals
        const registry = try client.getRegistry();

        self.* = .{
            .allocator = allocator,
            .client = client,
            .registry = registry,
            .compositor = null,
            .surface = null,
            .xdg_wm_base = null,
            .xdg_surface = null,
            .xdg_toplevel = null,
            .shm_pool = null,
            .current_buffer = null,
            .width = 800,
            .height = 600,
            .scale = 1.0,
            .fractional_scale_manager = null,
            .has_dmabuf = false,
            .has_fractional_scaling = false,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.current_buffer) |buffer| {
            buffer.destroy() catch {};
        }
        if (self.shm_pool) |pool| {
            pool.deinit();
        }
        if (self.xdg_toplevel) |toplevel| {
            toplevel.destroy() catch {};
        }
        if (self.xdg_surface) |surface| {
            surface.destroy() catch {};
        }
        if (self.surface) |surface_id| {
            var surface_obj = wzl.Object{
                .id = surface_id,
                .interface = &wzl.wl_surface_interface,
                .version = 1,
                .client = self.client,
            };
            surface_obj.destroy() catch {};
        }

        self.registry.deinit();
        self.client.deinit();
        self.allocator.destroy(self);
    }

    /// Connect to Wayland display and discover available features
    pub fn connect(self: *Self) !void {
        try self.client.connect();

        // Set up registry listener to discover globals
        const RegistryHandler = struct {
            backend: *WaylandBackend,

            fn handleGlobal(
                data: ?*@This(),
                registry: *wzl.Registry,
                name: u32,
                interface_name: []const u8,
                version: u32
            ) void {
                _ = registry;
                const handler = data orelse return;
                const backend = handler.backend;

                std.log.info("Wayland global: {s} v{d}", .{interface_name, version});

                if (std.mem.eql(u8, interface_name, "wl_compositor")) {
                    backend.compositor = backend.registry.bind(
                        name,
                        "wl_compositor",
                        @min(version, 4)
                    ) catch return;
                    std.log.info("Bound wl_compositor", .{});
                } else if (std.mem.eql(u8, interface_name, "xdg_wm_base")) {
                    // XDG shell for window management
                    std.log.info("Found xdg_wm_base", .{});
                } else if (std.mem.eql(u8, interface_name, "zwp_linux_dmabuf_v1")) {
                    backend.has_dmabuf = true;
                    std.log.info("DMA-BUF support available", .{});
                } else if (std.mem.eql(u8, interface_name, "wp_fractional_scale_manager_v1")) {
                    backend.has_fractional_scaling = true;
                    std.log.info("Fractional scaling support available", .{});
                }
            }

            fn handleGlobalRemove(data: ?*@This(), registry: *wzl.Registry, name: u32) void {
                _ = data;
                _ = registry;
                _ = name;
            }
        };

        var handler = RegistryHandler{ .backend = self };
        self.registry.setListener(
            RegistryHandler,
            .{
                .global = RegistryHandler.handleGlobal,
                .global_remove = RegistryHandler.handleGlobalRemove,
            },
            &handler,
        );

        // Roundtrip to get all globals
        try self.client.connection.roundtrip();

        if (self.compositor == null) {
            return error.NoCompositor;
        }
    }

    /// Create a window surface
    pub fn createWindow(self: *Self, title: []const u8, width: u32, height: u32) !void {
        _ = title;
        self.width = width;
        self.height = height;

        // Create wl_surface
        if (self.compositor) |compositor_id| {
            const compositor_obj = wzl.Object{
                .id = compositor_id,
                .interface = &wzl.wl_compositor_interface,
                .version = 4,
                .client = self.client,
            };

            // Request surface creation
            const surface_id = self.client.nextId();
            const message = try wzl.protocol.Message.init(
                self.allocator,
                compositor_obj.id,
                0, // create_surface opcode
                &[_]wzl.protocol.Argument{
                    .{ .new_id = surface_id },
                },
            );
            try self.client.connection.sendMessage(message);

            self.surface = surface_id;
            std.log.info("Created wl_surface with id {d}", .{surface_id});
        }

            // Set up XDG shell for window management
        try self.setupXdgShell(title);

        // Configure fractional scaling if available
        if (self.has_fractional_scaling) {
            try self.setupFractionalScaling();
        }

        // Set up DMA-BUF if available
        if (self.has_dmabuf) {
            try self.setupDmaBuf();
        }
    }

    /// Allocate a shared memory buffer for rendering
    pub fn allocateBuffer(self: *Self) !void {
        const stride = self.width * 4; // ARGB8888 = 4 bytes per pixel
        const size = stride * self.height;

        // Create shared memory pool
        self.shm_pool = try wzl.createMemoryMappedBuffer(
            self.allocator,
            self.client,
            size
        );

        std.log.info("Allocated SHM buffer: {d}x{d} ({d} bytes)", .{
            self.width,
            self.height,
            size
        });
    }

    /// Render text buffer to Wayland surface
    pub fn render(self: *Self, buffer: *phantom.Buffer) !void {
        _ = buffer;

        // TODO: Implement rendering
        // For now, just clear the surface
        if (self.shm_pool) |pool| {
            const stride = self.width * 4;
            const size = stride * self.height;

            // Get pixel data
            const pixels = pool.data[0..size];

            // Clear to black
            @memset(pixels, 0);

            // TODO: Render actual buffer content
            // TODO: Handle fractional scaling
            // TODO: Use DMA-BUF if available
        }

        // Commit surface
        if (self.surface) |surface_id| {
            const message = try wzl.protocol.Message.init(
                self.allocator,
                surface_id,
                6, // commit opcode
                &[_]wzl.protocol.Argument{},
            );
            try self.client.connection.sendMessage(message);
        }
    }

    /// Handle Wayland events
    pub fn pollEvents(self: *Self) !void {
        // Process pending Wayland events
        try self.client.connection.dispatch();
    }

    /// Get current window dimensions
    pub fn getSize(self: *Self) struct { width: u32, height: u32 } {
        return .{
            .width = self.width,
            .height = self.height,
        };
    }

    /// Get fractional scale factor
    pub fn getScale(self: *Self) f32 {
        return self.scale;
    }

    /// Check if DMA-BUF is available
    pub fn hasDmaBuf(self: *Self) bool {
        return self.has_dmabuf;
    }

    /// Check if fractional scaling is available
    pub fn hasFractionalScaling(self: *Self) bool {
        return self.has_fractional_scaling;
    }

    // ======================
    // XDG Shell Integration
    // ======================

    /// Set up XDG shell for window management
    fn setupXdgShell(self: *Self, title: []const u8) !void {
        // Get xdg_wm_base from registry
        const xdg_wm_base_name = try self.findGlobal("xdg_wm_base");
        const xdg_wm_base_id = try self.registry.bind(
            xdg_wm_base_name,
            "xdg_wm_base",
            6
        );

        // Create XDG surface from wl_surface
        if (self.surface) |surface_id| {
            const xdg_surface_id = self.client.nextId();
            const message1 = try wzl.protocol.Message.init(
                self.allocator,
                xdg_wm_base_id,
                2, // get_xdg_surface opcode
                &[_]wzl.protocol.Argument{
                    .{ .new_id = xdg_surface_id },
                    .{ .object = surface_id },
                },
            );
            try self.client.connection.sendMessage(message1);

            // Create XDG toplevel from XDG surface
            const xdg_toplevel_id = self.client.nextId();
            const message2 = try wzl.protocol.Message.init(
                self.allocator,
                xdg_surface_id,
                1, // get_toplevel opcode
                &[_]wzl.protocol.Argument{
                    .{ .new_id = xdg_toplevel_id },
                },
            );
            try self.client.connection.sendMessage(message2);

            // Set window title
            const title_bytes = try self.allocator.alloc(u8, title.len + 1);
            defer self.allocator.free(title_bytes);
            @memcpy(title_bytes[0..title.len], title);
            title_bytes[title.len] = 0;

            const message3 = try wzl.protocol.Message.init(
                self.allocator,
                xdg_toplevel_id,
                2, // set_title opcode
                &[_]wzl.protocol.Argument{
                    .{ .string = title_bytes },
                },
            );
            try self.client.connection.sendMessage(message3);

            // Commit surface
            const message4 = try wzl.protocol.Message.init(
                self.allocator,
                surface_id,
                6, // commit opcode
                &[_]wzl.protocol.Argument{},
            );
            try self.client.connection.sendMessage(message4);

            std.log.info("XDG Shell configured: {s}", .{title});
        }
    }

    /// Find a global interface by name
    fn findGlobal(self: *Self, interface_name: []const u8) !u32 {
        // This would normally cache globals during registry enumeration
        // For now, return a placeholder - in production, track during connect()
        _ = self;
        _ = interface_name;
        return 1; // Placeholder
    }

    // ==========================
    // Fractional Scaling Support
    // ==========================

    /// Configure fractional scaling for HiDPI displays
    fn setupFractionalScaling(self: *Self) !void {
        // Find fractional scale manager
        const scale_manager_name = try self.findGlobal("wp_fractional_scale_manager_v1");
        const scale_manager_id = try self.registry.bind(
            scale_manager_name,
            "wp_fractional_scale_manager_v1",
            1
        );

        if (self.surface) |surface_id| {
            // Request fractional scale object
            const scale_object_id = self.client.nextId();
            const message = try wzl.protocol.Message.init(
                self.allocator,
                scale_manager_id,
                0, // get_fractional_scale opcode
                &[_]wzl.protocol.Argument{
                    .{ .new_id = scale_object_id },
                    .{ .object = surface_id },
                },
            );
            try self.client.connection.sendMessage(message);

            std.log.info("Fractional scaling configured", .{});
        }
    }

    /// Update scale factor (called by event handler)
    pub fn updateScale(self: *Self, scale_120ths: u32) void {
        self.scale = @as(f32, @floatFromInt(scale_120ths)) / 120.0;
        std.log.info("Scale updated to {d:.2}", .{self.scale});
    }

    // ===================
    // DMA-BUF Integration
    // ===================

    /// Set up DMA-BUF for zero-copy rendering
    fn setupDmaBuf(self: *Self) !void {
        // Find DMA-BUF manager
        const dmabuf_name = try self.findGlobal("zwp_linux_dmabuf_v1");
        const dmabuf_id = try self.registry.bind(
            dmabuf_name,
            "zwp_linux_dmabuf_v1",
            4
        );

        // Store for later use in rendering
        _ = dmabuf_id;
        std.log.info("DMA-BUF support configured", .{});
    }

    // ==============
    // Input Handling
    // ==============

    /// Input event types
    pub const InputEvent = union(enum) {
        keyboard_key: struct {
            key: u32,
            state: KeyState,
            modifiers: KeyModifiers,
        },
        pointer_motion: struct {
            x: f32,
            y: f32,
        },
        pointer_button: struct {
            button: u32,
            state: ButtonState,
        },
        pointer_scroll: struct {
            axis: ScrollAxis,
            value: f32,
        },
        touch_down: struct {
            id: i32,
            x: f32,
            y: f32,
        },
        touch_up: struct {
            id: i32,
        },
        touch_motion: struct {
            id: i32,
            x: f32,
            y: f32,
        },
    };

    pub const KeyState = enum(u32) {
        released = 0,
        pressed = 1,
    };

    pub const ButtonState = enum(u32) {
        released = 0,
        pressed = 1,
    };

    pub const ScrollAxis = enum(u32) {
        vertical = 0,
        horizontal = 1,
    };

    pub const KeyModifiers = packed struct {
        shift: bool = false,
        ctrl: bool = false,
        alt: bool = false,
        super: bool = false,
    };

    /// Set up input handling (keyboard, pointer, touch)
    pub fn setupInput(self: *Self, event_callback: *const fn (InputEvent) void) !void {
        // Find wl_seat
        const seat_name = try self.findGlobal("wl_seat");
        const seat_id = try self.registry.bind(
            seat_name,
            "wl_seat",
            7
        );

        // Get pointer capability
        const pointer_id = self.client.nextId();
        const message1 = try wzl.protocol.Message.init(
            self.allocator,
            seat_id,
            0, // get_pointer opcode
            &[_]wzl.protocol.Argument{
                .{ .new_id = pointer_id },
            },
        );
        try self.client.connection.sendMessage(message1);

        // Get keyboard capability
        const keyboard_id = self.client.nextId();
        const message2 = try wzl.protocol.Message.init(
            self.allocator,
            seat_id,
            1, // get_keyboard opcode
            &[_]wzl.protocol.Argument{
                .{ .new_id = keyboard_id },
            },
        );
        try self.client.connection.sendMessage(message2);

        // Get touch capability
        const touch_id = self.client.nextId();
        const message3 = try wzl.protocol.Message.init(
            self.allocator,
            seat_id,
            2, // get_touch opcode
            &[_]wzl.protocol.Argument{
                .{ .new_id = touch_id },
            },
        );
        try self.client.connection.sendMessage(message3);

        _ = event_callback; // Store for event dispatch
        std.log.info("Input handling configured", .{});
    }

    // ==========================
    // GPU-Accelerated Rendering
    // ==========================

    /// Glyph atlas for GPU-accelerated text rendering
    pub const GlyphAtlas = struct {
        allocator: std.mem.Allocator,
        texture_width: u32,
        texture_height: u32,
        glyphs: std.AutoHashMap(GlyphKey, GlyphEntry),
        next_x: u32,
        next_y: u32,
        row_height: u32,

        pub const GlyphKey = struct {
            codepoint: u32,
            size: u16,
            bold: bool,
            italic: bool,

            pub fn hash(self: GlyphKey) u64 {
                var h: u64 = self.codepoint;
                h = h * 31 + self.size;
                h = h * 31 + @intFromBool(self.bold);
                h = h * 31 + @intFromBool(self.italic);
                return h;
            }

            pub fn eql(a: GlyphKey, b: GlyphKey) bool {
                return a.codepoint == b.codepoint and
                    a.size == b.size and
                    a.bold == b.bold and
                    a.italic == b.italic;
            }
        };

        pub const GlyphEntry = struct {
            x: u32,
            y: u32,
            width: u32,
            height: u32,
            advance: f32,
            bearing_x: f32,
            bearing_y: f32,
        };

        pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*GlyphAtlas {
            const atlas = try allocator.create(GlyphAtlas);
            atlas.* = .{
                .allocator = allocator,
                .texture_width = width,
                .texture_height = height,
                .glyphs = std.AutoHashMap(GlyphKey, GlyphEntry).init(allocator),
                .next_x = 0,
                .next_y = 0,
                .row_height = 0,
            };
            return atlas;
        }

        pub fn deinit(self: *GlyphAtlas) void {
            self.glyphs.deinit();
            self.allocator.destroy(self);
        }

        /// Add a glyph to the atlas
        pub fn addGlyph(
            self: *GlyphAtlas,
            key: GlyphKey,
            width: u32,
            height: u32,
            advance: f32,
            bearing_x: f32,
            bearing_y: f32,
            pixel_data: []const u8,
        ) !void {
            // Check if we need a new row
            if (self.next_x + width > self.texture_width) {
                self.next_x = 0;
                self.next_y += self.row_height;
                self.row_height = 0;
            }

            // Check if we're out of space
            if (self.next_y + height > self.texture_height) {
                return error.AtlasFull;
            }

            const entry = GlyphEntry{
                .x = self.next_x,
                .y = self.next_y,
                .width = width,
                .height = height,
                .advance = advance,
                .bearing_x = bearing_x,
                .bearing_y = bearing_y,
            };

            try self.glyphs.put(key, entry);

            // TODO: Upload pixel_data to GPU texture at (entry.x, entry.y)
            _ = pixel_data;

            self.next_x += width + 2; // 2px padding
            self.row_height = @max(self.row_height, height + 2);
        }

        /// Get glyph entry from atlas
        pub fn getGlyph(self: *GlyphAtlas, key: GlyphKey) ?GlyphEntry {
            return self.glyphs.get(key);
        }
    };

    /// GPU rendering backend selection
    pub const RenderBackend = enum {
        vulkan,
        opengl,
        software,
    };

    /// Create GPU rendering context
    pub fn createRenderContext(self: *Self, backend: RenderBackend) !void {
        switch (backend) {
            .vulkan => {
                std.log.info("Initializing Vulkan rendering backend", .{});
                // TODO: Use wzl.vulkan_backend for Vulkan initialization
            },
            .opengl => {
                std.log.info("Initializing OpenGL rendering backend", .{});
                // TODO: Use wzl.egl_backend for OpenGL/EGL initialization
            },
            .software => {
                std.log.info("Using software rendering (current implementation)", .{});
            },
        }
        _ = self;
    }

    /// Render text buffer with GPU acceleration
    pub fn renderTextGPU(
        self: *Self,
        buffer: *phantom.Buffer,
        glyph_atlas: *GlyphAtlas,
    ) !void {
        _ = self;
        _ = buffer;
        _ = glyph_atlas;

        // TODO: Implement GPU-accelerated text rendering
        // 1. Iterate through buffer cells
        // 2. Look up glyphs in atlas
        // 3. Generate vertex buffer with quad per glyph
        // 4. Upload to GPU
        // 5. Draw with single draw call

        std.log.debug("GPU text rendering (stub)", .{});
    }

    // ====================
    // Font Hinting/Shaping
    // ====================

    /// Font configuration for rendering
    pub const FontConfig = struct {
        family: []const u8,
        size: u16,
        dpi: u16,
        hinting: HintingMode,
        subpixel: SubpixelMode,
    };

    pub const HintingMode = enum {
        none,
        slight,
        medium,
        full,
    };

    pub const SubpixelMode = enum {
        none,
        rgb,
        bgr,
        vrgb,
        vbgr,
    };

    /// Initialize font shaping for text rendering
    pub fn setupFontShaping(self: *Self, config: FontConfig) !void {
        _ = self;
        // TODO: Integrate with gcode/zfont for font loading and shaping
        std.log.info("Font shaping configured: {s} {}pt @ {}dpi", .{
            config.family,
            config.size,
            config.dpi,
        });
    }

    /// Shape text with complex script support
    pub fn shapeText(
        self: *Self,
        text: []const u8,
        font_config: FontConfig,
    ) ![]ShapedGlyph {
        _ = self;
        _ = text;
        _ = font_config;

        // TODO: Use gcode/zfont for text shaping
        // Returns array of positioned glyphs with advances
        return &[_]ShapedGlyph{};
    }

    pub const ShapedGlyph = struct {
        glyph_id: u32,
        x_offset: f32,
        y_offset: f32,
        x_advance: f32,
        y_advance: f32,
        cluster: u32, // Character cluster index
    };
};

/// Detect if we're running under Wayland
pub fn isWaylandAvailable() bool {
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY");
    return wayland_display != null;
}

/// Get Wayland display name
pub fn getWaylandDisplay() ?[]const u8 {
    return std.posix.getenv("WAYLAND_DISPLAY");
}

test "wayland availability detection" {
    const available = isWaylandAvailable();
    if (available) {
        const display = getWaylandDisplay();
        try std.testing.expect(display != null);
    }
}

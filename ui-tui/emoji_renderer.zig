//! Color Emoji Rendering for Grim
//!
//! Supports modern color emoji formats:
//! - COLR/CPAL (Microsoft, Google)
//! - SBIX (Apple)
//! - CBDT/CBLC (Google)
//! - SVG (OpenType SVG)

const std = @import("std");

pub const EmojiRenderer = struct {
    allocator: std.mem.Allocator,

    // Emoji font support
    color_fonts: std.ArrayList(ColorFont),
    fallback_emoji_font: ?*ColorFont,

    // Emoji cache
    emoji_cache: std.AutoHashMap(u32, RenderedEmoji),

    // Rendering backend
    backend: RenderBackend,

    const Self = @This();

    pub const ColorFont = struct {
        path: []const u8,
        format: ColorFormat,
        size: u16,
        // Font handle would go here
    };

    pub const ColorFormat = enum {
        colr_cpal,  // Microsoft/Google color tables
        sbix,       // Apple bitmap strikes
        cbdt_cblc,  // Google bitmap data
        svg,        // OpenType SVG
    };

    pub const RenderedEmoji = struct {
        width: u32,
        height: u32,
        pixels: []u8,      // RGBA8888
        baseline: i32,
        advance: f32,

        pub fn deinit(self: *RenderedEmoji, allocator: std.mem.Allocator) void {
            allocator.free(self.pixels);
        }
    };

    pub const RenderBackend = enum {
        cpu_rgba,   // CPU-side RGBA rendering
        gpu_atlas,  // GPU texture atlas
    };

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .color_fonts = std.ArrayList(ColorFont).init(allocator),
            .fallback_emoji_font = null,
            .emoji_cache = std.AutoHashMap(u32, RenderedEmoji).init(allocator),
            .backend = .gpu_atlas,
        };

        // Load system emoji fonts
        try self.loadSystemEmojiF onts();

        std.log.info("Emoji renderer initialized: {} color fonts loaded", .{
            self.color_fonts.items.len,
        });

        return self;
    }

    pub fn deinit(self: *Self) void {
        var it = self.emoji_cache.valueIterator();
        while (it.next()) |emoji| {
            var mut_emoji = emoji.*;
            mut_emoji.deinit(self.allocator);
        }
        self.emoji_cache.deinit();

        for (self.color_fonts.items) |font| {
            self.allocator.free(font.path);
        }
        self.color_fonts.deinit();

        self.allocator.destroy(self);
    }

    /// Load system emoji fonts from common locations
    fn loadSystemEmojiFonts(self: *Self) !void {
        const emoji_fonts = [_]struct {
            path: []const u8,
            format: ColorFormat,
        }{
            // Linux
            .{ .path = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf", .format = .colr_cpal },
            .{ .path = "/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf", .format = .colr_cpal },

            // macOS
            .{ .path = "/System/Library/Fonts/Apple Color Emoji.ttc", .format = .sbix },

            // Windows
            .{ .path = "C:\\Windows\\Fonts\\seguiemj.ttf", .format = .colr_cpal },
        };

        for (emoji_fonts) |font_info| {
            const file = std.fs.cwd().openFile(font_info.path, .{}) catch continue;
            file.close();

            const font = ColorFont{
                .path = try self.allocator.dupe(u8, font_info.path),
                .format = font_info.format,
                .size = 16, // Default size
            };

            try self.color_fonts.append(font);

            // Set first found as fallback
            if (self.fallback_emoji_font == null) {
                self.fallback_emoji_font = &self.color_fonts.items[self.color_fonts.items.len - 1];
            }

            std.log.info("Loaded emoji font: {s} ({})", .{ font_info.path, font_info.format });
        }

        if (self.color_fonts.items.len == 0) {
            std.log.warn("No color emoji fonts found", .{});
        }
    }

    /// Render an emoji to RGBA bitmap
    pub fn renderEmoji(self: *Self, codepoint: u32, size: u16) !*RenderedEmoji {
        // Check cache first
        if (self.emoji_cache.get(codepoint)) |*cached| {
            return cached;
        }

        // Render from font
        const rendered = try self.renderEmojiUncached(codepoint, size);

        // Cache the result
        try self.emoji_cache.put(codepoint, rendered);

        return self.emoji_cache.getPtr(codepoint).?;
    }

    fn renderEmojiUncached(self: *Self, codepoint: u32, size: u16) !RenderedEmoji {
        const font = self.fallback_emoji_font orelse return error.NoEmojiFont;

        // TODO: Use real font rendering library (e.g., FreeType with color support)
        // For now, return a placeholder

        const width = size;
        const height = size;
        const pixel_count = @as(usize, width) * @as(usize, height);
        const pixels = try self.allocator.alloc(u8, pixel_count * 4);

        // Fill with a placeholder pattern (checkerboard)
        for (0..height) |y| {
            for (0..width) |x| {
                const i = (y * width + x) * 4;
                const checker = ((x / 4) + (y / 4)) % 2;
                const gray: u8 = if (checker == 0) 200 else 150;

                pixels[i + 0] = gray; // R
                pixels[i + 1] = gray; // G
                pixels[i + 2] = gray; // B
                pixels[i + 3] = 255;  // A
            }
        }

        _ = codepoint;
        _ = font;

        return RenderedEmoji{
            .width = width,
            .height = height,
            .pixels = pixels,
            .baseline = @intCast(@divTrunc(height * 3, 4)),
            .advance = @floatFromInt(width),
        };
    }

    /// Check if a codepoint is an emoji
    pub fn isEmoji(codepoint: u32) bool {
        // Common emoji ranges
        return (codepoint >= 0x1F300 and codepoint <= 0x1F9FF) or // Misc symbols and pictographs
            (codepoint >= 0x1F600 and codepoint <= 0x1F64F) or // Emoticons
            (codepoint >= 0x1F680 and codepoint <= 0x1F6FF) or // Transport
            (codepoint >= 0x2600 and codepoint <= 0x26FF) or   // Misc symbols
            (codepoint >= 0x2700 and codepoint <= 0x27BF) or   // Dingbats
            (codepoint >= 0xFE00 and codepoint <= 0xFE0F) or   // Variation selectors
            (codepoint >= 0x1F900 and codepoint <= 0x1F9FF) or // Supplemental symbols
            (codepoint >= 0x1FA70 and codepoint <= 0x1FAFF);   // Extended pictographs
    }

    /// Get emoji metadata
    pub fn getEmojiInfo(codepoint: u32) ?EmojiInfo {
        // TODO: Load from emoji metadata database
        if (!isEmoji(codepoint)) return null;

        return EmojiInfo{
            .codepoint = codepoint,
            .category = getEmojiCategory(codepoint),
            .shortcode = getEmojiShortcode(codepoint),
            .keywords = &[_][]const u8{},
        };
    }

    fn getEmojiCategory(codepoint: u32) EmojiCategory {
        if (codepoint >= 0x1F600 and codepoint <= 0x1F64F) return .smileys;
        if (codepoint >= 0x1F680 and codepoint <= 0x1F6FF) return .travel;
        if (codepoint >= 0x1F300 and codepoint <= 0x1F5FF) return .symbols;
        return .other;
    }

    fn getEmojiShortcode(codepoint: u32) []const u8 {
        // Map common emoji to shortcodes
        return switch (codepoint) {
            0x1F600 => ":grinning:",
            0x1F602 => ":joy:",
            0x1F44D => ":+1:",
            0x1F44E => ":-1:",
            0x2764 => ":heart:",
            0x1F525 => ":fire:",
            0x1F680 => ":rocket:",
            0x2705 => ":white_check_mark:",
            0x274C => ":x:",
            0x1F4A1 => ":bulb:",
            else => ":unknown:",
        };
    }
};

pub const EmojiInfo = struct {
    codepoint: u32,
    category: EmojiCategory,
    shortcode: []const u8,
    keywords: []const []const u8,
};

pub const EmojiCategory = enum {
    smileys,
    people,
    animals,
    food,
    travel,
    activities,
    objects,
    symbols,
    flags,
    other,
};

/// Emoji sequence handler (for multi-codepoint emoji like skin tones, ZWJ sequences)
pub const EmojiSequence = struct {
    codepoints: []const u32,

    pub fn init(allocator: std.mem.Allocator, codepoints: []const u32) !EmojiSequence {
        return .{
            .codepoints = try allocator.dupe(u32, codepoints),
        };
    }

    pub fn deinit(self: *EmojiSequence, allocator: std.mem.Allocator) void {
        allocator.free(self.codepoints);
    }

    /// Check if sequence is a valid emoji (ZWJ, variation selector, skin tone, etc.)
    pub fn isValid(self: EmojiSequence) bool {
        if (self.codepoints.len == 0) return false;

        // Check for ZWJ sequences (e.g., family emoji)
        for (self.codepoints, 0..) |cp, i| {
            if (cp == 0x200D and i > 0 and i < self.codepoints.len - 1) {
                // Valid ZWJ sequence
                return true;
            }
        }

        // Check for skin tone modifiers
        if (self.codepoints.len == 2) {
            const modifier = self.codepoints[1];
            if (modifier >= 0x1F3FB and modifier <= 0x1F3FF) {
                return true;
            }
        }

        // Check for variation selectors (emoji vs text presentation)
        if (self.codepoints.len == 2 and self.codepoints[1] == 0xFE0F) {
            return true;
        }

        return false;
    }

    /// Get display width of emoji sequence
    pub fn getDisplayWidth(self: EmojiSequence) u32 {
        _ = self;
        return 2; // Most emoji are 2 columns wide in terminals
    }
};

/// Emoji picker/autocomplete support
pub const EmojiPicker = struct {
    allocator: std.mem.Allocator,
    emoji_list: std.ArrayList(EmojiInfo),

    pub fn init(allocator: std.mem.Allocator) !*EmojiPicker {
        const picker = try allocator.create(EmojiPicker);
        picker.* = .{
            .allocator = allocator,
            .emoji_list = std.ArrayList(EmojiInfo).init(allocator),
        };

        // Load popular emoji
        try picker.loadPopularEmoji();

        return picker;
    }

    pub fn deinit(self: *EmojiPicker) void {
        self.emoji_list.deinit();
        self.allocator.destroy(self);
    }

    fn loadPopularEmoji(self: *EmojiPicker) !void {
        const popular = [_]u32{
            0x1F600, // 😀
            0x1F602, // 😂
            0x1F44D, // 👍
            0x1F44E, // 👎
            0x2764,  // ❤️
            0x1F525, // 🔥
            0x1F680, // 🚀
            0x2705,  // ✅
            0x274C,  // ❌
            0x1F4A1, // 💡
        };

        for (popular) |codepoint| {
            if (EmojiRenderer.getEmojiInfo(codepoint)) |info| {
                try self.emoji_list.append(info);
            }
        }
    }

    /// Search emoji by shortcode or keyword
    pub fn search(self: *EmojiPicker, query: []const u8) ![]EmojiInfo {
        var results = std.ArrayList(EmojiInfo).init(self.allocator);

        for (self.emoji_list.items) |emoji| {
            // Match shortcode
            if (std.mem.indexOf(u8, emoji.shortcode, query) != null) {
                try results.append(emoji);
                continue;
            }

            // Match keywords
            for (emoji.keywords) |keyword| {
                if (std.mem.indexOf(u8, keyword, query) != null) {
                    try results.append(emoji);
                    break;
                }
            }
        }

        return results.toOwnedSlice();
    }
};

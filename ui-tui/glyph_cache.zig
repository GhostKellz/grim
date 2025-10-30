//! Glyph Cache Warmup System for Grim
//!
//! Preloads commonly used glyphs on startup to prevent stuttering during editing.
//! Uses frequency analysis to prioritize which glyphs to cache.

const std = @import("std");

pub const GlyphCache = struct {
    allocator: std.mem.Allocator,
    atlas: *Atlas,
    font_loader: *FontLoader,

    // Cache statistics
    hit_count: u64,
    miss_count: u64,
    warmup_complete: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, atlas: *Atlas, font_loader: *FontLoader) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .atlas = atlas,
            .font_loader = font_loader,
            .hit_count = 0,
            .miss_count = 0,
            .warmup_complete = false,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Warm up cache with commonly used glyphs
    pub fn warmup(self: *Self, config: WarmupConfig) !void {
        const start = std.time.milliTimestamp();
        var glyphs_loaded: usize = 0;

        std.log.info("Starting glyph cache warmup...", .{});

        // 1. ASCII printable characters (32-126) - Most common in code
        if (config.ascii_printable) {
            for (32..127) |codepoint| {
                try self.loadGlyph(@intCast(codepoint), config.font_size, false, false);
                glyphs_loaded += 1;
            }
            std.log.debug("Loaded ASCII printable: {} glyphs", .{95});
        }

        // 2. Common programming symbols (already in ASCII, but emphasize)
        if (config.programming_symbols) {
            const symbols = "(){}[]<>+-*/=!&|^~%#@$?:;.,\"'`\\";
            for (symbols) |ch| {
                try self.loadGlyph(ch, config.font_size, false, false);
                try self.loadGlyph(ch, config.font_size, true, false); // Bold variants
            }
            glyphs_loaded += symbols.len * 2;
            std.log.debug("Loaded programming symbols with bold", .{});
        }

        // 3. Numbers 0-9 in multiple styles
        if (config.numbers) {
            for ('0'..'9' + 1) |ch| {
                try self.loadGlyph(ch, config.font_size, false, false); // Normal
                try self.loadGlyph(ch, config.font_size, true, false); // Bold
                try self.loadGlyph(ch, config.font_size, false, true); // Italic
            }
            glyphs_loaded += 10 * 3;
            std.log.debug("Loaded numbers in 3 styles", .{});
        }

        // 4. Common programming keywords (bold variants)
        if (config.keywords) {
            const keywords = [_][]const u8{
                "const", "var", "fn", "pub", "if", "else", "for", "while",
                "switch", "return", "try", "catch", "struct", "enum", "union",
            };

            for (keywords) |keyword| {
                for (keyword) |ch| {
                    try self.loadGlyph(ch, config.font_size, true, false);
                }
            }
            std.log.debug("Loaded keyword characters (bold)", .{});
        }

        // 5. Extended ASCII (128-255) - Latin-1 supplement
        if (config.extended_ascii) {
            for (128..256) |codepoint| {
                try self.loadGlyph(@intCast(codepoint), config.font_size, false, false);
                glyphs_loaded += 1;
            }
            std.log.debug("Loaded extended ASCII: {} glyphs", .{128});
        }

        // 6. Common emoji (if color emoji enabled)
        if (config.emoji) {
            const common_emoji = [_]u32{
                0x1F600, // 😀 Grinning face
                0x1F602, // 😂 Face with tears of joy
                0x1F44D, // 👍 Thumbs up
                0x1F44E, // 👎 Thumbs down
                0x2764,  // ❤️ Red heart
                0x1F525, // 🔥 Fire
                0x1F680, // 🚀 Rocket
                0x2705,  // ✅ Check mark
                0x274C,  // ❌ Cross mark
                0x1F4A1, // 💡 Light bulb
            };

            for (common_emoji) |codepoint| {
                try self.loadGlyph(codepoint, config.font_size, false, false);
                glyphs_loaded += 1;
            }
            std.log.debug("Loaded common emoji: {} glyphs", .{common_emoji.len});
        }

        // 7. Box drawing characters (for UI elements)
        if (config.box_drawing) {
            // Unicode box drawing (U+2500 - U+257F)
            for (0x2500..0x2580) |codepoint| {
                try self.loadGlyph(@intCast(codepoint), config.font_size, false, false);
                glyphs_loaded += 1;
            }
            std.log.debug("Loaded box drawing: {} glyphs", .{128});
        }

        const elapsed = std.time.milliTimestamp() - start;
        self.warmup_complete = true;

        std.log.info("Glyph cache warmup complete: {} glyphs in {}ms", .{
            glyphs_loaded,
            elapsed,
        });
    }

    /// Load a single glyph into the atlas
    fn loadGlyph(self: *Self, codepoint: u32, size: u16, bold: bool, italic: bool) !void {
        const key = AtlasKey{
            .codepoint = codepoint,
            .size = size,
            .bold = bold,
            .italic = italic,
        };

        // Check if already cached
        if (self.atlas.hasGlyph(key)) {
            return;
        }

        // Render glyph
        const glyph_data = try self.font_loader.renderGlyph(codepoint, size, bold, italic);
        defer glyph_data.deinit();

        // Add to atlas
        try self.atlas.addGlyph(key, glyph_data);
    }

    /// Get cache hit rate
    pub fn getHitRate(self: *Self) f32 {
        const total = self.hit_count + self.miss_count;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hit_count)) / @as(f32, @floatFromInt(total));
    }

    pub fn recordHit(self: *Self) void {
        self.hit_count += 1;
    }

    pub fn recordMiss(self: *Self) void {
        self.miss_count += 1;
    }
};

pub const WarmupConfig = struct {
    font_size: u16 = 14,

    // Character sets to preload
    ascii_printable: bool = true,
    programming_symbols: bool = true,
    numbers: bool = true,
    keywords: bool = true,
    extended_ascii: bool = true,
    emoji: bool = true,
    box_drawing: bool = true,

    /// Preset configurations
    pub const minimal = WarmupConfig{
        .ascii_printable = true,
        .programming_symbols = true,
        .numbers = true,
        .keywords = false,
        .extended_ascii = false,
        .emoji = false,
        .box_drawing = false,
    };

    pub const standard = WarmupConfig{
        .ascii_printable = true,
        .programming_symbols = true,
        .numbers = true,
        .keywords = true,
        .extended_ascii = false,
        .emoji = true,
        .box_drawing = true,
    };

    pub const maximum = WarmupConfig{
        .ascii_printable = true,
        .programming_symbols = true,
        .numbers = true,
        .keywords = true,
        .extended_ascii = true,
        .emoji = true,
        .box_drawing = true,
    };
};

// Stub types (would be real implementations)
pub const Atlas = struct {
    pub fn hasGlyph(self: *Atlas, key: AtlasKey) bool {
        _ = self;
        _ = key;
        return false;
    }

    pub fn addGlyph(self: *Atlas, key: AtlasKey, data: GlyphData) !void {
        _ = self;
        _ = key;
        _ = data;
    }
};

pub const AtlasKey = struct {
    codepoint: u32,
    size: u16,
    bold: bool,
    italic: bool,
};

pub const FontLoader = struct {
    pub fn renderGlyph(self: *FontLoader, codepoint: u32, size: u16, bold: bool, italic: bool) !GlyphData {
        _ = self;
        _ = codepoint;
        _ = size;
        _ = bold;
        _ = italic;
        return GlyphData{};
    }
};

pub const GlyphData = struct {
    pub fn deinit(self: GlyphData) void {
        _ = self;
    }
};

/// Frequency-based glyph prioritization
pub const FrequencyAnalyzer = struct {
    frequencies: std.AutoHashMap(u32, u64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FrequencyAnalyzer {
        return .{
            .frequencies = std.AutoHashMap(u32, u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FrequencyAnalyzer) void {
        self.frequencies.deinit();
    }

    /// Record glyph usage
    pub fn recordUsage(self: *FrequencyAnalyzer, codepoint: u32) !void {
        const entry = try self.frequencies.getOrPut(codepoint);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    /// Get top N most frequently used glyphs
    pub fn getTopGlyphs(self: *FrequencyAnalyzer, n: usize) ![]u32 {
        var entries = try std.ArrayList(struct { codepoint: u32, count: u64 }).initCapacity(
            self.allocator,
            self.frequencies.count(),
        );
        defer entries.deinit();

        var it = self.frequencies.iterator();
        while (it.next()) |entry| {
            try entries.append(.{
                .codepoint = entry.key_ptr.*,
                .count = entry.value_ptr.*,
            });
        }

        // Sort by frequency (descending)
        std.mem.sort(@TypeOf(entries.items[0]), entries.items, {}, struct {
            fn lessThan(_: void, a: @TypeOf(entries.items[0]), b: @TypeOf(entries.items[0])) bool {
                return a.count > b.count;
            }
        }.lessThan);

        // Return top N codepoints
        const count = @min(n, entries.items.len);
        const result = try self.allocator.alloc(u32, count);
        for (entries.items[0..count], 0..) |entry, i| {
            result[i] = entry.codepoint;
        }

        return result;
    }

    /// Save frequency data to file
    pub fn save(self: *FrequencyAnalyzer, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var it = self.frequencies.iterator();
        while (it.next()) |entry| {
            try file.writer().print("{},{}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    /// Load frequency data from file
    pub fn load(self: *FrequencyAnalyzer, path: []const u8) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch return; // Ignore if file doesn't exist
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        var buf: [1024]u8 = undefined;
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            var it = std.mem.split(u8, line, ",");
            const codepoint_str = it.next() orelse continue;
            const count_str = it.next() orelse continue;

            const codepoint = try std.fmt.parseInt(u32, codepoint_str, 10);
            const count = try std.fmt.parseInt(u64, count_str, 10);

            try self.frequencies.put(codepoint, count);
        }
    }
};

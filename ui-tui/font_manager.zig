const std = @import("std");

/// Font Manager - Nerd Font Icon Support
/// Provides icon mappings for file types, UI elements, and LSP features
/// Falls back to ASCII when Nerd Fonts are unavailable
pub const FontManager = struct {
    allocator: std.mem.Allocator,
    nerd_fonts_enabled: bool,

    pub fn init(allocator: std.mem.Allocator, enable_nerd_fonts: bool) FontManager {
        return .{
            .allocator = allocator,
            .nerd_fonts_enabled = enable_nerd_fonts,
        };
    }

    pub fn deinit(self: *FontManager) void {
        _ = self;
    }

    // File Type Icons

    /// Get icon for file extension
    pub fn getFileIcon(self: *const FontManager, file_path: []const u8) []const u8 {
        const ext = std.fs.path.extension(file_path);

        if (self.nerd_fonts_enabled) {
            return self.getNerdFontFileIcon(ext);
        } else {
            return self.getAsciiFileIcon(ext);
        }
    }

    fn getNerdFontFileIcon(self: *const FontManager, ext: []const u8) []const u8 {
        _ = self;

        // Nerd Font icons (using Unicode codepoints)
        // https://www.nerdfonts.com/cheat-sheet

        // Programming languages
        if (std.mem.eql(u8, ext, ".zig")) return "\u{e6a9}"; //
        if (std.mem.eql(u8, ext, ".rs")) return "\u{e7a8}"; //
        if (std.mem.eql(u8, ext, ".go")) return "\u{e626}"; //
        if (std.mem.eql(u8, ext, ".js")) return "\u{e74e}"; //
        if (std.mem.eql(u8, ext, ".ts")) return "\u{e628}"; //
        if (std.mem.eql(u8, ext, ".py")) return "\u{e73c}"; //
        if (std.mem.eql(u8, ext, ".c")) return "\u{e61e}"; //
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".cxx")) return "\u{e61d}"; //
        if (std.mem.eql(u8, ext, ".h") or std.mem.eql(u8, ext, ".hpp")) return "\u{e61e}"; //
        if (std.mem.eql(u8, ext, ".java")) return "\u{e738}"; //
        if (std.mem.eql(u8, ext, ".rb")) return "\u{e739}"; //
        if (std.mem.eql(u8, ext, ".php")) return "\u{e73d}"; //
        if (std.mem.eql(u8, ext, ".swift")) return "\u{e755}"; //
        if (std.mem.eql(u8, ext, ".kt")) return "\u{e634}"; //
        if (std.mem.eql(u8, ext, ".scala")) return "\u{e737}"; //
        if (std.mem.eql(u8, ext, ".lua")) return "\u{e620}"; //
        if (std.mem.eql(u8, ext, ".vim")) return "\u{e62b}"; //

        // Web technologies
        if (std.mem.eql(u8, ext, ".html")) return "\u{e736}"; //
        if (std.mem.eql(u8, ext, ".css")) return "\u{e749}"; //
        if (std.mem.eql(u8, ext, ".scss") or std.mem.eql(u8, ext, ".sass")) return "\u{e749}"; //
        if (std.mem.eql(u8, ext, ".jsx")) return "\u{e7ba}"; //
        if (std.mem.eql(u8, ext, ".tsx")) return "\u{e7ba}"; //
        if (std.mem.eql(u8, ext, ".vue")) return "\u{e6a0}"; //

        // Data formats
        if (std.mem.eql(u8, ext, ".json")) return "\u{e60b}"; //
        if (std.mem.eql(u8, ext, ".xml")) return "\u{e619}"; //
        if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return "\u{e619}"; //
        if (std.mem.eql(u8, ext, ".toml")) return "\u{e60b}"; //
        if (std.mem.eql(u8, ext, ".csv")) return "\u{e60b}"; //

        // Documentation
        if (std.mem.eql(u8, ext, ".md")) return "\u{e609}"; //
        if (std.mem.eql(u8, ext, ".txt")) return "\u{e60b}"; //
        if (std.mem.eql(u8, ext, ".pdf")) return "\u{e60b}"; //

        // Build/Config files
        if (std.mem.eql(u8, ext, ".gitignore")) return "\u{e702}"; //
        if (std.mem.eql(u8, ext, ".dockerfile")) return "\u{e7b0}"; //
        if (std.mem.eql(u8, ext, ".sh")) return "\u{e795}"; //
        if (std.mem.eql(u8, ext, ".bash")) return "\u{e795}"; //
        if (std.mem.eql(u8, ext, ".zsh")) return "\u{e795}"; //

        // Archives
        if (std.mem.eql(u8, ext, ".zip")) return "\u{e615}"; //
        if (std.mem.eql(u8, ext, ".tar")) return "\u{e615}"; //
        if (std.mem.eql(u8, ext, ".gz")) return "\u{e615}"; //

        // Images
        if (std.mem.eql(u8, ext, ".png") or std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg") or
            std.mem.eql(u8, ext, ".gif") or std.mem.eql(u8, ext, ".svg")) return "\u{e60d}"; //

        // Ghostlang
        if (std.mem.eql(u8, ext, ".gza")) return "\u{e61f}"; // 👻 (ghost icon)

        // Default file icon
        return "\u{e60b}"; //
    }

    fn getAsciiFileIcon(self: *const FontManager, ext: []const u8) []const u8 {
        _ = self;

        // ASCII fallbacks
        if (std.mem.eql(u8, ext, ".zig")) return "[Z]";
        if (std.mem.eql(u8, ext, ".rs")) return "[R]";
        if (std.mem.eql(u8, ext, ".go")) return "[G]";
        if (std.mem.eql(u8, ext, ".js")) return "[J]";
        if (std.mem.eql(u8, ext, ".ts")) return "[T]";
        if (std.mem.eql(u8, ext, ".py")) return "[P]";
        if (std.mem.eql(u8, ext, ".c")) return "[C]";
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc")) return "[C+]";
        if (std.mem.eql(u8, ext, ".md")) return "[M]";
        if (std.mem.eql(u8, ext, ".json")) return "[{}]";
        if (std.mem.eql(u8, ext, ".html")) return "[H]";
        if (std.mem.eql(u8, ext, ".css")) return "[S]";
        if (std.mem.eql(u8, ext, ".gza")) return "[G]"; // Ghostlang

        return "[F]"; // Generic file
    }

    // UI Element Icons

    /// Modified buffer indicator
    pub fn getModifiedIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f111}"; //  (filled circle)
        } else {
            return "*";
        }
    }

    /// Saved/unmodified indicator
    pub fn getSavedIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f00c}"; //  (checkmark)
        } else {
            return " ";
        }
    }

    /// LSP active indicator
    pub fn getLspActiveIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f0eb}"; //  (lightbulb)
        } else {
            return "[LSP]";
        }
    }

    /// LSP inactive indicator
    pub fn getLspInactiveIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f1e6}"; //  (lightbulb outline)
        } else {
            return "[-]";
        }
    }

    /// LSP loading/connecting indicator
    pub fn getLspLoadingIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f110}"; //  (spinner)
        } else {
            return "[~]";
        }
    }

    /// Error/diagnostic indicator
    pub fn getErrorIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f00d}"; //  (X)
        } else {
            return "E";
        }
    }

    /// Warning indicator
    pub fn getWarningIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f071}"; //  (triangle exclamation)
        } else {
            return "W";
        }
    }

    /// Info indicator
    pub fn getInfoIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f05a}"; //  (info circle)
        } else {
            return "I";
        }
    }

    /// Hint indicator
    pub fn getHintIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f0eb}"; //  (lightbulb)
        } else {
            return "H";
        }
    }

    /// Folder icon
    pub fn getFolderIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{e5ff}"; //
        } else {
            return "[D]";
        }
    }

    /// Git branch icon
    pub fn getGitBranchIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{e725}"; //
        } else {
            return "git:";
        }
    }

    /// Line number icon
    pub fn getLineNumberIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{e624}"; //
        } else {
            return "Ln";
        }
    }

    /// Column number icon
    pub fn getColumnIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{e623}"; //
        } else {
            return "Col";
        }
    }

    /// Mode indicators
    pub fn getModeIcon(self: *const FontManager, mode: Mode) []const u8 {
        if (self.nerd_fonts_enabled) {
            return switch (mode) {
                .normal => "\u{f444}", //  (keyboard)
                .insert => "\u{f031}", //  (pencil)
                .visual => "\u{f0c5}", //  (copy/selection)
                .command => "\u{f120}", //  (terminal)
            };
        } else {
            return switch (mode) {
                .normal => "NORMAL",
                .insert => "INSERT",
                .visual => "VISUAL",
                .command => "COMMAND",
            };
        }
    }

    pub const Mode = enum {
        normal,
        insert,
        visual,
        command,
    };

    /// Search icon
    pub fn getSearchIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f002}"; //
        } else {
            return "/";
        }
    }

    /// Buffer picker icon
    pub fn getBufferPickerIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f0c9}"; //  (list)
        } else {
            return "[::]";
        }
    }

    // LSP-specific icons

    /// Completion item kind icons
    pub fn getCompletionIcon(self: *const FontManager, kind: CompletionKind) []const u8 {
        if (self.nerd_fonts_enabled) {
            return switch (kind) {
                .function => "\u{f794}", //
                .method => "\u{f6a6}", //
                .variable => "\u{f71b}", //
                .class => "\u{f0e8}", //
                .interface => "\u{f417}", //
                .module => "\u{f40d}", //
                .property => "\u{f02b}", //
                .keyword => "\u{f1de}", //
                .snippet => "\u{f48a}", //
                .text => "\u{f100}", //
                .enum_member => "\u{f435}", //
                .constant => "\u{f8ff}", //
            };
        } else {
            return switch (kind) {
                .function => "[f]",
                .method => "[m]",
                .variable => "[v]",
                .class => "[c]",
                .interface => "[i]",
                .module => "[M]",
                .property => "[p]",
                .keyword => "[k]",
                .snippet => "[s]",
                .text => "[t]",
                .enum_member => "[e]",
                .constant => "[C]",
            };
        }
    }

    pub const CompletionKind = enum {
        function,
        method,
        variable,
        class,
        interface,
        module,
        property,
        keyword,
        snippet,
        text,
        enum_member,
        constant,
    };

    /// Signature help icon
    pub fn getSignatureHelpIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f787}"; //
        } else {
            return "()";
        }
    }

    /// Hover info icon
    pub fn getHoverIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f05a}"; //
        } else {
            return "[?]";
        }
    }

    /// Code action icon
    pub fn getCodeActionIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f0eb}"; //  (lightbulb)
        } else {
            return "[!]";
        }
    }

    /// Inlay hint icon
    pub fn getInlayHintIcon(self: *const FontManager) []const u8 {
        if (self.nerd_fonts_enabled) {
            return "\u{f4a4}"; //
        } else {
            return ":";
        }
    }
};

test "FontManager file icons" {
    const allocator = std.testing.allocator;

    var fm = FontManager.init(allocator, true);
    defer fm.deinit();

    // Test some common file types
    const zig_icon = fm.getFileIcon("test.zig");
    try std.testing.expect(zig_icon.len > 0);

    const rust_icon = fm.getFileIcon("main.rs");
    try std.testing.expect(rust_icon.len > 0);

    const unknown_icon = fm.getFileIcon("file.xyz");
    try std.testing.expect(unknown_icon.len > 0);
}

test "FontManager UI icons" {
    const allocator = std.testing.allocator;

    var fm = FontManager.init(allocator, true);
    defer fm.deinit();

    // Test mode icons
    const normal_icon = fm.getModeIcon(.normal);
    try std.testing.expect(normal_icon.len > 0);

    // Test LSP icons
    const lsp_icon = fm.getLspActiveIcon();
    try std.testing.expect(lsp_icon.len > 0);

    // Test diagnostic icons
    const error_icon = fm.getErrorIcon();
    try std.testing.expect(error_icon.len > 0);
}

test "FontManager ASCII fallback" {
    const allocator = std.testing.allocator;

    var fm = FontManager.init(allocator, false); // Disable Nerd Fonts
    defer fm.deinit();

    const zig_icon = fm.getFileIcon("test.zig");
    try std.testing.expectEqualStrings("[Z]", zig_icon);

    const modified = fm.getModifiedIcon();
    try std.testing.expectEqualStrings("*", modified);

    const normal_mode = fm.getModeIcon(.normal);
    try std.testing.expectEqualStrings("NORMAL", normal_mode);
}

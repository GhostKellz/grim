const std = @import("std");
const core = @import("../core/mod.zig");
const syntax = @import("../syntax/mod.zig");
const ui_tui = @import("../ui-tui/mod.zig");
const Theme = ui_tui.Theme;

/// Ghostlang FFI Bridge - Exposes Grim's Zig APIs to Ghostlang
/// This is Option 1: Direct Zig bindings for maximum performance
pub const GhostlangBridge = struct {
    allocator: std.mem.Allocator,
    fuzzy: ?*core.FuzzyFinder,
    git: ?*core.Git,
    harpoon: ?*core.Harpoon,
    features: ?*syntax.Features,
    zap: ?*core.ZapIntegration,
    theme: ?*Theme,
    theme_name: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) GhostlangBridge {
        return .{
            .allocator = allocator,
            .fuzzy = null,
            .git = null,
            .harpoon = null,
            .features = null,
            .zap = null,
            .theme = null,
            .theme_name = null,
        };
    }

    pub fn deinit(self: *GhostlangBridge) void {
        if (self.fuzzy) |f| {
            f.deinit();
            self.allocator.destroy(f);
        }
        if (self.git) |g| {
            g.deinit();
            self.allocator.destroy(g);
        }
        if (self.harpoon) |h| {
            h.deinit();
            self.allocator.destroy(h);
        }
        if (self.zap) |z| {
            z.deinit();
            self.allocator.destroy(z);
        }
        if (self.theme) |t| {
            self.allocator.destroy(t);
        }
        if (self.theme_name) |name| {
            self.allocator.free(name);
        }
        _ = self.features;
    }

    // ========================================================================
    // FUZZY FINDER API
    // ========================================================================

    /// Initialize fuzzy finder
    pub export fn grim_fuzzy_init(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.fuzzy != null) return true;

        const finder = bridge.allocator.create(core.FuzzyFinder) catch return false;
        finder.* = core.FuzzyFinder.init(bridge.allocator);
        bridge.fuzzy = finder;
        return true;
    }

    /// Find files in directory (returns JSON array of paths)
    pub export fn grim_fuzzy_find_files(
        bridge: *GhostlangBridge,
        path: [*:0]const u8,
        max_depth: usize,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.fuzzy == null) {
            return "[]";
        }

        const path_slice = std.mem.span(path);
        bridge.fuzzy.?.findFiles(path_slice, max_depth) catch return "[]";

        // Return JSON array of file paths
        var json = std.ArrayList(u8).init(bridge.allocator);
        json.append('[') catch return "[]";

        const entries = bridge.fuzzy.?.entries.items;
        for (entries, 0..) |entry, i| {
            json.appendSlice("\"") catch break;
            json.appendSlice(entry.display) catch break;
            json.appendSlice("\"") catch break;
            if (i < entries.len - 1) {
                json.appendSlice(",") catch break;
            }
        }
        json.append(']') catch return "[]";
        json.append(0) catch return "[]"; // Null terminate

        return json.items.ptr;
    }

    /// Filter entries by query
    pub export fn grim_fuzzy_filter(
        bridge: *GhostlangBridge,
        query: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.fuzzy == null) return "[]";

        const query_slice = std.mem.span(query);
        bridge.fuzzy.?.filter(query_slice) catch return "[]";

        // Return JSON array of scored results
        var json = std.ArrayList(u8).init(bridge.allocator);
        json.append('[') catch return "[]";

        const results = bridge.fuzzy.?.getResults();
        for (results, 0..) |result, i| {
            var buf: [256]u8 = undefined;
            const obj = std.fmt.bufPrint(&buf, "{{\"path\":\"{s}\",\"score\":{d}}}", .{ result.entry.path, result.score }) catch break;
            json.appendSlice(obj) catch break;
            if (i < results.len - 1) {
                json.appendSlice(",") catch break;
            }
        }
        json.append(']') catch return "[]";
        json.append(0) catch return "[]";

        return json.items.ptr;
    }

    // ========================================================================
    // GIT API
    // ========================================================================

    /// Initialize git integration
    pub export fn grim_git_init(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.git != null) return true;

        const git = bridge.allocator.create(core.Git) catch return false;
        git.* = core.Git.init(bridge.allocator);
        bridge.git = git;
        return true;
    }

    /// Detect git repository
    pub export fn grim_git_detect(
        bridge: *GhostlangBridge,
        path: [*:0]const u8,
    ) callconv(.C) bool {
        if (bridge.git == null) return false;

        const path_slice = std.mem.span(path);
        return bridge.git.?.detectRepository(path_slice) catch false;
    }

    /// Get current branch (returns null-terminated string)
    pub export fn grim_git_branch(bridge: *GhostlangBridge) callconv(.C) [*:0]const u8 {
        if (bridge.git == null) return "";

        const branch = bridge.git.?.getCurrentBranch() catch return "";
        return branch.ptr;
    }

    /// Get file status (returns: 0=unmodified, 1=modified, 2=added, 3=deleted, 4=renamed, 5=untracked)
    pub export fn grim_git_status(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
    ) callconv(.C) i32 {
        if (bridge.git == null) return 0;

        const path_slice = std.mem.span(filepath);
        const status = bridge.git.?.getFileStatus(path_slice) catch return 0;

        return switch (status) {
            .unmodified => 0,
            .modified => 1,
            .added => 2,
            .deleted => 3,
            .renamed => 4,
            .untracked => 5,
        };
    }

    /// Get git blame for file (returns JSON array)
    pub export fn grim_git_blame(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.git == null) return "[]";

        const path_slice = std.mem.span(filepath);
        const blame = bridge.git.?.getBlame(path_slice) catch return "[]";

        // Return JSON array
        var json = std.ArrayList(u8).init(bridge.allocator);
        json.append('[') catch return "[]";

        for (blame, 0..) |info, i| {
            var buf: [512]u8 = undefined;
            const obj = std.fmt.bufPrint(&buf, "{{\"commit\":\"{s}\",\"author\":\"{s}\",\"date\":\"{s}\"}}", .{ info.commit_hash, info.author, info.date }) catch break;
            json.appendSlice(obj) catch break;
            if (i < blame.len - 1) {
                json.appendSlice(",") catch break;
            }
        }
        json.append(']') catch return "[]";
        json.append(0) catch return "[]";

        return json.items.ptr;
    }

    /// Stage file
    pub export fn grim_git_stage(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
    ) callconv(.C) bool {
        if (bridge.git == null) return false;

        const path_slice = std.mem.span(filepath);
        bridge.git.?.stageFile(path_slice) catch return false;
        return true;
    }

    /// Unstage file
    pub export fn grim_git_unstage(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
    ) callconv(.C) bool {
        if (bridge.git == null) return false;

        const path_slice = std.mem.span(filepath);
        bridge.git.?.unstageFile(path_slice) catch return false;
        return true;
    }

    /// Discard changes
    pub export fn grim_git_discard(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
    ) callconv(.C) bool {
        if (bridge.git == null) return false;

        const path_slice = std.mem.span(filepath);
        bridge.git.?.discardChanges(path_slice) catch return false;
        return true;
    }

    /// Stage hunk at line
    pub export fn grim_git_stage_hunk(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
        line: usize,
    ) callconv(.C) bool {
        if (bridge.git == null) return false;

        const path_slice = std.mem.span(filepath);
        bridge.git.?.stageHunk(path_slice, line) catch return false;
        return true;
    }

    /// Get hunks for file (returns JSON array)
    pub export fn grim_git_hunks(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.git == null) return "[]";

        const path_slice = std.mem.span(filepath);
        const hunks = bridge.git.?.getHunks(path_slice) catch return "[]";

        var json = std.ArrayList(u8).init(bridge.allocator);
        json.append('[') catch return "[]";

        for (hunks, 0..) |hunk, i| {
            const type_str = switch (hunk.hunk_type) {
                .added => "added",
                .modified => "modified",
                .deleted => "deleted",
            };
            var buf: [512]u8 = undefined;
            const obj = std.fmt.bufPrint(&buf, "{{\"start\":{d},\"end\":{d},\"type\":\"{s}\"}}", .{ hunk.start_line, hunk.end_line, type_str }) catch break;
            json.appendSlice(obj) catch break;
            if (i < hunks.len - 1) {
                json.appendSlice(",") catch break;
            }
        }
        json.append(']') catch return "[]";
        json.append(0) catch return "[]";

        return json.items.ptr;
    }

    // ========================================================================
    // HARPOON API
    // ========================================================================

    /// Initialize harpoon
    pub export fn grim_harpoon_init(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.harpoon != null) return true;

        const harpoon = bridge.allocator.create(core.Harpoon) catch return false;
        harpoon.* = core.Harpoon.init(bridge.allocator);
        bridge.harpoon = harpoon;
        return true;
    }

    /// Pin file to slot
    pub export fn grim_harpoon_pin(
        bridge: *GhostlangBridge,
        filepath: [*:0]const u8,
        slot: usize,
        line: usize,
        col: usize,
    ) callconv(.C) bool {
        if (bridge.harpoon == null) return false;

        const path_slice = std.mem.span(filepath);
        bridge.harpoon.?.pin(path_slice, slot, line, col) catch return false;
        return true;
    }

    /// Jump to slot (returns filepath or empty string)
    pub export fn grim_harpoon_jump(
        bridge: *GhostlangBridge,
        slot: usize,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.harpoon == null) return "";

        const file = bridge.harpoon.?.get(slot) orelse return "";
        return file.path.ptr;
    }

    /// Unpin slot
    pub export fn grim_harpoon_unpin(
        bridge: *GhostlangBridge,
        slot: usize,
    ) callconv(.C) bool {
        if (bridge.harpoon == null) return false;

        bridge.harpoon.?.unpin(slot) catch return false;
        return true;
    }

    // ========================================================================
    // SYNTAX FEATURES API
    // ========================================================================

    /// Initialize syntax features
    pub export fn grim_syntax_init(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.features != null) return true;

        const features = bridge.allocator.create(syntax.Features) catch return false;
        features.* = syntax.Features.init(bridge.allocator);
        bridge.features = features;
        return true;
    }

    /// Get fold regions (returns JSON array)
    pub export fn grim_syntax_folds(
        bridge: *GhostlangBridge,
        source: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.features == null) return "[]";

        const source_slice = std.mem.span(source);
        const regions = bridge.features.?.getFoldRegionsSimple(source_slice) catch return "[]";
        defer bridge.allocator.free(regions);

        var json = std.ArrayList(u8).init(bridge.allocator);
        json.append('[') catch return "[]";

        for (regions, 0..) |region, i| {
            var buf: [256]u8 = undefined;
            const obj = std.fmt.bufPrint(&buf, "{{\"start\":{d},\"end\":{d},\"level\":{d}}}", .{ region.start_line, region.end_line, region.level }) catch break;
            json.appendSlice(obj) catch break;
            if (i < regions.len - 1) {
                json.appendSlice(",") catch break;
            }
        }
        json.append(']') catch return "[]";
        json.append(0) catch return "[]";

        return json.items.ptr;
    }

    /// Expand selection (returns JSON with start/end bytes)
    pub export fn grim_syntax_expand(
        bridge: *GhostlangBridge,
        source: [*:0]const u8,
        start: usize,
        end: usize,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.features == null) return "null";

        const source_slice = std.mem.span(source);
        const range = bridge.features.?.expandSelection(source_slice, start, end) catch return "null";

        if (range) |r| {
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf, "{{\"start\":{d},\"end\":{d}}}", .{ r.start_byte, r.end_byte }) catch return "null";

            // Allocate and copy to persist
            const result = bridge.allocator.dupeZ(u8, json) catch return "null";
            return result.ptr;
        }

        return "null";
    }

    /// Shrink selection (returns JSON with start/end bytes)
    pub export fn grim_syntax_shrink(
        bridge: *GhostlangBridge,
        source: [*:0]const u8,
        start: usize,
        end: usize,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.features == null) return "null";

        const source_slice = std.mem.span(source);
        const range = bridge.features.?.shrinkSelection(source_slice, start, end) catch return "null";

        if (range) |r| {
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf, "{{\"start\":{d},\"end\":{d}}}", .{ r.start_byte, r.end_byte }) catch return "null";

            const result = bridge.allocator.dupeZ(u8, json) catch return "null";
            return result.ptr;
        }

        return "null";
    }

    // ========================================================================
    // ZAP AI API
    // ========================================================================

    /// Initialize Zap AI integration
    pub export fn grim_zap_init(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.zap != null) return true;

        const zap_instance = bridge.allocator.create(core.ZapIntegration) catch return false;
        zap_instance.* = core.ZapIntegration.init(bridge.allocator) catch {
            bridge.allocator.destroy(zap_instance);
            return false;
        };
        bridge.zap = zap_instance;
        return true;
    }

    /// Check if Zap/Ollama is available
    pub export fn grim_zap_available(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.zap == null) return false;
        return bridge.zap.?.isAvailable();
    }

    /// Generate AI commit message from diff
    pub export fn grim_zap_commit_message(
        bridge: *GhostlangBridge,
        diff: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const diff_slice = std.mem.span(diff);
        const message = bridge.zap.?.generateCommitMessage(diff_slice) catch return "";

        // Persist the result
        const result = bridge.allocator.dupeZ(u8, message) catch return "";
        return result.ptr;
    }

    /// Explain code changes
    pub export fn grim_zap_explain_changes(
        bridge: *GhostlangBridge,
        changes: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const changes_slice = std.mem.span(changes);
        const explanation = bridge.zap.?.explainChanges(changes_slice) catch return "";

        const result = bridge.allocator.dupeZ(u8, explanation) catch return "";
        return result.ptr;
    }

    /// Suggest merge conflict resolution
    pub export fn grim_zap_resolve_conflict(
        bridge: *GhostlangBridge,
        conflict: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const conflict_slice = std.mem.span(conflict);
        const suggestion = bridge.zap.?.suggestMergeResolution(conflict_slice) catch return "";

        const result = bridge.allocator.dupeZ(u8, suggestion) catch return "";
        return result.ptr;
    }

    /// AI code review
    pub export fn grim_zap_review_code(
        bridge: *GhostlangBridge,
        code: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const code_slice = std.mem.span(code);
        const review = bridge.zap.?.reviewCode(code_slice) catch return "";

        const result = bridge.allocator.dupeZ(u8, review) catch return "";
        return result.ptr;
    }

    /// Generate documentation
    pub export fn grim_zap_generate_docs(
        bridge: *GhostlangBridge,
        code: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const code_slice = std.mem.span(code);
        const docs = bridge.zap.?.generateDocs(code_slice) catch return "";

        const result = bridge.allocator.dupeZ(u8, docs) catch return "";
        return result.ptr;
    }

    /// Suggest better names
    pub export fn grim_zap_suggest_names(
        bridge: *GhostlangBridge,
        code: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const code_slice = std.mem.span(code);
        const names = bridge.zap.?.suggestNames(code_slice) catch return "";

        const result = bridge.allocator.dupeZ(u8, names) catch return "";
        return result.ptr;
    }

    /// Detect code issues
    pub export fn grim_zap_detect_issues(
        bridge: *GhostlangBridge,
        code: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.zap == null) return "";

        const code_slice = std.mem.span(code);
        const issues = bridge.zap.?.detectIssues(code_slice) catch return "";

        const result = bridge.allocator.dupeZ(u8, issues) catch return "";
        return result.ptr;
    }

    // ========================================================================
    // THEME API
    // ========================================================================

    /// Load default theme (ghost-hacker-blue)
    pub export fn grim_theme_load_default(bridge: *GhostlangBridge) callconv(.C) bool {
        // Clean up existing theme
        if (bridge.theme) |t| {
            bridge.allocator.destroy(t);
        }
        if (bridge.theme_name) |name| {
            bridge.allocator.free(name);
        }

        const theme = bridge.allocator.create(Theme) catch return false;
        theme.* = Theme.loadDefault(bridge.allocator) catch {
            bridge.allocator.destroy(theme);
            return false;
        };

        bridge.theme = theme;
        bridge.theme_name = bridge.allocator.dupe(u8, "ghost-hacker-blue") catch null;
        return true;
    }

    /// Load theme from file
    pub export fn grim_theme_load(
        bridge: *GhostlangBridge,
        theme_name: [*:0]const u8,
    ) callconv(.C) bool {
        // Clean up existing theme
        if (bridge.theme) |t| {
            bridge.allocator.destroy(t);
        }
        if (bridge.theme_name) |name| {
            bridge.allocator.free(name);
        }

        const name_slice = std.mem.span(theme_name);

        // Try multiple paths
        const paths = [_][]const u8{
            "themes/{s}.toml",
            "/usr/share/grim/themes/{s}.toml",
            "/usr/local/share/grim/themes/{s}.toml",
        };

        var theme_loaded = false;
        for (paths) |path_fmt| {
            const path = std.fmt.allocPrint(bridge.allocator, path_fmt, .{name_slice}) catch continue;
            defer bridge.allocator.free(path);

            if (Theme.loadFromFile(bridge.allocator, path)) |loaded_theme| {
                const theme = bridge.allocator.create(Theme) catch return false;
                theme.* = loaded_theme;
                bridge.theme = theme;
                bridge.theme_name = bridge.allocator.dupe(u8, name_slice) catch null;
                theme_loaded = true;
                break;
            } else |_| {
                continue;
            }
        }

        return theme_loaded;
    }

    /// Get current theme name
    pub export fn grim_theme_get_name(bridge: *GhostlangBridge) callconv(.C) [*:0]const u8 {
        if (bridge.theme_name) |name| {
            const result = bridge.allocator.dupeZ(u8, name) catch return "";
            return result.ptr;
        }
        return "default";
    }

    /// Get theme color as hex string (#RRGGBB)
    pub export fn grim_theme_get_color(
        bridge: *GhostlangBridge,
        color_name: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        if (bridge.theme == null) return "#c8d3f5"; // Default foreground

        const name_slice = std.mem.span(color_name);
        const theme = bridge.theme.?;

        // Map color names to theme fields
        const color = if (std.mem.eql(u8, name_slice, "foreground"))
            theme.foreground
        else if (std.mem.eql(u8, name_slice, "background"))
            theme.background
        else if (std.mem.eql(u8, name_slice, "cursor"))
            theme.cursor
        else if (std.mem.eql(u8, name_slice, "selection"))
            theme.selection
        else if (std.mem.eql(u8, name_slice, "keyword"))
            theme.keyword
        else if (std.mem.eql(u8, name_slice, "string"))
            theme.string_literal
        else if (std.mem.eql(u8, name_slice, "number"))
            theme.number_literal
        else if (std.mem.eql(u8, name_slice, "comment"))
            theme.comment
        else if (std.mem.eql(u8, name_slice, "function"))
            theme.function_name
        else if (std.mem.eql(u8, name_slice, "type"))
            theme.type_name
        else if (std.mem.eql(u8, name_slice, "variable"))
            theme.variable
        else if (std.mem.eql(u8, name_slice, "operator"))
            theme.operator
        else if (std.mem.eql(u8, name_slice, "line_number"))
            theme.line_number
        else if (std.mem.eql(u8, name_slice, "status_bar_bg"))
            theme.status_bar_bg
        else if (std.mem.eql(u8, name_slice, "status_bar_fg"))
            theme.status_bar_fg
        else
            theme.foreground; // Fallback

        // Convert RGB to hex string
        const hex = std.fmt.allocPrint(
            bridge.allocator,
            "#{x:0>2}{x:0>2}{x:0>2}",
            .{ color.r, color.g, color.b },
        ) catch return "#c8d3f5";

        const result = bridge.allocator.dupeZ(u8, hex) catch {
            bridge.allocator.free(hex);
            return "#c8d3f5";
        };
        bridge.allocator.free(hex);
        return result.ptr;
    }

    /// Get theme info as JSON
    pub export fn grim_theme_get_info(bridge: *GhostlangBridge) callconv(.C) [*:0]const u8 {
        if (bridge.theme == null) {
            return "{\"loaded\":false}";
        }

        const name = if (bridge.theme_name) |n| n else "unknown";

        // Build JSON response
        const json = std.fmt.allocPrint(
            bridge.allocator,
            "{{\"loaded\":true,\"name\":\"{s}\",\"foreground\":\"#{x:0>2}{x:0>2}{x:0>2}\",\"background\":\"#{x:0>2}{x:0>2}{x:0>2}\"}}",
            .{
                name,
                bridge.theme.?.foreground.r,
                bridge.theme.?.foreground.g,
                bridge.theme.?.foreground.b,
                bridge.theme.?.background.r,
                bridge.theme.?.background.g,
                bridge.theme.?.background.b,
            },
        ) catch return "{\"loaded\":false}";

        const result = bridge.allocator.dupeZ(u8, json) catch {
            bridge.allocator.free(json);
            return "{\"loaded\":false}";
        };
        bridge.allocator.free(json);
        return result.ptr;
    }

    /// Check if theme is loaded
    pub export fn grim_theme_is_loaded(bridge: *GhostlangBridge) callconv(.C) bool {
        return bridge.theme != null;
    }

    /// Reload current theme
    pub export fn grim_theme_reload(bridge: *GhostlangBridge) callconv(.C) bool {
        if (bridge.theme_name) |name| {
            const name_z = bridge.allocator.dupeZ(u8, name) catch return false;
            defer bridge.allocator.free(name_z);
            return grim_theme_load(bridge, name_z.ptr);
        }
        return grim_theme_load_default(bridge);
    }
};

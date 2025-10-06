const std = @import("std");
const core = @import("../core/mod.zig");
const syntax = @import("../syntax/mod.zig");

/// Ghostlang FFI Bridge - Exposes Grim's Zig APIs to Ghostlang
/// This is Option 1: Direct Zig bindings for maximum performance
pub const GhostlangBridge = struct {
    allocator: std.mem.Allocator,
    fuzzy: ?*core.FuzzyFinder,
    git: ?*core.Git,
    harpoon: ?*core.Harpoon,
    features: ?*syntax.Features,

    pub fn init(allocator: std.mem.Allocator) GhostlangBridge {
        return .{
            .allocator = allocator,
            .fuzzy = null,
            .git = null,
            .harpoon = null,
            .features = null,
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
            const obj = std.fmt.bufPrint(&buf,
                "{{\"path\":\"{s}\",\"score\":{d}}}",
                .{ result.entry.path, result.score }
            ) catch break;
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
            const obj = std.fmt.bufPrint(&buf,
                "{{\"commit\":\"{s}\",\"author\":\"{s}\",\"date\":\"{s}\"}}",
                .{ info.commit_hash, info.author, info.date }
            ) catch break;
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
            const obj = std.fmt.bufPrint(&buf,
                "{{\"start\":{d},\"end\":{d},\"type\":\"{s}\"}}",
                .{ hunk.start_line, hunk.end_line, type_str }
            ) catch break;
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
            const obj = std.fmt.bufPrint(&buf,
                "{{\"start\":{d},\"end\":{d},\"level\":{d}}}",
                .{ region.start_line, region.end_line, region.level }
            ) catch break;
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
            const json = std.fmt.bufPrint(&buf,
                "{{\"start\":{d},\"end\":{d}}}",
                .{ r.start_byte, r.end_byte }
            ) catch return "null";

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
            const json = std.fmt.bufPrint(&buf,
                "{{\"start\":{d},\"end\":{d}}}",
                .{ r.start_byte, r.end_byte }
            ) catch return "null";

            const result = bridge.allocator.dupeZ(u8, json) catch return "null";
            return result.ptr;
        }

        return "null";
    }
};

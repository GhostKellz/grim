//! Snippet expander for the editor
//! Handles tab stop navigation and snippet expansion

const std = @import("std");
const phantom = @import("phantom");
const core = @import("core");
const snippets = core.snippets;

pub const SnippetState = struct {
    tab_stops: std.ArrayList(snippets.TabStop),
    current_tab_stop: usize, // Index into tab_stops
    snippet_start_offset: usize, // Where snippet was inserted
    expanded_text: []u8, // The expanded snippet text

    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        tab_stops_list: std.ArrayList(snippets.TabStop),
        start_offset: usize,
        expanded: []u8,
    ) SnippetState {
        return .{
            .tab_stops = tab_stops_list,
            .current_tab_stop = 0,
            .snippet_start_offset = start_offset,
            .expanded_text = expanded,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SnippetState) void {
        for (self.tab_stops.items) |*tab_stop| {
            if (tab_stop.placeholder) |placeholder| {
                self.allocator.free(placeholder);
            }
        }
        self.tab_stops.deinit(self.allocator);
        self.allocator.free(self.expanded_text);
    }

    /// Get current tab stop
    pub fn getCurrentTabStop(self: *SnippetState) ?snippets.TabStop {
        // Sort tab stops by index to get correct order
        var sorted_stops = std.ArrayList(snippets.TabStop){};
        defer sorted_stops.deinit(self.allocator);

        sorted_stops.appendSlice(self.allocator, self.tab_stops.items) catch return null;

        std.mem.sort(snippets.TabStop, sorted_stops.items, {}, struct {
            fn lessThan(_: void, a: snippets.TabStop, b: snippets.TabStop) bool {
                if (a.index == 0) return false; // $0 comes last
                if (b.index == 0) return true;
                return a.index < b.index;
            }
        }.lessThan);

        if (self.current_tab_stop >= sorted_stops.items.len) return null;
        return sorted_stops.items[self.current_tab_stop];
    }

    /// Move to next tab stop
    pub fn nextTabStop(self: *SnippetState) bool {
        // Count non-zero tab stops
        var count: usize = 0;
        var has_final = false;
        for (self.tab_stops.items) |stop| {
            if (stop.index == 0) {
                has_final = true;
            } else {
                count += 1;
            }
        }

        const total_stops = count + if (has_final) @as(usize, 1) else @as(usize, 0);

        if (self.current_tab_stop + 1 < total_stops) {
            self.current_tab_stop += 1;
            return true;
        }

        // Reached the end
        return false;
    }

    /// Move to previous tab stop
    pub fn prevTabStop(self: *SnippetState) bool {
        if (self.current_tab_stop > 0) {
            self.current_tab_stop -= 1;
            return true;
        }
        return false;
    }

    /// Get absolute offset of current tab stop in document
    pub fn getCurrentOffset(self: *SnippetState) ?struct { start: usize, end: usize } {
        const tab_stop = self.getCurrentTabStop() orelse return null;
        return .{
            .start = self.snippet_start_offset + tab_stop.start,
            .end = self.snippet_start_offset + tab_stop.end,
        };
    }
};

/// Insert snippet at cursor position
pub fn insertSnippet(
    allocator: std.mem.Allocator,
    rope: *core.Rope,
    cursor_offset: usize,
    snippet: snippets.Snippet,
) !SnippetState {
    var tab_stops = std.ArrayList(snippets.TabStop){};
    errdefer tab_stops.deinit(allocator);

    // Expand snippet
    const expanded = try snippets.expandSnippet(allocator, snippet, &tab_stops);
    errdefer allocator.free(expanded);

    // Insert into rope
    try rope.insert(cursor_offset, expanded);

    return SnippetState.init(allocator, tab_stops, cursor_offset, expanded);
}

/// Trigger snippet completion (check if cursor is at end of a snippet prefix)
pub fn checkSnippetTrigger(
    rope: *core.Rope,
    cursor_offset: usize,
    snippet_library: *snippets.SnippetLibrary,
) ?snippets.Snippet {
    if (cursor_offset == 0) return null;

    const content = rope.slice(.{ .start = 0, .end = cursor_offset }) catch return null;

    // Find word before cursor
    var word_start = cursor_offset;
    while (word_start > 0 and isWordChar(content[word_start - 1])) {
        word_start -= 1;
    }

    if (word_start == cursor_offset) return null;

    const word = content[word_start..cursor_offset];

    // Check if word matches a snippet prefix
    return snippet_library.getSnippet(word);
}

fn isWordChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

test "snippet trigger detection" {
    const allocator = std.testing.allocator;

    var rope = try core.Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "fn");

    var library = snippets.SnippetLibrary.init(allocator);
    defer library.deinit();

    // Manually add a snippet for testing
    const snippet = snippets.Snippet{
        .prefix = "fn",
        .body = &.{ "fn ${1:name}() {", "  ${2:body}", "}" },
        .description = "Function",
    };

    try library.snippets.put(try allocator.dupe(u8, "test_fn"), snippet);

    const detected = checkSnippetTrigger(&rope, 2, &library);
    try std.testing.expect(detected != null);
}

const std = @import("std");
const core = @import("core");

pub const VimState = struct {
    mode: Mode,
    pending_operator: ?Operator,
    count: u32,
    register: u8,
    search_pattern: ?[]const u8,
    last_search_forward: bool,
    dot_command: ?Command,
    visual_start: ?usize,
    mark_positions: std.HashMap(u8, usize),
    jump_list: std.ArrayList(usize),
    jump_index: ?usize,

    pub const Mode = enum {
        normal,
        insert,
        visual,
        visual_line,
        visual_block,
        command,
        search,
    };

    pub const Operator = enum {
        delete,
        change,
        yank,
        format,
        indent,
        outdent,
        lowercase,
        uppercase,
        toggle_case,
    };

    pub const Motion = enum {
        left,
        right,
        up,
        down,
        word_forward,
        word_backward,
        word_end,
        big_word_forward,
        big_word_backward,
        line_start,
        line_end,
        line_first_char,
        file_start,
        file_end,
        paragraph_forward,
        paragraph_backward,
        sentence_forward,
        sentence_backward,
        matching_bracket,
        find_char,
        find_char_backward,
        till_char,
        till_char_backward,
        repeat_find,
        repeat_find_backward,
    };

    pub const TextObject = enum {
        inner_word,
        around_word,
        inner_sentence,
        around_sentence,
        inner_paragraph,
        around_paragraph,
        inner_paren,
        around_paren,
        inner_bracket,
        around_bracket,
        inner_brace,
        around_brace,
        inner_angle,
        around_angle,
        inner_quote,
        around_quote,
        inner_double_quote,
        around_double_quote,
        inner_backtick,
        around_backtick,
        inner_tag,
        around_tag,
    };

    pub const Command = struct {
        operator: ?Operator,
        motion: ?Motion,
        text_object: ?TextObject,
        count: u32,
        register: u8,
        char_arg: ?u21,
    };

    pub fn init(allocator: std.mem.Allocator) VimState {
        return .{
            .mode = .normal,
            .pending_operator = null,
            .count = 0,
            .register = '"',
            .search_pattern = null,
            .last_search_forward = true,
            .dot_command = null,
            .visual_start = null,
            .mark_positions = std.HashMap(u8, usize).init(allocator),
            .jump_list = std.ArrayList(usize).init(allocator),
            .jump_index = null,
        };
    }

    pub fn deinit(self: *VimState, allocator: std.mem.Allocator) void {
        if (self.search_pattern) |pattern| allocator.free(pattern);
        self.mark_positions.deinit();
        self.jump_list.deinit();
    }
};

pub const VimEngine = struct {
    allocator: std.mem.Allocator,
    state: VimState,
    rope: *core.Rope,
    registers: std.HashMap(u8, []u8),
    last_insert_text: std.ArrayList(u8),
    find_char: ?u21,
    find_forward: bool,
    cursor: usize,

    pub const Error = error{
        InvalidCommand,
        InvalidMotion,
        InvalidTextObject,
        BufferEmpty,
        OutOfBounds,
    } || std.mem.Allocator.Error || core.Rope.Error;

    pub fn init(allocator: std.mem.Allocator, rope: *core.Rope) !*VimEngine {
        const self = try allocator.create(VimEngine);
        self.* = .{
            .allocator = allocator,
            .state = VimState.init(allocator),
            .rope = rope,
            .registers = std.HashMap(u8, []u8).init(allocator),
            .last_insert_text = std.ArrayList(u8).init(allocator),
            .find_char = null,
            .find_forward = true,
            .cursor = 0,
        };
        return self;
    }

    pub fn deinit(self: *VimEngine) void {
        self.state.deinit(self.allocator);

        // Free registers
        var iter = self.registers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.registers.deinit();

        self.last_insert_text.deinit();
        self.allocator.destroy(self);
    }

    pub fn executeCommand(self: *VimEngine, command: VimState.Command) Error!void {
        // Handle operator + motion/text object combinations
        if (command.operator) |op| {
            const range = if (command.motion) |motion|
                try self.getMotionRange(motion, command.count, command.char_arg)
            else if (command.text_object) |text_obj|
                try self.getTextObjectRange(text_obj, self.cursor)
            else
                return Error.InvalidCommand;

            try self.executeOperator(op, range, command.register);
        } else if (command.motion) |motion| {
            // Pure motion
            const new_pos = try self.executeMotion(motion, command.count, command.char_arg);
            self.cursor = new_pos;
        }

        // Save command for dot repeat
        if (command.operator != null) {
            self.state.dot_command = command;
        }
    }

    fn executeOperator(self: *VimEngine, operator: VimState.Operator, range: Range, register: u8) Error!void {
        const start = @min(range.start, range.end);
        const end = @max(range.start, range.end);

        switch (operator) {
            .delete => {
                const deleted = try self.rope.slice(.{ .start = start, .end = end });
                try self.setRegister(register, deleted);
                try self.rope.delete(start, end - start);
                self.cursor = start;
            },
            .change => {
                const deleted = try self.rope.slice(.{ .start = start, .end = end });
                try self.setRegister(register, deleted);
                try self.rope.delete(start, end - start);
                self.cursor = start;
                self.state.mode = .insert;
            },
            .yank => {
                const yanked = try self.rope.slice(.{ .start = start, .end = end });
                try self.setRegister(register, yanked);
            },
            .format => {
                // TODO: Implement formatting via LSP
            },
            .indent => {
                try self.indentLines(start, end);
            },
            .outdent => {
                try self.outdentLines(start, end);
            },
            .lowercase => {
                try self.changeCaseRange(start, end, .lower);
            },
            .uppercase => {
                try self.changeCaseRange(start, end, .upper);
            },
            .toggle_case => {
                try self.changeCaseRange(start, end, .toggle);
            },
        }
    }

    fn executeMotion(self: *VimEngine, motion: VimState.Motion, count: u32, char_arg: ?u21) Error!usize {
        const effective_count = if (count == 0) 1 else count;
        var new_pos = self.cursor;

        for (0..effective_count) |_| {
            new_pos = switch (motion) {
                .left => try self.moveLeft(new_pos),
                .right => try self.moveRight(new_pos),
                .up => try self.moveUp(new_pos),
                .down => try self.moveDown(new_pos),
                .word_forward => try self.moveWordForward(new_pos, false),
                .word_backward => try self.moveWordBackward(new_pos, false),
                .word_end => try self.moveWordEnd(new_pos, false),
                .big_word_forward => try self.moveWordForward(new_pos, true),
                .big_word_backward => try self.moveWordBackward(new_pos, true),
                .line_start => try self.moveLineStart(new_pos),
                .line_end => try self.moveLineEnd(new_pos),
                .line_first_char => try self.moveLineFirstChar(new_pos),
                .file_start => 0,
                .file_end => self.rope.len(),
                .paragraph_forward => try self.moveParagraphForward(new_pos),
                .paragraph_backward => try self.moveParagraphBackward(new_pos),
                .sentence_forward => try self.moveSentenceForward(new_pos),
                .sentence_backward => try self.moveSentenceBackward(new_pos),
                .matching_bracket => try self.moveMatchingBracket(new_pos),
                .find_char => try self.moveFindChar(new_pos, char_arg.?, true),
                .find_char_backward => try self.moveFindChar(new_pos, char_arg.?, false),
                .till_char => try self.moveTillChar(new_pos, char_arg.?, true),
                .till_char_backward => try self.moveTillChar(new_pos, char_arg.?, false),
                .repeat_find => try self.moveRepeatFind(new_pos),
                .repeat_find_backward => try self.moveRepeatFindBackward(new_pos),
            };
        }

        return new_pos;
    }

    fn getMotionRange(self: *VimEngine, motion: VimState.Motion, count: u32, char_arg: ?u21) Error!Range {
        const start = self.cursor;
        const end = try self.executeMotion(motion, count, char_arg);
        return Range{ .start = start, .end = end };
    }

    fn getTextObjectRange(self: *VimEngine, text_object: VimState.TextObject, pos: usize) Error!Range {
        return switch (text_object) {
            .inner_word => try self.getWordRange(pos, true),
            .around_word => try self.getWordRange(pos, false),
            .inner_sentence => try self.getSentenceRange(pos, true),
            .around_sentence => try self.getSentenceRange(pos, false),
            .inner_paragraph => try self.getParagraphRange(pos, true),
            .around_paragraph => try self.getParagraphRange(pos, false),
            .inner_paren => try self.getBracketRange(pos, '(', ')', true),
            .around_paren => try self.getBracketRange(pos, '(', ')', false),
            .inner_bracket => try self.getBracketRange(pos, '[', ']', true),
            .around_bracket => try self.getBracketRange(pos, '[', ']', false),
            .inner_brace => try self.getBracketRange(pos, '{', '}', true),
            .around_brace => try self.getBracketRange(pos, '{', '}', false),
            .inner_angle => try self.getBracketRange(pos, '<', '>', true),
            .around_angle => try self.getBracketRange(pos, '<', '>', false),
            .inner_quote => try self.getQuoteRange(pos, '\'', true),
            .around_quote => try self.getQuoteRange(pos, '\'', false),
            .inner_double_quote => try self.getQuoteRange(pos, '"', true),
            .around_double_quote => try self.getQuoteRange(pos, '"', false),
            .inner_backtick => try self.getQuoteRange(pos, '`', true),
            .around_backtick => try self.getQuoteRange(pos, '`', false),
            .inner_tag => try self.getTagRange(pos, true),
            .around_tag => try self.getTagRange(pos, false),
        };
    }

    // Movement implementations
    fn moveLeft(self: *VimEngine, pos: usize) Error!usize {
        if (pos == 0) return pos;
        const content = try self.rope.slice(.{ .start = 0, .end = pos });

        // Find previous UTF-8 character boundary
        var i = pos - 1;
        while (i > 0 and (content[i] & 0xC0) == 0x80) : (i -= 1) {}
        return i;
    }

    fn moveRight(self: *VimEngine, pos: usize) Error!usize {
        const len = self.rope.len();
        if (pos >= len) return pos;

        const content = try self.rope.slice(.{ .start = pos, .end = len });
        if (content.len == 0) return pos;

        // Find next UTF-8 character boundary
        var i: usize = 1;
        while (i < content.len and (content[i] & 0xC0) == 0x80) : (i += 1) {}
        return @min(pos + i, len);
    }

    fn moveUp(self: *VimEngine, pos: usize) Error!usize {
        const line_start = try self.moveLineStart(pos);
        if (line_start == 0) return pos; // Already at first line

        // Find previous line start
        const prev_line_end = line_start - 1;
        const prev_line_start = try self.moveLineStart(prev_line_end);

        // Maintain column position
        const col = pos - line_start;
        const prev_line_len = prev_line_end - prev_line_start;
        return prev_line_start + @min(col, prev_line_len);
    }

    fn moveDown(self: *VimEngine, pos: usize) Error!usize {
        const line_start = try self.moveLineStart(pos);
        const line_end = try self.moveLineEnd(pos);

        // Check if there's a next line
        if (line_end >= self.rope.len() - 1) return pos;

        const next_line_start = line_end + 1;
        const next_line_end = try self.moveLineEnd(next_line_start);

        // Maintain column position
        const col = pos - line_start;
        const next_line_len = next_line_end - next_line_start;
        return next_line_start + @min(col, next_line_len);
    }

    fn moveWordForward(self: *VimEngine, pos: usize, big_word: bool) Error!usize {
        const len = self.rope.len();
        if (pos >= len) return pos;

        const content = try self.rope.slice(.{ .start = pos, .end = len });
        var i: usize = 0;

        // Skip current word
        while (i < content.len) {
            const ch = content[i];
            if (big_word) {
                if (std.ascii.isWhitespace(ch)) break;
            } else {
                if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
            }
            i += 1;
        }

        // Skip whitespace
        while (i < content.len and std.ascii.isWhitespace(content[i])) : (i += 1) {}

        return @min(pos + i, len);
    }

    fn moveWordBackward(self: *VimEngine, pos: usize, big_word: bool) Error!usize {
        if (pos == 0) return 0;

        const content = try self.rope.slice(.{ .start = 0, .end = pos });
        var i = content.len;

        // Skip whitespace
        while (i > 0 and std.ascii.isWhitespace(content[i - 1])) : (i -= 1) {}
        if (i == 0) return 0;

        // Skip word
        while (i > 0) {
            const ch = content[i - 1];
            if (big_word) {
                if (std.ascii.isWhitespace(ch)) break;
            } else {
                if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
            }
            i -= 1;
        }

        return i;
    }

    fn moveWordEnd(self: *VimEngine, pos: usize, big_word: bool) Error!usize {
        const len = self.rope.len();
        if (pos >= len - 1) return len - 1;

        const content = try self.rope.slice(.{ .start = pos + 1, .end = len });
        var i: usize = 0;

        // Skip whitespace
        while (i < content.len and std.ascii.isWhitespace(content[i])) : (i += 1) {}

        // Find end of word
        while (i < content.len) {
            const ch = content[i];
            if (big_word) {
                if (std.ascii.isWhitespace(ch)) break;
            } else {
                if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
            }
            i += 1;
        }

        return @min(pos + i, len - 1);
    }

    fn moveLineStart(self: *VimEngine, pos: usize) Error!usize {
        if (pos == 0) return 0;

        const content = try self.rope.slice(.{ .start = 0, .end = pos });
        var i = content.len;

        while (i > 0) : (i -= 1) {
            if (content[i - 1] == '\n') break;
        }

        return i;
    }

    fn moveLineEnd(self: *VimEngine, pos: usize) Error!usize {
        const len = self.rope.len();
        if (pos >= len) return len;

        const content = try self.rope.slice(.{ .start = pos, .end = len });
        for (content, 0..) |ch, i| {
            if (ch == '\n') return pos + i;
        }

        return len;
    }

    fn moveLineFirstChar(self: *VimEngine, pos: usize) Error!usize {
        const line_start = try self.moveLineStart(pos);
        const line_end = try self.moveLineEnd(pos);

        const line_content = try self.rope.slice(.{ .start = line_start, .end = line_end });
        for (line_content, 0..) |ch, i| {
            if (!std.ascii.isWhitespace(ch)) {
                return line_start + i;
            }
        }

        return line_start;
    }

    // Text object implementations
    fn getWordRange(self: *VimEngine, pos: usize, inner: bool) Error!Range {
        _ = inner;
        const len = self.rope.len();
        const content = try self.rope.slice(.{ .start = 0, .end = len });

        // Find word boundaries
        var start = pos;
        var end = pos;

        // Find start of word
        while (start > 0 and self.isWordChar(content[start - 1])) : (start -= 1) {}

        // Find end of word
        while (end < content.len and self.isWordChar(content[end])) : (end += 1) {}

        return Range{ .start = start, .end = end };
    }

    fn getBracketRange(self: *VimEngine, pos: usize, open: u8, close: u8, inner: bool) Error!Range {
        const len = self.rope.len();
        const content = try self.rope.slice(.{ .start = 0, .end = len });

        // Find opening bracket
        var start_pos: ?usize = null;
        var depth: i32 = 0;

        var i = pos;
        while (i > 0) : (i -= 1) {
            const ch = content[i - 1];
            if (ch == close) {
                depth += 1;
            } else if (ch == open) {
                if (depth == 0) {
                    start_pos = i - 1;
                    break;
                }
                depth -= 1;
            }
        }

        if (start_pos == null) return Error.InvalidTextObject;

        // Find closing bracket
        var end_pos: ?usize = null;
        depth = 0;
        i = pos;
        while (i < content.len) : (i += 1) {
            const ch = content[i];
            if (ch == open) {
                depth += 1;
            } else if (ch == close) {
                if (depth == 0) {
                    end_pos = i;
                    break;
                }
                depth -= 1;
            }
        }

        if (end_pos == null) return Error.InvalidTextObject;

        const start = if (inner) start_pos.? + 1 else start_pos.?;
        const end = if (inner) end_pos.? else end_pos.? + 1;

        return Range{ .start = start, .end = end };
    }

    // Helper functions
    fn isWordChar(self: *VimEngine, ch: u8) bool {
        _ = self;
        return std.ascii.isAlphanumeric(ch) or ch == '_';
    }

    fn setRegister(self: *VimEngine, register: u8, content: []const u8) !void {
        if (self.registers.get(register)) |existing| {
            self.allocator.free(existing);
        }
        try self.registers.put(register, try self.allocator.dupe(u8, content));
    }

    // Placeholder implementations for remaining functions
    fn moveParagraphForward(self: *VimEngine, pos: usize) Error!usize {
        _ = self;
        return pos;
    }

    fn moveParagraphBackward(self: *VimEngine, pos: usize) Error!usize {
        _ = self;
        return pos;
    }

    fn moveSentenceForward(self: *VimEngine, pos: usize) Error!usize {
        _ = self;
        return pos;
    }

    fn moveSentenceBackward(self: *VimEngine, pos: usize) Error!usize {
        _ = self;
        return pos;
    }

    fn moveMatchingBracket(self: *VimEngine, pos: usize) Error!usize {
        _ = self;
        return pos;
    }

    fn moveFindChar(self: *VimEngine, pos: usize, char: u21, forward: bool) Error!usize {
        _ = self;
        _ = char;
        _ = forward;
        return pos;
    }

    fn moveTillChar(self: *VimEngine, pos: usize, char: u21, forward: bool) Error!usize {
        _ = self;
        _ = char;
        _ = forward;
        return pos;
    }

    fn moveRepeatFind(self: *VimEngine, pos: usize) Error!usize {
        _ = self;
        return pos;
    }

    fn moveRepeatFindBackward(self: *VimEngine, pos: usize) Error!usize {
        _ = self;
        return pos;
    }

    fn getSentenceRange(self: *VimEngine, pos: usize, inner: bool) Error!Range {
        _ = self;
        _ = inner;
        return Range{ .start = pos, .end = pos };
    }

    fn getParagraphRange(self: *VimEngine, pos: usize, inner: bool) Error!Range {
        _ = self;
        _ = inner;
        return Range{ .start = pos, .end = pos };
    }

    fn getQuoteRange(self: *VimEngine, pos: usize, quote: u8, inner: bool) Error!Range {
        _ = self;
        _ = quote;
        _ = inner;
        return Range{ .start = pos, .end = pos };
    }

    fn getTagRange(self: *VimEngine, pos: usize, inner: bool) Error!Range {
        _ = self;
        _ = inner;
        return Range{ .start = pos, .end = pos };
    }

    fn indentLines(self: *VimEngine, start: usize, end: usize) Error!void {
        _ = self;
        _ = start;
        _ = end;
    }

    fn outdentLines(self: *VimEngine, start: usize, end: usize) Error!void {
        _ = self;
        _ = start;
        _ = end;
    }

    fn changeCaseRange(self: *VimEngine, start: usize, end: usize, case: enum { lower, upper, toggle }) Error!void {
        _ = self;
        _ = start;
        _ = end;
        _ = case;
    }

    const Range = struct {
        start: usize,
        end: usize,
    };
};
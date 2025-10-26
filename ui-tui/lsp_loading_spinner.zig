const std = @import("std");
const phantom = @import("phantom");


pub const LSPLoadingSpinner = struct {
    spinner: *phantom.widgets.Spinner,
    allocator: std.mem.Allocator,
    visible: bool,

    pub fn init(allocator: std.mem.Allocator) !*LSPLoadingSpinner {
        const self = try allocator.create(LSPLoadingSpinner);

        const spinner = try phantom.widgets.Spinner.init(allocator);

        // Configure spinner style (dots animation looks clean)
        spinner.spinner_style = .dots;  // ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏

        // Style the spinner
        spinner.spinner_color = phantom.Style.default().withFg(phantom.Color.bright_cyan);
        spinner.message_style = phantom.Style.default().withFg(phantom.Color.bright_white);

        self.* = .{
            .spinner = spinner,
            .allocator = allocator,
            .visible = false,
        };

        return self;
    }

    pub fn deinit(self: *LSPLoadingSpinner) void {
        self.spinner.widget.vtable.deinit(&self.spinner.widget);
        self.allocator.destroy(self);
    }

    /// Start showing spinner with message
    pub fn start(self: *LSPLoadingSpinner, message: []const u8) void {
        self.spinner.setMessage(message);
        self.visible = true;
    }

    /// Update spinner message while it's running
    pub fn updateMessage(self: *LSPLoadingSpinner, message: []const u8) void {
        self.spinner.setMessage(message);
    }

    /// Stop showing spinner
    pub fn stop(self: *LSPLoadingSpinner) void {
        self.visible = false;
    }

    /// Advance animation frame (call on each tick)
    pub fn tick(self: *LSPLoadingSpinner) void {
        if (self.visible) {
            self.spinner.tick();
        }
    }

    /// Change spinner style
    pub fn setStyle(self: *LSPLoadingSpinner, style: phantom.widgets.SpinnerStyle) void {
        self.spinner.setStyle(style);
    }

    pub fn render(self: *LSPLoadingSpinner, buffer: anytype, area: phantom.Rect) void {
        if (!self.visible) return;
        self.spinner.widget.vtable.render(&self.spinner.widget, buffer, area);
    }
};

/// Predefined messages for common LSP operations
pub const LSPMessages = struct {
    pub const INITIALIZING = "Initializing LSP server...";
    pub const LOADING_COMPLETIONS = "Loading completions...";
    pub const FETCHING_DIAGNOSTICS = "Fetching diagnostics...";
    pub const FORMATTING = "Formatting document...";
    pub const GOTO_DEFINITION = "Finding definition...";
    pub const FIND_REFERENCES = "Finding references...";
    pub const HOVER = "Loading documentation...";
    pub const RENAME = "Renaming symbol...";
    pub const CODE_ACTION = "Loading code actions...";
    pub const SIGNATURE_HELP = "Loading signature help...";
};

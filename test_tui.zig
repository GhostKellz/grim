const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Phantom runtime
    try phantom.runtime.initRuntime(allocator);
    defer phantom.runtime.deinitRuntime();

    // Create application
    var app = try phantom.App.init(allocator, .{
        .title = "Grim Test",
        .tick_rate_ms = 50,
        .mouse_enabled = true,
    });
    defer app.deinit();

    // Create a simple text widget
    var text = try phantom.widgets.Text.init(allocator, "Hello from Grim!\nPress 'q' to quit.");
    defer text.deinit();

    text.setStyle(phantom.Style.default()
        .withFg(phantom.Color.bright_green)
        .withBold());

    // Add widget to app
    try app.addWidget(&text.widget);

    // Event handler
    const TestEventHandler = struct {
        fn handle(event: phantom.Event, user_data: ?*anyopaque) anyerror!bool {
            _ = user_data;
            switch (event) {
                .key => |key| {
                    switch (key) {
                        .char => |c| {
                            if (c == 'q' or c == 'Q') return false; // Quit
                        },
                        .ctrl => |c| {
                            if (c == 'c' or c == 'q') return false; // Quit
                        },
                        else => {},
                    }
                },
                else => {},
            }
            return true;
        }
    };

    try app.event_loop.addHandler(TestEventHandler.handle);

    std.debug.print("Starting test TUI... Press 'q' or Ctrl+C to quit.\n");

    // Run the app
    try app.run();

    std.debug.print("Test TUI closed.\n");
}

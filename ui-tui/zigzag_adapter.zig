/// ZigZag-Phantom Event Loop Bridge
/// Connects ZigZag's high-performance event loop with Phantom's event system

const std = @import("std");
const zigzag = @import("zigzag");
const phantom = @import("phantom");
const escape_parser = @import("escape_parser.zig");

/// Event handler function type with explicit error set
pub const EventHandler = *const fn (phantom.Event) anyerror!bool;

/// Bridge between ZigZag event loop and Phantom event handlers
pub const ZigZagPhantomBridge = struct {
    allocator: std.mem.Allocator,
    zigzag_loop: zigzag.EventLoop,
    phantom_handlers: std.ArrayList(EventHandler),

    // Event loop state
    stdin_watch: ?*const zigzag.Watch = null,
    tick_timer: ?zigzag.Timer = null,
    should_stop: bool = false,

    // Terminal state
    terminal_size: phantom.Size,

    /// Initialize the bridge
    pub fn init(allocator: std.mem.Allocator, terminal_size: phantom.Size) !*ZigZagPhantomBridge {
        const self = try allocator.create(ZigZagPhantomBridge);

        // Initialize ZigZag event loop with event coalescing enabled
        const loop = try zigzag.EventLoop.init(allocator, .{
            .max_events = 256,
            .backend = .epoll, // Use epoll (io_uring requires kernel 6.1+)
            .coalescing = .{
                .coalesce_resize = true,
                .max_coalesce_time_ms = 10,
                .max_batch_size = 32,
            },
        });

        self.* = .{
            .allocator = allocator,
            .zigzag_loop = loop,
            .phantom_handlers = .empty,
            .terminal_size = terminal_size,
        };

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *ZigZagPhantomBridge) void {
        // Cancel timers
        if (self.tick_timer) |*timer| {
            self.zigzag_loop.cancelTimer(timer);
        }

        // Remove watches
        if (self.stdin_watch) |watch| {
            self.zigzag_loop.removeFd(watch);
        }

        self.phantom_handlers.deinit(self.allocator);
        self.zigzag_loop.deinit();
        self.allocator.destroy(self);
    }

    /// Add a Phantom event handler
    pub fn addHandler(self: *ZigZagPhantomBridge, handler: EventHandler) !void {
        try self.phantom_handlers.append(self.allocator, handler);
    }

    /// Start watching stdin for keyboard input
    pub fn watchStdin(self: *ZigZagPhantomBridge) !void {
        const stdin_fd = std.posix.STDIN_FILENO;

        // Add stdin to ZigZag event loop
        const watch = try self.zigzag_loop.addFd(stdin_fd, .{ .read = true });
        self.stdin_watch = watch;

        // Set callback
        self.zigzag_loop.setCallback(watch, stdinCallback);

        // Store self as user_data
        if (self.zigzag_loop.watches.getPtr(stdin_fd)) |stored_watch| {
            stored_watch.user_data = @ptrCast(self);
        }
    }

    /// Add tick timer for rendering (60 FPS = ~16ms)
    pub fn addTickTimer(self: *ZigZagPhantomBridge, interval_ms: u64) !void {
        self.tick_timer = try self.zigzag_loop.addRecurringTimer(interval_ms, tickCallback);

        // Store self as user_data in timer
        if (self.zigzag_loop.timers.getPtr(self.tick_timer.?.id)) |stored_timer| {
            stored_timer.user_data = @ptrCast(self);
        }
    }

    /// Run the event loop (blocking)
    pub fn run(self: *ZigZagPhantomBridge) !void {
        while (!self.should_stop) {
            const had_events = try self.zigzag_loop.tick();

            if (!had_events) {
                // Sleep for 10ms if no events
                std.posix.nanosleep(0, 10 * std.time.ns_per_ms);
            }
        }
    }

    /// Stop the event loop
    pub fn stop(self: *ZigZagPhantomBridge) void {
        self.should_stop = true;
        self.zigzag_loop.stop();
    }

    /// Dispatch a Phantom event to all registered handlers
    fn dispatchEvent(self: *ZigZagPhantomBridge, event: phantom.Event) !void {
        for (self.phantom_handlers.items) |handler| {
            const handled = try handler(event);
            if (handled) break;
        }
    }

    /// Stdin callback - handles keyboard input
    fn stdinCallback(watch: *const zigzag.Watch, event: zigzag.Event) void {
        if (event.type != .read_ready) return;

        // Get self from user_data
        const self = @as(*ZigZagPhantomBridge, @ptrCast(@alignCast(watch.user_data orelse return)));

        // Read from stdin
        var buffer: [4096]u8 = undefined;
        const bytes_read = std.posix.read(event.fd, &buffer) catch |err| {
            std.log.err("Failed to read from stdin: {}", .{err});
            return;
        };

        if (bytes_read == 0) return;

        // Parse escape sequences
        var parser = escape_parser.EscapeParser.init(buffer[0..bytes_read]);
        while (parser.next()) |key| {
            // Create Phantom key event
            const phantom_event = phantom.Event{ .key = key };

            // Dispatch to handlers
            self.dispatchEvent(phantom_event) catch |err| {
                std.log.err("Error dispatching key event: {}", .{err});
            };
        }
    }

    /// Tick callback - triggers rendering
    fn tickCallback(user_data: ?*anyopaque) void {
        const self = @as(*ZigZagPhantomBridge, @ptrCast(@alignCast(user_data orelse return)));

        // Create Phantom tick event
        const phantom_event = phantom.Event{ .tick = {} };

        // Dispatch to handlers
        self.dispatchEvent(phantom_event) catch |err| {
            std.log.err("Error dispatching tick event: {}", .{err});
        };
    }
};

/// Initialize terminal signal handler for window resize
pub fn initSignalHandler(allocator: std.mem.Allocator, loop: *zigzag.EventLoop, bridge: *ZigZagPhantomBridge) !zigzag.terminal.SignalHandler {
    var signal_handler = try zigzag.terminal.SignalHandler.init(loop);
    try signal_handler.register();

    // Note: Signal handler automatically uses event loop's coalescer
    // SIGWINCH events will be delivered as .window_resize events
    // We'd need to add a callback mechanism to handle them
    // For now, the coalescer will batch resize events automatically

    _ = allocator;
    _ = bridge;

    return signal_handler;
}

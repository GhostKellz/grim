//! AI module for Grim editor
//! Integrates with thanos.grim plugin for AI-powered features

const std = @import("std");

pub const InlineCompletionEngine = @import("inline_completion.zig").InlineCompletionEngine;
pub const CompletionContext = @import("inline_completion.zig").CompletionContext;
pub const Completion = @import("inline_completion.zig").Completion;
pub const DebounceTimer = @import("inline_completion.zig").DebounceTimer;

pub const GhostText = @import("ghost_text.zig").GhostText;
pub const GhostTextRenderer = @import("ghost_text.zig").GhostTextRenderer;
pub const GhostTextStyle = @import("ghost_text.zig").GhostTextStyle;

pub const ChatWindow = @import("chat_window.zig").ChatWindow;
pub const ChatMessage = @import("chat_window.zig").ChatMessage;
pub const ChatHistory = @import("chat_window.zig").ChatHistory;
pub const MessageRole = @import("chat_window.zig").MessageRole;

pub const DiffViewer = @import("diff_viewer.zig").DiffViewer;
pub const DiffHunk = @import("diff_viewer.zig").DiffHunk;
pub const DiffLine = @import("diff_viewer.zig").DiffLine;
pub const ChangeType = @import("diff_viewer.zig").ChangeType;

pub const ProviderSwitcher = @import("provider_switcher.zig").ProviderSwitcher;
pub const ProviderInfo = @import("provider_switcher.zig").ProviderInfo;

pub const ContextManager = @import("context_manager.zig").ContextManager;
pub const ContextItem = @import("context_manager.zig").ContextItem;
pub const ContextType = @import("context_manager.zig").ContextType;

pub const CostTracker = @import("cost_tracker.zig").CostTracker;
pub const ProviderCost = @import("cost_tracker.zig").ProviderCost;
pub const CostEstimate = @import("cost_tracker.zig").CostEstimate;

// AI Client - manages AI features for editor
pub const Client = struct {
    allocator: std.mem.Allocator,
    inline_engine: ?*InlineCompletionEngine,
    ghost_renderer: ?*GhostTextRenderer,
    chat_window: ?*ChatWindow,
    context_manager: ?*ContextManager,
    cost_tracker: ?*CostTracker,

    pub fn init(allocator: std.mem.Allocator) !*Client {
        const self = try allocator.create(Client);
        self.* = .{
            .allocator = allocator,
            .inline_engine = try InlineCompletionEngine.init(allocator, 300),
            .ghost_renderer = try allocator.create(GhostTextRenderer),
            .chat_window = null,
            .context_manager = null,
            .cost_tracker = null,
        };
        self.ghost_renderer.?.* = GhostTextRenderer.init(allocator);
        return self;
    }

    pub fn deinit(self: *Client) void {
        if (self.inline_engine) |engine| {
            engine.deinit();
            self.allocator.destroy(engine);
        }
        if (self.ghost_renderer) |renderer| {
            renderer.deinit();
            self.allocator.destroy(renderer);
        }
        if (self.chat_window) |window| {
            window.deinit();
        }
        if (self.context_manager) |manager| {
            manager.deinit();
        }
        if (self.cost_tracker) |tracker| {
            tracker.deinit();
        }
        self.allocator.destroy(self);
    }
};

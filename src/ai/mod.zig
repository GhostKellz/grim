//! AI module for Grim editor
//! Integrates with thanos.grim plugin for AI-powered features

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

// Client is just a marker type for now
pub const Client = struct {
    // TODO: Remove this placeholder
};

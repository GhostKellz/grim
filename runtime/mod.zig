const std = @import("std");

// Core plugin system
pub const plugin_api = @import("plugin_api.zig");
pub const plugin_manager = @import("plugin_manager.zig");
pub const plugin_manifest = @import("plugin_manifest.zig");
pub const plugin_discovery = @import("plugin_discovery.zig");
pub const plugin_loader = @import("plugin_loader.zig");
pub const native_plugin = @import("native_plugin.zig");
pub const plugin_cache = @import("plugin_cache.zig");
pub const example_plugin = @import("example_plugin.zig");

// Phase 3 Runtime APIs
pub const buffer_edit_api = @import("buffer_edit_api.zig");
pub const operator_repeat_api = @import("operator_repeat_api.zig");
pub const command_replay_api = @import("command_replay_api.zig");
pub const buffer_events_api = @import("buffer_events_api.zig");
pub const highlight_theme_api = @import("highlight_theme_api.zig");
pub const test_harness = @import("test_harness.zig");

// Re-exports: Core plugin system
pub const PluginAPI = plugin_api.PluginAPI;
pub const Plugin = plugin_api.PluginAPI.Plugin;
pub const PluginContext = plugin_api.PluginAPI.PluginContext;
pub const Command = plugin_api.PluginAPI.Command;
pub const EventType = plugin_api.PluginAPI.EventType;
pub const EventData = plugin_api.PluginAPI.EventData;
pub const EventHandler = plugin_api.PluginAPI.EventHandler;
pub const KeystrokeHandler = plugin_api.PluginAPI.KeystrokeHandler;

pub const PluginManager = plugin_manager.PluginManager;
pub const PluginManifest = plugin_manifest.PluginManifest;
pub const PluginDiscovery = plugin_discovery.PluginDiscovery;
pub const DiscoveredPlugin = plugin_discovery.DiscoveredPlugin;
pub const PluginLoader = plugin_loader.PluginLoader;
pub const LoadedPlugin = plugin_loader.LoadedPlugin;
pub const NativePluginLoader = native_plugin.NativePluginLoader;
pub const NativePlugin = native_plugin.NativePlugin;
pub const PluginCache = plugin_cache.PluginCache;
pub const UpdateStrategy = plugin_cache.UpdateStrategy;

// Re-exports: Phase 3 Runtime APIs
pub const BufferEditAPI = buffer_edit_api.BufferEditAPI;
pub const OperatorRepeatAPI = operator_repeat_api.OperatorRepeatAPI;
pub const CommandReplayAPI = command_replay_api.CommandReplayAPI;
pub const BufferEventsAPI = buffer_events_api.BufferEventsAPI;
pub const HighlightThemeAPI = highlight_theme_api.HighlightThemeAPI;
pub const TestHarness = test_harness.TestHarness;

// Type aliases for convenience
pub const TextObject = buffer_edit_api.BufferEditAPI.TextObject;
pub const VirtualCursor = buffer_edit_api.BufferEditAPI.VirtualCursor;
pub const MultiCursorEdit = buffer_edit_api.BufferEditAPI.MultiCursorEdit;
pub const OperatorType = operator_repeat_api.OperatorRepeatAPI.OperatorType;
pub const BufferEventType = buffer_events_api.BufferEventsAPI.BufferEventType;
pub const HighlightGroup = highlight_theme_api.HighlightThemeAPI.HighlightGroup;
pub const Theme = highlight_theme_api.HighlightThemeAPI.Theme;

pub fn defaultAllocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

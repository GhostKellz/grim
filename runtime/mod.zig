const std = @import("std");
pub const plugin_api = @import("plugin_api.zig");
pub const plugin_manager = @import("plugin_manager.zig");
pub const plugin_manifest = @import("plugin_manifest.zig");
pub const plugin_discovery = @import("plugin_discovery.zig");
pub const plugin_loader = @import("plugin_loader.zig");
pub const native_plugin = @import("native_plugin.zig");
pub const plugin_cache = @import("plugin_cache.zig");
pub const example_plugin = @import("example_plugin.zig");

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

pub fn defaultAllocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

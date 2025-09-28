const std = @import("std");
pub const plugin_api = @import("plugin_api.zig");
pub const plugin_manager = @import("plugin_manager.zig");
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
pub const PluginManifest = plugin_manager.PluginManager.PluginManifest;
pub const PluginInfo = plugin_manager.PluginManager.PluginInfo;

pub fn defaultAllocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

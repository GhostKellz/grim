const std = @import("std");
const zap_lib = @import("zap"); // Import real zap library

/// Re-export zap's core types for Grim's use
pub const ZapContext = zap_lib.ZapContext;
pub const OllamaConfig = zap_lib.ollama.OllamaConfig;

/// Grim-specific wrapper around zap
pub const ZapIntegration = struct {
    zap_ctx: ZapContext,
    allocator: std.mem.Allocator,
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) !ZapIntegration {
        return ZapIntegration{
            .allocator = allocator,
            .zap_ctx = try ZapContext.init(allocator),
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: OllamaConfig) !ZapIntegration {
        return ZapIntegration{
            .allocator = allocator,
            .zap_ctx = try ZapContext.initWithConfig(allocator, config),
        };
    }

    pub fn deinit(self: *ZapIntegration) void {
        self.zap_ctx.deinit();
    }

    pub fn generateCommitMessage(self: *ZapIntegration, diff: []const u8) ![]const u8 {
        return try self.zap_ctx.generateCommit(diff);
    }

    pub fn explainChanges(self: *ZapIntegration, commit_range: []const u8) ![]const u8 {
        return try self.zap_ctx.explainChanges(commit_range);
    }

    pub fn suggestMergeResolution(self: *ZapIntegration, conflict: []const u8) ![]const u8 {
        return try self.zap_ctx.suggestMergeResolution(conflict);
    }

    pub fn isAvailable(self: *ZapIntegration) bool {
        return self.zap_ctx.isAvailable() catch false;
    }

    pub fn reviewCode(self: *ZapIntegration, code: []const u8) ![]const u8 {
        return try self.zap_ctx.reviewCode(code);
    }

    pub fn generateDocs(self: *ZapIntegration, code: []const u8) ![]const u8 {
        return try self.zap_ctx.generateDocs(code);
    }

    pub fn suggestNames(self: *ZapIntegration, code: []const u8) ![]const u8 {
        return try self.zap_ctx.suggestNames(code);
    }

    pub fn detectIssues(self: *ZapIntegration, code: []const u8) ![]const u8 {
        return try self.zap_ctx.detectIssues(code);
    }
};

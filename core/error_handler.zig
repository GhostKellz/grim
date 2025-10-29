//! Centralized error handling and user-friendly error messages

const std = @import("std");

pub const ErrorContext = struct {
    operation: []const u8,
    file_path: ?[]const u8 = null,
    details: ?[]const u8 = null,
};

/// Convert system errors to user-friendly messages
pub fn formatError(allocator: std.mem.Allocator, err: anyerror, context: ErrorContext) ![]const u8 {
    const base_message = getUserMessage(err);

    var message = std.ArrayList(u8){};
    defer message.deinit(allocator);

    try message.appendSlice(allocator, context.operation);
    try message.appendSlice(allocator, " failed: ");
    try message.appendSlice(allocator, base_message);

    if (context.file_path) |path| {
        try message.appendSlice(allocator, "\nFile: ");
        try message.appendSlice(allocator, path);
    }

    if (context.details) |details| {
        try message.appendSlice(allocator, "\nDetails: ");
        try message.appendSlice(allocator, details);
    }

    return message.toOwnedSlice(allocator);
}

/// Get user-friendly error message
pub fn getUserMessage(err: anyerror) []const u8 {
    return switch (err) {
        // File system errors
        error.FileNotFound => "File not found",
        error.AccessDenied => "Permission denied",
        error.IsDir => "Expected file, found directory",
        error.NotDir => "Expected directory, found file",
        error.PathAlreadyExists => "Path already exists",
        error.FileTooBig => "File too large to open",
        error.NoSpaceLeft => "No space left on device",
        error.DeviceBusy => "Device busy",
        error.FileBusy => "File is in use",
        error.NameTooLong => "File name too long",
        error.InvalidUtf8 => "Invalid UTF-8 encoding",
        error.DiskQuota => "Disk quota exceeded",

        // Memory errors
        error.OutOfMemory => "Out of memory",

        // Network errors
        error.ConnectionRefused => "Connection refused",
        error.ConnectionResetByPeer => "Connection reset",
        error.ConnectionTimedOut => "Connection timed out",
        error.NetworkUnreachable => "Network unreachable",
        error.BrokenPipe => "Connection broken",

        // LSP specific
        error.LspServerDied => "Language server stopped responding",
        error.InvalidJson => "Invalid JSON response from server",
        error.UnexpectedResponse => "Unexpected server response",
        error.RequestTimeout => "Request timed out",
        error.ServerNotInitialized => "Language server not initialized",

        // Parsing errors
        error.InvalidCharacter => "Invalid character in input",
        error.UnexpectedToken => "Unexpected token",
        error.InvalidSyntax => "Invalid syntax",

        // Generic fallback
        else => @errorName(err),
    };
}

/// Log error with context
pub fn logError(err: anyerror, context: ErrorContext) void {
    std.log.err("{s} failed: {s}", .{ context.operation, getUserMessage(err) });
    if (context.file_path) |path| {
        std.log.err("  File: {s}", .{path});
    }
    if (context.details) |details| {
        std.log.err("  Details: {s}", .{details});
    }
}

/// Graceful error handling with fallback
pub fn handleWithFallback(
    comptime T: type,
    result: anyerror!T,
    fallback: T,
    context: ErrorContext,
) T {
    return result catch |err| {
        logError(err, context);
        return fallback;
    };
}

test "formatError basic" {
    const allocator = std.testing.allocator;

    const message = try formatError(allocator, error.FileNotFound, .{
        .operation = "Open file",
        .file_path = "/test/file.txt",
    });
    defer allocator.free(message);

    try std.testing.expect(std.mem.indexOf(u8, message, "File not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "/test/file.txt") != null);
}

test "getUserMessage" {
    try std.testing.expectEqualStrings("File not found", getUserMessage(error.FileNotFound));
    try std.testing.expectEqualStrings("Out of memory", getUserMessage(error.OutOfMemory));
}

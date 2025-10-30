# Session Management

Grim provides automatic session management to preserve your workspace across editor restarts.

## Overview

Sessions save and restore:

- Open buffers and their file paths
- Cursor positions in each buffer
- Scroll offsets
- Window splits and layouts (if enabled)
- Modified buffer states

## Features

### Auto-Save Sessions

The editor automatically saves your workspace state at regular intervals.

**Default Behavior**:
- Auto-save enabled by default
- Saves every 30 seconds
- Session stored in `~/.config/grim/sessions/auto_save.json`

### Manual Sessions

Save and load named sessions for different projects or workflows.

```vim
:SessionSave my_project       " Save current workspace as 'my_project'
:SessionLoad my_project       " Load 'my_project' workspace
:SessionDelete my_project     " Delete 'my_project' session
:SessionList                  " List all saved sessions
```

### Session Restoration

On startup, Grim can automatically restore your last session:

```json
{
  "session": {
    "restore_on_startup": true,
    "save_window_layout": true
  }
}
```

## Configuration

### Basic Configuration

In `~/.config/grim/config.json`:

```json
{
  "editor": {
    "auto_save": true,
    "auto_save_interval_ms": 30000
  },
  "session": {
    "restore_on_startup": true,
    "save_window_layout": true,
    "session_directory": "~/.config/grim/sessions"
  }
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `auto_save` | boolean | `true` | Enable automatic session saving |
| `auto_save_interval_ms` | number | `30000` | Auto-save interval in milliseconds |
| `restore_on_startup` | boolean | `true` | Restore last session on startup |
| `save_window_layout` | boolean | `true` | Include window splits in session |
| `session_directory` | string | `~/.config/grim/sessions` | Where to store sessions |

## Session File Format

Sessions are stored as JSON files:

```json
{
  "name": "my_project",
  "buffers": [
    {
      "id": 0,
      "file_path": "/home/user/project/main.zig",
      "cursor_line": 142,
      "cursor_column": 23,
      "scroll_offset": 120,
      "modified": false
    },
    {
      "id": 1,
      "file_path": "/home/user/project/config.zig",
      "cursor_line": 45,
      "cursor_column": 8,
      "scroll_offset": 30,
      "modified": true
    }
  ],
  "active_buffer_id": 0,
  "created_at": 1704067200
}
```

## API

### AutoSaveSession

Location: `ui-tui/auto_save_session.zig`

```zig
pub const AutoSaveSession = struct {
    sessions: *BufferSessions,
    buffer_mgr: *BufferManager,
    auto_save_enabled: bool,
    auto_save_interval_ms: u64,
    last_save_time: i64,
    
    pub fn init(allocator, sessions, buffer_mgr) !*AutoSaveSession
    pub fn deinit(self: *AutoSaveSession) void
    pub fn enable(self: *AutoSaveSession, interval_ms: ?u64) void
    pub fn disable(self: *AutoSaveSession) void
    pub fn tick(self: *AutoSaveSession) !bool
    pub fn save(self: *AutoSaveSession) !void
    pub fn restore(self: *AutoSaveSession) !void
    pub fn hasAutoSave(self: *AutoSaveSession) bool
    pub fn timeSinceLastSave(self: *AutoSaveSession) i64
};
```

### BufferSessions

Location: `ui-tui/buffer_sessions.zig`

```zig
pub const BufferSessions = struct {
    pub fn init(allocator: std.mem.Allocator) !BufferSessions
    pub fn saveSession(name: []const u8, buffer_mgr) !void
    pub fn loadSession(name: []const u8, buffer_mgr) !void
    pub fn deleteSession(name: []const u8) !void
    pub fn listSessions() ![]const []const u8
    pub fn getSessionInfo(name: []const u8) !SessionInfo
};
```

## Usage Examples

### Programmatic Usage

```zig
// Initialize auto-save
const auto_save = try AutoSaveSession.init(
    allocator,
    sessions,
    buffer_mgr
);
defer auto_save.deinit();

// Enable with custom interval (60 seconds)
auto_save.enable(60_000);

// In main loop:
while (running) {
    // ... handle events ...
    
    // Tick auto-save (saves if interval elapsed)
    const saved = try auto_save.tick();
    if (saved) {
        std.log.info("Workspace auto-saved", .{});
    }
}

// On startup:
if (config.session.restore_on_startup) {
    if (auto_save.hasAutoSave()) {
        try auto_save.restore();
    }
}
```

### Command Line

```bash
# Start with session restoration
grim --restore-session

# Start with specific session
grim --session my_project

# Disable auto-save for this session
grim --no-auto-save
```

## Workflow Examples

### Project-Based Workflow

```vim
" Save session for each project
:SessionSave grim_editor
:SessionSave web_server
:SessionSave game_engine

" Switch between projects
:SessionLoad grim_editor
:SessionLoad web_server
```

### Task-Based Workflow

```vim
" Save state for different tasks
:SessionSave feature_auth
:SessionSave bugfix_memory_leak
:SessionSave refactor_parser

" Resume specific task
:SessionLoad bugfix_memory_leak
```

## Implementation Details

### Auto-Save Timing

The auto-save system uses millisecond timestamps to track intervals:

```zig
pub fn tick(self: *AutoSaveSession) !bool {
    if (!self.auto_save_enabled) return false;
    
    const now = std.time.milliTimestamp();
    const elapsed = now - self.last_save_time;
    
    if (elapsed >= self.auto_save_interval_ms) {
        try self.save();
        return true;  // Saved
    }
    
    return false;  // Not yet time to save
}
```

### Session Serialization

Sessions are serialized using Zig's built-in JSON support:

```zig
fn serializeSession(session: *const Session) ![]const u8 {
    var string = std.ArrayList(u8){};
    try std.json.stringify(session, .{}, string.writer());
    return string.toOwnedSlice(allocator);
}
```

### Directory Structure

```
~/.config/grim/sessions/
├── auto_save.json          # Automatic session
├── my_project.json         # Named session
├── web_server.json         # Named session
└── game_engine.json        # Named session
```

## Troubleshooting

### Session Not Restoring

**Issue**: Workspace not restored on startup

**Solutions**:
1. Check `restore_on_startup = true` in config
2. Verify session file exists: `ls ~/.config/grim/sessions/auto_save.json`
3. Check file permissions: `chmod 644 ~/.config/grim/sessions/*.json`

### Auto-Save Not Working

**Issue**: Session not saving automatically

**Solutions**:
1. Verify `auto_save = true` in config
2. Check editor log for errors: `tail -f ~/.local/state/grim/editor.log`
3. Ensure sufficient disk space: `df -h ~/.config`

### Session File Corrupted

**Issue**: Error loading session: "Invalid JSON"

**Solutions**:
1. Backup the corrupted file: `cp ~/.config/grim/sessions/auto_save.json ~/backup.json`
2. Delete and restart: `rm ~/.config/grim/sessions/auto_save.json`
3. Session will be recreated on next save

### Lost Unsaved Changes

**Issue**: Modified buffers not marked as modified after restore

**Note**: This is expected behavior. Session management saves buffer states, not unsaved changes. Use auto-save file feature (`:set auto_save_file`) to preserve unsaved changes.

## Best Practices

1. **Use Named Sessions for Projects**: Create a session per project for quick context switching
2. **Enable Auto-Save**: Keep `auto_save = true` to prevent data loss
3. **Reasonable Intervals**: 30-60 seconds is a good balance between safety and performance
4. **Regular Cleanup**: Periodically delete old sessions: `:SessionDelete old_project`
5. **Backup Important Sessions**: Copy session files before major changes

## See Also

- [Configuration Reference](configuration.md)
- [Commands](commands.md)
- [Workspace Management](workspace.md)

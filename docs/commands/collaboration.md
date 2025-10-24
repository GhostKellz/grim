# Collaboration Commands Reference

Real-time collaborative editing commands for Grim.

## Overview

Grim supports real-time collaborative editing using:
- **WebSocket** - Low-latency bidirectional communication
- **Operational Transform (OT)** - Conflict resolution algorithm
- **User Presence** - See collaborator cursors and selections

## Commands

### `:collab start [port]`

Start a collaboration server.

**Usage:**
```vim
:collab start           " Start server on port 8080 (default)
:collab start 9000      " Start server on port 9000
```

**Behavior:**
- Binds to `0.0.0.0:<port>` (accepts connections from network)
- Generates session URL: `ws://localhost:<port>`
- Shows session info in status line
- Current buffer becomes shared

**Example:**
```vim
:collab start 8080

" Status line shows: 🤝 Session started on :8080
```

**Share URL with collaborators:**
```
ws://your-ip:8080
```

---

### `:collab join <url>`

Join an existing collaboration session.

**Usage:**
```vim
:collab join ws://192.168.1.100:8080
:collab join ws://localhost:8080
```

**Behavior:**
- Connects to remote session
- Downloads current buffer state
- Sends user presence (cursor, selection)
- Enables real-time sync

**Example:**
```vim
:collab join ws://192.168.1.50:8080

" Status line shows: 🤝 Connected to 192.168.1.50:8080
" Your cursor appears colored to other users
```

---

### `:collab stop`

Stop collaboration (disconnect or shutdown server).

**Usage:**
```vim
:collab stop
```

**Behavior:**
- If server: Closes server, disconnects all clients
- If client: Disconnects from session, keeps local buffer
- Removes presence indicators

**Example:**
```vim
:collab stop

" Status line clears collaboration info
```

---

### `:collab users`

Show connected users.

**Usage:**
```vim
:collab users
```

**Example Output:**
```
# Collaboration Session

**Connected Users:** 3

1. You (localhost) - Line 42, Col 10
2. alice@192.168.1.50 - Line 15, Col 5
3. bob@192.168.1.51 - Line 100, Col 0

**Session:** ws://localhost:8080
**Uptime:** 15 minutes
```

---

## User Presence

### Remote Cursors

When in a collaboration session, you'll see other users' cursors as **colored blocks** (█):

**Colors:**
- 🟥 Red
- 🟩 Green
- 🟨 Yellow
- 🟦 Blue
- 🟪 Magenta
- 🟦 Cyan

**Example:**
```zig
fn main() !void {
    const x = 42;█  ← alice (red cursor)
    const y = x █2; ← bob (green cursor)
    return;
}
   ↑ Your cursor (normal)
```

---

### Status Line Indicator

When collaborating, status line shows:

**Server:**
```
🤝 3 users | Session :8080
```

**Client:**
```
🤝 Connected to 192.168.1.50:8080
```

---

## Operational Transform (OT)

Grim uses OT to resolve conflicts when multiple users edit simultaneously.

### How It Works

1. **Local Edit** - You type text
2. **Send Operation** - Your change is sent to server
3. **Transform** - Server transforms your op against concurrent ops
4. **Broadcast** - Transformed op sent to other users
5. **Apply** - Other users apply your change

**Example Scenario:**

```
Initial: "Hello"

User A: Insert " World" at position 5 → "Hello World"
User B: Insert "!" at position 5 → "Hello!"

OT Resolution: "Hello World!"
```

**Without OT:** Conflicts, data loss, cursor drift

**With OT:** Smooth, conflict-free collaboration

---

## Network Requirements

### Firewall

Ensure collaboration port is open:

```bash
# Allow port 8080 (or your chosen port)
sudo ufw allow 8080/tcp
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
```

---

### NAT / Router

If collaborators are on different networks:
1. **Port forward** on router (port 8080 → your machine)
2. Use **public IP** when sharing URL
3. Or use **ngrok** for tunneling:

```bash
ngrok tcp 8080
# Share the ngrok URL: ws://0.tcp.ngrok.io:12345
```

---

## Security Considerations

⚠️ **Current Version:** No authentication or encryption

**Recommendations:**
1. Use on trusted networks only
2. Use SSH tunneling for remote sessions:
   ```bash
   ssh -L 8080:localhost:8080 user@remote-machine
   ```
3. Or use VPN (WireGuard, Tailscale)

**Future:** Session passwords, TLS/WSS support

---

## Troubleshooting

### Cannot Connect

**Issue:** `:collab join` fails to connect

**Solutions:**
1. Verify server is running: `:collab users` (on server)
2. Check firewall allows port
3. Ping server: `ping <server-ip>`
4. Try localhost first: `ws://localhost:8080`

---

### Cursor Drift

**Issue:** Collaborator cursors appear in wrong position

**Solutions:**
1. Ensure all users on same Grim version
2. Check for OT algorithm bugs (report issue)
3. Disconnect and reconnect: `:collab stop`, `:collab join ...`

---

### High Latency

**Issue:** Edits take >1 second to appear

**Solutions:**
1. Check network latency: `ping <server-ip>`
2. Reduce buffer size if possible
3. Use faster network (WiFi → Ethernet)
4. Collaborate on same LAN if possible

---

## Use Cases

### Pair Programming

```vim
" Developer 1 (driver)
:collab start

" Developer 2 (navigator)
:collab join ws://192.168.1.100:8080
```

**Workflow:**
- Driver types code
- Navigator reviews, suggests changes
- Both can edit simultaneously

---

### Code Review

```vim
" Reviewer
:collab start
:e feature-branch.zig

" Author
:collab join ws://reviewer-ip:8080
```

**Workflow:**
- Reviewer navigates to issue
- Author explains code
- Real-time discussion via comments

---

### Teaching / Tutoring

```vim
" Instructor
:collab start
:e lesson.zig

" Students
:collab join ws://instructor-ip:8080
```

**Workflow:**
- Instructor types example code
- Students follow along in real-time
- Students ask questions via edits/comments

---

## Architecture

```
┌─────────────────────────────────────┐
│ Grim Instance 1 (Server)            │
│  :collab start 8080                 │
│  WebSocket Server (0.0.0.0:8080)   │
└──────────────┬──────────────────────┘
               │
       ┌───────┴──────┐
       │              │
       ▼              ▼
┌─────────────┐  ┌─────────────┐
│ Grim 2      │  │ Grim 3      │
│ (Client)    │  │ (Client)    │
│ :collab join│  │ :collab join│
└─────────────┘  └─────────────┘
```

**Message Flow:**
1. Client sends `operation` (insert/delete)
2. Server transforms via OT
3. Server broadcasts to all clients
4. Clients apply operation

---

## Configuration

`~/.config/grim/collab.toml`:

```toml
[collaboration]
default_port = 8080
max_users = 10
timeout_seconds = 30
enable_presence = true
cursor_colors = ["red", "green", "yellow", "blue", "magenta", "cyan"]

[network]
bind_address = "0.0.0.0"  # Or "127.0.0.1" for localhost-only
enable_ipv6 = true

[security]
require_password = false
password = ""
enable_tls = false
cert_file = ""
key_file = ""
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `:collab start [port]` | Start server (default: 8080) |
| `:collab join <url>` | Join session |
| `:collab stop` | Disconnect/shutdown |
| `:collab users` | Show connected users |

**Status Indicators:**
- `🤝 N users` - Active collaboration
- Colored cursors (█) - Remote user positions

---

## See Also

- [Commands Reference](README.md)
- [Network Setup](../network-setup.md)
- [WebSocket Protocol](../protocols/websocket.md)
- [Operational Transform](../algorithms/ot.md)

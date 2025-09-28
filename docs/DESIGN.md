# Grim Subsystem Notes (v0.1 scaffolding)

This document tracks the initial subsystems that anchor the Grim editor MVP. Each module lives in the top-level directory noted below and is re-exported through `src/root.zig` for downstream consumers.

## `core/rope.zig`
- Arena-backed rope buffer with persistent snapshots.
- Public API keeps allocator ownership with the caller; snapshots reuse arena allocations to avoid copy storms.
- Exposes `insert`, `delete`, and zero-copy `slice` when the requested range aligns with a leaf.
- Unit tests cover happy-path editing, deletion, and snapshot restore semantics.

### Invariants
- `length` always tracks logical buffer length in bytes.
- `pieces` array holds immutable leaf slices allocated from the arena.
- `ensureCut` splits leaves only when necessary; ranges outside `[0, length]` return `error.OutOfBounds`.

## `ui-tui/app.zig`
- Modal input skeleton supporting Normal and Insert modes.
- Dispatch table maps `h`, `j`, `k`, `l`, `i`, and `<Esc>` into motion/command enums.
- Insert mode records UTF-8 graphemes into a growable buffer for follow-up integration with the rope.
- Tests verify movement semantics, mode transitions, and UTF-8 capture.

### Next steps
- Wire motions into the rope buffer once window/render plumbing exists.
- Layer repeat counts and operator-pending states on top of the current command dispatcher.

## `host/ghostlang.zig`
- Prepares an arena-scoped Ghostlang runtime environment.
- `loadConfig` reads `~/.config/grim/init.gza` (or provided directory) with a 16 MiB guard.
- `callSetup` asserts `fn setup` (or `pub fn setup`) exists before marking the runtime as initialized.
- Unit tests mock on-disk configs and ensure error coverage.

### Extension hooks
- Future work: embed the Ghostlang VM, expose `editor.command`/`editor.keymap`, and sandbox I/O through capability objects.

## `lsp/client.zig`
- JSON-RPC 2.0 framing with explicit `Content-Length` parsing.
- `sendInitialize` emits the handshake payload and tracks the pending request id.
- `poll` reads a single message, dispatching initializes and `textDocument/publishDiagnostics` notifications.
- Diagnostics log through an allocator-aware callback for statusline/UI consumption.
- Tests rely on a mock transport to assert framing and diagnostic fan-out.

### Planned enhancements
- Support for multiple outstanding requests (per-method queues).
- Cancellation tokens and idle timers.
- Streaming diagnostics into a shared store instead of fire-and-forget logging.

## Runtime helpers
- `runtime/mod.zig` exposes a placeholder `defaultAllocator` helper, standing in for the future allocation strategy (bump-per-frame, arena-per-buffer).

---
This scaffold establishes the contracts that subsequent UI, rendering, and plugin work will build upon. When extending these modules, favor explicit allocators, total error propagation, and deterministic tests.

# GRIM Wishlist – Runtime Support Needs

_Last updated: 2025-10-09_

This note captures the upstream capabilities Phantom.grim needs from the Grim
runtime to keep shipping the Phase 2 polish and Phase 3 plugin roadmap. Each
entry describes the feature, why we need it, the consumer module, and any
workarounds in place today.

| Capability | Why we need it | Consumers | Current workaround | Priority |
|------------|----------------|-----------|--------------------|----------|
| **Structured buffer edit API** (range replace, text object helpers, virtual cursors) | Power `editor.autopairs`, `editor.surround`, and rich comment toggles without manual byte math. | `plugins/editor/{comment,autopairs,surround}.gza` | Scratch adapter that copies buffer lines into Ghostlang and re-writes via bridge. Fails on multi-byte + large files. | P0 |
| **Operator-pending + dot-repeat hooks** | Align user workflows with LazyVim (repeat last surround/comment) and ensure keymaps behave predictably. | `phantom.lazy` descriptor replay, comment/surround modules. | Manual state tracking per plugin; no global repeat integration. | P0 |
| **Command/key replay API** (`phantom.exec_command`, `phantom.feedkeys`) | Allow lazy loader to immediately re-run commands and key sequences that triggered the plugin, removing rerun prompts. | `plugins/core/plugin-manager.gza` | We log pending actions and ask the user to rerun manually. | P0 |
| **Buffer change events** (`BufTextChanged`, `InsertLeavePre`, etc.) with payloads | Needed for autopairs/surround undo safety and telemetry on text manipulation. | Phase 3 ergonomics plugins, health reporter. | Polling via timers; no payload data. | P1 |
| **Highlight group API + theme bridge** | Render indent guides and colorizer overlays with stable IDs. | `plugins/editor/{indent-guides,colorizer}.gza`, theme system. | Placeholder ANSI styling, no per-scope highlights. | P1 |
| **Ghostlang regression harness** (headless buffer + command runner) | Run comment/autopairs/surround regression suites and future plugin tests. | `tests/` harness, CI. | Tests stubbed out; we rely on manual smoke tests. | P1 |
| **Telemetry sink** (structured events, wall-clock timings) | Extend health report with per-plugin load counts and timings; feed `:PhantomPlugins` dashboard. | `plugins/extras/health.gza`, observability milestone. | We store metrics in-memory; no exporter. | P2 |
| **LSP attach orchestration** (language client hooks, diagnostics stream) | Ship `plugins/editor/lsp.gza` with parity across Ghostls/ZLS/RA. | Phase 3 language tooling | Currently experimental in `ghostls`; no shared interface. | P2 |

## Suggested Sequencing

1. **Lock the buffer edit + command replay APIs** so Phase 3 ergonomics plugins
   can land with full functionality and without bespoke adapters.
2. Provide the **Ghostlang regression harness** in parallel so comment/autopairs
   suites can be written immediately after the APIs exist.
3. Follow up with **highlight and telemetry hooks** to unblock indent guides,
   colorizer, and the enhanced health report.
4. Deliver **LSP orchestration** helpers once the ergonomics plugins are stable;
   this lets us wire language servers without re-implementing clients per
   language.

## Tracking & Collaboration

- Open upstream issues in the Grim runtime for each P0/P1 item and link back
  here so we keep progress visible.
- Once a capability stabilizes, strike it out in the table and note the Grim
  commit that delivered it.
- Update `docs/lazyvim_parity_roadmap.md` after each unlock so downstream
  milestones stay in sync.

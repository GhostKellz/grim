
This checklist captures the remaining work Grim needs before merging `feature/ghostlang-gza-adapter` into `main`.

## Branch Logistics

- [ ] Rebase `feature/ghostlang-gza-adapter` onto the latest `main` from `github.com/ghostkellz/grim`.
- [ ] Confirm Grove submodule/path dependency points at the current Grove `main` (TypeScript grammar now bundled).
- [ ] Sync vendored Tree-sitter artifacts (`vendor/grammars/ghostlang`, TypeScript highlight fixtures) if the branch uses local copies.

## Editor Wiring

- [ ] Import `Grove.GhostlangUtilities` and initialize during Grim startup.
- [ ] Register `.gza`/`.ghost` extensions with Grim's buffer loader.
- [ ] Route document symbols, folding, and textobjects through Grove adapters for Ghostlang buffers.
- [ ] Ensure highlight classes map to Grim themes (Ghostlang + TypeScript).

## Validation Walkthrough

- [ ] Run through `archive/grim/branches/ghostlang-adapter/SMOKE.md` scenarios and record pass/fail.
- [ ] Validate `.gza` navigation, folding, textobject motions, and hover/definition lookups.
- [ ] Capture GIF or TUI screenshot evidence for the merge description.

## Performance & Telemetry

- [ ] Execute `zig build bench` inside Grove and record throughput numbers for the merge PR.
- [ ] Run `zig run src/tools/bench_compare.zig report` to generate the current performance report (attach summary to PR).
- [ ] Measure Grim incremental edit latency with the Grove TypeScript sample and ensure P50 < 5 ms (record raw data).

## Documentation & Follow-up

- [ ] Update Grim `README` / docs to note Ghostlang support and Grove dependency version.
- [ ] Add a short post-merge checklist entry back into Grove's `CODEX.md` Status Log.
- [ ] File follow-up issues for Markdown grammar adoption once Grove lands bundling.

---

Track completion with Grim maintainers; once all boxes are checked, the branch can merge to `main` with confidence.


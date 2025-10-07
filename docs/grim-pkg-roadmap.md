# grim-pkg CLI & Plugin Ecosystem Roadmap

## Goals

- Provide a first-party CLI for building, installing, publishing, and searching Phantom.grim plugins.
- Deliver deterministic installs with dependency resolution, version constraints, and lazy-loading triggers sourced from manifests.
- Ship a curated core plugin pack validated by automated regression tests.
- Polish the Phantom-grim bootstrap UX (themes, keybinding discovery, tutor, config validation) ahead of public release.

## CLI Surface

| Command | Description | Key Flags |
|---------|-------------|-----------|
| `grim-pkg build <path>` | Compile a `.gza` plugin (or workspace) into a distributable artifact. | `--out <dir>`, `--target <triple>`, `--release`, `--manifest <file>` |
| `grim-pkg install <plugin>` | Resolve dependencies, fetch artifacts from registry, install into `$GRIM_HOME/plugins`. | `--version`, `--registry <url>`, `--no-compile`, `--force` |
| `grim-pkg publish` | Package current plugin and upload manifest/artifact to registry. | `--registry`, `--token`, `--notes <file>`, `--dry-run` |
| `grim-pkg search <query>` | Query registry index by name, tags, or author. | `--registry`, `--limit`, `--json` |
| `grim-pkg info <plugin>` | Show manifest, versions, dependency tree. | `--registry`, `--version`, `--json` |
| `grim-pkg list` | List installed plugins with versions & enabled state. | `--json`, `--outdated` |
| `grim-pkg update [plugin]` | Update all or specific plugins, respecting semver ranges. | `--registry`, `--dry-run`, `--prerelease` |

### Execution Model

- CLI written in Zig, built as standalone executable via `build.zig`.
- Registry interactions use HTTP client from stdlib (`std.http`). Support custom registries via config file (`$GRIM_HOME/config/registry.toml`).
- Auth tokens read from environment or keychain file (`~/.config/grim/registry-credentials`).
- Artifact format: `.gza.tar.zst` (bytecode + resources) with `manifest.json` for quick install.

## Manifest Enhancements (`plugin.toml`)

New/updated fields to support dependency graph and lazy loading:

```toml
[plugin]
name = "file-tree"
version = "1.4.0"
author = "grim-team"
description = "Sidebar file explorer"
main = "init.gza"
license = "MIT"
min_grim_version = "0.6.0"

[config]
enable_on_startup = false
lazy_load = true
priority = 40

[lazy]
commands = ["FileTreeToggle"]
events = ["BufEnter"]
filetypes = ["zig", "ghostlang"]
keys = ["<leader>e"]

[dependencies]
requires = [
  { name = "runtime-ui", version = "^1.0.0" },
  { name = "gcode", version = ">=0.4" },
]
optional = [
  { name = "git-core", version = "^0.2", feature = "git_status" }
]
conflicts = [
  { name = "legacy-filetree" }
]

[distribution]
bundle = ["assets/**", "templates/**"]
debug_symbols = false
```

### Parsing Plan

- Replace ad-hoc parser with `std.json` reading of generated manifest JSON (`grim-pkg build` converts TOML → canonical JSON) to avoid TOML edge cases.
- Extend `PluginManifest` struct with:
  - `LazyLoadTriggers` (commands/events/filetypes/keys)
  - `Dependency` struct { name, version_constraint, feature? }
  - `FeatureFlags` map for enabling optional code paths.
- Add `manifest.validate()` enforcing required fields, semver compliance, and collision checks.

## Dependency Resolution Engine

1. Load manifest graph for requested plugin + dependencies from registry metadata.
2. Parse version constraints (SemVer) using `std.SemanticVersion` helper.
3. Build dependency DAG; detect cycles/conflicts.
4. Choose versions via backtracking resolver (similar to Cargo) with deterministic ordering.
5. Emit install plan (download/compile steps).
6. Persist lockfile `phantom-lock.json` with resolved versions, checksums, lazy triggers.

### Lazy-Load Integration

- `grim-pkg install` writes `lazy_triggers.gza` snippet consumed by runtime loader.
- Runtime plugin manager subscribes to events (commands, keymaps, filetypes) and requests load when trigger fires.
- Provide API `runtime.PluginManager.registerLazyPlugin(manifest: PluginManifest)` building dispatch table.

## First-Party Plugin Suite

Target set (initial):

| Plugin | Description | Lazy defaults |
|--------|-------------|---------------|
| `core/file-tree` | Sidebar navigator | Command `<leader>e`, Event `DirChanged` |
| `core/fuzzy` | FZF-style finder | Command `<leader>ff`, `BufEnter` |
| `core/git-signs` | Git gutter & blame | Event `BufReadPost` |
| `core/statusline` | Enhanced statusline | Enabled on startup |
| `core/which-key` | Key discovery overlay | Timeout `LeaderKey` |
| `core/autopairs` | Auto bracket/quotes | Insert mode hooks |

### Regression Tests

- Add `tests/plugin_smoke.zig` to spin up runtime, load each plugin under mocked filesystem, assert key bindings/commands register.
- Provide snapshot tests for lazy triggers (simulate command invocation, ensure plugin loads exactly once).
- Integrate into `zig build test` pipeline.

## UX Polish Milestone

### Bootstrap & Themes
- `grim init` prompts for profile (`core`, `phantom`).
- Default theme pack installed to `~/.config/grim/themes/`. Validate theme files via schema (color keys, contrast).
- Which-key overlay: implement `runtime/ui/which_key.zig`; expose `:WhichKey` command.

### Grim Tutor & Help
- Finalize lessons in `runtime/defaults/grim-tutor/` (Basics, Editing, Navigation, Plugins, Git).
- Add CLI `grim tutor` launching tutor mode.
- Add commands: `:Tutor`, `:Tutor <lesson>`, `:PhantomDocs` opening docs panel with search.

### Config Schema & Validation
- Define JSON schema for user config (`config.gza.json` compiled from definitions).
- Provide `grim validate-config` CLI subcommand and runtime checks with actionable errors (line numbers, suggestions).
- On startup, surface config issues in status bar + logs.

## Implementation Phasing

1. **Design & scaffolding** (current): finalize manifest structs, CLI API, registry contract.
2. **CLI core**: implement `grim-pkg` with build/install/search using local manifest/index; add tests.
3. **Registry integration**: add HTTP client, caching, auth; create local mock registry for tests.
4. **Runtime updates**: enhance plugin manager for lazy triggers + lockfile usage.
5. **Plugin suite**: port first-party plugins to new manifest, add regression tests.
6. **UX polish**: implement which-key overlay, tutor commands, config validation.
7. **Release prep**: docs, packaging, CI workflows, announce preview.

## Open Questions

- Registry hosting strategy (static CDN vs API server). For MVP, a static JSON index with signed artifacts is acceptable.
- Artifact signing format (Ed25519?); CLI should verify signatures when installing.
- Plugin sandboxing (allow native Zig plugins?). For now, Ghostlang `.gza` only.
- How to handle platform-specific assets (per-target builds?). Add `targets` array in manifest.

---

This roadmap splits work across tooling, runtime, and UX so the Phantom.grim experience matches the LazyVim-inspired vision while preserving Zig performance and deterministic installs.

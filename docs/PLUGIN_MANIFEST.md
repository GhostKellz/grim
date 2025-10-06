# Plugin Manifest Format (plugin.toml)

Complete reference for Grim plugin manifests.

---

## Basic Structure

```toml
[plugin]
name = "my-plugin"
version = "1.0.0"
author = "your-name"
description = "What this plugin does"
main = "init.gza"
license = "MIT"

[config]
enable_on_startup = true

[dependencies]
requires = ["fuzzy-finder"]

[optimize]
hot_functions = ["search"]
```

---

## Section: [plugin]

**Required** - Core plugin metadata

### Fields

#### name (required)
- **Type**: string
- **Description**: Unique plugin identifier (kebab-case)
- **Example**: `"hello-world"`, `"git-signs"`, `"telescope-grim"`

#### version (required)
- **Type**: string (semver)
- **Description**: Plugin version
- **Example**: `"1.0.0"`, `"2.1.3-beta"`

#### author (required)
- **Type**: string
- **Description**: Plugin author
- **Example**: `"your-name"`, `"Your Name <email@example.com>"`

#### description (required)
- **Type**: string
- **Description**: Short plugin description
- **Example**: `"Advanced fuzzy finder for Grim"`

#### main (required)
- **Type**: string (path)
- **Description**: Entry point script (relative to plugin dir)
- **Default**: `"init.gza"`
- **Example**: `"init.gza"`, `"src/main.gza"`

#### license (optional)
- **Type**: string
- **Description**: SPDX license identifier
- **Example**: `"MIT"`, `"Apache-2.0"`, `"GPL-3.0"`

#### homepage (optional)
- **Type**: string (URL)
- **Description**: Plugin homepage/repo
- **Example**: `"https://github.com/user/plugin"`

#### min_grim_version (optional)
- **Type**: string (semver)
- **Description**: Minimum Grim version required
- **Example**: `"0.1.0"`

---

## Section: [config]

**Optional** - Plugin configuration

### Fields

#### enable_on_startup (optional)
- **Type**: boolean
- **Default**: `true`
- **Description**: Load plugin on Grim startup
- **Example**: `false` (load manually with `:Plugin load`)

#### lazy_load (optional)
- **Type**: boolean
- **Default**: `false`
- **Description**: Load plugin on first use
- **Example**: `true` (don't load until command called)

#### load_after (optional)
- **Type**: array of strings
- **Description**: Load after these plugins
- **Example**: `["fuzzy-finder", "git"]`

#### priority (optional)
- **Type**: integer (0-100)
- **Default**: `50`
- **Description**: Load priority (higher = earlier)
- **Example**: `10` (load early), `90` (load late)

---

## Section: [dependencies]

**Optional** - Plugin dependencies

### Fields

#### requires (optional)
- **Type**: array of strings
- **Description**: Required plugins (must be installed)
- **Example**: `["fuzzy-finder", "git-signs"]`

#### optional (optional)
- **Type**: array of strings
- **Description**: Optional plugins (enhance if present)
- **Example**: `["lsp-support"]`

#### conflicts (optional)
- **Type**: array of strings
- **Description**: Conflicting plugins (cannot coexist)
- **Example**: `["old-status-line"]`

---

## Section: [optimize]

**Optional** - Performance optimization hints

### Fields

#### auto_optimize (optional)
- **Type**: boolean
- **Default**: `false`
- **Description**: Enable auto-optimization
- **Example**: `true` (Grim profiles and optimizes hot paths)

#### hot_functions (optional)
- **Type**: array of strings
- **Description**: Functions to JIT-compile to Zig
- **Example**: `["search", "parse_large_file"]`

#### compile_on_install (optional)
- **Type**: boolean
- **Default**: `false`
- **Description**: Pre-compile hot functions on install
- **Example**: `true`

#### profile_runtime (optional)
- **Type**: boolean
- **Default**: `false`
- **Description**: Profile plugin to detect hot paths
- **Example**: `true` (auto-detect optimization targets)

#### compile_threshold (optional)
- **Type**: string (duration)
- **Default**: `"1000ms"`
- **Description**: Compile functions exceeding this total time
- **Example**: `"500ms"`, `"2s"`

---

## Section: [update]

**Optional** - Update strategy (future feature)

### Fields

#### strategy (optional)
- **Type**: string enum
- **Values**: `"git"`, `"binary"`, `"smart"`
- **Default**: `"smart"`
- **Description**: Update method
- **Example**: `"smart"` (binary cache + git fallback)

#### git_url (optional)
- **Type**: string (URL)
- **Description**: Git repository URL
- **Example**: `"https://github.com/user/plugin.git"`

#### cache_url (optional)
- **Type**: string (URL template)
- **Description**: Binary cache URL pattern
- **Example**: `"https://plugins.grim.dev/{name}/{version}/{platform}"`

#### prefer_binary (optional)
- **Type**: boolean
- **Default**: `true`
- **Description**: Prefer pre-compiled binaries
- **Example**: `false` (always use source)

#### dev_mode (optional)
- **Type**: boolean or string (path)
- **Default**: `false`
- **Description**: Use local development version
- **Example**: `"~/Projects/my-plugin"` (symlink this path)

---

## Section: [native]

**Optional** - Native Zig extension (advanced)

### Fields

#### library (optional)
- **Type**: string (path)
- **Description**: Native library file (.so/.dll)
- **Example**: `"native/libplugin.so"`

#### functions (optional)
- **Type**: array of strings
- **Description**: Exported native functions
- **Example**: `["fast_search", "parse_buffer"]`

#### build_command (optional)
- **Type**: string
- **Description**: Command to build native extension
- **Example**: `"zig build-lib -dynamic native.zig"`

---

## Complete Example

```toml
# Advanced plugin with all features
[plugin]
name = "telescope-grim"
version = "2.0.0"
author = "Grim Community"
description = "Advanced fuzzy finder with live preview"
main = "init.gza"
license = "MIT"
homepage = "https://github.com/grim-plugins/telescope"
min_grim_version = "0.2.0"

[config]
enable_on_startup = true
lazy_load = false
load_after = ["fuzzy-finder"]
priority = 60

[dependencies]
requires = ["fuzzy-finder"]
optional = ["git-signs", "lsp-support"]

[optimize]
auto_optimize = true
hot_functions = ["fuzzy_match", "preview_file"]
compile_on_install = true
profile_runtime = true
compile_threshold = "500ms"

[update]
strategy = "smart"
git_url = "https://github.com/grim-plugins/telescope.git"
prefer_binary = true

[native]
library = "native/libtelescope.so"
functions = ["fast_fuzzy_match"]
build_command = "zig build-lib -dynamic -O ReleaseFast native/fuzzy.zig"

# Plugin-specific configuration
[telescope]
preview_window_size = 50
max_results = 100
live_preview = true
```

---

## Minimal Example

```toml
# Simple plugin (minimum required)
[plugin]
name = "hello-world"
version = "1.0.0"
author = "me"
description = "Hello world plugin"
main = "init.gza"
```

---

## Validation

Grim validates manifests on load. Common errors:

### Missing Required Fields
```
Error: plugin.toml missing required field 'name'
```

### Invalid Version
```
Error: Invalid version '1.0' (must be semver: '1.0.0')
```

### Dependency Not Found
```
Error: Required plugin 'fuzzy-finder' not installed
```

### Circular Dependencies
```
Error: Circular dependency: A → B → C → A
```

---

## Best Practices

### Versioning
- Use semantic versioning (semver)
- Bump major version for breaking changes
- Document breaking changes in plugin README

### Dependencies
- Minimize dependencies
- Use `optional` for enhancements
- Document what `optional` deps enable

### Optimization
- Start with `auto_optimize = true`
- Profile before manually marking hot functions
- Only use native extensions for CPU-intensive tasks

### Updates
- Provide `git_url` for open source plugins
- Consider binary cache for faster installs
- Use `dev_mode` during development

---

## Future Features

Coming soon:
- **Plugin registry** - Central plugin repository
- **Auto-updates** - Automatic plugin updates
- **Version pinning** - Lock to specific versions
- **Dependency resolution** - Smart dependency management
- **Binary signing** - Verify plugin authenticity

---

## See Also

- `PLUGIN_DEVELOPMENT.md` - How to write plugins
- `PLUGIN_API.md` - Available FFI functions
- `ROADMAP.md` - Plugin system roadmap

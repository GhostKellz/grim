# Grim Dependency Manager Design (.grim)

**Version:** 1.0
**Date:** October 19, 2025
**Status:** Design Proposal

---

## 🎯 Goal

Create a **modern, Zig-powered dependency manager** for Grim plugins (`.grim` packages) that provides:
- Zero-config installation
- Automatic dependency resolution
- Version management
- Built-in upgrades
- Native Zig compilation
- LazyVim/Kickstart-like simplicity

---

## 📦 Package Format

### Package Structure
```
my-plugin.grim/
├── plugin.zon           # Package manifest (Zig Object Notation)
├── init.gza             # Entry point (Ghostlang)
├── native/              # Optional native Zig code
│   └── bridge.zig
├── lua/                 # Optional Lua compatibility
│   └── plugin.lua
├── README.md
└── LICENSE
```

### plugin.zon Format
```zig
.{
    .name = "file-tree",
    .version = "0.2.0",
    .description = "Neo-tree-like file explorer",
    .author = "ghostkellz",
    .license = "MIT",

    // Dependencies
    .dependencies = .{
        .{ .name = "theme", .version = "^0.1.0" },
        .{ .name = "statusline", .version = "~0.2.0" },
    },

    // Native code compilation
    .native = .{
        .enabled = true,
        .entry = "native/bridge.zig",
        .output = "lib/filetree_native.so",
    },

    // Plugin metadata
    .category = "ui",
    .tags = .{ "file-explorer", "tree", "navigation" },

    // Compatibility
    .grim_version = ">=0.1.0",
    .ghostlang_version = ">=0.1.0",
}
```

---

## 🏗️ Architecture

### Components

#### 1. **GrimPkg CLI** (`grimpkg`)
Zig-based command-line tool for package management:

```bash
grimpkg install file-tree        # Install package
grimpkg update file-tree         # Update single package
grimpkg upgrade                  # Upgrade all packages
grimpkg remove file-tree         # Uninstall package
grimpkg list                     # List installed packages
grimpkg search tree              # Search registry
grimpkg info file-tree           # Show package info
```

#### 2. **Package Registry**
Centralized registry of .grim packages:

**Registry Structure:**
```
https://registry.grimedi.tor/
├── index.json           # Package index
├── packages/
│   ├── file-tree/
│   │   ├── 0.1.0.tar.gz
│   │   ├── 0.2.0.tar.gz
│   │   └── manifest.json
│   └── fuzzy-finder/
│       └── ...
└── api/
    ├── search
    ├── install
    └── stats
```

**index.json:**
```json
{
  "packages": [
    {
      "name": "file-tree",
      "versions": ["0.1.0", "0.2.0"],
      "latest": "0.2.0",
      "category": "ui",
      "downloads": 15234,
      "stars": 892
    }
  ]
}
```

#### 3. **Dependency Resolver**
Zig module for resolving package dependencies:

**Algorithm:**
1. Parse `plugin.zon` for dependencies
2. Fetch dependency tree from registry
3. Resolve version constraints (SemVer)
4. Detect conflicts
5. Generate install order (topological sort)
6. Download and cache packages

**Version Resolution:**
```zig
pub const VersionConstraint = union(enum) {
    exact: Version,       // "0.2.0"
    caret: Version,       // "^0.2.0" (>=0.2.0 <0.3.0)
    tilde: Version,       // "~0.2.0" (>=0.2.0 <0.2.1)
    gte: Version,         // ">=0.1.0"
    range: struct {       // ">=0.1.0 <0.3.0"
        min: Version,
        max: Version,
    },
};
```

#### 4. **Build System**
Integrated Zig build system for native plugins:

**Automatic Build:**
```zig
// grimpkg automatically runs:
zig build-lib native/bridge.zig \
    -dynamic \
    -lc \
    -O ReleaseFast \
    --name plugin_native
```

**Caching:**
- Build artifacts cached in `~/.cache/grim/packages/`
- Rebuild only when source changes (hash-based)
- Incremental compilation support

---

## 📂 Directory Structure

### User Directories
```
~/.local/share/grim/
├── packages/              # Installed packages
│   ├── file-tree@0.2.0/
│   ├── fuzzy-finder@0.3.1/
│   └── theme@0.1.5/
├── cache/                 # Package cache
│   ├── downloads/
│   └── builds/
└── state/
    ├── lock.json          # Dependency lock file
    └── installed.json     # Installed packages DB

~/.config/grim/
├── init.gza               # User config
├── plugins.gza            # Plugin configuration
└── packages.zon           # User-defined packages
```

### Lock File (lock.json)
```json
{
  "version": "1",
  "packages": {
    "file-tree": {
      "version": "0.2.0",
      "resolved": "https://registry.grimeditor.dev/file-tree-0.2.0.tar.gz",
      "integrity": "sha256-...",
      "dependencies": {
        "theme": "0.1.5",
        "statusline": "0.2.1"
      }
    }
  }
}
```

---

## 🔧 Implementation

### Core Modules

#### 1. **Package Manager (`src/package_manager.zig`)**
```zig
pub const PackageManager = struct {
    allocator: std.mem.Allocator,
    registry: Registry,
    cache_dir: []const u8,
    packages_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !PackageManager { }

    pub fn install(self: *PackageManager, name: []const u8, version: ?[]const u8) !void { }
    pub fn update(self: *PackageManager, name: []const u8) !void { }
    pub fn remove(self: *PackageManager, name: []const u8) !void { }
    pub fn list(self: *PackageManager) ![]PackageInfo { }
    pub fn upgrade(self: *PackageManager) !void { }
};
```

#### 2. **Registry Client (`src/registry.zig`)**
```zig
pub const Registry = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    http_client: std.http.Client,

    pub fn search(self: *Registry, query: []const u8) ![]PackageInfo { }
    pub fn getPackageInfo(self: *Registry, name: []const u8) !PackageInfo { }
    pub fn download(self: *Registry, name: []const u8, version: []const u8) ![]u8 { }
    pub fn getVersions(self: *Registry, name: []const u8) ![]Version { }
};
```

#### 3. **Dependency Resolver (`src/resolver.zig`)**
```zig
pub const DependencyResolver = struct {
    allocator: std.mem.Allocator,
    registry: *Registry,

    pub fn resolve(self: *DependencyResolver, package: []const u8, version: []const u8) !DependencyTree { }
    pub fn detectConflicts(self: *DependencyResolver, tree: DependencyTree) ![]Conflict { }
    pub fn getInstallOrder(self: *DependencyResolver, tree: DependencyTree) ![]Package { }
};

pub const DependencyTree = struct {
    root: Package,
    dependencies: std.StringHashMap(Package),
};
```

#### 4. **Build System (`src/builder.zig`)**
```zig
pub const Builder = struct {
    allocator: std.mem.Allocator,
    zig_exe: []const u8,
    cache_dir: []const u8,

    pub fn buildNative(self: *Builder, package_dir: []const u8, manifest: Manifest) !void { }
    pub fn clean(self: *Builder, package_name: []const u8) !void { }
    pub fn rebuild(self: *Builder, package_name: []const u8) !void { }
};
```

---

## 🚀 Usage Examples

### Installing Phantom.grim

**Traditional Way (Before):**
```bash
cd ~/.config/grim
git clone https://github.com/ghostkellz/phantom.grim .
./install.sh
```

**With GrimPkg (After):**
```bash
grimpkg install phantom
# Done! All 24 plugins installed and built automatically
```

### Creating packages.zon in User Config

**~/.config/grim/packages.zon:**
```zig
.{
    .packages = .{
        // UI Plugins
        "file-tree",
        "fuzzy-finder",
        "statusline",
        "theme",

        // LSP
        "lsp-config",

        // Git
        "git-signs",

        // AI
        "thanos",
    },

    // Optional: Pin versions
    .versions = .{
        .@"file-tree" = "0.2.0",
        .thanos = "^0.2.0",
    },
}
```

**Install Everything:**
```bash
grimpkg sync  # Install all packages from packages.zon
```

### Publishing a Package

```bash
# 1. Create plugin.zon
grimpkg init my-plugin

# 2. Develop plugin
# ...

# 3. Test locally
grimpkg install . --local

# 4. Publish to registry
grimpkg publish --tag v0.1.0
```

---

## 🔐 Security

### Package Verification
1. **SHA-256 checksums** for all downloads
2. **GPG signatures** on packages (optional)
3. **Sandboxed builds** (Zig's safety guarantees)
4. **Source verification** (GitHub releases only)

### Trust Model
- **Registry** is trusted (HTTPS)
- **Package authors** verified (GitHub OAuth)
- **Build process** deterministic (Zig guarantees)

---

## 📊 Performance

### Optimization Strategies

#### 1. **Parallel Downloads**
```zig
// Download multiple packages concurrently
var tasks: [10]std.Thread = undefined;
for (packages, 0..) |pkg, i| {
    tasks[i] = try std.Thread.spawn(.{}, downloadPackage, .{pkg});
}
for (tasks) |task| {
    task.join();
}
```

#### 2. **Incremental Builds**
- Hash-based change detection
- Only rebuild modified native code
- Cache build artifacts

#### 3. **Lazy Loading**
- Download packages on-demand
- Background updates
- Minimal startup overhead

---

## 🛠️ CLI Design

### Commands

#### `grimpkg install <package> [--version <ver>]`
Install a package and its dependencies.

**Options:**
- `--version, -v <version>` - Install specific version
- `--local` - Install from local directory
- `--dry-run` - Show what would be installed

**Example:**
```bash
grimpkg install file-tree --version 0.2.0
```

#### `grimpkg update <package>`
Update a single package to latest compatible version.

**Example:**
```bash
grimpkg update file-tree
```

#### `grimpkg upgrade`
Upgrade all packages to latest versions.

**Options:**
- `--patch` - Only patch updates
- `--minor` - Patch + minor updates
- `--major` - All updates (breaking changes)

**Example:**
```bash
grimpkg upgrade --minor
```

#### `grimpkg remove <package>`
Uninstall a package.

**Example:**
```bash
grimpkg remove old-plugin
```

#### `grimpkg list [--outdated]`
List installed packages.

**Options:**
- `--outdated` - Show only outdated packages
- `--tree` - Show dependency tree

**Example:**
```bash
grimpkg list --outdated
```

#### `grimpkg search <query>`
Search registry for packages.

**Example:**
```bash
grimpkg search file
```

#### `grimpkg sync`
Synchronize packages with `packages.zon`.

**Example:**
```bash
grimpkg sync  # Install/remove packages to match packages.zon
```

---

## 🌐 Registry API

### Endpoints

#### `GET /api/packages`
List all packages.

**Response:**
```json
{
  "packages": [
    {
      "name": "file-tree",
      "version": "0.2.0",
      "description": "File explorer",
      "author": "ghostkellz",
      "downloads": 15234
    }
  ]
}
```

#### `GET /api/packages/<name>`
Get package information.

**Response:**
```json
{
  "name": "file-tree",
  "versions": ["0.1.0", "0.2.0"],
  "latest": "0.2.0",
  "description": "...",
  "repository": "https://github.com/ghostkellz/file-tree.grim",
  "dependencies": {
    "theme": "^0.1.0"
  }
}
```

#### `GET /api/packages/<name>/<version>`
Download package tarball.

#### `POST /api/publish`
Publish new package version (requires auth).

---

## 📈 Migration Path

### Phase 1: Manual → Assisted
```bash
# User still uses install.sh, but grimpkg helps
grimpkg import  # Detect installed plugins, create packages.zon
```

### Phase 2: Hybrid
```bash
# Some plugins via grimpkg, some via git
grimpkg install file-tree
git clone custom-plugin ~/.local/share/grim/packages/custom
```

### Phase 3: Full GrimPkg
```bash
# Everything managed by grimpkg
grimpkg install phantom  # Installs entire Phantom.grim suite
```

---

## 🎯 Goals vs Other Ecosystems

| Feature | Grim/GrimPkg | Neovim/Lazy | VSCode |
|---------|--------------|-------------|--------|
| Native Zig compilation | ✅ | ❌ | ❌ |
| Zero-config | ✅ | ⚠️ (requires init.lua) | ✅ |
| Dependency resolution | ✅ | ⚠️ (manual) | ✅ |
| Version pinning | ✅ | ⚠️ (manual) | ✅ |
| Built-in upgrades | ✅ | ✅ | ✅ |
| Offline mode | ✅ | ⚠️ | ❌ |
| Rollback | ✅ (planned) | ⚠️ | ⚠️ |

---

## 🚧 Implementation Plan

### Week 3: Core Foundation
- [ ] Package manifest parser (plugin.zon)
- [ ] Version resolver (SemVer)
- [ ] Dependency tree builder

### Week 4: Registry & CLI
- [ ] Registry API implementation
- [ ] HTTP client for downloads
- [ ] CLI commands (install, list, remove)

### Week 5: Build System
- [ ] Zig build integration
- [ ] Native plugin compilation
- [ ] Build caching

### Week 6: Polish & Testing
- [ ] Upgrade command
- [ ] Conflict detection
- [ ] Integration tests

---

## 📝 Example: Full Flow

**User wants File Tree plugin:**

```bash
$ grimpkg install file-tree

[grimpkg] 🔍 Resolving dependencies...
[grimpkg] 📦 file-tree@0.2.0
[grimpkg]   ├── theme@0.1.5
[grimpkg]   └── statusline@0.2.1
[grimpkg]
[grimpkg] 📥 Downloading 3 packages...
[grimpkg] ✅ file-tree@0.2.0 downloaded
[grimpkg] ✅ theme@0.1.5 downloaded
[grimpkg] ✅ statusline@0.2.1 downloaded
[grimpkg]
[grimpkg] 🔨 Building native code...
[grimpkg] ✅ file-tree: compiled native/filetree.so
[grimpkg]
[grimpkg] ✅ Installed file-tree@0.2.0
[grimpkg]
[grimpkg] 💡 Restart Grim to load the new plugin:
[grimpkg]   grim
```

---

**Status:** Design ready for implementation! 🚀
**Next:** Create GrimPkg prototype in Zig

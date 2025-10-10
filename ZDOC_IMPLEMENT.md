# Integrating zdoc into grim

**zdoc** is a production-ready documentation generator for Zig projects. This guide shows how to integrate it into grim's build system.

## 🚀 Quick Start

### 1. Add zdoc as a dependency

```bash
zig fetch --save https://github.com/GhostKellz/zdoc/archive/refs/tags/v0.1.0.tar.gz
```

Or use the latest main branch:
```bash
zig fetch --save https://github.com/GhostKellz/zdoc/archive/refs/heads/main.tar.gz
```

This will update your `build.zig.zon` with the zdoc dependency.

### 2. Update build.zig

Add zdoc to your build.zig:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ... your existing build configuration ...

    // Add zdoc integration
    const zdoc_dep = b.dependency("zdoc", .{
        .target = target,
        .optimize = optimize,
    });

    const zdoc_exe = zdoc_dep.artifact("zdoc");

    // Create docs generation step
    const docs_step = b.step("docs", "Generate API documentation");

    const run_zdoc = b.addRunArtifact(zdoc_exe);
    run_zdoc.addArgs(&.{
        "--format=html",
        "src/root.zig",
        "src/main.zig",
        "src/ghostlang_bridge.zig",
        "docs/",
    });

    docs_step.dependOn(&run_zdoc.step);
}
```

### 3. Generate Documentation

```bash
zig build docs
```

This generates:
- `docs/index.html` - Multi-module index page
- `docs/[module]/index.html` - Module documentation
- `docs/[module]/search_index.json` - Symbol search indexes

## 📁 Generated Documentation Structure

```
docs/
├── index.html                    # Package manager overview
├── root/
│   ├── index.html                # Core library documentation
│   └── search_index.json
├── main/
│   ├── index.html                # CLI entry point
│   └── search_index.json
└── ghostlang_bridge/
    ├── index.html                # GhostLang integration
    └── search_index.json
```

## 🎨 Features for Package Manager Docs

### Perfect for CLI Tools
- ✅ **Command Documentation**: Document your CLI commands with full signatures
- ✅ **Configuration**: Document config file structures
- ✅ **API Documentation**: For library consumers
- ✅ **Integration Guides**: Link to existing docs (DESIGN.md, etc.)

### Enhanced Output
- ✅ **Visibility Badges**: `pub`, `export` indicators
- ✅ **Function Signatures**: Full type information
- ✅ **Error Handling**: Document all error cases
- ✅ **Return Values**: Clear return type documentation
- ✅ **GitHub Links**: Direct source code links

### Module Hierarchy
- ✅ **Index Page**: Professional gradient design
- ✅ **Statistics**: Function/type counts per module
- ✅ **Search**: Real-time module filtering
- ✅ **Mobile-Friendly**: Responsive design

## 📝 Documenting Package Manager Functions

Add comprehensive doc comments:

```zig
/// Install a package from the registry
///
/// This function downloads and installs the specified package,
/// resolving all dependencies recursively.
///
/// @param allocator Memory allocator for installation
/// @param package_name Name of the package to install
/// @param version Semantic version specifier (e.g., "^1.0.0")
/// @return Installation result with package metadata
/// @error NetworkError if download fails
/// @error InvalidPackage if package format is invalid
/// @error DependencyConflict if version resolution fails
/// @since grim v0.1.0
pub fn install(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    version: []const u8,
) !InstallResult {
    // ...
}
```

## 🔧 Advanced Usage

### Document Plugin System

If grim has a plugin system:

```zig
run_zdoc.addArgs(&.{
    "--format=html",
    "src/root.zig",
    "src/main.zig",
    "src/plugins/*.zig",  // Document all plugins
    "docs/",
});
```

### Multiple Output Formats

Generate multiple formats:

```zig
// HTML for web viewing
const html_docs = b.addRunArtifact(zdoc_exe);
html_docs.addArgs(&.{ "--format=html", "src/*.zig", "docs/html/" });

// JSON for tooling integration
const json_docs = b.addRunArtifact(zdoc_exe);
json_docs.addArgs(&.{ "--format=json", "src/*.zig", "docs/json/" });

docs_step.dependOn(&html_docs.step);
docs_step.dependOn(&json_docs.step);
```

### Link to Existing Documentation

Your generated docs can coexist with existing markdown docs:

```
docs/
├── index.html              # Generated: Module overview
├── DESIGN.md               # Existing: Architecture docs
├── PLUGIN_MANIFEST.md      # Existing: Plugin spec
├── phantom-architecture.md # Existing: Phantom integration
└── root/
    └── index.html          # Generated: API reference
```

## 📚 Package Manager Specific Tips

### Document Package Resolution

```zig
/// Resolve package dependencies using semantic versioning
///
/// Uses a constraint-based solver to find compatible versions.
///
/// @param packages List of packages to resolve
/// @return Dependency graph with resolved versions
/// @error NoSolutionFound if constraints are incompatible
pub fn resolveDependencies(...) !DependencyGraph {
    // ...
}
```

### Document Registry API

```zig
/// Fetch package metadata from the registry
///
/// @param package_name Package identifier
/// @return Package metadata including all versions
/// @error NetworkError if registry is unreachable
/// @error PackageNotFound if package doesn't exist
pub fn fetchMetadata(package_name: []const u8) !Metadata {
    // ...
}
```

### Document Lock File Format

```zig
/// Parse a grim.lock file
///
/// The lock file contains exact versions of all dependencies.
///
/// Format:
/// ```
/// [packages]
/// foo = "1.2.3"
/// bar = "2.0.1"
/// ```
///
/// @param content Lock file content
/// @return Parsed lock file structure
pub fn parseLockFile(content: []const u8) !LockFile {
    // ...
}
```

## 🌐 CI/CD Integration

### GitHub Actions

```yaml
name: Documentation

on: [push, pull_request]

jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.16.0

      - name: Generate Documentation
        run: zig build docs

      - name: Deploy to GitHub Pages
        if: github.ref == 'refs/heads/main'
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs
```

## 🎯 For grim Specifically

### Document Public API

Focus on what package consumers need:
- Package installation functions
- Configuration options
- Plugin interfaces
- Error types and handling

### Document CLI Commands

Even though CLI help text exists, API docs show the implementation:
- Command parsers
- Option validators
- Subcommand routing

### Document GhostLang Bridge

The bridge to GhostLang will be fully documented with:
- FFI interfaces
- Type conversions
- Memory management
- Error propagation

## 📖 Viewing Documentation

### Local Preview

```bash
zig build docs
cd docs
python -m http.server
# Open http://localhost:8000
```

### Production Deployment

Deploy to GitHub Pages, Netlify, or any static host.

## 🔗 Resources

- **zdoc Repository**: https://github.com/GhostKellz/zdoc
- **grim Repository**: Your repo URL
- **Generated Docs**: `docs/index.html`
- **Report Issues**: https://github.com/GhostKellz/zdoc/issues

---

**Happy documenting!** Your package manager now has professional API docs! 🎉

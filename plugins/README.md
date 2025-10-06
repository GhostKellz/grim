# Grim Plugins Directory

This directory contains user plugins for Grim.

## Plugin Structure

Each plugin lives in its own directory with a `plugin.toml` manifest:

```
plugins/
├── my-plugin/
│   ├── plugin.toml    # Required: Plugin manifest
│   ├── init.gza       # Required: Main entry point
│   └── lib/           # Optional: Additional modules
│       └── utils.gza
```

## Quick Start

### 1. Create a Plugin

```bash
mkdir -p ~/.config/grim/plugins/hello-world
cd ~/.config/grim/plugins/hello-world
```

### 2. Create `plugin.toml`

```toml
[plugin]
name = "hello-world"
version = "1.0.0"
author = "your-name"
description = "My first Grim plugin"
main = "init.gza"

[config]
enable_on_startup = true
```

### 3. Create `init.gza`

```ghostlang
-- Main plugin entry point
export fn setup() {
    grim.command("Hello", fn() {
        grim.notify("Hello from my plugin!")
    })
}

export fn teardown() {
    -- Cleanup if needed
}
```

### 4. Restart Grim

Your plugin loads automatically!

## Plugin Manifest Reference

See `PLUGIN_MANIFEST.md` for complete reference.

## Example Plugins

Built-in examples in `examples/` directory:
- `hello-world/` - Minimal plugin example
- `status-line/` - Status line customization
- `git-signs/` - Git integration example

## Plugin Development

See `docs/PLUGIN_DEVELOPMENT.md` for complete guide.

## Installing Community Plugins

```bash
grim plugin install telescope-grim
grim plugin update
grim plugin list
```

See `ROADMAP.md` for package manager details (coming soon).

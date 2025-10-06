
  fn my_handler() {
      // User logic here
      const result = grim.buffer.get_line(10)
      print(result)
  }

  Characteristics:
  - Interpreted Ghostlang
  - Hot reload
  - Easy to hack
  - Cross-platform automatically

  ---
  Tier 2: .toml Manifests (SECONDARY - Metadata)

  Describes the plugin

  [plugin]
  name = "my-plugin"
  version = "1.0.0"
  main = "init.gza"

  # INNOVATION: Performance hints!
  [optimize]
  # Grim can JIT-compile or pre-compile these functions
  hot_functions = ["search", "parse_large_file"]
  compile_on_install = true  # Pre-compile to Zig

  [update]
  # Our innovation vs LazyVim
  strategy = "smart"  # git + binary cache
  prefer_binary = true  # Use pre-compiled if available

  ---
  Tier 3: Pure Zig (BACKBONE - Performance Layer)

  The secret sauce!

  Use Case 1: System Plugins (Built into Grim)

  // Built-in plugins shipped with Grim
  // runtime/system_plugins/fuzzy.zig
  pub const FuzzyPlugin = struct {
      pub fn search(query: []const u8) ![]const SearchResult {
          // Native speed fuzzy search
      }
  };

  Use Case 2: JIT Compilation Target

  // Grim automatically generates this from hot .gza functions
  // .cache/grim/plugins/my-plugin/optimized.zig
  pub export fn my_handler_compiled() callconv(.C) void {
      // Generated from .gza for performance
  }

  Use Case 3: Native Extensions (Power Users)

  // Optional: User provides their own .zig for max speed
  // ~/.config/grim/plugins/my-plugin/native.zig
  pub export fn fast_search(query: [*:0]const u8) callconv(.C) Results {
      // Hand-tuned native code
  }

  ---
  🚀 INNOVATION: Smart Update System

  Problem with LazyVim/Vim:

  - Always git clone (slow)
  - Always rebuild (slower)
  - No binary caching
  - Version conflicts

  Grim's Solution: Git + Binary Cache Hybrid

  [update]
  strategy = "smart"

  # 1. Check binary cache first
  cache_url = "https://plugins.grim.dev/binaries/{name}/{version}/{platform}"

  # 2. Fall back to git if not cached
  git_url = "https://github.com/grim-plugins/my-plugin"

  # 3. Or use local dev mode
  dev_mode = false  # Uses ~/Projects/my-plugin directly

  Update Flow:

  grim plugin update my-plugin

  # Smart update:
  1. Check if binary available for your platform
     ✅ Found: my-plugin-v1.2.3-linux-x86_64.tar.gz
     → Download & extract (FAST! 2 seconds)

  2. Binary not found?
     → Git pull source
     → Auto-compile .gza hot functions to Zig
     → Cache binary for next time

  3. Dev mode?
     → Symlink to ~/Projects/my-plugin
     → Hot reload on file change

  Result: LazyVim-style convenience + Rust-style binary caching!

  ---
  🔧 Architecture: How They Intertwine

  ┌─────────────────────────────────────┐
  │     User writes .gza plugins        │
  │  (Ghostlang scripts, easy to hack)  │
  └──────────────┬──────────────────────┘
                 │
                 ▼
  ┌─────────────────────────────────────┐
  │    .toml Manifest with hints        │
  │  [optimize] hot_functions = [...]   │
  └──────────────┬──────────────────────┘
                 │
                 ▼
  ┌─────────────────────────────────────┐
  │    Grim's Plugin Manager            │
  │  - Loads .gza via Ghostlang runtime │
  │  - Checks [optimize] section        │
  │  - JIT compiles hot functions       │
  └──────────────┬──────────────────────┘
                 │
                 ├──→ Tier 1: Run .gza interpreted (default)
                 │
                 ├──→ Tier 2: Detect hot functions
                 │            Compile to Zig on-the-fly
                 │            Cache compiled binary
                 │
                 └──→ Tier 3: Use native .zig if provided
                              Maximum performance

  ---
  💡 Example: Search Plugin

  Tier 1: User's .gza Plugin

  -- plugins/smart-search/init.gza

  export fn setup() {
      grim.command("Search", search_command)
  }

  -- This function is HOT (called frequently)
  -- Marked in plugin.toml for optimization
  fn search_command() {
      const query = grim.ui.input("Search: ")
      const results = search_files(query)  // ← HOT PATH
      show_results(results)
  }

  fn search_files(query) {
      // Simple implementation
      // Grim will auto-optimize this!
      return grim.fuzzy.search(query)
  }

  Tier 2: Manifest Hints

  [plugin]
  name = "smart-search"
  main = "init.gza"

  [optimize]
  # Tell Grim which functions are hot
  hot_functions = ["search_files"]

  # Pre-compile on install
  compile_on_install = true

  # Use cached binary if available
  prefer_binary = true

  Tier 3: Grim Auto-Generates (or User Provides)

  // .cache/grim/plugins/smart-search/optimized.zig
  // Auto-generated from .gza OR user-provided

  pub export fn search_files_compiled(query: [*:0]const u8) callconv(.C) SearchResults {
      // Native speed implementation
      // Grim FFI handles the interface
  }

  Result: User writes simple .gza, Grim makes it fast automatically!

  ---
  🎯 Implementation Plan

  Week 1-2: Foundation (.gza + .toml)

  1. ✅ Plugin discovery (~/.config/grim/plugins/)
  2. ✅ Parse plugin.toml manifests
  3. ✅ Load .gza via Ghostlang runtime
  4. ✅ Basic lifecycle (setup/teardown)
  5. ✅ Command/keymap registration

  Week 3-4: Smart Updates

  1. ✅ Git clone for source plugins
  2. ✅ Binary cache system
  3. ✅ Platform detection
  4. ✅ Update command (grim plugin update)
  5. ✅ Dev mode (symlink support)

  Week 5-6: Zig Integration (The Backbone!)

  1. ✅ Load .so/.dll from plugins
  2. ✅ JIT compile hot functions
  3. ✅ Binary caching
  4. ✅ Detect [optimize] hints
  5. ✅ Auto-compile on install

  Week 7+: System Plugins

  1. ✅ Built-in Zig plugins
  2. ✅ Ship with Grim binary
  3. ✅ Expose via FFI to .gza plugins

  ---
  🚀 Directory Structure

  ~/.config/grim/
  ├── plugins/                    # User plugins
  │   ├── my-plugin/
  │   │   ├── plugin.toml        # Manifest
  │   │   ├── init.gza           # Primary script
  │   │   └── native.zig         # Optional: hand-tuned
  │   └── smart-search/
  │       ├── plugin.toml
  │       └── init.gza
  │
  ├── .cache/                     # Auto-generated
  │   ├── plugins/
  │   │   ├── my-plugin/
  │   │   │   └── optimized.so   # JIT compiled
  │   │   └── smart-search/
  │   │       └── optimized.so
  │   └── binaries/              # Downloaded pre-compiled
  │       └── my-plugin-v1.0.0-linux.tar.gz
  │
  └── plugins.lock               # Resolved versions (like Cargo.lock)

  ---
  🎨 Update Commands (Better than LazyVim!)

  # Update all plugins (smart mode)
  grim plugin update
  → Checks binary cache first
  → Downloads pre-compiled if available
  → Falls back to git + compile

  # Update specific plugin
  grim plugin update telescope

  # Force recompile (ignore cache)
  grim plugin update --rebuild telescope

  # Dev mode (live reload)
  grim plugin link ~/Projects/my-plugin
  → Symlinks for hot reload

  # Install from registry
  grim plugin install github:user/plugin
  → Checks binary cache
  → Downloads pre-compiled or source

  # Show what's compiled vs interpreted
  grim plugin status
  my-plugin        v1.0.0  [COMPILED] ⚡
  smart-search     v2.1.0  [INTERPRETED]
  telescope        v3.0.0  [NATIVE] 🚀

  ---
  🔥 The Killer Feature: Auto-Optimization

  # plugin.toml
  [optimize]
  # Simple flag enables magic!
  auto_optimize = true

  # Or be explicit
  hot_functions = ["search", "parse"]

  # Grim profiles during use
  profile_runtime = true  # Detect hot paths automatically

  # Compile strategy
  compile_threshold = "1000ms"  # Compile if >1s total runtime

  Grim watches your plugin usage and auto-compiles slow parts to Zig!

  ---
  ✅ Decision: Let's Build This!

  Architecture:
  - ✅ .gza = PRIMARY (user-facing, hackable)
  - ✅ .toml = SECONDARY (metadata, hints)
  - ✅ Zig = BACKBONE (performance, system plugins, JIT target)

  Innovation:
  - ✅ Smart updates (binary cache + git hybrid)
  - ✅ Auto-optimization (profile + JIT compile)
  - ✅ Dev mode (symlink for live reload)
  - ✅ Three tiers (interpreted → compiled → native)

  This beats LazyVim/Vim by:
  1. Faster updates (binary cache)
  2. Automatic performance (JIT compilation)
  3. Native speed available (Zig backbone)
  4. Easy to start (just .gza scripts)
  5. Dev-friendly (hot reload, symlinks)


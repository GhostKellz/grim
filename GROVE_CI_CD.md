# Grove CI/CD Strategy & Implementation

This document outlines the complete CI/CD strategy for Grove, the tree-sitter editor engine, and its integration with Grim.

---

## 🏗️ Architecture Overview

### **Repository Structure**
- **Grove**: Tree-sitter parsing engine with Ghostlang grammar support
- **Grim**: Text editor consuming Grove services for `.gza` file editing
- **Self-hosted runners**: Both projects use the same `nv-palladium` runner infrastructure

### **Integration Flow**
```
Grove (tree-sitter engine) → Grim (editor) → User workflows
     ↓                            ↓              ↓
CI tests grammar              CI tests editor   E2E testing
```

---

## 📋 Branch Strategy

### **Grove Branches**
- `main` - Stable Grove releases
- `feature/ghostlang-utilities` - Editor utilities development
- `feature/alpha-release` - Alpha phase preparation
- `develop` - Integration branch for Grove features

### **Grim Branches**
- `main` - Stable Grim releases
- `feature/ghostlang-gza-adapter` - Grove integration (following ADAPTER_GUIDE.md)

### **Cross-project Coordination**
- Grove changes trigger downstream Grim testing
- Grim adapter branch validates Grove utilities
- Automated dependency updates between projects

---

## 🚀 Grove CI/CD Workflows

### **1. Main CI Pipeline** (`.github/workflows/grove-ci.yml`)

```yaml
name: Grove CI
on:
  push: [main, develop]
  pull_request: [main]

jobs:
  test-core:
    runs-on: [self-hosted, nvidia, gpu, zig, palladium]
    steps:
      - Build Grove core
      - Test tree-sitter parsing
      - Test Ghostlang grammar
      - Run utility tests
```

### **2. Ghostlang Utilities** (`.github/workflows/ghostlang-tests.yml`)

```yaml
name: Ghostlang Utilities
on:
  push:
    paths: ['src/editor/**', 'vendor/grammars/ghostlang/**']

jobs:
  ghostlang-utilities:
    runs-on: [self-hosted, nvidia, gpu, zig, palladium]
    steps:
      - Test documentSymbols()
      - Test foldingRanges()
      - Test highlight()
      - Test textobjectAt()
      - Performance benchmarks
```

### **3. Cross-project Integration** (`.github/workflows/grim-integration.yml`)

```yaml
name: Grove → Grim Integration
on:
  push: [main]
  workflow_dispatch:

jobs:
  trigger-grim-tests:
    runs-on: [self-hosted, nvidia, gpu, zig, palladium]
    steps:
      - Trigger Grim's grove-integration workflow
      - Wait for Grim tests to complete
      - Report integration status
```

### **4. Release Pipeline** (`.github/workflows/grove-release.yml`)

```yaml
name: Grove Release
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: [self-hosted, nvidia, gpu, zig, palladium]
    steps:
      - Build release binaries
      - Run full test suite
      - Create GitHub release
      - Update Grim dependencies
```

---

## 🔄 Implementation Timeline

### **Phase 1: Grove Core CI**
- [x] Document strategy (this file)
- [ ] Create Grove CI workflows
- [ ] Set up self-hosted runner labels
- [ ] Test Grove core functionality

### **Phase 2: Ghostlang Integration**
- [ ] Test Ghostlang utilities specifically
- [ ] Validate editor service APIs
- [ ] Performance benchmarking
- [ ] Cross-project smoke tests

### **Phase 3: Grim Adapter Branch**
- [ ] Follow ADAPTER_GUIDE.md exactly
- [ ] Create `feature/ghostlang-gza-adapter` branch in Grim
- [ ] Implement Grove → Grim integration
- [ ] Run smoke tests with `.gza` files

### **Phase 4: Production Deployment**
- [ ] Automated releases
- [ ] Dependency management
- [ ] Documentation updates
- [ ] User workflow validation

---

## 🧪 Testing Strategy

### **Grove Unit Tests**
```bash
# Core parsing tests
zig build test --filter "tree-sitter"

# Ghostlang utilities tests
zig build test --filter "ghostlang utilities"

# Performance tests
zig build test --filter "performance"
```

### **Integration Tests**
```bash
# Grove → Grim end-to-end
./tools/test_grim_integration.sh

# .gza workflow validation
./tools/smoke_gza.sh examples/*.gza
```

### **Acceptance Criteria**
- ✅ Highlight parity with Grove grammar
- ✅ Document symbols load in <30ms/1k LOC
- ✅ Folding works for functions/blocks
- ✅ Textobjects select reliably
- ✅ No crashes; fallback tokenizer works

---

## 📊 Self-hosted Runner Configuration

### **Runner Labels**
Both Grove and Grim use: `[self-hosted, nvidia, gpu, zig, palladium]`

### **Runner Capabilities**
- **GPU support**: NVIDIA container toolkit
- **Zig nightly**: Latest Zig compiler
- **Build caching**: Persistent across jobs
- **Cross-project**: Shared between Grove/Grim

### **Resource Allocation**
- Grove: CPU-intensive parsing tests
- Grim: GUI/TUI integration tests
- Both: GPU-accelerated operations when needed

---

## 📦 Dependency Management

### **Grove Dependencies**
- Tree-sitter core
- Ghostlang grammar
- Zig build system
- Editor utilities

### **Grim Dependencies**
- Grove (via build.zig)
- Vendored queries (auto-updated)
- UI frameworks
- Configuration system

### **Update Strategy**
1. Grove releases trigger Grim dependency updates
2. Automated PRs for query/grammar changes
3. Version pinning for stability
4. Rollback procedures for failures

---

## 🚦 Deployment Flow

### **Development**
```
Grove feature → Grove CI → Grove merge → Trigger Grim tests → Integration OK
```

### **Release**
```
Grove tag → Release build → Update Grim deps → Grim adapter tests → User validation
```

### **Hotfix**
```
Grove fix → Fast-track CI → Emergency release → Grim hotfix → Deploy
```

---

## 📋 Action Items

### **Immediate (This Sprint)**
- [ ] Implement Grove CI workflows
- [ ] Set up Ghostlang utility testing
- [ ] Create Grim adapter branch
- [ ] Follow ADAPTER_GUIDE.md implementation

### **Next Sprint**
- [ ] Cross-project integration testing
- [ ] Performance optimization
- [ ] Release automation
- [ ] Documentation updates

### **Future**
- [ ] Multi-platform support
- [ ] Advanced caching strategies
- [ ] Telemetry and monitoring
- [ ] User feedback loops

---

## 🔗 Related Documents

- `ADAPTER_GUIDE.md` - Grim adapter implementation steps
- `ADAPTER_BRANCH.md` - Grim branch coordination
- `archive/workflow/` - Self-hosted runner setup
- `TODO.md` - Grove Alpha phase checklist

---

*This document serves as the single source of truth for Grove CI/CD strategy and coordinates with Grim's adapter implementation.*
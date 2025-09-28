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

## 🚀 Grim CI/CD Workflows

### **1. Main CI Pipeline** (`/.github/workflows/ci.yml`)
- Build and test on self-hosted runner with GPU support
- Zig build caching for faster builds
- Artifact archiving for releases

### **2. Grove Integration** (`/.github/workflows/grim-grove.yml`)
- Branch-specific testing for `feature/ghostlang-gza-adapter`
- Cross-project testing with Grove utilities
- Automated Grove query vendoring

### **3. Release Pipeline** (`/.github/workflows/main.yml`)
- Automated releases on version tags
- Uses self-hosted `nv-palladium` runner

---

## 📊 Self-hosted Runner Configuration

### **Runner Labels**
Both Grove and Grim use: `[self-hosted, nvidia, gpu, zig, palladium]`

### **Runner Capabilities**
- **GPU support**: NVIDIA container toolkit
- **Zig nightly**: Latest Zig compiler
- **Build caching**: Persistent across jobs
- **Cross-project**: Shared between Grove/Grim

### **Setup Reference**
See `archive/workflow/` for Docker configuration:
- `Dockerfile` - Ubuntu 24.04 with Zig nightly + NVIDIA toolkit
- `docker-compose.yml` - GPU-enabled container setup
- `entrypoint.sh` - GitHub Actions runner configuration

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

## 🔗 Related Documents

- `ADAPTER_GUIDE.md` - Grim adapter implementation steps
- `ADAPTER_BRANCH.md` - Grim branch coordination
- `archive/workflow/` - Self-hosted runner setup
- Feature branch: `feature/ghostlang-gza-adapter`

---

*This document serves as the single source of truth for Grove CI/CD strategy and coordinates with Grim's adapter implementation.*
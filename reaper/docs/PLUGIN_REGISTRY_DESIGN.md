# Grim Plugin Registry Design

**Version:** 1.0
**Date:** October 19, 2025
**Status:** Design Proposal

---

## 🎯 Overview

The **Grim Plugin Registry** is a centralized platform for discovering, installing, and managing Grim editor plugins (`.grim` packages).

**Goals:**
- Easy plugin discovery
- Automated installs and upgrades
- Version management
- Quality metrics (downloads, stars, ratings)
- Built on Zig for performance

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Users                            │
│  (grimpkg CLI, Grim editor, Web dashboard)         │
└───────────┬─────────────────────────────────────────┘
            │
            │ HTTPS/REST
            ▼
┌─────────────────────────────────────────────────────┐
│          Grim Registry API (Zig + zhttp)           │
│                                                     │
│  /api/packages      - List/search packages         │
│  /api/packages/<name> - Package info               │
│  /api/download      - Download tarball             │
│  /api/publish       - Publish new version          │
│  /api/stats         - Usage statistics             │
└───────────┬─────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────┐
│            Storage Layer                            │
│                                                     │
│  PostgreSQL: Metadata (packages, versions, users)  │
│  S3/MinIO: Package tarballs                        │
│  Redis: Cache (search results, popular packages)   │
└─────────────────────────────────────────────────────┘
```

---

## 📦 Data Model

### Database Schema (PostgreSQL)

#### `packages` table
```sql
CREATE TABLE packages (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    category VARCHAR(50),
    author_id INTEGER REFERENCES users(id),
    repository_url VARCHAR(500),
    homepage_url VARCHAR(500),
    license VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    download_count INTEGER DEFAULT 0,
    star_count INTEGER DEFAULT 0
);

CREATE INDEX idx_packages_category ON packages(category);
CREATE INDEX idx_packages_author ON packages(author_id);
CREATE INDEX idx_packages_downloads ON packages(download_count DESC);
```

#### `package_versions` table
```sql
CREATE TABLE package_versions (
    id SERIAL PRIMARY KEY,
    package_id INTEGER REFERENCES packages(id),
    version VARCHAR(50) NOT NULL,
    changelog TEXT,
    tarball_url VARCHAR(500),
    tarball_sha256 VARCHAR(64),
    tarball_size_bytes BIGINT,
    published_at TIMESTAMP DEFAULT NOW(),
    yanked BOOLEAN DEFAULT FALSE,
    UNIQUE(package_id, version)
);

CREATE INDEX idx_versions_package ON package_versions(package_id);
CREATE INDEX idx_versions_published ON package_versions(published_at DESC);
```

#### `dependencies` table
```sql
CREATE TABLE dependencies (
    id SERIAL PRIMARY KEY,
    version_id INTEGER REFERENCES package_versions(id),
    dependency_name VARCHAR(255) NOT NULL,
    version_constraint VARCHAR(100) NOT NULL
);

CREATE INDEX idx_dependencies_version ON dependencies(version_id);
```

#### `users` table
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    github_id INTEGER UNIQUE,
    username VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255),
    api_token VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

#### `package_stars` table
```sql
CREATE TABLE package_stars (
    user_id INTEGER REFERENCES users(id),
    package_id INTEGER REFERENCES packages(id),
    starred_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, package_id)
);
```

#### `download_stats` table
```sql
CREATE TABLE download_stats (
    package_id INTEGER REFERENCES packages(id),
    version VARCHAR(50),
    download_date DATE,
    count INTEGER DEFAULT 0,
    PRIMARY KEY (package_id, version, download_date)
);

CREATE INDEX idx_download_stats_date ON download_stats(download_date DESC);
```

---

## 🌐 API Endpoints

### Public Endpoints (No Auth)

#### `GET /api/packages`
List all packages with pagination and filtering.

**Query Parameters:**
- `page` (default: 1)
- `per_page` (default: 20, max: 100)
- `category` (optional)
- `sort` (downloads, stars, updated, name)
- `order` (asc, desc)

**Response:**
```json
{
  "packages": [
    {
      "name": "file-tree",
      "version": "0.2.0",
      "description": "Neo-tree-like file explorer",
      "author": "ghostkellz",
      "category": "ui",
      "downloads": 15234,
      "stars": 892,
      "updated_at": "2025-10-15T10:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 156
  }
}
```

#### `GET /api/packages/search?q=<query>`
Search packages by name, description, or tags.

**Response:**
```json
{
  "results": [
    {
      "name": "file-tree",
      "description": "File explorer for Grim",
      "score": 0.95
    }
  ],
  "total": 12
}
```

#### `GET /api/packages/<name>`
Get detailed package information.

**Response:**
```json
{
  "name": "file-tree",
  "description": "Neo-tree-like file explorer",
  "author": {
    "username": "ghostkellz",
    "github": "ghostkellz"
  },
  "category": "ui",
  "license": "MIT",
  "repository": "https://github.com/ghostkellz/file-tree.grim",
  "homepage": "https://file-tree.grimeditor.dev",
  "versions": [
    {
      "version": "0.2.0",
      "published_at": "2025-10-15T10:30:00Z",
      "size": "125 KB",
      "downloads": 5234
    },
    {
      "version": "0.1.0",
      "published_at": "2025-09-01T08:15:00Z",
      "size": "98 KB",
      "downloads": 10000
    }
  ],
  "latest_version": "0.2.0",
  "downloads": 15234,
  "stars": 892,
  "dependencies": {
    "theme": "^0.1.0",
    "statusline": "~0.2.0"
  }
}
```

#### `GET /api/packages/<name>/<version>/manifest`
Get plugin.zon manifest for a specific version.

**Response:**
```zig
.{
    .name = "file-tree",
    .version = "0.2.0",
    .description = "Neo-tree-like file explorer",
    ...
}
```

#### `GET /api/download/<name>/<version>`
Download package tarball.

**Response:** Binary tar.gz file

**Headers:**
- `Content-Type: application/gzip`
- `Content-Disposition: attachment; filename=file-tree-0.2.0.tar.gz`
- `X-SHA256: <checksum>`

### Authenticated Endpoints (Require API Token)

#### `POST /api/publish`
Publish a new package version.

**Request:**
```json
{
  "name": "my-plugin",
  "version": "0.1.0",
  "tarball": "<base64-encoded tar.gz>",
  "manifest": { ... }
}
```

**Response:**
```json
{
  "success": true,
  "package": "my-plugin",
  "version": "0.1.0",
  "url": "https://registry.grimeditor.dev/packages/my-plugin/0.1.0"
}
```

#### `POST /api/packages/<name>/star`
Star a package.

**Response:**
```json
{
  "success": true,
  "stars": 893
}
```

#### `DELETE /api/packages/<name>/star`
Unstar a package.

#### `PATCH /api/packages/<name>/versions/<version>`
Update version metadata (yank/unyank).

**Request:**
```json
{
  "yanked": true,
  "reason": "Security vulnerability"
}
```

---

## 🔐 Authentication

### GitHub OAuth Flow
1. User clicks "Login with GitHub"
2. Redirected to GitHub OAuth
3. Registry receives OAuth token
4. Create/update user record
5. Generate API token for `grimpkg` CLI

### API Token Usage
```bash
# Store token locally
grimpkg login

# Token saved to ~/.config/grim/auth.token

# Use in API requests
curl -H "Authorization: Bearer <token>" \
  https://registry.grimeditor.dev/api/publish
```

---

## 📊 Statistics & Analytics

### Metrics Tracked
1. **Downloads** per package/version/day
2. **Stars** per package
3. **Search queries** (for trending detection)
4. **Popular packages** (7-day, 30-day, all-time)
5. **New packages** per week
6. **Active authors**

### Endpoints

#### `GET /api/stats/popular`
Most downloaded packages (last 30 days).

**Response:**
```json
{
  "popular": [
    {
      "name": "file-tree",
      "downloads": 5234,
      "rank": 1
    }
  ]
}
```

#### `GET /api/stats/trending`
Trending packages (growing downloads).

#### `GET /api/stats/new`
Recently published packages.

---

## 🗂️ Storage

### Package Tarballs
- **S3/MinIO** for tarball storage
- CDN for fast downloads worldwide
- Versioned URLs: `https://cdn.grimeditor.dev/packages/file-tree-0.2.0.tar.gz`

### Metadata Cache
- **Redis** for caching:
  - Search results (5 min TTL)
  - Popular packages (1 hour TTL)
  - Package info (10 min TTL)

---

## 🚀 Publishing Workflow

### 1. Developer Publishes
```bash
$ cd my-plugin.grim
$ grimpkg publish --tag v0.1.0

[grimpkg] 📦 Building tarball...
[grimpkg] ✅ Created my-plugin-0.1.0.tar.gz (125 KB)
[grimpkg] 🔐 Authenticating...
[grimpkg] 📤 Uploading to registry...
[grimpkg] ✅ Published my-plugin@0.1.0
[grimpkg]
[grimpkg] View at: https://registry.grimeditor.dev/packages/my-plugin
```

### 2. Registry Processes
1. Validate manifest (plugin.zon)
2. Verify tarball structure
3. Scan for security issues
4. Extract metadata
5. Store tarball in S3
6. Update database
7. Invalidate cache
8. Send notification (webhook/email)

### 3. Users Install
```bash
$ grimpkg install my-plugin

[grimpkg] 📥 Downloading my-plugin@0.1.0...
[grimpkg] ✅ Installed my-plugin@0.1.0
```

---

## 🔍 Search Algorithm

### Full-Text Search (PostgreSQL)
```sql
SELECT name, description, ts_rank(search_vector, query) AS rank
FROM packages, plainto_tsquery('file tree') query
WHERE search_vector @@ query
ORDER BY rank DESC;
```

### Ranking Factors
1. **Exact name match** (highest priority)
2. **Name prefix match**
3. **Description match**
4. **Tags match**
5. **Popularity** (downloads + stars)

---

## 🛡️ Security

### Package Verification
1. **SHA-256 checksum** for every tarball
2. **Size limits** (max 50 MB per package)
3. **Manifest validation** (schema check)
4. **Author verification** (GitHub account required)

### Malware Detection
- Basic static analysis on publish
- Community reporting system
- Manual review for popular packages

### Rate Limiting
```
/api/packages - 100 req/min
/api/search - 50 req/min
/api/publish - 10 req/hour (per user)
/api/download - 1000 req/hour (per IP)
```

---

## 📈 Upgrade System

### Version Resolution
```bash
$ grimpkg upgrade file-tree

[grimpkg] 📦 Current: file-tree@0.1.0
[grimpkg] 🔍 Checking for updates...
[grimpkg] ✅ Available: file-tree@0.2.0
[grimpkg]
[grimpkg] Changelog:
[grimpkg]   - Added fuzzy search
[grimpkg]   - Fixed tree collapse bug
[grimpkg]   - Performance improvements
[grimpkg]
[grimpkg] Upgrade? [Y/n] Y
[grimpkg] 📥 Downloading...
[grimpkg] ✅ Upgraded to 0.2.0
```

### Rollback
```bash
$ grimpkg rollback file-tree

[grimpkg] ⏪ Rolling back file-tree...
[grimpkg] 📦 Current: 0.2.0
[grimpkg] ⬅️  Previous: 0.1.0
[grimpkg] ✅ Rolled back to 0.1.0
```

---

## 🎨 Web Dashboard

### Features
- **Browse** all packages
- **Search** with filters
- **Package details** page
- **Author profiles**
- **Statistics** dashboard
- **Publish UI** (alternative to CLI)

### URL Structure
```
https://registry.grimeditor.dev/
├── /packages              # Browse all
├── /packages/file-tree    # Package details
├── /authors/ghostkellz    # Author profile
├── /stats                 # Global statistics
└── /publish               # Publish UI
```

---

## 🚧 Implementation Roadmap

### Phase 1: MVP (Week 3-4)
- [ ] Basic API server (Zig + zhttp)
- [ ] PostgreSQL schema
- [ ] Package upload/download
- [ ] Simple web UI

### Phase 2: Core Features (Week 5-6)
- [ ] Search functionality
- [ ] Dependency resolution
- [ ] User authentication (GitHub OAuth)
- [ ] grimpkg CLI integration

### Phase 3: Polish (Week 7)
- [ ] Statistics/analytics
- [ ] Web dashboard
- [ ] CDN integration
- [ ] Security scanning

### Phase 4: Production (Week 8)
- [ ] Load testing
- [ ] Monitoring
- [ ] Backups
- [ ] Launch! 🚀

---

## 📊 Success Metrics

### Technical
- **API latency**: <100ms (p99)
- **Download speed**: >10 MB/s
- **Uptime**: 99.9%
- **Search response**: <50ms

### Community
- **Packages**: 100+ in first month
- **Downloads**: 10k+ per week
- **Active authors**: 50+
- **Stars**: Average 10+ per popular package

---

## 🌍 Infrastructure

### Hosting
- **API Server**: DigitalOcean/Hetzner (Zig binary, systemd)
- **Database**: Managed PostgreSQL
- **Storage**: S3-compatible (MinIO or Wasabi)
- **CDN**: Cloudflare
- **Cache**: Redis Cloud

### Estimated Costs (Monthly)
- API Server (4GB RAM): $20
- PostgreSQL: $15
- S3 Storage (100GB): $5
- CDN: $0 (Cloudflare free tier)
- **Total**: ~$40/month

---

## 📝 Example Queries

### Get Trending Packages (Last 7 Days)
```sql
SELECT p.name, SUM(ds.count) as downloads
FROM packages p
JOIN download_stats ds ON p.id = ds.package_id
WHERE ds.download_date >= NOW() - INTERVAL '7 days'
GROUP BY p.id, p.name
ORDER BY downloads DESC
LIMIT 10;
```

### Get Package Dependencies
```sql
SELECT d.dependency_name, d.version_constraint
FROM package_versions pv
JOIN dependencies d ON pv.id = d.version_id
WHERE pv.package_id = (SELECT id FROM packages WHERE name = 'file-tree')
  AND pv.version = '0.2.0';
```

---

**Status:** Design complete, ready for implementation! 🎯
**Next:** Build MVP in Zig with zhttp + PostgreSQL

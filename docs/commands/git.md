# Git Commands Reference

Git integration commands for Grim editor.

## Overview

Grim provides built-in Git commands for version control without leaving the editor.

## Commands

### `:Git <command>`

Execute arbitrary git command.

**Usage:**
```vim
:Git status
:Git add .
:Git commit -m "message"
:Git push
:Git pull
:Git log --oneline
```

**Output shown in popup or split window.**

---

### `:Gstatus`

Show git status.

**Usage:**
```vim
:Gstatus
:Gs             " Short form
```

**Example Output:**
```
On branch main
Your branch is up to date with 'origin/main'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        modified:   src/main.zig

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes)
        modified:   core/editor.zig

Untracked files:
  (use "git add <file>..." to include)
        test.zig
```

---

### `:Gadd [files]`

Stage files for commit.

**Usage:**
```vim
:Gadd                   " Stage current file
:Gadd .                 " Stage all changes
:Gadd src/main.zig      " Stage specific file
```

**Aliases:** `:Gstage`

---

### `:Gcommit [message]`

Commit staged changes.

**Usage:**
```vim
:Gcommit                " Open commit editor
:Gcommit -m "fix: bug" " Commit with inline message
```

**Commit Editor:**
If no message provided, opens buffer for commit message.

**AI-Powered Commits:**
Use `:ThanosCommit` to generate commit message from diff.

---

### `:Gpush [remote] [branch]`

Push commits to remote.

**Usage:**
```vim
:Gpush                  " Push to origin/current-branch
:Gpush origin main      " Push to origin/main
:Gpush -f               " Force push (dangerous!)
```

---

### `:Gpull [remote] [branch]`

Pull changes from remote.

**Usage:**
```vim
:Gpull                  " Pull from origin/current-branch
:Gpull origin develop   " Pull from origin/develop
```

---

### `:Gdiff [file]`

Show git diff.

**Usage:**
```vim
:Gdiff                  " Diff current file
:Gdiff src/main.zig     " Diff specific file
:Gdiff --cached         " Diff staged changes
```

**Output:**
Opens split window with unified diff format.

**Navigation:**
- `]c` - Next change
- `[c` - Previous change

---

### `:Glog [options]`

Show commit history.

**Usage:**
```vim
:Glog                   " Show log
:Glog --oneline         " Compact log
:Glog -n 10             " Last 10 commits
:Glog --author=alice    " Commits by alice
```

**Example Output:**
```
* 523172e (HEAD -> main) feat: polish gpkg package manager
* 628b1e6 feat: implement native Harpoon and Git UI
* 096978d feat: add native Harpoon + Git integration
* 848bb7e feat: add harpoon, undotree, neogit plugins
* 1586b84 perf: optimize startup + fix screen buffer
```

---

### `:Gblame`

Show git blame for current file.

**Usage:**
```vim
:Gblame
```

**Output:**
Opens split with blame annotations showing:
- Commit hash
- Author
- Date
- Line content

**Example:**
```
523172e (Alice 2025-10-24 12:34:56) fn main() !void {
628b1e6 (Bob   2025-10-23 09:15:30)     const x = 42;
```

---

### `:Gbranch [command]`

Git branch operations.

**Usage:**
```vim
:Gbranch                " List branches
:Gbranch new-feature    " Create branch
:Gbranch -d old-branch  " Delete branch
```

**Branch List Output:**
```
* main
  develop
  feature/ai-integration
  hotfix/bug-123
```

---

### `:Gcheckout <branch|file>`

Checkout branch or restore file.

**Usage:**
```vim
:Gcheckout develop          " Switch to develop branch
:Gcheckout -b new-feature   " Create and switch to new branch
:Gcheckout src/main.zig     " Restore file from HEAD
```

**Aliases:** `:Gco`

---

### `:Gmerge <branch>`

Merge branch into current branch.

**Usage:**
```vim
:Gmerge feature-branch
:Gmerge --no-ff feature  " No fast-forward
```

**Conflict Resolution:**
If conflicts occur, use `:Gdiff` to review and resolve.

---

### `:Grebase <branch>`

Rebase current branch onto another.

**Usage:**
```vim
:Grebase main
:Grebase --continue     " Continue after resolving conflicts
:Grebase --abort        " Abort rebase
```

---

### `:Gstash [command]`

Stash uncommitted changes.

**Usage:**
```vim
:Gstash                 " Stash changes
:Gstash push            " Explicit push
:Gstash pop             " Apply and remove stash
:Gstash list            " List stashes
:Gstash apply           " Apply without removing
:Gstash drop            " Remove stash
```

**Example:**
```vim
:Gstash                 " Stash changes
:Gcheckout feature      " Switch branch
:Gstash pop             " Restore changes
```

---

## Git Signs (Visual Indicators)

Grim shows git status in the gutter:

| Symbol | Meaning |
|--------|---------|
| `+` | Added line (new) |
| `~` | Modified line (changed) |
| `-` | Deleted line (removed) |

**Example:**
```
 1  │ fn main() !void {
 2 +│     const x = 42;      ← New line
 3 ~│     const y = x * 2;   ← Modified line
 4  │     std.debug.print("{}\n", .{y});
 5  │ }
```

**Colors:**
- Green `+` - Added
- Yellow `~` - Modified
- Red `-` - Deleted

---

## GitHub Integration

### `:GH <command>`

Execute GitHub CLI commands.

**Requires:** `gh` CLI tool installed

**Usage:**
```vim
:GH pr list             " List pull requests
:GH pr create           " Create PR
:GH pr view 123         " View PR #123
:GH issue list          " List issues
:GH issue create        " Create issue
:GH repo view           " View repository
```

**Examples:**
```vim
:GH pr create --title "feat: add AI" --body "Adds AI integration"
:GH pr merge 123
:GH pr checks 123       " Show CI status
```

---

## Git Workflow Examples

### Basic Workflow

```vim
" 1. Check status
:Gstatus

" 2. Stage changes
:Gadd .

" 3. Commit (AI-powered message)
:ThanosCommit

" 4. Push
:Gpush
```

---

### Feature Branch Workflow

```vim
" 1. Create branch
:Gcheckout -b feature/new-feature

" 2. Make changes, commit
:Gadd .
:Gcommit -m "feat: add new feature"

" 3. Push to remote
:Gpush origin feature/new-feature

" 4. Create PR via GitHub CLI
:GH pr create
```

---

### Stash and Switch

```vim
" 1. Stash current work
:Gstash

" 2. Switch to hotfix branch
:Gcheckout hotfix/critical-bug

" 3. Fix bug, commit, push
:Gadd .
:Gcommit -m "fix: critical bug"
:Gpush

" 4. Switch back and restore
:Gcheckout main
:Gstash pop
```

---

### Rebase Workflow

```vim
" 1. Update main branch
:Gcheckout main
:Gpull

" 2. Switch to feature branch
:Gcheckout feature/my-feature

" 3. Rebase onto main
:Grebase main

" 4. Resolve conflicts (if any)
:Gdiff
" ... fix conflicts ...
:Gadd .
:Grebase --continue

" 5. Force push (rewritten history)
:Gpush -f
```

---

## Configuration

`~/.config/grim/git.toml`:

```toml
[git]
enable_signs = true          # Show +/~/- in gutter
auto_fetch = true            # Auto-fetch from remote
fetch_interval_minutes = 10

[diff]
algorithm = "patience"       # Or "minimal", "histogram"
context_lines = 3            # Lines of context in diff
ignore_whitespace = false

[commit]
verbose = true               # Show diff in commit editor
gpg_sign = false             # GPG sign commits
template = "~/.gitmessage"   # Commit message template

[github]
enable_copilot = true        # GitHub Copilot integration
enable_gh_cli = true         # GitHub CLI support
```

---

## Git Aliases

Create shortcuts in `~/.config/grim/init.gza`:

```lua
vim.cmd("command! Gs Gstatus")
vim.cmd("command! Gc Gcommit")
vim.cmd("command! Gp Gpush")
vim.cmd("command! Gl Glog --oneline -n 20")
```

---

## Keybindings

Define in `~/.config/grim/init.gza`:

```lua
-- Git commands
map("n", "<leader>gs", ":Gstatus<CR>", "Git status")
map("n", "<leader>ga", ":Gadd .<CR>", "Git add all")
map("n", "<leader>gc", ":Gcommit<CR>", "Git commit")
map("n", "<leader>gp", ":Gpush<CR>", "Git push")
map("n", "<leader>gl", ":Glog<CR>", "Git log")
map("n", "<leader>gd", ":Gdiff<CR>", "Git diff")
map("n", "<leader>gb", ":Gblame<CR>", "Git blame")

-- GitHub PR
map("n", "<leader>gpr", ":GH pr create<CR>", "Create PR")
map("n", "<leader>gpm", ":GH pr merge<CR>", "Merge PR")
```

---

## Troubleshooting

### Not a Git Repository

**Issue:** Commands fail with "not a git repository"

**Solution:**
```bash
cd /path/to/project
git init
```

---

### Authentication Failed

**Issue:** Push fails with authentication error

**Solutions:**
1. Set up SSH keys: https://docs.github.com/en/authentication
2. Or use HTTPS with personal access token
3. Configure git credentials:
   ```bash
   git config --global credential.helper store
   ```

---

### Merge Conflicts

**Issue:** Merge/rebase stopped due to conflicts

**Resolution:**
1. View conflicts: `:Gdiff`
2. Edit files to resolve
3. Stage resolved files: `:Gadd .`
4. Continue: `:Gmerge --continue` or `:Grebase --continue`

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `:Gstatus` | Show git status |
| `:Gadd .` | Stage all changes |
| `:Gcommit` | Commit staged changes |
| `:Gpush` | Push to remote |
| `:Gpull` | Pull from remote |
| `:Gdiff` | Show diff |
| `:Glog` | Show commit history |
| `:Gblame` | Show git blame |
| `:Gcheckout <branch>` | Switch branch |
| `:Gmerge <branch>` | Merge branch |
| `:Gstash` | Stash changes |
| `:GH pr create` | Create GitHub PR |

---

## See Also

- [Commands Reference](README.md)
- [AI Commands](ai.md) - `:ThanosCommit` for AI commit messages
- [GitHub CLI](https://cli.github.com/)
- [Git Documentation](https://git-scm.com/doc)

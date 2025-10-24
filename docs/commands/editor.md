# Editor Commands Reference

Core editor commands for buffer, window, and file operations.

## File Operations

### `:e <file>` - Edit File

Open a file for editing.

**Usage:**
```vim
:e src/main.zig
:e ~/.config/grim/init.gza
:e /tmp/notes.txt
```

**Aliases:** `:edit`

**Behavior:**
- Creates new buffer if file doesn't exist
- Prompts to save if current buffer modified
- Supports tab completion for paths

---

### `:w [file]` - Write Buffer

Save current buffer to file.

**Usage:**
```vim
:w                    " Save to current file
:w newfile.zig        " Save as newfile.zig
```

**Aliases:** `:write`

**Options:**
- `:w!` - Force write (override readonly)

---

### `:q` - Quit

Close current buffer and exit editor.

**Usage:**
```vim
:q                    " Quit (fails if unsaved changes)
:q!                   " Force quit (discard changes)
```

**Aliases:** `:quit`

---

### `:wq` - Write and Quit

Save current buffer and exit.

**Usage:**
```vim
:wq                   " Save and quit
:wq!                  " Force save and quit
```

**Aliases:** `:x`

---

## Buffer Operations

### `:ls` - List Buffers

Show all open buffers.

**Usage:**
```vim
:ls
:buffers
```

**Example Output:**
```
1  %a  "src/main.zig"         line 45
2   a  "core/editor.zig"      line 1
3  #a  "ui-tui/simple_tui.zig" line 234
```

**Symbols:**
- `%` - Current buffer
- `#` - Alternate buffer
- `a` - Active (loaded)
- `h` - Hidden

---

### `:b <buffer>` - Switch Buffer

Switch to buffer by number or name.

**Usage:**
```vim
:b 2                  " Switch to buffer 2
:b main.zig           " Switch to buffer containing "main.zig"
:b#                   " Switch to alternate buffer
```

**Aliases:** `:buffer`

---

### `:bd [buffer]` - Delete Buffer

Close and remove buffer.

**Usage:**
```vim
:bd                   " Delete current buffer
:bd 2                 " Delete buffer 2
:bd main.zig          " Delete buffer by name
```

**Aliases:** `:bdelete`

---

## Window Operations

### `:split [file]` - Horizontal Split

Split window horizontally.

**Usage:**
```vim
:split                " Split current buffer
:split other.zig      " Split and open file
:sp                   " Short form
```

**Keybind:** `<C-w>s`

---

### `:vsplit [file]` - Vertical Split

Split window vertically.

**Usage:**
```vim
:vsplit               " Split current buffer
:vsplit other.zig     " Split and open file
:vsp                  " Short form
```

**Keybind:** `<C-w>v`

---

### Window Navigation

**Keybinds:**
- `<C-w>h` - Move to left window
- `<C-w>j` - Move to bottom window
- `<C-w>k` - Move to top window
- `<C-w>l` - Move to right window
- `<C-w>w` - Cycle through windows
- `<C-w>q` - Close current window

---

## Search and Replace

### `/pattern` - Search Forward

Search for pattern in buffer.

**Usage:**
```vim
/function             " Search for "function"
/fn.*init             " Search with regex
```

**Navigation:**
- `n` - Next match
- `N` - Previous match
- `<Esc>` - Cancel search

---

### `?pattern` - Search Backward

Search backward for pattern.

**Usage:**
```vim
?struct               " Search backward for "struct"
```

---

### `:s/old/new/` - Substitute

Replace text on current line.

**Usage:**
```vim
:s/old/new/           " Replace first occurrence
:s/old/new/g          " Replace all on line
:%s/old/new/g         " Replace all in file
:%s/old/new/gc        " Replace all with confirmation
```

**Flags:**
- `g` - Global (all occurrences)
- `c` - Confirm each replacement
- `i` - Case insensitive

---

## Line Operations

### `:d` - Delete Lines

Delete lines.

**Usage:**
```vim
:d                    " Delete current line
:5d                   " Delete line 5
:5,10d                " Delete lines 5-10
```

**Aliases:** `:delete`

---

### `:y` - Yank Lines

Copy lines to register.

**Usage:**
```vim
:y                    " Yank current line
:5,10y                " Yank lines 5-10
```

**Aliases:** `:yank`

---

### `:p` - Put Lines

Paste from register.

**Usage:**
```vim
:p                    " Put after current line
```

**Aliases:** `:put`

---

## Navigation

### `:<line>` - Go to Line

Jump to specific line number.

**Usage:**
```vim
:42                   " Go to line 42
:$                    " Go to last line
:1                    " Go to first line
```

**Keybind:** `gg` (first line), `G` (last line)

---

## Settings

### `:set <option>` - Set Option

Configure editor options.

**Usage:**
```vim
:set number           " Show line numbers
:set nonumber         " Hide line numbers
:set relativenumber   " Show relative line numbers
:set expandtab        " Use spaces for tabs
:set tabstop=4        " Tab width
:set shiftwidth=4     " Indent width
```

**Common Options:**
- `number` / `nonumber` - Line numbers
- `relativenumber` / `norelativenumber` - Relative line numbers
- `wrap` / `nowrap` - Line wrapping
- `expandtab` / `noexpandtab` - Spaces vs tabs
- `tabstop=N` - Tab width
- `shiftwidth=N` - Indent width

---

## Terminal

### `:term` - Open Terminal

Open integrated terminal in split.

**Usage:**
```vim
:term                 " Open terminal in horizontal split
:term bash            " Open specific shell
:term zig build       " Run command in terminal
```

**Terminal Controls:**
- `<C-\><C-n>` - Exit terminal mode to normal mode
- `i` - Enter terminal mode
- `:q` - Close terminal

---

## Help

### `:help [topic]` - Show Help

Display help documentation.

**Usage:**
```vim
:help                 " General help
:help commands        " Command reference
:help motions         " Motion reference
:help ai              " AI commands help
```

**Aliases:** `:h`

---

## Miscellaneous

### `:!command` - Execute Shell Command

Run external shell command.

**Usage:**
```vim
:!ls                  " List files
:!zig build           " Build project
:!git status          " Check git status
```

**Output shown in popup.**

---

### `:r !command` - Read Command Output

Insert command output into buffer.

**Usage:**
```vim
:r !date              " Insert current date
:r !ls                " Insert file list
```

---

### `:cd <dir>` - Change Directory

Change working directory.

**Usage:**
```vim
:cd ~/projects/grim
:cd ..
:pwd                  " Print working directory
```

---

### `:source <file>` - Source Config File

Execute commands from file.

**Usage:**
```vim
:source ~/.config/grim/init.gza
```

---

### `:registers` - Show Registers

Display register contents.

**Usage:**
```vim
:registers
:reg
```

**Example Output:**
```
""   Last yank/delete
"0   Last yank only
"1-9 Delete history
"a-z Named registers
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `:e <file>` | Edit file |
| `:w` | Write buffer |
| `:q` | Quit |
| `:wq` | Write and quit |
| `:ls` | List buffers |
| `:b <n>` | Switch to buffer |
| `:split` | Horizontal split |
| `:vsplit` | Vertical split |
| `/pattern` | Search forward |
| `:%s/old/new/g` | Replace all |
| `:set number` | Show line numbers |
| `:term` | Open terminal |
| `:help` | Show help |

## See Also

- [Motions](../motions/README.md)
- [AI Commands](ai.md)
- [LSP Commands](lsp.md)
- [Configuration](../configuration.md)

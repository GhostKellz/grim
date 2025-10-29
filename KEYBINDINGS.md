# Grim Keybindings Reference

## Normal Mode

### Motion
- `h, j, k, l` - Move left, down, up, right
- `w` - Next word start
- `b` - Previous word start
- `e` - Next word end
- `0` - Start of line
- `$` - End of line
- `gg` - Start of file
- `G` - End of file
- `{` - Previous paragraph
- `}` - Next paragraph

### Editing
- `i` - Enter insert mode before cursor
- `a` - Enter insert mode after cursor
- `I` - Insert at start of line
- `A` - Append at end of line
- `o` - Open line below
- `O` - Open line above
- `x` - Delete character
- `dd` - Delete line
- `yy` - Yank (copy) line
- `p` - Paste after cursor
- `P` - Paste before cursor
- `u` - Undo
- `Ctrl+r` - Redo

### Visual Mode
- `v` - Enter character-wise visual mode
- `V` - Enter line-wise visual mode
- (In visual) `hjkl` - Extend selection
- (In visual) `d` / `x` - Delete selection
- (In visual) `y` - Yank selection

### Search & Replace
- `/pattern` - Search forward
- `?pattern` - Search backward
- `n` - Next match
- `N` - Previous match
- `*` - Search word under cursor forward
- `#` - Search word under cursor backward
- `f{char}` - Find character forward on line
- `F{char}` - Find character backward on line
- `t{char}` - Till character forward
- `T{char}` - Till character backward
- `;` - Repeat last f/F/t/T
- `,` - Repeat last f/F/t/T in opposite direction

### Folding
- `za` - Toggle fold at cursor
- `zM` - Fold all
- `zR` - Unfold all

### Multi-Cursor
- `Ctrl+d` - Select next occurrence of word
- `Ctrl+a` - Select all occurrences of word
- `Esc` - Exit multi-cursor mode

### Command Mode
- `:` - Enter command mode
- `:w` - Write file
- `:q` - Quit
- `:wq` - Write and quit
- `:s/pattern/replacement/` - Substitute on current line

### Macros
- `q{register}` - Start recording macro
- `q` - Stop recording
- `@{register}` - Play macro

### LSP (when available)
- `gd` - Go to definition
- `K` - Show hover information
- `<leader>rn` - Rename symbol
- `<leader>ca` - Code actions

## Insert Mode
- `Esc` - Return to normal mode
- `Ctrl+w` - Delete word backward
- `Ctrl+u` - Delete to start of line
- Type normally to insert text

## Visual Mode
- `Esc` - Return to normal mode
- `hjkl` - Extend selection
- `w, b, e` - Extend by word
- `0, $` - Extend to line boundaries
- `gg, G` - Extend to file boundaries
- `d, x` - Delete selection
- `y` - Yank selection
- `V` - Switch to line-wise visual
- `v` - Switch to character-wise visual

## Command Mode
- Type your command
- `Enter` - Execute command
- `Esc` - Cancel and return to normal mode
- `Backspace` - Delete character

### Supported Commands
- `w [filename]` - Write file
- `q` - Quit (if no unsaved changes)
- `wq` - Write and quit
- `/pattern` - Search forward
- `?pattern` - Search backward
- `s/find/replace/` - Substitute on line
- `%s/find/replace/g` - Global substitute (coming soon)

## Snippets

Snippets are loaded from `~/.config/grim/snippets/<filetype>.json`

Trigger snippets by typing the prefix and pressing Tab (when implemented).

Example snippet files are provided in the `snippets/` directory:
- `zig.json` - Zig language snippets
- `rust.json` - Rust language snippets
- `go.json` - Go language snippets
- `javascript.json` - JavaScript snippets

### Snippet Tab Stops
- `$1`, `$2`, etc. - Tab stops in order
- `${1:default}` - Tab stop with placeholder text
- `$0` - Final cursor position

## Tips

- Use `.` to repeat the last change
- Combine counts with motions: `5j` moves down 5 lines
- Combine operators with motions: `d5j` deletes 5 lines down
- Use `%` to jump between matching brackets
- Use marks: `m{a-z}` to set mark, `'{a-z}` to jump to mark

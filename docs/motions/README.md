# Grim Motions Reference

Complete reference for cursor movement and navigation in Grim.

## Motion Categories

- [Basic Motions](#basic-motions) - Character and line movement
- [Word Motions](#word-motions) - Word-based navigation
- [Line Motions](#line-motions) - Line-specific movement
- [Screen Motions](#screen-motions) - Viewport navigation
- [Jump Motions](#jump-motions) - File-wide jumping
- [Search Motions](#search-motions) - Pattern-based navigation

## Basic Motions

### Character Movement

| Key | Motion | Description |
|-----|--------|-------------|
| `h` | ← | Move left |
| `j` | ↓ | Move down |
| `k` | ↑ | Move up |
| `l` | → | Move right |
| `<Space>` | → | Move right (alternative) |
| `<Backspace>` | ← | Move left (alternative) |

**With Count:**
- `5h` - Move 5 characters left
- `10j` - Move 10 lines down

---

## Word Motions

### Forward Word Movement

| Key | Motion | Description |
|-----|--------|-------------|
| `w` | Next word | Jump to start of next word |
| `W` | Next WORD | Jump to start of next WORD (whitespace-delimited) |
| `e` | End of word | Jump to end of current/next word |
| `E` | End of WORD | Jump to end of current/next WORD |

**Examples:**
```
cursor_position = 42;
^     ^         ^ ^  ^
w     w         w w  w

cursor_position = 42;
^                    ^
W                    W
```

**Word vs WORD:**
- **word** - Delimited by non-alphanumeric chars (`cursor`, `_`, `position`)
- **WORD** - Delimited by whitespace only (`cursor_position`)

---

### Backward Word Movement

| Key | Motion | Description |
|-----|--------|-------------|
| `b` | Previous word | Jump to start of previous word |
| `B` | Previous WORD | Jump to start of previous WORD |
| `ge` | Previous word end | Jump to end of previous word |
| `gE` | Previous WORD end | Jump to end of previous WORD |

---

## Line Motions

### Horizontal Line Movement

| Key | Motion | Description |
|-----|--------|-------------|
| `0` | Line start | Jump to column 0 (absolute start) |
| `^` | First non-blank | Jump to first non-whitespace character |
| `$` | Line end | Jump to end of line |
| `g_` | Last non-blank | Jump to last non-whitespace character |

**Example:**
```
    const x = 42;
^   ^     ^     ^
0   ^     g_    $
```

---

### Line-based Movement

| Key | Motion | Description |
|-----|--------|-------------|
| `+` | Next line | Move to first non-blank of next line |
| `-` | Previous line | Move to first non-blank of previous line |
| `_` | Current line | Move to first non-blank of current line |
| `<Enter>` | Next line | Move to start of next line |

---

## Screen Motions

### Viewport Navigation

| Key | Motion | Description |
|-----|--------|-------------|
| `H` | High | Jump to top of screen |
| `M` | Middle | Jump to middle of screen |
| `L` | Low | Jump to bottom of screen |

**With Count:**
- `5H` - 5 lines from top
- `5L` - 5 lines from bottom

---

### Scrolling

| Key | Motion | Description |
|-----|--------|-------------|
| `<C-f>` | Page down | Scroll one page forward |
| `<C-b>` | Page up | Scroll one page backward |
| `<C-d>` | Half page down | Scroll half page forward |
| `<C-u>` | Half page up | Scroll half page backward |
| `<C-e>` | Scroll down | Scroll viewport down one line |
| `<C-y>` | Scroll up | Scroll viewport up one line |

---

### Screen Positioning

| Key | Motion | Description |
|-----|--------|-------------|
| `zt` | Top | Position current line at top of screen |
| `zz` | Center | Position current line at center of screen |
| `zb` | Bottom | Position current line at bottom of screen |

---

## Jump Motions

### File Navigation

| Key | Motion | Description |
|-----|--------|-------------|
| `gg` | First line | Jump to first line of file |
| `G` | Last line | Jump to last line of file |
| `<N>G` | Line N | Jump to line N (e.g., `42G`) |
| `<N>gg` | Line N | Jump to line N (alternative) |
| `%` | Matching bracket | Jump to matching `()`, `{}`, `[]` |

**Examples:**
```vim
gg              " Jump to line 1
G               " Jump to last line
42G             " Jump to line 42
50gg            " Jump to line 50
```

---

### Jump List

| Key | Motion | Description |
|-----|--------|-------------|
| `<C-o>` | Older jump | Jump to older position in jump list |
| `<C-i>` | Newer jump | Jump to newer position in jump list |
| `` ` ` `` | Last jump | Jump to position before last jump |
| `''` | Last line | Jump to line of last jump |

**Jump List:**
Grim remembers your jump history (cross-file).

---

### Marks

| Key | Motion | Description |
|-----|--------|-------------|
| `m{a-z}` | Set mark | Set local mark (buffer-specific) |
| `m{A-Z}` | Set mark | Set global mark (file-specific) |
| `` `{a-z} `` | Jump to mark | Jump to mark (exact position) |
| `'{a-z}` | Jump to mark line | Jump to line of mark |

**Examples:**
```vim
ma              " Set mark 'a' at cursor
`a              " Jump to mark 'a' (exact position)
'a              " Jump to line of mark 'a'

mA              " Set global mark 'A' (persists across files)
```

---

## Search Motions

### Character Search

| Key | Motion | Description |
|-----|--------|-------------|
| `f{char}` | Find forward | Jump to next occurrence of {char} |
| `F{char}` | Find backward | Jump to previous occurrence of {char} |
| `t{char}` | Till forward | Jump to before next {char} |
| `T{char}` | Till backward | Jump to after previous {char} |
| `;` | Repeat search | Repeat last `f`/`F`/`t`/`T` search |
| `,` | Reverse search | Repeat last search in opposite direction |

**Examples:**
```zig
const allocator = std.heap.page_allocator;
^     ^         ^ ^    ^    ^    ^
f'a'  ;         ; ;    ;    ;    ;

fb              " Jump backward to 'b'
t'='            " Jump till '=' (stop before)
```

---

### Pattern Search

| Key | Motion | Description |
|-----|--------|-------------|
| `/pattern` | Search forward | Search for pattern |
| `?pattern` | Search backward | Search backward for pattern |
| `n` | Next match | Jump to next match |
| `N` | Previous match | Jump to previous match |
| `*` | Search word forward | Search for word under cursor (forward) |
| `#` | Search word backward | Search for word under cursor (backward) |

**Examples:**
```vim
/function       " Search for "function"
n               " Next match
N               " Previous match

*               " Search for word under cursor
```

---

## Text Object Motions

### Inner vs Around

Text objects have two forms:
- `i` - **inner** (excludes delimiters)
- `a` - **around** (includes delimiters)

| Key | Text Object | Description |
|-----|-------------|-------------|
| `iw` | Inner word | Inside word (excludes surrounding whitespace) |
| `aw` | Around word | Around word (includes surrounding whitespace) |
| `iW` | Inner WORD | Inside WORD |
| `aW` | Around WORD | Around WORD |
| `is` | Inner sentence | Inside sentence |
| `as` | Around sentence | Around sentence (includes trailing space) |
| `ip` | Inner paragraph | Inside paragraph |
| `ap` | Around paragraph | Around paragraph (includes blank lines) |

**Paired Delimiters:**

| Key | Text Object | Description |
|-----|-------------|-------------|
| `i(` / `i)` / `ib` | Inner parens | Inside `()` |
| `a(` / `a)` / `ab` | Around parens | Around `()` (includes parens) |
| `i{` / `i}` / `iB` | Inner braces | Inside `{}` |
| `a{` / `a}` / `aB` | Around braces | Around `{}` (includes braces) |
| `i[` / `i]` | Inner brackets | Inside `[]` |
| `a[` / `a]` | Around brackets | Around `[]` (includes brackets) |
| `i<` / `i>` | Inner angle | Inside `<>` |
| `a<` / `a>` | Around angle | Around `<>` (includes angle brackets) |
| `i'` | Inner quote | Inside `'...'` |
| `a'` | Around quote | Around `'...'` (includes quotes) |
| `i"` | Inner double quote | Inside `"..."` |
| `a"` | Around double quote | Around `"..."` (includes quotes) |
| `` i` `` | Inner backtick | Inside `` `...` `` |
| `` a` `` | Around backtick | Around `` `...` `` (includes backticks) |

**Examples:**
```zig
function("hello", world)
         ^-----^        " diw - delete inner word
         ^------^       " daw - delete around word (includes space)
        ^--------------^ " di( - delete inside parens
^-----------------------^ " da( - delete around parens (includes parens)
```

---

## Combining Motions with Operators

Motions can be combined with operators for powerful editing:

| Operator | Motion | Result |
|----------|--------|--------|
| `d` | Delete | Delete text |
| `c` | Change | Delete and enter insert mode |
| `y` | Yank | Copy text |
| `v` | Visual | Select text |

**Examples:**
```vim
dw              " Delete word
d2w             " Delete 2 words
d$              " Delete to end of line
dd              " Delete line
dt;             " Delete till semicolon
di(             " Delete inside parentheses
da{             " Delete around braces (including braces)

cw              " Change word
ci"             " Change inside quotes
ca{             " Change around braces

yw              " Yank word
y$              " Yank to end of line
yy              " Yank line
yi{             " Yank inside braces

vw              " Visual select word
vi(             " Visual select inside parens
```

---

## Special Motions

### Line-wise vs Character-wise

Most motions are **character-wise** (affect characters).
Some are **line-wise** (affect whole lines).

**Line-wise motions:**
- `j`, `k` - Move by line
- `gg`, `G` - Jump to line
- `+`, `-` - Line navigation

**Character-wise motions:**
- `h`, `l` - Character movement
- `w`, `e`, `b` - Word movement
- `f`, `t` - Character search

---

### Count with Motions

Almost all motions accept a count prefix:

```vim
5j              " Move down 5 lines
3w              " Move forward 3 words
2f;             " Find 2nd semicolon
10l             " Move right 10 characters
```

---

## Advanced Motion Techniques

### Combining Searches

```vim
/function       " Search for function
n               " Next occurrence
cgn             " Change next match (dot-repeatable!)
.               " Repeat on next match
```

---

### Visual Block Mode

```vim
<C-v>           " Enter visual block mode
jjj             " Select multiple lines
I               " Insert at start of each line
```

---

### Ex Command Ranges

Use motions in ex commands:

```vim
:.,$d           " Delete from current line to end
:1,10s/old/new/g " Replace in lines 1-10
:'<,'>d         " Delete visual selection
```

---

## Quick Reference Card

### Essential Motions

| Motion | Description |
|--------|-------------|
| `hjkl` | Arrow keys (left, down, up, right) |
| `w` / `b` | Next/previous word |
| `0` / `$` | Start/end of line |
| `gg` / `G` | First/last line |
| `f{char}` | Find character |
| `/pattern` | Search pattern |
| `%` | Matching bracket |
| `<C-d>` / `<C-u>` | Half page down/up |

### Text Objects

| Motion | Description |
|--------|-------------|
| `iw` / `aw` | Inner/around word |
| `i(` / `a(` | Inner/around parens |
| `i{` / `a{` | Inner/around braces |
| `i"` / `a"` | Inner/around quotes |

### Combining with Operators

```vim
dw              " Delete word
ciw             " Change inner word
yy              " Yank line
vip             " Visual select paragraph
```

---

## See Also

- [Commands Reference](../commands/README.md)
- [Operators](operators.md)
- [Visual Mode](visual.md)
- [Keybindings](../keybindings.md)

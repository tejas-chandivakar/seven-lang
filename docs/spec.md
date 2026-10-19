# SEVEN Language Specification

**Version:** 0.7 (Phase 7 — Developer Tools)
**Author:** Tejas Chandivakar
**Status:** Phase 7 complete — Developer Tools

---

## 1. Overview

SEVEN is a compiled, dynamically-typed programming language designed for **Assembly-level speed with Python-level simplicity**.

- **File extensions:** `.seven` (primary), `.sev`, `.sv7`, `.s7`
- **Compiler:** `seven build main.seven`
- **Interpreter (dev):** `seven run main.seven`
- **Bootstrap:** x86-64 NASM Assembly (Phase 1), self-hosted in Phase 2.

## 2. Design Principles

1. **Speed first** — direct Assembly generation, no VM, no GC.
2. **Human-readable** — `show`, `ask`, `repeat`, `each`, `skip`, `stop`, `err`, `secret`.
3. **Explicit blocks** — `end` closes every block. No `:` block start. No indentation rules.
4. **One way to do it** — no compound assignment (`+=`), no ternary; small grammar.
5. **Two modes** — `mode hybrid` (function-style arrays) and `mode natural` (English-style arrays).
6. **Natural I/O** — `show`, `ask`, `err`, `write`, `read` need no parentheses.
7. **Escape hatch** — `asm:` block and `unsafe:` block.

## 3. Mode System

A `.seven` file may declare its mode on the first non-comment line:

```
mode hybrid       !! default — push(list, x)
mode natural      !! English — add x to list
```

If omitted, `mode hybrid` is assumed. Mode only affects array mutation commands:

| Operation | `mode hybrid` | `mode natural` |
|-----------|--------------|----------------|
| Append | `push(list, x)` | `add x to list` |
| Remove | `remove(list, i)` | `remove i from list` |
| Insert | `insert(list, i, x)` | `insert x at i in list` |
| Pop | `pop(list)` | `pop from list` |

Everything else (syntax, keywords, classes, I/O, functions) is identical in both modes. Files in different modes can import each other freely — mode is a parse-time directive, not a runtime difference.

## 4. Lexical Structure

### Comments
```
!! single-line comment
x = 10  !! inline comment

!!!
   Multi-line comment
!!!
```
- `!!` from itself to end of line
- `!!!` (open) … `!!!` (close) — does NOT nest

### Identifiers
- Start with letter or underscore, then letters/digits/underscores
- Case-sensitive
- Not a reserved keyword

### Numeric literals
- Integer: `10`, `-5`, `0xFF`, `0b1010`
- Float: `3.14`, `-2.5`, `1e6`

### String literals
Three forms, all support `{expr}` auto-interpolation:
```
"double-quoted"
'single-quoted'
"""
triple-quoted
multi-line
"""
```
Escape sequences: `\n \t \" \' \\ \{ \}`.

`{{` and `}}` produce literal braces.

### Character literal
`char` type uses `'A'` when the context requires a char (declaration, cast).
When ambiguous with string, prefer double quotes for strings.

### Boolean & Null
`true`, `false`, `null` — lowercase only.

### Keywords (reserved)
```
show ask err secret put
if elif else end
func return
repeat while each as at skip stop match times
true false null
and or not in
try catch done error
class extends implements interface enum
struct packed shared
ref deref alloc free
async await gen yield
spawn send receive wait channel mutex
asm unsafe comptime const
import module from
this
many
mode hybrid natural
```

Reserved but currently unused: `raise`, `throw`, `fail`, `assert`, `self`, `static`.

## 5. Grammar (Phase 1 subset — EBNF)

```
program     = [ mode_decl ] { statement } ;
mode_decl   = "mode" ( "hybrid" | "natural" ) ;

statement   = assign | show | show_raw | err | ask_stmt | secret_stmt
            | if | repeat | while | each | func | return | error_stmt
            | file_write | file_read
            | natural_cmd          (* mode natural only *)
            | expr_stmt ;

assign      = IDENT "=" expression ;
show        = "show" expr_list ;
show_raw    = "show" "." "raw" expr_list ;
err         = "err" expr_list ;
expr_list   = expression { "," expression } ;

ask_stmt    = IDENT "=" "ask" STRING ;
secret_stmt = IDENT "=" "secret" STRING ;

file_write  = "write" STRING "," expression ;
file_read   = IDENT "=" "read" STRING ;

if          = "if" expression block
              { "elif" expression block }
              [ "else" block ]
              "end" ;

repeat      = "repeat" expression [ "times" ] [ "as" IDENT ] block "end" ;
while       = "while" expression block "end" ;
each        = "each" IDENT "as" IDENT [ "," IDENT ] block "end" ;

func        = "func" IDENT "(" [ params ] ")" block "end" ;
params      = param { "," param } ;
param       = [ "many" ] IDENT [ "=" expression ] ;

return      = "return" [ expression ] ;
error_stmt  = "error" expression ;

(* mode natural array commands *)
natural_cmd = "add" expression "to" IDENT
            | "remove" expression "from" IDENT
            | "insert" expression "at" expression "in" IDENT
            | "pop" "from" IDENT ;

block       = { statement } ;

expression  = logic ;
logic       = compare { ("and"|"or") compare } ;
compare     = add [ ("=="|"!="|"<"|">"|"<="|">="|"in"|"not" "in") add ] ;
add         = mul { ("+"|"-") mul } ;
mul         = unary { ("*"|"/"|"//"|"%") unary } ;
unary       = [ "-" | "not" ] power ;
power       = primary [ "**" unary ] ;
primary     = NUMBER | STRING | IDENT | "true" | "false" | "null"
            | "(" expression ")" | call | array | member ;

call        = IDENT "(" [ args ] ")" ;
args        = expression { "," expression } ;
array       = "[" [ expression { "," expression } ] "]" ;

member      = primary "." IDENT [ call_tail ]
            | primary "[" index_expr "]" ;
call_tail   = "(" [ args ] ")" ;
index_expr  = expression ;    (* negative allowed *)
```

## 6. Semantics

### 6.1 Strings & Interpolation
- Any string literal (`""`, `''`, `"""..."""`) auto-interpolates.
- `{expr}` inside a string is evaluated and stringified.
- `{{` and `}}` produce literal `{` and `}`.
- Interpolation is compile-time expanded to concatenation:
  ```
  show "Hi {name}"     ≡     show "Hi " + name
  ```

### 6.2 `show` variants
- `show a, b, c` — writes each, separated by single space, then newline.
- `show a + b`   — writes the single concatenated value + newline.
- `show.raw x`   — no newline appended.
- `err x, y`     — same as `show` but to stderr.

### 6.3 `ask` and `secret`
- Both prompt to stderr (visible even when stdout is piped) and read a line from stdin.
- `ask` **auto-detects** the value:
  - Contains only `0-9` (optional leading `-`) → int
  - Matches float pattern → float
  - Otherwise → string
- `secret` never echoes input; always returns string.

### 6.4 Membership (`in`)
- On arrays: linear scan, returns bool.
- On strings: substring test.
- On dicts: key test.
- `not in` is a single lexical token pair.

### 6.5 Negative Indexing
- `nums[-1]` is the last element; `nums[-2]` second last, etc.
- Out-of-range (positive or negative) is a runtime error.

### 6.6 Slicing
- No `[start:stop]` syntax. Use functions:
  - `slice(arr, start, stop)` — indexes `start..stop-1`
  - `step(arr, n)` — every n-th element
  - `reverse(arr)` — reversed copy

### 6.7 Variadic Params
- `many x` in a `func` param list collects remaining args into an array `x`.
- At most one `many` parameter, must be last.

### 6.8 Loop Index
- `each list as x`       — value only
- `each list as i, x`    — **index first**, value second

### 6.9 Error Model
- `error <value>` unwinds to nearest `try` block's `catch`.
- No `assert`. Use `if !cond → error "..."`.
- `catch` binds the error value optionally: `catch e`.

### 6.10 Classes
- Fields declared directly inside `class`.
- Methods use `func`.
- Reference own fields via `this.field`.
- **`shared func`** — static (class-level) method: `ClassName.method()`.

### 6.11 Mode System
- `mode hybrid` (default): array ops are function calls — `push(list, x)`.
- `mode natural`: array ops are English commands — `add x to list`.
- Mode is file-scoped. Cross-file imports work regardless of mode.
- Both modes produce identical compiled output.

## 7. Built-in Functions

### Original (Phase 1-5)
| Function | Description |
|----------|-------------|
| `len(x)` | String length or array count |
| `type(x)` | Returns "int", "string", or "array" |
| `str(x)` | Convert to string |
| `int(x)` | Convert string to integer |
| `slice(arr, start, stop)` | Sub-array |
| `reverse(arr)` | Reversed copy |
| `step(arr, n)` | Every n-th element |
| `abs(n)` | Absolute value |
| `min(a, b)` | Minimum |
| `max(a, b)` | Maximum |
| `sqrt(n)` | Integer square root |
| `random(n)` | Random integer 0..n-1 |
| `sort(arr)` | Sorted copy |
| `join(arr, sep)` | Join array to string |
| `range(n)` / `range(a,b)` | Generate integer array |
| `ord(ch)` | Character to ASCII code |
| `chr(n)` | ASCII code to character |
| `substr(s, start, len)` | Substring |
| `push(arr, val)` | Append to array |
| `pop(arr)` | Remove last element |
| `exit(code)` | Exit program |

### String Functions (Phase 6)
| Function | Description |
|----------|-------------|
| `replace(str, old, new)` | Replace all occurrences |
| `upper(str)` | Convert to uppercase |
| `lower(str)` | Convert to lowercase |
| `trim(str)` | Strip leading/trailing whitespace |
| `find(str, sub)` | Find substring index (-1 if not found) |
| `count(str, sub)` | Count non-overlapping occurrences |
| `pad(str, width, char)` | Left-pad to width |

### Math Functions (Phase 6)
| Function | Description |
|----------|-------------|
| `pow(base, exp)` | Integer exponentiation |
| `clamp(val, lo, hi)` | Clamp value to range |
| `sign(n)` | Returns -1, 0, or 1 |
| `gcd(a, b)` | Greatest common divisor |
| `sum(arr)` | Sum of array elements |
| `avg(arr)` | Average (integer division) |

### Array Functions (Phase 6)
| Function | Description |
|----------|-------------|
| `find(arr, val)` | Find index of element (-1 if not found) |
| `fill(n, val)` | Create array of n copies |
| `concat(arr1, arr2)` | Merge two arrays |
| `unique(arr)` | Deduplicated copy |
| `insert(arr, idx, val)` | Insert element at index |
| `remove(arr, idx)` | Remove element at index |

### Conversion Functions (Phase 6)
| Function | Description |
|----------|-------------|
| `hex(n)` | Integer to "0xFF" hex string |
| `bin(n)` | Integer to "0b1010" binary string |
| `bool(val)` | Convert to 1 or 0 |
| `number(str)` | String to integer (alias for int) |

### File I/O Functions (Phase 6)
| Function | Description |
|----------|-------------|
| `exists(path)` | Check if file exists (1/0) |
| `append(path, data)` | Append data to file |
| `delete(path)` | Delete file |
| `lines(path)` | Read file as array of lines |

### OS/System Functions (Phase 6)
| Function | Description |
|----------|-------------|
| `time()` | Unix timestamp in seconds |
| `clock()` | Monotonic nanoseconds |
| `sleep(seconds)` | Pause execution |
| `args()` | Command-line arguments as array |
| `env(name)` | Get environment variable |
| `system(cmd)` | Execute shell command, return exit code |

### String Methods
Called on string values with dot syntax: `s.upper()`, `s.lower()`, etc.

| Method | Description |
|--------|-------------|
| `.upper()` | Uppercase copy |
| `.lower()` | Lowercase copy |
| `.trim()` | Strip whitespace |
| `.contains(sub)` | Substring test (bool) |
| `.replace(old, new)` | Replace all |
| `.len()` | String length |
| `.startswith(pre)` | Prefix test |
| `.endswith(suf)` | Suffix test |
| `.index(sub)` | Find substring position |
| `.split(sep)` | Split into array |
| `.repeat(n)` | Repeat n times |

## 8. Runtime Model

- **No garbage collection.** 16MB bump arena freed on exit.
- **Stack-based expression evaluation** in generated code.
- **All variables are global** (BSS slots).
- **Values are 64-bit integers** — strings and arrays are heap pointers.
- **String/int detection** uses magnitude heuristic (> 0x400000 = string pointer).

## 9. Developer Tools

| Tool | Command | Description |
|------|---------|-------------|
| REPL | `tools/repl` | Interactive shell with history, `.help`, `.clear`, `.undo` |
| Formatter | `tools/fmt file.seven` | Auto-indent (4 spaces default), `--check` mode |
| Linter | `tools/lint file.seven` | Block matching, style checks, unused variables |
| Profiler | `tools/profile file.seven [N]` | Compile/asm/execution timing over N runs |
| VS Code | `editor/vscode/` | Syntax highlighting, snippets (v0.2.0) |

## 10. Reserved for Later Phases

- Async, generators, channels, mutex
- Decorators, operator overloading, comptime
- Modules, imports, package manager
- `mode strict` — optional type annotations

See `roadmap.md` for full phase plan.

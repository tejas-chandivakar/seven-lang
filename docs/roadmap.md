# SEVEN Development Roadmap

## Phase 1 — Mini Bootstrap Compiler (COMPLETE)
**Language:** x86-64 NASM Assembly
**Goal:** First working `seven build main.seven → executable`

- [x] Lexer (tokenizer)
- [x] Code Generator (single-pass, no AST)
- [x] Runtime library (print, strings, arrays, file I/O)
- [x] 39 core tests passing

---

## Phase 2 — Core Language Features (COMPLETE)
**Goal:** Expand language with practical features

- [x] String methods (.upper, .lower, .trim, .contains, .replace, .split, etc.)
- [x] Array operations (push, pop, sort, join, range, slice, reverse, step)
- [x] Comparison operators (above, below, atleast, atmost, is, isnt)
- [x] Error handling (try/catch/done)
- [x] File I/O (write/read statements)

---

## Phase 3 — Expression System (COMPLETE)
**Goal:** Full expression evaluation

- [x] Operator precedence (or → and → compare → add → mul → unary → primary)
- [x] Boolean operators (and, or, not)
- [x] String interpolation
- [x] Negative indexing

---

## Phase 4 — Advanced Features (COMPLETE)
**Goal:** Functions, classes, natural mode

- [x] User-defined functions with parameters
- [x] Variadic parameters (many)
- [x] Array subscript assignment
- [x] Each/as iteration with index
- [x] Inline assembly (asm: block)

---

## Phase 5 — Self-Hosted Compiler (COMPLETE)
**Goal:** Compiler written in SEVEN itself

- [x] Self-hosted compiler bootstraps successfully
- [x] 46 tests passing

---

## Phase 6 — Standard Library (COMPLETE)
**Goal:** Expand built-in functions for real-world programs

### String Functions
- [x] `replace(str, old, new)` — replace substring
- [x] `upper(str)` / `lower(str)` — case conversion
- [x] `trim(str)` — strip whitespace
- [x] `find(str, sub)` — find substring index
- [x] `count(str, sub)` — count occurrences
- [x] `pad(str, width, char)` — left-pad to width

### Math Functions
- [x] `pow(base, exp)` — integer exponentiation
- [x] `clamp(val, lo, hi)` — clamp to range
- [x] `sign(n)` — returns -1, 0, or 1
- [x] `gcd(a, b)` — greatest common divisor
- [x] `sum(arr)` — sum array elements
- [x] `avg(arr)` — average (integer division)

### Array Functions
- [x] `find(arr, val)` — find index of element
- [x] `fill(n, val)` — create array of n copies
- [x] `concat(arr1, arr2)` — merge arrays
- [x] `unique(arr)` — deduplicate
- [x] `insert(arr, idx, val)` — insert at index
- [x] `remove(arr, idx)` — remove at index

### Conversion Functions
- [x] `hex(n)` — integer to hex string
- [x] `bin(n)` — integer to binary string
- [x] `bool(val)` — convert to boolean (1/0)
- [x] `number(str)` — string to integer

### File I/O Functions
- [x] `exists(path)` — check if file exists
- [x] `append(path, data)` — append to file
- [x] `delete(path)` — delete file
- [x] `lines(path)` — read file as array of lines

### OS/System Functions
- [x] `time()` — unix timestamp (seconds)
- [x] `clock()` — monotonic nanoseconds
- [x] `sleep(seconds)` — pause execution
- [x] `args()` — command-line arguments as array
- [x] `env(name)` — get environment variable
- [x] `system(cmd)` — execute shell command

**Total: 28 new built-in functions, 51 tests passing**

---

## Phase 7 — Developer Tools (COMPLETE)
**Goal:** Tools for writing and debugging SEVEN code

- [x] REPL — interactive shell (`tools/repl`)
- [x] Formatter — auto-indent (`tools/fmt`, `--check` mode)
- [x] VS Code Extension — syntax highlighting, snippets (v0.2.0)
- [x] Linter — block matching, style checks, variable usage (`tools/lint`)
- [x] Profiler — compile/asm/execution timing (`tools/profile`)

## Phase 8 — Package Manager (SPM)
`spm init`, `spm install`, `spm publish`, registry.

## Phase 9 — Testing Framework (COMPLETE)
**Goal:** Assert-based testing with automated test runner

- [x] `assert(cond, msg)` — builtin keyword (runtime + codegen)
- [x] Test runner — auto-discovers `test_*.seven` files (`tools/test`)
- [x] Colored pass/fail/skip output with failure details
- [x] Assert-based test suite — math, strings, arrays, control flow, functions, conversions
- [x] 54 tests passing (7 new assert-based + 47 existing)

## Phase 10 — Documentation + Website
sevenlang.org, docs, playground, tutorials.

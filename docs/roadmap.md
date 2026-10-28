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

## Phase 8 — Package Manager (SPM) (COMPLETE)
**Goal:** Package management for SEVEN projects

- [x] `spm init` — create seven.pkg manifest
- [x] `spm install <pkg>` — install from local path, GitHub, or registry
- [x] `spm uninstall <pkg>` — remove installed packages
- [x] `spm list` — list installed packages
- [x] `spm info [pkg]` — show package/project info
- [x] `spm publish` — package as tarball for distribution
- [x] `spm search <query>` — search the registry
- [x] `spm update` — update all installed packages
- [x] `spm run <script>` — run named scripts from seven.pkg
- [x] Lock file (spm.lock) for reproducible installs
- [x] GitHub-based package registry (seven-packages org)
- [x] Example package (mathext) with fibonacci, is_prime, abs, min, max

## Phase 9 — Testing Framework (COMPLETE)
**Goal:** Assert-based testing with automated test runner

- [x] `assert(cond, msg)` — builtin keyword (runtime + codegen)
- [x] Test runner — auto-discovers `test_*.seven` files (`tools/test`)
- [x] Colored pass/fail/skip output with failure details
- [x] Assert-based test suite — math, strings, arrays, control flow, functions, conversions
- [x] 54 tests passing (7 new assert-based + 47 existing)

## Phase 10 — Advanced Features (COMPLETE)
**Goal:** Bitwise operators, string indexing, ord/chr, substr

- [x] Bitwise operators (band, bor, bxor, bnot, shl, shr)
- [x] `substr(str, start, len)` — substring extraction
- [x] `ord(char)` / `chr(code)` — character ↔ ASCII conversion
- [x] String indexing with `char_at`
- [x] 60+ tests passing

---

## Phase 11 — Self-Hosted Compiler Modules (COMPLETE)
**Goal:** Full self-hosted compiler pipeline written in SEVEN

- [x] Self-hosted lexer (`src/self/lexer.seven`)
- [x] Self-hosted parser (`src/self/parser.seven`) — map-based AST
- [x] Self-hosted semantic analyzer (`src/self/analyzer.seven`)
- [x] Self-hosted IR generator (`src/self/irgen.seven`)
- [x] Self-hosted code generator (`src/self/codegen.seven`) — IR → x86-64 assembly
- [x] Full test coverage for each module

---

## Phase 12 — Imports & Compiler Pipeline (COMPLETE)
**Goal:** `use` keyword for imports, full pipeline driver

- [x] `use "path.seven"` — import/include with duplicate-guard
- [x] `compile.seven` — connects all 5 modules into end-to-end pipeline
- [x] Runtime hardening: heap 16MB → 64MB, OOM error messages, variable overflow checking
- [x] Interpreter buffer increases: 4096 variables, 524288 scope stack entries
- [x] 70 tests passing (zero regressions)

---

## Phase 13 — LLVM Backend (COMPLETE)
**Goal:** High-performance native compilation via LLVM

### 13a — LLVM Setup + Basic Features
- [x] C lexer (`llvm_lexer.c`) — tokenizes .seven source
- [x] LLVM codegen (`llvm_codegen.c`) — generates LLVM IR
- [x] Variables, math, if/elif/else, while, repeat, func, assert
- [x] Expression precedence: primary → mul → add → compare → and → or
- [x] 33x faster than NASM interpreter (0.05s vs 1.67s on 100M loop benchmark)

### 13b — Strings & Arrays
- [x] String concatenation with `+` operator
- [x] String comparison with `is`/`isnt`
- [x] Array literals `[1, 2, 3]`
- [x] Array subscript `arr[i]`
- [x] `each`/`as` loop over arrays
- [x] `push`/`pop` statements
- [x] Method syntax: `.len()`, `.upper()`, `.lower()`, `.push()`, `.sort()`, etc.

### 13c — Standard Library (28 builtins)
- [x] C runtime library (`llvm_runtime.c`) — all stdlib functions
- [x] String: `len`, `upper`, `lower`, `trim`, `contains`, `replace`, `substr`, `find`, `count`, `pad`, `ord`, `chr`, `char_at`, `str`
- [x] Math: `pow`, `abs`, `clamp`, `sign`, `gcd`, `sum`, `avg`
- [x] Arrays: `range`, `fill`, `join`, `unique`, `sort`, `reverse`, `slice`, `get`, `set`, `insert`, `remove`, `concat`
- [x] Conversion: `hex`, `bin`, `bool`, `number`, `int`, `str`
- [x] File I/O: `file_exists`, `file_read`, `write`, `delete`, `append`
- [x] OS: `time`, `clock_ns`, `env`, `system`, `sleep`
- [x] I/O: `ask`

### 13d — Cross-Platform Build
- [x] `--target <triple>` flag for cross-compilation
- [x] Runtime object file pre-compiled for linking
- [x] Path handling for spaces in directory names

### 13e — CLI Integration
- [x] `--asm` flag delegates to NASM backend
- [x] `--version` / `--help` flags
- [x] `--emit-ir` for LLVM IR inspection
- [x] Version bump to v1.4

---

## Phase 14 — Platform Support (IN PROGRESS)
**Goal:** Native support on all major platforms

### 14a — Windows Native (COMPLETE)
- [x] Cross-platform runtime (`llvm_runtime.c`) — Win32 API + POSIX
- [x] Cross-platform codegen (`llvm_codegen.c`) — exe detection, clang detection, linking
- [x] Cross-platform CLI (`llvm_main.c`) — `--asm` delegation, `.exe` extension
- [x] CMake build system (`CMakeLists.txt`) for Windows builds
- [x] `build.bat` — auto-detects LLVM, configures and builds
- [x] `install-windows.bat` — one-command setup (installs LLVM + CMake + builds)
- [x] Portable format specifiers (`PRId64`/`PRIx64`) for MSVC compatibility
- [x] Windows path handling (backslash + forward slash)

### 14b — Future
- [ ] macOS native builds (Apple Silicon + x86_64)
- [ ] Linux ARM64 builds
- [ ] Package manager integration (winget, brew, apt)

---

## Future — Performance
- [ ] LLVM optimization passes (O2/O3)
- [ ] Constant folding (compile-time evaluation of literal expressions)
- [ ] Register-based expression evaluation for NASM backend
- [ ] Peephole optimization for NASM (redundant push/pop removal)
- [ ] Loop invariant hoisting

## Future — Features
- [ ] Custom backend (like Rust's Cranelift — eventually replace LLVM)
- [ ] WebAssembly target (`--target wasm32`)
- [ ] Documentation website: sevenlang.org, tutorials
- [ ] Garbage collector or arena-reset allocator
- [ ] Self-hosting loop close: compile real `.seven` programs end-to-end

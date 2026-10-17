# SEVEN Development Roadmap

## Phase 1 — Mini Bootstrap Compiler (CURRENT)
**Duration:** 3-4 months
**Language:** x86-64 NASM Assembly
**Goal:** First working `seven build main.seven → executable`

### Step 1.1 — Lexer (`src/lexer.asm`)
- [ ] File I/O (open, read, close)
- [ ] Whitespace / comment skipping (`!!`)
- [ ] Identifier + keyword scan
- [ ] Number literals (int, hex `0x`, binary `0b`, float)
- [ ] String literals with escape sequences
- [ ] Operator scan (single + multi-char: `**`, `==`, `!=`, `<=`, `>=`, `<<`, `>>`)
- [ ] Token emit + debug print
- [ ] Line/column tracking for error messages

### Step 1.2 — Parser (`src/parser.asm`)
- [ ] Token stream (peek/consume)
- [ ] Expression precedence climbing
- [ ] Statement dispatch
- [ ] AST bump allocator
- [ ] Grammar coverage: assign, show, if/elif/else, repeat, while, func/return, arrays
- [ ] Error reporting (line/col + expected/found)

### Step 1.3 — Code Generator (`src/codegen.asm`)
- [ ] Emit `section .text` / `.data` / `.bss`
- [ ] `_start` prologue + exit epilogue
- [ ] Integer arithmetic
- [ ] Variables (stack-frame slot per var)
- [ ] Control flow (if/repeat/while + unique labels)
- [ ] Functions (call/ret, argument passing via SysV AMD64 ABI)
- [ ] `show` runtime (write syscall)
- [ ] `ask` runtime (read syscall)
- [ ] String literal pool

### Step 1.4 — Runtime (`src/runtime.asm`)
- [ ] itoa / atoi
- [ ] print_int / print_string / println
- [ ] read_line
- [ ] arena allocator (bump)
- [ ] error_exit(msg)

### Step 1.5 — Testing
- [ ] Every file in `tests/` compiles and runs
- [ ] Golden-output comparison
- [ ] Error-path tests (syntax errors, div-by-zero, etc.)

**End of Phase 1:** `./seven build examples/hello.seven` produces a working native executable.

---

## Phase 2 — Self-Hosted Compiler
Rewrite lexer/parser/codegen in SEVEN itself. Add optimizer.

## Phase 3 — Standard Library
math, string, array, file, time, os, data structures.

## Phase 4 — Developer Tools
REPL, formatter, linter, debugger, VS Code LSP, profiler.

## Phase 5 — Package Manager (SPM)
`spm init`, `spm install`, `spm publish`, registry.

## Phase 6 — Testing Framework
Unit tests, benchmarks, coverage, mocks.

## Phase 7 — Documentation + Website
sevenlang.org, docs, playground, tutorials.

## Phase 8 — Domain Libraries
Web, DB, AI/ML, GUI, Networking, Crypto, Graphics.

## Phase 9 — Community + Ecosystem
GitHub, Discord, meetups, RFC process.

## Phase 10 — Enterprise + Future
Cross-compile, FFI, JIT, GPU, WASM, RISC-V, Quantum.

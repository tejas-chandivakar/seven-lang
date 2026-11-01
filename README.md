# SEVEN Language

> **Fast as Assembly. Simple as Python. Powered by LLVM.**

**S**peed · **E**asy · **V**ersatile · **E**fficient · **N**ative

🌐 [Website](https://seven-language.github.io) · 📦 [Download](https://github.com/tejas-chandivakar/seven-lang/releases) · 📖 [Docs](https://seven-language.github.io/docs.html)

Created by **Tejas Chandivakar**

---

## What is SEVEN?

SEVEN is a compiled, general-purpose programming language with an LLVM backend. It gives you Python's readability with native machine code performance — no VM, no garbage collector, no runtime overhead.

- Compiles to native x86-64 via LLVM
- LLVM optimization passes (-O0 to -O3)
- WebAssembly target support
- Self-hosted compiler (written in SEVEN itself)
- 1600x faster than Python on compute benchmarks

## Hello World

```
!! hello.seven
show "Hello, SEVEN!"

name = ask "Your name: "
show "Hello, " + name
```

```bash
seven run hello.seven
```

## Install

### Windows (Recommended — Installer)

Download and run the installer — includes compiler + LLVM runtime, automatically adds to PATH:

📥 **[Download SEVEN v1.0.0 (Windows x64, 19 MB)](https://github.com/tejas-chandivakar/seven-lang/releases/download/v1.0.0/seven-setup-1.0.0-win64.exe)**

Requires: Windows 10+ (64-bit), [LLVM](https://github.com/llvm/llvm-project/releases) pre-installed.

### Linux / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/tejas-chandivakar/seven-lang/main/install.sh | sh
```

### Build from Source

```bash
git clone https://github.com/tejas-chandivakar/seven-lang.git
cd seven-lang

# Linux
make

# Windows
install-windows.bat
```

## Usage

```bash
seven run hello.seven              # Compile and run
seven build hello.seven -o hello   # Build executable
seven build hello.seven --emit-ir  # View LLVM IR output
```

## Speed Comparison

100 million integer loop iterations:

| Language | Time | vs Python |
|----------|------|-----------|
| **SEVEN** | **0.003s** | **1600x faster** |
| Rust | 0.004s | 1250x faster |
| C# .NET | 0.12s | 41x faster |
| Node.js | 0.52s | 9.6x faster |
| Perl | 1.75s | 2.8x faster |
| Python | 5.0s | baseline |

SEVEN uses LLVM backend with optimizations enabled by default.

## Repository Layout

```
seven-lang/
├── src/           Compiler source (NASM bootstrap + LLVM backend)
├── self/          Self-hosted compiler (written in SEVEN)
├── site/          Website (seven-language.github.io)
├── installer/     Windows installer (Inno Setup)
├── examples/      Example .seven programs
├── tests/         Test suite (70+ tests)
├── docs/          Language specification
├── editor/        VS Code syntax extension
├── build/         Compiled artifacts
└── tools/         Build tools
```

## Documentation

- 🌐 **[Online Docs](https://seven-language.github.io/docs.html)** — Full language reference
- 📝 **[Syntax Guide](docs/syntax.md)** — Quick reference
- 📋 **[Language Spec](docs/spec.md)** — Formal specification
- 🗺️ **[Roadmap](docs/roadmap.md)** — Development plan

## License

MIT

# SEVEN Language

> **Fast as Assembly. Simple as Python. Powerful as C++. Ready for everything.**

**S**peed · **E**asy · **V**ersatile · **E**fficient · **N**ative

Created by **Tejas Chandivakar**

---

## What is SEVEN?

SEVEN is a compiled, general-purpose programming language that aims to give you Python's readability with Assembly's raw speed. Programs are written in `.seven` files and compiled directly to native machine code — no VM, no garbage collector, no runtime overhead.

## Hello World

```
!! hello.seven
show "Hello, SEVEN!"

name = ask "Taru naam: "
show "Namaste, " + name
```

Build and run:
```bash
seven build hello.seven
./hello
```

## Repository Layout

```
E:\SEVEN language\
├── src/          Bootstrap compiler in x86-64 NASM Assembly
│   ├── lexer.asm
│   ├── parser.asm
│   └── codegen.asm
├── examples/     Example .seven programs
├── tests/        Language feature tests
├── docs/         spec.md, syntax.md, roadmap.md
├── build/        Compiled artifacts (git-ignored)
├── tools/        Third-party tools (NASM etc.)
├── chat-reference.md   Complete language reference
├── Makefile
└── README.md
```

## Building the Compiler (Linux / WSL)

```bash
sudo apt install nasm
cd "/mnt/e/SEVEN language"
make
./build/seven-lexer examples/hello.seven
```

## Documentation

- **Spec** — `docs/spec.md`
- **Syntax quick reference** — `docs/syntax.md`
- **Roadmap** — `docs/roadmap.md`
- **Full reference** — `chat-reference.md`

## License

TBD.

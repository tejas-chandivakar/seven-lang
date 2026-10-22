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

## Install (Linux / WSL — no build tools needed)

One line — downloads a prebuilt static binary (~53 KB), no NASM required:

```bash
curl -fsSL https://raw.githubusercontent.com/tejas-chandivakar/seven-lang/main/install.sh | sh
```

Then run a program:

```bash
echo 'show "Hello from SEVEN!"' > hello.seven
seven run hello.seven
```

Options: `SEVEN_BIN_DIR=/usr/local/bin` to change the install directory,
`SEVEN_VERSION=v1.0.0` to pin a version.

## Building from source (Linux / WSL)

```bash
sudo apt install nasm
cd "/mnt/e/SEVEN language"
make            # builds build/seven
make dist       # packages dist/seven + tarball + checksums
./build/seven run examples/hello.seven
```

## Documentation

- **Spec** — `docs/spec.md`
- **Syntax quick reference** — `docs/syntax.md`
- **Roadmap** — `docs/roadmap.md`
- **Full reference** — `chat-reference.md`

## License

TBD.

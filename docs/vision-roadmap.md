# SEVEN — Vision Roadmap: A General-Purpose, Everywhere Language

> Goal: make SEVEN usable across systems/OS, drivers, AI/ML, IoT, computer
> vision, application software, mobile, and web — and adopted by a real
> community.
>
> This document is an **honest engineering + adoption plan**, not marketing.
> It states what SEVEN is today, the hard gaps, the few decisions that matter
> most, and a phased path. Dates are deliberately omitted — progress depends
> on contributors, not calendar.

---

## 0. Where SEVEN is today (honest baseline)

**Real achievements** (do not undersell these):
- Self-hosted compiler, bootstrapped from hand-written x86-64 NASM.
- Working interpreter (`seven run`) + compiler (`seven build`).
- 57 tests passing; stdlib of ~48 builtins; try/catch/error; dev tools
  (REPL, fmt, lint, profile, test runner); VS Code extension; website.

**Architectural facts that limit "everywhere":**
| Area | Today | Why it blocks the vision |
|------|-------|--------------------------|
| Frontend | Single-pass, **no AST/IR** | Can't type-check, optimize, or add advanced features cleanly |
| Types | Dynamically typed | Systems/embedded/ML need static types + sizes for safety & speed |
| Numbers | Integers only, **no floats** | AI/ML/vision/graphics are impossible without f32/f64 + SIMD |
| Backend | Hand-written x86-64 NASM, **Linux only** | One CPU, one OS. "Everywhere" needs ARM, RISC-V, WASM |
| Memory | Bump allocator, **no free** | Leaks; unusable for long-running or memory-constrained targets |
| Interop | **No C FFI** | Must reimplement the whole world instead of reusing it |
| Modules | None | No namespaces, no real packages, no large-codebase scaling |
| Concurrency | None | Servers, drivers, real-time all need it |

**Bottom line:** SEVEN is an excellent *educational/hobby* language with a rare
feat (self-hosting). To be general-purpose it needs a compiler-architecture
rebuild. That is normal — Rust, Swift, and Zig all went through this.

---

## 1. The four decisions that matter most

If only four things are done, do these. Everything else is detail.

### Decision 1 — Retarget the backend to **LLVM** (or Cranelift/QBE)
Hand-writing NASM for every platform does not scale to "everywhere."
Emitting **LLVM IR** gives, essentially for free:
- x86-64, **ARM64 (phones, Macs, servers), RISC-V (embedded), WebAssembly (web)**
- World-class optimization (the thing that makes a language *fast enough* to
  be taken seriously)
- A stable path other serious languages already use (Rust, Swift, Julia, Clang)

Keep the existing NASM backend as the bootstrap/teaching path. Add LLVM as the
production backend. This single decision unlocks systems, embedded, mobile, and
web targets at once.

*Lighter alternatives if LLVM is too heavy:* **QBE** (tiny, ~x86/ARM/RISC-V) or
**Cranelift** (fast, WASM-friendly). Good for a smaller team.

### Decision 2 — A **static type system** with inference
- Sized primitives: `i8..i64`, `u8..u64`, `f32`, `f64`, `bool`, `char`, pointers.
- Structs, enums (sum types), generics, interfaces/traits.
- Type **inference** so code still reads like today's SEVEN (`x = 5`), but the
  compiler knows the types. This is what makes code both *readable* and *fast*,
  and it is what powers autocomplete, refactoring, and catching bugs early.
- Requires the AST + typed IR (Phase 11 below).

### Decision 3 — **C FFI** (the cheat code)
The highest-leverage feature in the whole plan. With a clean C ABI interop,
SEVEN *instantly* reuses the existing universe instead of rewriting it:
- AI/ML → BLAS, cuBLAS, cuDNN, ONNX Runtime
- Vision → OpenCV, libjpeg, FFmpeg
- Systems → libc, OpenSSL, SQLite, zlib
- Mobile → platform SDKs via their C layers
Without FFI, every domain means re-implementing decades of libraries. With it,
SEVEN becomes useful in weeks, not years.

### Decision 4 — Pick **ONE beachhead**, not all nine at once
Languages that try to be "best at everything on day one" die. Winners pick a
niche where they are *clearly the best choice*, win it, then expand:
- Rust → "memory-safe systems" → then everywhere
- Go → "simple network services" → then everywhere
- Python → "scripting/glue" → then ML
Recommended beachhead for SEVEN: **"the most readable systems/embedded
language"** — it plays to the existing strengths (compiles to native, no GC,
inline asm, English-like syntax). See §4 for the choice.

---

## 2. Foundation phases (must come before any domain work)

These rebuild the compiler into something extensible. Order matters.

### Phase 11 — AST + Typed IR
Replace single-pass codegen with: Lexer → Parser → **AST** → Semantic analysis
→ **Typed IR** → Backend. Everything below depends on this.

### Phase 12 — Static type system + inference
Sized numeric types, `f32`/`f64` (fixes the float gap), structs, enums,
generics, traits, type inference. Dynamic mode can remain for scripting.

### Phase 13 — LLVM backend + multi-target
Emit LLVM IR. Add cross-compilation: `seven build --target arm64`,
`--target wasm32`, `--target riscv32`. Keep NASM backend for bootstrap.

### Phase 14 — Memory model
Pick ONE and commit: (a) ownership/borrow (Rust-style, no GC — best for
systems/embedded), (b) ARC (Swift-style), or (c) optional GC. Recommendation:
**ownership + optional GC mode**, so systems code stays zero-overhead but
scripting stays easy.

### Phase 15 — C FFI
`extern "c"` declarations, struct layout control, calling conventions, linking
against `.a`/`.so`/`.dylib`. Auto-binding generator from C headers.

### Phase 16 — Module & package system
Namespaces, `import`, visibility, plus finish **SPM** (SEVEN Package Manager)
with a real registry, semantic versioning, and lockfiles.

### Phase 17 — Concurrency
`async`/`await`, lightweight tasks, channels, threads, atomics. Needed by
servers, drivers, and real-time code.

---

## 3. Domain tracks (what each vertical actually requires)

Each builds on the foundation above. "Min bar" = the realistic minimum to be
taken seriously by practitioners in that field.

### A. Systems / OS / Drivers  *(closest to today's strengths)*
- **Needs:** freestanding/`no_std` mode (no libc, no OS), raw pointers,
  `volatile`, MMIO, custom linker sections, interrupt handlers, inline asm
  (✅ already have `asm:`), stable ABI.
- **Min bar:** boot a bare-metal "hello" on real hardware or QEMU; write a
  simple device driver; link with no runtime.
- **Depends on:** Phases 11–14.

### B. IoT / Embedded
- **Needs:** cross-compile to ARM Cortex-M / RISC-V / ESP32 / AVR; tiny
  binaries; no/!small heap; deterministic timing; HAL bindings.
- **Min bar:** blink an LED on an ESP32/STM32 board; binary under a few KB.
- **Depends on:** 11–15 (FFI to vendor HALs).

### C. AI / ML
- **Needs:** `f32`/`f64` (Phase 12), **SIMD/vectorization**, N-dim arrays /
  tensors, **GPU via FFI** (CUDA/ROCm/Metal) or bindings to BLAS/ONNX,
  ideally Python interop (ML ecosystem is Python).
- **Min bar:** train a small MLP on MNIST at a speed comparable to NumPy;
  call into an existing BLAS/ONNX via FFI.
- **Depends on:** 11–13, 15. *Reality: bind to existing GPU libs — do not
  rewrite CUDA.*

### D. Computer Vision
- **Needs:** everything in ML + image buffers, camera I/O, OpenCV/FFmpeg
  bindings, SIMD image kernels.
- **Min bar:** load an image, run a filter/edge-detector at usable FPS; call
  OpenCV via FFI.
- **Depends on:** C + 15.

### E. Application Software (desktop/CLI)
- **Needs:** rich stdlib (collections, regex, datetime, JSON, HTTP),
  GUI bindings (GTK/Qt via FFI), good error handling (✅ have try/catch).
- **Min bar:** ship a real cross-platform CLI tool and a small GUI app.
- **Depends on:** 13, 15, 16.

### F. Web Development
- **Backend:** async HTTP server (Phase 17), DB drivers (via FFI), JSON,
  routing, TLS.
- **Frontend:** **compile to WebAssembly** (Phase 13) — this is the key target;
  DOM bindings.
- **Min bar:** a REST API server + a WASM frontend demo, both in SEVEN.
- **Depends on:** 13, 15, 16, 17.

### G. Mobile OS / Mobile apps  *(hardest — do last)*
- **Needs:** ARM64; interop with Swift/ObjC (iOS) and Kotlin/Java via JNI
  (Android); UI framework bindings; app packaging (`.ipa`/`.apk`); platform
  signing.
- **Min bar:** a "hello" app running on a real Android/iOS device, logic in
  SEVEN, UI via platform bridge.
- **Depends on:** 13, 15, plus heavy platform-specific work. *Even Rust/Kotlin
  find this hard — expect this to be a long tail.*

**Dependency summary:** Foundation (11–17) → A/B (systems/embedded) and E
(apps) come first and cheapest → C/D (ML/vision) and F (web) next → G (mobile)
last.

---

## 4. Recommended sequencing (what to actually do)

1. **Phase 11 (AST/IR)** — unblocks everything. Non-negotiable first step.
2. **Phase 12 (types + floats)** — fixes the single most-requested gap.
3. **Phase 13 (LLVM, multi-target + WASM)** — "everywhere" becomes real here.
4. **Phase 15 (C FFI)** — reuse the world; makes every domain cheap.
5. **Beachhead = Systems/Embedded (tracks A+B)** — plays to current strengths
   (native, no GC, inline asm, readable). Win this first.
6. Then **Web (F)** via WASM + async, then **ML/Vision (C/D)** via FFI, then
   **Mobile (G)**.

Memory model (14), modules (16), concurrency (17) slot in as each track needs
them.

---

## 5. Adoption & fame track (parallel — technical quality is necessary but NOT sufficient)

Most technically-good languages die unknown. Fame is its own engineering:

- **One killer story.** A sentence that makes a developer try it today.
  e.g. *"The readability of Python with the speed and control of C — compiles
  to native and WASM."* Be the obvious best choice for ONE thing first.
- **Dogfood loudly.** Build impressive real things *in* SEVEN (a small OS, a
  WASM web app, an embedded demo). Show, don't tell.
- **Lower the on-ramp.** Playground (✅ started), `rustup`-style installer,
  10-minute "build something real" tutorial, example gallery.
- **Package registry with real packages.** A language with no libraries stays a
  toy. Seed SPM with genuinely useful crates (HTTP, JSON, regex, math).
- **Stability promise.** Ship a real **1.0** with a backward-compatibility
  guarantee. Churn scares adopters away.
- **Community surfaces.** Public repo (✅), Discord/forum, "awesome-seven" list,
  good first issues, responsive maintainership, a visible roadmap (this file).
- **Proof & comparisons.** Honest benchmarks vs C/Rust/Go/Python; migration
  guides; case studies.
- **Patience.** Rust took ~9 years to 1.0 and mainstream traction. This is a
  long game won by consistency.

---

## 6. Risks & honest caveats

- **Scope is enormous.** All nine domains is 5–10+ years of work for a team.
  Solo, pick the beachhead and go deep — breadth can come from the community.
- **FFI first, rewrites later.** Do not reimplement CUDA/OpenCV/libc. Bind.
- **LLVM is a big dependency** to learn and ship. QBE/Cranelift are smaller if
  resources are tight.
- **Mobile OS is the hardest target** and gives the least leverage early —
  schedule it last.
- **A language's value ≈ its ecosystem.** Budget as much energy for registry,
  docs, and community as for the compiler.

---

## 7. One-line summary

> Rebuild the frontend (AST + types + floats), retarget to **LLVM** for
> multi-platform + WASM, add **C FFI** to reuse the world, win **one beachhead
> (systems/embedded)** first, and invest in registry + docs + community in
> parallel. That is the realistic path from "impressive hobby language" to
> "language people actually use everywhere."

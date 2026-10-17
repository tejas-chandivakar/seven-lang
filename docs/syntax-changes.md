# SEVEN Syntax — Decision Log

Records all finalized syntax decisions after the initial `chat-reference.md`.

---

## 2026-09-28 — Comments

- `!!` — single-line comment
- `!!!  ...  !!!` — multi-line comment (no nesting)

```
!! single-line
x = 10  !! inline
!!!
   Multi-line
   Andar !! pan chalse
!!!
```

---

## 2026-09-28 — Batch 1 Decisions (Sections 2-23)

### 2. Print — Multiple Arguments  ✅ BOTH ALLOWED
```
show "Name:", name       !! comma-separated with auto space
show "Name: " + name     !! concat with +
```

### 3. Print — No Newline  ✅ `show.raw`
```
show.raw "loading..."    !! no newline
show "done!"             !! with newline
```

### 4. String Interpolation  ✅ AUTO (no prefix)
Every double-quoted string auto-interpolates `{var}`:
```
show "Hi {name}, age {age}"
show "Result: {x + y}"
```
Escape a literal brace with `{{` and `}}`.

### 5. Input — `ask` Return Type  ✅ AUTO-DETECT
```
age = ask "Age: "        !! auto-int if numeric
pi = ask "Pi: "          !! auto-float if decimal
name = ask "Name: "      !! string
```

### 6. Error Print (stderr)  ✅ `err` keyword
```
err "Something broke!"
err "Line " + lineno
```

### 7. Hidden Input  ✅ `secret` keyword
```
pwd = secret "Password: "
```

### 8. Compound Assignment  ❌ SKIP
Keep verbose form:
```
x = x + 1
x = x * 2
```

### 9. Integer Division  ✅ `//` operator
```
x = 10 // 3       !! = 3   (int)
y = 10 / 3        !! = 3.33 (float)
```

### 10. `in` Operator  ✅ ADD
```
if x in [1, 2, 3]
    show "found"
end

if "a" not in word
    show "no a"
end
```

### 11. Ternary  ❌ SKIP
Use full if/end only.

### 12. Loop Index (enumerate)  ✅ INDEX FIRST
```
each nums as i, x
    show i, x
end
```

### 13. Named Function Arguments  ❌ SKIP
Positional only:
```
connect("localhost", 8080)
```

### 14. Variable Arguments  ✅ `many` keyword
```
func sum_all(many nums)
    return sum(nums)
end

sum_all(1, 2, 3, 4, 5)
```

### 15. Type Annotations  ❌ SKIP
Dynamic only:
```
func add(a, b)
    return a + b
end
```

### 16. Negative Indexing  ✅ ADD
```
nums[-1]        !! last
nums[-2]        !! second last
```

### 17. Slicing  ✅ FUNCTIONS
No bracket-slice syntax; use functions:
```
slice(nums, 1, 5)        !! idx 1..4
step(nums, 2)            !! every 2nd
reverse(nums)            !! reversed copy
```

### 18. Throw Error  ✅ `error` keyword
```
error "bad input"
error Error("details")
```

### 19. Assert  ❌ SKIP
Use if + error manually:
```
if x <= 0
    error "must be positive"
end
```

### 20. String Quotes  ✅ BOTH + TRIPLE
```
s1 = 'hello'
s2 = "hello"
s3 = """
Multi-line
string
"""
```
Note: single-char literals: use explicit `char` type or `'A'` context. If ambiguous, prefer double quotes.

### 21. String Methods  ✅ METHOD STYLE
```
s.upper()
s.split(" ").join("-")
s.replace("a", "b").trim()
```

### 22. Class — `this`  ✅ `this` keyword
```
class Dog
    name = ""
    func bark()
        show this.name
    end
end
```

### 23. Static Methods  ✅ `shared` keyword
```
class Math
    shared func pi()
        return 3.14
    end
end

Math.pi()
```

---

## 2026-09-30 — Block Syntax: No `:`, Keep `end`

**Decision:** Remove `:` as block-start marker. Keep `end` as block closer.

**Before:**
```
if x > 5:
    show "big"
end

func add(a, b):
    return a + b
end
```

**After:**
```
if x > 5
    show "big"
end

func add(a, b)
    return a + b
end
```

**Rationale:**
- Minimalist syntax — fewer characters to type
- `end` provides safety for block boundaries (copy-paste safe, no indent-only bugs)
- No ambiguity — `end` clearly marks where blocks close
- Beginner-friendly — one less symbol to learn

---

## 2026-09-30 — Mode System: `mode hybrid` + `mode natural`

**Decision:** Two language modes declared at file top. Affects only array mutation syntax.

```
mode hybrid       !! default — function-style array ops
mode natural      !! English-style array ops
```

**Hybrid mode (default):**
```
push(nums, 4)
remove(nums, 0)
insert(nums, 1, 99)
pop(nums)
```

**Natural mode:**
```
add 4 to nums
remove 0 from nums
insert 99 at 1 in nums
pop from nums
```

**Rationale:**
- Gives users a choice — beginners prefer natural, experienced devs prefer hybrid
- Both produce identical compiled output
- Mode is file-scoped — different files in a project can use different modes
- Only 4 array operations differ — everything else is identical
- Compiler impact minimal — 4 extra parse rules in natural mode

---

## 2026-09-30 — I/O Commands: No Parentheses

**Decision:** Built-in I/O commands (`show`, `ask`, `err`, `write`, `read`, `secret`) do NOT need parentheses. User-defined functions and built-in utility functions (`push`, `len`, `slice`, etc.) DO need parentheses.

**Rule:** Language commands = no `()`. Functions = `()`.

```
!! I/O commands — no parentheses
show "Hello"
name = ask "Name"
err "Error!"
write "file.txt", "data"
content = read "file.txt"

!! Functions — parentheses required
push(nums, 4)
x = len(nums)
y = slice(nums, 1, 3)
result = add(a, b)
```

**Rationale:**
- `show "Hello"` feels more natural than `show("Hello")` for beginners
- Clear distinction: commands (I/O) vs functions (computation)
- Compile speed: negligible difference (~1-3%) — commands are a fixed keyword list

---

## Keyword Additions

New keywords introduced by these decisions:
- `err` (stderr print)
- `secret` (hidden input)
- `in`, `not in` (membership)
- `many` (variadic parameter)
- `error` (throw)
- `this` (instance ref)
- `shared` (static method)
- `mode`, `hybrid`, `natural` (mode system)
- `times` (optional in `repeat N times`)

Removed / unused:
- `raise`, `throw`, `fail` (used `error` instead)
- `assert` (skipped)
- `self` (using `this`)
- `static` (using `shared`)

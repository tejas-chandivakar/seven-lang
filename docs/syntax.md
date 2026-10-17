# SEVEN Syntax Quick Reference

**Updated:** 2026-09-30 — Mode system, No `:` block start, `end` block close.
**File extensions:** `.seven` (primary), `.sev`, `.sv7`, `.s7`
See `syntax-changes.md` for decision rationale.

---

## Mode Declaration

```
mode hybrid       !! default — array ops use function style: push(list, x)
mode natural      !! array ops use English style: add x to list
```

No declaration = `mode hybrid` by default. Mode affects only array operations — everything else is identical.

---

## Comments
```
!! single-line comment
x = 10  !! inline comment

!!!
   Multi-line comment
   Andar !! pan chalse
!!!
```

## Variables
```
x = 10                !! int (auto)
name = "Tejas"        !! string (auto)
pi = 3.14             !! float (auto)
flag = true           !! bool
nothing = null

const MAX = 100       !! constant
```

## Strings & Interpolation
```
s1 = 'hello'          !! both quotes OK
s2 = "hello"
m  = """
Multi-line
"""

!! Auto-interpolation with {var}
show "Hi {name}, age {age}"
show "Result: {x + y}"
show "Literal brace: {{ }}"

!! Method style
s.upper()
s.split(" ").join("-")
s.replace("a", "b").trim()
```

## Output (no parentheses — language commands)
```
show "Hello"                    !! print + newline
show "Name:", name, "Age:", age !! comma-separated, auto space
show.raw "loading..."           !! no newline
err "Error message!"            !! to stderr
```

## Input (no parentheses — language commands)
```
name = ask "Name: "             !! string
age = ask "Age: "               !! auto-int if numeric
pi  = ask "Pi: "                !! auto-float if decimal
pwd = secret "Password: "       !! hidden input
```

## Math
```
+  -  *  /  %  **
//        !! integer division
&  |  ^  ~  <<  >>
```
No compound assignment — use `x = x + 1`.

## Comparison & Logic
```
==  !=  <  >  <=  >=
and  or  not
in   not in           !! membership: x in [1,2,3]
```

## If
```
if x > 5
    show "big"
elif x == 5
    show "equal"
else
    show "small"
end
```

## Loops
```
repeat 5
    show "hi"
end

repeat 5 times as i
    show i
end

each nums as i, x      !! index first, value second
    show i, x
end

while x < 10
    x = x + 1
end
```

Loop control:
```
skip    !! continue
stop    !! break
```

## Functions (parentheses — function calls)
```
func add(a, b)
    return a + b
end

!! Default parameters
func connect(host, port = 8080)
    show "{host}:{port}"
end

!! Variable arguments
func sum_all(many nums)
    return sum(nums)
end

sum_all(1, 2, 3, 4, 5)
```

No named args, no type annotations.

## Arrays

### mode hybrid (default)
```
nums = [1, 2, 3]
push(nums, 4)
pop(nums)
insert(nums, 1, 99)
remove(nums, 0)
```

### mode natural
```
nums = [1, 2, 3]
add 4 to nums
pop from nums
insert 99 at 1 in nums
remove 0 from nums
```

### Common (both modes)
```
show nums[0]
show nums[-1]           !! last (negative index OK)
show nums[-2]           !! second last

slice(nums, 1, 5)       !! subarray
step(nums, 2)           !! every 2nd
reverse(nums)           !! reversed copy
len(nums)               !! length
```

## Files (no parentheses — language commands)
```
write "file.txt", "data"
data = read "file.txt"
add "file.txt", "more data"
lines = readlines "file.txt"
```

## Error Handling
```
try
    x = 10 / 0
catch
    err "division by zero"
done
    show "cleanup"
end

!! Throw error
error "bad input"
error Error("with details")
```

No `assert` — use `if + error`.

## Classes
```
class Dog
    name = ""
    sound = ""

    func bark()
        show "{this.name} says {this.sound}"
    end
end

!! Inheritance
class Puppy extends Dog
    age = 0
end

!! Static method (shared)
class Math
    shared func pi()
        return 3.14
    end
end

Math.pi()
```

---

## Keyword Summary

**New keywords (Batch 1):**
`err`, `secret`, `in`, `not in`, `many`, `error`, `this`, `shared`

**Mode system keywords:**
`mode`, `hybrid`, `natural`

**Reserved (not used):**
`raise`, `throw`, `fail`, `assert`, `self`, `static`

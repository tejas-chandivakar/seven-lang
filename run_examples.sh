#!/bin/bash
# SEVEN Language — HTML Syntax Reference Examples Runner
cd "/mnt/e/SEVEN language"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

run_example() {
    local title="$1"
    local code="$2"
    local tmpname="__ex_tmp"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${YELLOW}▶ $title${RESET}"
    echo -e "${CYAN}Code:${RESET}"
    echo "$code"
    echo ""

    echo "$code" > "${tmpname}.seven"

    if ./build/seven "${tmpname}.seven" 2>/dev/null && \
       nasm -f elf64 -w-label-redef-late "${tmpname}.asm" -o "${tmpname}.o" 2>/dev/null && \
       ld "${tmpname}.o" build/runtime.o -o "${tmpname}" 2>/dev/null; then
        echo -e "${GREEN}Output:${RESET}"
        ./"${tmpname}"
    else
        echo -e "${RED}ERROR: compile failed${RESET}"
        ./build/seven "${tmpname}.seven"
    fi

    rm -f "${tmpname}.seven" "${tmpname}.asm" "${tmpname}.o" "${tmpname}"
    echo ""
}

echo -e "${YELLOW}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${YELLOW}║   SEVEN Language — Syntax Reference Examples  ║${RESET}"
echo -e "${YELLOW}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# 1. Variables + Math
run_example "1. Variables + Math" \
'x = 10
y = 3
show x + y
show x - y
show x * y
show x / y
show x % y'

# 2. String Interpolation
run_example "2. String Interpolation" \
'name = "Tejas"
lang = "SEVEN"
show "Hello {name}!"
show "Language: {lang}"'

# 3. String Methods
run_example "3. String Methods" \
's = "Hello SEVEN"
show s.upper()
show s.lower()
t = "  trim me  "
show t.trim()
show s.contains("SEVEN")
show s.replace("SEVEN", "World")'

# 4. If / Elif / Else
run_example "4. If / Elif / Else" \
'score = 85
if score >= 90
    show "Grade: A"
elif score >= 80
    show "Grade: B"
elif score >= 70
    show "Grade: C"
else
    show "Grade: F"
end'

# 5. While Loop
run_example "5. While Loop" \
'i = 1
while i <= 3
    show i
    i = i + 1
end'

# 6. Repeat Loop
run_example "6. Repeat Loop" \
'repeat 3
    show "hi"
end'

# 7. Arrays
run_example "7. Arrays" \
'nums = [10, 20, 30]
show nums[0]
show nums[-1]
push(nums, 40)
show len(nums)'

# 8. Each Loop
run_example "8. Each Loop" \
'fruits = ["apple", "banana", "mango"]
each fruits as f
    show f
end'

# 9. Each with Index
run_example "9. Each with Index" \
'fruits = ["apple", "mango"]
each fruits as i, f
    show i
    show f
end'

# 10. In Operator
run_example "10. In Operator" \
'nums = [1, 3, 5]
if 3 in nums
    show "found"
end
if 9 in nums
    show "nine found"
else
    show "nine not found"
end'

# 11. Slice / Reverse / Step
run_example "11. Slice / Reverse / Step" \
'arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
sl = slice(arr, 2, 6)
show sl[0]
show sl[1]
show sl[2]
show sl[3]
rv = reverse(arr)
show rv[0]
st = step(arr, 3)
show st[0]
show st[1]
show st[2]
show st[3]'

# 12. Basic Function
run_example "12. Basic Function" \
'func add(a, b)
    return a + b
end

result = add(10, 20)
show result'

# 13. Default Parameters
run_example "13. Default Parameters" \
'func greet(name, msg = "Hello")
    show msg
    show name
end

greet("Tejas")
greet("SEVEN", "Namaste")'

# 14. Variadic — many
run_example "14. Variadic — many" \
'func sum_all(many nums)
    total = 0
    each nums as n
        total = total + n
    end
    return total
end

show sum_all(1, 2, 3, 4, 5)'

# 15. Try / Catch
run_example "15. Try / Catch" \
'try
    show "before"
    error "something failed"
    show "after"
catch e
    show "caught:"
    show e
end
show "done"'

echo -e "${YELLOW}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${YELLOW}║           BADHA EXAMPLES COMPLETE!            ║${RESET}"
echo -e "${YELLOW}╚══════════════════════════════════════════════╝${RESET}"

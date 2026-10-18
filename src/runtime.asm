; ============================================================
; SEVEN Language - Runtime Library
; Linked into every compiled SEVEN program
; Architecture: x86-64 NASM Assembly (Linux ELF64)
; Author: Tejas Chandivakar
; ============================================================

section .data
    newline_char db 10
    space_char   db 32
    minus_char   db '-'
    true_str     db "true", 0
    true_str_len equ 4
    false_str    db "false", 0
    false_str_len equ 5
    null_str     db "null", 0
    null_str_len equ 4
    divzero_msg  db "Error: division by zero", 10
    divzero_len  equ $ - divzero_msg
    type_int_str db "int", 0
    type_str_str db "string", 0
    type_arr_str db "array", 0

section .bss
    int_buf      resb 21        ; buffer for int->string (max 20 digits + sign)
    read_buf     resb 1024      ; stdin read buffer
    read_len     resq 1         ; bytes read from stdin
    concat_buf   resb 4096      ; string concatenation buffer
    heap_base    resq 1         ; bump allocator base
    heap_ptr     resq 1         ; bump allocator current
    heap_end     resq 1         ; bump allocator end

section .text

; ============================================================
; rt_init — Initialize runtime (heap allocator)
; Uses mmap to allocate 1MB heap
; ============================================================
global rt_init
rt_init:
    push rbp
    mov rbp, rsp
    ; mmap(NULL, 1048576, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    mov rax, 9              ; sys_mmap
    xor rdi, rdi            ; addr = NULL
    mov rsi, 1048576        ; 1MB
    mov rdx, 3              ; PROT_READ | PROT_WRITE
    mov r10, 34             ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1              ; fd = -1
    xor r9, r9              ; offset = 0
    syscall
    mov [heap_base], rax
    mov [heap_ptr], rax
    add rax, 1048576
    mov [heap_end], rax
    pop rbp
    ret

; ============================================================
; rt_alloc — Bump allocate rdi bytes, return pointer in rax
; ============================================================
global rt_alloc
rt_alloc:
    mov rax, [heap_ptr]
    ; Align to 8 bytes
    add rdi, 7
    and rdi, ~7
    add rax, rdi
    cmp rax, [heap_end]
    jg .oom
    xchg rax, [heap_ptr]
    ret
.oom:
    ; Out of memory — exit with code 137
    mov rax, 60
    mov rdi, 137
    syscall

; ============================================================
; rt_print_str — Print string at rsi, length rdx to stdout
; ============================================================
global rt_print_str
rt_print_str:
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    syscall
    ret

; ============================================================
; rt_print_str_err — Print string to stderr
; ============================================================
global rt_print_str_err
rt_print_str_err:
    mov rax, 1
    mov rdi, 2              ; stderr
    syscall
    ret

; ============================================================
; rt_print_newline — Print newline to stdout
; ============================================================
global rt_print_newline
rt_print_newline:
    mov rax, 1
    mov rdi, 1
    mov rsi, newline_char
    mov rdx, 1
    syscall
    ret

; ============================================================
; rt_print_space — Print space to stdout
; ============================================================
global rt_print_space
rt_print_space:
    mov rax, 1
    mov rdi, 1
    mov rsi, space_char
    mov rdx, 1
    syscall
    ret

; ============================================================
; rt_print_int — Print integer in rdi to stdout
; Handles negative numbers
; ============================================================
global rt_print_int
rt_print_int:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rax, rdi
    mov r12, 0              ; negative flag

    ; Handle negative
    cmp rax, 0
    jge .positive
    neg rax
    mov r12, 1
.positive:
    ; Convert to string (reverse)
    lea rbx, [int_buf + 20]
    mov byte [rbx], 0       ; null terminator
.digit_loop:
    dec rbx
    xor rdx, rdx
    mov rcx, 10
    div rcx                 ; rax = quotient, rdx = remainder
    add dl, '0'
    mov [rbx], dl
    cmp rax, 0
    jne .digit_loop

    ; Add minus sign if negative
    cmp r12, 1
    jne .print_it
    dec rbx
    mov byte [rbx], '-'
.print_it:
    ; Calculate length
    lea rdx, [int_buf + 20]
    sub rdx, rbx            ; rdx = length
    mov rsi, rbx            ; rsi = start of string
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    syscall

    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; rt_print_bool — Print "true" or "false"
; rdi = 0 (false) or non-zero (true)
; ============================================================
global rt_print_bool
rt_print_bool:
    cmp rdi, 0
    je .print_false
    mov rsi, true_str
    mov rdx, true_str_len
    jmp .do_print
.print_false:
    mov rsi, false_str
    mov rdx, false_str_len
.do_print:
    mov rax, 1
    mov rdi, 1
    syscall
    ret

; ============================================================
; rt_read_line — Read line from stdin into read_buf
; Returns: rax = pointer to read_buf, rdx = length (without newline)
; ============================================================
global rt_read_line
rt_read_line:
    push rbp
    mov rbp, rsp

    mov rax, 0              ; sys_read
    mov rdi, 0              ; stdin
    mov rsi, read_buf
    mov rdx, 1023
    syscall

    ; Store length
    mov [read_len], rax

    ; Strip trailing newline
    cmp rax, 0
    jle .done
    dec rax
    cmp byte [read_buf + rax], 10
    jne .no_strip
    mov byte [read_buf + rax], 0
    jmp .done
.no_strip:
    inc rax
    mov byte [read_buf + rax], 0
.done:
    mov rdx, rax            ; length
    mov rax, read_buf       ; pointer

    pop rbp
    ret

; ============================================================
; rt_prompt — Print prompt string (rsi, rdx) to stderr, then read line
; Returns: rax = pointer to input, rdx = length
; ============================================================
global rt_prompt
rt_prompt:
    push rbp
    mov rbp, rsp
    push rsi
    push rdx

    ; Print prompt to stderr
    mov rax, 1
    mov rdi, 2              ; stderr
    pop rdx
    pop rsi
    syscall

    ; Print "? " after prompt
    push rax
    mov rax, 1
    mov rdi, 2
    push rbx
    sub rsp, 2
    mov byte [rsp], '?'
    mov byte [rsp+1], ' '
    mov rsi, rsp
    mov rdx, 2
    syscall
    add rsp, 2
    pop rbx
    pop rax

    ; Read line
    call rt_read_line

    pop rbp
    ret

; ============================================================
; rt_str_to_int — Convert string at rsi to integer
; Returns: rax = integer value, rdx = 1 if valid int, 0 if not
; ============================================================
global rt_str_to_int
rt_str_to_int:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    xor rax, rax            ; result = 0
    xor r12, r12            ; negative flag
    mov rbx, rsi            ; string pointer

    ; Check for minus
    cmp byte [rbx], '-'
    jne .parse_digits
    mov r12, 1
    inc rbx
    ; Must have at least one digit after minus
    cmp byte [rbx], 0
    je .not_int

.parse_digits:
    cmp byte [rbx], 0
    je .end_parse
    movzx rcx, byte [rbx]
    sub rcx, '0'
    cmp rcx, 9
    ja .not_int
    imul rax, 10
    add rax, rcx
    inc rbx
    jmp .parse_digits

.end_parse:
    ; Check we parsed at least one digit
    cmp rbx, rsi
    je .not_int
    ; Apply negative
    cmp r12, 1
    jne .valid
    neg rax
.valid:
    mov rdx, 1
    pop r12
    pop rbx
    pop rbp
    ret

.not_int:
    xor rax, rax
    xor rdx, rdx
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; rt_str_len — String length (null-terminated)
; rdi = string pointer, returns rax = length
; ============================================================
global rt_str_len
rt_str_len:
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ============================================================
; rt_str_copy — Copy string from rsi to rdi, returns bytes copied in rax
; ============================================================
global rt_str_copy
rt_str_copy:
    xor rax, rax
.loop:
    mov cl, [rsi + rax]
    mov [rdi + rax], cl
    cmp cl, 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ============================================================
; rt_str_eq — Compare strings rdi and rsi
; Returns: rax = 1 if equal, 0 if not
; ============================================================
global rt_str_eq
rt_str_eq:
    ; Guard: if either arg looks like an integer (not a pointer), return 0
    cmp rdi, 0
    jl .not_eq
    cmp rdi, 0x400000
    jbe .not_eq
    cmp rsi, 0
    jl .not_eq
    cmp rsi, 0x400000
    jbe .not_eq
    xor rax, rax
.loop:
    mov cl, [rdi]
    cmp cl, [rsi]
    jne .not_eq
    cmp cl, 0
    je .eq
    inc rdi
    inc rsi
    jmp .loop
.eq:
    mov rax, 1
.not_eq:
    ret

; ============================================================
; rt_str_concat — Concatenate strings rdi and rsi into new heap string
; Returns: rax = pointer to new string
; ============================================================
global rt_str_concat
rt_str_concat:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14

    mov r12, rdi            ; str1
    mov r13, rsi            ; str2

    ; Get lengths
    mov rdi, r12
    call rt_str_len
    mov r14, rax            ; len1

    mov rdi, r13
    call rt_str_len
    push rax                ; len2

    ; Allocate len1 + len2 + 1
    pop rdi
    add rdi, r14
    inc rdi
    push rdi
    call rt_alloc
    pop rcx                 ; total len (unused but popped)

    ; Copy str1
    mov rdi, rax
    push rax
    mov rsi, r12
    call rt_str_copy

    ; Copy str2 at offset
    pop rax
    push rax
    lea rdi, [rax + r14]
    mov rsi, r13
    call rt_str_copy

    pop rax                 ; return pointer

    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_int_to_str — Convert integer rdi to string on heap
; Returns: rax = pointer to string
; ============================================================
global rt_int_to_str
rt_int_to_str:
    push rbp
    mov rbp, rsp
    push r12
    push rbx

    mov rax, rdi
    mov r12, 0              ; negative flag

    cmp rax, 0
    jge .pos
    neg rax
    mov r12, 1
.pos:
    ; Build in int_buf (reverse)
    lea rbx, [int_buf + 20]
    mov byte [rbx], 0
.loop:
    dec rbx
    xor rdx, rdx
    mov rcx, 10
    div rcx
    add dl, '0'
    mov [rbx], dl
    cmp rax, 0
    jne .loop

    cmp r12, 1
    jne .alloc
    dec rbx
    mov byte [rbx], '-'
.alloc:
    ; Calculate length and allocate
    lea rdi, [int_buf + 20]
    sub rdi, rbx
    inc rdi                 ; +1 for null
    push rbx
    push rdi
    call rt_alloc
    pop rcx
    pop rbx

    ; Copy to heap
    mov rdi, rax
    mov rsi, rbx
    push rax
    call rt_str_copy
    pop rax

    pop rbx
    pop r12
    pop rbp
    ret

; ============================================================
; rt_file_open_read — Open file for reading
; rdi = filename (null-terminated), returns rax = fd (-1 on error)
; ============================================================
global rt_file_open_read
rt_file_open_read:
    mov rax, 2              ; sys_open
    ; rdi already has filename
    xor rsi, rsi            ; O_RDONLY
    xor rdx, rdx            ; mode (unused for read)
    syscall
    ret

; ============================================================
; rt_file_open_write — Open file for writing (create/truncate)
; rdi = filename, returns rax = fd
; ============================================================
global rt_file_open_write
rt_file_open_write:
    mov rax, 2              ; sys_open
    mov rsi, 577            ; O_WRONLY | O_CREAT | O_TRUNC
    mov rdx, 0644o          ; permissions rw-r--r--
    syscall
    ret

; ============================================================
; rt_file_read — Read entire file into heap string
; rdi = fd, returns rax = pointer to string, rdx = length
; ============================================================
global rt_file_read
rt_file_read:
    push rbp
    mov rbp, rsp
    push r12

    mov r12, rdi            ; save fd

    ; Allocate 64KB buffer
    mov rdi, 65536
    call rt_alloc
    push rax                ; save buffer pointer

    ; Read file
    mov rax, 0              ; sys_read
    mov rdi, r12            ; fd
    pop rsi
    push rsi                ; keep buffer pointer
    mov rdx, 65535
    syscall

    ; Null-terminate
    pop rsi
    mov byte [rsi + rax], 0
    mov rdx, rax            ; length
    mov rax, rsi            ; pointer

    ; Close file
    push rax
    push rdx
    mov rax, 3              ; sys_close
    mov rdi, r12
    syscall
    pop rdx
    pop rax

    pop r12
    pop rbp
    ret

; ============================================================
; rt_file_write — Write string to file
; rdi = fd, rsi = string, rdx = length
; ============================================================
global rt_file_write
rt_file_write:
    push rbp
    mov rbp, rsp
    mov rax, 1              ; sys_write
    syscall
    pop rbp
    ret

; ============================================================
; rt_file_write_str — Write string to named file
; rdi = filename (null-terminated), rsi = string to write
; ============================================================
global rt_file_write_str
rt_file_write_str:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rsi             ; save string

    ; Open file for writing
    call rt_file_open_write  ; rdi already has filename
    cmp rax, 0
    jl .fws_error
    mov r13, rax             ; fd

    ; Get string length
    mov rdi, r12
    call rt_str_len
    mov rdx, rax             ; length

    ; Write
    mov rax, 1               ; sys_write
    mov rdi, r13             ; fd
    mov rsi, r12             ; string
    syscall

    ; Close
    mov rax, 3
    mov rdi, r13
    syscall

    mov rax, 0               ; success
.fws_error:
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_file_read_str — Read file into heap string
; rdi = filename (null-terminated), returns rax = string ptr
; ============================================================
global rt_file_read_str
rt_file_read_str:
    push rbp
    mov rbp, rsp
    push r12

    call rt_file_open_read
    cmp rax, 0
    jl .frs_error
    mov rdi, rax
    call rt_file_read        ; rax = string ptr
    pop r12
    pop rbp
    ret
.frs_error:
    ; Return empty string on error
    mov rdi, 1
    call rt_alloc
    mov byte [rax], 0
    pop r12
    pop rbp
    ret

; ============================================================
; rt_str_upper — Convert string to uppercase (new heap copy)
; rdi = source string, returns rax = new string
; ============================================================
global rt_str_upper
rt_str_upper:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi
    mov rdi, r12
    call rt_str_len
    mov r13, rax
    lea rdi, [rax + 1]
    call rt_alloc
    push rax
    xor rcx, rcx
.upper_loop:
    cmp rcx, r13
    je .upper_done
    movzx edx, byte [r12 + rcx]
    cmp dl, 'a'
    jb .upper_copy
    cmp dl, 'z'
    ja .upper_copy
    sub dl, 32
.upper_copy:
    mov [rax + rcx], dl
    inc rcx
    jmp .upper_loop
.upper_done:
    pop rax
    mov byte [rax + r13], 0
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_str_lower — Convert string to lowercase (new heap copy)
; rdi = source string, returns rax = new string
; ============================================================
global rt_str_lower
rt_str_lower:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi
    mov rdi, r12
    call rt_str_len
    mov r13, rax
    lea rdi, [rax + 1]
    call rt_alloc
    push rax
    xor rcx, rcx
.lower_loop:
    cmp rcx, r13
    je .lower_done
    movzx edx, byte [r12 + rcx]
    cmp dl, 'A'
    jb .lower_copy
    cmp dl, 'Z'
    ja .lower_copy
    add dl, 32
.lower_copy:
    mov [rax + rcx], dl
    inc rcx
    jmp .lower_loop
.lower_done:
    pop rax
    mov byte [rax + r13], 0
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_str_trim — Trim leading/trailing whitespace (new heap copy)
; rdi = source string, returns rax = new string
; ============================================================
global rt_str_trim
rt_str_trim:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    mov r12, rdi
    ; Find start (skip leading whitespace)
    xor r13, r13
.trim_left:
    movzx eax, byte [r12 + r13]
    cmp al, 0
    je .trim_empty
    cmp al, ' '
    je .trim_left_next
    cmp al, 9
    je .trim_left_next
    cmp al, 10
    je .trim_left_next
    cmp al, 13
    je .trim_left_next
    jmp .trim_find_end
.trim_left_next:
    inc r13
    jmp .trim_left
.trim_empty:
    mov rdi, 1
    call rt_alloc
    mov byte [rax], 0
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
.trim_find_end:
    ; Find end
    mov rdi, r12
    call rt_str_len
    mov r14, rax
.trim_right:
    cmp r14, r13
    jle .trim_copy
    dec r14
    movzx eax, byte [r12 + r14]
    cmp al, ' '
    je .trim_right
    cmp al, 9
    je .trim_right
    cmp al, 10
    je .trim_right
    cmp al, 13
    je .trim_right
    inc r14
.trim_copy:
    mov rdi, r14
    sub rdi, r13
    inc rdi
    push rdi
    call rt_alloc
    pop rdi
    dec rdi
    push rax
    xor rcx, rcx
.trim_cp:
    cmp rcx, rdi
    je .trim_done
    lea rdx, [r12 + r13]
    movzx edx, byte [rdx + rcx]
    mov [rax + rcx], dl
    inc rcx
    jmp .trim_cp
.trim_done:
    pop rax
    mov byte [rax + rdi], 0
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_str_contains — Check if string contains substring
; rdi = haystack, rsi = needle, returns rax = 1 if found, 0 if not
; ============================================================
global rt_str_contains
rt_str_contains:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi             ; haystack
    mov r13, rsi             ; needle
    mov rdi, r12
    call rt_str_len
    mov r14, rax             ; haystack len
    mov rdi, r13
    call rt_str_len
    mov r15, rax             ; needle len
    cmp r15, 0
    je .contains_yes
    cmp r15, r14
    jg .contains_no
    mov rcx, r14
    sub rcx, r15
    inc rcx                  ; max start positions
    xor r8, r8               ; current position
.contains_outer:
    cmp r8, rcx
    jge .contains_no
    xor r9, r9
.contains_inner:
    cmp r9, r15
    je .contains_yes
    lea rax, [r12 + r8]
    movzx eax, byte [rax + r9]
    cmp al, [r13 + r9]
    jne .contains_next
    inc r9
    jmp .contains_inner
.contains_next:
    inc r8
    jmp .contains_outer
.contains_yes:
    mov rax, 1
    jmp .contains_ret
.contains_no:
    xor rax, rax
.contains_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_str_replace — Replace first occurrence of old with new
; rdi = source, rsi = old, rdx = new, returns rax = new string
; ============================================================
global rt_str_replace
rt_str_replace:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi             ; source
    mov r13, rsi             ; old
    mov [rbp-40], rdx        ; new (stored on stack)
    ; Get lengths
    mov rdi, r12
    call rt_str_len
    mov r14, rax             ; source len
    mov rdi, r13
    call rt_str_len
    mov r15, rax             ; old len
    mov rdi, [rbp-40]
    call rt_str_len
    mov [rbp-48], rax        ; new len
    ; Find old in source
    cmp r15, 0
    je .replace_copy_all
    mov rcx, r14
    sub rcx, r15
    inc rcx
    xor r8, r8
.replace_find:
    cmp r8, rcx
    jge .replace_copy_all
    xor r9, r9
.replace_cmp:
    cmp r9, r15
    je .replace_found
    lea rax, [r12 + r8]
    movzx eax, byte [rax + r9]
    cmp al, [r13 + r9]
    jne .replace_next
    inc r9
    jmp .replace_cmp
.replace_next:
    inc r8
    jmp .replace_find
.replace_found:
    ; r8 = position of match
    ; Allocate: source_len - old_len + new_len + 1
    mov rdi, r14
    sub rdi, r15
    add rdi, [rbp-48]
    inc rdi
    call rt_alloc
    push rax
    ; Copy prefix (0..r8)
    xor rcx, rcx
.replace_pre:
    cmp rcx, r8
    je .replace_mid
    movzx edx, byte [r12 + rcx]
    mov [rax + rcx], dl
    inc rcx
    jmp .replace_pre
.replace_mid:
    ; Copy new string
    mov rsi, [rbp-40]
    mov rdi, [rbp-48]
    xor r9, r9
.replace_new:
    cmp r9, rdi
    je .replace_post
    movzx edx, byte [rsi + r9]
    pop rax
    push rax
    mov [rax + rcx], dl
    inc rcx
    inc r9
    jmp .replace_new
.replace_post:
    ; Copy rest after match
    lea r9, [r8 + r15]
.replace_rest:
    cmp r9, r14
    je .replace_done
    movzx edx, byte [r12 + r9]
    pop rax
    push rax
    mov [rax + rcx], dl
    inc rcx
    inc r9
    jmp .replace_rest
.replace_done:
    pop rax
    mov byte [rax + rcx], 0
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
.replace_copy_all:
    ; No match — return copy of source
    mov rdi, r12
    mov rsi, r12
    call rt_str_copy
    lea rdi, [r14 + 1]
    call rt_alloc
    push rax
    mov rdi, rax
    mov rsi, r12
    call rt_str_copy
    pop rax
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_new — Create new empty array with given capacity
; rdi = initial capacity (0 = default 8), returns rax = array ptr
; Layout: [count:8][capacity:8][elem0:8][elem1:8]...
; ============================================================
global rt_arr_new
rt_arr_new:
    push rbp
    mov rbp, rsp
    cmp rdi, 0
    jne .has_cap
    mov rdi, 8
.has_cap:
    push rdi
    shl rdi, 3               ; capacity * 8 for elements
    add rdi, 16              ; + 16 for count and capacity header
    call rt_alloc
    pop rdi
    mov qword [rax], 0       ; count = 0
    mov [rax + 8], rdi        ; capacity
    pop rbp
    ret

; ============================================================
; rt_arr_push — Push value onto array
; rdi = array ptr, rsi = value, returns rax = array ptr
; ============================================================
global rt_arr_push
rt_arr_push:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi             ; array
    mov r13, rsi             ; value
    mov rcx, [r12]           ; count
    cmp rcx, [r12 + 8]       ; count vs capacity
    jl .has_space
    ; Need to grow — allocate new array with 2x capacity
    mov rdi, [r12 + 8]
    shl rdi, 1               ; new capacity = old * 2
    push rdi
    push rcx
    shl rdi, 3
    add rdi, 16
    call rt_alloc
    pop rcx
    pop rdi
    mov qword [rax], rcx     ; copy count
    mov [rax + 8], rdi        ; new capacity
    ; Copy elements
    xor r8, r8
.copy:
    cmp r8, rcx
    je .copy_done
    mov r9, [r12 + 16 + r8 * 8]
    mov [rax + 16 + r8 * 8], r9
    inc r8
    jmp .copy
.copy_done:
    mov r12, rax             ; use new array
.has_space:
    mov rcx, [r12]
    mov [r12 + 16 + rcx * 8], r13
    inc qword [r12]
    mov rax, r12
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_pop — Pop last value from array
; rdi = array ptr, returns rax = popped value
; ============================================================
global rt_arr_pop
rt_arr_pop:
    mov rcx, [rdi]
    cmp rcx, 0
    je .empty
    dec rcx
    mov [rdi], rcx
    mov rax, [rdi + 16 + rcx * 8]
    ret
.empty:
    xor rax, rax
    ret

; ============================================================
; rt_arr_get — Get element at index
; rdi = array ptr, rsi = index, returns rax = value
; ============================================================
global rt_arr_get
rt_arr_get:
    ; Handle negative index: if rsi >= 0x8000000000000000 (i.e., negative signed)
    test rsi, rsi
    jns .pos_index
    ; Negative: rsi = count + rsi (e.g., -1 → count-1)
    add rsi, [rdi]
    js .oob                  ; still negative → out of bounds
.pos_index:
    cmp rsi, [rdi]
    jge .oob
    mov rax, [rdi + 16 + rsi * 8]
    ret
.oob:
    xor rax, rax
    ret

; ============================================================
; rt_arr_set — Set element at index
; rdi = array ptr, rsi = index, rdx = value
; ============================================================
global rt_arr_set
rt_arr_set:
    cmp rsi, [rdi]
    jge .oob
    mov [rdi + 16 + rsi * 8], rdx
.oob:
    ret

; ============================================================
; rt_arr_contains — Check if value exists in array
; rdi = array ptr, rsi = value to find
; returns rax = 1 if found, 0 if not
; ============================================================
global rt_arr_contains
rt_arr_contains:
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rdi]           ; count
    lea r13, [rdi + 16]      ; start of elements
    mov r14, rsi             ; value to find
    ; Negative values are always integers
    cmp r14, 0
    jl .ac_int_loop
    ; Detect if value is a string pointer (> 0x400000)
    mov rax, 0x400000
    cmp r14, rax
    jbe .ac_int_loop
    ; String comparison loop
.ac_str_loop:
    cmp r12, 0
    je .ac_not_found
    mov rdi, [r13]
    mov rsi, r14
    call rt_str_eq
    cmp rax, 1
    je .ac_found
    add r13, 8
    dec r12
    jmp .ac_str_loop
    ; Integer comparison loop
.ac_int_loop:
    cmp r12, 0
    je .ac_not_found
    cmp [r13], r14
    je .ac_found
    add r13, 8
    dec r12
    jmp .ac_int_loop
.ac_found:
    mov rax, 1
    jmp .ac_done
.ac_not_found:
    xor rax, rax
.ac_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; rt_arr_len — Get array length
; rdi = array ptr, returns rax = count
; ============================================================
global rt_arr_len
rt_arr_len:
    mov rax, [rdi]
    ret

; ============================================================
; rt_arr_slice — Create new array from arr[start..end)
; rdi = array ptr, rsi = start, rdx = end
; returns rax = new array ptr
; ============================================================
global rt_arr_slice
rt_arr_slice:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    mov r12, rdi             ; source array
    mov r13, rsi             ; start
    mov r14, rdx             ; end
    ; Clamp start/end
    cmp r13, 0
    jge .slice_start_ok
    xor r13, r13
.slice_start_ok:
    mov rax, [r12]
    cmp r14, rax
    jle .slice_end_ok
    mov r14, rax
.slice_end_ok:
    cmp r13, r14
    jge .slice_empty
    ; Create new array
    xor rdi, rdi
    call rt_arr_new
    mov rcx, r13
.slice_loop:
    cmp rcx, r14
    jge .slice_done
    push rcx
    push rax
    mov rdi, rax
    mov rsi, [r12 + 16 + rcx * 8]
    call rt_arr_push
    pop rcx                  ; discard old arr ptr
    pop rcx                  ; restore counter
    inc rcx
    jmp .slice_loop
.slice_empty:
    xor rdi, rdi
    call rt_arr_new
.slice_done:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_reverse — Create new reversed array
; rdi = array ptr, returns rax = new array ptr
; ============================================================
global rt_arr_reverse
rt_arr_reverse:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi             ; source
    mov r13, [rdi]           ; count
    xor rdi, rdi
    call rt_arr_new
.rev_loop:
    cmp r13, 0
    je .rev_done
    dec r13
    push r13
    push rax
    mov rdi, rax
    mov rsi, [r12 + 16 + r13 * 8]
    call rt_arr_push
    pop rcx                  ; discard old
    pop r13
    jmp .rev_loop
.rev_done:
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_step — Create new array from every N-th element
; rdi = array ptr, rsi = step size
; returns rax = new array ptr
; ============================================================
global rt_arr_step
rt_arr_step:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    mov r12, rdi             ; source
    mov r13, rsi             ; step
    mov r14, 0               ; index
    xor rdi, rdi
    call rt_arr_new
.step_loop:
    cmp r14, [r12]
    jge .step_done
    push r14
    push rax
    mov rdi, rax
    mov rsi, [r12 + 16 + r14 * 8]
    call rt_arr_push
    pop rcx                  ; discard old
    pop r14
    add r14, r13
    jmp .step_loop
.step_done:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_len — Universal length: works for strings and arrays
; rdi = pointer, returns rax = length
; Heuristic: if [ptr] and [ptr+8] look like array header
; (count <= capacity, capacity <= 1M), treat as array
; ============================================================
global rt_len
rt_len:
    push rbp
    mov rbp, rsp
    cmp rdi, 0x400000
    jb .str_len
    ; Check if it could be an array
    mov rax, [rdi]           ; potential count
    mov rcx, [rdi + 8]       ; potential capacity
    cmp rcx, 0
    je .str_len
    cmp rcx, 1048576
    ja .str_len
    cmp rax, rcx
    ja .str_len
    ; Looks like array — return count
    pop rbp
    ret
.str_len:
    call rt_str_len
    pop rbp
    ret

; ============================================================
; rt_print_val — Print value: auto-detect string pointer vs int
; rdi = value. If it points into heap or data section (.rodata),
; print as string; otherwise print as integer.
; ============================================================
global rt_print_val
rt_print_val:
    push rbp
    mov rbp, rsp
    ; Negative values are always integers (signed check)
    cmp rdi, 0
    jl .print_as_int
    ; Check if value looks like a pointer (in heap range or > 0x400000)
    cmp rdi, 0x400000
    jb .print_as_int
    ; Try to read first byte — if it's printable ASCII or null, it's a string
    movzx eax, byte [rdi]
    cmp al, 0
    je .print_empty
    cmp al, 127
    ja .print_as_int
    ; Looks like a string pointer — get length and print
    push rdi
    call rt_str_len
    mov rdx, rax
    pop rsi
    call rt_print_str
    pop rbp
    ret
.print_empty:
    ; Empty string — print nothing
    pop rbp
    ret
.print_as_int:
    call rt_print_int
    pop rbp
    ret

; ============================================================
; rt_div_check — Check divisor in rbx, abort if zero
; ============================================================
global rt_div_check
rt_div_check:
    cmp rbx, 0
    jne .ok
    mov rax, 1
    mov rdi, 2
    mov rsi, divzero_msg
    mov rdx, divzero_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall
.ok:
    ret

; ============================================================
; rt_abs — Absolute value: rdi = input, rax = |input|
; ============================================================
global rt_abs
rt_abs:
    mov rax, rdi
    cmp rax, 0
    jge .done
    neg rax
.done:
    ret

; ============================================================
; rt_min — Minimum of rdi, rsi → rax
; ============================================================
global rt_min
rt_min:
    mov rax, rdi
    cmp rsi, rax
    jge .done
    mov rax, rsi
.done:
    ret

; ============================================================
; rt_max — Maximum of rdi, rsi → rax
; ============================================================
global rt_max
rt_max:
    mov rax, rdi
    cmp rsi, rax
    jle .done
    mov rax, rsi
.done:
    ret

; ============================================================
; rt_sqrt — Integer square root (floor): rdi = input, rax = floor(sqrt(input))
; ============================================================
global rt_sqrt
rt_sqrt:
    push rbx
    cmp rdi, 0
    jle .zero
    cmp rdi, 1
    je .one
    mov rax, rdi
    shr rax, 1              ; initial guess = n/2
.loop:
    mov rbx, rax             ; save old guess
    ; new = (old + n/old) / 2
    push rdx
    xor rdx, rdx
    push rax
    mov rax, rdi
    div rbx                  ; rax = n / old
    pop rcx                  ; rcx = old
    add rax, rcx             ; rax = old + n/old
    shr rax, 1               ; rax = (old + n/old) / 2
    pop rdx
    cmp rax, rbx
    jl .loop                 ; if new < old, keep going
    mov rax, rbx             ; return old (converged)
    pop rbx
    ret
.zero:
    xor rax, rax
    pop rbx
    ret
.one:
    mov rax, 1
    pop rbx
    ret

; ============================================================
; rt_random — Random number in range [rdi, rsi] → rax
; Uses Linux getrandom syscall (318)
; ============================================================
global rt_random
rt_random:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    sub rsp, 8               ; space for random bytes
    mov r12, rdi             ; min
    mov r13, rsi             ; max

    ; getrandom(&buf, 8, 0)
    mov rax, 318             ; sys_getrandom
    lea rdi, [rsp]
    mov rsi, 8
    xor rdx, rdx
    syscall

    mov rax, [rsp]           ; get random 8 bytes
    ; Make positive
    cmp rax, 0
    jge .positive
    neg rax
.positive:
    ; range = max - min + 1
    mov rcx, r13
    sub rcx, r12
    inc rcx
    ; rax = rax % range + min
    xor rdx, rdx
    div rcx
    mov rax, rdx
    add rax, r12

    add rsp, 8
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_type — Return type string pointer: rdi = value → rax = ptr to type string
; Uses magnitude threshold: > 0x400000 = string/array, check array header
; ============================================================
global rt_type
rt_type:
    push rbx
    ; Negative values are always integers
    cmp rdi, 0
    jl .is_int_ret
    mov rax, 0x400000
    cmp rdi, rax
    jbe .is_int
    ; Could be string or array — check if it looks like an array
    ; Arrays have count at [rdi], and count < 10000000 typically
    ; and elements start at [rdi+16]
    ; Heuristic: if [rdi] (first qword) is a small number and [rdi+8] >= heap area, it's an array
    mov rax, [rdi]           ; potential count
    cmp rax, 0
    jl .is_str               ; negative = not array count
    cmp rax, 100000000
    jg .is_str               ; too large for array count
    ; Check second qword (capacity) — should also be reasonable
    mov rbx, [rdi + 8]
    cmp rbx, rax
    jl .is_str               ; capacity < count = not array
    mov rax, type_arr_str
    pop rbx
    ret
.is_str:
    mov rax, type_str_str
    pop rbx
    ret
.is_int:
    ; Check for bool (0 or 1)
    cmp rdi, 0
    je .is_int_ret
    cmp rdi, 1
    je .is_int_ret
    ; Regular int
.is_int_ret:
    mov rax, type_int_str
    pop rbx
    ret

; ============================================================
; rt_str_startswith — Check if string rdi starts with rsi
; rdi = string ptr, rsi = prefix ptr → rax = 1/0
; ============================================================
global rt_str_startswith
rt_str_startswith:
    push rbx
    push r12
    push r13
    mov r12, rdi             ; string
    mov r13, rsi             ; prefix
.sw_loop:
    mov al, [r13]
    cmp al, 0
    je .sw_yes               ; prefix ended = match
    mov bl, [r12]
    cmp bl, 0
    je .sw_no                ; string ended before prefix
    cmp al, bl
    jne .sw_no
    inc r12
    inc r13
    jmp .sw_loop
.sw_yes:
    mov rax, 1
    pop r13
    pop r12
    pop rbx
    ret
.sw_no:
    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; rt_str_endswith — Check if string rdi ends with rsi
; rdi = string ptr, rsi = suffix ptr → rax = 1/0
; ============================================================
global rt_str_endswith
rt_str_endswith:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi             ; string
    mov r13, rsi             ; suffix
    ; Get string length
    mov rdi, r12
    call rt_str_len
    mov r14, rax             ; str_len
    ; Get suffix length
    mov rdi, r13
    call rt_str_len
    mov rbx, rax             ; suf_len
    ; If suffix longer than string, no
    cmp rbx, r14
    jg .ew_no
    ; Compare from str + (str_len - suf_len)
    mov rdi, r12
    add rdi, r14
    sub rdi, rbx             ; rdi = start position
    mov rsi, r13
.ew_loop:
    mov al, [rsi]
    cmp al, 0
    je .ew_yes
    cmp al, [rdi]
    jne .ew_no
    inc rdi
    inc rsi
    jmp .ew_loop
.ew_yes:
    mov rax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.ew_no:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; rt_str_index — Find substring rsi in string rdi
; rdi = haystack, rsi = needle → rax = index (or -1)
; ============================================================
global rt_str_index
rt_str_index:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi             ; haystack
    mov r13, rsi             ; needle
    ; Get needle length
    mov rdi, r13
    call rt_str_len
    mov r14, rax             ; needle_len
    cmp r14, 0
    je .idx_found_zero       ; empty needle = 0
    ; Get haystack length
    mov rdi, r12
    call rt_str_len
    mov r15, rax             ; hay_len
    xor rbx, rbx            ; position counter
.idx_outer:
    mov rax, r15
    sub rax, rbx
    cmp rax, r14
    jl .idx_not_found        ; not enough chars left
    ; Compare needle at position rbx
    xor rcx, rcx
.idx_inner:
    cmp rcx, r14
    je .idx_found
    mov al, [r12 + rbx]
    add al, 0               ; load byte
    mov al, [r12 + rbx + 0]
    push rbx
    add rbx, rcx
    mov al, [r12 + rbx]
    pop rbx
    cmp al, [r13 + rcx]
    jne .idx_next
    inc rcx
    jmp .idx_inner
.idx_next:
    inc rbx
    jmp .idx_outer
.idx_found:
    mov rax, rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.idx_found_zero:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.idx_not_found:
    mov rax, -1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; rt_str_split — Split string rdi by separator rsi → rax = new array
; ============================================================
global rt_str_split
rt_str_split:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    push rbx
    mov r12, rdi             ; string
    mov r13, rsi             ; separator

    ; Get separator length
    mov rdi, r13
    call rt_str_len
    mov r14, rax             ; sep_len

    ; Create result array
    xor rdi, rdi
    call rt_arr_new
    mov r15, rax             ; result array

    ; If sep_len == 0, split each char
    cmp r14, 0
    je .split_chars

    mov rbx, r12             ; current position
.split_loop:
    mov al, [rbx]
    cmp al, 0
    je .split_last           ; end of string, push remaining

    ; Check if separator matches at current position
    xor rcx, rcx
.split_cmp:
    cmp rcx, r14
    je .split_found          ; full separator matched
    mov al, [rbx + rcx]
    cmp al, 0
    je .split_last           ; end of string
    cmp al, [r13 + rcx]
    jne .split_advance
    inc rcx
    jmp .split_cmp

.split_advance:
    inc rbx
    jmp .split_loop

.split_found:
    ; Copy substring from r12 to rbx into new string
    mov rdi, rbx
    sub rdi, r12             ; length of substring
    push rdi
    inc rdi                  ; +1 for null
    call rt_alloc
    mov rdi, rax             ; dest
    pop rcx                  ; length
    push rcx
    mov rsi, r12             ; src
    ; Copy rcx bytes
    push rdi
.copy1:
    cmp rcx, 0
    je .copy1_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .copy1
.copy1_done:
    mov byte [rdi], 0        ; null terminate
    pop rdi                  ; restore dest start
    pop rcx                  ; length (unused)

    ; Push substring to array
    mov rsi, rdi
    mov rdi, r15
    call rt_arr_push
    mov r15, rax

    ; Advance past separator
    add rbx, r14
    mov r12, rbx             ; new start
    jmp .split_loop

.split_last:
    ; Push remaining string (from r12 to end)
    mov rdi, r12
    call rt_str_len
    mov rcx, rax
    inc rcx                  ; +1 for null
    push rcx
    mov rdi, rcx
    call rt_alloc
    mov rdi, rax
    pop rcx
    dec rcx
    mov rsi, r12
    push rdi
.copy2:
    cmp rcx, 0
    je .copy2_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .copy2
.copy2_done:
    mov byte [rdi], 0
    pop rdi
    mov rsi, rdi
    mov rdi, r15
    call rt_arr_push
    mov r15, rax

    mov rax, r15
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.split_chars:
    ; Split each character into its own string
    mov rbx, r12
.sc_loop:
    mov al, [rbx]
    cmp al, 0
    je .sc_done
    ; Allocate 2-byte string
    mov rdi, 2
    call rt_alloc
    mov cl, [rbx]
    mov [rax], cl
    mov byte [rax + 1], 0
    mov rsi, rax
    mov rdi, r15
    call rt_arr_push
    mov r15, rax
    inc rbx
    jmp .sc_loop
.sc_done:
    mov rax, r15
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_str_repeat — Repeat string rdi, rsi times → rax = new string
; ============================================================
global rt_str_repeat
rt_str_repeat:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    mov r12, rdi             ; string
    mov r13, rsi             ; count
    ; Get string length
    mov rdi, r12
    call rt_str_len
    mov r14, rax             ; str_len
    ; Allocate str_len * count + 1
    mov rdi, r14
    imul rdi, r13
    inc rdi
    call rt_alloc
    mov rdi, rax             ; dest
    push rdi                 ; save start
    ; Copy string count times
    xor rcx, rcx
.rep_outer:
    cmp rcx, r13
    je .rep_done
    mov rsi, r12
    push rcx
    mov rcx, r14
.rep_inner:
    cmp rcx, 0
    je .rep_inner_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .rep_inner
.rep_inner_done:
    pop rcx
    inc rcx
    jmp .rep_outer
.rep_done:
    mov byte [rdi], 0        ; null terminate
    pop rax                  ; return start
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_sort — Sort integer array in-place (bubble sort): rdi = array ptr
; Returns: rax = array ptr
; ============================================================
global rt_arr_sort
rt_arr_sort:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push rbx
    mov r12, rdi             ; array
    mov r13, [r12]           ; count
    cmp r13, 1
    jle .sort_done
    lea r14, [r12 + 16]      ; elements start
.sort_outer:
    xor rbx, rbx            ; swapped flag
    xor rcx, rcx            ; i = 0
.sort_inner:
    lea rax, [rcx + 1]
    cmp rax, r13
    jge .sort_check
    mov rax, [r14 + rcx * 8]
    mov rdx, [r14 + rcx * 8 + 8]
    cmp rax, rdx
    jle .sort_no_swap
    ; Swap
    mov [r14 + rcx * 8], rdx
    mov [r14 + rcx * 8 + 8], rax
    mov rbx, 1
.sort_no_swap:
    inc rcx
    jmp .sort_inner
.sort_check:
    cmp rbx, 0
    jne .sort_outer
.sort_done:
    mov rax, r12
    pop rbx
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_join — Join array of strings with separator
; rdi = array, rsi = separator → rax = new string
; ============================================================
global rt_arr_join
rt_arr_join:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    push rbx
    mov r12, rdi             ; array
    mov r13, rsi             ; separator
    mov r14, [r12]           ; count
    lea r15, [r12 + 16]      ; elements

    ; Get separator length
    mov rdi, r13
    call rt_str_len
    mov rbx, rax             ; sep_len

    ; First pass: calculate total length
    xor rcx, rcx             ; total
    xor r8, r8               ; i
.join_len:
    cmp r8, r14
    jge .join_alloc
    push rcx
    push r8
    mov rdi, [r15 + r8 * 8]
    call rt_str_len
    pop r8
    pop rcx
    add rcx, rax
    ; Add separator length (except after last)
    lea rax, [r8 + 1]
    cmp rax, r14
    jge .join_len_next
    add rcx, rbx
.join_len_next:
    inc r8
    jmp .join_len

.join_alloc:
    inc rcx                  ; +1 for null
    push rcx
    mov rdi, rcx
    call rt_alloc
    pop rcx
    mov rdi, rax             ; dest pointer
    push rdi                 ; save start

    ; Second pass: copy strings with separators
    xor r8, r8
.join_copy:
    cmp r8, r14
    jge .join_finish
    ; Copy element string
    push r8
    mov rsi, [r15 + r8 * 8]
.jc_loop:
    mov al, [rsi]
    cmp al, 0
    je .jc_elem_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .jc_loop
.jc_elem_done:
    pop r8
    ; Add separator if not last
    lea rax, [r8 + 1]
    cmp rax, r14
    jge .jc_next
    mov rsi, r13
    mov rcx, rbx
.jc_sep:
    cmp rcx, 0
    je .jc_next
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .jc_sep
.jc_next:
    inc r8
    jmp .join_copy

.join_finish:
    mov byte [rdi], 0        ; null terminate
    pop rax                  ; return start
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_range — Create array of integers from rdi to rsi-1
; rdi = start, rsi = end → rax = new array
; ============================================================
global rt_range
rt_range:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push rbx
    mov r12, rdi             ; start
    mov r13, rsi             ; end

    ; Create array
    xor rdi, rdi
    call rt_arr_new
    mov r14, rax             ; array

    mov rbx, r12
.range_loop:
    cmp rbx, r13
    jge .range_done
    mov rdi, r14
    mov rsi, rbx
    call rt_arr_push
    mov r14, rax
    inc rbx
    jmp .range_loop
.range_done:
    mov rax, r14
    pop rbx
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_exit — Exit with code in rdi
; ============================================================
global rt_exit
rt_exit:
    mov rax, 60
    syscall

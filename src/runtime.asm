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
    oom_msg      db "FATAL: Out of heap memory (64MB)", 10
    oom_msg_len  equ $ - oom_msg
    mmap_fail_msg db "FATAL: mmap failed to allocate heap", 10
    mmap_fail_msg_len equ $ - mmap_fail_msg
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
    saved_rsp    resq 1         ; initial rsp at _start (for argc/argv access)
    timespec_buf resb 16        ; for clock_gettime (sec + nsec)

section .text

; ============================================================
; rt_init — Initialize runtime (heap allocator)
; Uses mmap to allocate 64MB heap
; ============================================================
global rt_init
rt_init:
    push rbp
    mov rbp, rsp
    ; mmap(NULL, 268435456, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    mov rax, 9              ; sys_mmap
    xor rdi, rdi            ; addr = NULL
    mov rsi, 67108864       ; 64MB
    mov rdx, 3              ; PROT_READ | PROT_WRITE
    mov r10, 34             ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1              ; fd = -1
    xor r9, r9              ; offset = 0
    syscall
    cmp rax, -1
    je .mmap_fail
    cmp rax, -4096
    ja .mmap_fail
    mov [heap_base], rax
    mov [heap_ptr], rax
    add rax, 268435456
    mov [heap_end], rax
    pop rbp
    ret
.mmap_fail:
    mov rax, 1
    mov rdi, 2
    lea rsi, [mmap_fail_msg]
    mov rdx, mmap_fail_msg_len
    syscall
    mov rax, 60
    mov rdi, 138
    syscall

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
    mov rax, 1
    mov rdi, 2              ; stderr
    lea rsi, [oom_msg]
    mov rdx, oom_msg_len
    syscall
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
; rt_str_count — Count non-overlapping occurrences of sub in str
; rdi = string, rsi = substring, returns rax = count
; ============================================================
global rt_str_count
rt_str_count:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi             ; string
    mov r13, rsi             ; substring
    ; Get lengths
    call rt_str_len
    mov r14, rax             ; str len
    mov rdi, r13
    call rt_str_len
    mov r15, rax             ; sub len
    xor rcx, rcx             ; count = 0
    xor r8, r8               ; position = 0
    cmp r15, 0
    je .sc_done              ; empty sub → 0
.sc_loop:
    mov rax, r14
    sub rax, r15
    cmp r8, rax
    jg .sc_done
    ; Compare sub at position r8
    xor r9, r9
.sc_cmp:
    cmp r9, r15
    je .sc_match
    lea rax, [r12 + r8]
    movzx eax, byte [rax + r9]
    cmp al, [r13 + r9]
    jne .sc_next
    inc r9
    jmp .sc_cmp
.sc_match:
    inc rcx
    add r8, r15              ; skip past match (non-overlapping)
    jmp .sc_loop
.sc_next:
    inc r8
    jmp .sc_loop
.sc_done:
    mov rax, rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_str_pad — Pad string to width with char
; rdi = string, rsi = target width, rdx = pad char (as string ptr)
; Returns rax = new padded string (left-padded)
; ============================================================
global rt_str_pad
rt_str_pad:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi             ; string
    mov r13, rsi             ; target width
    mov r14, rdx             ; pad char string ptr
    ; Get string length
    call rt_str_len
    mov r15, rax             ; str len
    ; If already >= width, return copy
    cmp r15, r13
    jge .sp_copy
    ; Get pad char (first char of pad string)
    movzx ecx, byte [r14]
    cmp cl, 0
    je .sp_copy              ; empty pad → return copy
    push rcx                 ; save pad char
    ; Allocate width + 1
    lea rdi, [r13 + 1]
    call rt_alloc
    push rax                 ; save result ptr
    ; Fill pad chars
    mov rcx, r13
    sub rcx, r15             ; pad_count = width - len
    pop rax
    push rax
    xor r8, r8
    mov r9, [rsp + 8]        ; pad char from stack
.sp_fill:
    cmp r8, rcx
    je .sp_copy_str
    mov [rax + r8], r9b
    inc r8
    jmp .sp_fill
.sp_copy_str:
    ; Copy original string after pad
    xor r9, r9
.sp_copy_loop:
    cmp r9, r15
    je .sp_term
    movzx edx, byte [r12 + r9]
    pop rax
    push rax
    mov [rax + r8], dl
    inc r8
    inc r9
    jmp .sp_copy_loop
.sp_term:
    pop rax
    mov byte [rax + r8], 0
    add rsp, 8               ; clean pad char from stack
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
.sp_copy:
    ; Return copy of original
    lea rdi, [r15 + 1]
    call rt_alloc
    push rax
    xor rcx, rcx
.sp_copy_orig:
    cmp rcx, r15
    je .sp_copy_done
    movzx edx, byte [r12 + rcx]
    pop rax
    push rax
    mov [rax + rcx], dl
    inc rcx
    jmp .sp_copy_orig
.sp_copy_done:
    pop rax
    mov byte [rax + rcx], 0
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
    cmp rcx, 16777216
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
; rt_str_char_at — Get character at index as new 1-char string
; rdi = string ptr, rsi = index
; Returns: rax = pointer to new 1-char null-terminated string
; ============================================================
global rt_str_char_at
rt_str_char_at:
    push rbp
    mov rbp, rsp
    push r12
    ; Handle negative index
    test rsi, rsi
    jns .sca_pos
    push rdi
    push rsi
    call rt_str_len
    pop rsi
    pop rdi
    add rsi, rax
    js .sca_empty
.sca_pos:
    ; Bounds check
    push rdi
    push rsi
    call rt_str_len
    pop rsi
    pop rdi
    cmp rsi, rax
    jge .sca_empty
    ; Get the byte
    movzx r12d, byte [rdi + rsi]
    ; Allocate 2 bytes (char + null)
    mov rdi, 2
    call rt_alloc
    mov byte [rax], r12b
    mov byte [rax + 1], 0
    pop r12
    pop rbp
    ret
.sca_empty:
    mov rdi, 2
    call rt_alloc
    mov byte [rax], 0
    pop r12
    pop rbp
    ret

; ============================================================
; rt_subscript — Auto-detect string vs array subscript
; rdi = value (string ptr or array ptr), rsi = index
; Returns: rax = element (array) or 1-char string (string)
; ============================================================
global rt_subscript
rt_subscript:
    push rbp
    mov rbp, rsp
    ; Check if it's a string or array using heuristic
    cmp rdi, 0
    jl .sub_arr
    cmp rdi, 0x400000
    jbe .sub_arr
    ; Check array header: [count][capacity] — both should be small positive
    mov rax, [rdi]           ; potential count
    mov rcx, [rdi + 8]       ; potential capacity
    cmp rcx, 0
    je .sub_str
    cmp rcx, 16777216
    ja .sub_str
    cmp rax, rcx
    ja .sub_str
    ; Looks like array
.sub_arr:
    call rt_arr_get
    pop rbp
    ret
.sub_str:
    call rt_str_char_at
    pop rbp
    ret

; ============================================================
; rt_ord — Get ASCII code of first character of string
; rdi = string ptr, returns rax = integer (0-255)
; ============================================================
global rt_ord
rt_ord:
    cmp rdi, 0
    je .ord_zero
    cmp rdi, 0x400000
    jbe .ord_zero
    movzx eax, byte [rdi]
    ret
.ord_zero:
    xor eax, eax
    ret

; ============================================================
; rt_chr — Convert integer to 1-char string
; rdi = integer (0-255), returns rax = pointer to 1-char string
; ============================================================
global rt_chr
rt_chr:
    push rbp
    mov rbp, rsp
    push rdi
    mov rdi, 2
    call rt_alloc
    pop rdi
    mov byte [rax], dil
    mov byte [rax + 1], 0
    pop rbp
    ret

; ============================================================
; rt_substr — Extract substring str[start..end)
; rdi = string ptr, rsi = start index, rdx = end index
; Returns: rax = pointer to new string on heap
; ============================================================
global rt_substr
rt_substr:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    mov r12, rdi             ; source string
    mov r13, rsi             ; start
    mov r14, rdx             ; end
    ; Get string length
    call rt_str_len
    ; Clamp start
    cmp r13, 0
    jge .ss_start_ok
    xor r13, r13
.ss_start_ok:
    ; Clamp end
    cmp r14, rax
    jle .ss_end_ok
    mov r14, rax
.ss_end_ok:
    ; Check valid range
    cmp r13, r14
    jge .ss_empty
    ; Allocate (end - start + 1) bytes
    mov rdi, r14
    sub rdi, r13
    inc rdi                  ; +1 for null terminator
    call rt_alloc
    ; Copy bytes: src = r12 + r13, dest = rax, len = r14 - r13
    mov rcx, r14
    sub rcx, r13
    mov rsi, r12
    add rsi, r13             ; source + start
    mov rdi, rax             ; dest
    push rax                 ; save result ptr
    rep movsb
    mov byte [rdi], 0        ; null terminate (rdi points past copied data)
    pop rax
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
.ss_empty:
    mov rdi, 1
    call rt_alloc
    mov byte [rax], 0
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_find — Find index of value in array (-1 if not found)
; rdi = array ptr, rsi = value, returns rax = index or -1
; ============================================================
global rt_arr_find
rt_arr_find:
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rdi]           ; count
    lea r13, [rdi + 16]      ; elements start
    mov r14, rsi             ; value to find
    xor rbx, rbx             ; index = 0
    cmp r14, 0
    jl .af_int_loop
    mov rax, 0x400000
    cmp r14, rax
    jbe .af_int_loop
.af_str_loop:
    cmp rbx, r12
    je .af_not_found
    mov rdi, [r13 + rbx * 8]
    mov rsi, r14
    call rt_str_eq
    cmp rax, 1
    je .af_found
    inc rbx
    jmp .af_str_loop
.af_int_loop:
    cmp rbx, r12
    je .af_not_found
    cmp [r13 + rbx * 8], r14
    je .af_found
    inc rbx
    jmp .af_int_loop
.af_found:
    mov rax, rbx
    jmp .af_done
.af_not_found:
    mov rax, -1
.af_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; rt_find — Generic find: detects array vs string and dispatches
; rdi = array or string, rsi = value/substring
; Returns rax = index (-1 if not found)
; ============================================================
global rt_find
rt_find:
    ; Check if rdi is an array (pointer > 0x400000 AND [rdi] is small count)
    cmp rdi, 0x400000
    jb .find_str
    ; Could be string or array — check if [rdi] looks like an array count
    ; Array layout: [count:8][capacity:8][...], count < capacity
    ; String: first bytes are ASCII chars (usually < 128)
    ; Heuristic: if [rdi+8] > [rdi] and [rdi] < 0x100000, it's an array
    mov rax, [rdi]           ; potential count
    cmp rax, 0x100000
    jge .find_str            ; too large for array count
    mov rcx, [rdi + 8]      ; potential capacity
    cmp rcx, rax
    jl .find_str             ; capacity < count → not an array
    cmp rcx, 0x100000
    jge .find_str            ; capacity too large
    ; Looks like an array
    jmp rt_arr_find
.find_str:
    jmp rt_str_index

; ============================================================
; rt_arr_fill — Create array of n copies of value
; rdi = count, rsi = value, returns rax = new array ptr
; ============================================================
global rt_arr_fill
rt_arr_fill:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi             ; count
    mov r13, rsi             ; value
    ; Create new array with capacity = count
    mov rdi, r12
    cmp rdi, 8
    jge .fill_cap_ok
    mov rdi, 8
.fill_cap_ok:
    call rt_arr_new
    push rax                 ; save array ptr
    ; Push value n times
    xor rcx, rcx
.fill_loop:
    cmp rcx, r12
    je .fill_done
    push rcx
    pop rcx
    push rcx
    mov rdi, [rsp + 8]      ; array ptr (may have been reallocated)
    mov rsi, r13
    call rt_arr_push
    mov [rsp + 8], rax       ; update if reallocated
    pop rcx
    inc rcx
    jmp .fill_loop
.fill_done:
    pop rax
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_concat — Concatenate two arrays into a new one
; rdi = arr1, rsi = arr2, returns rax = new array
; ============================================================
global rt_arr_concat
rt_arr_concat:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi             ; arr1
    mov r13, rsi             ; arr2
    ; Total count
    mov r14, [r12]           ; arr1 count
    mov r15, [r13]           ; arr2 count
    mov rdi, r14
    add rdi, r15
    cmp rdi, 8
    jge .cc_cap_ok
    mov rdi, 8
.cc_cap_ok:
    call rt_arr_new
    push rax                 ; save result
    ; Copy arr1 elements
    xor rcx, rcx
.cc_loop1:
    cmp rcx, r14
    je .cc_loop2_start
    push rcx
    mov rdi, [rsp + 8]
    mov rsi, [r12 + 16 + rcx * 8]
    call rt_arr_push
    mov [rsp + 8], rax
    pop rcx
    inc rcx
    jmp .cc_loop1
.cc_loop2_start:
    xor rcx, rcx
.cc_loop2:
    cmp rcx, r15
    je .cc_done
    push rcx
    mov rdi, [rsp + 8]
    mov rsi, [r13 + 16 + rcx * 8]
    call rt_arr_push
    mov [rsp + 8], rax
    pop rcx
    inc rcx
    jmp .cc_loop2
.cc_done:
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_unique — Return new array with duplicates removed
; rdi = array ptr, returns rax = new array
; ============================================================
global rt_arr_unique
rt_arr_unique:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    mov r12, rdi             ; source array
    mov r13, [r12]           ; count
    xor rdi, rdi
    call rt_arr_new
    push rax                 ; result array
    xor r14, r14             ; index
.uniq_loop:
    cmp r14, r13
    je .uniq_done
    mov rsi, [r12 + 16 + r14 * 8]
    push rsi
    mov rdi, [rsp + 8]      ; result array
    call rt_arr_contains
    pop rsi
    cmp rax, 1
    je .uniq_skip
    ; Not in result yet — push it
    push rsi
    mov rdi, [rsp + 8]
    pop rsi
    call rt_arr_push
    mov [rsp], rax           ; update result ptr
.uniq_skip:
    inc r14
    jmp .uniq_loop
.uniq_done:
    pop rax
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_insert — Insert value at index, shift elements right
; rdi = array ptr, rsi = index, rdx = value, returns rax = array ptr
; ============================================================
global rt_arr_insert
rt_arr_insert:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi             ; array
    mov r13, rsi             ; index
    mov r14, rdx             ; value
    ; First push a dummy to ensure capacity
    mov rdi, r12
    mov rsi, 0
    call rt_arr_push
    mov r12, rax             ; potentially reallocated
    ; Now shift elements right from end to index
    mov r15, [r12]           ; new count (already incremented by push)
    dec r15                  ; last valid index
.ins_shift:
    cmp r15, r13
    jle .ins_place
    mov rax, [r12 + 16 + r15 * 8 - 8]
    mov [r12 + 16 + r15 * 8], rax
    dec r15
    jmp .ins_shift
.ins_place:
    mov [r12 + 16 + r13 * 8], r14
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_arr_remove — Remove element at index, shift elements left
; rdi = array ptr, rsi = index, returns rax = removed value
; ============================================================
global rt_arr_remove
rt_arr_remove:
    push r12
    push r13
    push r14
    mov r12, rdi             ; array
    mov r13, rsi             ; index
    mov r14, [r12]           ; count
    ; Bounds check
    cmp r13, r14
    jge .rem_oob
    ; Save removed value
    mov rax, [r12 + 16 + r13 * 8]
    push rax
    ; Shift left
    lea rcx, [r13 + 1]
.rem_shift:
    cmp rcx, r14
    je .rem_done
    mov rax, [r12 + 16 + rcx * 8]
    mov [r12 + 16 + rcx * 8 - 8], rax
    inc rcx
    jmp .rem_shift
.rem_done:
    dec qword [r12]
    pop rax
    pop r14
    pop r13
    pop r12
    ret
.rem_oob:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    ret

; ============================================================
; rt_pow — Integer exponentiation: rdi = base, rsi = exp, returns rax
; ============================================================
global rt_pow
rt_pow:
    mov rax, 1
    cmp rsi, 0
    je .pow_done
.pow_loop:
    imul rax, rdi
    dec rsi
    jnz .pow_loop
.pow_done:
    ret

; ============================================================
; rt_clamp — Clamp rdi to range [rsi, rdx]
; rdi = value, rsi = min, rdx = max, returns rax
; ============================================================
global rt_clamp
rt_clamp:
    mov rax, rdi
    cmp rax, rsi
    jge .clamp_not_low
    mov rax, rsi
    ret
.clamp_not_low:
    cmp rax, rdx
    jle .clamp_done
    mov rax, rdx
.clamp_done:
    ret

; ============================================================
; rt_sign — Sign of number: rdi = value, returns rax (-1, 0, 1)
; ============================================================
global rt_sign
rt_sign:
    cmp rdi, 0
    jg .sign_pos
    jl .sign_neg
    xor rax, rax
    ret
.sign_pos:
    mov rax, 1
    ret
.sign_neg:
    mov rax, -1
    ret

; ============================================================
; rt_gcd — Greatest common divisor (Euclidean)
; rdi = a, rsi = b, returns rax
; ============================================================
global rt_gcd
rt_gcd:
    mov rax, rdi
    mov rcx, rsi
    ; Make both positive
    cmp rax, 0
    jge .gcd_a_pos
    neg rax
.gcd_a_pos:
    cmp rcx, 0
    jge .gcd_loop
    neg rcx
.gcd_loop:
    cmp rcx, 0
    je .gcd_done
    xor rdx, rdx
    div rcx
    mov rax, rcx
    mov rcx, rdx
    jmp .gcd_loop
.gcd_done:
    ret

; ============================================================
; rt_arr_sum — Sum all elements in array
; rdi = array ptr, returns rax = sum
; ============================================================
global rt_arr_sum
rt_arr_sum:
    mov rcx, [rdi]           ; count
    xor rax, rax             ; sum = 0
    cmp rcx, 0
    je .sum_done
    lea rsi, [rdi + 16]      ; elements start at offset 16
.sum_loop:
    add rax, [rsi]
    add rsi, 8
    dec rcx
    jnz .sum_loop
.sum_done:
    ret

; ============================================================
; rt_arr_avg — Average of array elements (integer division)
; rdi = array ptr, returns rax = avg
; ============================================================
global rt_arr_avg
rt_arr_avg:
    push rdi
    call rt_arr_sum
    pop rdi
    mov rcx, [rdi]           ; count
    cmp rcx, 0
    je .avg_zero
    xor rdx, rdx
    idiv rcx
    ret
.avg_zero:
    xor rax, rax
    ret

; ============================================================
; rt_file_exists — Check if file exists
; rdi = filename string ptr, returns rax = 1 if exists, 0 if not
; ============================================================
global rt_file_exists
rt_file_exists:
    ; sys_access(filename, F_OK=0)
    mov rax, 21              ; sys_access
    mov rsi, 0               ; F_OK
    syscall
    cmp rax, 0
    jl .fexist_no
    mov rax, 1
    ret
.fexist_no:
    xor rax, rax
    ret

; ============================================================
; rt_file_delete — Delete a file
; rdi = filename string ptr, returns rax = 0 on success, -1 on error
; ============================================================
global rt_file_delete
rt_file_delete:
    mov rax, 87              ; sys_unlink
    syscall
    ret

; ============================================================
; rt_file_append — Append data to file
; rdi = filename string ptr, rsi = data string ptr
; returns rax = 0 on success
; ============================================================
global rt_file_append
rt_file_append:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi             ; filename
    mov r13, rsi             ; data
    ; Get data length
    mov rdi, r13
    call rt_str_len
    push rax                 ; data length
    ; Open file: O_WRONLY|O_CREAT|O_APPEND = 1|64|1024 = 1089
    mov rax, 2               ; sys_open
    mov rdi, r12
    mov rsi, 1089            ; O_WRONLY|O_CREAT|O_APPEND
    mov rdx, 0644o           ; permissions
    syscall
    cmp rax, 0
    jl .fappend_err
    mov r12, rax             ; fd
    ; Write data
    mov rax, 1               ; sys_write
    mov rdi, r12
    mov rsi, r13
    pop rdx                  ; data length
    syscall
    ; Close
    mov rax, 3               ; sys_close
    mov rdi, r12
    syscall
    xor rax, rax
    pop r13
    pop r12
    pop rbp
    ret
.fappend_err:
    add rsp, 8               ; clean data length
    mov rax, -1
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_file_lines — Read file as array of lines
; rdi = filename string ptr, returns rax = array of strings
; ============================================================
global rt_file_lines
rt_file_lines:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi             ; filename
    ; Read file contents
    call rt_file_read_str    ; rax = string content, or 0 on error
    cmp rax, 0
    je .flines_empty
    mov r13, rax             ; file content string
    ; Get content length
    mov rdi, r13
    call rt_str_len
    mov r14, rax             ; content length
    ; Create result array
    xor rdi, rdi
    call rt_arr_new
    mov r15, rax             ; result array
    ; Split by newline
    xor rcx, rcx             ; start of current line
.flines_loop:
    cmp rcx, r14
    jg .flines_done
    ; Find end of line (or end of string)
    mov r8, rcx              ; line start
.flines_find_nl:
    cmp r8, r14
    je .flines_emit
    movzx eax, byte [r13 + r8]
    cmp al, 10               ; newline
    je .flines_emit
    inc r8
    jmp .flines_find_nl
.flines_emit:
    ; Create substring from rcx to r8
    mov rdi, r8
    sub rdi, rcx
    inc rdi                  ; +1 for null
    push rcx
    push r8
    call rt_alloc
    pop r8
    pop rcx
    ; Copy bytes
    push rax
    xor r9, r9
.flines_copy:
    lea rdx, [rcx + r9]
    cmp rdx, r8
    je .flines_term
    lea rdx, [r13 + rcx]
    movzx edx, byte [rdx + r9]
    pop rax
    push rax
    mov [rax + r9], dl
    inc r9
    jmp .flines_copy
.flines_term:
    pop rax
    mov byte [rax + r9], 0
    ; Push line to array
    mov rdi, r15
    mov rsi, rax
    call rt_arr_push
    mov r15, rax             ; update if reallocated
    ; Move past newline
    lea rcx, [r8 + 1]
    jmp .flines_loop
.flines_done:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
.flines_empty:
    xor rdi, rdi
    call rt_arr_new
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_hex — Convert integer to hex string "0xNN..."
; rdi = value, returns rax = string ptr
; ============================================================
global rt_hex
rt_hex:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi             ; save value
    ; Allocate 20 bytes
    mov rdi, 20
    call rt_alloc
    mov r13, rax             ; result ptr
    cmp r12, 0
    jne .hex_nonzero
    mov byte [r13], '0'
    mov byte [r13 + 1], 0
    mov rax, r13
    pop r13
    pop r12
    pop rbp
    ret
.hex_nonzero:
    ; Build digits in reverse on stack
    sub rsp, 20
    xor rcx, rcx
    mov rdi, r12
    cmp rdi, 0
    jge .hex_loop
    neg rdi
.hex_loop:
    cmp rdi, 0
    je .hex_write
    mov rax, rdi
    and rax, 0xF
    cmp al, 10
    jl .hex_digit
    add al, 'a' - 10
    jmp .hex_store
.hex_digit:
    add al, '0'
.hex_store:
    mov [rsp + rcx], al
    inc rcx
    shr rdi, 4
    jmp .hex_loop
.hex_write:
    lea rsi, [r13]
    xor r8, r8
.hex_rev:
    cmp r8, rcx
    je .hex_done
    mov r9, rcx
    dec r9
    sub r9, r8
    movzx edx, byte [rsp + r9]
    mov [rsi + r8], dl
    inc r8
    jmp .hex_rev
.hex_done:
    mov byte [rsi + r8], 0
    add rsp, 20
    mov rax, r13
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_bin — Convert integer to binary string "0bNNN..."
; rdi = value, returns rax = string ptr
; ============================================================
global rt_bin
rt_bin:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi             ; save value
    mov rdi, 70
    call rt_alloc
    mov r13, rax             ; result ptr
    cmp r12, 0
    jne .bin_nonzero
    mov byte [r13], '0'
    mov byte [r13 + 1], 0
    mov rax, r13
    pop r13
    pop r12
    pop rbp
    ret
.bin_nonzero:
    sub rsp, 68
    xor rcx, rcx
    mov rdi, r12
    cmp rdi, 0
    jge .bin_loop
    neg rdi
.bin_loop:
    cmp rdi, 0
    je .bin_write
    mov rax, rdi
    and rax, 1
    add al, '0'
    mov [rsp + rcx], al
    inc rcx
    shr rdi, 1
    jmp .bin_loop
.bin_write:
    lea rsi, [r13]
    xor r8, r8
.bin_rev:
    cmp r8, rcx
    je .bin_done
    mov r9, rcx
    dec r9
    sub r9, r8
    movzx edx, byte [rsp + r9]
    mov [rsi + r8], dl
    inc r8
    jmp .bin_rev
.bin_done:
    mov byte [rsi + r8], 0
    add rsp, 68
    mov rax, r13
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_bool — Convert value to boolean (0 or 1)
; rdi = value (0, empty string, empty array = 0; else 1)
; returns rax = 0 or 1
; ============================================================
global rt_bool
rt_bool:
    cmp rdi, 0
    je .bool_false
    ; Check if it's a string pointer
    cmp rdi, 0x400000
    jb .bool_true
    ; Could be string or array — check first byte
    movzx eax, byte [rdi]
    cmp al, 0
    je .bool_false           ; empty string
    ; Check if array with count 0
    mov rax, [rdi]
    cmp rax, 0
    je .bool_check_arr
    jmp .bool_true
.bool_check_arr:
    ; [rdi] = 0 could be empty array or empty string (first byte 0)
    ; Already checked first byte above for string, so this is array
    jmp .bool_false
.bool_true:
    mov rax, 1
    ret
.bool_false:
    xor rax, rax
    ret

; ============================================================
; rt_time — Return current unix timestamp (seconds since epoch)
; No args, returns seconds in rax
; ============================================================
global rt_time
rt_time:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    ; clock_gettime(CLOCK_REALTIME=0, &timespec)
    mov rax, 228             ; sys_clock_gettime
    xor rdi, rdi             ; CLOCK_REALTIME = 0
    lea rsi, [rbp - 16]     ; timespec on stack
    syscall
    mov rax, [rbp - 16]     ; tv_sec
    leave
    ret

; ============================================================
; rt_clock — Return monotonic nanoseconds for benchmarking
; No args, returns nanoseconds in rax
; ============================================================
global rt_clock
rt_clock:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    ; clock_gettime(CLOCK_MONOTONIC=1, &timespec)
    mov rax, 228             ; sys_clock_gettime
    mov rdi, 1               ; CLOCK_MONOTONIC
    lea rsi, [rbp - 16]
    syscall
    mov rax, [rbp - 16]     ; tv_sec
    imul rax, 1000000000     ; sec * 1e9
    add rax, [rbp - 8]      ; + tv_nsec
    leave
    ret

; ============================================================
; rt_sleep — Sleep for rdi seconds
; rdi = seconds to sleep
; ============================================================
global rt_sleep
rt_sleep:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    mov [rbp - 16], rdi      ; tv_sec = seconds
    mov qword [rbp - 8], 0   ; tv_nsec = 0
    ; nanosleep(&req, NULL)
    mov rax, 35               ; sys_nanosleep
    lea rdi, [rbp - 16]      ; req
    xor rsi, rsi              ; rem = NULL
    syscall
    xor rax, rax
    leave
    ret

; ============================================================
; rt_args — Return command-line args as SEVEN array
; Uses saved_rsp to access argc/argv from _start
; Returns array pointer in rax
; ============================================================
global rt_args
global saved_rsp
rt_args:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14

    ; saved_rsp points to original stack at _start
    ; Linux stack at _start: [argc][argv[0]][argv[1]]...[NULL][envp...]
    mov r12, [saved_rsp]     ; original rsp
    mov r13, [r12]           ; argc
    lea r14, [r12 + 8]       ; &argv[0]

    ; Create new array
    mov rdi, r13
    call rt_arr_new          ; rax = new array
    push rax                 ; save array ptr

    ; Push each argv string
    xor r12, r12             ; i = 0
.args_loop:
    cmp r12, r13
    jge .args_done
    mov rdi, [r14 + r12 * 8] ; argv[i] (C string ptr)
    ; Need to copy to heap since argv strings are on stack
    ; Find length
    push rdi
    xor rcx, rcx
.args_strlen:
    cmp byte [rdi + rcx], 0
    je .args_strlen_done
    inc rcx
    jmp .args_strlen
.args_strlen_done:
    ; Allocate rcx+1 bytes
    push rcx
    lea rdi, [rcx + 1]
    call rt_alloc            ; rax = heap ptr
    pop rcx
    pop rsi                  ; original string ptr
    ; Copy
    push rax
    push rcx
    mov rdi, rax
.args_copy:
    cmp rcx, 0
    je .args_copy_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .args_copy
.args_copy_done:
    mov byte [rdi], 0        ; null terminate
    pop rcx
    pop rax                  ; heap string ptr
    ; Push to array: rdi=array, rsi=value
    mov rsi, rax
    mov rdi, [rsp]           ; array ptr
    call rt_arr_push
    inc r12
    jmp .args_loop
.args_done:
    pop rax                  ; return array
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_env — Get environment variable value
; rdi = variable name (string ptr)
; Returns: string ptr in rax, or 0 if not found
; ============================================================
global rt_env
rt_env:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; name to find

    ; Find name length
    xor r13, r13
.env_namelen:
    cmp byte [r12 + r13], 0
    je .env_namelen_done
    inc r13
    jmp .env_namelen

.env_namelen_done:
    ; Walk envp: after argv on the stack
    ; saved_rsp -> [argc][argv[0]]...[argv[argc-1]][NULL][envp[0]]...
    mov r14, [saved_rsp]
    mov rax, [r14]           ; argc
    lea r14, [r14 + 8 + rax * 8 + 8] ; skip argc + argv + NULL

.env_loop:
    mov r15, [r14]           ; envp[i]
    test r15, r15
    jz .env_not_found        ; NULL = end of env

    ; Compare name: check if envp[i] starts with name + '='
    xor rcx, rcx
.env_cmp:
    cmp rcx, r13
    je .env_check_eq         ; matched all name chars
    movzx eax, byte [r12 + rcx]
    cmp al, byte [r15 + rcx]
    jne .env_next
    inc rcx
    jmp .env_cmp

.env_check_eq:
    cmp byte [r15 + rcx], '='
    jne .env_next

    ; Found! Copy value part (after '=') to heap
    lea rsi, [r15 + rcx + 1] ; value start
    ; Find value length
    xor rdx, rdx
.env_vallen:
    cmp byte [rsi + rdx], 0
    je .env_vallen_done
    inc rdx
    jmp .env_vallen
.env_vallen_done:
    ; Allocate and copy
    push rsi
    push rdx
    lea rdi, [rdx + 1]
    call rt_alloc
    pop rdx
    pop rsi
    mov rdi, rax
    push rax
    mov rcx, rdx
.env_copy:
    cmp rcx, 0
    je .env_copy_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .env_copy
.env_copy_done:
    mov byte [rdi], 0
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.env_next:
    add r14, 8
    jmp .env_loop

.env_not_found:
    xor rax, rax             ; return 0 (empty/null)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_system — Execute shell command
; rdi = command string ptr
; Returns exit code in rax
; ============================================================
global rt_system
rt_system:
    push rbp
    mov rbp, rsp
    push r12

    mov r12, rdi             ; save command

    ; fork()
    mov rax, 57              ; sys_fork
    syscall
    test rax, rax
    jz .system_child
    ; Parent: wait for child
    push rax                 ; save child pid
    ; wait4(pid, &status, 0, NULL)
    mov rdi, rax             ; pid
    lea rsi, [rbp - 24]     ; &status (use stack space)
    xor rdx, rdx             ; options = 0
    xor r10, r10             ; rusage = NULL
    mov rax, 61              ; sys_wait4
    syscall
    ; Get exit status: WEXITSTATUS = (status >> 8) & 0xff
    mov eax, [rbp - 24]
    shr eax, 8
    and eax, 0xff
    movzx rax, al
    pop rcx                  ; discard child pid
    pop r12
    pop rbp
    ret

.system_child:
    ; execve("/bin/sh", ["/bin/sh", "-c", cmd, NULL], envp)
    ; Build argv on stack
    sub rsp, 32
    lea rax, [rel .sh_path]
    mov [rsp], rax           ; argv[0] = "/bin/sh"
    lea rax, [rel .sh_c_flag]
    mov [rsp + 8], rax       ; argv[1] = "-c"
    mov [rsp + 16], r12      ; argv[2] = command
    mov qword [rsp + 24], 0  ; argv[3] = NULL
    ; execve
    lea rdi, [rel .sh_path]  ; filename
    mov rsi, rsp             ; argv
    ; Get envp from saved_rsp
    mov rdx, [saved_rsp]
    mov rax, [rdx]           ; argc
    lea rdx, [rdx + 8 + rax * 8 + 8] ; envp
    mov rax, 59              ; sys_execve
    syscall
    ; If exec fails, exit child
    mov rax, 60
    mov rdi, 127
    syscall

section .rodata
.sh_path:   db "/bin/sh", 0
.sh_c_flag: db "-c", 0

section .text

; ============================================================
; rt_assert — Assert condition is truthy
; rdi = condition value, rsi = message string ptr (0 if none)
; If condition is 0, prints message to stderr and exits with 1
; ============================================================
global rt_assert
rt_assert:
    test rdi, rdi
    jnz .pass
    ; assertion failed
    push rsi
    ; print "Assertion failed"
    mov rax, 1          ; write
    mov rdi, 2          ; stderr
    lea rsi, [rel .assert_prefix]
    mov rdx, 19
    syscall
    pop rsi
    ; print message if provided
    test rsi, rsi
    jz .no_msg
    cmp rsi, 0x400000
    jb .no_msg
    ; find length
    push rsi
    xor rcx, rcx
.msg_len:
    cmp byte [rsi+rcx], 0
    je .msg_done
    inc rcx
    jmp .msg_len
.msg_done:
    mov rdx, rcx
    pop rsi
    mov rax, 1
    mov rdi, 2
    syscall
.no_msg:
    ; print newline
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .assert_nl]
    mov rdx, 1
    syscall
    ; exit with code 1
    mov rdi, 1
    mov rax, 60
    syscall
.pass:
    mov rax, 1
    ret

section .rodata
.assert_prefix: db "Assertion failed: "
.assert_nl:     db 10

section .text

; ============================================================
; rt_exit — Exit with code in rdi
; ============================================================
global rt_exit
rt_exit:
    mov rax, 60
    syscall

; ============================================================
; MAP DATA STRUCTURE
; Layout: [count:8][capacity:8][entry0_key_ptr:8][entry0_key_len:8][entry0_value:8]...
; Each entry = 24 bytes (key_ptr, key_len, value)
; Total size = 16 + capacity * 24
; Uses linear scan (fast enough for compiler symbol tables < 10k entries)
; ============================================================

; ============================================================
; rt_map_new — Create a new empty map
; rdi = initial capacity (0 = default 64)
; Returns: rax = map pointer
; ============================================================
global rt_map_new
rt_map_new:
    push rbp
    mov rbp, rsp
    push r12
    cmp rdi, 0
    jne .has_cap
    mov rdi, 64
.has_cap:
    mov r12, rdi              ; save capacity
    ; allocate: 16 (header) + capacity * 24 (entries)
    imul rdi, 24
    add rdi, 16
    call rt_alloc
    mov qword [rax], 0        ; count = 0
    mov [rax + 8], r12         ; capacity
    ; zero out all entries (key_ptr=0 means empty)
    xor rcx, rcx
.zero_loop:
    cmp rcx, r12
    jge .zero_done
    lea rdx, [rax + 16]
    imul r8, rcx, 24
    mov qword [rdx + r8], 0        ; key_ptr = 0
    mov qword [rdx + r8 + 8], 0    ; key_len = 0
    mov qword [rdx + r8 + 16], 0   ; value = 0
    inc rcx
    jmp .zero_loop
.zero_done:
    pop r12
    pop rbp
    ret

; ============================================================
; rt_map_find_slot — Internal: find entry index for key
; rdi = map ptr, rsi = key ptr, rdx = key len
; Returns: rax = entry index (0-based), or -1 if not found
; ============================================================
rt_map_find_slot:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi              ; map
    mov r13, rsi              ; key ptr
    mov r14, rdx              ; key len
    mov r15, [r12]            ; count
    xor rcx, rcx              ; index
.find_loop:
    cmp rcx, r15
    jge .find_notfound
    lea rax, [r12 + 16]       ; entries base
    imul r8, rcx, 24
    mov rdi, [rax + r8]       ; entry key_ptr
    test rdi, rdi
    jz .find_next             ; empty slot
    mov rsi, [rax + r8 + 8]   ; entry key_len
    cmp rsi, r14
    jne .find_next            ; different length
    ; Compare key bytes
    push rcx
    mov rsi, r13              ; our key
    mov rdx, r14              ; length
    ; rdi = entry key (already set)
    ; rsi = search key
    ; rdx = length
    xor rcx, rcx
.cmp_loop:
    cmp rcx, rdx
    je .cmp_match
    movzx r8, byte [rdi + rcx]
    movzx r9, byte [rsi + rcx]
    cmp r8, r9
    jne .cmp_no
    inc rcx
    jmp .cmp_loop
.cmp_match:
    pop rcx
    mov rax, rcx              ; found at index
    jmp .find_done
.cmp_no:
    pop rcx
.find_next:
    inc rcx
    jmp .find_loop
.find_notfound:
    mov rax, -1
.find_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_map_set — Set key-value pair in map
; rdi = map ptr, rsi = key ptr (string), rdx = value
; Returns: rax = map ptr (may be new if grown)
; ============================================================
global rt_map_set
rt_map_set:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi              ; map
    mov r14, rdx              ; value
    ; Get key length
    mov r13, rsi              ; key ptr
    push r14
    mov rdi, rsi
    call rt_str_len
    mov r15, rax              ; key len
    pop r14
    ; Find existing slot
    mov rdi, r12
    mov rsi, r13
    mov rdx, r15
    call rt_map_find_slot
    cmp rax, -1
    je .set_new
    ; Update existing entry
    lea rdx, [r12 + 16]
    imul rax, 24
    mov [rdx + rax + 16], r14 ; update value
    mov rax, r12
    jmp .set_done
.set_new:
    ; Check if need to grow
    mov rcx, [r12]            ; count
    mov rdx, [r12 + 8]        ; capacity
    cmp rcx, rdx
    jl .set_append
    ; Grow: allocate new map with 2x capacity
    push r13
    push r14
    push r15
    shl rdx, 1                ; new capacity
    mov rdi, rdx
    push rdx
    imul rdi, 24
    add rdi, 16
    call rt_alloc
    pop rdx
    mov qword [rax], 0        ; count = 0
    mov [rax + 8], rdx         ; new capacity
    ; Zero new entries
    xor rcx, rcx
.grow_zero:
    cmp rcx, rdx
    jge .grow_copy
    lea r8, [rax + 16]
    imul r9, rcx, 24
    mov qword [r8 + r9], 0
    mov qword [r8 + r9 + 8], 0
    mov qword [r8 + r9 + 16], 0
    inc rcx
    jmp .grow_zero
.grow_copy:
    ; Copy old entries
    mov rcx, [r12]            ; old count
    xor r8, r8
.copy_entries:
    cmp r8, rcx
    jge .copy_done
    lea r9, [r12 + 16]
    imul r10, r8, 24
    lea r11, [rax + 16]
    ; Copy 24 bytes
    mov rdi, [r9 + r10]
    mov [r11 + r10], rdi
    mov rdi, [r9 + r10 + 8]
    mov [r11 + r10 + 8], rdi
    mov rdi, [r9 + r10 + 16]
    mov [r11 + r10 + 16], rdi
    inc r8
    jmp .copy_entries
.copy_done:
    mov [rax], rcx            ; restore count
    mov r12, rax              ; use new map
    pop r15
    pop r14
    pop r13
.set_append:
    ; Append new entry at count position
    mov rcx, [r12]            ; count
    lea rdx, [r12 + 16]
    imul rax, rcx, 24
    mov [rdx + rax], r13      ; key_ptr
    mov [rdx + rax + 8], r15  ; key_len
    mov [rdx + rax + 16], r14 ; value
    inc qword [r12]           ; count++
    mov rax, r12
.set_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_map_get — Get value by key from map
; rdi = map ptr, rsi = key ptr (string)
; Returns: rax = value, or 0 if not found
; ============================================================
global rt_map_get
rt_map_get:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi              ; map
    ; Get key length
    mov rdi, rsi
    push rsi
    call rt_str_len
    pop rsi
    mov rdx, rax              ; key len
    mov rdi, r12
    ; rsi = key ptr (already)
    call rt_map_find_slot
    cmp rax, -1
    je .get_notfound
    lea rdx, [r12 + 16]
    imul rax, 24
    mov rax, [rdx + rax + 16] ; return value
    jmp .get_done
.get_notfound:
    xor rax, rax              ; return 0
.get_done:
    pop r12
    pop rbp
    ret

; ============================================================
; rt_map_has — Check if key exists in map
; rdi = map ptr, rsi = key ptr (string)
; Returns: rax = 1 if found, 0 if not
; ============================================================
global rt_map_has
rt_map_has:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi              ; map
    mov rdi, rsi
    push rsi
    call rt_str_len
    pop rsi
    mov rdx, rax              ; key len
    mov rdi, r12
    call rt_map_find_slot
    cmp rax, -1
    je .has_no
    mov rax, 1
    jmp .has_done
.has_no:
    xor rax, rax
.has_done:
    pop r12
    pop rbp
    ret

; ============================================================
; rt_map_keys — Get all keys as an array of strings
; rdi = map ptr
; Returns: rax = array ptr (SEVEN array)
; ============================================================
global rt_map_keys
rt_map_keys:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    mov r12, rdi              ; map
    mov r13, [r12]            ; count
    ; Create array with capacity = count
    mov rdi, r13
    cmp rdi, 0
    jne .keys_has_cap
    mov rdi, 1
.keys_has_cap:
    call rt_arr_new
    mov r14, rax              ; array
    ; Add each key
    xor rcx, rcx
.keys_loop:
    cmp rcx, r13
    jge .keys_done
    push rcx
    lea rdx, [r12 + 16]
    imul rax, rcx, 24
    mov rdi, [rdx + rax]      ; key_ptr
    test rdi, rdi
    jz .keys_skip
    ; Copy key to new string (so it's a proper heap string)
    mov rsi, [rdx + rax + 8]  ; key_len
    push rsi
    push rdi
    mov rdi, rsi
    add rdi, 1                ; +1 for null terminator
    call rt_alloc
    pop rsi                   ; original key_ptr
    pop rdx                   ; key_len
    push rax                  ; save new string ptr
    ; Copy bytes
    xor rcx, rcx
.keys_copy:
    cmp rcx, rdx
    jge .keys_copy_done
    movzx r8, byte [rsi + rcx]
    mov [rax + rcx], r8b
    inc rcx
    jmp .keys_copy
.keys_copy_done:
    mov byte [rax + rdx], 0   ; null terminate
    pop rsi                   ; new string ptr = value to push
    mov rdi, r14              ; array
    call rt_arr_push
    mov r14, rax              ; arr_push may return new array
    jmp .keys_next
.keys_skip:
.keys_next:
    pop rcx
    inc rcx
    jmp .keys_loop
.keys_done:
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_map_delete — Remove a key from map
; rdi = map ptr, rsi = key ptr (string)
; Returns: rax = 1 if deleted, 0 if not found
; ============================================================
global rt_map_delete
rt_map_delete:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rdi              ; map
    mov rdi, rsi
    push rsi
    call rt_str_len
    pop rsi
    mov rdx, rax              ; key len
    mov rdi, r12
    call rt_map_find_slot
    cmp rax, -1
    je .del_notfound
    ; Found — shift remaining entries down
    mov r13, rax              ; slot to remove
    lea rdx, [r12 + 16]       ; entries base
    mov rcx, [r12]            ; count
    dec rcx
.del_shift:
    cmp r13, rcx
    jge .del_shift_done
    ; entry[r13] = entry[r13+1]
    imul r8, r13, 24
    lea r9, [r13 + 1]
    imul r9, 24
    mov rax, [rdx + r9]
    mov [rdx + r8], rax
    mov rax, [rdx + r9 + 8]
    mov [rdx + r8 + 8], rax
    mov rax, [rdx + r9 + 16]
    mov [rdx + r8 + 16], rax
    inc r13
    jmp .del_shift
.del_shift_done:
    dec qword [r12]           ; count--
    mov rax, 1
    jmp .del_done
.del_notfound:
    xor rax, rax
.del_done:
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; rt_map_count — Get number of entries in map
; rdi = map ptr
; Returns: rax = count
; ============================================================
global rt_map_count
rt_map_count:
    mov rax, [rdi]
    ret

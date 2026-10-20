; ============================================================
; SEVEN Language - Interpreter
; Direct execution from token stream (no code generation)
; Architecture: x86-64 NASM Assembly (Linux ELF64)
; Author: Tejas Chandivakar
; ============================================================
;
; Reuses the lexer's token stream. Instead of emitting assembly,
; evaluates expressions and executes statements directly.
;
; Token format (from lexer): 16 bytes per token
;   [type:1][subtype:1][padding:2][length:4][pointer:8]
; ============================================================

section .data
    ; Token type constants (must match lexer)
    TOK_EOF     equ 0
    TOK_IDENT   equ 1
    TOK_INT     equ 2
    TOK_FLOAT   equ 3
    TOK_STRING  equ 4
    TOK_KEYWORD equ 5
    TOK_OP      equ 6
    TOK_PUNCT   equ 7
    TOK_NEWLINE equ 8
    TOK_DOT     equ 9

    ; Operator subtypes
    OP_PLUS     equ 1
    OP_MINUS    equ 2
    OP_STAR     equ 3
    OP_SLASH    equ 4
    OP_PERCENT  equ 5
    OP_DSTAR    equ 6
    OP_DSLASH   equ 7
    OP_EQ       equ 8
    OP_NEQ      equ 9
    OP_LT       equ 10
    OP_GT       equ 11
    OP_LTE      equ 12
    OP_GTE      equ 13
    OP_ASSIGN   equ 14
    OP_AMP      equ 15
    OP_PIPE     equ 16
    OP_CARET    equ 17
    OP_TILDE    equ 18
    OP_LSHIFT   equ 19
    OP_RSHIFT   equ 20

    ; Punct subtypes
    PUNCT_LPAREN   equ 1
    PUNCT_RPAREN   equ 2
    PUNCT_LBRACKET equ 3
    PUNCT_RBRACKET equ 4
    PUNCT_COMMA    equ 5

    ; Error messages
    interp_err_unknown db "Interpreter error: unknown statement", 10, 0
    interp_err_unknown_len equ $ - interp_err_unknown
    interp_err_divzero db "Error: Division by zero", 10, 0
    interp_err_divzero_len equ $ - interp_err_divzero
    interp_err_var db "Error: Undefined variable: ", 0
    interp_err_var_len equ $ - interp_err_var
    interp_err_func db "Error: Undefined function: ", 0
    interp_err_func_len equ $ - interp_err_func
    interp_newline db 10, 0

    ; Boolean string constants
    str_true db "true", 0
    str_false db "false", 0
    str_null db "null", 0

    ; Type strings
    str_type_int db "int", 0
    str_type_string db "string", 0
    str_type_array db "array", 0

    ; Assert prefix
    str_assert_fail db "Assertion failed: ", 0
    str_assert_fail_len equ 18

section .bss
    ; Token position
    ip_pos      resq 1

    ; Variable storage (name pointer, name length, value) — max 512 variables
    var_names   resq 512        ; pointers to name text
    var_nlens   resq 512        ; name lengths
    var_vals    resq 512        ; values (integer or string pointer)
    var_count   resq 1

    ; Function storage — max 128 functions
    func_names  resq 128        ; pointers to function name
    func_nlens  resq 128        ; name lengths
    func_starts resq 128        ; token position where body starts
    func_param_counts resq 128  ; number of parameters
    func_param_names  resq 1024 ; parameter names (8 per func * 128)
    func_param_nlens  resq 1024 ; parameter name lengths
    func_count  resq 1

    ; Call stack for function args — max depth 32, 8 args each
    call_arg_vals resq 256      ; 32 * 8 args
    call_arg_count resq 32
    call_depth  resq 1

    ; Saved variable snapshots for function scoping
    save_vals   resq 512        ; backup of var_vals per call
    save_count  resq 32         ; backup of var_count per call

    ; Loop control
    loop_depth  resq 1
    loop_skip_flag resq 1       ; 1 = skip (continue)
    loop_stop_flag resq 1       ; 1 = stop (break)

    ; Return value
    return_val  resq 1
    return_flag resq 1          ; 1 = return was hit

    ; Expression evaluation stack — max 64 entries
    eval_stack  resq 64
    eval_sp     resq 1

    ; String scratch buffer for building strings
    str_scratch resb 4096

    ; Array storage — max 64 arrays, each up to 256 elements
    arr_storage resq 16384      ; 64 * 256 elements
    arr_lengths resq 64         ; length of each array
    arr_count   resq 1
    arr_ptrs    resq 64         ; pointers into arr_storage

    ; Exit code
    interp_exit_code resq 1

section .text
    extern lexer_get_token, lexer_token_count
    extern kw_show, kw_err, kw_if, kw_elif, kw_else, kw_end
    extern kw_repeat, kw_times, kw_while, kw_each, kw_as
    extern kw_func, kw_return, kw_skip, kw_stop
    extern kw_true, kw_false, kw_null
    extern kw_and, kw_or, kw_not
    extern kw_in, kw_is, kw_isnt, kw_above, kw_below, kw_atleast, kw_atmost
    extern kw_try, kw_catch, kw_error, kw_push
    extern kw_ask, kw_write, kw_read, kw_many, kw_match, kw_case
    extern kw_mode
    extern rt_init
    extern rt_print_str, rt_print_int, rt_print_newline
    extern rt_print_val, rt_str_len, rt_str_concat
    extern rt_int_to_str, rt_str_to_int, rt_str_copy
    extern rt_str_eq
    extern rt_alloc
    extern rt_prompt, rt_read_line
    extern rt_print_str_err
    extern rt_str_upper, rt_str_lower, rt_str_trim
    extern rt_str_replace, rt_str_contains
    extern rt_str_startswith, rt_str_endswith
    extern rt_str_index, rt_str_split, rt_str_repeat
    extern rt_len
    extern rt_abs, rt_min, rt_max, rt_sqrt, rt_random
    extern rt_type
    extern rt_range
    extern rt_arr_new, rt_arr_push, rt_arr_get, rt_arr_set, rt_arr_len
    extern rt_arr_sort, rt_arr_join, rt_arr_reverse
    extern rt_arr_slice, rt_arr_contains, rt_arr_step
    extern rt_arr_pop

; ============================================================
; interp_init — Initialize interpreter state
; ============================================================
global interp_init
interp_init:
    call rt_init
    mov qword [ip_pos], 0
    mov qword [var_count], 0
    mov qword [func_count], 0
    mov qword [call_depth], 0
    mov qword [loop_depth], 0
    mov qword [loop_skip_flag], 0
    mov qword [loop_stop_flag], 0
    mov qword [return_val], 0
    mov qword [return_flag], 0
    mov qword [eval_sp], 0
    mov qword [arr_count], 0
    mov qword [interp_exit_code], 0
    ret

; ============================================================
; interp_program — Main interpreter loop
; Returns: rax = exit code
; ============================================================
global interp_program
interp_program:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    ; Skip mode declaration if present
    call ip_skip_nl
    lea rdi, [kw_mode]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    jne .no_mode
    call ip_advance          ; skip 'mode'
    call ip_advance          ; skip 'hybrid'/'natural'
.no_mode:

.stmt_loop:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .done

    call interp_stmt
    jmp .stmt_loop

.done:
    mov rax, [interp_exit_code]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; Token stream helpers (mirrors codegen's cg_* functions)
; ============================================================

; ip_peek — Get current token pointer
ip_peek:
    mov rdi, [ip_pos]
    call lexer_get_token
    ret

; ip_advance — Consume current token, return pointer
ip_advance:
    mov rdi, [ip_pos]
    call lexer_get_token
    inc qword [ip_pos]
    ret

; ip_skip_nl — Skip newline tokens
ip_skip_nl:
.loop:
    call ip_peek
    movzx ecx, byte [rax]
    cmp cl, TOK_NEWLINE
    jne .done
    call ip_advance
    jmp .loop
.done:
    ret

; ip_tok_type — Return type of current token in al
ip_tok_type:
    call ip_peek
    movzx eax, byte [rax]
    ret

; ip_tok_sub — Return subtype of current token in al
ip_tok_sub:
    call ip_peek
    movzx eax, byte [rax + 1]
    ret

; ip_is_kw — Check if current token matches keyword
; rdi = keyword text, rsi = length
; Returns: rax = 1 if match, 0 if not
ip_is_kw:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call ip_peek
    movzx ecx, byte [rax]
    cmp cl, TOK_KEYWORD
    jne .no
    mov ecx, [rax + 4]
    cmp rcx, r13
    jne .no
    mov rdi, [rax + 8]
    mov rsi, r12
    mov rcx, r13
.cmp:
    cmp rcx, 0
    je .yes
    movzx eax, byte [rdi]
    cmp al, [rsi]
    jne .no
    inc rdi
    inc rsi
    dec rcx
    jmp .cmp
.yes:
    mov rax, 1
    pop r13
    pop r12
    ret
.no:
    xor rax, rax
    pop r13
    pop r12
    ret

; ip_is_ident — Check if current token is identifier matching text
; rdi = name, rsi = length
; Returns: rax = 1 if match, 0 if not
ip_is_ident:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call ip_peek
    movzx ecx, byte [rax]
    cmp cl, TOK_IDENT
    jne .no
    mov ecx, [rax + 4]
    cmp rcx, r13
    jne .no
    mov rdi, [rax + 8]
    mov rsi, r12
    mov rcx, r13
.cmp:
    cmp rcx, 0
    je .yes
    movzx eax, byte [rdi]
    cmp al, [rsi]
    jne .no
    inc rdi
    inc rsi
    dec rcx
    jmp .cmp
.yes:
    mov rax, 1
    pop r13
    pop r12
    ret
.no:
    xor rax, rax
    pop r13
    pop r12
    ret

; ip_tok_text_match — Check if current token text matches
; rdi = text, rsi = length
; Returns: rax = 1 if match, 0 if not
ip_tok_text_match:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call ip_peek
    mov ecx, [rax + 4]
    cmp rcx, r13
    jne .no
    mov rdi, [rax + 8]
    mov rsi, r12
    mov rcx, r13
.cmp:
    cmp rcx, 0
    je .yes
    movzx eax, byte [rdi]
    cmp al, [rsi]
    jne .no
    inc rdi
    inc rsi
    dec rcx
    jmp .cmp
.yes:
    mov rax, 1
    pop r13
    pop r12
    ret
.no:
    xor rax, rax
    pop r13
    pop r12
    ret

; ============================================================
; Variable helpers
; ============================================================

; var_set — Set variable value
; rdi = name pointer, rsi = name length, rdx = value
var_set:
    push r12
    push r13
    push r14
    mov r12, rdi             ; name ptr
    mov r13, rsi             ; name len
    mov r14, rdx             ; value

    ; Search existing
    xor rcx, rcx
.search:
    cmp rcx, [var_count]
    jge .new
    cmp r13, [var_nlens + rcx * 8]
    jne .next
    ; Compare names
    push rcx
    mov rdi, [var_names + rcx * 8]
    mov rsi, r12
    mov rdx, r13
.cmpn:
    cmp rdx, 0
    je .found
    movzx eax, byte [rdi]
    cmp al, [rsi]
    jne .not_match
    inc rdi
    inc rsi
    dec rdx
    jmp .cmpn
.found:
    pop rcx
    mov [var_vals + rcx * 8], r14
    pop r14
    pop r13
    pop r12
    ret
.not_match:
    pop rcx
.next:
    inc rcx
    jmp .search

.new:
    mov rcx, [var_count]
    mov [var_names + rcx * 8], r12
    mov [var_nlens + rcx * 8], r13
    mov [var_vals + rcx * 8], r14
    inc qword [var_count]
    pop r14
    pop r13
    pop r12
    ret

; var_get — Get variable value
; rdi = name pointer, rsi = name length
; Returns: rax = value (0 if not found)
var_get:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor rcx, rcx
.search:
    cmp rcx, [var_count]
    jge .not_found
    cmp r13, [var_nlens + rcx * 8]
    jne .next
    push rcx
    mov rdi, [var_names + rcx * 8]
    mov rsi, r12
    mov rdx, r13
.cmpn:
    cmp rdx, 0
    je .found
    movzx eax, byte [rdi]
    cmp al, [rsi]
    jne .not_match
    inc rdi
    inc rsi
    dec rdx
    jmp .cmpn
.found:
    pop rcx
    mov rax, [var_vals + rcx * 8]
    pop r13
    pop r12
    ret
.not_match:
    pop rcx
.next:
    inc rcx
    jmp .search
.not_found:
    xor rax, rax
    pop r13
    pop r12
    ret

; ============================================================
; Function storage helpers
; ============================================================

; func_register — Register a function
; rdi = name pointer, rsi = name length, rdx = token start pos
func_register:
    push r12
    mov r12, [func_count]
    mov [func_names + r12 * 8], rdi
    mov [func_nlens + r12 * 8], rsi
    mov [func_starts + r12 * 8], rdx
    inc qword [func_count]
    pop r12
    ret

; func_find — Find function by name
; rdi = name pointer, rsi = name length
; Returns: rax = index (or -1 if not found)
func_find:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor rcx, rcx
.search:
    cmp rcx, [func_count]
    jge .not_found
    cmp r13, [func_nlens + rcx * 8]
    jne .next
    push rcx
    mov rdi, [func_names + rcx * 8]
    mov rsi, r12
    mov rdx, r13
.cmpn:
    cmp rdx, 0
    je .found
    movzx eax, byte [rdi]
    cmp al, [rsi]
    jne .not_match
    inc rdi
    inc rsi
    dec rdx
    jmp .cmpn
.found:
    pop rax
    pop r13
    pop r12
    ret
.not_match:
    pop rcx
.next:
    inc rcx
    jmp .search
.not_found:
    mov rax, -1
    pop r13
    pop r12
    ret

; ============================================================
; ip_skip_block — Skip tokens until matching 'end' at depth 0
; Tracks nesting of if/repeat/while/each/func/try/match blocks
; After return, ip_pos is past the matching 'end'
; ============================================================
ip_skip_block:
    push rbp
    mov rbp, rsp
    push r14
    mov r14, 1               ; depth
.loop:
    call ip_tok_type
    cmp al, TOK_EOF
    je .done

    ; Check block-opening keywords
    cmp al, TOK_KEYWORD
    jne .advance

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    jne .not_end
    dec r14
    cmp r14, 0
    jle .found_end
    call ip_advance
    jmp .loop
.not_end:
    lea rdi, [kw_if]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    je .nest
    lea rdi, [kw_repeat]
    mov rsi, 6
    call ip_is_kw
    cmp rax, 1
    je .nest
    lea rdi, [kw_while]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .nest
    lea rdi, [kw_each]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .nest
    lea rdi, [kw_func]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .nest
    lea rdi, [kw_try]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .nest
    lea rdi, [kw_match]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .nest
    jmp .advance
.nest:
    inc r14
.advance:
    call ip_advance
    jmp .loop
.found_end:
    call ip_advance          ; skip 'end'
.done:
    pop r14
    pop rbp
    ret

; ============================================================
; interp_stmt — Execute one statement
; ============================================================
interp_stmt:
    push rbp
    mov rbp, rsp

    ; Check control flags
    cmp qword [return_flag], 1
    je .skip_stmt
    cmp qword [loop_stop_flag], 1
    je .skip_stmt
    cmp qword [loop_skip_flag], 1
    je .skip_stmt

    call ip_skip_nl
    call ip_tok_type

    cmp al, TOK_KEYWORD
    je .kw_dispatch
    cmp al, TOK_IDENT
    je .ident_stmt
    cmp al, TOK_EOF
    je .done

    ; Skip unknown token
    call ip_advance
    pop rbp
    ret

.skip_stmt:
    ; When return/skip/stop is active, skip to next newline or EOF
    call ip_tok_type
    cmp al, TOK_EOF
    je .done
    cmp al, TOK_NEWLINE
    je .done
    call ip_advance
    jmp .skip_stmt

.done:
    pop rbp
    ret

; ---- Keyword dispatch ----
.kw_dispatch:
    lea rdi, [kw_show]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .do_show

    lea rdi, [kw_err]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .do_err

    lea rdi, [kw_if]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    je .do_if

    lea rdi, [kw_repeat]
    mov rsi, 6
    call ip_is_kw
    cmp rax, 1
    je .do_repeat

    lea rdi, [kw_while]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .do_while

    lea rdi, [kw_each]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .do_each

    lea rdi, [kw_func]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .do_func

    lea rdi, [kw_return]
    mov rsi, 6
    call ip_is_kw
    cmp rax, 1
    je .do_return

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .do_end

    lea rdi, [kw_skip]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .do_skip

    lea rdi, [kw_stop]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .do_stop

    lea rdi, [kw_try]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .do_try

    lea rdi, [kw_push]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .do_push_stmt

    lea rdi, [kw_write]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .do_write_file

    lea rdi, [kw_read]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .do_read_file

    lea rdi, [kw_ask]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .do_ask

    lea rdi, [kw_match]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .do_match

    ; Unknown keyword — skip it
    call ip_advance
    pop rbp
    ret

; ============================================================
; show — Print expression value + newline
; ============================================================
.do_show:
    call ip_advance          ; skip 'show'

    ; Check for show.raw (no newline)
    call ip_tok_type
    cmp al, TOK_DOT
    je .show_check_raw

    call interp_expr
    mov rdi, rax
    call rt_print_val
    call rt_print_newline
    pop rbp
    ret

.show_check_raw:
    ; Check if next is "raw"
    call ip_advance          ; skip '.'
    call ip_peek
    mov ecx, [rax + 4]
    cmp ecx, 3
    jne .show_not_raw
    mov rdi, [rax + 8]
    cmp byte [rdi], 'r'
    jne .show_not_raw
    cmp byte [rdi + 1], 'a'
    jne .show_not_raw
    cmp byte [rdi + 2], 'w'
    jne .show_not_raw
    call ip_advance          ; skip 'raw'
    call interp_expr
    mov rdi, rax
    call rt_print_val
    pop rbp
    ret
.show_not_raw:
    ; Not .raw — treat as expression
    call interp_expr
    mov rdi, rax
    call rt_print_val
    call rt_print_newline
    pop rbp
    ret

; ============================================================
; err — Print to stderr
; ============================================================
.do_err:
    call ip_advance          ; skip 'err'
    call interp_expr
    mov rdi, rax
    ; Print to stderr
    cmp rdi, 0
    jl .err_int
    cmp rdi, 0x400000
    jb .err_int
    push rdi
    call rt_str_len
    mov rdx, rax
    pop rsi
    mov rax, 1
    mov rdi, 2
    syscall
    ; Newline to stderr
    mov rax, 1
    mov rdi, 2
    mov rsi, interp_newline
    mov rdx, 1
    syscall
    pop rbp
    ret
.err_int:
    ; Convert int to string and print to stderr
    call rt_int_to_str
    push rax
    mov rdi, rax
    call rt_str_len
    mov rdx, rax
    pop rsi
    mov rax, 1
    mov rdi, 2
    syscall
    mov rax, 1
    mov rdi, 2
    mov rsi, interp_newline
    mov rdx, 1
    syscall
    pop rbp
    ret

; ============================================================
; if/elif/else/end
; ============================================================
.do_if:
    call ip_advance          ; skip 'if'
    call interp_expr         ; evaluate condition
    push rax                 ; save condition

    pop rax
    cmp rax, 0
    je .if_skip_to_elif_else

    ; Condition true — execute body
.if_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .if_hit_end

    ; Check for elif/else/end
    lea rdi, [kw_elif]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .if_skip_rest

    lea rdi, [kw_else]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .if_skip_rest

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .if_hit_end

    call interp_stmt
    ; Check if return/break was triggered
    cmp qword [return_flag], 1
    je .if_skip_rest
    cmp qword [loop_stop_flag], 1
    je .if_skip_rest
    jmp .if_body

.if_hit_end:
    call ip_advance          ; skip 'end'
    pop rbp
    ret

; Skip to matching elif/else/end (condition was false)
.if_skip_to_elif_else:
    push r14
    mov r14, 1               ; nesting depth (callee-saved register)
.if_skip_loop:
    call ip_tok_type
    cmp al, TOK_EOF
    je .if_skip_done_pop

    lea rdi, [kw_if]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    jne .if_skip_not_if
    inc r14
    call ip_advance
    jmp .if_skip_loop
.if_skip_not_if:
    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    jne .if_skip_not_end
    dec r14
    cmp r14, 0
    je .if_skip_hit_end
    call ip_advance
    jmp .if_skip_loop
.if_skip_not_end:
    cmp r14, 1
    jne .if_skip_other
    lea rdi, [kw_elif]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .if_skip_do_elif
    lea rdi, [kw_else]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .if_skip_do_else
.if_skip_other:
    call ip_advance
    jmp .if_skip_loop

.if_skip_hit_end:
    pop r14
    call ip_advance          ; skip 'end'
    pop rbp
    ret

.if_skip_do_elif:
    pop r14
    call ip_advance          ; skip 'elif'
    call interp_expr         ; evaluate elif condition
    cmp rax, 0
    je .if_skip_to_elif_else
    jmp .if_body

.if_skip_do_else:
    pop r14
    call ip_advance          ; skip 'else'
    jmp .if_body

.if_skip_done_pop:
    pop r14
    pop rbp
    ret

.if_do_elif:
    call ip_advance          ; skip 'elif'
    call interp_expr         ; evaluate elif condition
    cmp rax, 0
    je .if_skip_to_elif_else
    jmp .if_body             ; condition true

.if_do_else:
    call ip_advance          ; skip 'else'
    jmp .if_body             ; execute else body

; Skip rest of if block (after true branch executed)
.if_skip_rest:
    push r14
    mov r14, 1
.if_skip_rest_loop:
    call ip_tok_type
    cmp al, TOK_EOF
    je .if_sr_done
    lea rdi, [kw_if]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    jne .if_sr_not_if
    inc r14
    call ip_advance
    jmp .if_skip_rest_loop
.if_sr_not_if:
    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    jne .if_sr_other
    dec r14
    cmp r14, 0
    je .if_sr_hit_end
    call ip_advance
    jmp .if_skip_rest_loop
.if_sr_other:
    call ip_advance
    jmp .if_skip_rest_loop

.if_sr_hit_end:
    pop r14
    call ip_advance          ; skip 'end'
    pop rbp
    ret

.if_sr_done:
    pop r14
    pop rbp
    ret

; ============================================================
; repeat N times [as i] / end
; ============================================================
.do_repeat:
    call ip_advance          ; skip 'repeat'
    call interp_expr         ; evaluate count
    push rax                 ; save count

    ; Check for 'times'
    lea rdi, [kw_times]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    jne .repeat_no_times
    call ip_advance          ; skip 'times'
.repeat_no_times:

    ; Check for 'as i'
    lea rdi, [kw_as]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    jne .repeat_no_as

    call ip_advance          ; skip 'as'
    ; Get iterator variable name
    call ip_peek
    mov r14, [rax + 8]       ; name pointer
    mov r15d, [rax + 4]      ; name length (32-bit load, zero-extends)
    call ip_advance          ; skip variable name
    jmp .repeat_start

.repeat_no_as:
    xor r14, r14             ; no iterator variable
    xor r15, r15

.repeat_start:
    ; Save loop state on stack: [body_start, count, iter_name_ptr, iter_name_len, counter]
    pop rax                  ; count (was pushed earlier)
    push r14                 ; iter var name ptr
    push r15                 ; iter var name len
    push rax                 ; count
    push qword [ip_pos]      ; body start
    push qword 0             ; iteration counter

    inc qword [loop_depth]

.repeat_iter:
    ; Load state: [rsp]=counter, [rsp+8]=body_start, [rsp+16]=count
    mov rbx, [rsp]           ; counter
    cmp rbx, [rsp + 16]     ; compare with count
    jge .repeat_done

    ; Set iterator variable if present
    mov r14, [rsp + 32]      ; iter var name ptr (pushed first = highest offset)
    cmp r14, 0
    je .repeat_no_iter_var
    mov rdi, r14
    mov rsi, [rsp + 24]     ; iter var name len
    mov rdx, rbx
    call var_set
.repeat_no_iter_var:

    ; Reset position to body start
    mov rax, [rsp + 8]
    mov qword [ip_pos], rax
    mov qword [loop_skip_flag], 0

    ; Execute body until 'end'
.repeat_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .repeat_done

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .repeat_body_end

    ; Check control flags
    cmp qword [loop_skip_flag], 1
    je .repeat_skip_body
    cmp qword [loop_stop_flag], 1
    je .repeat_stop
    cmp qword [return_flag], 1
    je .repeat_stop

    call interp_stmt
    jmp .repeat_body

.repeat_skip_body:
    call ip_skip_block       ; skip to matching 'end'
    jmp .repeat_iter_next

.repeat_body_end:
    ; 'end' found — next iteration
    call ip_advance          ; skip 'end'
.repeat_iter_next:
    inc qword [rsp]          ; increment counter on stack
    jmp .repeat_iter

.repeat_stop:
    mov qword [loop_stop_flag], 0
    call ip_skip_block       ; skip to matching 'end'

.repeat_done:
    add rsp, 40              ; discard loop state (5 * 8)
    dec qword [loop_depth]
    pop rbp
    ret

; ============================================================
; while cond / end
; ============================================================
.do_while:
    call ip_advance          ; skip 'while'
    push qword [ip_pos]      ; save condition start on stack

    inc qword [loop_depth]

.while_iter:
    mov rax, [rsp]           ; get condition start from stack
    mov qword [ip_pos], rax  ; reset to condition
    call interp_expr         ; evaluate condition
    cmp rax, 0
    je .while_find_end

    mov qword [loop_skip_flag], 0

    ; Execute body
.while_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .while_done

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .while_body_end

    cmp qword [loop_skip_flag], 1
    je .while_skip_to_end
    cmp qword [loop_stop_flag], 1
    je .while_stop
    cmp qword [return_flag], 1
    je .while_stop

    call interp_stmt
    jmp .while_body

.while_body_end:
    call ip_advance          ; skip 'end'
    jmp .while_iter

.while_skip_to_end:
    call ip_skip_block       ; skip to matching 'end'
    jmp .while_iter

.while_stop:
    mov qword [loop_stop_flag], 0
.while_find_end:
    call ip_skip_block       ; skip to matching 'end'
.while_done:
    add rsp, 8               ; discard saved condition start
    dec qword [loop_depth]
    pop rbp
    ret

; ============================================================
; each arr as item / end
; ============================================================
.do_each:
    call ip_advance          ; skip 'each'
    call interp_expr         ; evaluate array/range
    mov r12, rax             ; array pointer

    ; Expect 'as'
    lea rdi, [kw_as]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    jne .each_done_early
    call ip_advance          ; skip 'as'

    ; Get variable name
    call ip_peek
    mov r13, [rax + 8]       ; var name ptr
    mov ecx, [rax + 4]
    mov r14, rcx             ; var name len
    call ip_advance          ; skip var name

    ; Check for second variable (index): each arr as item, idx
    xor r15, r15             ; index var name ptr (0 = none)
    xor rbx, rbx             ; index var name len
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .each_no_idx
    call ip_tok_sub
    cmp al, PUNCT_COMMA
    jne .each_no_idx
    call ip_advance          ; skip ','
    call ip_peek
    mov r15, [rax + 8]       ; idx var name ptr
    mov ecx, [rax + 4]
    mov rbx, rcx             ; idx var name len
    call ip_advance          ; skip idx var
.each_no_idx:

    ; Save all loop state on stack
    ; Stack layout: [counter, arr_len, body_start, idx_var_ptr, idx_var_len, arr_ptr, item_name_ptr, item_name_len]
    push r14                 ; item var name len  [rsp+56]
    push r13                 ; item var name ptr  [rsp+48]
    push r12                 ; array pointer      [rsp+40]
    push rbx                 ; idx var len        [rsp+32]
    push r15                 ; idx var ptr        [rsp+24]
    mov rcx, [ip_pos]
    push rcx                 ; body start pos     [rsp+16]

    ; Get array length
    mov rdi, r12
    call rt_arr_len
    push rax                 ; array length       [rsp+8]
    push qword 0             ; counter            [rsp+0]

    inc qword [loop_depth]

.each_iter:
    mov rbx, [rsp]           ; counter
    mov rax, [rsp + 8]       ; array length
    cmp rbx, rax
    jge .each_end

    ; Get element
    mov rdi, [rsp + 40]      ; array pointer
    mov rsi, rbx
    call rt_arr_get

    ; Set item variable
    mov rdx, rax             ; element value
    mov rdi, [rsp + 48]      ; item name ptr
    mov rsi, [rsp + 56]      ; item name len
    call var_set

    ; Set index variable if present
    mov rcx, [rsp + 24]      ; idx var ptr
    cmp rcx, 0
    je .each_no_set_idx
    mov rdi, rcx
    mov rsi, [rsp + 32]      ; idx var len
    mov rdx, [rsp]           ; counter as index
    call var_set
.each_no_set_idx:

    ; Reset to body start
    mov rcx, [rsp + 16]      ; body start pos
    mov [ip_pos], rcx
    mov qword [loop_skip_flag], 0

.each_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .each_cleanup

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .each_body_end

    cmp qword [loop_skip_flag], 1
    je .each_skip_to_end
    cmp qword [loop_stop_flag], 1
    je .each_stop
    cmp qword [return_flag], 1
    je .each_stop

    call interp_stmt
    jmp .each_body

.each_body_end:
    call ip_advance          ; skip 'end'
    inc qword [rsp]          ; increment counter
    jmp .each_iter

.each_skip_to_end:
    call ip_skip_block       ; skip to matching 'end'
    inc qword [rsp]          ; increment counter
    jmp .each_iter

.each_stop:
    mov qword [loop_stop_flag], 0
    call ip_skip_block       ; skip to matching 'end'

.each_cleanup:
    add rsp, 64              ; clean up 8 pushed values
    dec qword [loop_depth]
.each_done_early:
    pop rbp
    ret

.each_end:
    ; Find final 'end' and skip past it
    mov rcx, [rsp + 16]      ; body start
    mov [ip_pos], rcx
    call ip_skip_block       ; skip to matching 'end'
    jmp .each_cleanup

; ============================================================
; func name(params) / end — Register function
; ============================================================
.do_func:
    call ip_advance          ; skip 'func'

    ; Get function name
    call ip_peek
    mov r12, [rax + 8]       ; name pointer
    mov ecx, [rax + 4]
    mov r13, rcx             ; name length
    call ip_advance          ; skip name

    ; Register function (body position set after parsing params)
    mov rdi, r12
    mov rsi, r13
    xor rdx, rdx             ; placeholder, updated below
    call func_register

    ; Get func index for param storage
    mov rcx, [func_count]
    dec rcx                  ; just registered, so count-1
    mov r14, rcx             ; func index

    xor r15, r15             ; param count (init before branch)

    ; Parse parameters: expect '(' params ')'
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .func_no_params
    call ip_tok_sub
    cmp al, PUNCT_LPAREN
    jne .func_no_params
    call ip_advance          ; skip '('
.func_param_loop:
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .func_not_rparen
    call ip_tok_sub
    cmp al, PUNCT_RPAREN
    je .func_params_done
.func_not_rparen:
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .func_not_comma
    call ip_tok_sub
    cmp al, PUNCT_COMMA
    jne .func_not_comma
    call ip_advance          ; skip ','
    jmp .func_param_loop
.func_not_comma:
    ; Check for 'many' keyword
    lea rdi, [kw_many]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    jne .func_regular_param
    call ip_advance          ; skip 'many'
    ; Next token is the variadic param name
.func_regular_param:
    call ip_peek
    mov rdi, [rax + 8]       ; param name ptr
    mov ecx, [rax + 4]
    ; Store param name: func_param_names[func_idx * 8 + param_idx]
    mov rax, r14
    shl rax, 3               ; * 8 params per func
    add rax, r15
    mov [func_param_names + rax * 8], rdi
    mov [func_param_nlens + rax * 8], rcx
    call ip_advance          ; skip param name
    inc r15
    jmp .func_param_loop

.func_params_done:
    call ip_advance          ; skip ')'
.func_no_params:
    mov [func_param_counts + r14 * 8], r15

    ; Now set the body start position (after params)
    mov rax, [ip_pos]
    mov [func_starts + r14 * 8], rax

    ; Skip function body (don't execute it now)
    call ip_skip_block
.func_done:
    pop rbp
    ret

; ============================================================
; return [expr]
; ============================================================
.do_return:
    call ip_advance          ; skip 'return'
    ; Check if there's an expression (not newline/EOF)
    call ip_tok_type
    cmp al, TOK_NEWLINE
    je .return_void
    cmp al, TOK_EOF
    je .return_void
    call interp_expr
    mov [return_val], rax
    mov qword [return_flag], 1
    pop rbp
    ret
.return_void:
    mov qword [return_val], 0
    mov qword [return_flag], 1
    pop rbp
    ret

; ============================================================
; skip (continue) / stop (break)
; ============================================================
.do_skip:
    call ip_advance
    mov qword [loop_skip_flag], 1
    pop rbp
    ret

.do_stop:
    call ip_advance
    mov qword [loop_stop_flag], 1
    pop rbp
    ret

; ============================================================
; end — should not reach here (handled by block owners)
; ============================================================
.do_end:
    call ip_advance
    pop rbp
    ret

; ============================================================
; try/catch/done — Error handling
; ============================================================
.do_try:
    call ip_advance          ; skip 'try'
    ; Execute body, catch errors (simplified: just execute)
.try_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .try_done

    lea rdi, [kw_catch]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .try_skip_catch

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .try_end

    call interp_stmt
    jmp .try_body

.try_skip_catch:
    call ip_advance          ; skip 'catch'
    call ip_skip_block       ; skip to matching 'end'
    pop rbp
    ret

.try_end:
    call ip_advance          ; skip 'end'
.try_done:
    pop rbp
    ret

; ============================================================
; push arr, val
; ============================================================
.do_push_stmt:
    call ip_advance          ; skip 'push'
    call interp_expr         ; array
    push rax
    ; Expect ','
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .push_done
    call ip_advance          ; skip ','
    call interp_expr         ; value
    mov rsi, rax
    pop rdi
    call rt_arr_push
    pop rbp
    ret
.push_done:
    pop rax
    pop rbp
    ret

; ============================================================
; write path, data — File write
; ============================================================
.do_write_file:
    call ip_advance          ; skip 'write'
    call interp_expr         ; path
    push rax
    ; Expect expression (data)
    call interp_expr
    mov rsi, rax             ; data
    pop rdi                  ; path
    extern rt_file_write_str
    call rt_file_write_str
    pop rbp
    ret

; ============================================================
; read path — File read (as statement, stores nothing useful)
; ============================================================
.do_read_file:
    call ip_advance          ; skip 'read'
    call interp_expr
    pop rbp
    ret

; ============================================================
; ask "prompt" — Input (as statement)
; ============================================================
.do_ask:
    call ip_advance          ; skip 'ask'
    call interp_expr         ; prompt string
    mov rdi, rax
    call rt_prompt
    pop rbp
    ret

; ============================================================
; match expr / case val / end — Pattern matching
; ============================================================
.do_match:
    call ip_advance          ; skip 'match'
    call interp_expr         ; match expression
    push rax                 ; save match value

.match_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .match_done

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .match_end

    lea rdi, [kw_case]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    jne .match_skip_line

    call ip_advance          ; skip 'case'

    ; Check for 'else' (default case)
    lea rdi, [kw_else]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .match_case_else

    call interp_expr         ; case value
    ; Compare with match value
    mov rdx, [rsp]           ; match value
    cmp rax, rdx
    je .match_case_hit
    jmp .match_skip_case

.match_case_else:
    call ip_advance          ; skip 'else'
.match_case_hit:
    ; Execute case body
.match_case_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .match_done
    lea rdi, [kw_case]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .match_skip_rest
    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .match_end
    call interp_stmt
    jmp .match_case_body

.match_skip_case:
    ; Skip until next case or end
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .match_done
    lea rdi, [kw_case]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .match_body
    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .match_end
    call ip_advance
    jmp .match_skip_case

.match_skip_rest:
    ; Already matched — skip remaining cases to matching 'end'
    call ip_skip_block
    jmp .match_end

.match_skip_line:
    call ip_advance
    jmp .match_body

.match_end:
    call ip_advance          ; skip 'end'
.match_done:
    pop rax                  ; clean match value
    pop rbp
    ret

; ============================================================
; Identifier statement — assignment or function call
; ============================================================
.ident_stmt:
    call ip_peek
    mov r12, [rax + 8]       ; name pointer
    mov ecx, [rax + 4]
    mov r13, rcx             ; name length
    call ip_advance          ; skip identifier

    ; Check for '=' (assignment)
    call ip_tok_type
    cmp al, TOK_OP
    jne .ident_not_assign
    call ip_tok_sub
    cmp al, OP_ASSIGN
    jne .ident_not_assign

    call ip_advance          ; skip '='

    ; Check for array literal [
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .ident_regular_assign
    call ip_tok_sub
    cmp al, PUNCT_LBRACKET
    jne .ident_regular_assign

    ; Array literal
    call interp_array_literal
    mov rdx, rax
    mov rdi, r12
    mov rsi, r13
    call var_set
    pop rbp
    ret

.ident_regular_assign:
    ; Check for 'ask' keyword (input)
    lea rdi, [kw_ask]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    jne .ident_normal_assign
    call ip_advance          ; skip 'ask'
    call interp_expr         ; prompt
    mov rdi, rax
    call rt_prompt
    mov rdx, rax
    mov rdi, r12
    mov rsi, r13
    call var_set
    pop rbp
    ret

.ident_normal_assign:
    call interp_expr
    mov rdx, rax
    mov rdi, r12
    mov rsi, r13
    call var_set
    pop rbp
    ret

.ident_not_assign:
    ; Check for '[' (array subscript assign: arr[i] = val)
    cmp al, TOK_PUNCT
    jne .ident_check_call
    call ip_tok_sub
    cmp al, PUNCT_LBRACKET
    jne .ident_check_call

    ; Array subscript assignment
    call ip_advance          ; skip '['
    call interp_expr         ; index
    push rax
    ; Expect ']'
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .arr_assign_err
    call ip_advance          ; skip ']'
    ; Expect '='
    call ip_tok_type
    cmp al, TOK_OP
    jne .arr_assign_err
    call ip_tok_sub
    cmp al, OP_ASSIGN
    jne .arr_assign_err
    call ip_advance          ; skip '='
    call interp_expr         ; value
    mov rdx, rax             ; value
    pop rsi                  ; index
    ; Get array
    mov rdi, r12
    push rdx
    push rsi
    mov rsi, r13
    call var_get
    pop rsi
    pop rdx
    mov rdi, rax             ; array pointer
    call rt_arr_set
    pop rbp
    ret

.arr_assign_err:
    pop rax
    pop rbp
    ret

.ident_check_call:
    ; Check for '(' (function call as statement)
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .ident_check_dot
    call ip_tok_sub
    cmp al, PUNCT_LPAREN
    jne .ident_check_dot

    ; Function call
    mov rdi, r12
    mov rsi, r13
    call interp_call
    pop rbp
    ret

.ident_check_dot:
    ; Check for '.' (method call as statement)
    call ip_tok_type
    cmp al, TOK_DOT
    jne .ident_other
    ; Get variable value first
    mov rdi, r12
    mov rsi, r13
    call var_get
    mov r14, rax             ; object value
    call ip_advance          ; skip '.'
    ; Get method name
    call ip_peek
    mov r12, [rax + 8]
    mov ecx, [rax + 4]
    mov r13, rcx
    call ip_advance          ; skip method name
    ; For now just skip the method call args
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .ident_other
    call ip_tok_sub
    cmp al, PUNCT_LPAREN
    jne .ident_other
    ; Skip args (consume until matching ')')
    call ip_advance          ; skip '('
    mov r14, 1
.dot_skip_args:
    call ip_tok_type
    cmp al, TOK_EOF
    je .ident_other
    cmp al, TOK_PUNCT
    jne .dot_skip_other
    call ip_tok_sub
    cmp al, PUNCT_LPAREN
    je .dot_skip_nest
    cmp al, PUNCT_RPAREN
    jne .dot_skip_other
    dec r14
    cmp r14, 0
    je .dot_skip_done
    call ip_advance
    jmp .dot_skip_args
.dot_skip_nest:
    inc r14
    call ip_advance
    jmp .dot_skip_args
.dot_skip_other:
    call ip_advance
    jmp .dot_skip_args
.dot_skip_done:
    call ip_advance          ; skip ')'

.ident_other:
    pop rbp
    ret

; ============================================================
; interp_call — Call a user function
; rdi = name pointer, rsi = name length
; Returns: rax = return value
; ============================================================
interp_call:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; func name
    mov r13, rsi             ; func name len

    ; Collect arguments
    call ip_advance          ; skip '('
    xor r14, r14             ; arg count
    sub rsp, 64              ; space for up to 8 args

.call_args:
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .call_not_rparen
    call ip_tok_sub
    cmp al, PUNCT_RPAREN
    je .call_args_done
.call_not_rparen:
    ; Skip commas
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .call_eval_arg
    call ip_tok_sub
    cmp al, PUNCT_COMMA
    jne .call_eval_arg
    call ip_advance
.call_eval_arg:
    call interp_expr
    mov [rsp + r14 * 8], rax
    inc r14
    jmp .call_args

.call_args_done:
    call ip_advance          ; skip ')'

    ; Check for builtin functions first
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14             ; arg count
    lea rcx, [rsp]           ; args array pointer
    call interp_try_builtin
    cmp rax, -1
    jne .call_return_builtin

    ; Find user function
    mov rdi, r12
    mov rsi, r13
    call func_find
    cmp rax, -1
    je .call_not_found

    mov r15, rax             ; func index

    ; Save current position
    push qword [ip_pos]

    ; Set parameters as variables
    xor rcx, rcx
.call_set_params:
    cmp rcx, [func_param_counts + r15 * 8]
    jge .call_set_done
    ; Get param name
    mov rax, r15
    shl rax, 3
    add rax, rcx
    push rcx
    mov rdi, [func_param_names + rax * 8]
    mov rsi, [func_param_nlens + rax * 8]
    ; Get arg value
    pop rcx
    push rcx
    mov rdx, [rsp + 8 + rcx * 8 + 8]  ; +8 for pushed ip_pos, +8 for rbp shift
    call var_set
    pop rcx
    inc rcx
    jmp .call_set_params
.call_set_done:

    ; Jump to function body
    mov rax, [func_starts + r15 * 8]
    mov [ip_pos], rax
    mov qword [return_flag], 0

    ; Execute function body
.call_body:
    call ip_skip_nl
    call ip_tok_type
    cmp al, TOK_EOF
    je .call_body_done

    lea rdi, [kw_end]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .call_hit_end

    cmp qword [return_flag], 1
    je .call_skip_to_end

    call interp_stmt
    jmp .call_body

.call_hit_end:
    call ip_advance          ; skip 'end'
.call_body_done:
    mov rax, [return_val]
    mov qword [return_flag], 0

    ; Restore position
    pop qword [ip_pos]

    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.call_skip_to_end:
    call ip_skip_block       ; skip to matching 'end'
    jmp .call_body_done

.call_not_found:
    ; Print error
    mov rax, 1
    mov rdi, 2
    mov rsi, interp_err_func
    mov rdx, interp_err_func_len
    syscall
    mov rsi, r12
    mov rdx, r13
    mov rax, 1
    mov rdi, 2
    syscall
    mov rax, 1
    mov rdi, 2
    mov rsi, interp_newline
    mov rdx, 1
    syscall

.call_return_builtin:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; interp_array_literal — Parse [val, val, ...]
; Returns: rax = array pointer
; ============================================================
interp_array_literal:
    push rbp
    mov rbp, rsp
    push r12

    ; Create new array
    call rt_arr_new
    mov r12, rax

    call ip_advance          ; skip '['

.arr_lit_loop:
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .arr_lit_not_close
    call ip_tok_sub
    cmp al, PUNCT_RBRACKET
    je .arr_lit_done
.arr_lit_not_close:
    ; Skip commas
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .arr_lit_val
    call ip_tok_sub
    cmp al, PUNCT_COMMA
    jne .arr_lit_val
    call ip_advance
    jmp .arr_lit_loop
.arr_lit_val:
    call interp_expr
    mov rsi, rax
    mov rdi, r12
    call rt_arr_push
    jmp .arr_lit_loop

.arr_lit_done:
    call ip_advance          ; skip ']'
    mov rax, r12

    pop r12
    pop rbp
    ret

; ============================================================
; interp_expr — Evaluate expression, return value in rax
; Operator precedence: or → and → not → compare → add → mul → unary → primary
; ============================================================
interp_expr:
    push rbp
    mov rbp, rsp
    call interp_expr_or
    pop rbp
    ret

; ---- or ----
interp_expr_or:
    push rbp
    mov rbp, rsp
    push r12

    call interp_expr_and
    mov r12, rax

.or_loop:
    lea rdi, [kw_or]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    jne .or_done
    call ip_advance
    call interp_expr_and
    ; r12 or rax
    cmp r12, 0
    jne .or_true
    cmp rax, 0
    jne .or_true
    xor r12, r12
    jmp .or_loop
.or_true:
    mov r12, 1
    jmp .or_loop
.or_done:
    mov rax, r12
    pop r12
    pop rbp
    ret

; ---- and ----
interp_expr_and:
    push rbp
    mov rbp, rsp
    push r12

    call interp_expr_not
    mov r12, rax

.and_loop:
    lea rdi, [kw_and]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    jne .and_done
    call ip_advance
    call interp_expr_not
    cmp r12, 0
    je .and_false
    cmp rax, 0
    je .and_false
    mov r12, 1
    jmp .and_loop
.and_false:
    xor r12, r12
    jmp .and_loop
.and_done:
    mov rax, r12
    pop r12
    pop rbp
    ret

; ---- not ----
interp_expr_not:
    push rbp
    mov rbp, rsp

    lea rdi, [kw_not]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    jne .not_pass
    call ip_advance
    call interp_expr_not
    cmp rax, 0
    je .not_true
    xor rax, rax
    pop rbp
    ret
.not_true:
    mov rax, 1
    pop rbp
    ret
.not_pass:
    call interp_expr_compare
    pop rbp
    ret

; ---- compare ----
interp_expr_compare:
    push rbp
    mov rbp, rsp
    push r12
    push r13

    call interp_expr_add
    mov r12, rax

.cmp_loop:
    ; Check operator tokens
    call ip_tok_type
    cmp al, TOK_OP
    je .cmp_op
    ; Check keyword comparisons
    cmp al, TOK_KEYWORD
    je .cmp_kw
    jmp .cmp_done

.cmp_op:
    call ip_tok_sub
    cmp al, OP_EQ
    je .cmp_eq
    cmp al, OP_NEQ
    je .cmp_neq
    cmp al, OP_LT
    je .cmp_lt
    cmp al, OP_GT
    je .cmp_gt
    cmp al, OP_LTE
    je .cmp_lte
    cmp al, OP_GTE
    je .cmp_gte
    jmp .cmp_done

.cmp_kw:
    lea rdi, [kw_is]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    je .cmp_is
    lea rdi, [kw_isnt]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .cmp_isnt
    lea rdi, [kw_above]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .cmp_above
    lea rdi, [kw_below]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .cmp_below
    lea rdi, [kw_atleast]
    mov rsi, 7
    call ip_is_kw
    cmp rax, 1
    je .cmp_atleast
    lea rdi, [kw_atmost]
    mov rsi, 6
    call ip_is_kw
    cmp rax, 1
    je .cmp_atmost
    lea rdi, [kw_in]
    mov rsi, 2
    call ip_is_kw
    cmp rax, 1
    je .cmp_in
    jmp .cmp_done

.cmp_eq:
.cmp_is:
    call ip_advance
    call interp_expr_add
    ; String comparison if both are pointers
    cmp r12, 0x400000
    jb .cmp_int_eq
    cmp rax, 0x400000
    jb .cmp_int_eq
    ; Both could be strings
    mov rdi, r12
    mov rsi, rax
    call rt_str_eq
    mov r12, rax
    jmp .cmp_loop
.cmp_int_eq:
    cmp r12, rax
    je .cmp_set_true
    jmp .cmp_set_false

.cmp_neq:
.cmp_isnt:
    call ip_advance
    call interp_expr_add
    cmp r12, 0x400000
    jb .cmp_int_neq
    cmp rax, 0x400000
    jb .cmp_int_neq
    mov rdi, r12
    mov rsi, rax
    call rt_str_eq
    cmp rax, 0
    je .cmp_set_true
    jmp .cmp_set_false
.cmp_int_neq:
    cmp r12, rax
    jne .cmp_set_true
    jmp .cmp_set_false

.cmp_lt:
.cmp_below:
    call ip_advance
    call interp_expr_add
    cmp r12, rax
    jl .cmp_set_true
    jmp .cmp_set_false

.cmp_gt:
.cmp_above:
    call ip_advance
    call interp_expr_add
    cmp r12, rax
    jg .cmp_set_true
    jmp .cmp_set_false

.cmp_lte:
.cmp_atleast:
    call ip_advance
    call interp_expr_add
    cmp r12, rax
    jle .cmp_set_true
    jmp .cmp_set_false

.cmp_gte:
.cmp_atmost:
    call ip_advance
    call interp_expr_add
    cmp r12, rax
    jge .cmp_set_true
    jmp .cmp_set_false

.cmp_in:
    call ip_advance
    call interp_expr_add
    ; rax = container, r12 = element
    mov rdi, rax
    mov rsi, r12
    call rt_arr_contains
    mov r12, rax
    jmp .cmp_loop

.cmp_set_true:
    mov r12, 1
    jmp .cmp_loop
.cmp_set_false:
    xor r12, r12
    jmp .cmp_loop

.cmp_done:
    mov rax, r12
    pop r13
    pop r12
    pop rbp
    ret

; ---- add/sub & string concat ----
interp_expr_add:
    push rbp
    mov rbp, rsp
    push r12

    call interp_expr_mul
    mov r12, rax

.add_loop:
    call ip_tok_type
    cmp al, TOK_OP
    jne .add_done
    call ip_tok_sub
    cmp al, OP_PLUS
    je .add_plus
    cmp al, OP_MINUS
    je .add_minus
    jmp .add_done

.add_plus:
    call ip_advance
    call interp_expr_mul
    ; Check if either operand is a string pointer
    cmp r12, 0x400000
    jae .add_str_concat
    cmp rax, 0x400000
    jae .add_int_to_str_concat
    add r12, rax
    jmp .add_loop

.add_str_concat:
    ; r12 is string, concatenate
    cmp rax, 0x400000
    jae .add_both_str
    ; r12 = string, rax = int → convert int to string first
    push r12
    mov rdi, rax
    call rt_int_to_str
    mov rsi, rax
    pop rdi
    call rt_str_concat
    mov r12, rax
    jmp .add_loop
.add_both_str:
    mov rdi, r12
    mov rsi, rax
    call rt_str_concat
    mov r12, rax
    jmp .add_loop
.add_int_to_str_concat:
    ; r12 = int, rax = string → convert int to string first
    push rax
    mov rdi, r12
    call rt_int_to_str
    mov rdi, rax
    pop rsi
    call rt_str_concat
    mov r12, rax
    jmp .add_loop

.add_minus:
    call ip_advance
    call interp_expr_mul
    sub r12, rax
    jmp .add_loop

.add_done:
    mov rax, r12
    pop r12
    pop rbp
    ret

; ---- mul/div/mod ----
interp_expr_mul:
    push rbp
    mov rbp, rsp
    push r12

    call interp_expr_power
    mov r12, rax

.mul_loop:
    call ip_tok_type
    cmp al, TOK_OP
    jne .mul_done
    call ip_tok_sub
    cmp al, OP_STAR
    je .mul_star
    cmp al, OP_SLASH
    je .mul_slash
    cmp al, OP_DSLASH
    je .mul_dslash
    cmp al, OP_PERCENT
    je .mul_percent
    cmp al, OP_AMP
    je .mul_amp
    cmp al, OP_PIPE
    je .mul_pipe
    cmp al, OP_CARET
    je .mul_caret
    cmp al, OP_LSHIFT
    je .mul_lshift
    cmp al, OP_RSHIFT
    je .mul_rshift
    jmp .mul_done

.mul_star:
    call ip_advance
    call interp_expr_power
    imul r12, rax
    jmp .mul_loop

.mul_slash:
.mul_dslash:
    call ip_advance
    call interp_expr_power
    cmp rax, 0
    je .mul_divzero
    mov rcx, rax
    mov rax, r12
    cqo
    idiv rcx
    mov r12, rax             ; quotient
    jmp .mul_loop

.mul_percent:
    call ip_advance
    call interp_expr_power
    cmp rax, 0
    je .mul_divzero
    mov rcx, rax
    mov rax, r12
    cqo
    idiv rcx
    mov r12, rdx             ; remainder
    jmp .mul_loop

.mul_amp:
    call ip_advance
    call interp_expr_power
    and r12, rax
    jmp .mul_loop

.mul_pipe:
    call ip_advance
    call interp_expr_power
    or r12, rax
    jmp .mul_loop

.mul_caret:
    call ip_advance
    call interp_expr_power
    xor r12, rax
    jmp .mul_loop

.mul_lshift:
    call ip_advance
    call interp_expr_power
    mov rcx, rax
    shl r12, cl
    jmp .mul_loop

.mul_rshift:
    call ip_advance
    call interp_expr_power
    mov rcx, rax
    sar r12, cl
    jmp .mul_loop

.mul_divzero:
    mov rax, 1
    mov rdi, 2
    mov rsi, interp_err_divzero
    mov rdx, interp_err_divzero_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

.mul_done:
    mov rax, r12
    pop r12
    pop rbp
    ret

; ---- power ** ----
interp_expr_power:
    push rbp
    mov rbp, rsp
    push r12

    call interp_expr_unary
    mov r12, rax

    call ip_tok_type
    cmp al, TOK_OP
    jne .pow_done
    call ip_tok_sub
    cmp al, OP_DSTAR
    jne .pow_done

    call ip_advance
    call interp_expr_power    ; right-associative
    ; r12 ** rax
    mov rdi, r12
    mov rsi, rax
    ; Inline power calculation
    mov rcx, rsi             ; exponent
    mov rax, 1               ; result
    cmp rcx, 0
    je .pow_result
.pow_loop:
    imul rax, rdi
    dec rcx
    jnz .pow_loop
.pow_result:
    mov r12, rax

.pow_done:
    mov rax, r12
    pop r12
    pop rbp
    ret

; ---- unary (-, ~) ----
interp_expr_unary:
    push rbp
    mov rbp, rsp

    call ip_tok_type
    cmp al, TOK_OP
    jne .unary_primary

    call ip_tok_sub
    cmp al, OP_MINUS
    je .unary_neg
    cmp al, OP_TILDE
    je .unary_tilde
    jmp .unary_primary

.unary_neg:
    call ip_advance
    call interp_expr_unary
    neg rax
    pop rbp
    ret

.unary_tilde:
    call ip_advance
    call interp_expr_unary
    not rax
    pop rbp
    ret

.unary_primary:
    call interp_expr_primary
    pop rbp
    ret

; ============================================================
; interp_expr_primary — Leaf values and postfix operations
; ============================================================
interp_expr_primary:
    push rbp
    mov rbp, rsp
    push r12
    push r13

    call ip_tok_type

    ; Integer literal
    cmp al, TOK_INT
    je .prim_int

    ; String literal
    cmp al, TOK_STRING
    je .prim_string

    ; Keyword (true, false, null)
    cmp al, TOK_KEYWORD
    je .prim_keyword

    ; Parenthesized expression
    cmp al, TOK_PUNCT
    jne .prim_ident
    call ip_tok_sub
    cmp al, PUNCT_LPAREN
    je .prim_paren
    cmp al, PUNCT_LBRACKET
    je .prim_array_lit
    jmp .prim_zero

.prim_int:
    call ip_peek
    mov ecx, [rax + 4]       ; length
    mov rsi, [rax + 8]       ; pointer to digits
    ; Parse integer from text
    xor r12, r12             ; result
    xor r13, r13             ; index
    ; Check for negative
    movzx eax, byte [rsi]
    cmp al, '-'
    jne .prim_int_loop
    inc r13
    mov rbx, 1               ; negative flag
    jmp .prim_int_parse
.prim_int_loop:
    xor rbx, rbx
.prim_int_parse:
    cmp r13, rcx
    jge .prim_int_done
    movzx eax, byte [rsi + r13]
    sub al, '0'
    imul r12, 10
    movzx rax, al
    add r12, rax
    inc r13
    jmp .prim_int_parse
.prim_int_done:
    cmp rbx, 1
    jne .prim_int_pos
    neg r12
.prim_int_pos:
    call ip_advance
    mov rax, r12
    jmp .prim_postfix

.prim_string:
    call ip_peek
    mov ecx, [rax + 4]       ; length
    mov rsi, [rax + 8]       ; pointer to string content
    ; Allocate and copy string
    push rcx
    push rsi
    mov rdi, rcx
    add rdi, 1               ; +1 for null terminator
    call rt_alloc
    mov r12, rax
    pop rsi
    pop rcx
    ; Copy string bytes
    mov rdi, r12
    xor r13, r13
.prim_str_copy:
    cmp r13, rcx
    jge .prim_str_done
    movzx eax, byte [rsi + r13]
    mov [rdi + r13], al
    inc r13
    jmp .prim_str_copy
.prim_str_done:
    mov byte [rdi + r13], 0  ; null terminate
    call ip_advance
    mov rax, r12
    jmp .prim_postfix

.prim_keyword:
    lea rdi, [kw_true]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .prim_true
    lea rdi, [kw_false]
    mov rsi, 5
    call ip_is_kw
    cmp rax, 1
    je .prim_false
    lea rdi, [kw_null]
    mov rsi, 4
    call ip_is_kw
    cmp rax, 1
    je .prim_null
    ; Check for 'ask'
    lea rdi, [kw_ask]
    mov rsi, 3
    call ip_is_kw
    cmp rax, 1
    je .prim_ask
    ; Unknown keyword in expression — return 0
    call ip_advance
    xor rax, rax
    jmp .prim_postfix

.prim_true:
    call ip_advance
    mov rax, 1
    jmp .prim_postfix
.prim_false:
    call ip_advance
    xor rax, rax
    jmp .prim_postfix
.prim_null:
    call ip_advance
    xor rax, rax
    jmp .prim_postfix

.prim_ask:
    call ip_advance          ; skip 'ask'
    call interp_expr         ; prompt
    mov rdi, rax
    call rt_prompt
    jmp .prim_postfix

.prim_paren:
    call ip_advance          ; skip '('
    call interp_expr
    mov r12, rax
    ; Expect ')'
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .prim_paren_done
    call ip_advance          ; skip ')'
.prim_paren_done:
    mov rax, r12
    jmp .prim_postfix

.prim_array_lit:
    call interp_array_literal
    jmp .prim_postfix

.prim_ident:
    call ip_tok_type
    cmp al, TOK_IDENT
    jne .prim_zero

    call ip_peek
    mov r12, [rax + 8]       ; name pointer
    mov ecx, [rax + 4]
    mov r13, rcx             ; name length
    call ip_advance          ; skip ident

    ; Check for '(' — function call
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .prim_ident_no_call
    call ip_tok_sub
    cmp al, PUNCT_LPAREN
    jne .prim_ident_no_call

    ; Function call in expression
    mov rdi, r12
    mov rsi, r13
    call interp_call
    jmp .prim_postfix

.prim_ident_no_call:
    ; Variable lookup
    mov rdi, r12
    mov rsi, r13
    call var_get
    jmp .prim_postfix

.prim_zero:
    xor rax, rax

; ---- Postfix: array subscript [i] and dot methods .method() ----
.prim_postfix:
    mov r12, rax             ; current value

.postfix_loop:
    call ip_tok_type
    cmp al, TOK_PUNCT
    je .postfix_check_bracket
    cmp al, TOK_DOT
    je .postfix_dot
    jmp .postfix_done

.postfix_check_bracket:
    call ip_tok_sub
    cmp al, PUNCT_LBRACKET
    jne .postfix_done

    ; Array subscript
    call ip_advance          ; skip '['
    call interp_expr         ; index
    push rax
    ; Expect ']'
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .postfix_bracket_done
    call ip_advance          ; skip ']'
.postfix_bracket_done:
    pop rsi                  ; index
    mov rdi, r12             ; array
    ; Check if it's a string or array
    cmp r12, 0x400000
    jb .postfix_done
    ; Check first byte to decide
    call rt_arr_get
    mov r12, rax
    jmp .postfix_loop

.postfix_dot:
    call ip_advance          ; skip '.'
    call ip_peek
    mov r13, [rax + 8]       ; method name pointer
    mov ecx, [rax + 4]
    push rcx                 ; save method name length
    call ip_advance          ; skip method name

    ; Check for '(' — method call
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .postfix_dot_prop
    call ip_tok_sub
    cmp al, PUNCT_LPAREN
    jne .postfix_dot_prop

    ; Dot method call: r12.method(args)
    call ip_advance          ; skip '('
    ; Collect args
    pop rcx                  ; method name length
    push rcx
    ; For now: pass object as first arg, call as builtin
    ; Collect args into stack
    sub rsp, 64              ; space for args
    mov [rsp], r12           ; first arg = object
    mov r14, 1               ; arg count (starts at 1 for object)

.dot_args_loop:
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .dot_not_rparen
    call ip_tok_sub
    cmp al, PUNCT_RPAREN
    je .dot_args_done
.dot_not_rparen:
    call ip_tok_type
    cmp al, TOK_PUNCT
    jne .dot_eval_arg
    call ip_tok_sub
    cmp al, PUNCT_COMMA
    jne .dot_eval_arg
    call ip_advance
.dot_eval_arg:
    call interp_expr
    mov [rsp + r14 * 8], rax
    inc r14
    jmp .dot_args_loop

.dot_args_done:
    call ip_advance          ; skip ')'
    ; Call builtin with method name and args
    mov rdi, r13             ; method name
    mov rsi, [rsp + 64]      ; method name length (from earlier push)
    mov rdx, r14             ; arg count
    lea rcx, [rsp]           ; args
    call interp_try_dot_method
    add rsp, 64
    pop rcx                  ; clean method name length
    mov r12, rax
    jmp .postfix_loop

.postfix_dot_prop:
    pop rcx                  ; method name length
    ; Property access without () — just return the object for now
    jmp .postfix_loop

.postfix_done:
    mov rax, r12
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; interp_try_builtin — Try to call a builtin function
; rdi = name ptr, rsi = name len, rdx = arg count, rcx = args array
; Returns: rax = result, or -1 if not a builtin
; ============================================================
interp_try_builtin:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; name
    mov r13, rsi             ; name len
    mov r14, rdx             ; argc
    mov r15, rcx             ; args

    ; Check each builtin name
    ; len
    cmp r13, 3
    jne .not_len
    cmp byte [r12], 'l'
    jne .not_len
    cmp byte [r12 + 1], 'e'
    jne .not_len
    cmp byte [r12 + 2], 'n'
    jne .not_len
    mov rdi, [r15]
    call rt_len
    jmp .builtin_ret
.not_len:

    ; str
    cmp r13, 3
    jne .not_str
    cmp byte [r12], 's'
    jne .not_str
    cmp byte [r12 + 1], 't'
    jne .not_str
    cmp byte [r12 + 2], 'r'
    jne .not_str
    mov rdi, [r15]
    call rt_int_to_str
    jmp .builtin_ret
.not_str:

    ; int
    cmp r13, 3
    jne .not_int
    cmp byte [r12], 'i'
    jne .not_int
    cmp byte [r12 + 1], 'n'
    jne .not_int
    cmp byte [r12 + 2], 't'
    jne .not_int
    mov rdi, [r15]
    call rt_str_to_int
    jmp .builtin_ret
.not_int:

    ; type
    cmp r13, 4
    jne .not_type
    cmp byte [r12], 't'
    jne .not_type
    cmp byte [r12 + 1], 'y'
    jne .not_type
    cmp byte [r12 + 2], 'p'
    jne .not_type
    cmp byte [r12 + 3], 'e'
    jne .not_type
    mov rdi, [r15]
    call rt_type
    jmp .builtin_ret
.not_type:

    ; abs
    cmp r13, 3
    jne .not_abs
    cmp byte [r12], 'a'
    jne .not_abs
    cmp byte [r12 + 1], 'b'
    jne .not_abs
    cmp byte [r12 + 2], 's'
    jne .not_abs
    mov rdi, [r15]
    call rt_abs
    jmp .builtin_ret
.not_abs:

    ; min
    cmp r13, 3
    jne .not_min
    cmp byte [r12], 'm'
    jne .not_min
    cmp byte [r12 + 1], 'i'
    jne .not_min
    cmp byte [r12 + 2], 'n'
    jne .not_min
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_min
    jmp .builtin_ret
.not_min:

    ; max
    cmp r13, 3
    jne .not_max
    cmp byte [r12], 'm'
    jne .not_max
    cmp byte [r12 + 1], 'a'
    jne .not_max
    cmp byte [r12 + 2], 'x'
    jne .not_max
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_max
    jmp .builtin_ret
.not_max:

    ; sqrt
    cmp r13, 4
    jne .not_sqrt
    cmp byte [r12], 's'
    jne .not_sqrt
    cmp byte [r12 + 1], 'q'
    jne .not_sqrt
    cmp byte [r12 + 2], 'r'
    jne .not_sqrt
    cmp byte [r12 + 3], 't'
    jne .not_sqrt
    mov rdi, [r15]
    call rt_sqrt
    jmp .builtin_ret
.not_sqrt:

    ; upper
    cmp r13, 5
    jne .not_upper
    cmp byte [r12], 'u'
    jne .not_upper
    cmp byte [r12 + 1], 'p'
    jne .not_upper
    mov rdi, [r15]
    call rt_str_upper
    jmp .builtin_ret
.not_upper:

    ; lower
    cmp r13, 5
    jne .not_lower
    cmp byte [r12], 'l'
    jne .not_lower
    cmp byte [r12 + 1], 'o'
    jne .not_lower
    mov rdi, [r15]
    call rt_str_lower
    jmp .builtin_ret
.not_lower:

    ; trim
    cmp r13, 4
    jne .not_trim
    cmp byte [r12], 't'
    jne .not_trim
    cmp byte [r12 + 1], 'r'
    jne .not_trim
    cmp byte [r12 + 2], 'i'
    jne .not_trim
    cmp byte [r12 + 3], 'm'
    jne .not_trim
    mov rdi, [r15]
    call rt_str_trim
    jmp .builtin_ret
.not_trim:

    ; replace
    cmp r13, 7
    jne .not_replace
    cmp byte [r12], 'r'
    jne .not_replace
    cmp byte [r12 + 1], 'e'
    jne .not_replace
    cmp byte [r12 + 2], 'p'
    jne .not_replace
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    call rt_str_replace
    jmp .builtin_ret
.not_replace:

    ; find
    cmp r13, 4
    jne .not_find
    cmp byte [r12], 'f'
    jne .not_find
    cmp byte [r12 + 1], 'i'
    jne .not_find
    cmp byte [r12 + 2], 'n'
    jne .not_find
    cmp byte [r12 + 3], 'd'
    jne .not_find
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_str_index
    jmp .builtin_ret
.not_find:

    ; count
    cmp r13, 5
    jne .not_count
    cmp byte [r12], 'c'
    jne .not_count
    cmp byte [r12 + 1], 'o'
    jne .not_count
    ; Use rt_str_index in a loop? For now skip
    jmp .not_count
.not_count:

    ; sort
    cmp r13, 4
    jne .not_sort
    cmp byte [r12], 's'
    jne .not_sort
    cmp byte [r12 + 1], 'o'
    jne .not_sort
    cmp byte [r12 + 2], 'r'
    jne .not_sort
    cmp byte [r12 + 3], 't'
    jne .not_sort
    mov rdi, [r15]
    call rt_arr_sort
    jmp .builtin_ret
.not_sort:

    ; reverse
    cmp r13, 7
    jne .not_reverse
    cmp byte [r12], 'r'
    jne .not_reverse
    cmp byte [r12 + 1], 'e'
    jne .not_reverse
    cmp byte [r12 + 2], 'v'
    jne .not_reverse
    mov rdi, [r15]
    call rt_arr_reverse
    jmp .builtin_ret
.not_reverse:

    ; join
    cmp r13, 4
    jne .not_join
    cmp byte [r12], 'j'
    jne .not_join
    cmp byte [r12 + 1], 'o'
    jne .not_join
    cmp byte [r12 + 2], 'i'
    jne .not_join
    cmp byte [r12 + 3], 'n'
    jne .not_join
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_arr_join
    jmp .builtin_ret
.not_join:

    ; unique — use runtime if available
    cmp r13, 6
    jne .not_unique
    cmp byte [r12], 'u'
    jne .not_unique
    cmp byte [r12 + 1], 'n'
    jne .not_unique
    extern rt_arr_unique
    mov rdi, [r15]
    call rt_arr_unique
    jmp .builtin_ret
.not_unique:

    ; concat
    cmp r13, 6
    jne .not_concat
    cmp byte [r12], 'c'
    jne .not_concat
    cmp byte [r12 + 1], 'o'
    jne .not_concat
    cmp byte [r12 + 2], 'n'
    jne .not_concat
    extern rt_arr_concat
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_arr_concat
    jmp .builtin_ret
.not_concat:

    ; fill
    cmp r13, 4
    jne .not_fill
    cmp byte [r12], 'f'
    jne .not_fill
    cmp byte [r12 + 1], 'i'
    jne .not_fill
    cmp byte [r12 + 2], 'l'
    jne .not_fill
    cmp byte [r12 + 3], 'l'
    jne .not_fill
    extern rt_arr_fill
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_arr_fill
    jmp .builtin_ret
.not_fill:

    ; insert
    cmp r13, 6
    jne .not_insert
    cmp byte [r12], 'i'
    jne .not_insert
    cmp byte [r12 + 1], 'n'
    jne .not_insert
    cmp byte [r12 + 2], 's'
    jne .not_insert
    extern rt_arr_insert
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    call rt_arr_insert
    jmp .builtin_ret
.not_insert:

    ; remove
    cmp r13, 6
    jne .not_remove
    cmp byte [r12], 'r'
    jne .not_remove
    cmp byte [r12 + 1], 'e'
    jne .not_remove
    cmp byte [r12 + 2], 'm'
    jne .not_remove
    extern rt_arr_remove
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_arr_remove
    jmp .builtin_ret
.not_remove:

    ; range
    cmp r13, 5
    jne .not_range
    cmp byte [r12], 'r'
    jne .not_range
    cmp byte [r12 + 1], 'a'
    jne .not_range
    cmp byte [r12 + 2], 'n'
    jne .not_range
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_range
    jmp .builtin_ret
.not_range:

    ; random
    cmp r13, 6
    jne .not_random
    cmp byte [r12], 'r'
    jne .not_random
    cmp byte [r12 + 1], 'a'
    jne .not_random
    cmp byte [r12 + 2], 'n'
    jne .not_random
    cmp byte [r12 + 3], 'd'
    jne .not_random
    mov rdi, [r15]
    call rt_random
    jmp .builtin_ret
.not_random:

    ; assert
    cmp r13, 6
    jne .not_assert
    cmp byte [r12], 'a'
    jne .not_assert
    cmp byte [r12 + 1], 's'
    jne .not_assert
    cmp byte [r12 + 2], 's'
    jne .not_assert
    cmp byte [r12 + 3], 'e'
    jne .not_assert
    cmp byte [r12 + 4], 'r'
    jne .not_assert
    cmp byte [r12 + 5], 't'
    jne .not_assert
    ; assert(condition, message)
    mov rdi, [r15]           ; condition
    cmp rdi, 0
    jne .assert_pass
    ; Failed — print message and exit
    mov rax, 1
    mov rdi, 2
    mov rsi, str_assert_fail
    mov rdx, str_assert_fail_len
    syscall
    ; Print message
    mov rdi, [r15 + 8]
    cmp rdi, 0x400000
    jb .assert_exit
    push rdi
    call rt_str_len
    mov rdx, rax
    pop rsi
    mov rax, 1
    mov rdi, 2
    syscall
    ; Newline
    mov rax, 1
    mov rdi, 2
    mov rsi, interp_newline
    mov rdx, 1
    syscall
.assert_exit:
    mov rax, 60
    mov rdi, 1
    syscall
.assert_pass:
    mov rax, 1
    jmp .builtin_ret
.not_assert:

    ; hex
    cmp r13, 3
    jne .not_hex
    cmp byte [r12], 'h'
    jne .not_hex
    cmp byte [r12 + 1], 'e'
    jne .not_hex
    cmp byte [r12 + 2], 'x'
    jne .not_hex
    extern rt_hex
    mov rdi, [r15]
    call rt_hex
    jmp .builtin_ret
.not_hex:

    ; bin
    cmp r13, 3
    jne .not_bin
    cmp byte [r12], 'b'
    jne .not_bin
    cmp byte [r12 + 1], 'i'
    jne .not_bin
    cmp byte [r12 + 2], 'n'
    jne .not_bin
    extern rt_bin
    mov rdi, [r15]
    call rt_bin
    jmp .builtin_ret
.not_bin:

    ; bool
    cmp r13, 4
    jne .not_bool
    cmp byte [r12], 'b'
    jne .not_bool
    cmp byte [r12 + 1], 'o'
    jne .not_bool
    cmp byte [r12 + 2], 'o'
    jne .not_bool
    cmp byte [r12 + 3], 'l'
    jne .not_bool
    extern rt_bool
    mov rdi, [r15]
    call rt_bool
    jmp .builtin_ret
.not_bool:

    ; number (alias for int conversion)
    cmp r13, 6
    jne .not_number
    cmp byte [r12], 'n'
    jne .not_number
    cmp byte [r12 + 1], 'u'
    jne .not_number
    cmp byte [r12 + 2], 'm'
    jne .not_number
    mov rdi, [r15]
    call rt_str_to_int
    jmp .builtin_ret
.not_number:

    ; ord
    cmp r13, 3
    jne .not_ord
    cmp byte [r12], 'o'
    jne .not_ord
    cmp byte [r12 + 1], 'r'
    jne .not_ord
    cmp byte [r12 + 2], 'd'
    jne .not_ord
    extern rt_ord
    mov rdi, [r15]
    call rt_ord
    jmp .builtin_ret
.not_ord:

    ; chr
    cmp r13, 3
    jne .not_chr
    cmp byte [r12], 'c'
    jne .not_chr
    cmp byte [r12 + 1], 'h'
    jne .not_chr
    cmp byte [r12 + 2], 'r'
    jne .not_chr
    extern rt_chr
    mov rdi, [r15]
    call rt_chr
    jmp .builtin_ret
.not_chr:

    ; substr
    cmp r13, 6
    jne .not_substr
    cmp byte [r12], 's'
    jne .not_substr
    cmp byte [r12 + 1], 'u'
    jne .not_substr
    cmp byte [r12 + 2], 'b'
    jne .not_substr
    extern rt_substr
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    call rt_substr
    jmp .builtin_ret
.not_substr:

    ; push
    cmp r13, 4
    jne .not_push_builtin
    cmp byte [r12], 'p'
    jne .not_push_builtin
    cmp byte [r12 + 1], 'u'
    jne .not_push_builtin
    cmp byte [r12 + 2], 's'
    jne .not_push_builtin
    cmp byte [r12 + 3], 'h'
    jne .not_push_builtin
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_arr_push
    jmp .builtin_ret
.not_push_builtin:

    ; Not a builtin
    mov rax, -1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.builtin_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; interp_try_dot_method — Handle obj.method(args)
; rdi = method name, rsi = method name len, rdx = arg count, rcx = args
; args[0] = object, args[1..] = additional args
; Returns: rax = result
; ============================================================
interp_try_dot_method:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; method name
    mov r13, rsi             ; method name len
    mov r14, rdx             ; argc
    mov r15, rcx             ; args (args[0] = object)

    ; .upper()
    cmp r13, 5
    jne .dm_not_upper
    cmp byte [r12], 'u'
    jne .dm_not_upper
    cmp byte [r12 + 1], 'p'
    jne .dm_not_upper
    mov rdi, [r15]
    call rt_str_upper
    jmp .dm_ret
.dm_not_upper:

    ; .lower()
    cmp r13, 5
    jne .dm_not_lower
    cmp byte [r12], 'l'
    jne .dm_not_lower
    cmp byte [r12 + 1], 'o'
    jne .dm_not_lower
    mov rdi, [r15]
    call rt_str_lower
    jmp .dm_ret
.dm_not_lower:

    ; .trim()
    cmp r13, 4
    jne .dm_not_trim
    cmp byte [r12], 't'
    jne .dm_not_trim
    cmp byte [r12 + 1], 'r'
    jne .dm_not_trim
    mov rdi, [r15]
    call rt_str_trim
    jmp .dm_ret
.dm_not_trim:

    ; .replace(old, new)
    cmp r13, 7
    jne .dm_not_replace
    cmp byte [r12], 'r'
    jne .dm_not_replace
    cmp byte [r12 + 1], 'e'
    jne .dm_not_replace
    cmp byte [r12 + 2], 'p'
    jne .dm_not_replace
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    call rt_str_replace
    jmp .dm_ret
.dm_not_replace:

    ; .contains(sub)
    cmp r13, 8
    jne .dm_not_contains
    cmp byte [r12], 'c'
    jne .dm_not_contains
    cmp byte [r12 + 1], 'o'
    jne .dm_not_contains
    cmp byte [r12 + 2], 'n'
    jne .dm_not_contains
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_str_contains
    jmp .dm_ret
.dm_not_contains:

    ; .startswith(prefix)
    cmp r13, 10
    jne .dm_not_startswith
    cmp byte [r12], 's'
    jne .dm_not_startswith
    cmp byte [r12 + 1], 't'
    jne .dm_not_startswith
    cmp byte [r12 + 2], 'a'
    jne .dm_not_startswith
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_str_startswith
    jmp .dm_ret
.dm_not_startswith:

    ; .endswith(suffix)
    cmp r13, 8
    jne .dm_not_endswith
    cmp byte [r12], 'e'
    jne .dm_not_endswith
    cmp byte [r12 + 1], 'n'
    jne .dm_not_endswith
    cmp byte [r12 + 2], 'd'
    jne .dm_not_endswith
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_str_endswith
    jmp .dm_ret
.dm_not_endswith:

    ; .index(sub)
    cmp r13, 5
    jne .dm_not_index
    cmp byte [r12], 'i'
    jne .dm_not_index
    cmp byte [r12 + 1], 'n'
    jne .dm_not_index
    cmp byte [r12 + 2], 'd'
    jne .dm_not_index
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_str_index
    jmp .dm_ret
.dm_not_index:

    ; .split(delim)
    cmp r13, 5
    jne .dm_not_split
    cmp byte [r12], 's'
    jne .dm_not_split
    cmp byte [r12 + 1], 'p'
    jne .dm_not_split
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_str_split
    jmp .dm_ret
.dm_not_split:

    ; .repeat(n)
    cmp r13, 6
    jne .dm_not_repeat
    cmp byte [r12], 'r'
    jne .dm_not_repeat
    cmp byte [r12 + 1], 'e'
    jne .dm_not_repeat
    cmp byte [r12 + 2], 'p'
    jne .dm_not_repeat
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call rt_str_repeat
    jmp .dm_ret
.dm_not_repeat:

    ; .len()
    cmp r13, 3
    jne .dm_not_len
    cmp byte [r12], 'l'
    jne .dm_not_len
    cmp byte [r12 + 1], 'e'
    jne .dm_not_len
    mov rdi, [r15]
    call rt_len
    jmp .dm_ret
.dm_not_len:

    ; Unknown method — return object unchanged
    mov rax, [r15]

.dm_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

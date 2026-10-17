; ============================================================
; SEVEN Language - Main Entry Point
; Phase 1: Bootstrap Compiler
; Architecture: x86-64 NASM Assembly (Linux ELF64)
; Author: Tejas Chandivakar
; ============================================================
;
; Usage:
;   seven build <file.seven>     → compile to executable
;   seven run <file.seven>       → compile and run (TODO)
;   seven lex <file.seven>       → show tokens (debug)
;
; Accepts: .seven, .sev, .sv7, .s7 extensions
;
; Pipeline: Source → Lexer → Parser → Codegen → .asm → NASM → ld → ELF64
; ============================================================

section .data
    ; ---- Messages ----
    msg_banner  db "SEVEN Compiler v0.1 (Phase 1 Bootstrap)", 10, 0
    msg_banner_len equ $ - msg_banner

    msg_usage   db "Usage: seven <command> <file>", 10
                db "Commands:", 10
                db "  build <file.seven>  - compile to executable", 10
                db "  lex <file.seven>    - show tokens (debug)", 10
                db 10
                db "Accepted extensions: .seven .sev .sv7 .s7", 10, 0
    msg_usage_len equ $ - msg_usage

    msg_file_err db "Error: Could not open file: ", 0
    msg_file_err_len equ $ - msg_file_err

    msg_lexing   db "Lexing... ", 0
    msg_parsing  db "Parsing... ", 0
    msg_codegen  db "Generating code... ", 0
    msg_writing  db "Writing output... ", 0
    msg_done     db "done", 10, 0
    msg_ok       db "OK", 10, 0
    msg_compile_ok db "Compilation successful!", 10, 0
    msg_compile_ok_len equ $ - msg_compile_ok

    msg_wrote    db "Output: ", 0
    msg_wrote_len equ $ - msg_wrote

    msg_nextsteps db "To assemble and link:", 10
                  db "  nasm -f elf64 <output>.asm -o <output>.o", 10
                  db "  nasm -f elf64 src/runtime.asm -o runtime.o", 10
                  db "  ld <output>.o runtime.o -o <output>", 10, 0
    msg_nextsteps_len equ $ - msg_nextsteps

    msg_tokens   db "Tokens: ", 0
    msg_newline  db 10, 0

    ; Token type names for debug output
    tok_names:
    tok_name_eof    db "EOF", 0
    tok_name_ident  db "IDENT", 0
    tok_name_int    db "INT", 0
    tok_name_float  db "FLOAT", 0
    tok_name_string db "STRING", 0
    tok_name_kw     db "KEYWORD", 0
    tok_name_op     db "OP", 0
    tok_name_punct  db "PUNCT", 0
    tok_name_nl     db "NEWLINE", 0
    tok_name_dot    db "DOT", 0

    ; Output file suffix
    out_suffix  db ".asm", 0

    ; Commands
    cmd_build   db "build", 0
    cmd_lex     db "lex", 0
    cmd_run     db "run", 0

    ; Debug format strings
    dbg_tok_pre  db "  [", 0
    dbg_tok_mid  db "] ", 0
    dbg_tok_quote db "'", 0
    dbg_tok_nl   db 10, 0

section .bss
    argc        resq 1
    argv_cmd    resq 1       ; pointer to command string
    argv_file   resq 1       ; pointer to filename string
    out_filename resb 256    ; output .asm filename
    base_name   resb 256     ; filename without extension

section .text
    global _start

    ; External functions
    extern lexer_init, lexer_load_file, lexer_tokenize
    extern lexer_token_count, lexer_get_token, lexer_get_mode
    extern codegen_init, codegen_program, codegen_write_file
    extern rt_print_str, rt_print_int, rt_print_newline, rt_str_len

; ============================================================
; _start — Entry point
; ============================================================
_start:
    ; Get argc
    mov rax, [rsp]
    mov [argc], rax

    ; Check minimum args (program + command + file = 3)
    cmp rax, 3
    jl .check_no_args

    ; Get command (argv[1])
    mov rax, [rsp + 16]
    mov [argv_cmd], rax

    ; Get filename (argv[2])
    mov rax, [rsp + 24]
    mov [argv_file], rax

    ; Determine command
    mov rdi, [argv_cmd]
    mov rsi, cmd_build
    call str_equal
    cmp rax, 1
    je .do_build

    mov rdi, [argv_cmd]
    mov rsi, cmd_lex
    call str_equal
    cmp rax, 1
    je .do_lex

    mov rdi, [argv_cmd]
    mov rsi, cmd_run
    call str_equal
    cmp rax, 1
    je .do_build             ; run = build for now

    jmp .show_usage

.check_no_args:
    ; If just 2 args (seven <file>), assume build
    cmp qword [argc], 2
    jne .show_usage
    mov rax, [rsp + 16]
    mov [argv_file], rax
    jmp .do_build

; ============================================================
; do_build — Full compilation pipeline
; ============================================================
.do_build:
    ; Print banner
    mov rax, 1
    mov rdi, 2              ; stderr
    mov rsi, msg_banner
    mov rdx, msg_banner_len
    syscall

    ; Step 1: Lex
    call print_msg_lexing
    call lexer_init
    mov rdi, [argv_file]
    call lexer_load_file
    cmp rax, 0
    jne .file_error
    call lexer_tokenize
    call print_msg_done

    ; Step 2: Codegen (reads directly from token stream)
    call print_msg_codegen
    call codegen_init
    call codegen_program
    call print_msg_done

    ; Step 4: Write output file
    call print_msg_writing
    call make_output_filename
    mov rdi, out_filename
    call codegen_write_file
    cmp rax, 0
    jne .write_error
    call print_msg_done

    ; Print output filename
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_wrote
    mov rdx, msg_wrote_len
    syscall
    mov rdi, out_filename
    call rt_str_len
    mov rdx, rax
    mov rsi, out_filename
    mov rax, 1
    mov rdi, 2
    syscall
    call print_newline_stderr

    ; Print success
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_compile_ok
    mov rdx, msg_compile_ok_len
    syscall

    ; Print next steps
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_nextsteps
    mov rdx, msg_nextsteps_len
    syscall

    ; Exit 0
    xor rdi, rdi
    jmp .exit

; ============================================================
; do_lex — Lex only, print tokens (debug mode)
; ============================================================
.do_lex:
    ; Print banner
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_banner
    mov rdx, msg_banner_len
    syscall

    ; Lex
    call lexer_init
    mov rdi, [argv_file]
    call lexer_load_file
    cmp rax, 0
    jne .file_error
    call lexer_tokenize

    ; Print token count
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_tokens
    mov rdx, 8
    syscall

    call lexer_token_count
    mov rdi, rax
    call print_int_stdout
    call print_newline_stdout

    ; Print each token
    xor r12, r12             ; token index
.print_token_loop:
    mov rdi, r12
    call lexer_get_token
    mov r13, rax             ; token pointer

    ; Check for EOF
    movzx eax, byte [r13]
    cmp al, 0               ; TOK_EOF
    je .lex_done

    ; Print: "  [TYPE] 'text'"
    mov rax, 1
    mov rdi, 1
    mov rsi, dbg_tok_pre
    mov rdx, 3
    syscall

    ; Print type name
    movzx eax, byte [r13]
    call get_tok_type_name
    mov rdi, rax
    call rt_str_len
    mov rdx, rax
    mov rsi, rdi
    mov rax, 1
    mov rdi, 1
    syscall

    ; Print "] "
    mov rax, 1
    mov rdi, 1
    mov rsi, dbg_tok_mid
    mov rdx, 2
    syscall

    ; Print token text (if not newline)
    movzx eax, byte [r13]
    cmp al, 8               ; TOK_NEWLINE
    je .skip_text

    ; Print quote
    mov rax, 1
    mov rdi, 1
    mov rsi, dbg_tok_quote
    mov rdx, 1
    syscall

    ; Print text
    mov ecx, [r13 + 4]      ; length
    mov rsi, [r13 + 8]      ; pointer
    mov rdx, rcx
    mov rax, 1
    mov rdi, 1
    syscall

    ; Print quote
    mov rax, 1
    mov rdi, 1
    mov rsi, dbg_tok_quote
    mov rdx, 1
    syscall

.skip_text:
    ; Print newline
    call print_newline_stdout

    inc r12
    jmp .print_token_loop

.lex_done:
    xor rdi, rdi
    jmp .exit

; ============================================================
; Error handlers
; ============================================================
.file_error:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_file_err
    mov rdx, msg_file_err_len
    syscall
    ; Print filename
    mov rsi, [argv_file]
    mov rdi, rsi
    call rt_str_len
    mov rdx, rax
    mov rax, 1
    mov rdi, 2
    syscall
    call print_newline_stderr
    mov rdi, 1
    jmp .exit

.write_error:
    mov rdi, 1
    jmp .exit

.show_usage:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_usage
    mov rdx, msg_usage_len
    syscall
    mov rdi, 1
    jmp .exit

.exit:
    mov rax, 60
    syscall

; ============================================================
; Helper functions
; ============================================================

; str_equal — Compare two null-terminated strings
; rdi = str1, rsi = str2
; Returns: rax = 1 if equal, 0 if not
str_equal:
.loop:
    movzx eax, byte [rdi]
    movzx ecx, byte [rsi]
    cmp al, cl
    jne .ne
    cmp al, 0
    je .eq
    inc rdi
    inc rsi
    jmp .loop
.eq:
    mov rax, 1
    ret
.ne:
    xor rax, rax
    ret

; make_output_filename — Create output .asm filename from input
; Strips extension, adds .asm
make_output_filename:
    push rbp
    mov rbp, rsp
    push r12

    mov rdi, [argv_file]

    ; Find last '/' or '\' or start
    mov r12, rdi             ; base = start
.find_base:
    movzx eax, byte [rdi]
    cmp al, 0
    je .found_base
    cmp al, '/'
    je .set_base
    cmp al, '\'
    je .set_base
    inc rdi
    jmp .find_base
.set_base:
    lea r12, [rdi + 1]
    inc rdi
    jmp .find_base
.found_base:

    ; Copy base name, stop at '.' or end
    lea rdi, [out_filename]
    mov rsi, r12
.copy_base:
    movzx eax, byte [rsi]
    cmp al, 0
    je .add_ext
    cmp al, '.'
    je .add_ext
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .copy_base

.add_ext:
    ; Add ".asm"
    mov byte [rdi], '.'
    mov byte [rdi + 1], 'a'
    mov byte [rdi + 2], 's'
    mov byte [rdi + 3], 'm'
    mov byte [rdi + 4], 0

    pop r12
    pop rbp
    ret

; get_tok_type_name — Get name string for token type
; al = token type
; Returns: rax = pointer to name string
get_tok_type_name:
    cmp al, 0
    je .eof
    cmp al, 1
    je .ident
    cmp al, 2
    je .int_
    cmp al, 3
    je .float_
    cmp al, 4
    je .string_
    cmp al, 5
    je .keyword_
    cmp al, 6
    je .op_
    cmp al, 7
    je .punct_
    cmp al, 8
    je .newline_
    cmp al, 9
    je .dot_
    mov rax, tok_name_eof
    ret
.eof:
    mov rax, tok_name_eof
    ret
.ident:
    mov rax, tok_name_ident
    ret
.int_:
    mov rax, tok_name_int
    ret
.float_:
    mov rax, tok_name_float
    ret
.string_:
    mov rax, tok_name_string
    ret
.keyword_:
    mov rax, tok_name_kw
    ret
.op_:
    mov rax, tok_name_op
    ret
.punct_:
    mov rax, tok_name_punct
    ret
.newline_:
    mov rax, tok_name_nl
    ret
.dot_:
    mov rax, tok_name_dot
    ret

; print_int_stdout — Print integer rdi to stdout
print_int_stdout:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 24

    mov rax, rdi
    lea rbx, [rsp + 23]
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

    ; Print
    lea rdx, [rsp + 23]
    sub rdx, rbx
    mov rsi, rbx
    mov rax, 1
    mov rdi, 1
    syscall

    add rsp, 24
    pop rbx
    pop rbp
    ret

; print_newline_stdout
print_newline_stdout:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    ret

; print_newline_stderr
print_newline_stderr:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_newline
    mov rdx, 1
    syscall
    ret

; Progress messages (to stderr)
print_msg_lexing:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_lexing
    mov rdx, 10
    syscall
    ret

print_msg_parsing:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_parsing
    mov rdx, 11
    syscall
    ret

print_msg_codegen:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_codegen
    mov rdx, 20
    syscall
    ret

print_msg_writing:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_writing
    mov rdx, 18
    syscall
    ret

print_msg_done:
    mov rax, 1
    mov rdi, 2
    mov rsi, msg_done
    mov rdx, 5
    syscall
    ret

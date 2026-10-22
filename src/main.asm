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
    msg_banner  db "SEVEN Compiler v1.0", 10, 0
    msg_banner_len equ $ - msg_banner

    msg_version db "SEVEN Language Compiler", 10
                db "  Version:  1.0.0", 10
                db "  Phase:    10 (Error Handling)", 10
                db "  Target:   x86-64 Linux (ELF64)", 10
                db "  Author:   Tejas Chandivakar", 10
                db "  Tagline:  Fast as Assembly. Simple as Python.", 10, 0
    msg_version_len equ $ - msg_version

    msg_usage   db "Usage: seven <command> <file>", 10, 10
                db "Commands:", 10
                db "  build <file.seven>  - compile to .asm", 10
                db "  run   <file.seven>  - compile and run", 10
                db "  lex   <file.seven>  - show tokens (debug)", 10
                db "  version             - show version info", 10
                db "  help                - show this help", 10
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
    cmd_version db "version", 0
    cmd_help    db "help", 0

    ; Run mode strings
    nasm_path   db "/usr/bin/nasm", 0
    nasm_str    db "nasm", 0
    nasm_f_flag db "-f", 0
    nasm_fmt    db "elf64", 0
    nasm_w_flag db "-w-label-redef-late", 0
    nasm_o_flag db "-o", 0
    ld_path     db "/usr/bin/ld", 0
    ld_str      db "ld", 0
    msg_run_err db "Error: run step failed", 10, 0
    msg_run_err_len equ $ - msg_run_err
    msg_running db "Running...", 10, 0
    msg_running_len equ $ - msg_running

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
    obj_filename resb 256    ; output .o filename
    bin_filename resb 256    ; output binary filename
    runtime_path resb 512    ; path to runtime.o
    is_run_mode resq 1       ; 1 if running in `run` mode
    nasm_argv   resq 10      ; argv for nasm exec
    ld_argv     resq 10      ; argv for ld exec
    bin_argv    resq 4       ; argv for binary exec

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
    ; Save initial rsp for args()/env() access
    extern saved_rsp
    mov [saved_rsp], rsp

    ; Get argc
    mov rax, [rsp]
    mov [argc], rax

    ; Need at least 2 args (program + something)
    cmp rax, 2
    jl .show_usage

    ; Get command/file (argv[1])
    mov rax, [rsp + 16]
    mov [argv_cmd], rax

    ; Check no-file commands first: version, help
    mov rdi, [argv_cmd]
    mov rsi, cmd_version
    call str_equal
    cmp rax, 1
    je .do_version

    mov rdi, [argv_cmd]
    mov rsi, cmd_help
    call str_equal
    cmp rax, 1
    je .do_help

    ; Commands that need a file need 3 args
    cmp qword [argc], 3
    jl .check_shorthand

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
    je .do_run

    jmp .show_usage

.check_shorthand:
    ; 2 args: seven <file> — assume build
    mov rax, [rsp + 16]
    mov [argv_file], rax
    jmp .do_build

; ============================================================
; do_version — Print version info
; ============================================================
.do_version:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_version
    mov rdx, msg_version_len
    syscall
    xor rdi, rdi
    jmp .exit

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
; do_run — Interpret source directly (no compile step)
; ============================================================
.do_run:
    mov qword [is_run_mode], 1

    ; Step 1: Lex
    call lexer_init
    mov rdi, [argv_file]
    call lexer_load_file
    cmp rax, 0
    jne .file_error
    call lexer_tokenize

    ; Step 2: Interpret
    extern interp_init, interp_program
    call interp_init
    call interp_program

    ; interp_program returns exit code in rax
    mov rdi, rax
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

.do_help:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_usage
    mov rdx, msg_usage_len
    syscall
    xor rdi, rdi
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

; ============================================================
; fork_exec_wait — Fork, exec a program, wait for it
; rdi = path to executable
; rsi = argv array (null-terminated)
; Returns: rax = child exit code (0 = success)
; ============================================================
fork_exec_wait:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    sub rsp, 8              ; align + space for wstatus

    mov r12, rdi             ; path
    mov r13, rsi             ; argv

    ; fork() = syscall 57
    mov rax, 57
    syscall
    cmp rax, 0
    jl .few_error            ; fork failed
    je .few_child            ; child process

    ; Parent: wait for child
    mov r14, rax             ; child pid
    ; wait4(pid, &wstatus, 0, NULL) = syscall 61
    mov rdi, r14
    lea rsi, [rbp - 32]     ; wstatus on stack
    xor rdx, rdx            ; options = 0
    xor r10, r10             ; rusage = NULL
    mov rax, 61
    syscall

    ; Extract exit code: wstatus >> 8 & 0xFF
    mov eax, [rbp - 32]
    shr eax, 8
    and eax, 0xFF

    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.few_child:
    ; execve(path, argv, envp=NULL) = syscall 59
    mov rdi, r12
    mov rsi, r13
    xor rdx, rdx            ; envp = NULL
    mov rax, 59
    syscall
    ; If execve returns, it failed — exit(127)
    mov rdi, 127
    mov rax, 60
    syscall

.few_error:
    mov rax, 1
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; make_obj_filename — Create .o filename from out_filename
; e.g. "test.asm" → "test.o"
; ============================================================
make_obj_filename:
    lea rsi, [out_filename]
    lea rdi, [obj_filename]
.mol:
    movzx eax, byte [rsi]
    cmp al, 0
    je .mo_ext
    cmp al, '.'
    je .mo_dot
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .mol
.mo_dot:
    ; Check if this is the .asm extension
    cmp byte [rsi + 1], 'a'
    jne .mo_copy
    cmp byte [rsi + 2], 's'
    jne .mo_copy
    cmp byte [rsi + 3], 'm'
    jne .mo_copy
.mo_ext:
    mov byte [rdi], '.'
    mov byte [rdi + 1], 'o'
    mov byte [rdi + 2], 0
    ret
.mo_copy:
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .mol

; ============================================================
; make_bin_filename — Create binary filename (no extension)
; e.g. "test.asm" → "test"
; ============================================================
make_bin_filename:
    lea rsi, [out_filename]
    lea rdi, [bin_filename]
.mbl:
    movzx eax, byte [rsi]
    cmp al, 0
    je .mb_done
    cmp al, '.'
    je .mb_dot
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .mbl
.mb_dot:
    cmp byte [rsi + 1], 'a'
    jne .mb_copy
    cmp byte [rsi + 2], 's'
    jne .mb_copy
    cmp byte [rsi + 3], 'm'
    jne .mb_copy
.mb_done:
    mov byte [rdi], 0
    ret
.mb_copy:
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .mbl

; ============================================================
; find_runtime_path — Find runtime.o relative to the compiler
; Uses /proc/self/exe to find compiler location, then appends runtime.o
; ============================================================
find_runtime_path:
    push rbp
    mov rbp, rsp
    push r12

    ; readlink("/proc/self/exe", buf, 511) = syscall 89
    lea rdi, [.proc_self]
    lea rsi, [runtime_path]
    mov rdx, 511
    mov rax, 89
    syscall
    cmp rax, 0
    jle .frp_fallback

    ; Null-terminate
    lea rdi, [runtime_path]
    mov byte [rdi + rax], 0

    ; Find last '/' and replace everything after with "runtime.o"
    mov r12, rax
    lea rdi, [runtime_path]
    add rdi, r12
.frp_scan:
    cmp rdi, runtime_path
    jbe .frp_fallback
    dec rdi
    cmp byte [rdi], '/'
    jne .frp_scan

    ; rdi points to last '/', write "runtime.o" after it
    inc rdi
    mov byte [rdi],     'r'
    mov byte [rdi + 1], 'u'
    mov byte [rdi + 2], 'n'
    mov byte [rdi + 3], 't'
    mov byte [rdi + 4], 'i'
    mov byte [rdi + 5], 'm'
    mov byte [rdi + 6], 'e'
    mov byte [rdi + 7], '.'
    mov byte [rdi + 8], 'o'
    mov byte [rdi + 9], 0

    pop r12
    pop rbp
    ret

.frp_fallback:
    ; Fallback: use "build/runtime.o"
    lea rdi, [runtime_path]
    mov byte [rdi],      'b'
    mov byte [rdi + 1],  'u'
    mov byte [rdi + 2],  'i'
    mov byte [rdi + 3],  'l'
    mov byte [rdi + 4],  'd'
    mov byte [rdi + 5],  '/'
    mov byte [rdi + 6],  'r'
    mov byte [rdi + 7],  'u'
    mov byte [rdi + 8],  'n'
    mov byte [rdi + 9],  't'
    mov byte [rdi + 10], 'i'
    mov byte [rdi + 11], 'm'
    mov byte [rdi + 12], 'e'
    mov byte [rdi + 13], '.'
    mov byte [rdi + 14], 'o'
    mov byte [rdi + 15], 0

    pop r12
    pop rbp
    ret

section .rodata
.proc_self: db "/proc/self/exe", 0

section .text

; ============================================================
; delete_file — Unlink a file
; rdi = path (null-terminated)
; ============================================================
delete_file:
    ; unlink() = syscall 87
    mov rax, 87
    syscall
    ret

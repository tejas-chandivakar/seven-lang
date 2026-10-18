; ============================================================
; SEVEN Language - Lexer (Tokenizer)
; Phase 1: Bootstrap Compiler
; Architecture: x86-64 NASM Assembly (Linux ELF64)
; Author: Tejas Chandivakar
; ============================================================
;
; Tokenizes .seven/.sev/.sv7/.s7 source files.
; Syntax: No ':' block start. 'end' block close.
; Modes: 'mode hybrid' (default), 'mode natural'.
;
; Token format in memory (16 bytes per token):
;   [type:1][subtype:1][padding:2][length:4][pointer:8]
; ============================================================

section .data
    ; ---- Keyword table (null-terminated strings) ----
    ; Each keyword: address, length, token subtype
    ; Export keyword labels for codegen
    global kw_show, kw_ask, kw_err, kw_secret, kw_write, kw_read
    global kw_if, kw_elif, kw_else, kw_end
    global kw_func, kw_return, kw_repeat, kw_times, kw_while, kw_each, kw_as
    global kw_skip, kw_stop, kw_true, kw_false, kw_null
    global kw_and, kw_or, kw_not, kw_in, kw_is
    global kw_equals, kw_isnt, kw_above, kw_below, kw_atleast, kw_atmost
    global kw_try, kw_catch, kw_error
    global kw_many, kw_mode, kw_push
    global kw_match, kw_case

    kw_table:
    kw_show     db "show", 0
    kw_ask      db "ask", 0
    kw_err      db "err", 0
    kw_secret   db "secret", 0
    kw_write    db "write", 0
    kw_read     db "read", 0
    kw_readlines db "readlines", 0
    kw_if       db "if", 0
    kw_elif     db "elif", 0
    kw_else     db "else", 0
    kw_end      db "end", 0
    kw_func     db "func", 0
    kw_return   db "return", 0
    kw_repeat   db "repeat", 0
    kw_times    db "times", 0
    kw_while    db "while", 0
    kw_each     db "each", 0
    kw_as       db "as", 0
    kw_skip     db "skip", 0
    kw_stop     db "stop", 0
    kw_true     db "true", 0
    kw_false    db "false", 0
    kw_null     db "null", 0
    kw_and      db "and", 0
    kw_or       db "or", 0
    kw_not      db "not", 0
    kw_in       db "in", 0
    kw_is       db "is", 0
    kw_equals   db "equals", 0
    kw_isnt     db "isnt", 0
    kw_above    db "above", 0
    kw_below    db "below", 0
    kw_atleast  db "atleast", 0
    kw_atmost   db "atmost", 0
    kw_try      db "try", 0
    kw_catch    db "catch", 0
    kw_error    db "error", 0
    kw_many     db "many", 0
    kw_mode     db "mode", 0
    kw_push     db "push", 0
    kw_match    db "match", 0
    kw_case     db "case", 0
    kw_end_marker db 0      ; sentinel

    ; ---- Keyword pointer table for fast lookup ----
    ; Array of [pointer, length] pairs
    kw_ptrs:
    dq kw_show, 4
    dq kw_ask, 3
    dq kw_err, 3
    dq kw_secret, 6
    dq kw_write, 5
    dq kw_read, 4
    dq kw_readlines, 9
    dq kw_if, 2
    dq kw_elif, 4
    dq kw_else, 4
    dq kw_end, 3
    dq kw_func, 4
    dq kw_return, 6
    dq kw_repeat, 6
    dq kw_times, 5
    dq kw_while, 5
    dq kw_each, 4
    dq kw_as, 2
    dq kw_skip, 4
    dq kw_stop, 4
    dq kw_true, 4
    dq kw_false, 5
    dq kw_null, 4
    dq kw_and, 3
    dq kw_or, 2
    dq kw_not, 3
    dq kw_in, 2
    dq kw_is, 2
    dq kw_equals, 6
    dq kw_isnt, 4
    dq kw_above, 5
    dq kw_below, 5
    dq kw_atleast, 7
    dq kw_atmost, 6
    dq kw_try, 3
    dq kw_catch, 5
    dq kw_error, 5
    dq kw_many, 4
    dq kw_mode, 4
    dq kw_push, 4
    dq kw_match, 5
    dq kw_case, 4
    dq 0, 0                 ; sentinel

    ; ---- Token type constants ----
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

    ; ---- Operator subtypes ----
    OP_PLUS     equ 1
    OP_MINUS    equ 2
    OP_STAR     equ 3
    OP_SLASH    equ 4
    OP_PERCENT  equ 5
    OP_DSTAR    equ 6       ; **
    OP_DSLASH   equ 7       ; //
    OP_EQ       equ 8       ; ==
    OP_NEQ      equ 9       ; !=
    OP_LT       equ 10
    OP_GT       equ 11
    OP_LTE      equ 12      ; <=
    OP_GTE      equ 13      ; >=
    OP_ASSIGN   equ 14      ; =
    OP_AMP      equ 15      ; &
    OP_PIPE     equ 16      ; |
    OP_CARET    equ 17      ; ^
    OP_TILDE    equ 18      ; ~
    OP_LSHIFT   equ 19      ; <<
    OP_RSHIFT   equ 20      ; >>

    ; ---- Punctuation subtypes ----
    PUNCT_LPAREN  equ 1     ; (
    PUNCT_RPAREN  equ 2     ; )
    PUNCT_LBRACKET equ 3    ; [
    PUNCT_RBRACKET equ 4    ; ]
    PUNCT_COMMA   equ 5     ; ,
    PUNCT_DOT     equ 6     ; .

    ; ---- Error messages ----
    err_unterminated_str db "Error: Unterminated string at line ", 0
    err_unterminated_comment db "Error: Unterminated multi-line comment at line ", 0
    err_unexpected_char db "Error: Unexpected character at line ", 0

section .bss
    ; Source buffer
    src_buf      resb 131072     ; 128KB source buffer
    src_len      resq 1
    src_pos      resq 1          ; current position in source
    src_line     resq 1          ; current line number

    ; Token output buffer (max 16384 tokens * 16 bytes = 256KB)
    tok_buf      resb 262144
    tok_count    resq 1
    tok_pos      resq 1          ; current token index (for parser)

    ; Identifier scratch buffer
    ident_buf    resb 256

    ; Mode
    current_mode resb 1          ; 0 = hybrid, 1 = natural

section .text

; ============================================================
; lexer_init — Initialize lexer state
; ============================================================
global lexer_init
lexer_init:
    mov qword [src_pos], 0
    mov qword [src_line], 1
    mov qword [tok_count], 0
    mov qword [tok_pos], 0
    mov byte [current_mode], 0   ; hybrid default
    ret

; ============================================================
; lexer_load_file — Load source file into src_buf
; rdi = filename (null-terminated)
; Returns: rax = 0 on success, -1 on error
; ============================================================
global lexer_load_file
lexer_load_file:
    push rbp
    mov rbp, rsp
    push r12

    ; Open file
    mov rax, 2              ; sys_open
    xor rsi, rsi            ; O_RDONLY
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .error
    mov r12, rax            ; save fd

    ; Read file
    mov rax, 0              ; sys_read
    mov rdi, r12
    mov rsi, src_buf
    mov rdx, 131071         ; max bytes
    syscall
    cmp rax, 0
    jl .close_error
    mov [src_len], rax

    ; Null-terminate
    mov byte [src_buf + rax], 0

    ; Close
    mov rax, 3
    mov rdi, r12
    syscall

    xor rax, rax            ; success
    pop r12
    pop rbp
    ret

.close_error:
    push rax
    mov rax, 3
    mov rdi, r12
    syscall
    pop rax
.error:
    mov rax, -1
    pop r12
    pop rbp
    ret

; ============================================================
; lexer_peek — Get current character without advancing
; Returns: al = current char (0 if EOF)
; ============================================================
lexer_peek:
    mov rax, [src_pos]
    cmp rax, [src_len]
    jge .eof
    movzx eax, byte [src_buf + rax]
    ret
.eof:
    xor eax, eax
    ret

; ============================================================
; lexer_peek_at — Get character at offset rdi from current position
; Returns: al = char (0 if out of bounds)
; ============================================================
lexer_peek_at:
    mov rax, [src_pos]
    add rax, rdi
    cmp rax, [src_len]
    jge .eof
    movzx eax, byte [src_buf + rax]
    ret
.eof:
    xor eax, eax
    ret

; ============================================================
; lexer_advance — Advance one character, track line numbers
; Returns: al = consumed char
; ============================================================
lexer_advance:
    mov rax, [src_pos]
    cmp rax, [src_len]
    jge .eof
    movzx eax, byte [src_buf + rax]
    inc qword [src_pos]
    cmp al, 10              ; newline?
    jne .done
    inc qword [src_line]
.done:
    ret
.eof:
    xor eax, eax
    ret

; ============================================================
; emit_token — Add token to token buffer
; dil = type, sil = subtype, rdx = pointer to text, rcx = length
; ============================================================
global emit_token
emit_token:
    push rbx
    mov rax, [tok_count]
    shl rax, 4              ; * 16 bytes per token
    lea rbx, [tok_buf + rax]
    mov [rbx], dil           ; type
    mov [rbx + 1], sil       ; subtype
    push rax
    mov rax, [src_line]
    mov [rbx + 2], ax        ; line number (16-bit)
    pop rax
    mov [rbx + 4], ecx       ; length
    mov [rbx + 8], rdx       ; pointer
    inc qword [tok_count]
    pop rbx
    ret

; ============================================================
; skip_whitespace — Skip spaces and tabs (not newlines)
; ============================================================
skip_whitespace:
.loop:
    call lexer_peek
    cmp al, ' '
    je .skip
    cmp al, 9               ; tab
    je .skip
    cmp al, 13              ; carriage return
    je .skip
    ret
.skip:
    call lexer_advance
    jmp .loop

; ============================================================
; scan_comment — Handle !! and !!! comments
; Called when current char is '!'
; ============================================================
scan_comment:
    push rbp
    mov rbp, rsp

    ; Check for !!
    mov rdi, 1
    call lexer_peek_at
    cmp al, '!'
    jne .not_comment

    ; Check for !!! (multi-line)
    mov rdi, 2
    call lexer_peek_at
    cmp al, '!'
    je .multiline

    ; Single-line comment: skip to end of line
    call lexer_advance       ; skip first !
    call lexer_advance       ; skip second !
.single_loop:
    call lexer_peek
    cmp al, 0
    je .done
    cmp al, 10              ; newline
    je .done
    call lexer_advance
    jmp .single_loop

.multiline:
    ; Skip opening !!!
    call lexer_advance
    call lexer_advance
    call lexer_advance
    ; Skip to closing !!!
.multi_loop:
    call lexer_peek
    cmp al, 0
    je .done                 ; EOF — unclosed comment (lenient)
    cmp al, '!'
    jne .multi_advance
    ; Check for !!!
    mov rdi, 1
    call lexer_peek_at
    cmp al, '!'
    jne .multi_advance
    mov rdi, 2
    call lexer_peek_at
    cmp al, '!'
    jne .multi_advance
    ; Found closing !!!
    call lexer_advance
    call lexer_advance
    call lexer_advance
    jmp .done
.multi_advance:
    call lexer_advance
    jmp .multi_loop

.done:
    mov rax, 1               ; was a comment
    pop rbp
    ret
.not_comment:
    xor rax, rax             ; not a comment
    pop rbp
    ret

; ============================================================
; scan_string — Scan string literal ("..." or '...' or """...""")
; Handles {expr} interpolation markers (stored as-is for parser)
; ============================================================
scan_string:
    push rbp
    mov rbp, rsp
    push r12
    push r13

    call lexer_peek
    mov r12b, al             ; quote character (' or ")

    ; Check for triple quote
    mov rdi, 1
    call lexer_peek_at
    cmp al, r12b
    jne .single_quote
    mov rdi, 2
    call lexer_peek_at
    cmp al, r12b
    jne .single_quote

    ; Triple quote — skip opening """
    call lexer_advance
    call lexer_advance
    call lexer_advance

    ; Record start position
    mov r13, [src_pos]

.triple_loop:
    call lexer_peek
    cmp al, 0
    je .emit_str             ; EOF
    cmp al, r12b
    jne .triple_next
    ; Check for closing triple
    mov rdi, 1
    call lexer_peek_at
    cmp al, r12b
    jne .triple_next
    mov rdi, 2
    call lexer_peek_at
    cmp al, r12b
    jne .triple_next
    ; Found closing """
    ; Calculate length before consuming closing quotes
    mov rcx, [src_pos]
    sub rcx, r13             ; length of string content
    call lexer_advance
    call lexer_advance
    call lexer_advance
    jmp .emit_str_with_len

.triple_next:
    call lexer_advance
    jmp .triple_loop

.single_quote:
    ; Skip opening quote
    call lexer_advance

    ; Record start position
    mov r13, [src_pos]

.string_loop:
    call lexer_peek
    cmp al, 0
    je .emit_str             ; EOF — unterminated
    cmp al, 10               ; newline — unterminated
    je .emit_str
    cmp al, '\\'
    je .escape
    cmp al, r12b             ; closing quote
    je .close_quote
    call lexer_advance
    jmp .string_loop

.escape:
    call lexer_advance       ; skip backslash
    call lexer_advance       ; skip escaped char
    jmp .string_loop

.close_quote:
    mov rcx, [src_pos]
    sub rcx, r13             ; length
    call lexer_advance       ; skip closing quote
    jmp .emit_str_with_len

.emit_str:
    mov rcx, [src_pos]
    sub rcx, r13
.emit_str_with_len:
    ; Emit string token
    lea rdx, [src_buf + r13] ; pointer to string content
    mov dil, TOK_STRING
    xor sil, sil
    call emit_token

    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; scan_number — Scan integer or float literal
; Handles: decimal, hex (0x), binary (0b), float (with .)
; ============================================================
scan_number:
    push rbp
    mov rbp, rsp
    push r12
    push r13

    mov r12, [src_pos]       ; start position
    mov r13b, 0              ; is_float flag

    ; Check for 0x or 0b prefix
    call lexer_peek
    cmp al, '0'
    jne .decimal
    mov rdi, 1
    call lexer_peek_at
    cmp al, 'x'
    je .hex
    cmp al, 'X'
    je .hex
    cmp al, 'b'
    je .binary
    cmp al, 'B'
    je .binary

.decimal:
    call lexer_peek
    cmp al, '0'
    jb .check_dot
    cmp al, '9'
    ja .check_dot
    call lexer_advance
    jmp .decimal

.check_dot:
    cmp al, '.'
    jne .emit_num
    ; Check next char is digit (not method call like arr.len)
    mov rdi, 1
    call lexer_peek_at
    cmp al, '0'
    jb .emit_num
    cmp al, '9'
    ja .emit_num
    mov r13b, 1              ; is float
    call lexer_advance       ; consume .
.float_digits:
    call lexer_peek
    cmp al, '0'
    jb .emit_num
    cmp al, '9'
    ja .emit_num
    call lexer_advance
    jmp .float_digits

.hex:
    call lexer_advance       ; skip 0
    call lexer_advance       ; skip x
.hex_loop:
    call lexer_peek
    cmp al, '0'
    jb .emit_num
    cmp al, '9'
    jbe .hex_next
    cmp al, 'a'
    jb .check_upper_hex
    cmp al, 'f'
    jbe .hex_next
    jmp .emit_num
.check_upper_hex:
    cmp al, 'A'
    jb .emit_num
    cmp al, 'F'
    ja .emit_num
.hex_next:
    call lexer_advance
    jmp .hex_loop

.binary:
    call lexer_advance       ; skip 0
    call lexer_advance       ; skip b
.bin_loop:
    call lexer_peek
    cmp al, '0'
    je .bin_next
    cmp al, '1'
    je .bin_next
    jmp .emit_num
.bin_next:
    call lexer_advance
    jmp .bin_loop

.emit_num:
    mov rcx, [src_pos]
    sub rcx, r12             ; length
    lea rdx, [src_buf + r12] ; pointer
    cmp r13b, 0
    je .emit_int
    mov dil, TOK_FLOAT
    jmp .do_emit
.emit_int:
    mov dil, TOK_INT
.do_emit:
    xor sil, sil
    call emit_token

    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; scan_identifier — Scan identifier or keyword
; ============================================================
scan_identifier:
    push rbp
    mov rbp, rsp
    push r12
    push r13

    mov r12, [src_pos]       ; start position

.id_loop:
    call lexer_peek
    ; Check if alphanumeric or underscore
    cmp al, '_'
    je .id_next
    cmp al, 'a'
    jb .check_upper
    cmp al, 'z'
    jbe .id_next
    jmp .check_digit
.check_upper:
    cmp al, 'A'
    jb .check_digit
    cmp al, 'Z'
    jbe .id_next
.check_digit:
    cmp al, '0'
    jb .id_done
    cmp al, '9'
    ja .id_done
.id_next:
    call lexer_advance
    jmp .id_loop

.id_done:
    mov rcx, [src_pos]
    sub rcx, r12             ; length
    lea rdx, [src_buf + r12] ; pointer
    mov r13, rcx             ; save length

    ; Check if it's a keyword
    push rdx
    push rcx
    call is_keyword
    pop rcx
    pop rdx
    cmp rax, 1
    je .emit_keyword

    ; Regular identifier
    mov dil, TOK_IDENT
    xor sil, sil
    call emit_token
    jmp .done

.emit_keyword:
    mov dil, TOK_KEYWORD
    xor sil, sil
    mov rcx, r13
    call emit_token

.done:
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; is_keyword — Check if string (rdx, rcx) is a keyword
; Returns: rax = 1 if keyword, 0 if not
; ============================================================
is_keyword:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14

    mov r12, rdx             ; string pointer
    mov r13, rcx             ; string length

    lea r14, [kw_ptrs]
.check_loop:
    mov rdi, [r14]           ; keyword pointer
    cmp rdi, 0
    je .not_keyword          ; end of table
    mov rsi, [r14 + 8]      ; keyword length
    cmp rsi, r13
    jne .next                ; length mismatch

    ; Compare strings
    push rcx
    mov rcx, r13
    push r12
    push rdi
.cmp_loop:
    cmp rcx, 0
    je .match
    movzx eax, byte [r12]
    cmp al, [rdi]
    jne .no_match
    inc r12
    inc rdi
    dec rcx
    jmp .cmp_loop

.match:
    pop rdi
    pop r12
    pop rcx
    mov rax, 1
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

.no_match:
    pop rdi
    pop r12
    pop rcx
.next:
    add r14, 16              ; next entry (8 bytes ptr + 8 bytes len)
    jmp .check_loop

.not_keyword:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ============================================================
; scan_operator — Scan single or multi-character operator
; ============================================================
scan_operator:
    push rbp
    mov rbp, rsp

    mov r8, [src_pos]        ; start position
    call lexer_peek
    mov cl, al               ; save first char

    ; Two-character operators
    mov rdi, 1
    call lexer_peek_at
    mov dl, al               ; second char

    ; Check ** (power)
    cmp cl, '*'
    jne .not_dstar
    cmp dl, '*'
    jne .not_dstar
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_DSTAR
    call emit_token
    jmp .done

.not_dstar:
    ; Check // (integer division)
    cmp cl, '/'
    jne .not_dslash
    cmp dl, '/'
    jne .not_dslash
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_DSLASH
    call emit_token
    jmp .done

.not_dslash:
    ; Check == != <= >=
    cmp cl, '='
    jne .not_eq
    cmp dl, '='
    jne .single_eq
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_EQ
    call emit_token
    jmp .done
.single_eq:
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_OP
    mov sil, OP_ASSIGN
    call emit_token
    jmp .done

.not_eq:
    cmp cl, '!'
    jne .not_neq
    cmp dl, '='
    jne .done_notoken        ; lone ! is not valid
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_NEQ
    call emit_token
    jmp .done

.not_neq:
    cmp cl, '<'
    jne .not_lt
    cmp dl, '='
    jne .check_lshift
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_LTE
    call emit_token
    jmp .done
.check_lshift:
    cmp dl, '<'
    jne .single_lt
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_LSHIFT
    call emit_token
    jmp .done
.single_lt:
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_OP
    mov sil, OP_LT
    call emit_token
    jmp .done

.not_lt:
    cmp cl, '>'
    jne .not_gt
    cmp dl, '='
    jne .check_rshift
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_GTE
    call emit_token
    jmp .done
.check_rshift:
    cmp dl, '>'
    jne .single_gt
    call lexer_advance
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 2
    mov dil, TOK_OP
    mov sil, OP_RSHIFT
    call emit_token
    jmp .done
.single_gt:
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_OP
    mov sil, OP_GT
    call emit_token
    jmp .done

.not_gt:
    ; Single character operators — save cl before rcx is overwritten
    movzx r9d, cl           ; r9b = current character
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_OP

    cmp r9b, '+'
    jne .not_plus
    mov sil, OP_PLUS
    jmp .emit_single
.not_plus:
    cmp r9b, '-'
    jne .not_minus
    mov sil, OP_MINUS
    jmp .emit_single
.not_minus:
    cmp r9b, '*'
    jne .not_star
    mov sil, OP_STAR
    jmp .emit_single
.not_star:
    cmp r9b, '/'
    jne .not_slash
    mov sil, OP_SLASH
    jmp .emit_single
.not_slash:
    cmp r9b, '%'
    jne .not_pct
    mov sil, OP_PERCENT
    jmp .emit_single
.not_pct:
    cmp r9b, '&'
    jne .not_amp
    mov sil, OP_AMP
    jmp .emit_single
.not_amp:
    cmp r9b, '|'
    jne .not_pipe
    mov sil, OP_PIPE
    jmp .emit_single
.not_pipe:
    cmp r9b, '^'
    jne .not_caret
    mov sil, OP_CARET
    jmp .emit_single
.not_caret:
    cmp r9b, '~'
    jne .done_notoken
    mov sil, OP_TILDE

.emit_single:
    call emit_token
    jmp .done

.done_notoken:
.done:
    pop rbp
    ret

; ============================================================
; lexer_tokenize — Main tokenization loop
; Call after lexer_load_file and lexer_init
; ============================================================
global lexer_tokenize
lexer_tokenize:
    push rbp
    mov rbp, rsp

.main_loop:
    ; Skip whitespace (not newlines)
    call skip_whitespace

    ; Peek current character
    call lexer_peek
    cmp al, 0
    je .eof

    ; Newline
    cmp al, 10
    je .newline

    ; Comment (!! or !!!)
    cmp al, '!'
    jne .not_comment
    call scan_comment
    cmp rax, 1
    je .main_loop
.not_comment:

    ; String
    call lexer_peek
    cmp al, '"'
    je .string
    cmp al, 39              ; single quote '
    je .string
    jmp .not_string
.string:
    call scan_string
    jmp .main_loop
.not_string:

    ; Number
    call lexer_peek
    cmp al, '0'
    jb .not_number
    cmp al, '9'
    ja .not_number
    call scan_number
    jmp .main_loop
.not_number:

    ; Identifier or keyword (starts with letter or _)
    call lexer_peek
    cmp al, '_'
    je .identifier
    cmp al, 'a'
    jb .check_upper_id
    cmp al, 'z'
    jbe .identifier
.check_upper_id:
    cmp al, 'A'
    jb .not_identifier
    cmp al, 'Z'
    jbe .identifier
    jmp .not_identifier
.identifier:
    call scan_identifier
    jmp .main_loop
.not_identifier:

    ; Punctuation
    call lexer_peek
    cmp al, '('
    je .punct
    cmp al, ')'
    je .punct
    cmp al, '['
    je .punct
    cmp al, ']'
    je .punct
    cmp al, ','
    je .comma
    cmp al, '.'
    je .dot
    jmp .not_punct

.punct:
    mov r8, [src_pos]
    mov cl, al
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_PUNCT
    ; Determine subtype
    cmp byte [src_buf + r8], '('
    jne .p1
    mov sil, PUNCT_LPAREN
    jmp .emit_punct
.p1:
    cmp byte [src_buf + r8], ')'
    jne .p2
    mov sil, PUNCT_RPAREN
    jmp .emit_punct
.p2:
    cmp byte [src_buf + r8], '['
    jne .p3
    mov sil, PUNCT_LBRACKET
    jmp .emit_punct
.p3:
    mov sil, PUNCT_RBRACKET
.emit_punct:
    call emit_token
    jmp .main_loop

.comma:
    mov r8, [src_pos]
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_PUNCT
    mov sil, PUNCT_COMMA
    call emit_token
    jmp .main_loop

.dot:
    mov r8, [src_pos]
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_DOT
    xor sil, sil
    call emit_token
    jmp .main_loop
.not_punct:

    ; Operators
    call lexer_peek
    cmp al, '+'
    je .operator
    cmp al, '-'
    je .operator
    cmp al, '*'
    je .operator
    cmp al, '/'
    je .operator
    cmp al, '%'
    je .operator
    cmp al, '='
    je .operator
    cmp al, '<'
    je .operator
    cmp al, '>'
    je .operator
    cmp al, '!'
    je .operator
    cmp al, '&'
    je .operator
    cmp al, '|'
    je .operator
    cmp al, '^'
    je .operator
    cmp al, '~'
    je .operator
    jmp .unexpected

.operator:
    call scan_operator
    jmp .main_loop

.newline:
    mov r8, [src_pos]
    call lexer_advance
    lea rdx, [src_buf + r8]
    mov rcx, 1
    mov dil, TOK_NEWLINE
    xor sil, sil
    call emit_token
    jmp .main_loop

.unexpected:
    ; Skip unexpected character
    call lexer_advance
    jmp .main_loop

.eof:
    ; Emit EOF token
    xor rdx, rdx
    xor rcx, rcx
    mov dil, TOK_EOF
    xor sil, sil
    call emit_token

    pop rbp
    ret

; ============================================================
; Token access functions for the parser
; ============================================================

; lexer_get_token — Get token at index rdi
; Returns: pointer to token in rax (16-byte struct)
global lexer_get_token
lexer_get_token:
    shl rdi, 4
    lea rax, [tok_buf + rdi]
    ret

; lexer_token_count — Returns token count in rax
global lexer_token_count
lexer_token_count:
    mov rax, [tok_count]
    ret

; lexer_get_mode — Returns current mode in al (0=hybrid, 1=natural)
global lexer_get_mode
lexer_get_mode:
    movzx eax, byte [current_mode]
    ret

; lexer_set_mode — Set mode from al
global lexer_set_mode
lexer_set_mode:
    mov [current_mode], al
    ret

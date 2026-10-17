; ============================================================
; SEVEN Language - Parser (AST Builder)
; Phase 1: Bootstrap Compiler
; Architecture: x86-64 NASM Assembly (Linux ELF64)
; Author: Tejas Chandivakar
; ============================================================
;
; Consumes token stream from lexer, builds AST nodes.
; Grammar: No ':' blocks. 'end' closes all blocks.
; Supports mode hybrid/natural.
;
; AST Node format (32 bytes):
;   [type:1][subtype:1][child_count:2][padding:4]
;   [left:8]           ; left child / data pointer
;   [right:8]          ; right child / second operand
;   [extra:8]          ; third child / extra data
; ============================================================

section .data
    ; ---- AST Node types ----
    AST_PROGRAM     equ 1
    AST_ASSIGN      equ 2
    AST_SHOW        equ 3
    AST_SHOW_RAW    equ 4
    AST_ERR         equ 5
    AST_ASK         equ 6
    AST_SECRET      equ 7
    AST_IF          equ 8
    AST_ELIF        equ 9
    AST_ELSE        equ 10
    AST_REPEAT      equ 11
    AST_WHILE       equ 12
    AST_EACH        equ 13
    AST_FUNC        equ 14
    AST_RETURN      equ 15
    AST_CALL        equ 16
    AST_BINOP       equ 17
    AST_UNARY       equ 18
    AST_INT_LIT     equ 19
    AST_FLOAT_LIT   equ 20
    AST_STR_LIT     equ 21
    AST_IDENT       equ 22
    AST_BOOL_LIT    equ 23
    AST_NULL_LIT    equ 24
    AST_ARRAY_LIT   equ 25
    AST_INDEX       equ 26
    AST_MEMBER      equ 27
    AST_METHOD      equ 28
    AST_BLOCK       equ 29
    AST_CLASS       equ 30
    AST_ERROR       equ 31
    AST_TRY         equ 32
    AST_WRITE       equ 33
    AST_READ        equ 34
    AST_IMPORT      equ 35
    AST_CONST       equ 36
    AST_NATURAL_CMD equ 37  ; mode natural array commands
    AST_EXPR_LIST   equ 38
    AST_PARAM       equ 39
    AST_SKIP        equ 40
    AST_STOP        equ 41

    ; ---- Token types (must match lexer) ----
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

    ; Punct subtypes
    PUNCT_LPAREN   equ 1
    PUNCT_RPAREN   equ 2
    PUNCT_LBRACKET equ 3
    PUNCT_RBRACKET equ 4
    PUNCT_COMMA    equ 5

    ; ---- Error messages ----
    parse_err_expect db "Parse error: unexpected token at line ", 0
    parse_err_expect_len equ $ - parse_err_expect

section .bss
    ; Parser state
    par_pos     resq 1      ; current token index
    par_line    resq 1      ; current line for errors

    ; AST node pool (bump allocated)
    ast_pool    resb 524288  ; 512KB for AST nodes
    ast_ptr     resq 1       ; next free position in pool

    ; Statement list for blocks (pointers to AST nodes)
    stmt_list   resq 4096    ; max 4096 statements
    stmt_count  resq 1

    ; Param list for functions
    param_list  resq 256
    param_count resq 1

    ; Arg list for calls
    arg_list    resq 256
    arg_count   resq 1

    ; Expr list for show/err
    expr_list_buf resq 256
    expr_list_count resq 1

section .text

; ============================================================
; ast_alloc — Allocate a 32-byte AST node
; Returns: rax = pointer to new node
; ============================================================
ast_alloc:
    mov rax, [ast_ptr]
    add qword [ast_ptr], 32
    ; Zero it out
    mov qword [rax], 0
    mov qword [rax + 8], 0
    mov qword [rax + 16], 0
    mov qword [rax + 24], 0
    ret

; ============================================================
; parser_init — Initialize parser state
; ============================================================
global parser_init
parser_init:
    mov qword [par_pos], 0
    mov qword [par_line], 1
    lea rax, [ast_pool]
    mov [ast_ptr], rax
    ret

; ============================================================
; peek — Get current token pointer without consuming
; Returns: rax = pointer to token (16-byte struct)
; ============================================================
peek:
    mov rdi, [par_pos]
    call lexer_get_token
    ret

; ============================================================
; advance — Consume current token and return it
; Returns: rax = pointer to consumed token
; ============================================================
advance:
    mov rdi, [par_pos]
    call lexer_get_token
    push rax
    ; Track newlines for line numbers
    movzx ecx, byte [rax]
    cmp cl, TOK_NEWLINE
    jne .not_nl
    inc qword [par_line]
.not_nl:
    inc qword [par_pos]
    pop rax
    ret

; ============================================================
; skip_newlines — Skip any newline tokens
; ============================================================
skip_newlines:
.loop:
    call peek
    movzx ecx, byte [rax]
    cmp cl, TOK_NEWLINE
    jne .done
    call advance
    jmp .loop
.done:
    ret

; ============================================================
; tok_is_keyword — Check if current token is a specific keyword
; rdi = keyword string, rsi = keyword length
; Returns: rax = 1 if match, 0 if not
; ============================================================
tok_is_keyword:
    push r12
    push r13
    mov r12, rdi             ; expected keyword
    mov r13, rsi             ; expected length

    call peek
    movzx ecx, byte [rax]
    cmp cl, TOK_KEYWORD
    jne .no
    ; Compare length
    mov ecx, [rax + 4]
    cmp rcx, r13
    jne .no
    ; Compare text
    mov rdi, [rax + 8]      ; token text pointer
    mov rsi, r12             ; expected text
    mov rcx, r13
.cmp:
    cmp rcx, 0
    je .yes
    movzx edx, byte [rdi]
    cmp dl, [rsi]
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
; tok_type — Get type of current token
; Returns: al = token type
; ============================================================
tok_type:
    call peek
    movzx eax, byte [rax]
    ret

; ============================================================
; tok_subtype — Get subtype of current token
; Returns: al = token subtype
; ============================================================
tok_subtype:
    call peek
    movzx eax, byte [rax + 1]
    ret

; ============================================================
; expect_keyword — Consume keyword or error
; rdi = keyword string, rsi = length
; ============================================================
expect_keyword:
    push rdi
    push rsi
    call tok_is_keyword
    pop rsi
    pop rdi
    cmp rax, 1
    jne .err
    call advance
    ret
.err:
    ; For now, just skip — proper error handling later
    call advance
    ret

; ============================================================
; parse_program — Top-level: parse all statements
; Returns: rax = AST_PROGRAM node
; ============================================================
global parse_program
parse_program:
    push rbp
    mov rbp, rsp
    push r12

    ; Check for mode declaration
    call skip_newlines
    lea rdi, [kw_mode]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    jne .no_mode
    call advance             ; consume 'mode'
    call skip_newlines
    ; Check hybrid or natural
    lea rdi, [kw_natural]
    mov rsi, 7
    call tok_is_keyword
    cmp rax, 1
    jne .check_hybrid
    mov al, 1
    call lexer_set_mode
    call advance
    jmp .no_mode
.check_hybrid:
    ; Default or explicit hybrid
    call advance             ; consume 'hybrid'
.no_mode:

    ; Parse statements
    mov qword [stmt_count], 0

.stmt_loop:
    call skip_newlines
    call tok_type
    cmp al, TOK_EOF
    je .done

    call parse_statement
    cmp rax, 0
    je .stmt_loop            ; null statement (empty line)

    ; Add to statement list
    mov rcx, [stmt_count]
    mov [stmt_list + rcx * 8], rax
    inc qword [stmt_count]
    jmp .stmt_loop

.done:
    ; Create program node
    call ast_alloc
    mov byte [rax], AST_PROGRAM
    mov rcx, [stmt_count]
    mov word [rax + 2], cx   ; child count
    ; Store pointer to stmt_list copy
    mov [rax + 8], rcx       ; statement count in left
    lea rdx, [stmt_list]
    mov [rax + 16], rdx      ; pointer to statement list

    pop r12
    pop rbp
    ret

; ============================================================
; parse_statement — Parse a single statement
; Returns: rax = AST node (or 0 for empty)
; ============================================================
global parse_statement
parse_statement:
    push rbp
    mov rbp, rsp

    call skip_newlines
    call tok_type
    cmp al, TOK_EOF
    je .null_stmt

    ; Check for keywords
    cmp al, TOK_KEYWORD
    je .keyword_stmt

    ; Check for identifier (could be assignment or expression)
    cmp al, TOK_IDENT
    je .ident_stmt

    ; Expression statement
    call parse_expression
    pop rbp
    ret

.null_stmt:
    xor rax, rax
    pop rbp
    ret

.keyword_stmt:
    ; Dispatch based on keyword
    lea rdi, [kw_show]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .parse_show

    lea rdi, [kw_err]
    mov rsi, 3
    call tok_is_keyword
    cmp rax, 1
    je .parse_err

    lea rdi, [kw_if]
    mov rsi, 2
    call tok_is_keyword
    cmp rax, 1
    je .parse_if

    lea rdi, [kw_repeat]
    mov rsi, 6
    call tok_is_keyword
    cmp rax, 1
    je .parse_repeat

    lea rdi, [kw_while]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    je .parse_while

    lea rdi, [kw_each]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .parse_each

    lea rdi, [kw_func]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .parse_func

    lea rdi, [kw_return]
    mov rsi, 6
    call tok_is_keyword
    cmp rax, 1
    je .parse_return

    lea rdi, [kw_class]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    je .parse_class

    lea rdi, [kw_try]
    mov rsi, 3
    call tok_is_keyword
    cmp rax, 1
    je .parse_try

    lea rdi, [kw_error]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    je .parse_error

    lea rdi, [kw_write]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    je .parse_write

    lea rdi, [kw_import]
    mov rsi, 6
    call tok_is_keyword
    cmp rax, 1
    je .parse_import

    lea rdi, [kw_const]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    je .parse_const

    lea rdi, [kw_skip]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .parse_skip

    lea rdi, [kw_stop]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .parse_stop

    ; Unknown keyword — treat as expression
    call parse_expression
    pop rbp
    ret

.ident_stmt:
    ; Could be assignment (x = ...) or expression (func_call())
    ; Peek ahead for '='
    call peek
    mov r8, [rax + 8]       ; save ident pointer
    mov r9d, [rax + 4]      ; save ident length

    ; Save position
    mov r10, [par_pos]
    call advance             ; consume identifier

    call skip_newlines
    call tok_type
    cmp al, TOK_OP
    jne .not_assign
    call tok_subtype
    cmp al, OP_ASSIGN
    jne .not_assign

    ; It's an assignment: ident = expr
    call advance             ; consume '='

    ; Check for 'ask' or 'secret' on RHS
    lea rdi, [kw_ask]
    mov rsi, 3
    call tok_is_keyword
    cmp rax, 1
    je .parse_ask_assign

    lea rdi, [kw_secret]
    mov rsi, 6
    call tok_is_keyword
    cmp rax, 1
    je .parse_secret_assign

    lea rdi, [kw_read]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .parse_read_assign

    ; Regular assignment
    call parse_expression
    push rax                 ; save expr

    call ast_alloc
    mov byte [rax], AST_ASSIGN
    mov [rax + 8], r8       ; ident pointer
    mov [rax + 4], r9d      ; ident length (in length field)
    pop rdx
    mov [rax + 16], rdx     ; expression
    pop rbp
    ret

.parse_ask_assign:
    call advance             ; consume 'ask'
    call parse_expression    ; prompt string
    push rax

    call ast_alloc
    mov byte [rax], AST_ASK
    mov [rax + 8], r8       ; variable name pointer
    mov [rax + 4], r9d      ; variable name length
    pop rdx
    mov [rax + 16], rdx     ; prompt expression
    pop rbp
    ret

.parse_secret_assign:
    call advance             ; consume 'secret'
    call parse_expression    ; prompt string
    push rax

    call ast_alloc
    mov byte [rax], AST_SECRET
    mov [rax + 8], r8
    mov [rax + 4], r9d
    pop rdx
    mov [rax + 16], rdx
    pop rbp
    ret

.parse_read_assign:
    call advance             ; consume 'read'
    call parse_expression    ; filename
    push rax

    call ast_alloc
    mov byte [rax], AST_READ
    mov [rax + 8], r8
    mov [rax + 4], r9d
    pop rdx
    mov [rax + 16], rdx
    pop rbp
    ret

.not_assign:
    ; Backtrack — it was an expression starting with ident
    mov [par_pos], r10
    call parse_expression
    pop rbp
    ret

; ---- Keyword statement parsers ----

.parse_show:
    call advance             ; consume 'show'
    ; Check for .raw
    call tok_type
    cmp al, TOK_DOT
    jne .show_normal
    ; peek next for 'raw'
    call advance             ; consume '.'
    lea rdi, [rel kw_table]  ; we don't have kw_raw, just advance
    call advance             ; consume 'raw'

    ; Parse expression list
    call parse_expr_list
    call ast_alloc
    mov byte [rax], AST_SHOW_RAW
    mov rcx, [expr_list_count]
    mov [rax + 8], rcx
    lea rdx, [expr_list_buf]
    mov [rax + 16], rdx
    pop rbp
    ret

.show_normal:
    call parse_expr_list
    call ast_alloc
    mov byte [rax], AST_SHOW
    mov rcx, [expr_list_count]
    mov [rax + 8], rcx
    lea rdx, [expr_list_buf]
    mov [rax + 16], rdx
    pop rbp
    ret

.parse_err:
    call advance             ; consume 'err'
    call parse_expr_list
    call ast_alloc
    mov byte [rax], AST_ERR
    mov rcx, [expr_list_count]
    mov [rax + 8], rcx
    lea rdx, [expr_list_buf]
    mov [rax + 16], rdx
    pop rbp
    ret

.parse_if:
    call advance             ; consume 'if'
    call parse_expression    ; condition
    push rax

    ; Parse block until elif/else/end
    call parse_block_until_end

    call ast_alloc
    mov byte [rax], AST_IF
    pop rdx
    mov [rax + 8], rdx       ; condition
    lea rdx, [stmt_list]
    mov [rax + 16], rdx      ; block
    mov rcx, [stmt_count]
    mov [rax + 24], rcx      ; block size
    pop rbp
    ret

.parse_repeat:
    call advance             ; consume 'repeat'
    call parse_expression    ; count
    push rax

    ; Check for 'times' (optional)
    lea rdi, [kw_times]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    jne .no_times
    call advance
.no_times:

    ; Check for 'as' (loop variable)
    lea rdi, [kw_as]
    mov rsi, 2
    call tok_is_keyword
    cmp rax, 1
    jne .no_repeat_var
    call advance             ; consume 'as'
    call advance             ; consume identifier (loop var)
    push rax                 ; save var token
    jmp .repeat_block
.no_repeat_var:
    push qword 0             ; no loop variable
.repeat_block:
    call parse_block_until_end

    call ast_alloc
    mov byte [rax], AST_REPEAT
    pop rdx                  ; loop var (or 0)
    mov [rax + 24], rdx
    pop rdx                  ; count expression
    mov [rax + 8], rdx
    mov rcx, [stmt_count]
    mov [rax + 16], rcx      ; block stmt count
    pop rbp
    ret

.parse_while:
    call advance             ; consume 'while'
    call parse_expression    ; condition
    push rax
    call parse_block_until_end
    call ast_alloc
    mov byte [rax], AST_WHILE
    pop rdx
    mov [rax + 8], rdx       ; condition
    mov rcx, [stmt_count]
    mov [rax + 16], rcx
    pop rbp
    ret

.parse_each:
    call advance             ; consume 'each'
    call advance             ; consume collection ident
    push rax                 ; save collection token
    ; Expect 'as'
    lea rdi, [kw_as]
    mov rsi, 2
    call expect_keyword
    ; First variable (index or value)
    call advance
    push rax                 ; var1 token
    ; Check for comma (second variable)
    call tok_type
    cmp al, TOK_PUNCT
    jne .each_no_comma
    call tok_subtype
    cmp al, PUNCT_COMMA
    jne .each_no_comma
    call advance             ; consume ','
    call advance             ; var2 token
    push rax                 ; var2
    jmp .each_block
.each_no_comma:
    push qword 0            ; no second var
.each_block:
    call parse_block_until_end
    call ast_alloc
    mov byte [rax], AST_EACH
    pop rdx                  ; var2 (or 0)
    mov [rax + 24], rdx
    pop rdx                  ; var1
    mov [rax + 16], rdx
    pop rdx                  ; collection
    mov [rax + 8], rdx
    pop rbp
    ret

.parse_func:
    call advance             ; consume 'func'
    call advance             ; function name token
    push rax                 ; save name

    ; Expect '('
    call advance             ; consume '('

    ; Parse params
    mov qword [param_count], 0
.param_loop:
    call tok_type
    cmp al, TOK_PUNCT
    jne .param_next
    call tok_subtype
    cmp al, PUNCT_RPAREN
    je .param_done
    cmp al, PUNCT_COMMA
    jne .param_next
    call advance             ; skip comma
.param_next:
    call tok_type
    cmp al, TOK_PUNCT
    je .param_done
    ; Check for 'many' keyword
    lea rdi, [kw_many]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    jne .regular_param
    call advance             ; consume 'many'
.regular_param:
    call advance             ; param name
    mov rcx, [param_count]
    mov [param_list + rcx * 8], rax
    inc qword [param_count]

    ; Check for default value
    call tok_type
    cmp al, TOK_OP
    jne .param_loop
    call tok_subtype
    cmp al, OP_ASSIGN
    jne .param_loop
    call advance             ; consume '='
    call parse_expression    ; default value (discarded for now)
    jmp .param_loop

.param_done:
    call advance             ; consume ')'
    call parse_block_until_end

    call ast_alloc
    mov byte [rax], AST_FUNC
    pop rdx                  ; function name
    mov [rax + 8], rdx
    mov rcx, [stmt_count]
    mov [rax + 16], rcx      ; body stmt count
    mov rcx, [param_count]
    mov [rax + 24], rcx      ; param count
    pop rbp
    ret

.parse_return:
    call advance             ; consume 'return'
    ; Check if there's an expression on the same line
    call tok_type
    cmp al, TOK_NEWLINE
    je .empty_return
    cmp al, TOK_EOF
    je .empty_return
    call parse_expression
    push rax
    call ast_alloc
    mov byte [rax], AST_RETURN
    pop rdx
    mov [rax + 8], rdx
    pop rbp
    ret
.empty_return:
    call ast_alloc
    mov byte [rax], AST_RETURN
    pop rbp
    ret

.parse_class:
    call advance             ; consume 'class'
    call advance             ; class name
    push rax
    ; Check for 'extends'
    lea rdi, [kw_extends]
    mov rsi, 7
    call tok_is_keyword
    cmp rax, 1
    jne .no_extends
    call advance             ; consume 'extends'
    call advance             ; parent class name
    push rax
    jmp .class_body
.no_extends:
    push qword 0
.class_body:
    call parse_block_until_end
    call ast_alloc
    mov byte [rax], AST_CLASS
    pop rdx                  ; parent (or 0)
    mov [rax + 24], rdx
    pop rdx                  ; class name
    mov [rax + 8], rdx
    mov rcx, [stmt_count]
    mov [rax + 16], rcx
    pop rbp
    ret

.parse_try:
    call advance             ; consume 'try'
    call parse_block_until_end
    call ast_alloc
    mov byte [rax], AST_TRY
    mov rcx, [stmt_count]
    mov [rax + 8], rcx
    pop rbp
    ret

.parse_error:
    call advance             ; consume 'error'
    call parse_expression
    push rax
    call ast_alloc
    mov byte [rax], AST_ERROR
    pop rdx
    mov [rax + 8], rdx
    pop rbp
    ret

.parse_write:
    call advance             ; consume 'write'
    call parse_expression    ; filename
    push rax
    ; Expect comma
    call tok_type
    cmp al, TOK_PUNCT
    jne .write_done
    call advance             ; consume ','
    call parse_expression    ; data
    push rax
    call ast_alloc
    mov byte [rax], AST_WRITE
    pop rdx
    mov [rax + 16], rdx      ; data
    pop rdx
    mov [rax + 8], rdx       ; filename
    pop rbp
    ret
.write_done:
    call ast_alloc
    mov byte [rax], AST_WRITE
    pop rdx
    mov [rax + 8], rdx
    pop rbp
    ret

.parse_import:
    call advance             ; consume 'import'
    call advance             ; module name
    push rax
    call ast_alloc
    mov byte [rax], AST_IMPORT
    pop rdx
    mov [rax + 8], rdx
    pop rbp
    ret

.parse_const:
    call advance             ; consume 'const'
    ; Similar to assign but const
    call advance             ; ident
    push rax
    ; Expect '='
    call advance
    call parse_expression
    push rax
    call ast_alloc
    mov byte [rax], AST_CONST
    pop rdx
    mov [rax + 16], rdx      ; value
    pop rdx
    mov [rax + 8], rdx       ; name
    pop rbp
    ret

.parse_skip:
    call advance
    call ast_alloc
    mov byte [rax], AST_SKIP
    pop rbp
    ret

.parse_stop:
    call advance
    call ast_alloc
    mov byte [rax], AST_STOP
    pop rbp
    ret

; ============================================================
; parse_block_until_end — Parse statements until 'end', 'elif', 'else', 'catch', 'done'
; Stores results in stmt_list/stmt_count
; Consumes the 'end' token
; ============================================================
parse_block_until_end:
    push rbp
    mov rbp, rsp

    mov qword [stmt_count], 0

.loop:
    call skip_newlines
    call tok_type
    cmp al, TOK_EOF
    je .done

    ; Check for block terminators
    lea rdi, [kw_end]
    mov rsi, 3
    call tok_is_keyword
    cmp rax, 1
    je .consume_end

    lea rdi, [kw_elif]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .done                 ; don't consume elif

    lea rdi, [kw_else]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .done

    lea rdi, [kw_catch]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    je .done

    lea rdi, [kw_done]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .done

    ; Parse statement
    call parse_statement
    cmp rax, 0
    je .loop
    mov rcx, [stmt_count]
    mov [stmt_list + rcx * 8], rax
    inc qword [stmt_count]
    jmp .loop

.consume_end:
    call advance             ; consume 'end'
.done:
    pop rbp
    ret

; ============================================================
; parse_expr_list — Parse comma-separated expressions
; Results in expr_list_buf/expr_list_count
; ============================================================
parse_expr_list:
    push rbp
    mov rbp, rsp

    mov qword [expr_list_count], 0

    call parse_expression
    mov rcx, [expr_list_count]
    mov [expr_list_buf + rcx * 8], rax
    inc qword [expr_list_count]

.loop:
    call tok_type
    cmp al, TOK_PUNCT
    jne .done
    call tok_subtype
    cmp al, PUNCT_COMMA
    jne .done
    call advance             ; consume ','
    call parse_expression
    mov rcx, [expr_list_count]
    mov [expr_list_buf + rcx * 8], rax
    inc qword [expr_list_count]
    jmp .loop

.done:
    pop rbp
    ret

; ============================================================
; parse_expression — Parse expression with precedence climbing
; Handles: logic > compare > add > mul > unary > power > primary
; ============================================================
global parse_expression
parse_expression:
    call parse_logic
    ret

parse_logic:
    push rbp
    mov rbp, rsp

    call parse_compare
    push rax

.loop:
    lea rdi, [kw_and]
    mov rsi, 3
    call tok_is_keyword
    cmp rax, 1
    je .logic_op
    lea rdi, [kw_or]
    mov rsi, 2
    call tok_is_keyword
    cmp rax, 1
    je .logic_op
    pop rax
    pop rbp
    ret

.logic_op:
    call advance             ; consume and/or
    push rax                 ; save operator token
    call parse_compare
    ; Build binop node
    push rax                 ; right
    call ast_alloc
    mov byte [rax], AST_BINOP
    pop rdx
    mov [rax + 24], rdx      ; right
    pop rdx
    mov [rax + 16], rdx      ; operator
    pop rdx
    mov [rax + 8], rdx       ; left
    push rax
    jmp .loop

parse_compare:
    push rbp
    mov rbp, rsp

    call parse_add
    push rax

    ; Check for comparison operators
    call tok_type
    cmp al, TOK_OP
    jne .check_in
    call tok_subtype
    cmp al, OP_EQ
    je .cmp_op
    cmp al, OP_NEQ
    je .cmp_op
    cmp al, OP_LT
    je .cmp_op
    cmp al, OP_GT
    je .cmp_op
    cmp al, OP_LTE
    je .cmp_op
    cmp al, OP_GTE
    je .cmp_op
    jmp .done

.check_in:
    lea rdi, [kw_in]
    mov rsi, 2
    call tok_is_keyword
    cmp rax, 1
    je .cmp_op
    lea rdi, [kw_not]
    mov rsi, 3
    call tok_is_keyword
    cmp rax, 1
    jne .done
    ; "not in" — peek ahead
    ; TODO: proper not-in handling
    jmp .done

.cmp_op:
    call advance             ; consume operator
    push rax
    call parse_add
    push rax
    call ast_alloc
    mov byte [rax], AST_BINOP
    pop rdx
    mov [rax + 24], rdx      ; right
    pop rdx
    mov [rax + 16], rdx      ; operator
    pop rdx
    mov [rax + 8], rdx       ; left
    pop rbp
    ret

.done:
    pop rax
    pop rbp
    ret

parse_add:
    push rbp
    mov rbp, rsp

    call parse_mul
    push rax

.loop:
    call tok_type
    cmp al, TOK_OP
    jne .done
    call tok_subtype
    cmp al, OP_PLUS
    je .add_op
    cmp al, OP_MINUS
    je .add_op
    jmp .done

.add_op:
    call advance
    push rax
    call parse_mul
    push rax
    call ast_alloc
    mov byte [rax], AST_BINOP
    pop rdx
    mov [rax + 24], rdx
    pop rdx
    mov [rax + 16], rdx
    pop rdx
    mov [rax + 8], rdx
    push rax
    jmp .loop

.done:
    pop rax
    pop rbp
    ret

parse_mul:
    push rbp
    mov rbp, rsp

    call parse_unary
    push rax

.loop:
    call tok_type
    cmp al, TOK_OP
    jne .done
    call tok_subtype
    cmp al, OP_STAR
    je .mul_op
    cmp al, OP_SLASH
    je .mul_op
    cmp al, OP_DSLASH
    je .mul_op
    cmp al, OP_PERCENT
    je .mul_op
    jmp .done

.mul_op:
    call advance
    push rax
    call parse_unary
    push rax
    call ast_alloc
    mov byte [rax], AST_BINOP
    pop rdx
    mov [rax + 24], rdx
    pop rdx
    mov [rax + 16], rdx
    pop rdx
    mov [rax + 8], rdx
    push rax
    jmp .loop

.done:
    pop rax
    pop rbp
    ret

parse_unary:
    push rbp
    mov rbp, rsp

    call tok_type
    cmp al, TOK_OP
    jne .check_not
    call tok_subtype
    cmp al, OP_MINUS
    jne .no_unary
    call advance
    push rax
    call parse_power
    push rax
    call ast_alloc
    mov byte [rax], AST_UNARY
    pop rdx
    mov [rax + 8], rdx       ; operand
    pop rdx
    mov [rax + 16], rdx      ; operator
    pop rbp
    ret

.check_not:
    lea rdi, [kw_not]
    mov rsi, 3
    call tok_is_keyword
    cmp rax, 1
    jne .no_unary
    call advance
    push rax
    call parse_power
    push rax
    call ast_alloc
    mov byte [rax], AST_UNARY
    pop rdx
    mov [rax + 8], rdx
    pop rdx
    mov [rax + 16], rdx
    pop rbp
    ret

.no_unary:
    call parse_power
    pop rbp
    ret

parse_power:
    push rbp
    mov rbp, rsp

    call parse_primary
    push rax

    call tok_type
    cmp al, TOK_OP
    jne .done
    call tok_subtype
    cmp al, OP_DSTAR
    jne .done
    call advance
    push rax
    call parse_unary         ; right-associative
    push rax
    call ast_alloc
    mov byte [rax], AST_BINOP
    pop rdx
    mov [rax + 24], rdx
    pop rdx
    mov [rax + 16], rdx
    pop rdx
    mov [rax + 8], rdx
    pop rbp
    ret

.done:
    pop rax
    pop rbp
    ret

; ============================================================
; parse_primary — Parse primary expression
; ============================================================
parse_primary:
    push rbp
    mov rbp, rsp

    call tok_type

    cmp al, TOK_INT
    je .int_lit
    cmp al, TOK_FLOAT
    je .float_lit
    cmp al, TOK_STRING
    je .str_lit
    cmp al, TOK_IDENT
    je .ident
    cmp al, TOK_KEYWORD
    je .keyword_primary

    ; Parenthesized expression
    cmp al, TOK_PUNCT
    jne .array_check
    call tok_subtype
    cmp al, PUNCT_LPAREN
    jne .array_check
    call advance             ; consume '('
    call parse_expression
    push rax
    call advance             ; consume ')'
    pop rax
    jmp .check_postfix

.array_check:
    call tok_subtype
    cmp al, PUNCT_LBRACKET
    jne .error
    jmp .array_lit

.int_lit:
    call advance
    push rax
    call ast_alloc
    mov byte [rax], AST_INT_LIT
    pop rdx
    mov [rax + 8], rdx       ; token pointer (has text + length)
    jmp .check_postfix

.float_lit:
    call advance
    push rax
    call ast_alloc
    mov byte [rax], AST_FLOAT_LIT
    pop rdx
    mov [rax + 8], rdx
    jmp .check_postfix

.str_lit:
    call advance
    push rax
    call ast_alloc
    mov byte [rax], AST_STR_LIT
    pop rdx
    mov [rax + 8], rdx
    jmp .check_postfix

.ident:
    call advance
    push rax

    ; Check for function call: ident(
    call tok_type
    cmp al, TOK_PUNCT
    jne .plain_ident
    call tok_subtype
    cmp al, PUNCT_LPAREN
    jne .plain_ident

    ; Function call
    call advance             ; consume '('
    mov qword [arg_count], 0
.arg_loop:
    call tok_type
    cmp al, TOK_PUNCT
    jne .parse_arg
    call tok_subtype
    cmp al, PUNCT_RPAREN
    je .args_done
.parse_arg:
    call parse_expression
    mov rcx, [arg_count]
    mov [arg_list + rcx * 8], rax
    inc qword [arg_count]
    ; Check for comma
    call tok_type
    cmp al, TOK_PUNCT
    jne .args_done
    call tok_subtype
    cmp al, PUNCT_COMMA
    jne .args_done
    call advance             ; consume ','
    jmp .arg_loop
.args_done:
    call advance             ; consume ')'

    call ast_alloc
    mov byte [rax], AST_CALL
    pop rdx
    mov [rax + 8], rdx       ; function name token
    mov rcx, [arg_count]
    mov [rax + 16], rcx      ; arg count
    lea rdx, [arg_list]
    mov [rax + 24], rdx      ; arg list pointer
    jmp .check_postfix

.plain_ident:
    call ast_alloc
    mov byte [rax], AST_IDENT
    pop rdx
    mov [rax + 8], rdx
    jmp .check_postfix

.keyword_primary:
    ; true, false, null
    lea rdi, [kw_true]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .true_lit
    lea rdi, [kw_false]
    mov rsi, 5
    call tok_is_keyword
    cmp rax, 1
    je .false_lit
    lea rdi, [kw_null]
    mov rsi, 4
    call tok_is_keyword
    cmp rax, 1
    je .null_lit
    ; Otherwise error
    jmp .error

.true_lit:
    call advance
    call ast_alloc
    mov byte [rax], AST_BOOL_LIT
    mov qword [rax + 8], 1
    jmp .check_postfix

.false_lit:
    call advance
    call ast_alloc
    mov byte [rax], AST_BOOL_LIT
    mov qword [rax + 8], 0
    jmp .check_postfix

.null_lit:
    call advance
    call ast_alloc
    mov byte [rax], AST_NULL_LIT
    jmp .check_postfix

.array_lit:
    call advance             ; consume '['
    mov qword [arg_count], 0
.arr_loop:
    call tok_type
    cmp al, TOK_PUNCT
    jne .arr_elem
    call tok_subtype
    cmp al, PUNCT_RBRACKET
    je .arr_done
.arr_elem:
    call parse_expression
    mov rcx, [arg_count]
    mov [arg_list + rcx * 8], rax
    inc qword [arg_count]
    call tok_type
    cmp al, TOK_PUNCT
    jne .arr_done
    call tok_subtype
    cmp al, PUNCT_COMMA
    jne .arr_done
    call advance
    jmp .arr_loop
.arr_done:
    call advance             ; consume ']'
    call ast_alloc
    mov byte [rax], AST_ARRAY_LIT
    mov rcx, [arg_count]
    mov [rax + 8], rcx
    lea rdx, [arg_list]
    mov [rax + 16], rdx
    jmp .check_postfix

.error:
    ; Create a null literal as fallback
    call advance
    call ast_alloc
    mov byte [rax], AST_NULL_LIT

; ---- Postfix operators: .member, [index], .method() ----
.check_postfix:
    push rax                 ; save current node

.postfix_loop:
    call tok_type

    ; Check for [index]
    cmp al, TOK_PUNCT
    jne .check_dot
    call tok_subtype
    cmp al, PUNCT_LBRACKET
    jne .postfix_done
    call advance             ; consume '['
    call parse_expression
    push rax                 ; index expr
    call advance             ; consume ']'

    call ast_alloc
    mov byte [rax], AST_INDEX
    pop rdx
    mov [rax + 16], rdx      ; index
    pop rdx
    mov [rax + 8], rdx       ; object
    push rax
    jmp .postfix_loop

.check_dot:
    cmp al, TOK_DOT
    jne .postfix_done
    call advance             ; consume '.'
    call advance             ; consume member name
    push rax                 ; member token

    ; Check for method call: .member(
    call tok_type
    cmp al, TOK_PUNCT
    jne .plain_member
    call tok_subtype
    cmp al, PUNCT_LPAREN
    jne .plain_member

    ; Method call
    call advance             ; consume '('
    mov qword [arg_count], 0
.method_arg_loop:
    call tok_type
    cmp al, TOK_PUNCT
    jne .method_arg
    call tok_subtype
    cmp al, PUNCT_RPAREN
    je .method_args_done
.method_arg:
    call parse_expression
    mov rcx, [arg_count]
    mov [arg_list + rcx * 8], rax
    inc qword [arg_count]
    call tok_type
    cmp al, TOK_PUNCT
    jne .method_args_done
    call tok_subtype
    cmp al, PUNCT_COMMA
    jne .method_args_done
    call advance
    jmp .method_arg_loop
.method_args_done:
    call advance             ; consume ')'

    call ast_alloc
    mov byte [rax], AST_METHOD
    pop rdx
    mov [rax + 16], rdx      ; method name
    pop rdx
    mov [rax + 8], rdx       ; object
    mov rcx, [arg_count]
    mov [rax + 24], rcx      ; arg count
    push rax
    jmp .postfix_loop

.plain_member:
    call ast_alloc
    mov byte [rax], AST_MEMBER
    pop rdx
    mov [rax + 16], rdx      ; member name
    pop rdx
    mov [rax + 8], rdx       ; object
    push rax
    jmp .postfix_loop

.postfix_done:
    pop rax
    pop rbp
    ret

; External references (from lexer.asm)
extern lexer_get_token
extern lexer_token_count
extern lexer_get_mode
extern lexer_set_mode

; Keyword strings (from lexer.asm data)
extern kw_show, kw_ask, kw_err, kw_secret, kw_write, kw_read
extern kw_if, kw_elif, kw_else, kw_end, kw_func, kw_return
extern kw_repeat, kw_times, kw_while, kw_each, kw_as
extern kw_skip, kw_stop, kw_true, kw_false, kw_null
extern kw_and, kw_or, kw_not, kw_in
extern kw_try, kw_catch, kw_done, kw_error
extern kw_class, kw_extends, kw_this, kw_shared, kw_many
extern kw_const, kw_import, kw_from
extern kw_mode, kw_hybrid, kw_natural

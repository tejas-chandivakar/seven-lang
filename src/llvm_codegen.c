// ============================================================
// SEVEN Language — LLVM Code Generator Implementation
// Phase 13a: show (print), variables, math, if/while
// ============================================================

#include "llvm_codegen.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---- Forward declarations ----
static void compile_statement(SevenModule *mod);
static LLVMValueRef compile_expr(SevenModule *mod);
static void compile_show(SevenModule *mod);
static void compile_assignment(SevenModule *mod);
static void compile_if(SevenModule *mod);
static void compile_while(SevenModule *mod);
static void compile_repeat(SevenModule *mod);
static void compile_func_def(SevenModule *mod);
static void compile_func_call(SevenModule *mod, const char *name);
static void compile_assert(SevenModule *mod);

static void skip_newlines(SevenModule *mod) {
    while (lexer_peek(mod->lex)->type == TOK_NEWLINE)
        lexer_next(mod->lex);
}

// ---- Variable management ----
static VarInfo *find_var(SevenModule *mod, const char *name) {
    for (int i = mod->var_count - 1; i >= 0; i--) {
        if (strcmp(mod->vars[i].name, name) == 0)
            return &mod->vars[i];
    }
    return NULL;
}

static VarInfo *create_var(SevenModule *mod, const char *name, int is_string) {
    VarInfo *existing = find_var(mod, name);
    if (existing) return existing;

    VarInfo *v = &mod->vars[mod->var_count++];
    v->name = strdup(name);
    v->is_string = is_string;

    // Create alloca in entry block
    LLVMBasicBlockRef current_bb = LLVMGetInsertBlock(mod->builder);
    LLVMBasicBlockRef entry = LLVMGetEntryBasicBlock(mod->current_func);
    LLVMValueRef first_inst = LLVMGetFirstInstruction(entry);

    LLVMBuilderRef tmp = LLVMCreateBuilderInContext(mod->ctx);
    if (first_inst)
        LLVMPositionBuilderBefore(tmp, first_inst);
    else
        LLVMPositionBuilderAtEnd(tmp, entry);

    v->alloca = LLVMBuildAlloca(tmp, LLVMInt64TypeInContext(mod->ctx), name);
    LLVMDisposeBuilder(tmp);

    // Initialize to 0
    LLVMBuildStore(mod->builder, LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0), v->alloca);

    return v;
}

// ---- External function declarations ----
static void declare_externals(SevenModule *mod) {
    LLVMTypeRef i8ptr = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMTypeRef i32 = LLVMInt32TypeInContext(mod->ctx);
    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);

    // printf(const char *, ...) -> int
    LLVMTypeRef printf_args[] = { i8ptr };
    LLVMTypeRef printf_type = LLVMFunctionType(i32, printf_args, 1, 1); // variadic
    mod->fn_printf = LLVMAddFunction(mod->module, "printf", printf_type);

    // exit(int) -> void
    LLVMTypeRef exit_args[] = { i32 };
    LLVMTypeRef exit_type = LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), exit_args, 1, 0);
    mod->fn_exit = LLVMAddFunction(mod->module, "exit", exit_type);

    // Format strings
    mod->fmt_int_nl = LLVMBuildGlobalStringPtr(mod->builder, "%lld\n", "fmt_int_nl");
    mod->fmt_str_nl = LLVMBuildGlobalStringPtr(mod->builder, "%s\n", "fmt_str_nl");
    mod->fmt_int = LLVMBuildGlobalStringPtr(mod->builder, "%lld", "fmt_int");
    mod->fmt_str = LLVMBuildGlobalStringPtr(mod->builder, "%s", "fmt_str");
    mod->fmt_newline = LLVMBuildGlobalStringPtr(mod->builder, "\n", "fmt_nl");
}

// ---- Codegen init ----
void seven_codegen_init(SevenModule *mod, const char *name) {
    memset(mod, 0, sizeof(*mod));
    mod->ctx = LLVMContextCreate();
    mod->module = LLVMModuleCreateWithNameInContext(name, mod->ctx);
    mod->builder = LLVMCreateBuilderInContext(mod->ctx);
    mod->target_triple = NULL;
}

void seven_codegen_set_target(SevenModule *mod, const char *triple) {
    mod->target_triple = triple;
    LLVMSetTarget(mod->module, triple);
}

// ---- Expression compiler ----
// Returns LLVMValueRef (i64 for numbers, i8* for strings)

static LLVMValueRef compile_primary(SevenModule *mod) {
    Token *t = lexer_peek(mod->lex);

    switch (t->type) {
        case TOK_INT: {
            lexer_next(mod->lex);
            long long val = atoll(t->value);
            return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), val, 1);
        }

        case TOK_STRING: {
            lexer_next(mod->lex);
            return LLVMBuildGlobalStringPtr(mod->builder, t->value, "str");
        }

        case TOK_TRUE: {
            lexer_next(mod->lex);
            return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 1, 0);
        }

        case TOK_FALSE: {
            lexer_next(mod->lex);
            return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
        }

        case TOK_IDENT: {
            lexer_next(mod->lex);
            const char *name = t->value;

            // Check for function call: ident(
            if (lexer_peek(mod->lex)->type == TOK_LPAREN) {
                compile_func_call(mod, name);
                // Get the return value from the call
                LLVMBasicBlockRef bb = LLVMGetInsertBlock(mod->builder);
                LLVMValueRef last = LLVMGetLastInstruction(bb);
                return last;
            }

            VarInfo *v = find_var(mod, name);
            if (!v) {
                fprintf(stderr, "error: undefined variable '%s'\n", name);
                return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
            }
            return LLVMBuildLoad2(mod->builder, LLVMInt64TypeInContext(mod->ctx), v->alloca, name);
        }

        case TOK_LPAREN: {
            lexer_next(mod->lex); // skip (
            LLVMValueRef val = compile_expr(mod);
            lexer_expect(mod->lex, TOK_RPAREN);
            return val;
        }

        case TOK_NOT: {
            lexer_next(mod->lex);
            LLVMValueRef val = compile_primary(mod);
            LLVMValueRef zero = LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
            LLVMValueRef cmp = LLVMBuildICmp(mod->builder, LLVMIntEQ, val, zero, "not");
            return LLVMBuildZExt(mod->builder, cmp, LLVMInt64TypeInContext(mod->ctx), "not_ext");
        }

        case TOK_MINUS: {
            lexer_next(mod->lex);
            LLVMValueRef val = compile_primary(mod);
            return LLVMBuildNeg(mod->builder, val, "neg");
        }

        default:
            fprintf(stderr, "%s:%d: error: unexpected token %s\n",
                    mod->lex->filename, t->line, token_type_name(t->type));
            lexer_next(mod->lex);
            return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
    }
}

static LLVMValueRef compile_multiplicative(SevenModule *mod) {
    LLVMValueRef left = compile_primary(mod);

    while (1) {
        Token *t = lexer_peek(mod->lex);
        if (t->type == TOK_STAR) {
            lexer_next(mod->lex);
            LLVMValueRef right = compile_primary(mod);
            left = LLVMBuildMul(mod->builder, left, right, "mul");
        } else if (t->type == TOK_SLASH) {
            lexer_next(mod->lex);
            LLVMValueRef right = compile_primary(mod);
            left = LLVMBuildSDiv(mod->builder, left, right, "div");
        } else if (t->type == TOK_PERCENT) {
            lexer_next(mod->lex);
            LLVMValueRef right = compile_primary(mod);
            left = LLVMBuildSRem(mod->builder, left, right, "mod");
        } else {
            break;
        }
    }
    return left;
}

static LLVMValueRef compile_additive(SevenModule *mod) {
    LLVMValueRef left = compile_multiplicative(mod);

    while (1) {
        Token *t = lexer_peek(mod->lex);
        if (t->type == TOK_PLUS) {
            lexer_next(mod->lex);
            LLVMValueRef right = compile_multiplicative(mod);
            left = LLVMBuildAdd(mod->builder, left, right, "add");
        } else if (t->type == TOK_MINUS) {
            lexer_next(mod->lex);
            LLVMValueRef right = compile_multiplicative(mod);
            left = LLVMBuildSub(mod->builder, left, right, "sub");
        } else {
            break;
        }
    }
    return left;
}

static LLVMValueRef compile_comparison(SevenModule *mod) {
    LLVMValueRef left = compile_additive(mod);

    Token *t = lexer_peek(mod->lex);
    LLVMIntPredicate pred;
    int is_cmp = 1;

    switch (t->type) {
        case TOK_IS:      pred = LLVMIntEQ; break;
        case TOK_ISNT:    pred = LLVMIntNE; break;
        case TOK_ABOVE:   pred = LLVMIntSGT; break;
        case TOK_BELOW:   pred = LLVMIntSLT; break;
        case TOK_ATLEAST: pred = LLVMIntSGE; break;
        case TOK_ATMOST:  pred = LLVMIntSLE; break;
        default: is_cmp = 0; break;
    }

    if (is_cmp) {
        lexer_next(mod->lex);
        LLVMValueRef right = compile_additive(mod);
        LLVMValueRef cmp = LLVMBuildICmp(mod->builder, pred, left, right, "cmp");
        return LLVMBuildZExt(mod->builder, cmp, LLVMInt64TypeInContext(mod->ctx), "cmp_ext");
    }
    return left;
}

static LLVMValueRef compile_logical_and(SevenModule *mod) {
    LLVMValueRef left = compile_comparison(mod);

    while (lexer_peek(mod->lex)->type == TOK_AND) {
        lexer_next(mod->lex);
        LLVMValueRef right = compile_comparison(mod);
        LLVMValueRef zero = LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
        LLVMValueRef l = LLVMBuildICmp(mod->builder, LLVMIntNE, left, zero, "l_bool");
        LLVMValueRef r = LLVMBuildICmp(mod->builder, LLVMIntNE, right, zero, "r_bool");
        LLVMValueRef res = LLVMBuildAnd(mod->builder, l, r, "and");
        left = LLVMBuildZExt(mod->builder, res, LLVMInt64TypeInContext(mod->ctx), "and_ext");
    }
    return left;
}

static LLVMValueRef compile_expr(SevenModule *mod) {
    LLVMValueRef left = compile_logical_and(mod);

    while (lexer_peek(mod->lex)->type == TOK_OR) {
        lexer_next(mod->lex);
        LLVMValueRef right = compile_logical_and(mod);
        LLVMValueRef zero = LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
        LLVMValueRef l = LLVMBuildICmp(mod->builder, LLVMIntNE, left, zero, "l_bool");
        LLVMValueRef r = LLVMBuildICmp(mod->builder, LLVMIntNE, right, zero, "r_bool");
        LLVMValueRef res = LLVMBuildOr(mod->builder, l, r, "or");
        left = LLVMBuildZExt(mod->builder, res, LLVMInt64TypeInContext(mod->ctx), "or_ext");
    }
    return left;
}

// ---- Statement compilers ----

static void compile_show(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'show'

    Token *t = lexer_peek(mod->lex);

    if (t->type == TOK_STRING) {
        // show "string"
        LLVMValueRef str = compile_expr(mod);
        LLVMValueRef args[] = { mod->fmt_str_nl, str };
        LLVMBuildCall2(mod->builder,
            LLVMFunctionType(LLVMInt32TypeInContext(mod->ctx),
                (LLVMTypeRef[]){ LLVMPointerTypeInContext(mod->ctx, 0) }, 1, 1),
            mod->fn_printf, args, 2, "");
    } else {
        // show expression (integer)
        LLVMValueRef val = compile_expr(mod);

        // Check if it's a pointer (string) or integer
        if (LLVMGetTypeKind(LLVMTypeOf(val)) == LLVMPointerTypeKind) {
            LLVMValueRef args[] = { mod->fmt_str_nl, val };
            LLVMBuildCall2(mod->builder,
                LLVMFunctionType(LLVMInt32TypeInContext(mod->ctx),
                    (LLVMTypeRef[]){ LLVMPointerTypeInContext(mod->ctx, 0) }, 1, 1),
                mod->fn_printf, args, 2, "");
        } else {
            LLVMValueRef args[] = { mod->fmt_int_nl, val };
            LLVMBuildCall2(mod->builder,
                LLVMFunctionType(LLVMInt32TypeInContext(mod->ctx),
                    (LLVMTypeRef[]){ LLVMPointerTypeInContext(mod->ctx, 0) }, 1, 1),
                mod->fn_printf, args, 2, "");
        }
    }
}

static void compile_assignment(SevenModule *mod) {
    Token *name_tok = lexer_next(mod->lex); // identifier
    const char *name = name_tok->value;

    Token *op = lexer_peek(mod->lex);

    if (op->type == TOK_ASSIGN) {
        // x = expr
        lexer_next(mod->lex); // skip =
        LLVMValueRef val = compile_expr(mod);

        int is_str = (LLVMGetTypeKind(LLVMTypeOf(val)) == LLVMPointerTypeKind);
        VarInfo *v = create_var(mod, name, is_str);

        if (is_str) {
            // Store pointer as i64 (cast)
            LLVMValueRef cast = LLVMBuildPtrToInt(mod->builder, val,
                LLVMInt64TypeInContext(mod->ctx), "ptr2int");
            LLVMBuildStore(mod->builder, cast, v->alloca);
            v->is_string = 1;
        } else {
            LLVMBuildStore(mod->builder, val, v->alloca);
            v->is_string = 0;
        }
    }
}

static void compile_if(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'if'

    LLVMValueRef cond = compile_expr(mod);
    LLVMValueRef zero = LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
    LLVMValueRef cmp = LLVMBuildICmp(mod->builder, LLVMIntNE, cond, zero, "if_cond");

    LLVMBasicBlockRef then_bb = LLVMAppendBasicBlockInContext(mod->ctx, mod->current_func, "then");
    LLVMBasicBlockRef else_bb = LLVMCreateBasicBlockInContext(mod->ctx, "else");
    LLVMBasicBlockRef merge_bb = LLVMCreateBasicBlockInContext(mod->ctx, "endif");

    LLVMBuildCondBr(mod->builder, cmp, then_bb, else_bb);

    // Then block
    LLVMPositionBuilderAtEnd(mod->builder, then_bb);
    skip_newlines(mod);

    while (1) {
        Token *t = lexer_peek(mod->lex);
        if (t->type == TOK_END || t->type == TOK_ELSE || t->type == TOK_ELIF || t->type == TOK_EOF)
            break;
        compile_statement(mod);
        skip_newlines(mod);
    }

    if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(mod->builder)))
        LLVMBuildBr(mod->builder, merge_bb);

    Token *t = lexer_peek(mod->lex);

    if (t->type == TOK_ELIF) {
        LLVMAppendExistingBasicBlock(mod->current_func, else_bb);
        LLVMPositionBuilderAtEnd(mod->builder, else_bb);
        compile_if(mod); // recursive — elif is just nested if
        if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(mod->builder)))
            LLVMBuildBr(mod->builder, merge_bb);
    } else if (t->type == TOK_ELSE) {
        lexer_next(mod->lex); // skip 'else'
        skip_newlines(mod);

        LLVMAppendExistingBasicBlock(mod->current_func, else_bb);
        LLVMPositionBuilderAtEnd(mod->builder, else_bb);

        while (1) {
            Token *t2 = lexer_peek(mod->lex);
            if (t2->type == TOK_END || t2->type == TOK_EOF) break;
            compile_statement(mod);
            skip_newlines(mod);
        }

        if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(mod->builder)))
            LLVMBuildBr(mod->builder, merge_bb);

        lexer_expect(mod->lex, TOK_END); // skip 'end'
    } else {
        // No else — empty else block
        LLVMAppendExistingBasicBlock(mod->current_func, else_bb);
        LLVMPositionBuilderAtEnd(mod->builder, else_bb);
        LLVMBuildBr(mod->builder, merge_bb);

        lexer_expect(mod->lex, TOK_END);
    }

    LLVMAppendExistingBasicBlock(mod->current_func, merge_bb);
    LLVMPositionBuilderAtEnd(mod->builder, merge_bb);
}

static void compile_while(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'while'

    LLVMBasicBlockRef cond_bb = LLVMAppendBasicBlockInContext(mod->ctx, mod->current_func, "while_cond");
    LLVMBasicBlockRef body_bb = LLVMCreateBasicBlockInContext(mod->ctx, "while_body");
    LLVMBasicBlockRef exit_bb = LLVMCreateBasicBlockInContext(mod->ctx, "while_exit");

    LLVMBuildBr(mod->builder, cond_bb);
    LLVMPositionBuilderAtEnd(mod->builder, cond_bb);

    LLVMValueRef cond = compile_expr(mod);
    LLVMValueRef zero = LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
    LLVMValueRef cmp = LLVMBuildICmp(mod->builder, LLVMIntNE, cond, zero, "while_test");

    LLVMBuildCondBr(mod->builder, cmp, body_bb, exit_bb);

    // Body
    LLVMAppendExistingBasicBlock(mod->current_func, body_bb);
    LLVMPositionBuilderAtEnd(mod->builder, body_bb);
    skip_newlines(mod);

    while (1) {
        Token *t = lexer_peek(mod->lex);
        if (t->type == TOK_DONE || t->type == TOK_EOF) break;
        compile_statement(mod);
        skip_newlines(mod);
    }

    lexer_expect(mod->lex, TOK_DONE);

    if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(mod->builder)))
        LLVMBuildBr(mod->builder, cond_bb);

    LLVMAppendExistingBasicBlock(mod->current_func, exit_bb);
    LLVMPositionBuilderAtEnd(mod->builder, exit_bb);
}

static void compile_repeat(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'repeat'

    LLVMValueRef count = compile_expr(mod);

    // Create counter
    LLVMValueRef counter = LLVMBuildAlloca(mod->builder, LLVMInt64TypeInContext(mod->ctx), "rep_i");
    LLVMBuildStore(mod->builder, LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0), counter);

    LLVMBasicBlockRef cond_bb = LLVMAppendBasicBlockInContext(mod->ctx, mod->current_func, "rep_cond");
    LLVMBasicBlockRef body_bb = LLVMCreateBasicBlockInContext(mod->ctx, "rep_body");
    LLVMBasicBlockRef exit_bb = LLVMCreateBasicBlockInContext(mod->ctx, "rep_exit");

    LLVMBuildBr(mod->builder, cond_bb);
    LLVMPositionBuilderAtEnd(mod->builder, cond_bb);

    LLVMValueRef i = LLVMBuildLoad2(mod->builder, LLVMInt64TypeInContext(mod->ctx), counter, "i");
    LLVMValueRef cmp = LLVMBuildICmp(mod->builder, LLVMIntSLT, i, count, "rep_test");
    LLVMBuildCondBr(mod->builder, cmp, body_bb, exit_bb);

    LLVMAppendExistingBasicBlock(mod->current_func, body_bb);
    LLVMPositionBuilderAtEnd(mod->builder, body_bb);
    skip_newlines(mod);

    while (1) {
        Token *t = lexer_peek(mod->lex);
        if (t->type == TOK_DONE || t->type == TOK_EOF) break;
        compile_statement(mod);
        skip_newlines(mod);
    }

    lexer_expect(mod->lex, TOK_DONE);

    // Increment counter
    LLVMValueRef cur = LLVMBuildLoad2(mod->builder, LLVMInt64TypeInContext(mod->ctx), counter, "cur");
    LLVMValueRef next = LLVMBuildAdd(mod->builder, cur,
        LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 1, 0), "inc");
    LLVMBuildStore(mod->builder, next, counter);

    LLVMBuildBr(mod->builder, cond_bb);

    LLVMAppendExistingBasicBlock(mod->current_func, exit_bb);
    LLVMPositionBuilderAtEnd(mod->builder, exit_bb);
}

static void compile_func_def(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'func'

    Token *name_tok = lexer_expect(mod->lex, TOK_IDENT);
    const char *name = name_tok->value;

    lexer_expect(mod->lex, TOK_LPAREN);

    // Collect parameter names
    char *params[32];
    int param_count = 0;

    if (lexer_peek(mod->lex)->type != TOK_RPAREN) {
        params[param_count++] = strdup(lexer_expect(mod->lex, TOK_IDENT)->value);
        while (lexer_match(mod->lex, TOK_COMMA)) {
            params[param_count++] = strdup(lexer_expect(mod->lex, TOK_IDENT)->value);
        }
    }
    lexer_expect(mod->lex, TOK_RPAREN);

    // Create function type: all params i64, returns i64
    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
    LLVMTypeRef param_types[32];
    for (int i = 0; i < param_count; i++) param_types[i] = i64;
    LLVMTypeRef fn_type = LLVMFunctionType(i64, param_types, param_count, 0);
    LLVMValueRef func = LLVMAddFunction(mod->module, name, fn_type);

    // Save in function table
    FuncInfo *fi = &mod->funcs[mod->func_count++];
    fi->name = strdup(name);
    fi->func = func;
    fi->param_count = param_count;

    // Save current state
    LLVMValueRef prev_func = mod->current_func;
    int prev_var_count = mod->var_count;

    mod->current_func = func;

    // Create entry block
    LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(mod->ctx, func, "entry");
    LLVMPositionBuilderAtEnd(mod->builder, entry);

    // Create allocas for parameters
    for (int i = 0; i < param_count; i++) {
        VarInfo *v = create_var(mod, params[i], 0);
        LLVMBuildStore(mod->builder, LLVMGetParam(func, i), v->alloca);
        free(params[i]);
    }

    // Create 'result' variable
    create_var(mod, "result", 0);

    // Compile body
    skip_newlines(mod);
    while (1) {
        Token *t = lexer_peek(mod->lex);
        if (t->type == TOK_END || t->type == TOK_EOF) break;
        compile_statement(mod);
        skip_newlines(mod);
    }
    lexer_expect(mod->lex, TOK_END);

    // Return 'result' variable
    if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(mod->builder))) {
        VarInfo *rv = find_var(mod, "result");
        LLVMValueRef ret_val;
        if (rv)
            ret_val = LLVMBuildLoad2(mod->builder, i64, rv->alloca, "retval");
        else
            ret_val = LLVMConstInt(i64, 0, 0);
        LLVMBuildRet(mod->builder, ret_val);
    }

    // Restore state
    mod->current_func = prev_func;
    mod->var_count = prev_var_count;

    // Position builder back in main
    LLVMBasicBlockRef main_bb = LLVMGetLastBasicBlock(prev_func);
    LLVMPositionBuilderAtEnd(mod->builder, main_bb);
}

static void compile_func_call(SevenModule *mod, const char *name) {
    lexer_next(mod->lex); // skip (

    LLVMValueRef args[32];
    int arg_count = 0;

    if (lexer_peek(mod->lex)->type != TOK_RPAREN) {
        args[arg_count++] = compile_expr(mod);
        while (lexer_match(mod->lex, TOK_COMMA)) {
            args[arg_count++] = compile_expr(mod);
        }
    }
    lexer_expect(mod->lex, TOK_RPAREN);

    // Find function
    FuncInfo *fi = NULL;
    for (int i = 0; i < mod->func_count; i++) {
        if (strcmp(mod->funcs[i].name, name) == 0) {
            fi = &mod->funcs[i];
            break;
        }
    }

    if (!fi) {
        fprintf(stderr, "error: undefined function '%s'\n", name);
        return;
    }

    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
    LLVMTypeRef param_types[32];
    for (int i = 0; i < fi->param_count; i++) param_types[i] = i64;
    LLVMTypeRef fn_type = LLVMFunctionType(i64, param_types, fi->param_count, 0);

    LLVMBuildCall2(mod->builder, fn_type, fi->func, args, arg_count, "call");
}

static void compile_assert(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'assert'
    lexer_expect(mod->lex, TOK_LPAREN);

    LLVMValueRef cond = compile_expr(mod);

    // Check for message
    LLVMValueRef msg = NULL;
    if (lexer_match(mod->lex, TOK_COMMA)) {
        msg = compile_expr(mod);
    }
    lexer_expect(mod->lex, TOK_RPAREN);

    LLVMValueRef zero = LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
    LLVMValueRef cmp = LLVMBuildICmp(mod->builder, LLVMIntNE, cond, zero, "assert_test");

    LLVMBasicBlockRef fail_bb = LLVMAppendBasicBlockInContext(mod->ctx, mod->current_func, "assert_fail");
    LLVMBasicBlockRef ok_bb = LLVMCreateBasicBlockInContext(mod->ctx, "assert_ok");

    LLVMBuildCondBr(mod->builder, cmp, ok_bb, fail_bb);

    // Fail: print message and exit(1)
    LLVMPositionBuilderAtEnd(mod->builder, fail_bb);
    if (msg) {
        LLVMValueRef fail_fmt = LLVMBuildGlobalStringPtr(mod->builder, "Assertion failed: %s\n", "assert_fmt");
        LLVMValueRef args[] = { fail_fmt, msg };
        LLVMBuildCall2(mod->builder,
            LLVMFunctionType(LLVMInt32TypeInContext(mod->ctx),
                (LLVMTypeRef[]){ LLVMPointerTypeInContext(mod->ctx, 0) }, 1, 1),
            mod->fn_printf, args, 2, "");
    } else {
        LLVMValueRef fail_msg = LLVMBuildGlobalStringPtr(mod->builder, "Assertion failed\n", "assert_msg");
        LLVMValueRef args[] = { mod->fmt_str, fail_msg };
        LLVMBuildCall2(mod->builder,
            LLVMFunctionType(LLVMInt32TypeInContext(mod->ctx),
                (LLVMTypeRef[]){ LLVMPointerTypeInContext(mod->ctx, 0) }, 1, 1),
            mod->fn_printf, args, 2, "");
    }
    LLVMBuildCall2(mod->builder,
        LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx),
            (LLVMTypeRef[]){ LLVMInt32TypeInContext(mod->ctx) }, 1, 0),
        mod->fn_exit, (LLVMValueRef[]){ LLVMConstInt(LLVMInt32TypeInContext(mod->ctx), 1, 0) }, 1, "");
    LLVMBuildUnreachable(mod->builder);

    // OK: continue
    LLVMAppendExistingBasicBlock(mod->current_func, ok_bb);
    LLVMPositionBuilderAtEnd(mod->builder, ok_bb);
}

// ---- Main statement dispatcher ----
static void compile_statement(SevenModule *mod) {
    skip_newlines(mod);
    Token *t = lexer_peek(mod->lex);

    switch (t->type) {
        case TOK_SHOW:    compile_show(mod); break;
        case TOK_IF:      compile_if(mod); break;
        case TOK_WHILE:   compile_while(mod); break;
        case TOK_REPEAT:  compile_repeat(mod); break;
        case TOK_FUNC:    compile_func_def(mod); break;
        case TOK_ASSERT:  compile_assert(mod); break;
        case TOK_RESULT:
        case TOK_IDENT:   compile_assignment(mod); break;
        case TOK_EOF:     break;
        default:
            fprintf(stderr, "%s:%d: warning: skipping token %s\n",
                    mod->lex->filename, t->line, token_type_name(t->type));
            lexer_next(mod->lex);
            break;
    }
}

// ---- Top-level compile ----
int seven_codegen_compile(SevenModule *mod, Lexer *lex) {
    mod->lex = lex;

    // Create main function
    LLVMTypeRef main_type = LLVMFunctionType(
        LLVMInt32TypeInContext(mod->ctx), NULL, 0, 0);
    mod->current_func = LLVMAddFunction(mod->module, "main", main_type);

    LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(
        mod->ctx, mod->current_func, "entry");
    LLVMPositionBuilderAtEnd(mod->builder, entry);

    // Declare external functions (printf, exit, etc.)
    declare_externals(mod);

    // Compile all statements
    skip_newlines(mod);
    while (lexer_peek(mod->lex)->type != TOK_EOF) {
        compile_statement(mod);
        skip_newlines(mod);
    }

    // Return 0 from main
    if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(mod->builder))) {
        LLVMBuildRet(mod->builder, LLVMConstInt(LLVMInt32TypeInContext(mod->ctx), 0, 0));
    }

    // Verify module
    char *error = NULL;
    if (LLVMVerifyModule(mod->module, LLVMReturnStatusAction, &error)) {
        fprintf(stderr, "LLVM verify error: %s\n", error);
        LLVMDisposeMessage(error);
        return 0;
    }
    LLVMDisposeMessage(error);

    return 1;
}

void seven_codegen_dump_ir(SevenModule *mod) {
    char *ir = LLVMPrintModuleToString(mod->module);
    printf("%s", ir);
    LLVMDisposeMessage(ir);
}

int seven_codegen_emit(SevenModule *mod, const char *output, int run_after) {
    // Initialize targets
    LLVMInitializeAllTargetInfos();
    LLVMInitializeAllTargets();
    LLVMInitializeAllTargetMCs();
    LLVMInitializeAllAsmParsers();
    LLVMInitializeAllAsmPrinters();

    const char *triple = mod->target_triple;
    if (!triple) triple = LLVMGetDefaultTargetTriple();

    LLVMSetTarget(mod->module, triple);

    char *error = NULL;
    LLVMTargetRef target;
    if (LLVMGetTargetFromTriple(triple, &target, &error)) {
        fprintf(stderr, "error: %s\n", error);
        LLVMDisposeMessage(error);
        return 0;
    }

    LLVMTargetMachineRef machine = LLVMCreateTargetMachine(
        target, triple, "generic", "",
        LLVMCodeGenLevelAggressive,
        LLVMRelocPIC,
        LLVMCodeModelDefault);

    // Emit object file
    char obj_path[512];
    snprintf(obj_path, sizeof(obj_path), "%s.o", output);

    if (LLVMTargetMachineEmitToFile(machine, mod->module, obj_path,
                                     LLVMObjectFile, &error)) {
        fprintf(stderr, "error: %s\n", error);
        LLVMDisposeMessage(error);
        LLVMDisposeTargetMachine(machine);
        return 0;
    }

    // Link with clang
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "clang-21 %s -o %s -lm 2>&1", obj_path, output);
    int ret = system(cmd);

    // Clean up object file
    remove(obj_path);

    if (ret != 0) {
        fprintf(stderr, "error: linking failed\n");
        LLVMDisposeTargetMachine(machine);
        return 0;
    }

    fprintf(stderr, "Compiled: %s\n", output);

    // Run if requested
    if (run_after) {
        char run_cmd[512];
        snprintf(run_cmd, sizeof(run_cmd), "./%s", output);
        ret = system(run_cmd);
        remove(output); // cleanup
        LLVMDisposeTargetMachine(machine);
        return (ret == 0);
    }

    LLVMDisposeTargetMachine(machine);
    return 1;
}

void seven_codegen_free(SevenModule *mod) {
    LLVMDisposeBuilder(mod->builder);
    LLVMDisposeModule(mod->module);
    LLVMContextDispose(mod->ctx);

    for (int i = 0; i < mod->var_count; i++)
        free(mod->vars[i].name);
    for (int i = 0; i < mod->func_count; i++)
        free(mod->funcs[i].name);
}

// ============================================================
// SEVEN Language — LLVM Code Generator Implementation
// Phase 13: Full LLVM backend with strings, arrays, stdlib
// ============================================================

#include "llvm_codegen.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <io.h>
    #define PATH_SEP '\\'
#else
    #include <unistd.h>
    #define PATH_SEP '/'
#endif

// Runtime function refs (declared in declare_externals)
static LLVMValueRef rt_str_concat, rt_str_len, rt_str_equal;
static LLVMValueRef rt_str_upper, rt_str_lower, rt_str_trim;
static LLVMValueRef rt_str_contains, rt_str_replace, rt_str_substr;
static LLVMValueRef rt_str_find, rt_str_count, rt_str_pad;
static LLVMValueRef rt_str_from_int, rt_str_to_int;
static LLVMValueRef rt_ord, rt_chr, rt_str_char_at;
static LLVMValueRef rt_arr_new, rt_arr_len, rt_arr_push, rt_arr_pop;
static LLVMValueRef rt_arr_get, rt_arr_set, rt_arr_sort, rt_arr_reverse;
static LLVMValueRef rt_arr_join, rt_arr_range, rt_arr_find, rt_arr_unique;
static LLVMValueRef rt_arr_fill, rt_arr_slice, rt_arr_concat;
static LLVMValueRef rt_arr_insert, rt_arr_remove;
static LLVMValueRef rt_pow, rt_clamp, rt_sign, rt_gcd;
static LLVMValueRef rt_sum, rt_avg, rt_abs_val;
static LLVMValueRef rt_hex, rt_bin, rt_bool_fn, rt_number;
static LLVMValueRef rt_file_exists, rt_file_write, rt_file_read;
static LLVMValueRef rt_file_append, rt_file_delete;
static LLVMValueRef rt_time, rt_clock_ns, rt_sleep_fn, rt_env, rt_system_fn;
static LLVMValueRef rt_ask, rt_show_int, rt_show_str;

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
static void compile_each(SevenModule *mod);
static void compile_push(SevenModule *mod);
static void compile_pop(SevenModule *mod);
static void compile_write_file(SevenModule *mod);
static void compile_read_file(SevenModule *mod);
static void compile_delete_file(SevenModule *mod);
static void compile_append_file(SevenModule *mod);
static LLVMValueRef compile_builtin_call(SevenModule *mod, const char *name);
static LLVMValueRef compile_array_literal(SevenModule *mod);

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

// ---- Helpers ----
static LLVMValueRef load_var(SevenModule *mod, VarInfo *v) {
    LLVMValueRef raw = LLVMBuildLoad2(mod->builder, LLVMInt64TypeInContext(mod->ctx), v->alloca, v->name);
    if (v->is_string >= 1)
        return LLVMBuildIntToPtr(mod->builder, raw, LLVMPointerTypeInContext(mod->ctx, 0), "ptr");
    return raw;
}

static LLVMValueRef val_to_ptr(SevenModule *mod, LLVMValueRef val) {
    if (LLVMGetTypeKind(LLVMTypeOf(val)) == LLVMPointerTypeKind) return val;
    return LLVMBuildIntToPtr(mod->builder, val, LLVMPointerTypeInContext(mod->ctx, 0), "toptr");
}

static LLVMValueRef val_to_i64(SevenModule *mod, LLVMValueRef val) {
    if (LLVMGetTypeKind(LLVMTypeOf(val)) == LLVMPointerTypeKind)
        return LLVMBuildPtrToInt(mod->builder, val, LLVMInt64TypeInContext(mod->ctx), "toi64");
    return val;
}

static int is_ptr_val(LLVMValueRef val) {
    return LLVMGetTypeKind(LLVMTypeOf(val)) == LLVMPointerTypeKind;
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

    LLVMTypeRef v = LLVMVoidTypeInContext(mod->ctx);

    // Helper to declare a function
    #define FN(var, cname, ret, n, ...) { \
        LLVMTypeRef a[] = { __VA_ARGS__ }; \
        var = LLVMAddFunction(mod->module, cname, LLVMFunctionType(ret, a, n, 0)); \
    }
    #define FN0(var, cname, ret) \
        var = LLVMAddFunction(mod->module, cname, LLVMFunctionType(ret, NULL, 0, 0));

    // String
    FN(rt_str_concat, "seven_str_concat", i8ptr, 2, i8ptr, i8ptr);
    FN(rt_str_len, "seven_str_len", i64, 1, i8ptr);
    FN(rt_str_equal, "seven_str_equal", i64, 2, i8ptr, i8ptr);
    FN(rt_str_upper, "seven_str_upper", i8ptr, 1, i8ptr);
    FN(rt_str_lower, "seven_str_lower", i8ptr, 1, i8ptr);
    FN(rt_str_trim, "seven_str_trim", i8ptr, 1, i8ptr);
    FN(rt_str_contains, "seven_str_contains", i64, 2, i8ptr, i8ptr);
    FN(rt_str_replace, "seven_str_replace", i8ptr, 3, i8ptr, i8ptr, i8ptr);
    FN(rt_str_substr, "seven_str_substr", i8ptr, 3, i8ptr, i64, i64);
    FN(rt_str_find, "seven_str_find", i64, 2, i8ptr, i8ptr);
    FN(rt_str_count, "seven_str_count", i64, 2, i8ptr, i8ptr);
    FN(rt_str_pad, "seven_str_pad", i8ptr, 3, i8ptr, i64, i8ptr);
    FN(rt_str_from_int, "seven_str_from_int", i8ptr, 1, i64);
    FN(rt_str_to_int, "seven_str_to_int", i64, 1, i8ptr);
    FN(rt_ord, "seven_ord", i64, 1, i8ptr);
    FN(rt_chr, "seven_chr", i8ptr, 1, i64);
    FN(rt_str_char_at, "seven_str_char_at", i8ptr, 2, i8ptr, i64);

    // Array
    FN0(rt_arr_new, "seven_arr_new", i8ptr);
    FN(rt_arr_len, "seven_arr_len", i64, 1, i8ptr);
    FN(rt_arr_push, "seven_arr_push", v, 2, i8ptr, i64);
    FN(rt_arr_pop, "seven_arr_pop", i64, 1, i8ptr);
    FN(rt_arr_get, "seven_arr_get", i64, 2, i8ptr, i64);
    FN(rt_arr_set, "seven_arr_set", v, 3, i8ptr, i64, i64);
    FN(rt_arr_sort, "seven_arr_sort", v, 1, i8ptr);
    FN(rt_arr_reverse, "seven_arr_reverse", v, 1, i8ptr);
    FN(rt_arr_join, "seven_arr_join", i8ptr, 2, i8ptr, i8ptr);
    FN(rt_arr_range, "seven_arr_range", i8ptr, 3, i64, i64, i64);
    FN(rt_arr_find, "seven_arr_find", i64, 2, i8ptr, i64);
    FN(rt_arr_unique, "seven_arr_unique", i8ptr, 1, i8ptr);
    FN(rt_arr_fill, "seven_arr_fill", i8ptr, 2, i64, i64);
    FN(rt_arr_slice, "seven_arr_slice", i8ptr, 3, i8ptr, i64, i64);
    FN(rt_arr_concat, "seven_arr_concat", i8ptr, 2, i8ptr, i8ptr);
    FN(rt_arr_insert, "seven_arr_insert", v, 3, i8ptr, i64, i64);
    FN(rt_arr_remove, "seven_arr_remove", v, 2, i8ptr, i64);

    // Math
    FN(rt_pow, "seven_pow", i64, 2, i64, i64);
    FN(rt_clamp, "seven_clamp", i64, 3, i64, i64, i64);
    FN(rt_sign, "seven_sign", i64, 1, i64);
    FN(rt_gcd, "seven_gcd", i64, 2, i64, i64);
    FN(rt_sum, "seven_sum", i64, 1, i8ptr);
    FN(rt_avg, "seven_avg", i64, 1, i8ptr);
    FN(rt_abs_val, "seven_abs_val", i64, 1, i64);

    // Conversion
    FN(rt_hex, "seven_hex", i8ptr, 1, i64);
    FN(rt_bin, "seven_bin", i8ptr, 1, i64);
    FN(rt_bool_fn, "seven_bool", i64, 1, i64);
    FN(rt_number, "seven_number", i64, 1, i8ptr);

    // File I/O
    FN(rt_file_exists, "seven_file_exists", i64, 1, i8ptr);
    FN(rt_file_write, "seven_file_write", v, 2, i8ptr, i8ptr);
    FN(rt_file_read, "seven_file_read", i8ptr, 1, i8ptr);
    FN(rt_file_append, "seven_file_append", v, 2, i8ptr, i8ptr);
    FN(rt_file_delete, "seven_file_delete", v, 1, i8ptr);

    // OS
    FN0(rt_time, "seven_time", i64);
    FN0(rt_clock_ns, "seven_clock_ns", i64);
    FN(rt_sleep_fn, "seven_sleep", v, 1, i64);
    FN(rt_env, "seven_env", i8ptr, 1, i8ptr);
    FN(rt_system_fn, "seven_system", i64, 1, i8ptr);

    // I/O
    FN(rt_ask, "seven_ask", i8ptr, 1, i8ptr);
    FN(rt_show_int, "seven_show_int", v, 1, i64);
    FN(rt_show_str, "seven_show_str", v, 1, i8ptr);

    #undef FN
    #undef FN0
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
                // Try builtin first
                LLVMValueRef bv = compile_builtin_call(mod, name);
                if (bv) return bv;

                // User-defined function
                compile_func_call(mod, name);
                LLVMBasicBlockRef bb = LLVMGetInsertBlock(mod->builder);
                LLVMValueRef last = LLVMGetLastInstruction(bb);
                return last;
            }

            // Check for method call: ident.method(args)
            if (lexer_peek(mod->lex)->type == TOK_DOT) {
                VarInfo *v = find_var(mod, name);
                if (!v) {
                    fprintf(stderr, "error: undefined variable '%s'\n", name);
                    return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
                }
                LLVMValueRef obj = load_var(mod, v);
                lexer_next(mod->lex); // skip .
                Token *method = lexer_expect(mod->lex, TOK_IDENT);
                const char *mname = method->value;
                lexer_expect(mod->lex, TOK_LPAREN);

                // String methods
                if (strcmp(mname, "len") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    if (v->is_string == 2) {
                        LLVMValueRef args[] = { obj };
                        return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMInt64TypeInContext(mod->ctx), (LLVMTypeRef[]){LLVMPointerTypeInContext(mod->ctx,0)}, 1, 0), rt_arr_len, args, 1, "len");
                    } else {
                        LLVMValueRef args[] = { obj };
                        return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMInt64TypeInContext(mod->ctx), (LLVMTypeRef[]){LLVMPointerTypeInContext(mod->ctx,0)}, 1, 0), rt_str_len, args, 1, "len");
                    }
                } else if (strcmp(mname, "upper") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMValueRef args[] = { obj };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMPointerTypeInContext(mod->ctx,0), (LLVMTypeRef[]){LLVMPointerTypeInContext(mod->ctx,0)}, 1, 0), rt_str_upper, args, 1, "upper");
                } else if (strcmp(mname, "lower") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMValueRef args[] = { obj };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMPointerTypeInContext(mod->ctx,0), (LLVMTypeRef[]){LLVMPointerTypeInContext(mod->ctx,0)}, 1, 0), rt_str_lower, args, 1, "lower");
                } else if (strcmp(mname, "trim") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMValueRef args[] = { obj };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMPointerTypeInContext(mod->ctx,0), (LLVMTypeRef[]){LLVMPointerTypeInContext(mod->ctx,0)}, 1, 0), rt_str_trim, args, 1, "trim");
                } else if (strcmp(mname, "contains") == 0) {
                    LLVMValueRef arg = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj, arg };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMInt64TypeInContext(mod->ctx), (LLVMTypeRef[]){pt, pt}, 2, 0), rt_str_contains, args, 2, "contains");
                } else if (strcmp(mname, "replace") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_COMMA);
                    LLVMValueRef a2 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj, a1, a2 };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt, pt, pt}, 3, 0), rt_str_replace, args, 3, "replace");
                } else if (strcmp(mname, "find") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    if (v->is_string == 1) {
                        LLVMValueRef args[] = { obj, a1 };
                        return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMInt64TypeInContext(mod->ctx), (LLVMTypeRef[]){pt, pt}, 2, 0), rt_str_find, args, 2, "find");
                    } else {
                        LLVMValueRef args[] = { obj, val_to_i64(mod, a1) };
                        LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                        return LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, (LLVMTypeRef[]){pt, i64}, 2, 0), rt_arr_find, args, 2, "find");
                    }
                } else if (strcmp(mname, "push") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                    LLVMValueRef args[] = { obj, val_to_i64(mod, a1) };
                    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt, i64}, 2, 0), rt_arr_push, args, 2, "");
                    return obj;
                } else if (strcmp(mname, "pop") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMInt64TypeInContext(mod->ctx), (LLVMTypeRef[]){pt}, 1, 0), rt_arr_pop, args, 1, "pop");
                } else if (strcmp(mname, "sort") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj };
                    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt}, 1, 0), rt_arr_sort, args, 1, "");
                    return obj;
                } else if (strcmp(mname, "reverse") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj };
                    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt}, 1, 0), rt_arr_reverse, args, 1, "");
                    return obj;
                } else if (strcmp(mname, "join") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj, a1 };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt, pt}, 2, 0), rt_arr_join, args, 2, "join");
                } else if (strcmp(mname, "unique") == 0) {
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt}, 1, 0), rt_arr_unique, args, 1, "unique");
                } else if (strcmp(mname, "slice") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_COMMA);
                    LLVMValueRef a2 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                    LLVMValueRef args[] = { obj, val_to_i64(mod, a1), val_to_i64(mod, a2) };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt, i64, i64}, 3, 0), rt_arr_slice, args, 3, "slice");
                } else if (strcmp(mname, "get") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                    LLVMValueRef args[] = { obj, val_to_i64(mod, a1) };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, (LLVMTypeRef[]){pt, i64}, 2, 0), rt_arr_get, args, 2, "get");
                } else if (strcmp(mname, "set") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_COMMA);
                    LLVMValueRef a2 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                    LLVMValueRef args[] = { obj, val_to_i64(mod, a1), val_to_i64(mod, a2) };
                    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt, i64, i64}, 3, 0), rt_arr_set, args, 3, "");
                    return obj;
                } else if (strcmp(mname, "substr") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_COMMA);
                    LLVMValueRef a2 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                    LLVMValueRef args[] = { obj, val_to_i64(mod, a1), val_to_i64(mod, a2) };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt, i64, i64}, 3, 0), rt_str_substr, args, 3, "substr");
                } else if (strcmp(mname, "count") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMValueRef args[] = { obj, a1 };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMInt64TypeInContext(mod->ctx), (LLVMTypeRef[]){pt, pt}, 2, 0), rt_str_count, args, 2, "count");
                } else if (strcmp(mname, "char_at") == 0) {
                    LLVMValueRef a1 = compile_expr(mod);
                    lexer_expect(mod->lex, TOK_RPAREN);
                    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                    LLVMValueRef args[] = { obj, val_to_i64(mod, a1) };
                    return LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt, i64}, 2, 0), rt_str_char_at, args, 2, "char_at");
                } else {
                    fprintf(stderr, "error: unknown method '%s'\n", mname);
                    return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
                }
            }

            // Check for array subscript: ident[expr]
            if (lexer_peek(mod->lex)->type == TOK_LBRACKET) {
                VarInfo *v = find_var(mod, name);
                if (!v) {
                    fprintf(stderr, "error: undefined variable '%s'\n", name);
                    return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
                }
                LLVMValueRef arr = load_var(mod, v);
                lexer_next(mod->lex); // skip [
                LLVMValueRef idx = compile_expr(mod);
                lexer_expect(mod->lex, TOK_RBRACKET);
                LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
                LLVMValueRef args[] = { arr, val_to_i64(mod, idx) };
                return LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, (LLVMTypeRef[]){pt, i64}, 2, 0), rt_arr_get, args, 2, "aget");
            }

            VarInfo *v = find_var(mod, name);
            if (!v) {
                fprintf(stderr, "error: undefined variable '%s'\n", name);
                return LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
            }
            return load_var(mod, v);
        }

        case TOK_LPAREN: {
            lexer_next(mod->lex); // skip (
            LLVMValueRef val = compile_expr(mod);
            lexer_expect(mod->lex, TOK_RPAREN);
            return val;
        }

        case TOK_LBRACKET:
            return compile_array_literal(mod);

        case TOK_ASK: {
            lexer_next(mod->lex);
            lexer_expect(mod->lex, TOK_LPAREN);
            LLVMValueRef prompt = compile_expr(mod);
            lexer_expect(mod->lex, TOK_RPAREN);
            LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
            LLVMValueRef args[] = { prompt };
            return LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt}, 1, 0), rt_ask, args, 1, "ask");
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
            if (is_ptr_val(left) || is_ptr_val(right)) {
                // String concatenation
                LLVMValueRef l = is_ptr_val(left) ? left : LLVMBuildCall2(mod->builder,
                    LLVMFunctionType(LLVMPointerTypeInContext(mod->ctx,0), (LLVMTypeRef[]){LLVMInt64TypeInContext(mod->ctx)}, 1, 0),
                    rt_str_from_int, (LLVMValueRef[]){left}, 1, "itoa");
                LLVMValueRef r = is_ptr_val(right) ? right : LLVMBuildCall2(mod->builder,
                    LLVMFunctionType(LLVMPointerTypeInContext(mod->ctx,0), (LLVMTypeRef[]){LLVMInt64TypeInContext(mod->ctx)}, 1, 0),
                    rt_str_from_int, (LLVMValueRef[]){right}, 1, "itoa");
                LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
                left = LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt, pt}, 2, 0),
                    rt_str_concat, (LLVMValueRef[]){l, r}, 2, "concat");
            } else {
                left = LLVMBuildAdd(mod->builder, left, right, "add");
            }
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
        if ((pred == LLVMIntEQ || pred == LLVMIntNE) && (is_ptr_val(left) || is_ptr_val(right))) {
            LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
            LLVMValueRef args[] = { left, right };
            LLVMValueRef eq = LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMInt64TypeInContext(mod->ctx), (LLVMTypeRef[]){pt, pt}, 2, 0), rt_str_equal, args, 2, "streq");
            if (pred == LLVMIntNE) {
                LLVMValueRef zero = LLVMConstInt(LLVMInt64TypeInContext(mod->ctx), 0, 0);
                LLVMValueRef c = LLVMBuildICmp(mod->builder, LLVMIntEQ, eq, zero, "neq");
                return LLVMBuildZExt(mod->builder, c, LLVMInt64TypeInContext(mod->ctx), "neq_ext");
            }
            return eq;
        }
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

        // Detect array literal for type tracking
        int rhs_is_array = (lexer_peek(mod->lex)->type == TOK_LBRACKET);
        // Detect array-returning builtins
        if (lexer_peek(mod->lex)->type == TOK_IDENT) {
            const char *fn = lexer_peek(mod->lex)->value;
            if (strcmp(fn, "range") == 0 || strcmp(fn, "fill") == 0 ||
                strcmp(fn, "unique") == 0 || strcmp(fn, "sort") == 0)
                rhs_is_array = 1;
        }

        LLVMValueRef val = compile_expr(mod);

        int is_ptr = (LLVMGetTypeKind(LLVMTypeOf(val)) == LLVMPointerTypeKind);
        int vtype = is_ptr ? (rhs_is_array ? 2 : 1) : 0;
        VarInfo *v = create_var(mod, name, vtype);

        if (is_ptr) {
            LLVMValueRef cast = LLVMBuildPtrToInt(mod->builder, val,
                LLVMInt64TypeInContext(mod->ctx), "ptr2int");
            LLVMBuildStore(mod->builder, cast, v->alloca);
            v->is_string = vtype;
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

    // Convert pointer args to i64 (user funcs use i64 for everything)
    for (int i = 0; i < arg_count; i++)
        args[i] = val_to_i64(mod, args[i]);

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

// ---- Builtin function call ----
static LLVMValueRef compile_builtin_call(SevenModule *mod, const char *name) {
    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMTypeRef vt = LLVMVoidTypeInContext(mod->ctx);

    // Helper: parse (arg) or (arg, arg, ...)
    #define PARSE_ARGS_START lexer_next(mod->lex) // skip (
    #define PARSE_ARG compile_expr(mod)
    #define PARSE_COMMA lexer_expect(mod->lex, TOK_COMMA)
    #define PARSE_ARGS_END lexer_expect(mod->lex, TOK_RPAREN)
    #define CALL1(fn, rt, a1t, a1) LLVMBuildCall2(mod->builder, LLVMFunctionType(rt, (LLVMTypeRef[]){a1t}, 1, 0), fn, (LLVMValueRef[]){a1}, 1, "b")
    #define CALL2(fn, rt, a1t, a2t, a1, a2) LLVMBuildCall2(mod->builder, LLVMFunctionType(rt, (LLVMTypeRef[]){a1t, a2t}, 2, 0), fn, (LLVMValueRef[]){a1, a2}, 2, "b")
    #define CALL3(fn, rt, a1t, a2t, a3t, a1, a2, a3) LLVMBuildCall2(mod->builder, LLVMFunctionType(rt, (LLVMTypeRef[]){a1t, a2t, a3t}, 3, 0), fn, (LLVMValueRef[]){a1, a2, a3}, 3, "b")

    // --- String functions ---
    if (strcmp(name, "len") == 0) {
        PARSE_ARGS_START;
        // Check if arg is a variable to determine type
        Token *peek = lexer_peek(mod->lex);
        int arg_is_array = 0;
        if (peek->type == TOK_IDENT) {
            VarInfo *vv = find_var(mod, peek->value);
            if (vv && vv->is_string == 2) arg_is_array = 1;
        } else if (peek->type == TOK_LBRACKET) {
            arg_is_array = 1;
        }
        LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        if (arg_is_array)
            return CALL1(rt_arr_len, i64, pt, is_ptr_val(a) ? a : val_to_ptr(mod, a));
        return CALL1(rt_str_len, i64, pt, a);
    }
    if (strcmp(name, "upper") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_str_upper, pt, pt, a);
    }
    if (strcmp(name, "lower") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_str_lower, pt, pt, a);
    }
    if (strcmp(name, "trim") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_str_trim, pt, pt, a);
    }
    if (strcmp(name, "contains") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        return CALL2(rt_str_contains, i64, pt, pt, a, b);
    }
    if (strcmp(name, "replace") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_COMMA; LLVMValueRef c = PARSE_ARG; PARSE_ARGS_END;
        return CALL3(rt_str_replace, pt, pt, pt, pt, a, b, c);
    }
    if (strcmp(name, "substr") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_COMMA; LLVMValueRef c = PARSE_ARG; PARSE_ARGS_END;
        return CALL3(rt_str_substr, pt, pt, i64, i64, a, val_to_i64(mod, b), val_to_i64(mod, c));
    }
    if (strcmp(name, "str_find") == 0 || strcmp(name, "find") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        if (is_ptr_val(b))
            return CALL2(rt_str_find, i64, pt, pt, a, b);
        return CALL2(rt_arr_find, i64, pt, i64, val_to_ptr(mod, a), val_to_i64(mod, b));
    }
    if (strcmp(name, "count") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        return CALL2(rt_str_count, i64, pt, pt, a, b);
    }
    if (strcmp(name, "pad") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_COMMA; LLVMValueRef c = PARSE_ARG; PARSE_ARGS_END;
        return CALL3(rt_str_pad, pt, pt, i64, pt, a, val_to_i64(mod, b), c);
    }
    if (strcmp(name, "ord") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_ord, i64, pt, a);
    }
    if (strcmp(name, "chr") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_chr, pt, i64, val_to_i64(mod, a));
    }
    if (strcmp(name, "char_at") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        return CALL2(rt_str_char_at, pt, pt, i64, a, val_to_i64(mod, b));
    }
    if (strcmp(name, "str") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_str_from_int, pt, i64, val_to_i64(mod, a));
    }
    if (strcmp(name, "int") == 0 || strcmp(name, "number") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        if (is_ptr_val(a)) return CALL1(rt_number, i64, pt, a);
        return a;
    }

    // --- Math functions ---
    if (strcmp(name, "pow") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        return CALL2(rt_pow, i64, i64, i64, val_to_i64(mod, a), val_to_i64(mod, b));
    }
    if (strcmp(name, "abs") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_abs_val, i64, i64, val_to_i64(mod, a));
    }
    if (strcmp(name, "clamp") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_COMMA; LLVMValueRef c = PARSE_ARG; PARSE_ARGS_END;
        return CALL3(rt_clamp, i64, i64, i64, i64, val_to_i64(mod, a), val_to_i64(mod, b), val_to_i64(mod, c));
    }
    if (strcmp(name, "sign") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_sign, i64, i64, val_to_i64(mod, a));
    }
    if (strcmp(name, "gcd") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        return CALL2(rt_gcd, i64, i64, i64, val_to_i64(mod, a), val_to_i64(mod, b));
    }
    if (strcmp(name, "sum") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_sum, i64, pt, val_to_ptr(mod, a));
    }
    if (strcmp(name, "avg") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_avg, i64, pt, val_to_ptr(mod, a));
    }

    // --- Conversion ---
    if (strcmp(name, "hex") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_hex, pt, i64, val_to_i64(mod, a));
    }
    if (strcmp(name, "bin") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_bin, pt, i64, val_to_i64(mod, a));
    }
    if (strcmp(name, "bool") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_bool_fn, i64, i64, val_to_i64(mod, a));
    }

    // --- Array creation ---
    if (strcmp(name, "range") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG;
        LLVMValueRef c;
        if (lexer_match(mod->lex, TOK_COMMA)) c = PARSE_ARG;
        else c = LLVMConstInt(i64, 1, 0);
        PARSE_ARGS_END;
        return CALL3(rt_arr_range, pt, i64, i64, i64, val_to_i64(mod, a), val_to_i64(mod, b), val_to_i64(mod, c));
    }
    if (strcmp(name, "fill") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        return CALL2(rt_arr_fill, pt, i64, i64, val_to_i64(mod, a), val_to_i64(mod, b));
    }
    if (strcmp(name, "join") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_COMMA; LLVMValueRef b = PARSE_ARG; PARSE_ARGS_END;
        return CALL2(rt_arr_join, pt, pt, pt, val_to_ptr(mod, a), b);
    }

    // --- File I/O as functions ---
    if (strcmp(name, "file_exists") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_file_exists, i64, pt, a);
    }
    if (strcmp(name, "file_read") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_file_read, pt, pt, a);
    }

    // --- OS ---
    if (strcmp(name, "time") == 0) {
        PARSE_ARGS_START; PARSE_ARGS_END;
        return LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, NULL, 0, 0), rt_time, NULL, 0, "time");
    }
    if (strcmp(name, "clock") == 0 || strcmp(name, "clock_ns") == 0) {
        PARSE_ARGS_START; PARSE_ARGS_END;
        return LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, NULL, 0, 0), rt_clock_ns, NULL, 0, "clock");
    }
    if (strcmp(name, "env") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_env, pt, pt, a);
    }
    if (strcmp(name, "system") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_system_fn, i64, pt, a);
    }
    if (strcmp(name, "sleep") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        LLVMBuildCall2(mod->builder, LLVMFunctionType(vt, (LLVMTypeRef[]){i64}, 1, 0), rt_sleep_fn, (LLVMValueRef[]){val_to_i64(mod, a)}, 1, "");
        return LLVMConstInt(i64, 0, 0);
    }
    if (strcmp(name, "ask") == 0) {
        PARSE_ARGS_START; LLVMValueRef a = PARSE_ARG; PARSE_ARGS_END;
        return CALL1(rt_ask, pt, pt, a);
    }

    #undef PARSE_ARGS_START
    #undef PARSE_ARG
    #undef PARSE_COMMA
    #undef PARSE_ARGS_END
    #undef CALL1
    #undef CALL2
    #undef CALL3

    return NULL; // not a builtin
}

// ---- Array literal ----
static LLVMValueRef compile_array_literal(SevenModule *mod) {
    lexer_next(mod->lex); // skip [
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
    LLVMTypeRef vt = LLVMVoidTypeInContext(mod->ctx);

    LLVMValueRef arr = LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, NULL, 0, 0), rt_arr_new, NULL, 0, "arr");

    if (lexer_peek(mod->lex)->type != TOK_RBRACKET) {
        LLVMValueRef elem = compile_expr(mod);
        LLVMValueRef args[] = { arr, val_to_i64(mod, elem) };
        LLVMBuildCall2(mod->builder, LLVMFunctionType(vt, (LLVMTypeRef[]){pt, i64}, 2, 0), rt_arr_push, args, 2, "");

        while (lexer_match(mod->lex, TOK_COMMA)) {
            elem = compile_expr(mod);
            LLVMValueRef args2[] = { arr, val_to_i64(mod, elem) };
            LLVMBuildCall2(mod->builder, LLVMFunctionType(vt, (LLVMTypeRef[]){pt, i64}, 2, 0), rt_arr_push, args2, 2, "");
        }
    }
    lexer_expect(mod->lex, TOK_RBRACKET);
    return arr;
}

// ---- Each/as loop ----
static void compile_each(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'each'
    LLVMValueRef collection = compile_expr(mod);
    lexer_expect(mod->lex, TOK_AS);
    Token *var_tok = lexer_expect(mod->lex, TOK_IDENT);
    const char *var_name = var_tok->value;

    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);

    LLVMValueRef arr_ptr = is_ptr_val(collection) ? collection : val_to_ptr(mod, collection);
    LLVMValueRef arr_len = LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, (LLVMTypeRef[]){pt}, 1, 0), rt_arr_len, (LLVMValueRef[]){arr_ptr}, 1, "alen");

    LLVMValueRef idx = LLVMBuildAlloca(mod->builder, i64, "each_i");
    LLVMBuildStore(mod->builder, LLVMConstInt(i64, 0, 0), idx);

    VarInfo *elem_var = create_var(mod, var_name, 0);

    LLVMBasicBlockRef cond_bb = LLVMAppendBasicBlockInContext(mod->ctx, mod->current_func, "each_cond");
    LLVMBasicBlockRef body_bb = LLVMCreateBasicBlockInContext(mod->ctx, "each_body");
    LLVMBasicBlockRef exit_bb = LLVMCreateBasicBlockInContext(mod->ctx, "each_exit");

    LLVMBuildBr(mod->builder, cond_bb);
    LLVMPositionBuilderAtEnd(mod->builder, cond_bb);

    LLVMValueRef cur_idx = LLVMBuildLoad2(mod->builder, i64, idx, "i");
    LLVMValueRef cmp = LLVMBuildICmp(mod->builder, LLVMIntSLT, cur_idx, arr_len, "each_test");
    LLVMBuildCondBr(mod->builder, cmp, body_bb, exit_bb);

    LLVMAppendExistingBasicBlock(mod->current_func, body_bb);
    LLVMPositionBuilderAtEnd(mod->builder, body_bb);

    // Get current element
    LLVMValueRef cur_i = LLVMBuildLoad2(mod->builder, i64, idx, "ci");
    LLVMValueRef elem = LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, (LLVMTypeRef[]){pt, i64}, 2, 0), rt_arr_get, (LLVMValueRef[]){arr_ptr, cur_i}, 2, "elem");
    LLVMBuildStore(mod->builder, elem, elem_var->alloca);

    skip_newlines(mod);
    while (1) {
        Token *t = lexer_peek(mod->lex);
        if (t->type == TOK_DONE || t->type == TOK_EOF) break;
        compile_statement(mod);
        skip_newlines(mod);
    }
    lexer_expect(mod->lex, TOK_DONE);

    // Increment index
    LLVMValueRef next_i = LLVMBuildLoad2(mod->builder, i64, idx, "ni");
    LLVMValueRef inc = LLVMBuildAdd(mod->builder, next_i, LLVMConstInt(i64, 1, 0), "inc");
    LLVMBuildStore(mod->builder, inc, idx);
    LLVMBuildBr(mod->builder, cond_bb);

    LLVMAppendExistingBasicBlock(mod->current_func, exit_bb);
    LLVMPositionBuilderAtEnd(mod->builder, exit_bb);
}

// ---- Push statement: push arr, value ----
static void compile_push(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'push'
    Token *arr_tok = lexer_expect(mod->lex, TOK_IDENT);
    VarInfo *v = find_var(mod, arr_tok->value);
    if (!v) { fprintf(stderr, "error: undefined '%s'\n", arr_tok->value); return; }
    LLVMValueRef arr = load_var(mod, v);
    lexer_expect(mod->lex, TOK_COMMA);
    LLVMValueRef val = compile_expr(mod);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt, i64}, 2, 0),
        rt_arr_push, (LLVMValueRef[]){arr, val_to_i64(mod, val)}, 2, "");
}

// ---- Pop statement: pop arr ----
static void compile_pop(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'pop'
    Token *arr_tok = lexer_expect(mod->lex, TOK_IDENT);
    VarInfo *v = find_var(mod, arr_tok->value);
    if (!v) { fprintf(stderr, "error: undefined '%s'\n", arr_tok->value); return; }
    LLVMValueRef arr = load_var(mod, v);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMTypeRef i64 = LLVMInt64TypeInContext(mod->ctx);
    LLVMBuildCall2(mod->builder, LLVMFunctionType(i64, (LLVMTypeRef[]){pt}, 1, 0), rt_arr_pop, (LLVMValueRef[]){arr}, 1, "pop");
}

// ---- File I/O statements ----
static void compile_write_file(SevenModule *mod) {
    lexer_next(mod->lex); // skip 'write'
    LLVMValueRef path = compile_expr(mod);
    lexer_expect(mod->lex, TOK_COMMA);
    LLVMValueRef data = compile_expr(mod);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt, pt}, 2, 0),
        rt_file_write, (LLVMValueRef[]){path, data}, 2, "");
}

static void compile_read_file(SevenModule *mod) {
    // 'read' is handled as expression via file_read() builtin
    // As statement: read "path" — just discard result
    lexer_next(mod->lex);
    LLVMValueRef path = compile_expr(mod);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMBuildCall2(mod->builder, LLVMFunctionType(pt, (LLVMTypeRef[]){pt}, 1, 0), rt_file_read, (LLVMValueRef[]){path}, 1, "rd");
}

static void compile_delete_file(SevenModule *mod) {
    lexer_next(mod->lex);
    LLVMValueRef path = compile_expr(mod);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt}, 1, 0),
        rt_file_delete, (LLVMValueRef[]){path}, 1, "");
}

static void compile_append_file(SevenModule *mod) {
    lexer_next(mod->lex);
    LLVMValueRef path = compile_expr(mod);
    lexer_expect(mod->lex, TOK_COMMA);
    LLVMValueRef data = compile_expr(mod);
    LLVMTypeRef pt = LLVMPointerTypeInContext(mod->ctx, 0);
    LLVMBuildCall2(mod->builder, LLVMFunctionType(LLVMVoidTypeInContext(mod->ctx), (LLVMTypeRef[]){pt, pt}, 2, 0),
        rt_file_append, (LLVMValueRef[]){path, data}, 2, "");
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
        case TOK_EACH:    compile_each(mod); break;
        case TOK_FUNC:    compile_func_def(mod); break;
        case TOK_ASSERT:  compile_assert(mod); break;
        case TOK_PUSH:    compile_push(mod); break;
        case TOK_POP:     compile_pop(mod); break;
        case TOK_WRITE:   compile_write_file(mod); break;
        case TOK_DELETE:   compile_delete_file(mod); break;
        case TOK_APPEND:   compile_append_file(mod); break;
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

    if (LLVMTargetMachineEmitToFile(machine, mod->module, (char *)obj_path,
                                     LLVMObjectFile, &error)) {
        fprintf(stderr, "error: %s\n", error);
        LLVMDisposeMessage(error);
        LLVMDisposeTargetMachine(machine);
        return 0;
    }

    // Find runtime object next to our executable
    char exe_dir[512] = "";
#ifdef _WIN32
    {
        char exe_path[512];
        DWORD elen = GetModuleFileNameA(NULL, exe_path, sizeof(exe_path));
        if (elen > 0) {
            strncpy(exe_dir, exe_path, sizeof(exe_dir) - 1);
            char *sep = strrchr(exe_dir, '\\');
            if (!sep) sep = strrchr(exe_dir, '/');
            if (sep) *(sep + 1) = '\0';
        }
    }
#else
    {
        ssize_t elen = readlink("/proc/self/exe", exe_dir, sizeof(exe_dir) - 1);
        if (elen > 0) {
            exe_dir[elen] = '\0';
            char *slash = strrchr(exe_dir, '/');
            if (slash) *(slash + 1) = '\0';
        }
    }
#endif

    char rt_obj[512];
#ifdef _WIN32
    snprintf(rt_obj, sizeof(rt_obj), "%sseven_runtime_win.o", exe_dir);
#else
    snprintf(rt_obj, sizeof(rt_obj), "%sseven_runtime.o", exe_dir);
#endif

    // Detect clang binary
    const char *clang_bin = NULL;
#ifdef _WIN32
    if (system("clang --version >NUL 2>&1") == 0)
        clang_bin = "clang";
#else
    if (system("clang-21 --version >/dev/null 2>&1") == 0)
        clang_bin = "clang-21";
    else if (system("clang --version >/dev/null 2>&1") == 0)
        clang_bin = "clang";
#endif

    if (!clang_bin) {
        fprintf(stderr, "error: clang not found. Install LLVM/Clang.\n");
        remove(obj_path);
        LLVMDisposeTargetMachine(machine);
        return 0;
    }

    // Link: clang user.o runtime.o -o output -lm
    char cmd[4096];
#ifdef _WIN32
    {
        // Find MSVC and Windows SDK lib paths for the linker
        char msvc_lib[512] = "";
        char ucrt_lib[512] = "";
        char um_lib[512] = "";

        // Try to find VS install via vswhere
        FILE *vsp = _popen("\"C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe\" -latest -property installationPath 2>NUL", "r");
        char vs_path[512] = "";
        if (vsp) {
            if (fgets(vs_path, sizeof(vs_path), vsp)) {
                // Strip newline
                char *nl = strchr(vs_path, '\r');
                if (nl) *nl = '\0';
                nl = strchr(vs_path, '\n');
                if (nl) *nl = '\0';
            }
            _pclose(vsp);
        }

        // Find MSVC tools version
        if (vs_path[0]) {
            char search_path[512];
            snprintf(search_path, sizeof(search_path), "dir /b \"%s\\VC\\Tools\\MSVC\" 2>NUL", vs_path);
            FILE *dp = _popen(search_path, "r");
            char msvc_ver[64] = "";
            if (dp) {
                char line[64];
                while (fgets(line, sizeof(line), dp)) {
                    char *nl2 = strchr(line, '\r');
                    if (nl2) *nl2 = '\0';
                    nl2 = strchr(line, '\n');
                    if (nl2) *nl2 = '\0';
                    if (line[0]) strncpy(msvc_ver, line, sizeof(msvc_ver) - 1);
                }
                _pclose(dp);
            }
            if (msvc_ver[0])
                snprintf(msvc_lib, sizeof(msvc_lib), "%s\\VC\\Tools\\MSVC\\%s\\lib\\x64", vs_path, msvc_ver);
        }

        // Find Windows SDK version
        FILE *sdkp = _popen("dir /b \"C:\\Program Files (x86)\\Windows Kits\\10\\Lib\" 2>NUL", "r");
        char sdk_ver[64] = "";
        if (sdkp) {
            char line[64];
            while (fgets(line, sizeof(line), sdkp)) {
                char *nl3 = strchr(line, '\r');
                if (nl3) *nl3 = '\0';
                nl3 = strchr(line, '\n');
                if (nl3) *nl3 = '\0';
                if (line[0] == '1' && line[1] == '0')
                    strncpy(sdk_ver, line, sizeof(sdk_ver) - 1);
            }
            _pclose(sdkp);
        }
        if (sdk_ver[0]) {
            snprintf(ucrt_lib, sizeof(ucrt_lib), "C:\\Program Files (x86)\\Windows Kits\\10\\Lib\\%s\\ucrt\\x64", sdk_ver);
            snprintf(um_lib, sizeof(um_lib), "C:\\Program Files (x86)\\Windows Kits\\10\\Lib\\%s\\um\\x64", sdk_ver);
        }

        // Build link command with library paths
        int off = snprintf(cmd, sizeof(cmd), "%s \"%s\" \"%s\" -o \"%s\"",
                           clang_bin, obj_path, rt_obj, output);
        if (msvc_lib[0])
            off += snprintf(cmd + off, sizeof(cmd) - off, " -L\"%s\"", msvc_lib);
        if (ucrt_lib[0])
            off += snprintf(cmd + off, sizeof(cmd) - off, " -L\"%s\"", ucrt_lib);
        if (um_lib[0])
            off += snprintf(cmd + off, sizeof(cmd) - off, " -L\"%s\"", um_lib);
        snprintf(cmd + off, sizeof(cmd) - off, " 2>&1");
    }
#else
    snprintf(cmd, sizeof(cmd), "%s \"%s\" \"%s\" -o \"%s\" -lm 2>&1",
             clang_bin, obj_path, rt_obj, output);
#endif
    int ret = system(cmd);

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
#ifdef _WIN32
        snprintf(run_cmd, sizeof(run_cmd), "\"%s\"", output);
#else
        snprintf(run_cmd, sizeof(run_cmd), "\"./%s\"", output);
#endif
        ret = system(run_cmd);
        remove(output);
#ifdef _WIN32
        // Also clean up .pdb on Windows
        char pdb_path[512];
        snprintf(pdb_path, sizeof(pdb_path), "%s", output);
        char *dot = strrchr(pdb_path, '.');
        if (dot) strcpy(dot, ".pdb");
        else strcat(pdb_path, ".pdb");
        remove(pdb_path);
#endif
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

// ============================================================
// SEVEN Language — LLVM Code Generator
// Translates token stream → LLVM IR → native binary
// ============================================================
#ifndef SEVEN_CODEGEN_H
#define SEVEN_CODEGEN_H

#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/BitWriter.h>
#include "llvm_lexer.h"

#define MAX_VARS 1024
#define MAX_FUNCS 256
#define MAX_STRINGS 4096

typedef struct {
    char *name;
    LLVMValueRef alloca;   // stack slot
    int is_string;         // 0=int, 1=string, 2=array
} VarInfo;

typedef struct {
    char *name;
    LLVMValueRef func;
    int param_count;
} FuncInfo;

typedef struct {
    // LLVM core
    LLVMContextRef ctx;
    LLVMModuleRef module;
    LLVMBuilderRef builder;

    // Current function being compiled
    LLVMValueRef current_func;

    // Variables
    VarInfo vars[MAX_VARS];
    int var_count;

    // Functions
    FuncInfo funcs[MAX_FUNCS];
    int func_count;

    // String constants
    LLVMValueRef strings[MAX_STRINGS];
    int string_count;

    // printf function ref
    LLVMValueRef fn_printf;
    LLVMValueRef fn_puts;
    LLVMValueRef fn_scanf;
    LLVMValueRef fn_sprintf;
    LLVMValueRef fn_strcmp;
    LLVMValueRef fn_strlen;
    LLVMValueRef fn_malloc;
    LLVMValueRef fn_free;
    LLVMValueRef fn_exit;
    LLVMValueRef fn_snprintf;

    // Format strings
    LLVMValueRef fmt_int;      // "%lld"
    LLVMValueRef fmt_str;      // "%s"
    LLVMValueRef fmt_newline;  // "\n"
    LLVMValueRef fmt_int_nl;   // "%lld\n"
    LLVMValueRef fmt_str_nl;   // "%s\n"

    // Target
    const char *target_triple;

    // Lexer ref
    Lexer *lex;
} SevenModule;

// Initialize the codegen module
void seven_codegen_init(SevenModule *mod, const char *name);

// Set target triple for cross-compilation
void seven_codegen_set_target(SevenModule *mod, const char *triple);

// Compile token stream to LLVM IR
int seven_codegen_compile(SevenModule *mod, Lexer *lex);

// Dump LLVM IR to stdout
void seven_codegen_dump_ir(SevenModule *mod);

// Emit object file and link to executable
int seven_codegen_emit(SevenModule *mod, const char *output, int run_after);

// Free resources
void seven_codegen_free(SevenModule *mod);

#endif

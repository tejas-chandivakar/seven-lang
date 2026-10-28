// ============================================================
// SEVEN Language — LLVM Backend Entry Point
// Reads .seven source, lexes it, generates LLVM IR, compiles
//
// Usage: seven-llvm build <file.seven> [-o output] [--emit-ir]
//        seven-llvm run  <file.seven>
// ============================================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <process.h>
#else
    #include <unistd.h>
#endif
#include "llvm_lexer.h"
#include "llvm_codegen.h"

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s'\n", path);
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(len + 1);
    fread(buf, 1, len, f);
    buf[len] = '\0';
    fclose(f);
    return buf;
}

static void print_usage(void) {
    fprintf(stderr,
        "SEVEN Language v1.4 — Write Simple. Run Native.\n"
        "\n"
        "Usage: seven <command> <file.seven> [options]\n"
        "\n"
        "Commands:\n"
        "  build <file>   Compile to native executable (LLVM)\n"
        "  run   <file>   Compile and run immediately\n"
        "\n"
        "Options:\n"
        "  -o <output>    Output file name\n"
        "  --emit-ir      Print LLVM IR to stdout\n"
        "  --target <t>   Target triple (e.g. x86_64-pc-windows-msvc)\n"
        "  --asm          Use NASM x86-64 backend instead of LLVM\n"
        "\n");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    // Check for --asm flag: delegate to NASM binary
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--asm") == 0) {
            char exe_dir[512] = "";
#ifdef _WIN32
            {
                char buf[512];
                DWORD elen = GetModuleFileNameA(NULL, buf, sizeof(buf));
                if (elen > 0) {
                    strncpy(exe_dir, buf, sizeof(exe_dir) - 1);
                    char *sep = strrchr(exe_dir, '\\');
                    if (!sep) sep = strrchr(exe_dir, '/');
                    if (sep) *(sep + 1) = '\0';
                }
            }
            char asm_bin[512];
            snprintf(asm_bin, sizeof(asm_bin), "%sseven-asm.exe", exe_dir);
#else
            {
                ssize_t elen = readlink("/proc/self/exe", exe_dir, sizeof(exe_dir) - 1);
                if (elen > 0) {
                    exe_dir[elen] = '\0';
                    char *slash = strrchr(exe_dir, '/');
                    if (slash) *(slash + 1) = '\0';
                }
            }
            char asm_bin[512];
            snprintf(asm_bin, sizeof(asm_bin), "%sseven-asm", exe_dir);
#endif
            // Remove --asm from args
            char *new_argv[64];
            int j = 0;
            new_argv[j++] = asm_bin;
            for (int k = 1; k < argc && j < 63; k++) {
                if (strcmp(argv[k], "--asm") != 0)
                    new_argv[j++] = argv[k];
            }
            new_argv[j] = NULL;
#ifdef _WIN32
            int ret = (int)_spawnv(_P_WAIT, asm_bin, (const char *const *)new_argv);
            return ret;
#else
            execv(asm_bin, new_argv);
#endif
            fprintf(stderr, "error: NASM backend not found at %s\n", asm_bin);
            return 1;
        }
    }

    // Version / help
    if (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0) {
        printf("SEVEN v1.4 (LLVM backend)\n");
        return 0;
    }
    if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        print_usage();
        return 0;
    }

    if (argc < 3) {
        print_usage();
        return 1;
    }

    const char *cmd = argv[1];
    const char *input = argv[2];
    const char *output = NULL;
    const char *target = NULL;
    int emit_ir = 0;
    int run_mode = 0;

    if (strcmp(cmd, "run") == 0) {
        run_mode = 1;
    } else if (strcmp(cmd, "build") != 0) {
        fprintf(stderr, "error: unknown command '%s'\n", cmd);
        print_usage();
        return 1;
    }

    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            output = argv[++i];
        } else if (strcmp(argv[i], "--emit-ir") == 0) {
            emit_ir = 1;
        } else if (strcmp(argv[i], "--target") == 0 && i + 1 < argc) {
            target = argv[++i];
        }
    }

    // Default output name: strip extension, add .exe on Windows or Windows target
    char default_output[256];
    if (!output) {
        strncpy(default_output, input, sizeof(default_output) - 5);
        char *dot = strrchr(default_output, '.');
        if (dot) *dot = '\0';
#ifdef _WIN32
        strcat(default_output, ".exe");
#else
        if (target && strstr(target, "windows")) {
            strcat(default_output, ".exe");
        }
#endif
        output = default_output;
    }

    char *source = read_file(input);
    if (!source) return 1;

    // Lex
    Lexer lex;
    lexer_init(&lex, source, input);
    lexer_tokenize(&lex);

    // Codegen → LLVM IR
    SevenModule mod;
    seven_codegen_init(&mod, input);

    if (target) {
        seven_codegen_set_target(&mod, target);
    }

    int ok = seven_codegen_compile(&mod, &lex);
    if (!ok) {
        fprintf(stderr, "error: compilation failed\n");
        seven_codegen_free(&mod);
        lexer_free(&lex);
        free(source);
        return 1;
    }

    if (emit_ir) {
        seven_codegen_dump_ir(&mod);
    }

    // Write object file + link
    ok = seven_codegen_emit(&mod, output, run_mode);

    seven_codegen_free(&mod);
    lexer_free(&lex);
    free(source);

    return ok ? 0 : 1;
}
